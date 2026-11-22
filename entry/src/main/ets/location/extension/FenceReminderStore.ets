import { Reminder } from '../../model/Reminder';

/**
 * The slice of the persistent reminder repository the fence extension needs.
 *
 * Contract with the persistence owner: reads must return the same shape the UI process stores, and
 * save() must be durable before it resolves. Ownership stays with the repository team; this module
 * only consumes it, so the extension honours the V1 rule "state updates go through the persistent
 * repository, never a private copy".
 */
export interface FenceReminderStore {
  findById(id: string): Promise<Reminder | undefined>;
  save(reminder: Reminder): Promise<void>;
}

export const FENCE_REMINDER_STORE_UNAVAILABLE: string = 'FENCE_REMINDER_STORE_UNAVAILABLE';
