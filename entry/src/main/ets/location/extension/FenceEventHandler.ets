import { Reminder } from '../../model/Reminder';
import { ReminderStatus } from '../../model/ReminderEnums';
import { FenceMapping, FenceRegistry } from '../platform/LocationPlatform';
import { FENCE_HANDLER_NOT_FOUND } from '../repository/FenceRegistryStore';
import { decideFenceDelivery, FenceDeliveryDecision } from './FenceDeliveryPolicy';
import { FenceNotifier } from './FenceNotificationPublisher';
import { FenceReminderStore } from './FenceReminderStore';

export enum FenceEventResult {
  /** Notification published, reminder marked TRIGGERED, fence and mapping cleaned up. */
  DELIVERED = 'DELIVERED',
  /** No mapping for this fence id: the fence is a leftover, nothing to notify. */
  NOT_MAPPED = 'NOT_MAPPED',
  /** Gate said no (not active, wrong trigger type, BOTH time not reached, already delivered). */
  SKIPPED = 'SKIPPED',
  /** The reservation could not be written: fail closed, no notification. */
  REGISTRY_WRITE_FAILED = 'REGISTRY_WRITE_FAILED',
  /** The persistent reminder could not be read. */
  STORE_FAILED = 'STORE_FAILED',
  /** Notification was refused (user disabled notifications, publish error). */
  NOTIFY_FAILED = 'NOTIFY_FAILED',
  /** Notification went out but the reminder could not be marked TRIGGERED. */
  STATE_UPDATE_FAILED = 'STATE_UPDATE_FAILED',
  /** Delivered, but the fence or mapping could not be removed. */
  CLEANUP_FAILED = 'CLEANUP_FAILED'
}

export class FenceEventReport {
  result: FenceEventResult;
  fenceId: number;
  reminderId?: string;
  outcome?: string;

  constructor(result: FenceEventResult, fenceId: number) {
    this.result = result;
    this.fenceId = fenceId;
  }
}

function errorCode(error: Object | undefined): string {
  if (error instanceof Error) { return error.message; }
  return 'FENCE_EVENT_FAILED';
}

/** Snapshot of the reminder after delivery; the UTC clock is the fence event time. */
export function triggeredCopy(reminder: Reminder, at: number): Reminder {
  return { id: reminder.id, content: reminder.content, triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime, sceneId: reminder.sceneId, sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode, status: ReminderStatus.TRIGGERED,
    source: reminder.source, createdAt: reminder.createdAt, triggeredAt: at };
}

/**
 * Runs inside the fence extension process when the system reports a crossing.
 *
 * Order matters: the durable reservation is written before publishing (so a second event, even from
 * a different process, cannot notify twice), then the notification, then the state update, then the
 * cleanup that stops this fence from firing again.
 *
 * All collaborators are injected so the decision path is unit testable without a device.
 */
export class FenceEventHandler {
  private registry: FenceRegistry;
  private store: FenceReminderStore;
  private notifier: FenceNotifier;
  private removeFence: (fenceId: number) => Promise<void>;
  private now: () => number;
  private onError: (code: string) => void;

  constructor(registry: FenceRegistry, store: FenceReminderStore, notifier: FenceNotifier,
    removeFence: (fenceId: number) => Promise<void>, now: () => number, onError: (code: string) => void) {
    this.registry = registry;
    this.store = store;
    this.notifier = notifier;
    this.removeFence = removeFence;
    this.now = now;
    this.onError = onError;
  }

  async handle(geofenceId: number, enter: boolean): Promise<FenceEventReport> {
    const mapping: FenceMapping | undefined = await this.registry.find(geofenceId);
    if (mapping === undefined) {
      return new FenceEventReport(FenceEventResult.NOT_MAPPED, geofenceId);
    }
    let reminder: Reminder | undefined;
    try {
      reminder = await this.store.findById(mapping.reminderId);
    } catch (error) {
      this.onError(errorCode(error));
      const failed = new FenceEventReport(FenceEventResult.STORE_FAILED, geofenceId);
      failed.reminderId = mapping.reminderId;
      return failed;
    }
    const at: number = this.now();
    const decision: FenceDeliveryDecision =
      decideFenceDelivery(reminder, at, mapping.lastDeliveredAt, enter);
    if (!decision.deliver || reminder === undefined) {
      const skipped = new FenceEventReport(FenceEventResult.SKIPPED, geofenceId);
      skipped.reminderId = mapping.reminderId;
      skipped.outcome = decision.outcome;
      return skipped;
    }
    // Fail closed: without a durable reservation a repeated crossing could notify twice.
    try {
      await this.registry.markDelivered(geofenceId, at);
    } catch (error) {
      if (errorCode(error) === FENCE_HANDLER_NOT_FOUND) {
        const skipped = new FenceEventReport(FenceEventResult.SKIPPED, geofenceId);
        skipped.reminderId = mapping.reminderId;
        return skipped;
      }
      this.onError(errorCode(error));
      const failed = new FenceEventReport(FenceEventResult.REGISTRY_WRITE_FAILED, geofenceId);
      failed.reminderId = mapping.reminderId;
      return failed;
    }
    const delivered = new FenceEventReport(FenceEventResult.DELIVERED, geofenceId);
    delivered.reminderId = mapping.reminderId;
    try {
      await this.notifier.publish(mapping.reminderId, reminder.content);
    } catch (error) {
      // Release the reservation so a later crossing may try again.
      try { await this.registry.clearDelivered(geofenceId); }
      catch (_) { /* The reservation expires with the fence during cleanup. */ }
      this.onError(errorCode(error));
      return new FenceEventReport(FenceEventResult.NOTIFY_FAILED, geofenceId);
    }
    let stateUpdated: boolean = true;
    try {
      await this.store.save(triggeredCopy(reminder, at));
    } catch (error) {
      stateUpdated = false;
      this.onError(errorCode(error));
    }
    // Even when the state update failed the fence goes away: the user already has one notification
    // and the main process reconciles an ACTIVE reminder back to a fresh fence.
    let cleaned: boolean = true;
    try { await this.removeFence(geofenceId); }
    catch (_) { cleaned = false; }
    try { await this.registry.removeByReminder(mapping.reminderId); }
    catch (_) { cleaned = false; }
    if (!stateUpdated) { return new FenceEventReport(FenceEventResult.STATE_UPDATE_FAILED, geofenceId); }
    if (!cleaned) { return new FenceEventReport(FenceEventResult.CLEANUP_FAILED, geofenceId); }
    return delivered;
  }
}
