import { CreateReminderInput } from '../../main/ets/model/CreateReminderInput';
import { describe, it, expect } from '@ohos/hypium';
import { Scene } from '../../main/ets/model/Scene';
import { Reminder } from '../../main/ets/model/Reminder';
import { LocationTriggerMode, ReminderSource, ReminderStatus, TriggerType } from '../../main/ets/model/ReminderEnums';
import { SceneCatalog } from '../../main/ets/location/scene/SceneCatalog';
import { TextStorage } from '../../main/ets/location/repository/TextStorage';
import { LocationPlatform, LocationFix, FenceDelivery, FenceMapping, FenceRegistry } from '../../main/ets/location/platform/LocationPlatform';
import { LocationReminderAdapter, matchesLocationRegistration } from '../../main/ets/location/trigger/LocationReminderAdapter';
import { TriggerEventSink } from '../../main/ets/reminder/contract/TriggerEventSink';
import { TriggerConditionEvent, TriggerCondition } from '../../main/ets/reminder/contract/TriggerConditionEvent';
import { ReminderService } from '../../main/ets/service/ReminderService';
import { InMemoryReminderRepository } from '../../main/ets/repository/InMemoryReminderRepository';
import { TimeTriggerPort } from '../../main/ets/reminder/contract/TimeTriggerPort';
import { TriggerCoordinator } from '../../main/ets/reminder/TriggerCoordinator';
import { ReminderNotificationPort } from '../../main/ets/reminder/contract/ReminderNotificationPort';

