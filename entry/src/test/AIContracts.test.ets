import { describe, it, expect } from '@ohos/hypium';
import { AIParseStatus } from '../main/ets/ai/model/AIParseResult';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { FakeAIModelProvider } from '../main/ets/ai/provider/FakeAIModelProvider';
import { SceneResolveStatus, SceneResolver, SceneResolveResult } from '../main/ets/reminder/contract/SceneResolver';

class TestSceneResolver implements SceneResolver {
  async resolveByName(sceneName: string): Promise<SceneResolveResult> {
    return { status: SceneResolveStatus.RESOLVED, match: { id: 'lab', name: sceneName }, candidates: [] };
  }
}

export default function aiContractsTest() {
  describe('aiContractsTest', () => {
    it('returns exact fake response and refuses unknown text', 0, async () => {
      const fixtures = new Map<string, string>();
      fixtures.set('带电脑', '{"content":"带电脑"}');
      const provider = new FakeAIModelProvider(fixtures);
      const context: AIParseContext = { now: 1000, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };
      const known = await provider.requestParse('带电脑', context);
      const unknown = await provider.requestParse('未知输入', context);
      expect(known.rawResponse).assertEqual('{"content":"带电脑"}');
      expect(unknown.failure?.code).assertEqual('PROVIDER_ERROR');
      expect(unknown.failure?.retryable).assertFalse();
    });

    it('exposes statuses and location resolver contract', 0, async () => {
      expect(AIParseStatus.READY).assertEqual('READY');
      expect(AIParseStatus.NEEDS_CONFIRMATION).assertEqual('NEEDS_CONFIRMATION');
      expect(AIParseStatus.FAILED).assertEqual('FAILED');
      const result = await new TestSceneResolver().resolveByName('实验室');
      expect(result.status).assertEqual(SceneResolveStatus.RESOLVED);
      expect(result.match?.id).assertEqual('lab');
    });
  });
}
