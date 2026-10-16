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
import { validateCreateReminderInput } from '../main/ets/model/ReminderModelRules';

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

    it('accepts valid time location and both inputs at the time boundary', 0, () => {
      const time: CreateReminderInput = { content: 'a', triggerType: TriggerType.TIME, triggerTime: 1000, source: ReminderSource.MANUAL };
      const location: CreateReminderInput = { content: 'a', triggerType: TriggerType.LOCATION, sceneId: 'scene', source: ReminderSource.MANUAL };
      const both: CreateReminderInput = { content: 'a', triggerType: TriggerType.BOTH, triggerTime: 1001, sceneId: 'scene', source: ReminderSource.AI };
      expect(validateCreateReminderInput(time, 1000).length).assertEqual(0);
      expect(validateCreateReminderInput(location, 1000).length).assertEqual(0);
      expect(validateCreateReminderInput(both, 1000).length).assertEqual(0);
    });

    it('reports empty content and both missing conditions in stable order', 0, () => {
      const input: CreateReminderInput = { content: '  ', triggerType: TriggerType.BOTH, source: ReminderSource.AI };
      const errors = validateCreateReminderInput(input, 1000);
      expect(errors.length).assertEqual(3);
      expect(errors[0].code).assertEqual('EMPTY_CONTENT');
      expect(errors[0].field).assertEqual('content');
      expect(errors[1].code).assertEqual('MISSING_TRIGGER_TIME');
      expect(errors[2].code).assertEqual('MISSING_SCENE_ID');
      expect(errors[0].retryable).assertFalse();
    });

    it('rejects missing invalid and past times', 0, () => {
      const input: CreateReminderInput = { content: 'a', triggerType: TriggerType.TIME, source: ReminderSource.MANUAL };
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('MISSING_TRIGGER_TIME');
      input.triggerTime = Number.NaN;
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('INVALID_TRIGGER_TIME');
      input.triggerTime = Number.POSITIVE_INFINITY;
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('INVALID_TRIGGER_TIME');
      input.triggerTime = Number.NEGATIVE_INFINITY;
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('INVALID_TRIGGER_TIME');
      input.triggerTime = 999;
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('PAST_TRIGGER_TIME');
    });

    it('requires a nonblank scene id even when a scene name exists', 0, () => {
      const input: CreateReminderInput = { content: 'a', triggerType: TriggerType.LOCATION, sceneName: '实验室', source: ReminderSource.AI };
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('MISSING_SCENE_ID');
      input.sceneId = '  ';
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('MISSING_SCENE_ID');
    });

    it('rejects fields inconsistent with trigger type', 0, () => {
      const input: CreateReminderInput = { content: 'a', triggerType: TriggerType.TIME, triggerTime: 1000, source: ReminderSource.MANUAL };
      input.sceneId = 'scene';
      expect(validateCreateReminderInput(input, 1000)[0].field).assertEqual('sceneId');
      expect(validateCreateReminderInput(input, 1000)[0].code).assertEqual('INCONSISTENT_TRIGGER_FIELDS');
      input.sceneId = undefined;
      input.sceneName = '实验室';
      expect(validateCreateReminderInput(input, 1000)[0].field).assertEqual('sceneName');
      input.sceneName = undefined;
      input.locationTriggerMode = LocationTriggerMode.ENTER;
      expect(validateCreateReminderInput(input, 1000)[0].field).assertEqual('locationTriggerMode');
      const location: CreateReminderInput = { content: 'a', triggerType: TriggerType.LOCATION, sceneId: 'scene', triggerTime: 1000, source: ReminderSource.MANUAL };
      expect(validateCreateReminderInput(location, 1000)[0].field).assertEqual('triggerTime');
      expect(validateCreateReminderInput(location, 1000)[0].code).assertEqual('INCONSISTENT_TRIGGER_FIELDS');
    });

    it('rejects EXIT for location and both', 0, () => {
      const location: CreateReminderInput = { content: 'a', triggerType: TriggerType.LOCATION, sceneId: 'scene', locationTriggerMode: LocationTriggerMode.EXIT, source: ReminderSource.MANUAL };
      const both: CreateReminderInput = { content: 'a', triggerType: TriggerType.BOTH, triggerTime: 1000, sceneId: 'scene', locationTriggerMode: LocationTriggerMode.EXIT, source: ReminderSource.AI };
      expect(validateCreateReminderInput(location, 1000)[0].code).assertEqual('UNSUPPORTED_LOCATION_TRIGGER_MODE');
      expect(validateCreateReminderInput(both, 1000)[0].code).assertEqual('UNSUPPORTED_LOCATION_TRIGGER_MODE');
    });
  });
}
