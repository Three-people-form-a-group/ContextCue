import { describe, it, expect } from '@ohos/hypium';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { AIParseIssueCode } from '../main/ets/ai/model/AIParseResult';
import { AIProviderConfig, parseAIProviderConfig, DEFAULT_AI_TIMEOUT_MS } from '../main/ets/ai/provider/AIProviderConfig';
import { AIChatClient, AIChatRequest, AIChatResult } from '../main/ets/ai/provider/AIChatClient';
import { ZhipuAIModelProvider, buildParseSystemPrompt, describeNow } from '../main/ets/ai/provider/ZhipuAIModelProvider';

class ScriptedChatClient implements AIChatClient {
  private readonly handler: (request: AIChatRequest) => AIChatResult;
  lastRequest?: AIChatRequest;

  constructor(handler: (request: AIChatRequest) => AIChatResult) {
    this.handler = handler;
  }

  async chat(request: AIChatRequest): Promise<AIChatResult> {
    this.lastRequest = request;
    return this.handler(request);
  }
}

const VALID_CONFIG: AIProviderConfig = {
  apiKey: 'test-key-not-a-real-secret',
  endpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
  model: 'glm-5.3-flash',
  timeoutMs: 15000
};

export default function zhipuAIProviderTest() {
  describe('zhipuAIProviderTest', () => {
    const context: AIParseContext = { now: 1799400000000, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };

    it('builds system prompt with current time, timezone and contract rules', 0, () => {
      const prompt = buildParseSystemPrompt(context);
      expect(prompt.includes('Asia/Shanghai')).assertTrue();
      expect(prompt.includes('UTC')).assertTrue();
      expect(prompt.includes('triggerType')).assertTrue();
      expect(prompt.includes('ambiguous')).assertTrue();
      expect(prompt.includes('YYYY-MM-DDTHH:mm:ss')).assertTrue();
      expect(prompt.includes('不要带 markdown')).assertTrue();
      const nowText = describeNow(context);
      expect(nowText.includes('Asia/Shanghai')).assertTrue();
      expect(nowText.startsWith('2')).assertTrue();
    });
    it('sends model, temperature and user text through the chat client', 0, async () => {
      const client = new ScriptedChatClient((_request: AIChatRequest): AIChatResult => {
        return { content: '{"content":"带电脑","triggerType":"BOTH","triggerTime":"2026-11-16T14:00:00+08:00","sceneName":"实验室","ambiguous":false}' };
      });
      const provider = new ZhipuAIModelProvider(VALID_CONFIG, client);
      const result = await provider.requestParse('明天下午两点去实验室，提醒我带电脑', context);
      expect(result.rawResponse).assertUndefined();
      expect(result.failure).assertUndefined();
    });
    it('exposes the captured request for prompt assertions', 0, async () => {
      const client = new ScriptedChatClient((_request: AIChatRequest): AIChatResult => {
        return { content: '{"content":"x","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}' };
      });
      const provider = new ZhipuAIModelProvider(VALID_CONFIG, client);
      await provider.requestParse('提醒我买礼物', context);
      const sent = client.lastRequest as AIChatRequest;
      expect(sent.url).assertEqual(VALID_CONFIG.endpoint);
      expect(sent.model).assertEqual('glm-5.3-flash');
      expect(sent.temperature).assertEqual(0.1);
      expect(sent.user).assertEqual('提醒我买礼物');
      expect(sent.apiKey).assertEqual('test-key-not-a-real-secret');
    });
    it('maps missing content to retryable provider error', 0, async () => {
      const client = new ScriptedChatClient((_request: AIChatRequest): AIChatResult => {
        return {};
      });
      const provider = new ZhipuAIModelProvider(VALID_CONFIG, client);
      const result = await provider.requestParse('任意输入', context);
      expect(result.rawResponse).assertUndefined();
      expect(result.failure?.code).assertEqual(AIParseIssueCode.PROVIDER_ERROR);
      expect(result.failure?.retryable).assertTrue();
    });
    it('passes through provider failures unchanged', 0, async () => {
      const client = new ScriptedChatClient((_request: AIChatRequest): AIChatResult => {
        return { failure: { code: AIParseIssueCode.NETWORK_ERROR, retryable: true } };
      });
      const provider = new ZhipuAIModelProvider(VALID_CONFIG, client);
      const result = await provider.requestParse('任意输入', context);
      expect(result.failure?.code).assertEqual(AIParseIssueCode.NETWORK_ERROR);
      expect(result.failure?.retryable).assertTrue();
    });
    it('parses and validates local config json strictly', 0, () => {
      const config = parseAIProviderConfig('{"apiKey":"k","endpoint":"https://x/y","model":"m"}');
      expect(config?.timeoutMs).assertEqual(DEFAULT_AI_TIMEOUT_MS);
      expect(parseAIProviderConfig('{"endpoint":"https://x/y","model":"m"}')).assertUndefined();
      expect(parseAIProviderConfig('{"apiKey":"k","endpoint":"ftp://x","model":"m"}')).assertUndefined();
      expect(parseAIProviderConfig('{"apiKey":"k","endpoint":"https://x/y","model":"m","timeoutMs":0}')).assertUndefined();
      expect(parseAIProviderConfig('not json')).assertUndefined();
      const parsed = parseAIProviderConfig('{"apiKey":" k ","endpoint":" https://x/y ","model":" m ","timeoutMs":5000}');
      expect(parsed?.apiKey).assertEqual('k');
      expect(parsed?.timeoutMs).assertEqual(5000);
    });
  });
}
