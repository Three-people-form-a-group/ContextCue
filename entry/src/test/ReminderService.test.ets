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
  failFind: boolean = false;
  events?: string[];

  async save(reminder: Reminder): Promise<void> {
    this.saves++;
    this.events?.push('save:' + reminder.status);
    if (this.failSave) {
      throw new Error('save failed');
    }
    await super.save(reminder);
  }

  async findById(id: string): Promise<Reminder | undefined> {
    if (this.failFind) {
      throw new Error('read failed');
    }
    return super.findById(id);
  }

  async deleteById(id: string): Promise<boolean> {
    this.events?.push('delete');
    if (this.failDelete) {
      throw new Error('delete failed');
    }
    return super.deleteById(id);
  }
}

class DelayedDisableRepository extends TestRepository {
  private releaseDisable?: () => void;
  disableSaveEntered: boolean = false;

  async save(reminder: Reminder): Promise<void> {
    if (reminder.status === ReminderStatus.DISABLED) {
      this.disableSaveEntered = true;
      await new Promise<void>((resolve: () => void) => {
        this.releaseDisable = resolve;
      });
    }
    await super.save(reminder);
  }

  release(): void {
    if (this.releaseDisable !== undefined) {
      this.releaseDisable();
    }
  }
}

class TestTimePort implements TimeTriggerPort {
  scheduled: string[] = [];
  cancelled: string[] = [];
  failSchedule: boolean = false;
  failCancel: boolean = false;
  lastScheduledStatus?: ReminderStatus;
  events?: string[];

  async schedule(reminder: Reminder): Promise<void> {
    this.events?.push('schedule:' + reminder.content);
    if (this.failSchedule) {
      throw new Error('schedule failed');
    }
    this.scheduled.push(reminder.id);
    this.lastScheduledStatus = reminder.status;
  }