class MemoryStorage implements TextStorage {
  value?: string;
  async read(): Promise<string | undefined> { return this.value; }
  async write(value: string): Promise<void> { this.value = value; }
}
class FakePlatform implements LocationPlatform {
  callbacks: Map<number, () => void> = new Map<number, () => void>();
  deliveries: (FenceDelivery | undefined)[] = [];
  next: number = 0;
  ready: boolean = true;
  failAdd: boolean = false;
  emitOnAdd: boolean = false;
  failRemove: boolean = false;
  fix: LocationFix = { latitude: 31, longitude: 121, accuracy: 5, occurredAt: 100000 };
  async checkReady(): Promise<void> { if (!this.ready) { throw new Error('PERMISSION_DENIED'); } }
  async getCurrentPosition(): Promise<LocationFix> { await this.checkReady(); return this.fix; }
  async addFence(scene: Scene, enter: () => void, error: (code: string) => void,
    delivery?: FenceDelivery): Promise<number> {
    if (this.failAdd) { throw new Error('ADD_FAILED'); }
    const id = ++this.next;
    this.callbacks.set(id, enter);
    this.deliveries.push(delivery);
    if (this.emitOnAdd) { enter(); }
    return id;
  }
  async removeFence(id: number): Promise<void> {
    if (this.failRemove) { throw new Error('REMOVE_FAILED'); }
    this.callbacks.delete(id);
  }
  async activeFenceIds(): Promise<number[]> { return Array.from(this.callbacks.keys()); }
  async recoverOrphanFences(registry: FenceRegistry): Promise<void> {}
  seedFence(id: number): void {
    this.callbacks.set(id, () => {});
    // Keep new fence ids above the seeded ones, like the real service does.
    if (id > this.next) { this.next = id; }
  }
  enter(): void { this.callbacks.forEach((callback: () => void) => callback()); }
}
/** Stands in for FenceRegistryStore; the file backed version is exercised on device. */
class MemoryFenceRegistry implements FenceRegistry {
  entries: FenceMapping[] = [];
  failSave: boolean = false;
  failRemove: boolean = false;
  private lookup(fenceId: number): FenceMapping | undefined {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].fenceId === fenceId) { return this.entries[i]; }
    }
    return undefined;
  }
  async save(fenceId: number, reminderId: string): Promise<void> {
    if (this.failSave) { throw new Error('FENCE_REGISTRY_WRITE_FAILED'); }
    const kept: FenceMapping[] = this.entries.filter((item: FenceMapping) => item.fenceId !== fenceId &&
      item.reminderId !== reminderId);
    kept.push({ fenceId: fenceId, reminderId: reminderId });
    this.entries = kept;
  }
  async find(fenceId: number): Promise<FenceMapping | undefined> { return this.lookup(fenceId); }
  async findByReminder(reminderId: string): Promise<FenceMapping | undefined> {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].reminderId === reminderId) { return this.entries[i]; }
    }
    return undefined;
  }
  async remove(fenceId: number): Promise<void> {
    if (this.failRemove) { throw new Error('FENCE_REGISTRY_WRITE_FAILED'); }
    this.entries = this.entries.filter((item: FenceMapping) => item.fenceId !== fenceId);
  }
  async removeByReminder(reminderId: string): Promise<void> {
    if (this.failRemove) { throw new Error('FENCE_REGISTRY_WRITE_FAILED'); }
    this.entries = this.entries.filter((item: FenceMapping) => item.reminderId !== reminderId);
  }
  async markDelivered(fenceId: number, at: number): Promise<void> {
    const entry = this.lookup(fenceId);
    if (entry === undefined) { throw new Error('FENCE_HANDLER_NOT_FOUND'); }
    entry.lastDeliveredAt = at;
  }
  async clearDelivered(fenceId: number): Promise<void> {
    const entry = this.lookup(fenceId);
    if (entry !== undefined) { entry.lastDeliveredAt = undefined; }
  }
  async list(): Promise<FenceMapping[]> { return this.entries.map((item: FenceMapping) => item); }
}
class RecordingSink implements TriggerEventSink {
  events: TriggerConditionEvent[] = [];
  fail: boolean = false;
  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    if (this.fail) { throw new Error('SINK_FAILED'); }
    this.events.push(event);
  }
}
class SlowRepository extends InMemoryReminderRepository {
  releaseSave: () => void = () => {};
  block: boolean = true;
  async save(value: Reminder): Promise<void> {
    if (this.block && value.status === ReminderStatus.ACTIVE) {
      await new Promise<void>((resolve: () => void) => { this.releaseSave = resolve; });
    }
    await super.save(value);
  }
}
class DelayedSink implements TriggerEventSink {
  events: TriggerConditionEvent[] = [];
  releaseFirst: () => void = () => {};
  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    this.events.push(event);
    if (this.events.length === 1) {
      await new Promise<void>((resolve: () => void) => { this.releaseFirst = resolve; });
    }
  }
}
class ForwardSink implements TriggerEventSink {
  target?: TriggerCoordinator;
  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    if (this.target === undefined) { throw new Error('NOT_READY'); }
    await this.target.onConditionChanged(event);
  }
}
class NoTime implements TimeTriggerPort {
  async schedule(reminder: Reminder): Promise<void> {}
  async cancel(id: string): Promise<void> {}
}
class RecordingNotification implements ReminderNotificationPort {
  calls: number = 0;
  fail: boolean = false;
  async notify(reminder: Reminder): Promise<void> {
    if (this.fail) { throw new Error('NOTIFICATION_FAILED'); }
    this.calls++;
  }
}
function reminder(id: string): Reminder {
  return { id: id, content: '带电脑', triggerType: TriggerType.LOCATION, sceneId: 's',
    locationTriggerMode: LocationTriggerMode.ENTER, status: ReminderStatus.ACTIVE,
    source: ReminderSource.MANUAL, createdAt: 100000 };
}
async function makeCatalog(): Promise<SceneCatalog> {
  const catalog = new SceneCatalog(new MemoryStorage(), () => 100000, () => 's', async () => false);
  await catalog.create({ name: '实验室', latitude: 31, longitude: 121, radius: 100 });
  return catalog;
}

async function alwaysReady(expected: Reminder): Promise<boolean> { return true; }
function probeFor(repository: InMemoryReminderRepository): (expected: Reminder) => Promise<boolean> {
  return async (expected: Reminder): Promise<boolean> => {
    return matchesLocationRegistration(await repository.findById(expected.id), expected);
  };
}

