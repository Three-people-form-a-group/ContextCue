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
  failDelete: boolean = false;

  async save(reminder: Reminder): Promise<void> {
    this.saves++;
    if (this.failSave) {
      throw new Error('save failed');
    }
    await super.save(reminder);
  }

  async deleteById(id: string): Promise<boolean> {
    if (this.failDelete) {
      throw new Error('delete failed');
    }
    return super.deleteById(id);
  }
}

class TestTimePort implements TimeTriggerPort {
  scheduled: string[] = [];
  cancelled: string[] = [];
  failSchedule: boolean = false;
  failCancel: boolean = false;

  async schedule(reminder: Reminder): Promise<void> {
    if (this.failSchedule) {
      throw new Error('schedule failed');
    }
    this.scheduled.push(reminder.id);
  }

  async cancel(reminderId: string): Promise<void> {
    if (this.failCancel) {
      throw new Error('cancel failed');
    }
    this.cancelled.push(reminderId);
  }
}

class TestLocationPort implements LocationTriggerPort {
  registered: string[] = [];
  unregistered: string[] = [];
  failRegister: boolean = false;
  failUnregister: boolean = false;

  async register(reminder: Reminder): Promise<void> {
    if (this.failRegister) {
      throw new Error('register failed');
    }
    this.registered.push(reminder.id);
  }

  async unregister(reminderId: string): Promise<void> {
    if (this.failUnregister) {
      throw new Error('unregister failed');
    }
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

    it('disables and re-enables while same-status calls are true no-ops', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-6');
      await service.create(timeInput());
      expect((await service.disable('r-6')).data?.status).assertEqual(ReminderStatus.DISABLED);
      expect(time.cancelled.length).assertEqual(1);
      expect(location.unregistered.length).assertEqual(1);
      const savesAfterDisable = repository.saves;
      expect((await service.disable('r-6')).success).assertTrue();
      expect(repository.saves).assertEqual(savesAfterDisable);
      expect(time.cancelled.length).assertEqual(1);
      expect(location.unregistered.length).assertEqual(1);
      expect((await service.enable('r-6')).data?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(time.scheduled.length).assertEqual(2);
      const savesAfterEnable = repository.saves;
      expect((await service.enable('r-6')).success).assertTrue();
      expect(repository.saves).assertEqual(savesAfterEnable);
      expect(time.scheduled.length).assertEqual(2);
    });

    it('marks notification success before cleanup and retries cleanup without a second state write', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-7');
      await service.create(timeInput());
      location.failUnregister = true;
      const result = await service.markTriggered('r-7', 2500);
      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual('TRIGGER_CLEANUP_ERROR');
      expect(result.data?.status).assertEqual(ReminderStatus.TRIGGERED);
      expect(result.data?.triggeredAt).assertEqual(2500);
      expect((await repository.findById('r-7'))?.status).assertEqual(ReminderStatus.TRIGGERED);
      const savesAfterTrigger = repository.saves;
      expect((await service.markTriggered('r-7', 3000)).success).assertTrue();
      expect(repository.saves).assertEqual(savesAfterTrigger);
      expect((await repository.findById('r-7'))?.triggeredAt).assertEqual(2500);
      location.failUnregister = false;
      expect((await service.retryTriggerCleanup('r-7')).success).assertTrue();
      expect(repository.saves).assertEqual(savesAfterTrigger);
    });

    it('completes a triggered reminder but never re-enables it', 0, async () => {
      const repository = new TestRepository();
      const service = new ReminderService(repository, new TestTimePort(), new TestLocationPort(), () => 3000, () => 'r-8');
      const reminder: Reminder = { id: 'r-8', content: '带电脑', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.TRIGGERED, source: ReminderSource.MANUAL, createdAt: 1000, triggeredAt: 2500 };
      await repository.save(reminder);
      expect((await service.complete('r-8')).data?.completedAt).assertEqual(3000);
      expect((await service.enable('r-8')).error?.code).assertEqual('INVALID_STATUS_TRANSITION');
      expect((await repository.findById('r-8'))?.status).assertEqual(ReminderStatus.COMPLETED);
      expect((await service.complete('r-8')).data?.completedAt).assertEqual(3000);
    });

