// 课程表图片识别端口：与 AI 模块的 AIModelProvider 同构的供应商抽象。
// 现阶段只有 Fake 实现；真实视觉模型（MaaS 开通后）按此签名接入，
// 输出 parseTimetableData 可解析的标准 JSON。Token 成本控制：
// 压缩图片、一次调用、解析结果必须经用户预览确认后才保存。

export enum TimetableProviderFailureCode {
  NETWORK_ERROR = 'NETWORK_ERROR',
  PROVIDER_ERROR = 'PROVIDER_ERROR'
}

export interface TimetableProviderFailure {
  code: TimetableProviderFailureCode;
  retryable: boolean;
}

export interface TimetableProviderResult {
  rawResponse?: string;
  failure?: TimetableProviderFailure;
}

export interface TimetableImageContext {
  now: number;
  timeZone: string;
}

export interface TimetableImageParser {
  /**
   * imageToken 标识一张待识别的图片：Fake 阶段是 fixture 键，
   * 真实阶段由 Provider 适配器约定（如压缩后的 base64 或沙箱文件 URI）。
   */
  requestTimetableParse(imageToken: string, context: TimetableImageContext): Promise<TimetableProviderResult>;
}
