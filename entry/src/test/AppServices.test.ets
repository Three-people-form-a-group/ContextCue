import { describe, it, expect } from '@ohos/hypium';
import { AppServiceRegistry, getAppServices } from '../main/ets/app/AppServiceRegistry';
import { initializeAppServices } from '../main/ets/app/AppBootstrap';
import { AppServices, AppRuntimeMode, createAppServices } from '../main/ets/app/AppServices';
import { createDevelopmentServices } from '../main/ets/app/DevelopmentServices';
import { FakeAIModelProvider } from '../main/ets/ai/provider/FakeAIModelProvider';
import { AIParseStatus } from '../main/ets/ai/model/AIParseResult';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { InMemoryTimetableRepository } from '../main/ets/timetable/repository/InMemoryTimetableRepository';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../main/ets/reminder/contract/ReminderNotificationPort';
import { SceneResolver, SceneResolveResult, SceneResolveStatus } from '../main/ets/reminder/contract/SceneResolver';
import { TriggerEventSink } from '../main/ets/reminder/contract/TriggerEventSink';
import { TriggerCondition } from '../main/ets/reminder/contract/TriggerConditionEvent';

class TestTime implements TimeTriggerPort {
  async schedule(_reminder: Reminder): Promise<void> {}
  async cancel(_id: string): Promise<void> {}
}

class TestLocation implements LocationTriggerPort, SceneResolver {
  inside: boolean = false;
  async register(_reminder: Reminder): Promise<void> {}
  async unregister(_id: string): Promise<void> {}
  async isInsideScene(id: string): Promise<boolean> { return id === 'lab' && this.inside; }
  async resolveByName(_name: string): Promise<SceneResolveResult> {
    return { status: SceneResolveStatus.RESOLVED, match: { id: 'lab', name: '实验室' }, candidates: [] };
  }
}

class TestNotification implements ReminderNotificationPort {
  sent: string[] = [];
  fail: boolean = false;
  async notify(reminder: Reminder): Promise<void> {
    if (this.fail) { throw new Error('notification unavailable'); }
    this.sent.push(reminder.id);
  }
}

