import { Reminder } from '../model/Reminder';
import { ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { ReminderService } from '../service/ReminderService';
import { LocationTriggerPort } from './contract/LocationTriggerPort';
import { ReminderNotificationPort } from './contract/ReminderNotificationPort';
import { TriggerCondition, TriggerConditionEvent } from './contract/TriggerConditionEvent';
import { TriggerEventSink } from './contract/TriggerEventSink';

function coordinatorError(message: string): Error {
  return new Error(message);
}

interface ConditionSnapshot {
  matched: boolean;
  sceneId?: string;
}

export class TriggerCoordinator implements TriggerEventSink {
  private reminderService: ReminderService;
  private locationPort: LocationTriggerPort;
  private notificationPort: ReminderNotificationPort;
  private now: () => number;
  private processingGates: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  constructor(reminderService: ReminderService, locationPort: LocationTriggerPort,
    notificationPort: ReminderNotificationPort, now: () => number) {
    this.reminderService = reminderService;
    this.locationPort = locationPort;
    this.notificationPort = notificationPort;
    this.now = now;
  }

  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    return this.serialize(event.reminderId, () => this.process(event));
  }

  private async process(event: TriggerConditionEvent): Promise<void> {
    if (!event.satisfied) {
      return;
    }

    const loaded = await this.reminderService.findById(event.reminderId);
    if (!loaded.success || loaded.data === undefined) {
      if (loaded.error?.code === 'REMINDER_NOT_FOUND') {
        return;
      }
      throw coordinatorError('提醒读取失败');
    }

    const reminder = loaded.data;
    if (reminder.status !== ReminderStatus.ACTIVE) {
      return;
    }
    const snapshot = await this.captureCondition(reminder, event.condition);
    if (!snapshot.matched) {
      return;
    }

    const marked = await this.reminderService.processActiveTrigger(reminder.id, event.occurredAt,
      async (current: Reminder): Promise<boolean> => {
        if (!this.matchesCondition(current, event.condition, snapshot)) {
          return false;
        }
        try {
          await this.notificationPort.notify(current);
        } catch (_) {
          throw coordinatorError('提醒通知失败');
        }
        return true;
      });
    if (!marked.success) {
      if (marked.error?.code === 'REMINDER_NOT_FOUND') {
        return;
      }
      if (marked.error?.code === 'TRIGGER_CLEANUP_ERROR') {
        throw coordinatorError('触发器清理失败');
      }
      throw coordinatorError('提醒触发状态保存失败');
    }
  }

  private async captureCondition(reminder: Reminder, condition: TriggerCondition): Promise<ConditionSnapshot> {
    if (reminder.triggerType === TriggerType.TIME) {
      if (condition !== TriggerCondition.TIME) {
        return { matched: false };
      }
      if (reminder.triggerTime === undefined) {
        throw coordinatorError('时间触发条件不完整');
      }
      return { matched: this.now() >= reminder.triggerTime };
    }

    if (reminder.triggerType === TriggerType.LOCATION) {
      if (condition !== TriggerCondition.LOCATION) {
        return { matched: false };
      }
      const sceneId = this.requireSceneId(reminder.sceneId);
      return { matched: await this.isInside(sceneId), sceneId: sceneId };
    }

    if (reminder.triggerTime === undefined || reminder.sceneId === undefined) {
      throw coordinatorError('联合触发条件不完整');
    }
    if (this.now() < reminder.triggerTime) {
      return { matched: false };
    }
    const sceneId = this.requireSceneId(reminder.sceneId);
    return { matched: await this.isInside(sceneId), sceneId: sceneId };
  }

  private matchesCondition(reminder: Reminder, condition: TriggerCondition,
    snapshot: ConditionSnapshot): boolean {
    if (reminder.triggerType === TriggerType.TIME) {
      return condition === TriggerCondition.TIME && reminder.triggerTime !== undefined &&
        this.now() >= reminder.triggerTime;
    }
    if (reminder.triggerType === TriggerType.LOCATION) {
      return condition === TriggerCondition.LOCATION && reminder.sceneId === snapshot.sceneId;
    }
    return reminder.triggerTime !== undefined && this.now() >= reminder.triggerTime &&
      reminder.sceneId === snapshot.sceneId;
  }

  private requireSceneId(sceneId?: string): string {
    if (sceneId === undefined || sceneId.trim().length === 0) {
      throw coordinatorError('地点触发条件不完整');
    }
    return sceneId;
  }

  private async isInside(sceneId: string): Promise<boolean> {
    try {
      return await this.locationPort.isInsideScene(sceneId);
    } catch (_) {
      throw coordinatorError('地点条件检查失败');
    }
  }

  private async serialize(id: string, action: () => Promise<void>): Promise<void> {
    const previous = this.processingGates.get(id);
    let releaseGate: () => void = () => {};
    const gate: Promise<void> = new Promise<void>((resolve: () => void) => {
      releaseGate = resolve;
    });
    this.processingGates.set(id, gate);
    if (previous !== undefined) {
      await previous;
    }
    try {
      await action();
    } finally {
      releaseGate();
      if (this.processingGates.get(id) === gate) {
        this.processingGates.delete(id);
      }
    }
  }
}
