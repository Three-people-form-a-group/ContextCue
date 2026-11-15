import { Reminder } from '../../model/Reminder';

export interface TimeTriggerPort {
  schedule(reminder: Reminder): Promise<void>;
  cancel(reminderId: string): Promise<void>;
}
