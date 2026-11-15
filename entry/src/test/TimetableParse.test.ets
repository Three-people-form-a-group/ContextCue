import { describe, it, expect } from '@ohos/hypium';
import { TimetableDraft } from '../main/ets/timetable/model/TimetableTypes';
import { TimetableParseIssueCode } from '../main/ets/timetable/model/TimetableTypes';
import { computeCurrentWeek, occurrenceEpochMs, parseCalendarDate, parseHHmm,
  parseTimetableData, mondayOfWeek, validateTimetableDraft } from '../main/ets/timetable/parse/TimetableDataParser';

const VALID_JSON = '{"semesterName":"2026-2027学年第一学期","anchorDate":"2026-10-26","anchorWeek":8,' +
  '"courses":[{"name":"高等数学","teacher":"张老师","location":"教三-401","dayOfWeek":1,' +
  '"startTime":"08:00","endTime":"09:40","weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]}],"extra":"忽略"}';

export default function timetableParseTest() {
  describe('timetableParseTest', () => {
    it('accepts standard timetable json and tolerates extra keys', 0, () => {
      const result = parseTimetableData(VALID_JSON);
      expect(result.issues.length).assertEqual(0);
      expect(result.value?.semesterName).assertEqual('2026-2027学年第一学期');
      expect(result.value?.anchorWeek).assertEqual(8);
      expect(result.value?.courses.length).assertEqual(1);
      expect(result.value?.courses[0].location).assertEqual('教三-401');
    });
    it('tolerates markdown fences and prose around the json', 0, () => {
      const fenced = parseTimetableData('```json\n' + VALID_JSON + '\n```');
      expect(fenced.value?.courses.length).assertEqual(1);
      const prose = parseTimetableData('识别结果：' + VALID_JSON + ' 请确认。');
      expect(prose.value?.anchorWeek).assertEqual(8);
    });
    it('rejects malformed payloads with stable codes', 0, () => {
      expect(parseTimetableData('not json').issues[0].code).assertEqual(TimetableParseIssueCode.INVALID_JSON);
      expect(parseTimetableData('{"semesterName":"s"}').issues[0].code).assertEqual(TimetableParseIssueCode.MISSING_FIELD);
      expect(parseTimetableData('{"semesterName":"s","anchorDate":"2026-10-26","anchorWeek":8,"courses":[]}').issues[0].code)
        .assertEqual(TimetableParseIssueCode.MISSING_FIELD);
    });
    it('reports root-level format errors without inventing a field name', 0, () => {
      const arrayRoot = parseTimetableData('[]');
      expect(arrayRoot.value).assertUndefined();
      expect(arrayRoot.issues[0].code).assertEqual(TimetableParseIssueCode.INVALID_FIELD);
      expect(arrayRoot.issues[0].field).assertUndefined();
      const wrongType = parseTimetableData('{"semesterName":8,"anchorDate":"2026-10-26","anchorWeek":8,"courses":[]}');
      expect(wrongType.value).assertUndefined();
      expect(wrongType.issues[0].code).assertEqual(TimetableParseIssueCode.INVALID_FIELD);
      expect(wrongType.issues[0].field).assertUndefined();
    });
    it('validates field ranges and calendar correctness', 0, () => {
      const bad = parseTimetableData('{"semesterName":"s","anchorDate":"2026-02-30","anchorWeek":8,' +
        '"courses":[{"name":"数学","dayOfWeek":8,"startTime":"24:00","endTime":"09:00","weeks":[0]}]}');
      expect(bad.value).assertUndefined();
      const fields: string[] = [];
      for (const issue of bad.issues) {
        if (issue.field !== undefined) {
          fields.push(issue.field);
        }
      }
      expect(fields.includes('anchorDate')).assertTrue();
      expect(fields.includes('courses[0].dayOfWeek')).assertTrue();
      expect(fields.includes('courses[0].startTime')).assertTrue();
      expect(fields.includes('courses[0].weeks')).assertTrue();
    });
    it('validates manually built drafts with the same rules', 0, () => {
      const draft: TimetableDraft = {
        semesterName: ' ', anchorDate: '2026-10-26', anchorWeek: 8,
        courses: [{ name: '', dayOfWeek: 1, startTime: '08:00', endTime: '09:40', weeks: [8] }]
      };
      const issues = validateTimetableDraft(draft);
      expect(issues.length).assertEqual(2);
      expect(issues[0].code).assertEqual(TimetableParseIssueCode.MISSING_FIELD);
      expect(issues[1].field).assertEqual('courses[0].name');
    });
    it('computes calendar and week math deterministically', 0, () => {
      const anchor = parseCalendarDate('2026-10-26');
      expect(anchor).assertEqual(Date.UTC(2026, 9, 26, 12, 0, 0));
      expect(mondayOfWeek(parseCalendarDate('2026-11-01') as number)).assertEqual(Date.UTC(2026, 9, 26, 12, 0, 0));
      expect(computeCurrentWeek(anchor as number, 8, Date.UTC(2026, 9, 28, 12))).assertEqual(8);
      expect(computeCurrentWeek(anchor as number, 8, Date.UTC(2026, 10, 2, 12))).assertEqual(9);
      expect(computeCurrentWeek(anchor as number, 8, Date.UTC(2026, 9, 25, 12))).assertEqual(7);
      expect(parseHHmm('08:30')).assertEqual(510);
      expect(parseHHmm('24:00')).assertUndefined();
    });
    it('resolves occurrence wall clock times in the device timezone', 0, () => {
      const anchor = parseCalendarDate('2026-10-26') as number;
      expect(occurrenceEpochMs(anchor, 8, 8, 1, '08:00')).assertEqual(new Date(2026, 9, 26, 8, 0).getTime());
      expect(occurrenceEpochMs(anchor, 8, 9, 3, '14:00')).assertEqual(new Date(2026, 10, 4, 14, 0).getTime());
    });
  });
}
