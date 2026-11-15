// AI Provider 配置。凭证只允许通过本结构在组合根注入：
// 不进源码、不进资源文件、不进 Git；本地联调配置文件必须位于 .gitignore 忽略列表。

export interface AIProviderConfig {
  apiKey: string;
  endpoint: string;
  model: string;
  timeoutMs: number;
}

export const DEFAULT_AI_TIMEOUT_MS: number = 15000;

/**
 * 解析本地配置 JSON（严格形状：apiKey/endpoint/model 必填且非空，timeoutMs 可选）。
 * 返回 undefined 表示形状不合法，由调用方决定报错或回退。
 * 注意：本函数不校验 key 的有效性，只做结构校验；凭证本身绝不写入日志。
 */
export function parseAIProviderConfig(json: string): AIProviderConfig | undefined {
  let root: Object;
  try {
    root = JSON.parse(json) as Object;
  } catch (_) {
    return undefined;
  }
  if (root === null || typeof root !== 'object' || Array.isArray(root)) {
    return undefined;
  }
  const fields = root as Record<string, Object | null>;
  if (typeof fields['apiKey'] !== 'string' || (fields['apiKey'] as string).trim().length === 0 ||
    typeof fields['endpoint'] !== 'string' || (fields['endpoint'] as string).trim().length === 0 ||
    typeof fields['model'] !== 'string' || (fields['model'] as string).trim().length === 0) {
    return undefined;
  }
  const endpoint: string = (fields['endpoint'] as string).trim();
  if (!endpoint.startsWith('http://') && !endpoint.startsWith('https://')) {
    return undefined;
  }
  let timeoutMs: number = DEFAULT_AI_TIMEOUT_MS;
  if (fields['timeoutMs'] !== undefined && fields['timeoutMs'] !== null) {
    if (typeof fields['timeoutMs'] !== 'number' || !Number.isFinite(fields['timeoutMs'] as number) ||
      (fields['timeoutMs'] as number) <= 0) {
      return undefined;
    }
    timeoutMs = fields['timeoutMs'] as number;
  }
  return {
    apiKey: (fields['apiKey'] as string).trim(),
    endpoint: endpoint,
    model: (fields['model'] as string).trim(),
    timeoutMs: timeoutMs
  };
}
