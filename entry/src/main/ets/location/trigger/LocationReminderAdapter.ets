import { Reminder } from '../../model/Reminder';
import { LocationTriggerMode, ReminderStatus, TriggerType } from '../../model/ReminderEnums';
import { LocationTriggerPort } from '../../reminder/contract/LocationTriggerPort';
import { TriggerEventSink } from '../../reminder/contract/TriggerEventSink';
import { TriggerCondition, TriggerConditionEvent } from '../../reminder/contract/TriggerConditionEvent';
import { distanceMeters, isWithinRadius } from '../geometry/LocationGeometry';
import { LocationPlatform } from '../platform/LocationPlatform';
import { SceneCatalog } from '../scene/SceneCatalog';

class Registration {
  reminderId: string;
  sceneId: string;
  fenceId?: number;
  active: boolean = false;
  pending?: TriggerConditionEvent;
  delivery?: Promise<void>;
  timer?: number;
  waitAttempts: number = 0;
  expected: Reminder;

  constructor(expected: Reminder, sceneId: string) {
    this.reminderId = expected.id;
    this.sceneId = sceneId;
    this.expected = expected;
  }
}

export function matchesLocationRegistration(current: Reminder | undefined, expected: Reminder): boolean {
  return current !== undefined && current.status === ReminderStatus.ACTIVE && current.id === expected.id &&
    current.content === expected.content && current.triggerType === expected.triggerType &&
    current.triggerTime === expected.triggerTime && current.sceneId === expected.sceneId &&
    current.sceneName === expected.sceneName && current.locationTriggerMode === expected.locationTriggerMode &&
    current.source === expected.source && current.createdAt === expected.createdAt;
}

function snapshot(reminder: Reminder): Reminder {
  return { id: reminder.id, content: reminder.content, triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime, sceneId: reminder.sceneId, sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode, status: reminder.status, source: reminder.source,
    createdAt: reminder.createdAt, triggeredAt: reminder.triggeredAt, completedAt: reminder.completedAt };
}

/**
 * No resources are acquired at construction. start() is an integration lifecycle operation.
 * register() also starts lazily, because the user can grant location permission after app launch.
 */
export class LocationReminderAdapter implements LocationTriggerPort {
  private catalog: SceneCatalog;
  private platform: LocationPlatform;
  private sink: TriggerEventSink;
  private now: () => number;
  private onError: (code: string) => void;
  private isReminderReady: (expected: Reminder) => Promise<boolean>;
  private started: boolean = false;
  private gate: Promise<void> = Promise.resolve();
  private registrations: Map<string, Registration> = new Map<string, Registration>();

  constructor(catalog: SceneCatalog, platform: LocationPlatform, sink: TriggerEventSink,
    now: () => number, onError: (code: string) => void,
    isReminderReady: (expected: Reminder) => Promise<boolean>) {
    this.catalog = catalog;
    this.platform = platform;
    this.sink = sink;
    this.now = now;
    this.onError = onError;
    this.isReminderReady = isReminderReady;
  }

  private async exclusive(action: () => Promise<void>): Promise<void> {
    const previous = this.gate;
    let release: () => void = () => {};
    this.gate = new Promise<void>((resolve: () => void) => { release = resolve; });
    await previous;
    try { await action(); } finally { release(); }
  }

  private async ensureStarted(): Promise<void> {
    await this.platform.checkReady();
    this.started = true;
  }

