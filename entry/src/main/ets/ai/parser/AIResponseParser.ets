import { AIParsedReminder } from '../model/AIParsedReminder';
import { AIParseIssue, AIParseIssueCode } from '../model/AIParseResult';

export interface AIResponseParseResult {
  value?: AIParsedReminder;
  issues: AIParseIssue[];
}

function issue(code: AIParseIssueCode, field?: string): AIParseIssue {
  return { code: code, field: field, message: 'AI 响应格式不正确', retryable: false };
}

export function parseAIResponse(rawResponse: string): AIResponseParseResult {
  let root: Object;
  try {
    root = JSON.parse(rawResponse) as Object;
  } catch (_) {
    return { issues: [issue(AIParseIssueCode.INVALID_JSON)] };
  }
  if (root === null || typeof root !== 'object' || Array.isArray(root)) {
    return { issues: [issue(AIParseIssueCode.INVALID_FIELD)] };
  }
  const fields = root as Record<string, Object | null>;
  const keys = Object.keys(fields);
  const expected = ['content', 'triggerType', 'triggerTime', 'sceneName', 'ambiguous'];
  for (const key of expected) {
    if (!keys.includes(key)) {
      return { issues: [issue(AIParseIssueCode.MISSING_FIELD, key)] };
    }
  }
  if (keys.length !== expected.length) {
    return { issues: [issue(AIParseIssueCode.INVALID_FIELD)] };
  }
  if (typeof fields['content'] !== 'string' || typeof fields['triggerType'] !== 'string' ||
    (fields['triggerTime'] !== null && (typeof fields['triggerTime'] !== 'number' || !Number.isFinite(fields['triggerTime'] as number))) ||
    (fields['sceneName'] !== null && typeof fields['sceneName'] !== 'string') ||
    typeof fields['ambiguous'] !== 'boolean') {
    return { issues: [issue(AIParseIssueCode.INVALID_FIELD)] };
  }
  const value: AIParsedReminder = {
    content: fields['content'] as string,
    triggerType: fields['triggerType'] as string,
    triggerTime: fields['triggerTime'] as number | null,
    sceneName: fields['sceneName'] as string | null,
    ambiguous: fields['ambiguous'] as boolean
  };
  return { value: value, issues: [] };
}
