import { describe, it, expect } from '@ohos/hypium';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { DefaultAIService } from '../main/ets/ai/DefaultAIService';
import { AIParseIssueCode, AIParseStatus } from '../main/ets/ai/model/AIParseResult';
import { FakeAIModelProvider } from '../main/ets/ai/provider/FakeAIModelProvider';
import { AIModelProvider, AIProviderResult } from '../main/ets/ai/provider/AIModelProvider';
import { SceneResolveResult, SceneResolveStatus, SceneResolver } from '../main/ets/reminder/contract/SceneResolver';
import { ReminderSource, TriggerType } from '../main/ets/model/ReminderEnums';

class TestResolver implements SceneResolver {
  calls: number = 0;
  result: SceneResolveResult = { status: SceneResolveStatus.RESOLVED, match: { id: 'lab-1', name: '实验室' }, candidates: [] };
  async resolveByName(_name: string): Promise<SceneResolveResult> {
    this.calls++;
    return this.result;
  }
}

class NetworkFailureProvider implements AIModelProvider {
  async requestParse(_text: string, _context: AIParseContext): Promise<AIProviderResult> {
    return { failure: { code: AIParseIssueCode.NETWORK_ERROR, retryable: true } };
  }
}

class ThrowingProvider implements AIModelProvider {
  async requestParse(_text: string, _context: AIParseContext): Promise<AIProviderResult> {
    throw new Error('private provider detail');
  }
}

export default function aiServiceTest() {
  describe('aiServiceTest', () => {
    const context: AIParseContext = { now: 1000, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };
    it('makes valid BOTH input ready with resolved scene', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('input', '{"content":"带电脑","triggerType":"BOTH","triggerTime":2000,"sceneName":"实验室","ambiguous":false}');
      const resolver = new TestResolver();
      const outcome = await new DefaultAIService(new FakeAIModelProvider(fixtures), resolver).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.READY);
      expect(outcome.draft?.triggerType).assertEqual(TriggerType.BOTH);
      expect(outcome.draft?.sceneId).assertEqual('lab-1');
      expect(outcome.draft?.source).assertEqual(ReminderSource.AI);
      expect(resolver.calls).assertEqual(1);
    });
    it('requires confirmation when location is not unique', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('input', '{"content":"带电脑","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
      const resolver = new TestResolver();
      resolver.result = { status: SceneResolveStatus.AMBIGUOUS, candidates: [{ id: 'a', name: '实验室' }, { id: 'b', name: '实验室' }] };
      const outcome = await new DefaultAIService(new FakeAIModelProvider(fixtures), resolver).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.NEEDS_CONFIRMATION);
      expect(outcome.draft).assertUndefined();
      expect(outcome.issues[0].code).assertEqual(AIParseIssueCode.UNRESOLVED_LOCATION);
    });
    it('fails retryably on network failure without a draft', 0, async () => {
      const outcome = await new DefaultAIService(new NetworkFailureProvider(), new TestResolver()).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.FAILED);
      expect(outcome.draft).assertUndefined();
      expect(outcome.issues[0].retryable).assertTrue();
    });
    it('requires confirmation for past time without resolver call', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('input', '{"content":"带电脑","triggerType":"TIME","triggerTime":500,"sceneName":null,"ambiguous":false}');
      const resolver = new TestResolver();
      const outcome = await new DefaultAIService(new FakeAIModelProvider(fixtures), resolver).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.NEEDS_CONFIRMATION);
      expect(outcome.issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
      expect(resolver.calls).assertEqual(0);
    });
    it('fails on malformed JSON without exposing a draft', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('input', 'not json');
      const outcome = await new DefaultAIService(new FakeAIModelProvider(fixtures), new TestResolver()).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.FAILED);
      expect(outcome.issues[0].code).assertEqual(AIParseIssueCode.INVALID_JSON);
      expect(outcome.draft).assertUndefined();
    });
    it('requires confirmation for scene not found', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('input', '{"content":"带电脑","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
      const resolver = new TestResolver();
      resolver.result = { status: SceneResolveStatus.NOT_FOUND, candidates: [] };
      const outcome = await new DefaultAIService(new FakeAIModelProvider(fixtures), resolver).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.NEEDS_CONFIRMATION);
      expect(outcome.draft).assertUndefined();
    });
    it('contains unexpected provider exception', 0, async () => {
      const outcome = await new DefaultAIService(new ThrowingProvider(), new TestResolver()).parseReminder('input', context);
      expect(outcome.status).assertEqual(AIParseStatus.FAILED);
      expect(outcome.issues[0].code).assertEqual(AIParseIssueCode.PROVIDER_ERROR);
      expect(outcome.issues[0].message.includes('private')).assertFalse();
    });
  });
}
