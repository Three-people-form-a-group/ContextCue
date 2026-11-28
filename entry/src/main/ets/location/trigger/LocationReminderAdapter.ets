import { Reminder } from '../../model/Reminder';
import { LocationTriggerMode, ReminderStatus, TriggerType } from '../../model/ReminderEnums';
import { LocationTriggerPort } from '../../reminder/contract/LocationTriggerPort';
import { TriggerEventSink } from '../../reminder/contract/TriggerEventSink';
import { TriggerCondition, TriggerConditionEvent } from '../../reminder/contract/TriggerConditionEvent';
import { distanceMeters, isWithinRadius } from '../geometry/LocationGeometry';
import { FenceDelivery, FenceMapping, FenceRegistry, LocationPlatform } from '../platform/LocationPlatform';
import { SceneCatalog } from '../scene/SceneCatalog';
import { LocationMaintenance } from './LocationMaintenance';

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

/** A reminder that should own a fence: active, location driven, and enter oriented. */
export function isLocationRegistrationCandidate(reminder: Reminder): boolean {
  return reminder.id.trim().length > 0 && reminder.sceneId !== undefined &&
    reminder.sceneId.trim().length > 0 && reminder.status === ReminderStatus.ACTIVE &&
    (reminder.triggerType === TriggerType.LOCATION || reminder.triggerType === TriggerType.BOTH) &&
    (reminder.locationTriggerMode === undefined || reminder.locationTriggerMode === LocationTriggerMode.ENTER);
}

function errorCode(error: Object | undefined): string {
  if (error instanceof Error) { return error.message; }
  return '';
}

/** Registry failures keep their own code so the UI can tell a storage problem from a fence problem. */
function registrationFailure(error: Object | undefined): Error {
  const code = errorCode(error);
  if (code === 'FENCE_REGISTRY_WRITE_FAILED' || code === 'FENCE_REGISTRY_REQUIRES_RECOVERY' ||
    code === 'FENCE_REGISTRY_CORRUPT') {
    return new Error(code);
  }
  return new Error('LOCATION_FENCE_REGISTRATION_FAILED');
}

/**
 * No resources are acquired at construction. start() is an integration lifecycle operation.
 * register() also starts lazily, because the user can grant location permission after app launch.
 *
 * Every fence this adapter creates is paired with a durable mapping in the FenceRegistry, so a
 * later process (or the fence extension) can answer "which reminder owns fence N" and so removal
 * still works after a restart, when the in-memory registrations are empty.
 */
export class LocationReminderAdapter implements LocationTriggerPort, LocationMaintenance {
  private catalog: SceneCatalog;
  private platform: LocationPlatform;
  private sink: TriggerEventSink;
  private now: () => number;
  private onError: (code: string) => void;
  private isReminderReady: (expected: Reminder) => Promise<boolean>;
  private registry: FenceRegistry;
  private delivery?: FenceDelivery;
  private started: boolean = false;
  private gate: Promise<void> = Promise.resolve();
  private registrations: Map<string, Registration> = new Map<string, Registration>();