    it('keeps ACTIVE when ordinary cleanup fails and reports missing IDs', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const service = new ReminderService(repository, time, new TestLocationPort(), () => 1000, () => 'r-9');
      await service.create(timeInput());
      time.failCancel = true;
      const result = await service.disable('r-9');
      expect(result.error?.code).assertEqual('TRIGGER_CLEANUP_ERROR');
      expect((await repository.findById('r-9'))?.status).assertEqual(ReminderStatus.ACTIVE);
      expect((await service.disable('missing')).error?.code).assertEqual('REMINDER_NOT_FOUND');
    });

    it('edits ACTIVE BOTH to TIME and preserves identity while removing old location trigger', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-10');
      const both: CreateReminderInput = { content: '旧提醒', triggerType: TriggerType.BOTH, triggerTime: 2000, sceneId: 'scene-1', source: ReminderSource.MANUAL };
      await service.create(both);
      const updated = await service.update('r-10', timeInput());
      expect(updated.success).assertTrue();
      expect(updated.data?.id).assertEqual('r-10');
      expect(updated.data?.createdAt).assertEqual(1000);
      expect(updated.data?.content).assertEqual('带电脑');
      expect(updated.data?.triggerType).assertEqual(TriggerType.TIME);
      expect(updated.data?.sceneId).assertUndefined();
      expect(updated.data?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(location.unregistered.length).assertEqual(1);
      expect(time.cancelled.length).assertEqual(1);
      expect(time.scheduled.length).assertEqual(2);
    });

    it('edits DISABLED without registration and rejects editing terminal status', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'unused');
      const disabled: Reminder = { id: 'r-11', content: '旧提醒', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.DISABLED, source: ReminderSource.MANUAL, createdAt: 100 };
      await repository.save(disabled);
      const result = await service.update('r-11', timeInput());
      expect(result.data?.status).assertEqual(ReminderStatus.DISABLED);
      expect(result.data?.createdAt).assertEqual(100);
      expect(time.scheduled.length).assertEqual(0);
      const completed: Reminder = { id: 'r-12', content: '旧提醒', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.COMPLETED, source: ReminderSource.MANUAL, createdAt: 100, completedAt: 500 };
      await repository.save(completed);
      expect((await service.update('r-12', timeInput())).error?.code).assertEqual('INVALID_STATUS_TRANSITION');
    });

    it('restores old ACTIVE triggers and record when an edit save fails', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-13');
      await service.create(timeInput());
      repository.failSave = true;
      const next: CreateReminderInput = { content: '新提醒', triggerType: TriggerType.LOCATION, sceneId: 'scene-1', source: ReminderSource.AI };
      const result = await service.update('r-13', next);
      expect(result.error?.code).assertEqual('REPOSITORY_ERROR');
      expect((await repository.findById('r-13'))?.content).assertEqual('带电脑');
      expect(location.unregistered.length).assertEqual(2);
      expect(time.scheduled.length).assertEqual(2);
    });

    it('deletes only after cleanup and restores registration if deletion fails', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-14');
      await service.create(timeInput());
      repository.failDelete = true;
      expect((await service.delete('r-14')).error?.code).assertEqual('REPOSITORY_ERROR');
      expect((await repository.findById('r-14'))?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(time.scheduled.length).assertEqual(2);
      repository.failDelete = false;
      expect((await service.delete('r-14')).data).assertTrue();
      expect(await repository.findById('r-14')).assertUndefined();
      expect((await service.delete('r-14')).error?.code).assertEqual('REMINDER_NOT_FOUND');
    });

    it('never overwrites an existing reminder when an ID factory collides', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const service = new ReminderService(repository, time, new TestLocationPort(), () => 1000, () => 'r-existing');
      const existing: Reminder = { id: 'r-existing', content: '原提醒', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.DISABLED, source: ReminderSource.MANUAL, createdAt: 100 };
      await repository.save(existing);
      const result = await service.create(timeInput());
      expect(result.success).assertFalse();
      expect(result.error?.code).assertEqual('REPOSITORY_ERROR');
      expect((await repository.findById('r-existing'))?.content).assertEqual('原提醒');
      expect(time.scheduled.length).assertEqual(0);
    });
  });
}
