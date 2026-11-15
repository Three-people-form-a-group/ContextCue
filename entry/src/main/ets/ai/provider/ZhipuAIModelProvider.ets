import { AIParseContext } from '../contract/AIService';
import { AIParseIssueCode } from '../model/AIParseResult';
import { AIModelProvider, AIProviderResult } from './AIModelProvider';
import { AIChatClient, AIChatRequest } from './AIChatClient';
import { AIProviderConfig } from './AIProviderConfig';

const PROMPT_TEMPERATURE: number = 0.1;

/**
 * 智谱开放平台（open.bigmodel.cn）GLM 系列的 AIModelProvider 实现。
 * MaaS 开通前的阶段性真实来源；接口签名与 Fake 完全一致，
 * 组合根根据本地配置决定注入哪一个。密钥只在 AIChatClient 内部使用，
 * 本类不缓存、不输出凭证。
 */
export class ZhipuAIModelProvider implements AIModelProvider {
  private readonly config: AIProviderConfig;
  private readonly client: AIChatClient;

  constructor(config: AIProviderConfig, client: AIChatClient) {
    this.config = config;
    this.client = client;
  }

  async requestParse(text: string, context: AIParseContext): Promise<AIProviderResult> {
    const request: AIChatRequest = {
      url: this.config.endpoint,
      apiKey: this.config.apiKey,
      model: this.config.model,
      system: buildParseSystemPrompt(context),
      user: text,
      temperature: PROMPT_TEMPERATURE,
      timeoutMs: this.config.timeoutMs
    };
    const result = await this.client.chat(request);
    if (result.failure !== undefined) {
      return { failure: result.failure };
    }
    if (result.content === undefined) {
      return { failure: { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true } };
    }
    return { rawResponse: result.content };
  }
}

/** 当前时刻的描述段：让模型只做"理解 + 拼日期"，不做数值运算。 */
export function describeNow(context: AIParseContext): string {
  const d: Date = new Date(context.now);
  const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  const offsetMinutes: number = -d.getTimezoneOffset();
  const sign: string = offsetMinutes >= 0 ? '+' : '-';
  const abs: number = Math.abs(offsetMinutes);
  const pad = (v: number): string => (v < 10 ? '0' + v.toString() : v.toString());
  const offset = 'UTC' + sign + pad(Math.floor(abs / 60)) + ':' + pad(abs % 60);
  const local = d.getFullYear().toString() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
    ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  return local + '（' + weekdays[d.getDay()] + '，时区 ' + context.timeZone + '，' + offset + '）';
}

/** 提示词与《真实AI接入准备-2026-10-25.md》第二节保持同源。 */
export function buildParseSystemPrompt(context: AIParseContext): string {
  return '你是一个提醒解析助手。用户会给你一句中文，你把它解析成提醒的 JSON。当前时间：' +
    describeNow(context) + '。\n' +
    '只输出一个 JSON 对象，不要带 markdown 代码块，不要带任何解释文字。JSON 必须恰好包含以下五个键：\n' +
    '1. content：需要提醒用户做的事，去掉"提醒我"等提示词，保留动作本身。\n' +
    '2. triggerType：只能是 "TIME"（按时间提醒）、"LOCATION"（按地点提醒）或 "BOTH"（时间加地点）。\n' +
    '3. triggerTime：触发时间，格式 "YYYY-MM-DDTHH:mm:ss+08:00"（带时区偏移的 ISO-8601）。没有时间时为 null。\n' +
    '4. sceneName：地点名称，只取用户提到的场所词（如 实验室、家、快递站）。没有地点时为 null。\n' +
    '5. ambiguous：布尔值。任何不确定都要设为 true。\n' +
    '时间规则：相对时间（明天、今晚、十分钟后、周五）以提供的当前时间为基准；已经过去的星期几或日期顺延到下一次；' +
    '无法确定具体时间（如"下周""月底"）或日期不存在时，triggerTime 置 null 并把 ambiguous 设为 true。\n' +
    '歧义规则：如果用户说了地点也说了时间，但句子没有说清是"时间到达就提醒"还是"到达该地点才提醒"' +
    '（例如"明天下午两点去实验室，提醒我带电脑"更适合出发前提醒），把 ambiguous 设为 true，不要替用户选择。\n' +
    '提取规则：不要添加用户没说的信息，不要改写过去的时间，不要猜测地点对应的真实位置。';
}
