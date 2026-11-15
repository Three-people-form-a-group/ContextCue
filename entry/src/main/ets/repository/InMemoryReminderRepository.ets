import { Reminder } from '../model/Reminder';
import { ReminderRepository } from './ReminderRepository';

function copyReminder(reminder: Reminder): Reminder {
  return {
    id: reminder.id,
    content: reminder.content,
    triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime,
    sceneId: reminder.sceneId,
    sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode,
    status: reminder.status,
    source: reminder.source,
    createdAt: reminder.createdAt,
    triggeredAt: reminder.triggeredAt,
    completedAt: reminder.completedAt
  };
}

export class InMemoryReminderRepository implements ReminderRepository {
  private reminders: Map<string, Reminder> = new Map<string, Reminder>();

  async save(reminder: Reminder): Promise<void> {
    this.reminders.set(reminder.id, copyReminder(reminder));
  }

  async findById(id: string): Promise<Reminder | undefined> {
    const found = this.reminders.get(id);
    return found === undefined ? undefined : copyReminder(found);
  }

  async findAll(): Promise<Reminder[]> {
    const all: Reminder[] = [];
    this.reminders.forEach((reminder: Reminder) => {
      all.push(copyReminder(reminder));
    });
    return all;
  }

  async deleteById(id: string): Promise<boolean> {
    return this.reminders.delete(id);
  }
}