  constructor(catalog: SceneCatalog, platform: LocationPlatform, sink: TriggerEventSink,
    now: () => number, onError: (code: string) => void,
    isReminderReady: (expected: Reminder) => Promise<boolean>, registry: FenceRegistry,
    delivery?: FenceDelivery) {
    this.catalog = catalog;
    this.platform = platform;
    this.sink = sink;
    this.now = now;
    this.onError = onError;
    this.isReminderReady = isReminderReady;
    this.registry = registry;
    this.delivery = delivery;
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

  private async ensureReady(): Promise<void> {
    // Permission is granted at runtime, so the composition root cannot reliably pre-start us.
    // Lazily start inside the gate: calling start() here would await our own gate forever.
    if (!this.started) { await this.ensureStarted(); }
    else { await this.platform.checkReady(); }
  }

  async start(): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      await this.ensureStarted();
    });
  }

  /**
   * Stops in-process delivery only. Durable mappings and system fences survive on purpose: the
   * fence extension still needs them after this process is gone.
   */
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
    const expected = snapshot(reminder);
    if (!isLocationRegistrationCandidate(expected)) {
      throw new Error('LOCATION_INVALID_REGISTRATION');
    }
    await this.exclusive(async (): Promise<void> => {
      await this.ensureReady();
      await this.registerLocked(expected);
    });
  }

  /** Caller holds the gate. */
  private async registerLocked(expected: Reminder): Promise<void> {
    const id = expected.id;
    const sceneId = expected.sceneId as string;
    const existing = this.registrations.get(id);
    if (existing !== undefined) {
      if (existing.sceneId !== sceneId) { throw new Error('LOCATION_UNREGISTER_BEFORE_REPLACE'); }
      if (!matchesLocationRegistration(existing.expected, expected)) {
        throw new Error('LOCATION_UNREGISTER_BEFORE_REPLACE');
      }
      const mapped = await this.registry.findByReminder(id);
      if (mapped !== undefined || existing.fenceId === undefined) {
        existing.active = true;
        return;
      }
      // The fence record is gone (for example the extension delivered and cleaned it up), so the
      // registration cannot be trusted: drop it and recreate the fence below.
      this.registrations.delete(id);
      await this.catalog.release(existing.sceneId, id);
    }
    const scene = await this.catalog.acquire(sceneId, id);
    const registration = new Registration(expected, sceneId);
    this.registrations.set(id, registration);
    try {
      const fenceId = await this.platform.addFence(scene,
        (): void => { this.enter(registration); },
        (code: string): void => { this.onError(code); },
        this.delivery);
      registration.fenceId = fenceId;
      // The mapping must exist before anyone can learn this fence id, otherwise the extension would
      // meet a fence it cannot resolve and a restart would leak the fence.
      await this.registry.save(fenceId, id);
      registration.active = true;
      // A system callback may have arrived while addFence was in progress.
      if (registration.pending !== undefined) { this.scheduleDelivery(registration); }
    } catch (error) {
      await this.rollbackRegistration(registration, error);
    }
  }

  private async rollbackRegistration(registration: Registration, error: Object): Promise<void> {
    this.registrations.delete(registration.reminderId);
    if (registration.fenceId !== undefined) {
      try { await this.platform.removeFence(registration.fenceId); }
      catch (_) { /* Startup reconciliation deletes an unclaimed fence. */ }
    }
    try { await this.catalog.release(registration.sceneId, registration.reminderId); }
    catch (_) { /* The catalog release failure must not mask the registration failure. */ }
    throw registrationFailure(error);
  }

  async unregister(reminderId: string): Promise<void> {
    await this.exclusive(async (): Promise<void> => { await this.remove(reminderId); });
  }

  /**
   * Caller holds the gate.
   *
   * Mapping first, fence second. The mapping is the only way to find the fence after a restart, so
   * removing it last would leave an unremovable fence when the native removal fails. With this
   * order a failed native removal leaves at most one unclaimed fence, which startup reconciliation
   * deletes, and the failed call can be retried because the fence id is still in memory.
   */
  private async remove(id: string): Promise<void> {
    const registration = this.registrations.get(id);
    if (registration !== undefined) {
      // Suppress callbacks as soon as removal begins, even if the native removal fails.
      registration.active = false;
      registration.pending = undefined;
      if (registration.timer !== undefined) { clearTimeout(registration.timer); registration.timer = undefined; }
    }
    const mapped: FenceMapping | undefined = await this.registry.findByReminder(id);
    let fenceId = registration !== undefined ? registration.fenceId : undefined;
    if (fenceId === undefined && mapped !== undefined) { fenceId = mapped.fenceId; }
    if (registration === undefined && fenceId === undefined) { return; }
    if (mapped !== undefined) { await this.registry.removeByReminder(id); }
    if (fenceId !== undefined) {
      try {
        await this.platform.removeFence(fenceId);
      } catch (error) {
        // Restore the mapping so the fence stays reachable for the next attempt.
        if (mapped !== undefined) {
          try { await this.registry.save(fenceId, id); }
          catch (_) { /* Nothing left to do: startup reconciliation owns an unclaimed fence. */ }
        }
        // ArkTS forbids rethrowing an arbitrary value, so normalize it first.
        throw error instanceof Error ? error : new Error('LOCATION_FENCE_REMOVAL_FAILED');
      }
    }
    if (registration !== undefined) {
      this.registrations.delete(id);
      await this.catalog.release(registration.sceneId, id);
    }
  }

  /**
   * Startup accounting, call once after loading reminders and before serving user actions.
   *
   * The durable registry is the source of truth: fences whose reminder is gone or no longer a
   * location reminder are deleted, and reminders that should have a fence but lost it get one back.
   */
  async reconcile(activeReminders: Reminder[]): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      await this.ensureReady();
      await this.reconcileLocked(activeReminders);
    });
  }

  /** Caller holds the gate. */
  private async reconcileLocked(activeReminders: Reminder[]): Promise<void> {
    const expected: Map<string, Reminder> = new Map<string, Reminder>();
    for (let index = 0; index < activeReminders.length; index++) {
      const reminder = activeReminders[index];
      if (!isLocationRegistrationCandidate(reminder)) { continue; }
      expected.set(reminder.id, snapshot(reminder));
    }
    const mappings = await this.registry.list();
    for (let index = 0; index < mappings.length; index++) {
      const mapping = mappings[index];
      if (expected.has(mapping.reminderId)) { continue; }
      try { await this.platform.removeFence(mapping.fenceId); }
      catch (_) { /* Already removed by the system or by the extension. */ }
      await this.registry.removeByReminder(mapping.reminderId);
      const stale = this.registrations.get(mapping.reminderId);
      if (stale !== undefined) {
        this.registrations.delete(mapping.reminderId);
        try { await this.catalog.release(stale.sceneId, mapping.reminderId); }
        catch (_) { /* The reminder is gone; a leaked scene reference is not worth aborting. */ }
      }
    }
    const ids = Array.from(expected.keys());
    for (const id of ids) {
      const reminder = expected.get(id);
      if (reminder === undefined) { continue; }
      const mapped = await this.registry.findByReminder(id);
      const inMemory = this.registrations.get(id);
      if (mapped !== undefined && (this.delivery !== undefined || inMemory !== undefined)) {
        // The extension delivers, or this process still holds the callback.
        continue;
      }
      if (mapped !== undefined) {
        // In-process delivery needs a live callback, so the fence the dead process left is
        // replaceable only by removing it first.
        try { await this.platform.removeFence(mapped.fenceId); }
        catch (_) { /* Recreate anyway; the old fence dies with the registry entry. */ }
        await this.registry.removeByReminder(id);
      }
      try {
        await this.registerLocked(reminder);
      } catch (error) {
        this.onError(errorCode(error).length > 0 ? errorCode(error) : 'LOCATION_FENCE_REGISTRATION_FAILED');
      }
    }
  }

  /**
   * 用户触发的「重建地点提醒」：先做不依赖定位权限的重置（清空持久映射、移除本应用全部系统围栏），
   * 再按当前提醒重建。reminders.json 不参与，提醒本身不会因此被删除或改写。
   */
  async rebuild(reminders: Reminder[]): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      await this.resetLocked();
      // Re-registration genuinely needs location permission; the reset above already landed.
      await this.ensureReady();
      await this.reconcileLocked(reminders);
    });
  }

  /** 只清空持久映射与系统围栏，不需要定位权限，也不修改提醒数据。 */
  async reset(): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      await this.resetLocked();
    });
  }

  /** Caller holds the gate. */
  private async resetLocked(): Promise<void> {
    // Enumerating fences is best effort: a broken permission state must not block the reset of a
    // corrupt registry, otherwise the user can never recover from it.
    let failure: Error | undefined = undefined;
    let ids: number[] = [];
    try { ids = await this.platform.activeFenceIds(); }
    catch (error) {
      failure = error instanceof Error ? error : new Error('LOCATION_FENCE_ENUMERATION_FAILED');
    }
    // Clear the durable file unconditionally; it is the part that cannot be repaired by retrying.
    await this.registry.clear();
    for (const id of ids) {
      try { await this.platform.removeFence(id); }
      catch (error) {
        // Keep removing the rest; a leftover fence is unclaimed and gets cleaned as an orphan.
        if (failure === undefined) {
          failure = error instanceof Error ? error : new Error('LOCATION_FENCE_REMOVAL_FAILED');
        }
      }
    }
    const records = Array.from(this.registrations.values());
    this.registrations.clear();
    for (const registration of records) {
      registration.active = false;
      registration.pending = undefined;
      if (registration.timer !== undefined) { clearTimeout(registration.timer); registration.timer = undefined; }
      try { await this.catalog.release(registration.sceneId, registration.reminderId); }
      catch (_) { /* Rebuild acquires the scene again; a stale pin does not block it. */ }
    }
    // Surface the first failure after the in-memory state is consistent, so a retry starts clean.
    if (failure !== undefined) { throw failure; }
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
