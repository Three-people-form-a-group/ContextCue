import { describe, it, expect } from '@ohos/hypium';
import { parseAIResponse } from '../main/ets/ai/parser/AIResponseParser';
import { AIParseIssueCode } from '../main/ets/ai/model/AIParseResult';

export default function aiResponseParserTest() {
  describe('aiResponseParserTest', () => {
    it('accepts exact five-field JSON object', 0, () => {
      const result = parseAIResponse('{"content":"带电脑","triggerType":"BOTH","triggerTime":2000,"sceneName":"实验室","ambiguous":false}');
      expect(result.value?.content).assertEqual('带电脑');
      expect(result.value?.triggerTime).assertEqual(2000);
      expect(result.issues.length).assertEqual(0);
    });
    it('rejects markdown, arrays and extra keys', 0, () => {
      expect(parseAIResponse('```json\n{}\n```').issues[0].code).assertEqual(AIParseIssueCode.INVALID_JSON);
      expect(parseAIResponse('[]').issues[0].code).assertEqual(AIParseIssueCode.INVALID_FIELD);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":2,"sceneName":null,"ambiguous":false,"extra":1}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_FIELD);
    });
    it('rejects missing and wrongly typed fields without coercion', 0, () => {
      expect(parseAIResponse('{"content":"a"}').issues[0].code).assertEqual(AIParseIssueCode.MISSING_FIELD);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2000","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_FIELD);
    });
  });
}
