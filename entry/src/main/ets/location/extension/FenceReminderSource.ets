import { Reminder } from '../../model/Reminder';
import { FENCE_REMINDER_STORE_UNAVAILABLE, FenceReminderStore } from './FenceReminderStore';

class UnavailableFenceReminderStore implements FenceReminderStore {
  findById(id: string): Promise<Reminder | undefined> {
    return Promise.reject(new Error(FENCE_REMINDER_STORE_UNAVAILABLE));
  }

  save(reminder: Reminder): Promise<void> {
    return Promise.reject(new Error(FENCE_REMINDER_STORE_UNAVAILABLE));
  }
}

/**
 * Single wiring point between the fence extension and the persistent reminder repository.
 *
 * The repository factory (createPersistentReminderRepository(baseDir), JSON atomic write, shared
 * sandbox path for both processes) is owned by the reminder persistence work and has not landed yet.
 * Until it does, the extension cannot read or write reminders; it rejects with
 * FENCE_REMINDER_STORE_UNAVAILABLE and therefore never publishes a wrong notification.
 *
 * When the factory lands, replace the body of this function:
 *   return createPersistentReminderRepository(filesDir);
 * plus a thin adapter if its surface differs from FenceReminderStore.
 */
export function createFenceReminderStore(filesDir: string): FenceReminderStore {
  return new UnavailableFenceReminderStore();
}
