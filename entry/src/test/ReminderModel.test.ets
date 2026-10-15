import { describe, it, expect } from '@ohos/hypium';
import { CreateReminderInput } from '../main/ets/model/CreateReminderInput';
import { OperationResult } from '../main/ets/model/OperationResult';
import { Reminder } from '../main/ets/model/Reminder';
import {
  LocationTriggerMode,
  ReminderSource,
  ReminderStatus,
  TriggerType
} from '../main/ets/model/ReminderEnums';
import { Scene } from '../main/ets/model/Scene';

export default function reminderModelTest() {
  describe('reminderModelTest', () => {
    it('exposes stable enum values across modules', 0, () => {
      expect(TriggerType.TIME).assertEqual('TIME');
      expect(TriggerType.LOCATION).assertEqual('LOCATION');
      expect(TriggerType.BOTH).assertEqual('BOTH');
      expect(ReminderSource.MANUAL).assertEqual('MANUAL');
      expect(ReminderSource.AI).assertEqual('AI');
      expect(ReminderStatus.ACTIVE).assertEqual('ACTIVE');
      expect(ReminderStatus.TRIGGERED).assertEqual('TRIGGERED');
      expect(ReminderStatus.COMPLETED).assertEqual('COMPLETED');
      expect(ReminderStatus.DISABLED).assertEqual('DISABLED');
      expect(LocationTriggerMode.ENTER).assertEqual('ENTER');
      expect(LocationTriggerMode.EXIT).assertEqual('EXIT');
    });

    it('represents time location and combined reminders', 0, () => {
      const timeReminder: Reminder = {
        id: 'time-1',
        content: '带电脑',
        triggerType: TriggerType.TIME,
        triggerTime: 1000,
        status: ReminderStatus.ACTIVE,
        source: ReminderSource.MANUAL,
        createdAt: 100
      };
      const locationReminder: Reminder = {
        id: 'location-1',
        content: '提交报告',
        triggerType: TriggerType.LOCATION,
        sceneId: 'scene-1',
        sceneName: '实验室',
        locationTriggerMode: LocationTriggerMode.ENTER,
        status: ReminderStatus.DISABLED,
        source: ReminderSource.AI,
        createdAt: 200
      };
      const bothReminder: Reminder = {
        id: 'both-1',
        content: '取快递',
        triggerType: TriggerType.BOTH,
        triggerTime: 2000,
        sceneId: 'scene-2',
        sceneName: '宿舍',
        locationTriggerMode: LocationTriggerMode.ENTER,
        status: ReminderStatus.TRIGGERED,
        source: ReminderSource.AI,
        createdAt: 300,
        triggeredAt: 2100,
        completedAt: 2200
      };

      expect(timeReminder.triggerTime).assertEqual(1000);
      expect(locationReminder.sceneId).assertEqual('scene-1');
      expect(bothReminder.locationTriggerMode).assertEqual(LocationTriggerMode.ENTER);
      expect(bothReminder.triggeredAt).assertEqual(2100);
      expect(bothReminder.completedAt).assertEqual(2200);
    });

    it('shares scene creation input and operation result contracts', 0, () => {
      const scene: Scene = {
        id: 'scene-1',
        name: '实验室',
        latitude: 34.25,
        longitude: 108.95,
        radius: 100,
        createdAt: 100
      };
      const input: CreateReminderInput = {
        content: '带电脑',
        triggerType: TriggerType.BOTH,
        triggerTime: 1000,
        sceneId: scene.id,
        sceneName: scene.name,
        locationTriggerMode: LocationTriggerMode.ENTER,
        source: ReminderSource.AI
      };
      const successResult: OperationResult<CreateReminderInput> = {
        success: true,
        data: input
      };
      const failureResult: OperationResult<CreateReminderInput> = {
        success: false,
        error: {
          code: 'INVALID_INPUT',
          message: '创建输入无效',
          field: 'content',
          retryable: false
        }
      };

      expect(scene.radius).assertEqual(100);
      expect(successResult.data?.source).assertEqual(ReminderSource.AI);
      expect(failureResult.error?.code).assertEqual('INVALID_INPUT');
      expect(failureResult.error?.field).assertEqual('content');
      expect(failureResult.error?.retryable).assertFalse();
    });
  });
}
