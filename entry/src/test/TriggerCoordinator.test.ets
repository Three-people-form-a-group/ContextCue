import { describe, it, expect } from '@ohos/hypium';
import { Reminder } from '../main/ets/model/Reminder';
import { CreateReminderInput } from '../main/ets/model/CreateReminderInput';
import { OperationResult } from '../main/ets/model/OperationResult';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../main/ets/reminder/contract/ReminderNotificationPort';
import { TriggerCondition, TriggerConditionEvent } from '../main/ets/reminder/contract/TriggerConditionEvent';
import { TriggerCoordinator } from '../main/ets/reminder/TriggerCoordinator';
import { ReminderService } from '../main/ets/service/ReminderService';

class CoordinatorRepository extends InMemoryReminderRepository {
  failTriggeredSave: boolean = false;

  async save(reminder: Reminder): Promise<void> {
    if (this.failTriggeredSave && reminder.status === ReminderStatus.TRIGGERED) {
      throw new Error('save failed');
    }
    await super.save(reminder);
  }
}

class CoordinatorTimePort implements TimeTriggerPort {
  failCancel: boolean = false;

  async schedule(_: Reminder): Promise<void> {}

  async cancel(_: string): Promise<void> {
    if (this.failCancel) {
      throw new Error('cancel failed');
    }
  }
}

class CoordinatorLocationPort implements LocationTriggerPort {
  inside: boolean = false;
  failQuery: boolean = false;
  blockQuery: boolean = false;
  queryEntered: boolean = false;
  queriedSceneIds: string[] = [];
  private releaseQuery?: () => void;

  async register(_: Reminder): Promise<void> {}

  async unregister(_: string): Promise<void> {}

  async isInsideScene(sceneId: string): Promise<boolean> {
    this.queriedSceneIds.push(sceneId);
    this.queryEntered = true;
    if (this.blockQuery) {
      await new Promise<void>((resolve: () => void) => {
        this.releaseQuery = resolve;
      });
    }
    if (this.failQuery) {
      throw new Error('query failed');
    }
    return this.inside;
  }

  release(): void {
    if (this.releaseQuery !== undefined) {
      this.releaseQuery();
    }
  }
}

class CoordinatorNotificationPort implements ReminderNotificationPort {
  notifiedIds: string[] = [];
  failNotify: boolean = false;
  blockNotify: boolean = false;
  notifyEntered: boolean = false;
  private releaseNotify?: () => void;

  async notify(reminder: Reminder): Promise<void> {
    if (this.failNotify) {
      throw new Error('notify failed');
    }
    this.notifiedIds.push(reminder.id);
    this.notifyEntered = true;
    if (this.blockNotify) {
      await new Promise<void>((resolve: () => void) => {
        this.releaseNotify = resolve;
      });
    }
  }

  release(): void {
    if (this.releaseNotify !== undefined) {
      this.releaseNotify();
    }
  }
}

interface CoordinatorHarness {
  repository: CoordinatorRepository;
  time: CoordinatorTimePort;
  location: CoordinatorLocationPort;
  notification: CoordinatorNotificationPort;
  service: ReminderService;
  coordinator: TriggerCoordinator;
}

function harness(now: () => number): CoordinatorHarness {
  const repository = new CoordinatorRepository();
  const time = new CoordinatorTimePort();
  const location = new CoordinatorLocationPort();
  const notification = new CoordinatorNotificationPort();
  const service = new ReminderService(repository, time, location, now, () => 'unused');
  return {
    repository: repository,
    time: time,
    location: location,
    notification: notification,
    service: service,
    coordinator: new TriggerCoordinator(service, location, notification, now)
  };
}

function reminder(id: string, triggerType: TriggerType, status: ReminderStatus = ReminderStatus.ACTIVE,
  triggerTime?: number, sceneId?: string): Reminder {
  return {
    id: id,
    content: '带电脑',
    triggerType: triggerType,
    triggerTime: triggerTime,
    sceneId: sceneId,
    status: status,
    source: ReminderSource.MANUAL,
    createdAt: 1000
  };
}