class CompositionFixture {
  now: number = 1000;
  sequence: number = 0;
  timeSink?: TriggerEventSink;
  locationSink?: TriggerEventSink;
  location: TestLocation = new TestLocation();
  notification: TestNotification = new TestNotification();
  services: AppServices;
  constructor() {
    const fixtures = new Map<string, string>();
    fixtures.set('到实验室带电脑',
      '{"content":"带电脑","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
    this.services = createAppServices({
      mode: AppRuntimeMode.INTEGRATED,
      repository: new InMemoryReminderRepository(),
      timetableRepository: new InMemoryTimetableRepository(),
      createTimePort: (sink: TriggerEventSink): TimeTriggerPort => {
        this.timeSink = sink;
        return new TestTime();
      },
      createLocationPort: (sink: TriggerEventSink): LocationTriggerPort => {
        this.locationSink = sink;
        return this.location;
      },
      notificationPort: this.notification,
      sceneResolver: this.location,
      aiProvider: new FakeAIModelProvider(fixtures),
      now: () => this.now,
      newId: () => 'composed-' + (++this.sequence).toString()
    });
  }
  async emit(condition: TriggerCondition, id: string): Promise<void> {
    const sink = condition === TriggerCondition.TIME ? this.timeSink : this.locationSink;
    if (sink === undefined) { throw new Error('missing event connection'); }
    await sink.onConditionChanged({ reminderId: id, condition: condition, satisfied: true, occurredAt: this.now });
  }
}

export default function appServicesTest() {
  describe('AppServices', () => {
    it('fails clearly before startup initialization', 0, () => {
      const registry = new AppServiceRegistry();
      let failed = false;
      try { registry.get(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });

    it('repeated startup preserves shared page data and does not rerun factory', 0, async () => {
      const registry = new AppServiceRegistry();
      const first = registry.initialize(() => createDevelopmentServices());
      const result = await first.reminderService.create({ content: '带电脑', triggerType: TriggerType.TIME,
        triggerTime: Date.now() + 60000, source: ReminderSource.MANUAL });
      expect(result.success).assertTrue();
      let reran = false;
      const second = registry.initialize(() => { reran = true; return createDevelopmentServices(); });
      expect(reran).assertFalse();
      expect(second === registry.get()).assertTrue();
      expect((await second.reminderService.findAll()).data?.length).assertEqual(1);
    });

    it('failed startup publishes nothing and can be retried', 0, () => {
      const registry = new AppServiceRegistry();
      let failed = false;
      try { registry.initialize((): AppServices => { throw new Error('dependency unavailable'); }); }
      catch (_) { failed = true; }
      expect(failed).assertTrue();
      let unavailable = false;
      try { registry.get(); } catch (_) { unavailable = true; }
      expect(unavailable).assertTrue();
      registry.initialize(() => createDevelopmentServices());
      expect(registry.get().mode).assertEqual(AppRuntimeMode.DEVELOPMENT);
    });

    it('rejects recursive initialization and allows a later clean startup', 0, () => {
      const registry = new AppServiceRegistry();
      let failed = false;
      try { registry.initialize(() => registry.initialize(() => createDevelopmentServices())); }
      catch (_) { failed = true; }
      expect(failed).assertTrue();
      registry.initialize(() => createDevelopmentServices());
      expect(registry.get().mode).assertEqual(AppRuntimeMode.DEVELOPMENT);
    });

    it('Ability bootstrap makes the same services available through the page accessor', 0, () => {
      const first = initializeAppServices();
      expect(getAppServices() === first).assertTrue();
      expect(initializeAppServices() === first).assertTrue();
    });

    it('time adapter events use the same service as pages and notify once', 0, async () => {
      const fixture = new CompositionFixture();
      const created = await fixture.services.reminderService.create({ content: '开会', triggerType: TriggerType.TIME,
        triggerTime: 2000, source: ReminderSource.MANUAL });
      expect(created.success).assertTrue();
      fixture.now = 2000;
      await fixture.emit(TriggerCondition.TIME, 'composed-1');
      await fixture.emit(TriggerCondition.TIME, 'composed-1');
      expect((await fixture.services.reminderService.findById('composed-1')).data?.status)
        .assertEqual(ReminderStatus.TRIGGERED);
      expect(fixture.notification.sent.length).assertEqual(1);
      expect(fixture.notification.sent[0]).assertEqual('composed-1');
    });

    it('both adapters feed one coordinator and notification failure leaves active data', 0, async () => {
      const fixture = new CompositionFixture();
      const created = await fixture.services.reminderService.create({ content: '带电脑', triggerType: TriggerType.BOTH,
        triggerTime: 2000, sceneId: 'lab', source: ReminderSource.MANUAL });
      expect(created.success).assertTrue();
      fixture.now = 2000;
      await fixture.emit(TriggerCondition.TIME, 'composed-1');
      expect((await fixture.services.reminderService.findById('composed-1')).data?.status)
        .assertEqual(ReminderStatus.ACTIVE);
      fixture.location.inside = true;
      fixture.notification.fail = true;
      let failed = false;
      try { await fixture.emit(TriggerCondition.LOCATION, 'composed-1'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      expect((await fixture.services.reminderService.findById('composed-1')).data?.status)
        .assertEqual(ReminderStatus.ACTIVE);
      fixture.notification.fail = false;
      await fixture.emit(TriggerCondition.LOCATION, 'composed-1');
      expect((await fixture.services.reminderService.findById('composed-1')).data?.status)
        .assertEqual(ReminderStatus.TRIGGERED);
    });

    it('AI uses injected scene resolver and only confirmation saves to shared service', 0, async () => {
      const fixture = new CompositionFixture();
      const parsed = await fixture.services.aiService.parseReminder('到实验室带电脑',
        { now: 1000, timeZone: 'Asia/Shanghai', locale: 'zh-CN' });
      expect(parsed.status).assertEqual(AIParseStatus.READY);
      expect(parsed.draft?.sceneId).assertEqual('lab');
      expect((await fixture.services.reminderService.findAll()).data?.length).assertEqual(0);
      if (parsed.draft === undefined) { throw new Error('missing draft'); }
      expect((await fixture.services.reminderService.create(parsed.draft)).success).assertTrue();
      expect((await fixture.services.reminderService.findAll()).data?.length).assertEqual(1);
    });

    it('development supports CRUD with distinct IDs and does not invent AI results', 0, async () => {
      const services = createDevelopmentServices();
      expect(services.mode).assertEqual(AppRuntimeMode.DEVELOPMENT);
      const first = await services.reminderService.create({ content: '一', triggerType: TriggerType.TIME,
        triggerTime: Date.now() + 60000, source: ReminderSource.MANUAL });
      const second = await services.reminderService.create({ content: '二', triggerType: TriggerType.TIME,
        triggerTime: Date.now() + 60000, source: ReminderSource.MANUAL });
      expect(first.success).assertTrue();
      expect(second.success).assertTrue();
      expect(first.data?.id === second.data?.id).assertFalse();
      if (first.data === undefined) { throw new Error('missing reminder'); }
      expect((await services.reminderService.disable(first.data.id)).success).assertTrue();
      expect((await services.reminderService.delete(first.data.id)).success).assertTrue();
      expect((await services.reminderService.findAll()).data?.length).assertEqual(1);
      const parsed = await services.aiService.parseReminder('任意一句话',
        { now: Date.now(), timeZone: 'Asia/Shanghai', locale: 'zh-CN' });
      expect(parsed.status).assertEqual(AIParseStatus.FAILED);
      expect((await services.reminderService.findAll()).data?.length).assertEqual(1);
    });
  });
}