  async cancel(reminderId: string): Promise<void> {
    this.events?.push('cancel');
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
  registerError: string = 'register failed';
  failUnregister: boolean = false;
  events?: string[];

  async register(reminder: Reminder): Promise<void> {
    this.events?.push('register:' + reminder.content);
    if (this.failRegister) {
      throw new Error(this.registerError);
    }
    this.registered.push(reminder.id);
  }

  async unregister(reminderId: string): Promise<void> {
    this.events?.push('unregister');
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
      expect(time.lastScheduledStatus).assertEqual(ReminderStatus.ACTIVE);
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

    it('completes a triggered reminder then supports undo-complete back to ACTIVE', 0, async () => {
      const repository = new TestRepository();
      const service = new ReminderService(repository, new TestTimePort(), new TestLocationPort(), () => 3000, () => 'r-8');
      const reminder: Reminder = { id: 'r-8', content: '带电脑', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.TRIGGERED, source: ReminderSource.MANUAL, createdAt: 1000, triggeredAt: 2500 };
      await repository.save(reminder);
      expect((await service.complete('r-8')).data?.completedAt).assertEqual(3000);
      // 撤销完成：COMPLETED → ACTIVE 已允许（罗鸿程 2026-11-15 语义），时间戳必须清空
      const reenabled = await service.enable('r-8');
      expect(reenabled.data?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(reenabled.data?.completedAt).assertUndefined();
      expect(reenabled.data?.triggeredAt).assertUndefined();
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

    it('serializes overlapping status changes so a later completion cannot be overwritten', 0, async () => {
      const repository = new DelayedDisableRepository();
      const service = new ReminderService(repository, new TestTimePort(), new TestLocationPort(), () => 3000, () => 'unused');
      const reminder: Reminder = { id: 'r-race', content: '带电脑', triggerType: TriggerType.TIME, triggerTime: 4000, status: ReminderStatus.ACTIVE, source: ReminderSource.MANUAL, createdAt: 1000 };
      await repository.save(reminder);
      const disabling = service.disable('r-race');
      for (let i = 0; i < 20 && !repository.disableSaveEntered; i++) {
        await Promise.resolve();
      }
      expect(repository.disableSaveEntered).assertTrue();
      const completing = service.complete('r-race');
      for (let i = 0; i < 20; i++) {
        await Promise.resolve();
      }
      repository.release();
      expect((await disabling).success).assertTrue();
      expect((await completing).success).assertTrue();
      expect((await repository.findById('r-race'))?.status).assertEqual(ReminderStatus.COMPLETED);
    });

    it('orders registration, save, notification-state save, and cleanup', 0, async () => {
      const events: string[] = [];
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      repository.events = events;
      time.events = events;
      location.events = events;
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-order');
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.BOTH, triggerTime: 2000, sceneId: 'scene-1', source: ReminderSource.MANUAL };
      await service.create(input);
      expect(events.join(',')).assertEqual('schedule:带电脑,register:带电脑,save:ACTIVE');
      events.length = 0;
      await service.markTriggered('r-order', 2000);
      expect(events.join(',')).assertEqual('save:TRIGGERED,cancel,unregister');
    });

    it('orders active edit and deletion around repository mutation', 0, async () => {
      const events: string[] = [];
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      repository.events = events;
      time.events = events;
      location.events = events;
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-order-2');
      await service.create(timeInput());
      events.length = 0;
      await service.update('r-order-2', { content: '取快递', triggerType: TriggerType.LOCATION, sceneId: 'scene-1', source: ReminderSource.AI });
      expect(events.join(',')).assertEqual('cancel,unregister,register:取快递,save:ACTIVE');
      events.length = 0;
      await service.delete('r-order-2');
      expect(events.join(',')).assertEqual('cancel,unregister,delete');
    });

    it('returns stable errors for read, enable, ordinary save, and notification-state save failures', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const service = new ReminderService(repository, time, new TestLocationPort(), () => 1000, () => 'r-fail');
      await service.create(timeInput());
      repository.failFind = true;
      expect((await service.findById('r-fail')).error?.code).assertEqual('REPOSITORY_ERROR');
      repository.failFind = false;
      repository.failSave = true;
      const disabled = await service.disable('r-fail');
      expect(disabled.error?.code).assertEqual('REPOSITORY_ERROR');
      expect(disabled.error?.retryable).assertTrue();
      expect((await repository.findById('r-fail'))?.status).assertEqual(ReminderStatus.ACTIVE);
      const triggered = await service.markTriggered('r-fail', 2000);
      expect(triggered.error?.code).assertEqual('REPOSITORY_ERROR');
      expect((await repository.findById('r-fail'))?.status).assertEqual(ReminderStatus.ACTIVE);
      repository.failSave = false;
      await service.disable('r-fail');
      repository.failSave = true;
      const enabled = await service.enable('r-fail');
      expect(enabled.error?.code).assertEqual('REPOSITORY_ERROR');
      expect((await repository.findById('r-fail'))?.status).assertEqual(ReminderStatus.DISABLED);
    });

    it('keeps old data when replacement registration or deletion cleanup fails', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-fail-2');
      await service.create(timeInput());
      location.failRegister = true;
      const next: CreateReminderInput = { content: '新提醒', triggerType: TriggerType.LOCATION, sceneId: 'scene-1', source: ReminderSource.AI };
      expect((await service.update('r-fail-2', next)).error?.code).assertEqual('TRIGGER_REGISTRATION_ERROR');
      expect((await repository.findById('r-fail-2'))?.content).assertEqual('带电脑');
      expect(time.scheduled.length).assertEqual(2);
      time.failCancel = true;
      const deleted = await service.delete('r-fail-2');
      expect(deleted.error?.code).assertEqual('TRIGGER_CLEANUP_ERROR');
      expect((await repository.findById('r-fail-2'))?.status).assertEqual(ReminderStatus.ACTIVE);
    });

    it('surfaces stable location registration codes with retry guidance', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 1000, () => 'r-loc-code');
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.LOCATION,
        sceneId: 'scene-1', source: ReminderSource.MANUAL };
      location.failRegister = true;
      location.registerError = 'LOCATION_PERMISSION_DENIED';
      let result = await service.create(input);
      expect(result.error?.code).assertEqual('LOCATION_PERMISSION_DENIED');
      expect(result.error?.retryable).assertFalse();
      location.registerError = 'LOCATION_SWITCH_OFF';
      result = await service.create(input);
      expect(result.error?.code).assertEqual('LOCATION_SWITCH_OFF');
      expect(result.error?.retryable).assertTrue();
      location.registerError = 'LOCATION_FENCE_REGISTRATION_FAILED';
      result = await service.create(input);
      expect(result.error?.code).assertEqual('LOCATION_FENCE_REGISTRATION_FAILED');
      expect(result.error?.retryable).assertTrue();
      location.registerError = 'LOCATION_WGS84_FENCE_UNSUPPORTED';
      result = await service.create(input);
      expect(result.error?.code).assertEqual('LOCATION_WGS84_FENCE_UNSUPPORTED');
      expect(result.error?.retryable).assertFalse();
      location.failRegister = false;
      expect((await service.create(input)).success).assertTrue();
    });

    it('repeated terminal-state actions leave repository and ports unchanged', 0, async () => {
      const repository = new TestRepository();
      const time = new TestTimePort();
      const location = new TestLocationPort();
      const service = new ReminderService(repository, time, location, () => 3000, () => 'unused');
      const triggered: Reminder = { id: 'r-terminal', content: '带电脑', triggerType: TriggerType.TIME, triggerTime: 2000, status: ReminderStatus.TRIGGERED, source: ReminderSource.MANUAL, createdAt: 1000, triggeredAt: 2500 };
      await repository.save(triggered);
      const initialSaves = repository.saves;
      expect((await service.markTriggered('r-terminal', 3000)).data?.triggeredAt).assertEqual(2500);
      expect(repository.saves).assertEqual(initialSaves);
      expect(time.cancelled.length).assertEqual(0);
      expect(location.unregistered.length).assertEqual(0);
      await service.complete('r-terminal');
      const completedSaves = repository.saves;
      const cancelled = time.cancelled.length;
      const unregistered = location.unregistered.length;
      expect((await service.complete('r-terminal')).data?.completedAt).assertEqual(3000);
      expect(repository.saves).assertEqual(completedSaves);
      expect(time.cancelled.length).assertEqual(cancelled);
      expect(location.unregistered.length).assertEqual(unregistered);
    });
  });
}
