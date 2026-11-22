import { describe, it, expect } from '@ohos/hypium';
import { Reminder } from '../../main/ets/model/Reminder';
import { LocationTriggerMode, ReminderSource, ReminderStatus, TriggerType } from '../../main/ets/model/ReminderEnums';
import { FenceMapping, FenceRegistry } from '../../main/ets/location/platform/LocationPlatform';
import { decideFenceDelivery, FenceDeliveryOutcome } from '../../main/ets/location/extension/FenceDeliveryPolicy';
import { FenceEventHandler, FenceEventResult } from '../../main/ets/location/extension/FenceEventHandler';
import { FenceNotifier } from '../../main/ets/location/extension/FenceNotificationPublisher';
import { FenceReminderStore } from '../../main/ets/location/extension/FenceReminderStore';

class FakeRegistry implements FenceRegistry {
  entries: FenceMapping[] = [];
  failMark: boolean = false;
  cleared: number[] = [];
  private lookup(fenceId: number): FenceMapping | undefined {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].fenceId === fenceId) { return this.entries[i]; }
    }
    return undefined;
  }
  async save(fenceId: number, reminderId: string): Promise<void> {
    this.entries = this.entries.filter((item: FenceMapping) => item.fenceId !== fenceId &&
      item.reminderId !== reminderId);
    this.entries.push({ fenceId: fenceId, reminderId: reminderId });
  }
  async find(fenceId: number): Promise<FenceMapping | undefined> { return this.lookup(fenceId); }
  async findByReminder(reminderId: string): Promise<FenceMapping | undefined> {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].reminderId === reminderId) { return this.entries[i]; }
    }
    return undefined;
  }
  async remove(fenceId: number): Promise<void> {
    this.entries = this.entries.filter((item: FenceMapping) => item.fenceId !== fenceId);
  }
  async removeByReminder(reminderId: string): Promise<void> {
    this.entries = this.entries.filter((item: FenceMapping) => item.reminderId !== reminderId);
  }
  async markDelivered(fenceId: number, at: number): Promise<void> {
    if (this.failMark) { throw new Error('FENCE_REGISTRY_WRITE_FAILED'); }
    const entry = this.lookup(fenceId);
    if (entry === undefined) { throw new Error('FENCE_HANDLER_NOT_FOUND'); }
    entry.lastDeliveredAt = at;
  }
  async clearDelivered(fenceId: number): Promise<void> {
    this.cleared.push(fenceId);
    const entry = this.lookup(fenceId);
    if (entry !== undefined) { entry.lastDeliveredAt = undefined; }
  }
  async list(): Promise<FenceMapping[]> { return this.entries; }
}
class FakeStore implements FenceReminderStore {
  reminders: Reminder[] = [];
  saved: Reminder[] = [];
  failFind: boolean = false;
  failSave: boolean = false;
  async findById(id: string): Promise<Reminder | undefined> {
    if (this.failFind) { throw new Error('FENCE_REMINDER_STORE_UNAVAILABLE'); }
    for (let i = 0; i < this.reminders.length; i++) {
      if (this.reminders[i].id === id) { return this.reminders[i]; }
    }
    return undefined;
  }
  async save(reminder: Reminder): Promise<void> {
    if (this.failSave) { throw new Error('STORE_WRITE_FAILED'); }
    this.saved.push(reminder);
  }
}
class FakeNotifier implements FenceNotifier {
  published: string[] = [];
  fail: boolean = false;
  async publish(reminderId: string, content: string): Promise<void> {
    if (this.fail) { throw new Error('NOTIFICATION_DISABLED'); }
    this.published.push(reminderId);
  }
}
class CountingRemover {
  removed: number[] = [];
  fail: boolean = false;
  async remove(fenceId: number): Promise<void> {
    if (this.fail) { throw new Error('REMOVE_FAILED'); }
    this.removed.push(fenceId);
  }
}

function locationReminder(id: string): Reminder {
  return { id: id, content: '带电脑', triggerType: TriggerType.LOCATION, sceneId: 's',
    locationTriggerMode: LocationTriggerMode.ENTER, status: ReminderStatus.ACTIVE,
    source: ReminderSource.MANUAL, createdAt: 100000 };
}

class Harness {
  registry: FakeRegistry = new FakeRegistry();
  store: FakeStore = new FakeStore();
  notifier: FakeNotifier = new FakeNotifier();
  remover: CountingRemover = new CountingRemover();
  errors: string[] = [];
  now: number = 100000;

  handler(): FenceEventHandler {
    return new FenceEventHandler(this.registry, this.store, this.notifier,
      (fenceId: number): Promise<void> => this.remover.remove(fenceId),
      (): number => this.now,
      (code: string): void => { this.errors.push(code); });
  }
}