async function drain(): Promise<void> {
  await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 30); });
}

export default function locationAdapterTest() {
  describe('LocationReminderAdapter', () => {
    it('construction_is_quiet_and_start_checks_permission', 0, async () => {
      const platform = new FakePlatform();
      platform.ready = false;
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, new RecordingSink(), () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      expect(platform.callbacks.size).assertEqual(0);
      let failed: boolean = false;
      try { await adapter.start(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      failed = false;
      try { await adapter.register(reminder('r')); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('register_auto_starts_without_explicit_start', 0, async () => {
      const platform = new FakePlatform();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, new RecordingSink(), () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.register(reminder('r'));
      expect(platform.callbacks.size).assertEqual(1);
      await adapter.stop();
    });
    it('registers_idempotently_and_ignores_late_callback_after_unregister', 0, async () => {
      const platform = new FakePlatform();
      const sink = new RecordingSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, sink, () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      await adapter.register(reminder('r'));
      await adapter.register(reminder('r'));
      expect(platform.callbacks.size).assertEqual(1);
      const stale = platform.callbacks.get(1);
      await adapter.unregister('r');
      await adapter.unregister('r');
      if (stale !== undefined) { stale(); }
      await drain();
      expect(sink.events.length).assertEqual(0);
      expect(platform.callbacks.size).assertEqual(0);
    });
    it('shared_scene_keeps_other_reminders_registered', 0, async () => {
      const platform = new FakePlatform();
      const sink = new RecordingSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, sink, () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      await adapter.register(reminder('a'));
      await adapter.register(reminder('b'));
      await adapter.unregister('a');
      platform.enter();
      await drain();
      expect(sink.events.length).assertEqual(1);
      expect(sink.events[0].reminderId).assertEqual('b');
      expect(sink.events[0].condition).assertEqual(TriggerCondition.LOCATION);
      expect(sink.events[0].satisfied).assertTrue();
      expect(sink.events[0].occurredAt).assertEqual(100000);
      await adapter.stop();
    });
    it('cleans_reservation_after_failed_registration_and_retries_failed_removal', 0, async () => {
      const catalog = await makeCatalog();
      const platform = new FakePlatform();
      const adapter = new LocationReminderAdapter(catalog, platform, new RecordingSink(), () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      platform.failAdd = true;
      let failed: boolean = false;
      try { await adapter.register(reminder('r')); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      await catalog.update('s', { name: '实验室2', latitude: 31, longitude: 121, radius: 100 });
      platform.failAdd = false;
      await adapter.register(reminder('r'));
      platform.failRemove = true;
      failed = false;
      try { await adapter.unregister('r'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      platform.failRemove = false;
      await adapter.unregister('r');
      expect(platform.callbacks.size).assertEqual(0);
      await adapter.stop();
    });
    it('reports_failed_events_and_retries_without_swallowing_them', 0, async () => {
      const platform = new FakePlatform();
      const sink = new RecordingSink();
      const failures: string[] = [];
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, sink, () => 100000,
        (code: string) => { failures.push(code); }, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      await adapter.register(reminder('r'));
      sink.fail = true;
      platform.enter();
      await drain();
      expect(failures.length > 0).assertTrue();
      expect(sink.events.length).assertEqual(0);
      sink.fail = false;
      await adapter.retryPendingEvents();
      expect(sink.events.length).assertEqual(1);
      await adapter.stop();
    });
    it('keeps_latest_entry_while_previous_entry_is_processing', 0, async () => {
      let now: number = 100000;
      const platform = new FakePlatform();
      const sink = new DelayedSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, sink, () => now, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      await adapter.register(reminder('r'));
      platform.enter();
      await drain();
      now = 100001;
      platform.enter();
      sink.releaseFirst();
      await drain();
      expect(sink.events.length).assertEqual(2);
      expect(sink.events[1].occurredAt).assertEqual(100001);
      await adapter.stop();
    });
    it('rejects_stale_inaccurate_and_unavailable_position', 0, async () => {
      const platform = new FakePlatform();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, new RecordingSink(), () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      expect(await adapter.isInsideScene('s')).assertTrue();
      platform.fix = { latitude: 32, longitude: 121, accuracy: 5, occurredAt: 100000 };
      expect(await adapter.isInsideScene('s')).assertFalse();
      platform.fix = { latitude: 31, longitude: 121, accuracy: 500, occurredAt: 100000 };
      let failed: boolean = false;
      try { await adapter.isInsideScene('s'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      platform.fix = { latitude: 31, longitude: 121, accuracy: 5, occurredAt: 1 };
      failed = false;
      try { await adapter.isInsideScene('s'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      platform.ready = false;
      failed = false;
      try { await adapter.isInsideScene('s'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('rejects_exit_time_only_and_unknown_scene', 0, async () => {
      const adapter = new LocationReminderAdapter(await makeCatalog(), new FakePlatform(), new RecordingSink(), () => 100000, () => {}, alwaysReady, new MemoryFenceRegistry());
      await adapter.start();
      const input = reminder('r');
      input.locationTriggerMode = LocationTriggerMode.EXIT;
      let failed: boolean = false;
      try { await adapter.register(input); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      input.locationTriggerMode = LocationTriggerMode.ENTER;
      input.triggerType = TriggerType.TIME;
      failed = false;
      try { await adapter.register(input); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      input.triggerType = TriggerType.LOCATION;
      input.sceneId = 'missing';
      failed = false;
      try { await adapter.register(input); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('both_requires_time_and_current_location_and_retries_notification_failure', 0, async () => {
      let now: number = 100000;
      const platform = new FakePlatform();
      const repository = new InMemoryReminderRepository();
      const notifications = new RecordingNotification();
      const forward = new ForwardSink();
      const failures: string[] = [];
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, forward, () => now,
        (code: string) => { failures.push(code); }, probeFor(repository), new MemoryFenceRegistry());
      const service = new ReminderService(repository, new NoTime(), adapter, () => now, () => 'both');
      const coordinator = new TriggerCoordinator(service, adapter, notifications, () => now);
      forward.target = coordinator;
      await adapter.start();
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.BOTH,
        triggerTime: 110000, sceneId: 's', source: ReminderSource.MANUAL };
      expect((await service.create(input)).success).assertTrue();
      platform.enter();
      await drain();
      expect(notifications.calls).assertEqual(0);
      now = 110000;
      platform.fix = { latitude: 32, longitude: 121, accuracy: 5, occurredAt: now };
      await coordinator.onConditionChanged({ reminderId: 'both', condition: TriggerCondition.TIME, satisfied: true, occurredAt: now });
      expect(notifications.calls).assertEqual(0);
      platform.fix = { latitude: 31, longitude: 121, accuracy: 5, occurredAt: now };
      notifications.fail = true;
      platform.enter();
      await drain();
      expect(failures.length > 0).assertTrue();
      expect((await service.findById('both')).data?.status).assertEqual(ReminderStatus.ACTIVE);
      notifications.fail = false;
      await adapter.retryPendingEvents();
      expect(notifications.calls).assertEqual(1);
      expect((await service.findById('both')).data?.status).assertEqual(ReminderStatus.TRIGGERED);
      expect(platform.callbacks.size).assertEqual(0);
    });
    it('keeps_entry_until_slow_create_has_been_saved', 0, async () => {
      const platform = new FakePlatform();
      platform.emitOnAdd = true;
      const repository = new SlowRepository();
      const notifications = new RecordingNotification();
      const forward = new ForwardSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, forward, () => 100000, () => {}, probeFor(repository), new MemoryFenceRegistry());
      const service = new ReminderService(repository, new NoTime(), adapter, () => 100000, () => 'slow');
      forward.target = new TriggerCoordinator(service, adapter, notifications, () => 100000);
      await adapter.start();
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.LOCATION, sceneId: 's', source: ReminderSource.MANUAL };
      const creation = service.create(input);
      await drain();
      expect(notifications.calls).assertEqual(0);
      repository.block = false;
      repository.releaseSave();
      expect((await creation).success).assertTrue();
      await adapter.retryPendingEvents();
      expect(notifications.calls).assertEqual(1);
      expect((await service.findById('slow')).data?.status).assertEqual(ReminderStatus.TRIGGERED);
      await adapter.stop();
    });
    it('keeps_entry_until_slow_enable_has_been_saved', 0, async () => {
      const platform = new FakePlatform();
      platform.emitOnAdd = true;
      const repository = new SlowRepository();
      const old = reminder('enable');
      old.status = ReminderStatus.DISABLED;
      await repository.save(old);
      const notifications = new RecordingNotification();
      const forward = new ForwardSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, forward, () => 100000, () => {}, probeFor(repository), new MemoryFenceRegistry());
      const service = new ReminderService(repository, new NoTime(), adapter, () => 100000, () => 'unused');
      forward.target = new TriggerCoordinator(service, adapter, notifications, () => 100000);
      await adapter.start();
      const enabling = service.enable('enable');
      await drain();
      expect(notifications.calls).assertEqual(0);
      repository.block = false;
      repository.releaseSave();
      expect((await enabling).success).assertTrue();
      await adapter.retryPendingEvents();
      expect(notifications.calls).assertEqual(1);
      await adapter.stop();
    });
    it('waits_for_new_trigger_fields_during_same_scene_update', 0, async () => {
      const platform = new FakePlatform();
      platform.emitOnAdd = true;
      const repository = new SlowRepository();
      repository.block = false;
      const old = reminder('update');
      old.triggerType = TriggerType.BOTH;
      old.triggerTime = 200000;
      await repository.save(old);
      repository.block = true;
      const notifications = new RecordingNotification();
      const forward = new ForwardSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, forward, () => 100000, () => {}, probeFor(repository), new MemoryFenceRegistry());
      const service = new ReminderService(repository, new NoTime(), adapter, () => 100000, () => 'unused');
      forward.target = new TriggerCoordinator(service, adapter, notifications, () => 100000);
      await adapter.start();
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.LOCATION,
        sceneId: 's', source: ReminderSource.MANUAL };
      const updating = service.update('update', input);
      await drain();
      expect(notifications.calls).assertEqual(0);
      repository.block = false;
      repository.releaseSave();
      expect((await updating).success).assertTrue();
      await adapter.retryPendingEvents();
      expect(notifications.calls).assertEqual(1);
      await adapter.stop();
    });
    it('real_coordinator_notifies_once_and_cleans_up_without_self_wait', 0, async () => {
      const platform = new FakePlatform();
      const repository = new InMemoryReminderRepository();
      const notifications = new RecordingNotification();
      const forward = new ForwardSink();
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, forward, () => 100000, () => {}, probeFor(repository), new MemoryFenceRegistry());
      const service = new ReminderService(repository, new NoTime(), adapter, () => 100000, () => 'r');
      forward.target = new TriggerCoordinator(service, adapter, notifications, () => 100000);
      await adapter.start();
      const input: CreateReminderInput = { content: '带电脑', triggerType: TriggerType.LOCATION, sceneId: 's', source: ReminderSource.MANUAL };
      const created = await service.create(input);
      expect(created.success).assertTrue();
      platform.enter();
      platform.enter();
      await drain();
      expect(notifications.calls).assertEqual(1);
      expect((await service.findById('r')).data?.status).assertEqual(ReminderStatus.TRIGGERED);
      expect(platform.callbacks.size).assertEqual(0);
    });
    it('persists_each_fence_mapping_and_passes_the_configured_delivery', 0, async () => {
      const platform = new FakePlatform();
      const registry = new MemoryFenceRegistry();
      const catalog = await makeCatalog();
      const adapter = new LocationReminderAdapter(catalog, platform, new RecordingSink(), () => 100000, () => {},
        alwaysReady, registry, { fenceExtensionAbilityName: 'LocationFenceAbility' });
      await adapter.register(reminder('r'));
      expect(registry.entries.length).assertEqual(1);
      expect(registry.entries[0].fenceId).assertEqual(1);
      expect(registry.entries[0].reminderId).assertEqual('r');
      expect(platform.deliveries[0]?.fenceExtensionAbilityName).assertEqual('LocationFenceAbility');
      await adapter.unregister('r');
      expect(registry.entries.length).assertEqual(0);
    });
    it('rolls_back_the_fence_when_the_mapping_cannot_be_written', 0, async () => {
      const platform = new FakePlatform();
      const registry = new MemoryFenceRegistry();
      registry.failSave = true;
      const failures: string[] = [];
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, new RecordingSink(),
        () => 100000, (code: string) => { failures.push(code); }, alwaysReady, registry);
      let code: string = '';
      try { await adapter.register(reminder('r')); } catch (error) { code = (error as Error).message; }
      // A storage failure must not be reported as a fence failure, and the fence must not leak.
      expect(code).assertEqual('FENCE_REGISTRY_WRITE_FAILED');
      expect(platform.callbacks.size).assertEqual(0);
      registry.failSave = false;
      await adapter.register(reminder('r'));
      expect(platform.callbacks.size).assertEqual(1);
      await adapter.stop();
    });
    it('removes_the_fence_through_the_mapping_after_a_process_restart', 0, async () => {
      const platform = new FakePlatform();
      const registry = new MemoryFenceRegistry();
      const catalog = await makeCatalog();
      const first = new LocationReminderAdapter(catalog, platform, new RecordingSink(), () => 100000, () => {},
        alwaysReady, registry);
      await first.register(reminder('r'));
      expect(platform.callbacks.size).assertEqual(1);
      // A new process: no in-memory registrations, only the durable mapping.
      const second = new LocationReminderAdapter(catalog, platform, new RecordingSink(), () => 100000, () => {},
        alwaysReady, registry);
      await second.unregister('r');
      expect(platform.callbacks.size).assertEqual(0);
      expect(registry.entries.length).assertEqual(0);
    });
    it('reconcile_drops_orphan_fences_and_restores_missing_ones', 0, async () => {
      const platform = new FakePlatform();
      const registry = new MemoryFenceRegistry();
      const catalog = await makeCatalog();
      // Fence 41 belongs to a deleted reminder, fence 42 to a reminder that is still active.
      await registry.save(41, 'gone');
      await registry.save(42, 'live');
      platform.seedFence(41);
      platform.seedFence(42);
      const adapter = new LocationReminderAdapter(catalog, platform, new RecordingSink(), () => 100000, () => {},
        alwaysReady, registry);
      const live = reminder('live');
      await adapter.reconcile([live]);
      expect(registry.entries.length).assertEqual(1);
      expect(registry.entries[0].reminderId).assertEqual('live');
      // Without the extension the in-process callback is the only delivery path, so the fence is
      // recreated (new id 43) instead of being adopted from the dead process.
      expect(registry.entries[0].fenceId).assertEqual(43);
      expect(platform.callbacks.has(41)).assertFalse();
      expect(platform.callbacks.has(42)).assertFalse();
      expect(platform.callbacks.has(43)).assertTrue();
      await adapter.stop();
    });
    it('reconcile_keeps_extension_fences_without_readding_them', 0, async () => {
      const platform = new FakePlatform();
      const registry = new MemoryFenceRegistry();
      await registry.save(42, 'live');
      platform.seedFence(42);
      const adapter = new LocationReminderAdapter(await makeCatalog(), platform, new RecordingSink(),
        () => 100000, () => {}, alwaysReady, registry, { fenceExtensionAbilityName: 'LocationFenceAbility' });
      await adapter.reconcile([reminder('live')]);
      // The extension delivers for this fence, so adopting it is exactly right.
      expect(registry.entries.length).assertEqual(1);
      expect(registry.entries[0].fenceId).assertEqual(42);
      expect(platform.callbacks.has(42)).assertTrue();
      expect(platform.deliveries.length).assertEqual(0);
      await adapter.stop();
    });
  });
}
