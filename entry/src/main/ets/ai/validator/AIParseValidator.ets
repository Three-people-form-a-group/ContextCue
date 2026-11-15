import { AIParseContext } from '../contract/AIService';
import { AIParsedReminder } from '../model/AIParsedReminder';
import { AIParseIssue, AIParseIssueCode } from '../model/AIParseResult';

function issue(code: AIParseIssueCode, field: string): AIParseIssue {
  return { code: code, field: field, message: '请确认提醒信息', retryable: false };
}

export function validateAIParsedReminder(parsed: AIParsedReminder, context: AIParseContext): AIParseIssue[] {
  const issues: AIParseIssue[] = [];
  if (parsed.content.trim().length === 0) {
    issues.push(issue(AIParseIssueCode.MISSING_FIELD, 'content'));
  }
  if (parsed.triggerType !== 'TIME' && parsed.triggerType !== 'LOCATION' && parsed.triggerType !== 'BOTH') {
    issues.push(issue(AIParseIssueCode.AMBIGUOUS_RESULT, 'triggerType'));
  }
  if (parsed.triggerType === 'TIME' && parsed.sceneName !== null ||
    parsed.triggerType === 'LOCATION' && parsed.triggerTime !== null) {
    issues.push(issue(AIParseIssueCode.AMBIGUOUS_RESULT, 'triggerType'));
  }
  if (parsed.triggerType === 'TIME' || parsed.triggerType === 'BOTH') {
    if (parsed.triggerTime === null || !Number.isFinite(parsed.triggerTime) || parsed.triggerTime < context.now) {
      issues.push(issue(AIParseIssueCode.INVALID_TIME, 'triggerTime'));
    }
  }
  if (parsed.triggerType === 'LOCATION' || parsed.triggerType === 'BOTH') {
    if (parsed.sceneName === null || parsed.sceneName.trim().length === 0) {
      issues.push(issue(AIParseIssueCode.UNRESOLVED_LOCATION, 'sceneName'));
    }
  }
  if (parsed.ambiguous) {
    issues.push(issue(AIParseIssueCode.AMBIGUOUS_RESULT, 'ambiguous'));
  }
  return issues;
}
