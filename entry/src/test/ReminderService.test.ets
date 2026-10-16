import { describe, it, expect } from '@ohos/hypium';
import { CreateReminderInput } from '../main/ets/model/CreateReminderInput';
import { Reminder } from '../main/ets/model/Reminder';
import { LocationTriggerMode, ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';
import { ReminderService } from '../main/ets/service/ReminderService';

class TestRepository extends InMemoryReminderRepository {
  saves: number = 0;
  failSave: boolean = false;

  async save(reminder: Reminder): Promise<void> {
    this.saves++;
    if (this.failSave) {
      throw new Error('save failed');
    }
    await super.save(reminder);
  }
}

class TestTimePort implements TimeTriggerPort {
  scheduled: string[] = [];
  cancelled: string[] = [];
  failSchedule: boolean = false;

  async schedule(reminder: Reminder): Promise<void> {
    if (this.failSchedule) {
      throw new Error('schedule failed');
    }
    this.scheduled.push(reminder.id);
  }

  async cancel(reminderId: string): Promise<void> {
    this.cancelled.push(reminderId);
  }
}

class TestLocationPort implements LocationTriggerPort {
  registered: string[] = [];
  unregistered: string[] = [];
  failRegister: boolean = false;

  async register(reminder: Reminder): Promise<void> {
    if (this.failRegister) {
      throw new Error('register failed');
    }
    this.registered.push(reminder.id);
  }

  async unregister(reminderId: string): Promise<void> {
    this.unregistered.push(reminderId);
  }

  async isInsideScene(sceneId: string): Promise<boolean> {
    return sceneId === 'scene-1';
  }
}

function timeInput(): CreateReminderInput {
  return { content: '  带电脑  ', triggerType: TriggerType.TIME, triggerTime: 2000, source: ReminderSource.MANUAL };
}

export default function reminderServiceTest() {
  describe('reminderServiceTest', () => {
    it('creates one ACTIVE time reminder with canonical content and one save', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-1');
      const result = await service.create(timeInput());
      expect(result.success).assertTrue();
      expect(result.data?.id).assertEqual('r-1');
      expect(result.data?.content).assertEqual('带电脑');
      expect(result.data?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(result.data?.createdAt).assertEqual(1000);
      expect(result.data?.source).assertEqual(ReminderSource.MANUAL);
      expect(time.scheduled.length).assertEqual(1);
      expect(location.registered.length).assertEqual(0);
      expect(repository.saves).assertEqual(1);
      expect((await service.findById('r-1')).data?.content).assertEqual('带电脑');
      expect((await service.findAll()).data?.length).assertEqual(1);
    });

    it('creates a location reminder with trimmed scene id and default ENTER', 0, async () => {
      const repository = new TestRepository();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, new TestTimePort(), location, () => 1000, () => 'r-2');
      const input: CreateReminderInput = { content: '取快递', triggerType: TriggerType.LOCATION, sceneId: ' scene-1 ', source: ReminderSource.AI };
      const result = await service.create(input);
      expect(result.success).assertTrue();
      expect(result.data?.sceneId).assertEqual('scene-1');
      expect(result.data?.locationTriggerMode).assertEqual(LocationTriggerMode.ENTER);
      expect(result.data?.source).assertEqual(ReminderSource.AI);
      expect(location.registered.length).assertEqual(1);
    });

    it('rejects invalid EXIT without writing or registering', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-3');
      const input: CreateReminderInput = { content: '取快递', triggerType: TriggerType.LOCATION, sceneId: 'scene-1', locationTriggerMode: LocationTriggerMode.EXIT, source: ReminderSource.MANUAL };
      const result = await service.create(input);
      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual('UNSUPPORTED_LOCATION_TRIGGER_MODE');
      expect(repository.saves).assertEqual(0);
      expect(time.scheduled.length).assertEqual(0);
      expect(location.registered.length).assertEqual(0);
    });

    it('compensates a partial BOTH registration failure without a record', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      location.failRegister = true;
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-4');
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.BOTH, triggerTime: 2000, sceneId: 'scene-1', source: ReminderSource.MANUAL };
      const result = await service.create(input);
      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual('TRIGGER_REGISTRATION_ERROR');
      expect(repository.saves).assertEqual(0);
      expect(time.cancelled[0]).assertEqual('r-4');
      expect(await repository.findById('r-4')).assertUndefined();
    });

    it('compensates both triggers when final repository save fails', 0, async () => {
      const repository = new TestRepository();
      repository.failSave = true;
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-5');
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.BOTH, triggerTime: 2000, sceneId: 'scene-1', source: ReminderSource.MANUAL };
      const result = await service.create(input);
      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual('REPOSITORY_ERROR');
      expect(time.cancelled[0]).assertEqual('r-5');
      expect(location.unregistered[0]).assertEqual('r-5');
      expect(await repository.findById('r-5')).assertUndefined();
    });
  });
}