  async start(): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      await this.ensureStarted();
    });
  }

  async stop(): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      this.started = false;
      let failed: boolean = false;
      const ids = Array.from(this.registrations.keys());
      for (const id of ids) {
        try { await this.remove(id); } catch (_) { failed = true; }
      }
      if (failed) { throw new Error('LOCATION_STOP_CLEANUP_FAILED'); }
    });
  }

  async register(reminder: Reminder): Promise<void> {
    // Snapshot the shared model before the first await.
    const id = reminder.id;
    const sceneId = reminder.sceneId;
    const expected = snapshot(reminder);
    if (id.trim().length === 0 || sceneId === undefined || sceneId.trim().length === 0 ||
      (reminder.triggerType !== TriggerType.LOCATION && reminder.triggerType !== TriggerType.BOTH) ||
      reminder.status !== ReminderStatus.ACTIVE ||
      (reminder.locationTriggerMode !== undefined && reminder.locationTriggerMode !== LocationTriggerMode.ENTER)) {
      throw new Error('LOCATION_INVALID_REGISTRATION');
    }
    await this.exclusive(async (): Promise<void> => {
      // Permission is granted at runtime, so the composition root cannot reliably pre-start us.
      // Lazily start inside the gate: calling start() here would await our own gate forever.
      if (!this.started) { await this.ensureStarted(); }
      else { await this.platform.checkReady(); }
      const existing = this.registrations.get(id);
      if (existing !== undefined) {
        if (existing.sceneId !== sceneId) { throw new Error('LOCATION_UNREGISTER_BEFORE_REPLACE'); }
        if (!matchesLocationRegistration(existing.expected, expected)) {
          throw new Error('LOCATION_UNREGISTER_BEFORE_REPLACE');
        }
        existing.active = true;
        return;
      }
      const scene = await this.catalog.acquire(sceneId, id);
      const registration = new Registration(expected, sceneId);
      this.registrations.set(id, registration);
      try {
        registration.fenceId = await this.platform.addFence(scene,
          (): void => { this.enter(registration); },
          (code: string): void => { this.onError(code); });
        registration.active = true;
        // A system callback may have arrived while addFence was in progress.
        if (registration.pending !== undefined) { this.scheduleDelivery(registration); }
      } catch (_) {
        this.registrations.delete(id);
        await this.catalog.release(sceneId, id);
        throw new Error('LOCATION_FENCE_REGISTRATION_FAILED');
      }
    });
  }

  async unregister(reminderId: string): Promise<void> {
    await this.exclusive(async (): Promise<void> => { await this.remove(reminderId); });
  }

  private async remove(id: string): Promise<void> {
    const registration = this.registrations.get(id);
    if (registration === undefined) { return; }
    // Suppress callbacks as soon as removal begins, even if the native removal fails.
    registration.active = false;
    registration.pending = undefined;
    if (registration.timer !== undefined) { clearTimeout(registration.timer); registration.timer = undefined; }
    if (registration.fenceId !== undefined) { await this.platform.removeFence(registration.fenceId); }
    this.registrations.delete(id);
    await this.catalog.release(registration.sceneId, id);
  }

  async isInsideScene(sceneId: string): Promise<boolean> {
    if (!this.started) { throw new Error('LOCATION_NOT_STARTED'); }
    const scene = await this.catalog.findById(sceneId);
    if (scene === undefined) { throw new Error('SCENE_NOT_FOUND'); }
    const fix = await this.platform.getCurrentPosition();
    const at = this.now();
    if (!Number.isFinite(at) || at < 0 || !Number.isFinite(fix.occurredAt) || fix.occurredAt < 0 ||
      at - fix.occurredAt > 30000 || fix.occurredAt - at > 5000 ||
      !Number.isFinite(fix.accuracy) || fix.accuracy < 0 || fix.accuracy > scene.radius) {
      throw new Error('LOCATION_FIX_UNUSABLE');
    }
    const distance = distanceMeters(fix.latitude, fix.longitude, scene.latitude, scene.longitude);
    if (Math.abs(distance - scene.radius) < fix.accuracy) {
      throw new Error('LOCATION_FIX_UNCERTAIN');
    }
    return isWithinRadius(fix.latitude, fix.longitude, scene.latitude, scene.longitude, scene.radius);
  }

  private enter(registration: Registration): void {
    if (!this.started || this.registrations.get(registration.reminderId) !== registration) { return; }
    // Inactive records with an assigned fence are cancelled records awaiting cleanup.
    if (!registration.active && registration.fenceId !== undefined) { return; }
    const at = this.now();
    if (!Number.isFinite(at) || at < 0) { this.onError('LOCATION_INVALID_EVENT_CLOCK'); return; }
    registration.pending = { reminderId: registration.reminderId, condition: TriggerCondition.LOCATION,
      satisfied: true, occurredAt: at };
    registration.waitAttempts = 0;
    if (registration.active) { this.scheduleDelivery(registration); }
  }

  private scheduleDelivery(registration: Registration, delay: number = 0): void {
    if (registration.timer !== undefined) { return; }
    registration.timer = setTimeout((): void => {
      registration.timer = undefined;
      this.deliver(registration, true).catch((): void => { this.onError('LOCATION_EVENT_DELIVERY_FAILED'); });
    }, delay);
  }

  private async deliver(registration: Registration, allowWait: boolean): Promise<void> {
    if (!this.started || !registration.active ||
      this.registrations.get(registration.reminderId) !== registration) { return; }
    if (registration.delivery !== undefined) { await registration.delivery; return; }
    // Never hold the mutation gate while invoking the coordinator: it may unregister this reminder.
    const delivery = this.deliverEvent(registration, allowWait);
    registration.delivery = delivery;
    try {
      await delivery;
    } finally { registration.delivery = undefined; }
  }

  private async deliverEvent(registration: Registration, allowWait: boolean): Promise<void> {
    const event = registration.pending;
    if (event === undefined) { return; }
    const ready = await this.isReminderReady(registration.expected);
    if (!this.started || !registration.active ||
      this.registrations.get(registration.reminderId) !== registration) { return; }
    if (!ready) {
      registration.waitAttempts++;
      if (allowWait && registration.waitAttempts <= 50) {
        this.scheduleDelivery(registration, 100);
        return;
      }
      throw new Error('LOCATION_REMINDER_NOT_COMMITTED');
    }
    await this.sink.onConditionChanged(event);
    // Keep an entry that arrived while the previous event or readiness check was in flight.
    if (registration.pending === event) { registration.pending = undefined; }
    else if (registration.active) { this.scheduleDelivery(registration); }
  }

  /** Invoke after a transient failure, for example on foreground/resume. Rejects if any retry fails. */
  async retryPendingEvents(): Promise<void> {
    const records = Array.from(this.registrations.values());
    let failed: boolean = false;
    for (const registration of records) {
      try { await this.deliver(registration, false); }
      catch (_) { failed = true; this.onError('LOCATION_EVENT_DELIVERY_FAILED'); }
    }
    if (failed) { throw new Error('LOCATION_EVENT_RETRY_FAILED'); }
  }
}
