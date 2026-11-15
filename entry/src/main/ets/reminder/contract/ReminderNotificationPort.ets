import { Reminder } from '../../model/Reminder';

export interface ReminderNotificationPort {
  notify(reminder: Reminder): Promise<void>;
}
