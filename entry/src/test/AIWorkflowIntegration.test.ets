import { describe, it, expect } from '@ohos/hypium';
import { DefaultAIService } from '../main/ets/ai/DefaultAIService';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { AIParseOutcome, AIParseStatus } from '../main/ets/ai/model/AIParseResult';
import { FakeAIModelProvider } from '../main/ets/ai/provider/FakeAIModelProvider';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus } from '../main/ets/model/ReminderEnums';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { ReminderService } from '../main/ets/service/ReminderService';
import { TriggerCoordinator } from '../main/ets/reminder/TriggerCoordinator';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../main/ets/reminder/contract/ReminderNotificationPort';
import { TriggerCondition, TriggerConditionEvent } from '../main/ets/reminder/contract/TriggerConditionEvent';
import { SceneResolver, SceneResolveResult, SceneResolveStatus } from '../main/ets/reminder/contract/SceneResolver';

class WorkflowTimePort implements TimeTriggerPort {
  scheduled: string[] = [];
  cancelled: string[] = [];
  async schedule(reminder: Reminder): Promise<void> { this.scheduled.push(reminder.id); }
  async cancel(id: string): Promise<void> { this.cancelled.push(id); }
}

class WorkflowLocationPort implements LocationTriggerPort, SceneResolver {
  registered: string[] = [];
  unregistered: string[] = [];
  inside: boolean = false;
  failRegister: boolean = false;
  resolveStatus: SceneResolveStatus = SceneResolveStatus.RESOLVED;

  async register(reminder: Reminder): Promise<void> {
    if (this.failRegister) { throw new Error('registration failed'); }
    this.registered.push(reminder.id);
  }
  async unregister(id: string): Promise<void> { this.unregistered.push(id); }
  async isInsideScene(sceneId: string): Promise<boolean> { return sceneId === 'lab-1' && this.inside; }
  async resolveByName(_name: string): Promise<SceneResolveResult> {
    if (this.resolveStatus !== SceneResolveStatus.RESOLVED) {
      return { status: this.resolveStatus, candidates: [] };
    }
    return { status: SceneResolveStatus.RESOLVED, match: { id: 'lab-1', name: '实验室' }, candidates: [] };
  }
}

class WorkflowNotificationPort implements ReminderNotificationPort {
  reminders: Reminder[] = [];
  failNotify: boolean = false;
  async notify(reminder: Reminder): Promise<void> {
    if (this.failNotify) { throw new Error('notification failed'); }
    this.reminders.push(reminder);
  }
}

// Tests simulate the caller's explicit confirmation. Parsing alone never saves a reminder.
class Workflow {
  now: number = 1000;
  repository: InMemoryReminderRepository = new InMemoryReminderRepository();
  time: WorkflowTimePort = new WorkflowTimePort();
  location: WorkflowLocationPort = new WorkflowLocationPort();
  notification: WorkflowNotificationPort = new WorkflowNotificationPort();
  service: ReminderService;
  coordinator: TriggerCoordinator;
  ai: DefaultAIService;

  constructor(rawResponse: string) {
    const fixtures = new Map<string, string>();
    fixtures.set('明天下午两点去实验室，提醒我带电脑。', rawResponse);
    this.ai = new DefaultAIService(new FakeAIModelProvider(fixtures), this.location);
    this.service = new ReminderService(this.repository, this.time, this.location, () => this.now, () => 'ai-1');
    this.coordinator = new TriggerCoordinator(this.service, this.location, this.notification, () => this.now);
  }

  async parse(): Promise<AIParseOutcome> {
    const context: AIParseContext = { now: this.now, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };
    return this.ai.parseReminder('明天下午两点去实验室，提醒我带电脑。', context);
  }

  async confirm(outcome: AIParseOutcome): Promise<void> {
    if (outcome.status !== AIParseStatus.READY || outcome.draft === undefined) {
      throw new Error('Not a confirmable draft');
    }
    const created = await this.service.create(outcome.draft);
    expect(created.success).assertTrue();
    expect(created.data?.source).assertEqual(ReminderSource.AI);
  }

  async emit(condition: TriggerCondition): Promise<void> {
    const event: TriggerConditionEvent = {
      reminderId: 'ai-1', condition: condition, satisfied: true, occurredAt: this.now
    };
    await this.coordinator.onConditionChanged(event);
  }
}

