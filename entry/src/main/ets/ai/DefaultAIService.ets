import { AIParseContext, AIService } from './contract/AIService';
import { mapAIParsedReminder } from './mapper/ReminderMapper';
import { AIParseIssue, AIParseIssueCode, AIParseOutcome, AIParseStatus } from './model/AIParseResult';
import { AIModelProvider, AIProviderResult } from './provider/AIModelProvider';
import { parseAIResponse } from './parser/AIResponseParser';
import { validateAIParsedReminder } from './validator/AIParseValidator';
import { validateCreateReminderInput } from '../model/ReminderModelRules';
import { TriggerType } from '../model/ReminderEnums';
import { CreateReminderInput } from '../model/CreateReminderInput';
import { SceneCandidate, SceneResolveStatus, SceneResolver } from '../reminder/contract/SceneResolver';

function issue(code: AIParseIssueCode, field: string | undefined, retryable: boolean): AIParseIssue {
  return { code: code, field: field, message: retryable ? '暂时无法解析，请重试' : '请确认提醒信息', retryable: retryable };
}

function outcome(status: AIParseStatus, issues: AIParseIssue[]): AIParseOutcome {
  return { status: status, issues: issues };
}

const DEFAULT_PROVIDER_TIMEOUT_MS: number = 15000;

export class DefaultAIService implements AIService {
  private readonly provider: AIModelProvider;
  private readonly sceneResolver: SceneResolver;
  private readonly providerTimeoutMs: number;

  constructor(provider: AIModelProvider, sceneResolver: SceneResolver,
    providerTimeoutMs: number = DEFAULT_PROVIDER_TIMEOUT_MS) {
    this.provider = provider;
    this.sceneResolver = sceneResolver;
    this.providerTimeoutMs = Number.isFinite(providerTimeoutMs) && providerTimeoutMs > 0
      ? providerTimeoutMs : DEFAULT_PROVIDER_TIMEOUT_MS;
  }

  /**
   * 服务级超时兜底：供应商 Promise 挂起时按预算返回可重试的 NETWORK_ERROR，
   * 避免页面无限等待。正式 Provider 适配器仍应设置自己的 HTTP 超时。
   */
  private async requestWithTimeout(text: string, context: AIParseContext): Promise<AIProviderResult> {
    let timerId: number = 0;
    const timeoutPromise = new Promise<AIProviderResult>((resolve) => {
      timerId = setTimeout(() => {
        resolve({ failure: { code: AIParseIssueCode.NETWORK_ERROR, retryable: true } });
      }, this.providerTimeoutMs);
    });
    try {
      return await Promise.race([this.provider.requestParse(text, context), timeoutPromise]);
    } finally {
      clearTimeout(timerId);
    }
  }

  async parseReminder(text: string, context: AIParseContext): Promise<AIParseOutcome> {
    if (text.trim().length === 0) {
      return outcome(AIParseStatus.NEEDS_CONFIRMATION, [issue(AIParseIssueCode.INVALID_INPUT, 'text', false)]);
    }
    if (!Number.isFinite(context.now)) {
      return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.INVALID_INPUT, 'now', false)]);
    }
    if (context.timeZone.trim().length === 0) {
      return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.INVALID_INPUT, 'timeZone', false)]);
    }
    if (context.locale.trim().length === 0) {
      return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.INVALID_INPUT, 'locale', false)]);
    }
    let providerResult: AIProviderResult;
    try {
      providerResult = await this.requestWithTimeout(text, context);
    } catch (_) {
      return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.PROVIDER_ERROR, undefined, true)]);
    }
    if (providerResult.failure !== undefined) {
      return outcome(AIParseStatus.FAILED, [issue(providerResult.failure.code, undefined, providerResult.failure.retryable)]);
    }
    if (providerResult.rawResponse === undefined) {
      return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.PROVIDER_ERROR, undefined, true)]);
    }
    const parsed = parseAIResponse(providerResult.rawResponse);
    if (parsed.value === undefined) {
      const status = parsed.issues[0].code === AIParseIssueCode.INVALID_JSON ? AIParseStatus.FAILED : AIParseStatus.NEEDS_CONFIRMATION;
      return outcome(status, parsed.issues);
    }
    const validationIssues = validateAIParsedReminder(parsed.value, context);
    if (validationIssues.length > 0) {
      return outcome(AIParseStatus.NEEDS_CONFIRMATION, validationIssues);
    }
    let scene: SceneCandidate | undefined;
    if (parsed.value.triggerType === TriggerType.LOCATION || parsed.value.triggerType === TriggerType.BOTH) {
      try {
        const resolution = await this.sceneResolver.resolveByName(parsed.value.sceneName as string);
        if (resolution.status !== SceneResolveStatus.RESOLVED || resolution.match === undefined ||
          resolution.match.id.trim().length === 0) {
          // 地点没解析出来也回一个“部分 draft”：内容、提醒方式和时间仍可预填，
          // 编辑台再用地点名引导用户选择或新建场景。
          const partial: CreateReminderInput = mapAIParsedReminder(parsed.value, undefined);
          if (parsed.value.sceneName !== null) {
            partial.sceneName = parsed.value.sceneName;
          }
          const message: string = resolution.status === SceneResolveStatus.AMBIGUOUS
            ? '有多个同名地点，请在下面选择具体地点'
            : '这个地点还没有保存，可以在编辑台用当前位置新增';
          return {
            status: AIParseStatus.NEEDS_CONFIRMATION,
            draft: partial,
            issues: [{
              code: AIParseIssueCode.UNRESOLVED_LOCATION,
              field: 'sceneName',
              message: message,
              retryable: false
            }]
          };
        }
        scene = resolution.match;
      } catch (_) {
        return outcome(AIParseStatus.FAILED, [issue(AIParseIssueCode.SCENE_RESOLVER_ERROR, 'sceneName', true)]);
      }
    }
    const draft = mapAIParsedReminder(parsed.value, scene);
    const modelErrors = validateCreateReminderInput(draft, context.now);
    if (modelErrors.length > 0) {
      return outcome(AIParseStatus.NEEDS_CONFIRMATION, [issue(AIParseIssueCode.AMBIGUOUS_RESULT, modelErrors[0].field, false)]);
    }
    return { status: AIParseStatus.READY, draft: draft, issues: [] };
  }
}
