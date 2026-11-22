import { Reminder } from '../../model/Reminder';
import { LocationTriggerMode, ReminderStatus, TriggerType } from '../../model/ReminderEnums';

/** Why the extension did or did not notify. Every value is safe to log on a user device. */
export enum FenceDeliveryOutcome {
  DELIVER = 'DELIVER',
  NOT_ENTER = 'NOT_ENTER',
  REMINDER_NOT_FOUND = 'REMINDER_NOT_FOUND',
  NOT_ACTIVE = 'NOT_ACTIVE',
  NOT_LOCATION_TRIGGER = 'NOT_LOCATION_TRIGGER',
  EXIT_MODE = 'EXIT_MODE',
  TIME_NOT_REACHED = 'TIME_NOT_REACHED',
  ALREADY_DELIVERED = 'ALREADY_DELIVERED'
}

export class FenceDeliveryDecision {
  deliver: boolean;
  outcome: FenceDeliveryOutcome;

  constructor(deliver: boolean, outcome: FenceDeliveryOutcome) {
    this.deliver = deliver;
    this.outcome = outcome;
  }
}

function skip(outcome: FenceDeliveryOutcome): FenceDeliveryDecision {
  return new FenceDeliveryDecision(false, outcome);
}

/**
 * Pure gate: may the fence extension publish a notification for this crossing?
 *
 * The three V1 hazards of notifying from the extension are handled here and in the handler:
 * duplicates (ALREADY_DELIVERED, backed by a durable reservation), the BOTH-condition bypass
 * (TIME_NOT_REACHED), and state that never updates (the handler writes TRIGGERED through the
 * persistent repository).
 */
export function decideFenceDelivery(reminder: Reminder | undefined, now: number,
  lastDeliveredAt: number | undefined, enter: boolean): FenceDeliveryDecision {
  if (!enter) { return skip(FenceDeliveryOutcome.NOT_ENTER); }
  if (reminder === undefined) { return skip(FenceDeliveryOutcome.REMINDER_NOT_FOUND); }
  if (reminder.status !== ReminderStatus.ACTIVE) { return skip(FenceDeliveryOutcome.NOT_ACTIVE); }
  if (reminder.triggerType === TriggerType.TIME) { return skip(FenceDeliveryOutcome.NOT_LOCATION_TRIGGER); }
  if (reminder.locationTriggerMode !== undefined && reminder.locationTriggerMode !== LocationTriggerMode.ENTER) {
    return skip(FenceDeliveryOutcome.EXIT_MODE);
  }
  if (reminder.triggerType === TriggerType.BOTH) {
    const triggerTime: number | undefined = reminder.triggerTime;
    // BOTH means "time and place". A fence crossing before the time condition holds is not a trigger.
    if (triggerTime === undefined || !Number.isFinite(triggerTime) ||
      !Number.isFinite(now) || now < triggerTime) {
      return skip(FenceDeliveryOutcome.TIME_NOT_REACHED);
    }
  }
  if (lastDeliveredAt !== undefined) { return skip(FenceDeliveryOutcome.ALREADY_DELIVERED); }
  return new FenceDeliveryDecision(true, FenceDeliveryOutcome.DELIVER);
}
