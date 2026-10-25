import { describe, it, expect } from '@ohos/hypium';
import { parseAIResponse } from '../main/ets/ai/parser/AIResponseParser';
import { AIParseIssueCode } from '../main/ets/ai/model/AIParseResult';

function isoMs(iso: string): number {
  return new Date(iso).getTime();
}

export default function aiResponseParserTest() {
  describe('aiResponseParserTest', () => {
    it('accepts exact five-field JSON object with ISO-8601 time', 0, () => {
      const result = parseAIResponse('{"content":"带电脑","triggerType":"BOTH","triggerTime":"2026-10-26T14:00:00+08:00","sceneName":"实验室","ambiguous":false}');
      expect(result.value?.content).assertEqual('带电脑');
      expect(result.value?.triggerTime).assertEqual(isoMs('2026-10-26T14:00:00+08:00'));
      expect(result.issues.length).assertEqual(0);
    });
    it('strips markdown fences and prose around the JSON object', 0, () => {
      const fenced = parseAIResponse('```json\n{"content":"带电脑","triggerType":"TIME","triggerTime":"2026-10-26T14:00:00+08:00","sceneName":null,"ambiguous":false}\n```');
      expect(fenced.value?.triggerTime).assertEqual(isoMs('2026-10-26T14:00:00+08:00'));
      const prose = parseAIResponse('解析结果如下：{"content":"带电脑","triggerType":"TIME","triggerTime":"2026-10-26T14:00:00+08:00","sceneName":null,"ambiguous":false} 请确认。');
      expect(prose.value?.content).assertEqual('带电脑');
    });
    it('tolerates extra keys returned by real models', 0, () => {
      const result = parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"1970-01-01T00:00:02Z","sceneName":null,"ambiguous":false,"extra":1,"note":"说明"}');
      expect(result.value?.triggerTime).assertEqual(2000);
      expect(result.issues.length).assertEqual(0);
    });
    it('keeps finite epoch numbers compatible with the previous contract', 0, () => {
      const result = parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":2000,"sceneName":null,"ambiguous":false}');
      expect(result.value?.triggerTime).assertEqual(2000);
    });
    it('rejects unparseable payloads without coercion', 0, () => {
      expect(parseAIResponse('```json\n{broken\n```').issues[0].code).assertEqual(AIParseIssueCode.INVALID_JSON);
      expect(parseAIResponse('[]').issues[0].code).assertEqual(AIParseIssueCode.INVALID_FIELD);
      expect(parseAIResponse('not json').issues[0].code).assertEqual(AIParseIssueCode.INVALID_JSON);
    });
    it('rejects missing and wrongly typed fields without coercion', 0, () => {
      expect(parseAIResponse('{"content":"a"}').issues[0].code).assertEqual(AIParseIssueCode.MISSING_FIELD);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":true,"sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_FIELD);
    });
    it('converts ISO-8601 offset variants to epoch milliseconds', 0, () => {
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"1970-01-01T00:00:02Z","sceneName":null,"ambiguous":false}').value?.triggerTime).assertEqual(2000);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"1970-01-01T08:00:02+08:00","sceneName":null,"ambiguous":false}').value?.triggerTime).assertEqual(2000);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"1970-01-01T00:00:02.25Z","sceneName":null,"ambiguous":false}').value?.triggerTime).assertEqual(2250);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"1970-01-01 00:00:02Z","sceneName":null,"ambiguous":false}').value?.triggerTime).assertEqual(2000);
    });
    it('rejects ISO strings without offset or with impossible calendar values', 0, () => {
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2026-10-26T14:00:00","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2026-02-30T10:00:00Z","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2026-10-26T25:00:00Z","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2026-10-26T14:00","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
      expect(parseAIResponse('{"content":"a","triggerType":"TIME","triggerTime":"2000","sceneName":null,"ambiguous":false}').issues[0].code).assertEqual(AIParseIssueCode.INVALID_TIME);
    });
  });
}