export default function aiWorkflowIntegrationTest() {
  describe('aiWorkflowIntegrationTest', () => {
    it('keeps READY parsing side effect free until explicit confirmation', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"BOTH","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":"实验室","ambiguous":false}');
      const parsed = await w.parse();
      expect(parsed.status).assertEqual(AIParseStatus.READY);
      expect((await w.repository.findAll()).length).assertEqual(0);
      expect(w.time.scheduled.length).assertEqual(0);
      expect(w.location.registered.length).assertEqual(0);
      expect(w.notification.reminders.length).assertEqual(0);
      await w.confirm(parsed);
      expect(w.time.scheduled[0]).assertEqual('ai-1');
      expect(w.location.registered[0]).assertEqual('ai-1');
      expect((await w.service.findById('ai-1')).data?.sceneId).assertEqual('lab-1');
    });

    it('integrates AI TIME creation delivery and user completion', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"TIME","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":null,"ambiguous":false}');
      await w.confirm(await w.parse());
      expect(w.location.registered.length).assertEqual(0);
      await w.emit(TriggerCondition.TIME);
      expect(w.notification.reminders.length).assertEqual(0);
      w.now = 2000;
      await w.emit(TriggerCondition.TIME);
      await w.emit(TriggerCondition.TIME);
      expect(w.notification.reminders.length).assertEqual(1);
      expect(w.notification.reminders[0].content).assertEqual('带电脑');
      const triggered = (await w.service.findById('ai-1')).data;
      expect(triggered?.status).assertEqual(ReminderStatus.TRIGGERED);
      expect(triggered?.completedAt).assertUndefined();
      expect(w.time.cancelled[0]).assertEqual('ai-1');
      w.now = 2500;
      const completed = await w.service.complete('ai-1');
      expect(completed.data?.status).assertEqual(ReminderStatus.COMPLETED);
      expect(completed.data?.completedAt).assertEqual(2500);
    });

    it('integrates AI LOCATION with resolved scene and current location', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
      await w.confirm(await w.parse());
      expect(w.time.scheduled.length).assertEqual(0);
      expect(w.location.registered[0]).assertEqual('ai-1');
      await w.emit(TriggerCondition.LOCATION);
      expect(w.notification.reminders.length).assertEqual(0);
      w.location.inside = true;
      await w.emit(TriggerCondition.LOCATION);
      expect(w.notification.reminders.length).assertEqual(1);
      expect(w.location.unregistered[0]).assertEqual('ai-1');
      expect((await w.service.findById('ai-1')).data?.status).assertEqual(ReminderStatus.TRIGGERED);
    });

    it('integrates BOTH without retaining an early historical scene entry', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"BOTH","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":"实验室","ambiguous":false}');
      await w.confirm(await w.parse());
      w.location.inside = true;
      await w.emit(TriggerCondition.LOCATION);
      w.location.inside = false;
      w.now = 2000;
      await w.emit(TriggerCondition.TIME);
      expect(w.notification.reminders.length).assertEqual(0);
      w.location.inside = true;
      w.now = 2100;
      await w.emit(TriggerCondition.LOCATION);
      await w.emit(TriggerCondition.TIME);
      expect(w.notification.reminders.length).assertEqual(1);
      expect((await w.service.findById('ai-1')).data?.triggeredAt).assertEqual(2100);
    });

    it('allows a draft whose time expired while the user was confirming', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"TIME","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":null,"ambiguous":false}');
      const parsed = await w.parse();
      if (parsed.draft === undefined) { throw new Error('Expected draft'); }
      w.now = 3000;
      const created = await w.service.create(parsed.draft);
      // 2026-11-15 起允许记录过去时间：保存成功，进入待办（逾期）而不是被拒绝
      expect(created.success).assertTrue();
      expect((await w.repository.findAll()).length).assertEqual(1);
    });

    it('does not persist unresolved or malformed AI responses', 0, async () => {
      const unresolved = new Workflow('{"content":"带电脑","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
      unresolved.location.resolveStatus = SceneResolveStatus.NOT_FOUND;
      const confirmation = await unresolved.parse();
      expect(confirmation.status).assertEqual(AIParseStatus.NEEDS_CONFIRMATION);
      // 未解析出地点时只回填部分 draft，不能直接持久化
      expect(confirmation.draft?.sceneName).assertEqual('实验室');
      expect(confirmation.draft?.sceneId).assertUndefined();
      expect((await unresolved.repository.findAll()).length).assertEqual(0);
      const malformed = new Workflow('not json');
      expect((await malformed.parse()).status).assertEqual(AIParseStatus.FAILED);
      expect((await malformed.repository.findAll()).length).assertEqual(0);
    });

    it('compensates time registration if AI BOTH location registration fails', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"BOTH","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":"实验室","ambiguous":false}');
      const parsed = await w.parse();
      if (parsed.draft === undefined) { throw new Error('Expected draft'); }
      w.location.failRegister = true;
      const created = await w.service.create(parsed.draft);
      expect(created.success).assertFalse();
      expect(created.error?.code).assertEqual('TRIGGER_REGISTRATION_ERROR');
      expect(w.time.cancelled[0]).assertEqual('ai-1');
      expect((await w.repository.findAll()).length).assertEqual(0);
    });

    it('retains ACTIVE after delivery failure then retries without duplicate success', 0, async () => {
      const w = new Workflow('{"content":"带电脑","triggerType":"TIME","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":null,"ambiguous":false}');
      await w.confirm(await w.parse());
      w.now = 2000;
      w.notification.failNotify = true;
      let rejected = false;
      try { await w.emit(TriggerCondition.TIME); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
      expect((await w.service.findById('ai-1')).data?.status).assertEqual(ReminderStatus.ACTIVE);
      w.notification.failNotify = false;
      await w.emit(TriggerCondition.TIME);
      await w.emit(TriggerCondition.TIME);
      expect(w.notification.reminders.length).assertEqual(1);
      expect((await w.service.findById('ai-1')).data?.status).assertEqual(ReminderStatus.TRIGGERED);
    });
  });
}
