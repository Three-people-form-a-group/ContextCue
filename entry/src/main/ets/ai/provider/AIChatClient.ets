import { AIProviderFailure } from './AIModelProvider';

/**
 * OpenAI 兼容对话补全的 HTTP 端口。真实实现包装 @ohos.net.http；
 * 测试用 Fake 注入。Provider 适配器不直接接触网络 API，
 * 因此任何供应商只要能提供 chat/completions 形状就能接入。
 */
export interface AIChatRequest {
  url: string;
  apiKey: string;
  model: string;
  system: string;
  user: string;
  temperature: number;
  timeoutMs: number;
}

export interface AIChatResult {
  /** 200 且能取出 choices[0].message.content 时才有值 */
  content?: string;
  failure?: AIProviderFailure;
}

export interface AIChatClient {
  chat(request: AIChatRequest): Promise<AIChatResult>;
}
