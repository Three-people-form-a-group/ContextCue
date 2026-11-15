import { describe, it, expect } from '@ohos/hypium';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { AIParsedReminder } from '../main/ets/ai/model/AIParsedReminder';
import { AIParseIssueCode } from '../main/ets/ai/model/AIParseResult';
import { validateAIParsedReminder } from '../main/ets/ai/validator/AIParseValidator';

export default function aiParseValidatorTest() {
  describe('aiParseValidatorTest', () => {
    const context: AIParseContext = { now: 1000, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };
    it('accepts clear time reminder', 0, () => {
      const parsed: AIParsedReminder = { content: '带电脑', triggerType: 'TIME', triggerTime: 2000, sceneName: null, ambiguous: false };
      expect(validateAIParsedReminder(parsed, context).length).assertEqual(0);
    });
    it('flags past time and location contradiction', 0, () => {
      const parsed: AIParsedReminder = { content: '带电脑', triggerType: 'TIME', triggerTime: 500, sceneName: '实验室', ambiguous: false };
      const issues = validateAIParsedReminder(parsed, context);
      expect(issues[0].code).assertEqual(AIParseIssueCode.AMBIGUOUS_RESULT);
      expect(issues[1].code).assertEqual(AIParseIssueCode.INVALID_TIME);
    });
    it('flags missing location and explicit ambiguity', 0, () => {
      const parsed: AIParsedReminder = { content: '带电脑', triggerType: 'LOCATION', triggerTime: null, sceneName: ' ', ambiguous: true };
      const issues = validateAIParsedReminder(parsed, context);
      expect(issues[0].code).assertEqual(AIParseIssueCode.UNRESOLVED_LOCATION);
      expect(issues[1].code).assertEqual(AIParseIssueCode.AMBIGUOUS_RESULT);
    });
  });
}