function event(id: string, condition: TriggerCondition, satisfied: boolean, occurredAt: number): TriggerConditionEvent {
  return { reminderId: id, condition: condition, satisfied: satisfied, occurredAt: occurredAt };
}

export default function triggerCoordinatorTest() {
  describe('triggerCoordinatorTest', () => {
    it('triggers TIME only for a satisfied due TIME event', 0, async () => {
      let currentTime = 1500;
      const h = harness(() => currentTime);
      await h.repository.save(reminder('time-1', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));

      await h.coordinator.onConditionChanged(event('time-1', TriggerCondition.TIME, true, 1500));
      currentTime = 2500;
      await h.coordinator.onConditionChanged(event('time-1', TriggerCondition.TIME, false, 2400));
      await h.coordinator.onConditionChanged(event('time-1', TriggerCondition.LOCATION, true, 2450));
      expect(h.notification.notifiedIds.length).assertEqual(0);

      await h.coordinator.onConditionChanged(event('time-1', TriggerCondition.TIME, true, 2500));
      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('time-1'))?.status).assertEqual(ReminderStatus.TRIGGERED);
      expect((await h.repository.findById('time-1'))?.triggeredAt).assertEqual(2500);
    });

    it('triggers LOCATION only while currently inside the target scene', 0, async () => {
      const h = harness(() => 3000);
      await h.repository.save(reminder('location-1', TriggerType.LOCATION, ReminderStatus.ACTIVE, undefined, 'scene-1'));

      await h.coordinator.onConditionChanged(event('location-1', TriggerCondition.LOCATION, true, 2500));
      expect(h.notification.notifiedIds.length).assertEqual(0);
      h.location.inside = true;
      await h.coordinator.onConditionChanged(event('location-1', TriggerCondition.LOCATION, true, 2600));

      expect(h.location.queriedSceneIds.join(',')).assertEqual('scene-1,scene-1');
      expect(h.notification.notifiedIds[0]).assertEqual('location-1');
      expect((await h.repository.findById('location-1'))?.status).assertEqual(ReminderStatus.TRIGGERED);
    });

    it('applies BOTH as current time AND current location without historical flags', 0, async () => {
      let currentTime = 1500;
      const h = harness(() => currentTime);
      h.location.inside = true;
      await h.repository.save(reminder('both-1', TriggerType.BOTH, ReminderStatus.ACTIVE, 2000, 'scene-1'));

      await h.coordinator.onConditionChanged(event('both-1', TriggerCondition.LOCATION, true, 1500));
      expect(h.notification.notifiedIds.length).assertEqual(0);
      currentTime = 2000;
      h.location.inside = false;
      await h.coordinator.onConditionChanged(event('both-1', TriggerCondition.TIME, true, 2000));
      expect(h.notification.notifiedIds.length).assertEqual(0);
      h.location.inside = true;
      await h.coordinator.onConditionChanged(event('both-1', TriggerCondition.LOCATION, true, 2100));

      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('both-1'))?.triggeredAt).assertEqual(2100);
    });

    it('triggers BOTH at time arrival when already inside', 0, async () => {
      const h = harness(() => 2000);
      h.location.inside = true;
      await h.repository.save(reminder('both-2', TriggerType.BOTH, ReminderStatus.ACTIVE, 2000, 'scene-2'));

      await h.coordinator.onConditionChanged(event('both-2', TriggerCondition.TIME, true, 2000));

      expect(h.notification.notifiedIds[0]).assertEqual('both-2');
      expect(h.location.queriedSceneIds[0]).assertEqual('scene-2');
    });

    it('ignores stale missing disabled and terminal reminders', 0, async () => {
      const h = harness(() => 3000);
      await h.repository.save(reminder('disabled', TriggerType.TIME, ReminderStatus.DISABLED, 2000));
      await h.repository.save(reminder('triggered', TriggerType.TIME, ReminderStatus.TRIGGERED, 2000));
      await h.repository.save(reminder('completed', TriggerType.TIME, ReminderStatus.COMPLETED, 2000));

      await h.coordinator.onConditionChanged(event('missing', TriggerCondition.TIME, true, 3000));
      await h.coordinator.onConditionChanged(event('disabled', TriggerCondition.TIME, true, 3000));
      await h.coordinator.onConditionChanged(event('triggered', TriggerCondition.TIME, true, 3000));
      await h.coordinator.onConditionChanged(event('completed', TriggerCondition.TIME, true, 3000));

      expect(h.notification.notifiedIds.length).assertEqual(0);
    });

    it('leaves ACTIVE and rejects when notification fails', 0, async () => {
      const h = harness(() => 3000);
      h.notification.failNotify = true;
      await h.repository.save(reminder('notify-fail', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));
      let rejected = false;

      try {
        await h.coordinator.onConditionChanged(event('notify-fail', TriggerCondition.TIME, true, 3000));
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect((await h.repository.findById('notify-fail'))?.status).assertEqual(ReminderStatus.ACTIVE);
    });

    it('leaves ACTIVE and rejects when current location cannot be checked', 0, async () => {
      const h = harness(() => 3000);
      h.location.failQuery = true;
      await h.repository.save(reminder('location-fail', TriggerType.LOCATION, ReminderStatus.ACTIVE, undefined, 'scene-1'));
      let rejected = false;

      try {
        await h.coordinator.onConditionChanged(event('location-fail', TriggerCondition.LOCATION, true, 3000));
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(h.notification.notifiedIds.length).assertEqual(0);
      expect((await h.repository.findById('location-fail'))?.status).assertEqual(ReminderStatus.ACTIVE);
    });

    it('surfaces state-save failure after notification and keeps repository ACTIVE', 0, async () => {
      const h = harness(() => 3000);
      h.repository.failTriggeredSave = true;
      await h.repository.save(reminder('save-fail', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));
      let rejected = false;

      try {
        await h.coordinator.onConditionChanged(event('save-fail', TriggerCondition.TIME, true, 3000));
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('save-fail'))?.status).assertEqual(ReminderStatus.ACTIVE);
    });

    it('keeps TRIGGERED but reports when trigger cleanup fails', 0, async () => {
      const h = harness(() => 3000);
      h.time.failCancel = true;
      await h.repository.save(reminder('cleanup-fail', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));
      let rejected = false;

      try {
        await h.coordinator.onConditionChanged(event('cleanup-fail', TriggerCondition.TIME, true, 3000));
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('cleanup-fail'))?.status).assertEqual(ReminderStatus.TRIGGERED);
    });

    it('serializes concurrent events so successful notification is sent once', 0, async () => {
      const h = harness(() => 3000);
      h.notification.blockNotify = true;
      await h.repository.save(reminder('race', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));
      const first: Promise<void> = h.coordinator.onConditionChanged(
        event('race', TriggerCondition.TIME, true, 3000));
      for (let i = 0; i < 20 && !h.notification.notifyEntered; i++) {
        await Promise.resolve();
      }
      expect(h.notification.notifyEntered).assertTrue();
      const second: Promise<void> = h.coordinator.onConditionChanged(
        event('race', TriggerCondition.TIME, true, 3001));
      h.notification.release();
      await first;
      await second;

      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('race'))?.status).assertEqual(ReminderStatus.TRIGGERED);
    });

    it('does not notify an event invalidated by a concurrent disable', 0, async () => {
      const h = harness(() => 3000);
      h.location.inside = true;
      h.location.blockQuery = true;
      await h.repository.save(reminder('disable-race', TriggerType.LOCATION,
        ReminderStatus.ACTIVE, undefined, 'scene-1'));
      let eventRejected = false;
      const handling: Promise<void> = h.coordinator.onConditionChanged(
        event('disable-race', TriggerCondition.LOCATION, true, 3000)).catch(() => {
          eventRejected = true;
        });
      for (let i = 0; i < 20 && !h.location.queryEntered; i++) {
        await Promise.resolve();
      }
      expect(h.location.queryEntered).assertTrue();

      const disabled = await h.service.disable('disable-race');
      expect(disabled.success).assertTrue();
      h.location.release();
      await handling;

      expect(eventRejected).assertFalse();
      expect(h.notification.notifiedIds.length).assertEqual(0);
      expect((await h.repository.findById('disable-race'))?.status).assertEqual(ReminderStatus.DISABLED);
    });

    it('does not apply an old scene result after a concurrent update', 0, async () => {
      const h = harness(() => 3000);
      h.location.inside = true;
      h.location.blockQuery = true;
      await h.repository.save(reminder('update-race', TriggerType.LOCATION,
        ReminderStatus.ACTIVE, undefined, 'scene-old'));
      const handling: Promise<void> = h.coordinator.onConditionChanged(
        event('update-race', TriggerCondition.LOCATION, true, 3000));
      for (let i = 0; i < 20 && !h.location.queryEntered; i++) {
        await Promise.resolve();
      }
      expect(h.location.queryEntered).assertTrue();

      const next: CreateReminderInput = {
        content: '新地点提醒',
        triggerType: TriggerType.LOCATION,
        sceneId: 'scene-new',
        source: ReminderSource.MANUAL
      };
      const updated = await h.service.update('update-race', next);
      expect(updated.success).assertTrue();
      h.location.release();
      await handling;

      expect(h.notification.notifiedIds.length).assertEqual(0);
      expect((await h.repository.findById('update-race'))?.sceneId).assertEqual('scene-new');
      expect((await h.repository.findById('update-race'))?.status).assertEqual(ReminderStatus.ACTIVE);
    });

    it('keeps same-id service mutation queued while notification is pending', 0, async () => {
      const h = harness(() => 3000);
      h.notification.blockNotify = true;
      await h.repository.save(reminder('notify-lock', TriggerType.TIME, ReminderStatus.ACTIVE, 2000));
      const handling: Promise<void> = h.coordinator.onConditionChanged(
        event('notify-lock', TriggerCondition.TIME, true, 3000));
      for (let i = 0; i < 20 && !h.notification.notifyEntered; i++) {
        await Promise.resolve();
      }
      expect(h.notification.notifyEntered).assertTrue();
      let disableFinished = false;
      const disabling: Promise<OperationResult<Reminder>> = h.service.disable('notify-lock').then(
        (result: OperationResult<Reminder>): OperationResult<Reminder> => {
          disableFinished = true;
          return result;
        });
      for (let i = 0; i < 20; i++) {
        await Promise.resolve();
      }
      expect(disableFinished).assertFalse();

      h.notification.release();
      await handling;
      const disabled = await disabling;

      expect(disableFinished).assertTrue();
      expect(disabled.error?.code).assertEqual('INVALID_STATUS_TRANSITION');
      expect((await h.repository.findById('notify-lock'))?.status).assertEqual(ReminderStatus.TRIGGERED);
    });

    it('releases the same-id queue after a failed notification', 0, async () => {
      const h = harness(() => 3000);
      h.notification.failNotify = true;
      await h.repository.save(reminder('retry-after-failure', TriggerType.TIME,
        ReminderStatus.ACTIVE, 2000));
      let firstRejected = false;
      try {
        await h.coordinator.onConditionChanged(
          event('retry-after-failure', TriggerCondition.TIME, true, 3000));
      } catch (_) {
        firstRejected = true;
      }
      expect(firstRejected).assertTrue();

      h.notification.failNotify = false;
      await h.coordinator.onConditionChanged(
        event('retry-after-failure', TriggerCondition.TIME, true, 3001));

      expect(h.notification.notifiedIds.length).assertEqual(1);
      expect((await h.repository.findById('retry-after-failure'))?.status)
        .assertEqual(ReminderStatus.TRIGGERED);
    });
  });
}
