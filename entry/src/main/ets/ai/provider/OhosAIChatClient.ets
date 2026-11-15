import { http } from '@kit.NetworkKit';
import { AIParseIssueCode } from '../model/AIParseResult';
import { AIChatClient, AIChatRequest, AIChatResult } from './AIChatClient';
import { AIProviderFailure } from './AIModelProvider';

/**
 * 基于 @ohos.net.http 的真实实现。错误映射（与《真实AI接入准备》第三节一致）：
 * 连接失败/超时/429/5xx → NETWORK_ERROR 可重试；
 * 400/401/403/404 → PROVIDER_ERROR 不可重试；
 * 200 但响应体异常 → PROVIDER_ERROR 可重试。
 * 本类绝不输出 Authorization 头或 apiKey。
 */
export class OhosAIChatClient implements AIChatClient {
  async chat(request: AIChatRequest): Promise<AIChatResult> {
    const client = http.createHttp();
    try {
      const response = await client.request(request.url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + request.apiKey
        },
        extraData: JSON.stringify({
          model: request.model,
          messages: [
            { role: 'system', content: request.system },
            { role: 'user', content: request.user }
          ],
          temperature: request.temperature
        }),
        connectTimeout: request.timeoutMs,
        readTimeout: request.timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });
      return mapResponse(response.responseCode, response.result as string);
    } catch (_) {
      const failure: AIProviderFailure = { code: AIParseIssueCode.NETWORK_ERROR, retryable: true };
      return { failure: failure };
    } finally {
      client.destroy();
    }
  }
}

export function mapResponse(responseCode: number, body: string): AIChatResult {
  if (responseCode === 400 || responseCode === 401 || responseCode === 403 || responseCode === 404) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: false };
    return { failure: failure };
  }
  if (responseCode === 429 || responseCode >= 500) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.NETWORK_ERROR, retryable: true };
    return { failure: failure };
  }
  if (responseCode !== 200) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.NETWORK_ERROR, retryable: true };
    return { failure: failure };
  }
  let root: Object;
  try {
    root = JSON.parse(body) as Object;
  } catch (_) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true };
    return { failure: failure };
  }
  if (root === null || typeof root !== 'object' || Array.isArray(root)) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true };
    return { failure: failure };
  }
  const fields = root as Record<string, Object | null>;
  const choices = fields['choices'];
  if (!Array.isArray(choices) || choices.length === 0) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true };
    return { failure: failure };
  }
  const first = choices[0] as Record<string, Object | null>;
  const message = first['message'];
  if (message === null || message === undefined || typeof message !== 'object' || Array.isArray(message)) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true };
    return { failure: failure };
  }
  const content = (message as Record<string, Object | null>)['content'];
  if (typeof content !== 'string' || content.trim().length === 0) {
    const failure: AIProviderFailure = { code: AIParseIssueCode.PROVIDER_ERROR, retryable: true };
    return { failure: failure };
  }
  return { content: content };
}
