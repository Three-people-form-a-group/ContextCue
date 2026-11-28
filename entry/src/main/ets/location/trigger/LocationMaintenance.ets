import { Reminder } from '../../model/Reminder';

/**
 * Page-facing maintenance entry for location fences ("重建地点提醒").
 * It only touches fences, the durable fence registry and scene reservations; reminders.json is
 * never modified, so no reminder is created or deleted by a rebuild.
 */
export interface LocationMaintenance {
  /**
   * Clears the durable fence mapping file and removes every system fence of this app.
   * Deliberately does not require location permission, so a user with a broken permission state
   * (or a corrupt registry) can still get back to a clean slate.
   */
  reset(): Promise<void>;

  /**
   * reset(), then register fences again for the supplied reminders.
   * The reset phase needs no permission; the re-registration phase does, and surfaces the
   * platform permission error unchanged.
   */
  rebuild(reminders: Reminder[]): Promise<void>;
}
