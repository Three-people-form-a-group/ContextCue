import { describe, it, expect } from '@ohos/hypium';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import {
  TriggerCondition,
  TriggerConditionEvent
} from '../main/ets/reminder/contract/TriggerConditionEvent';
import { TriggerEventSink } from '../main/ets/reminder/contract/TriggerEventSink';
import { ReminderNotificationPort } from '../main/ets/reminder/contract/ReminderNotificationPort';

class TestTriggerEventSink implements TriggerEventSink {
  events: TriggerConditionEvent[] = [];

  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    this.events.push(event);
  }
}

class TestReminderNotificationPort implements ReminderNotificationPort {
  notified?: Reminder;

  async notify(reminder: Reminder): Promise<void> {
    this.notified = reminder;
  }
}

export default function reminderEventContractTest() {
  describe('reminderEventContractTest', () => {
    it('uses stable condition values and transports condition changes', 0, async () => {
      const sink = new TestTriggerEventSink();
      const timeEvent: TriggerConditionEvent = {
        reminderId: 'r-1',
        condition: TriggerCondition.TIME,
        satisfied: true,
        occurredAt: 2000
      };
      const locationEvent: TriggerConditionEvent = {
        reminderId: 'r-1',
        condition: TriggerCondition.LOCATION,
        satisfied: false,
        occurredAt: 2100
      };

      await sink.onConditionChanged(timeEvent);
      await sink.onConditionChanged(locationEvent);

      expect(TriggerCondition.TIME).assertEqual('TIME');
      expect(TriggerCondition.LOCATION).assertEqual('LOCATION');
      expect(sink.events.length).assertEqual(2);
      expect(sink.events[0].reminderId).assertEqual('r-1');
      expect(sink.events[0].satisfied).assertTrue();
      expect(sink.events[1].condition).assertEqual(TriggerCondition.LOCATION);
      expect(sink.events[1].satisfied).assertFalse();
      expect(sink.events[1].occurredAt).assertEqual(2100);
    });

    it('passes the shared Reminder model to the notification adapter', 0, async () => {
      const reminder: Reminder = {
        id: 'r-2',
        content: '带电脑',
        triggerType: TriggerType.BOTH,
        triggerTime: 2000,
        sceneId: 'scene-1',
        status: ReminderStatus.ACTIVE,
        source: ReminderSource.AI,
        createdAt: 1000
      };
      const notificationPort = new TestReminderNotificationPort();

      await notificationPort.notify(reminder);

      expect(notificationPort.notified?.id).assertEqual('r-2');
      expect(notificationPort.notified?.content).assertEqual('带电脑');
      expect(notificationPort.notified?.triggerType).assertEqual(TriggerType.BOTH);
    });
  });
}
