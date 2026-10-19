import { AIParseContext, AIService } from './contract/AIService';
import { mapAIParsedReminder } from './mapper/ReminderMapper';
import { AIParseIssue, AIParseIssueCode, AIParseOutcome, AIParseStatus } from './model/AIParseResult';
import { AIModelProvider, AIProviderResult } from './provider/AIModelProvider';
import { parseAIResponse } from './parser/AIResponseParser';
import { validateAIParsedReminder } from './validator/AIParseValidator';
import { validateCreateReminderInput } from '../model/ReminderModelRules';
import { TriggerType } from '../model/ReminderEnums';
import { SceneCandidate, SceneResolveStatus, SceneResolver } from '../reminder/contract/SceneResolver';

function issue(code: AIParseIssueCode, field: string | undefined, retryable: boolean): AIParseIssue {
  return { code: code, field: field, message: retryable ? '暂时无法解析，请重试' : '请确认提醒信息', retryable: retryable };
}

function outcome(status: AIParseStatus, issues: AIParseIssue[]): AIParseOutcome {
  return { status: status, issues: issues };
}

export class DefaultAIService implements AIService {
  private readonly provider: AIModelProvider;
  private readonly sceneResolver: SceneResolver;

  constructor(provider: AIModelProvider, sceneResolver: SceneResolver) {
    this.provider = provider;
    this.sceneResolver = sceneResolver;
  }

  async parseReminder(text: string, context: AIParseContext): Promise<AIParseOutcome> {
    if (text.trim().length === 0 || !Number.isFinite(context.now) ||
      context.timeZone.trim().length === 0 || context.locale.trim().length === 0) {
      return outcome(AIParseStatus.NEEDS_CONFIRMATION, [issue(AIParseIssueCode.INVALID_INPUT, 'text', false)]);
    }
    let providerResult: AIProviderResult;
    try {
      providerResult = await this.provider.requestParse(text, context);
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
          return outcome(AIParseStatus.NEEDS_CONFIRMATION, [issue(AIParseIssueCode.UNRESOLVED_LOCATION, 'sceneName', false)]);
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
