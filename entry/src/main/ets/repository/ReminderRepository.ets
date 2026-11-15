import { Reminder } from '../model/Reminder';

export interface ReminderRepository {
  save(reminder: Reminder): Promise<void>;
  findById(id: string): Promise<Reminder | undefined>;
  findAll(): Promise<Reminder[]>;
  deleteById(id: string): Promise<boolean>;
}