export default function fenceExtensionTest() {
  describe('FenceExtension', () => {
    it('decide_gates_by_status_trigger_type_mode_time_and_duplicates', 0, () => {
      const active = locationReminder('r');
      expect(decideFenceDelivery(active, 1000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.DELIVER);
      expect(decideFenceDelivery(active, 1000, undefined, false).outcome).assertEqual(FenceDeliveryOutcome.NOT_ENTER);
      expect(decideFenceDelivery(undefined, 1000, undefined, true).outcome)
        .assertEqual(FenceDeliveryOutcome.REMINDER_NOT_FOUND);
      const done = locationReminder('r');
      done.status = ReminderStatus.TRIGGERED;
      expect(decideFenceDelivery(done, 1000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.NOT_ACTIVE);
      const timed = locationReminder('r');
      timed.triggerType = TriggerType.TIME;
      expect(decideFenceDelivery(timed, 1000, undefined, true).outcome)
        .assertEqual(FenceDeliveryOutcome.NOT_LOCATION_TRIGGER);
      const exit = locationReminder('r');
      exit.locationTriggerMode = LocationTriggerMode.EXIT;
      expect(decideFenceDelivery(exit, 1000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.EXIT_MODE);
      // BOTH: a crossing before the time condition is not a trigger (the V1 BOTH bypass hole).
      const both = locationReminder('r');
      both.triggerType = TriggerType.BOTH;
      both.triggerTime = 2000;
      expect(decideFenceDelivery(both, 1000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.TIME_NOT_REACHED);
      expect(decideFenceDelivery(both, 2000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.DELIVER);
      both.triggerTime = undefined;
      expect(decideFenceDelivery(both, 2000, undefined, true).outcome).assertEqual(FenceDeliveryOutcome.TIME_NOT_REACHED);
      expect(decideFenceDelivery(active, 1000, 900, true).outcome).assertEqual(FenceDeliveryOutcome.ALREADY_DELIVERED);
    });
    it('publishes_once_then_marks_triggered_and_cleans_up', 0, async () => {
      const harness = new Harness();
      harness.store.reminders.push(locationReminder('r'));
      await harness.registry.save(7, 'r');
      const report = await harness.handler().handle(7, true);
      expect(report.result).assertEqual(FenceEventResult.DELIVERED);
      expect(harness.notifier.published.length).assertEqual(1);
      expect(harness.notifier.published[0]).assertEqual('r');
      expect(harness.store.saved.length).assertEqual(1);
      expect(harness.store.saved[0].status).assertEqual(ReminderStatus.TRIGGERED);
      expect(harness.store.saved[0].triggeredAt).assertEqual(100000);
      expect(harness.remover.removed.length).assertEqual(1);
      expect(harness.remover.removed[0]).assertEqual(7);
      expect(harness.registry.entries.length).assertEqual(0);
    });
    it('fails_closed_when_the_reservation_cannot_be_written', 0, async () => {
      const harness = new Harness();
      harness.store.reminders.push(locationReminder('r'));
      await harness.registry.save(7, 'r');
      harness.registry.failMark = true;
      const report = await harness.handler().handle(7, true);
      expect(report.result).assertEqual(FenceEventResult.REGISTRY_WRITE_FAILED);
      expect(harness.notifier.published.length).assertEqual(0);
      expect(harness.remover.removed.length).assertEqual(0);
    });
    it('releases_the_reservation_when_publishing_fails', 0, async () => {
      const harness = new Harness();
      harness.store.reminders.push(locationReminder('r'));
      await harness.registry.save(7, 'r');
      harness.notifier.fail = true;
      const report = await harness.handler().handle(7, true);
      expect(report.result).assertEqual(FenceEventResult.NOTIFY_FAILED);
      expect(harness.registry.cleared.length).assertEqual(1);
      expect(harness.registry.entries[0].lastDeliveredAt === undefined).assertTrue();
      // The fence stays so the next crossing can try again.
      expect(harness.remover.removed.length).assertEqual(0);
    });
    it('skips_duplicates_unknown_fences_and_reminders_that_are_not_ready', 0, async () => {
      const harness = new Harness();
      expect((await harness.handler().handle(9, true)).result).assertEqual(FenceEventResult.NOT_MAPPED);
      harness.store.reminders.push(locationReminder('r'));
      await harness.registry.save(7, 'r');
      harness.store.failFind = true;
      expect((await harness.handler().handle(7, true)).result).assertEqual(FenceEventResult.STORE_FAILED);
      harness.store.failFind = false;
      harness.store.reminders[0].status = ReminderStatus.COMPLETED;
      const skipped = await harness.handler().handle(7, true);
      expect(skipped.result).assertEqual(FenceEventResult.SKIPPED);
      expect(skipped.outcome).assertEqual(FenceDeliveryOutcome.NOT_ACTIVE);
      expect(harness.notifier.published.length).assertEqual(0);
      harness.store.reminders[0].status = ReminderStatus.ACTIVE;
      await harness.registry.markDelivered(7, 99000);
      const duplicate = await harness.handler().handle(7, true);
      expect(duplicate.result).assertEqual(FenceEventResult.SKIPPED);
      expect(duplicate.outcome).assertEqual(FenceDeliveryOutcome.ALREADY_DELIVERED);
      expect(harness.notifier.published.length).assertEqual(0);
    });
    it('delivers_then_reports_a_failed_state_update', 0, async () => {
      const harness = new Harness();
      harness.store.reminders.push(locationReminder('r'));
      await harness.registry.save(7, 'r');
      harness.store.failSave = true;
      const report = await harness.handler().handle(7, true);
      expect(report.result).assertEqual(FenceEventResult.STATE_UPDATE_FAILED);
      // The user already sees the notification, so the fence is still cleaned up.
      expect(harness.notifier.published.length).assertEqual(1);
      expect(harness.remover.removed.length).assertEqual(1);
      expect(harness.registry.entries.length).assertEqual(0);
      expect(harness.errors.length).assertEqual(1);
    });
  });
}
