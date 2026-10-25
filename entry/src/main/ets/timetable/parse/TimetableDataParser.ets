// 课程表数据解析与周次计算（纯逻辑，无 UI / 系统能力依赖）。
// 三种导入方式（手动表单、教务 JSON、AI 图片识别）都汇聚到同一个
// TimetableDraft 结构；教务 JSON 与视觉模型输出共用 parseTimetableData。

import { CourseDraft, TimetableDraft, TimetableParseIssue, TimetableParseIssueCode } from '../model/TimetableTypes';

const DAY_MS: number = 86400000;
const WEEK_MS: number = 7 * DAY_MS;
const MAX_WEEK: number = 30;

export interface TimetableDataParseResult {
  value?: TimetableDraft;
  issues: TimetableParseIssue[];
}

function issue(code: TimetableParseIssueCode, field: string | undefined, message: string): TimetableParseIssue {
  return { code: code, field: field, message: message };
}

function fieldIssue(code: TimetableParseIssueCode, field: string): TimetableParseIssue {
  return issue(code, field, '课程表数据格式不正确');
}

function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

function toDigits(text: string): number | undefined {
  if (text.length === 0) {
    return undefined;
  }
  let value: number = 0;
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (!isDigit(ch)) {
      return undefined;
    }
    value = value * 10 + (ch.charCodeAt(0) - 48);
  }
  return value;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap: boolean = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    return leap ? 29 : 28;
  }
  if (month === 4 || month === 6 || month === 9 || month === 11) {
    return 30;
  }
  return 31;
}

/** "YYYY-MM-DD" → 该日 12:00 UTC 的毫秒值（纯日期的规范表示，避免时区与夏令时干扰） */
export function parseCalendarDate(text: string): number | undefined {
  const s: string = text.trim();
  if (s.length !== 10 || s.charAt(4) !== '-' || s.charAt(7) !== '-') {
    return undefined;
  }
  const year: number | undefined = toDigits(s.substring(0, 4));
  const month: number | undefined = toDigits(s.substring(5, 7));
  const day: number | undefined = toDigits(s.substring(8, 10));
  if (year === undefined || month === undefined || day === undefined || year < 1000) {
    return undefined;
  }
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    return undefined;
  }
  return Date.UTC(year, month - 1, day, 12, 0, 0);
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

export function formatCalendarDate(dayMs: number): string {
  const d: Date = new Date(dayMs);
  return d.getUTCFullYear().toString() + '-' + pad2(d.getUTCMonth() + 1) + '-' + pad2(d.getUTCDate());
}

/** "HH:mm" → 当日分钟数；越界返回 undefined */
export function parseHHmm(text: string): number | undefined {
  const s: string = text.trim();
  if (s.length !== 5 || s.charAt(2) !== ':') {
    return undefined;
  }
  const hour: number | undefined = toDigits(s.substring(0, 2));
  const minute: number | undefined = toDigits(s.substring(3, 5));
  if (hour === undefined || minute === undefined || hour > 23 || minute > 59) {
    return undefined;
  }
  return hour * 60 + minute;
}

/** 设备本地时区下包含 nowMs 的那一天，转成规范日值 */
export function localDayCanonical(nowMs: number): number {
  const d: Date = new Date(nowMs);
  return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 12, 0, 0);
}

/** 该日期所在周的周一（规范日值）；周一为一周起点 */
export function mondayOfWeek(dayMs: number): number {
  const utcDay: number = new Date(dayMs).getUTCDay();
  const offset: number = utcDay === 0 ? 6 : utcDay - 1;
  return dayMs - offset * DAY_MS;
}

/** 当前是第几周：锚点日期所在周为 anchorWeek */
export function computeCurrentWeek(anchorDateMs: number, anchorWeek: number, nowMs: number): number {
  const mondayAnchor: number = mondayOfWeek(anchorDateMs);
  const mondayNow: number = mondayOfWeek(localDayCanonical(nowMs));
  return anchorWeek + Math.floor((mondayNow - mondayAnchor) / WEEK_MS);
}

/** 指定周次的周一（规范日值） */
export function weekMondayMs(anchorDateMs: number, anchorWeek: number, week: number): number {
  return mondayOfWeek(anchorDateMs) + (week - anchorWeek) * WEEK_MS;
}

/** 某周 dayOfWeek 的上课开始时刻（设备本地时区的墙上时间） */
export function occurrenceEpochMs(anchorDateMs: number, anchorWeek: number, week: number,
  dayOfWeek: number, startTime: string): number | undefined {
  const minutes: number | undefined = parseHHmm(startTime);
  if (minutes === undefined) {
    return undefined;
  }
  const dayMs: number = weekMondayMs(anchorDateMs, anchorWeek, week) + (dayOfWeek - 1) * DAY_MS;
  const d: Date = new Date(dayMs);
  return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(),
    Math.floor(minutes / 60), minutes % 60, 0, 0).getTime();
}

/** 手动表单路径的同一套校验；解析路径在校验后调用 */
export function validateTimetableDraft(draft: TimetableDraft): TimetableParseIssue[] {
  const issues: TimetableParseIssue[] = [];
  if (draft.semesterName.trim().length === 0) {
    issues.push(fieldIssue(TimetableParseIssueCode.MISSING_FIELD, 'semesterName'));
  }
  if (parseCalendarDate(draft.anchorDate) === undefined) {
    issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, 'anchorDate'));
  }
  if (!Number.isInteger(draft.anchorWeek) || draft.anchorWeek < 1 || draft.anchorWeek > MAX_WEEK) {
    issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, 'anchorWeek'));
  }
  if (!Array.isArray(draft.courses) || draft.courses.length === 0) {
    issues.push(fieldIssue(TimetableParseIssueCode.MISSING_FIELD, 'courses'));
    return issues;
  }
  for (let i = 0; i < draft.courses.length; i++) {
    const course: CourseDraft = draft.courses[i];
    if (course.name.trim().length === 0) {
      issues.push(fieldIssue(TimetableParseIssueCode.MISSING_FIELD, `courses[${i}].name`));
    }
    if (!Number.isInteger(course.dayOfWeek) || course.dayOfWeek < 1 || course.dayOfWeek > 7) {
      issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${i}].dayOfWeek`));
    }
    const start: number | undefined = parseHHmm(course.startTime);
    const end: number | undefined = parseHHmm(course.endTime);
    if (start === undefined || end === undefined || start >= end) {
      issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${i}].startTime`));
    }
    if (!Array.isArray(course.weeks) || course.weeks.length === 0) {
      issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${i}].weeks`));
    } else {
      for (let w = 0; w < course.weeks.length; w++) {
        const week: number = course.weeks[w];
        if (!Number.isInteger(week) || week < 1 || week > MAX_WEEK) {
          issues.push(fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${i}].weeks`));
          break;
        }
      }
    }
  }
  return issues;
}

function tryParseJson(text: string): Object | undefined {
  try {
    return JSON.parse(text) as Object;
  } catch (_) {
    return undefined;
  }
}

/** 容忍 markdown 围栏与说明文字：直接解析失败时截取首个 { 到最后一个 } 再试 */
function parseJsonObject(rawResponse: string): Object | undefined {
  const direct: Object | undefined = tryParseJson(rawResponse.trim());
  if (direct !== undefined) {
    return direct;
  }
  const start: number = rawResponse.indexOf('{');
  const end: number = rawResponse.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return undefined;
  }
  return tryParseJson(rawResponse.substring(start, end + 1));
}

function readOptionalString(fields: Record<string, Object | null>, key: string): string | undefined {
  const raw: Object | null = fields[key];
  if (typeof raw === 'string') {
    return raw;
  }
  return undefined;
}

interface CourseParseResult {
  course?: CourseDraft;
  issueField?: TimetableParseIssue;
}

function parseCourse(rawCourse: Object, index: string): CourseParseResult {
  if (rawCourse === null || typeof rawCourse !== 'object' || Array.isArray(rawCourse)) {
    return { issueField: fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${index}]`) };
  }
  const fields = rawCourse as Record<string, Object | null>;
  const keys: string[] = Object.keys(fields);
  for (const key of ['name', 'dayOfWeek', 'startTime', 'endTime', 'weeks']) {
    if (!keys.includes(key)) {
      return { issueField: fieldIssue(TimetableParseIssueCode.MISSING_FIELD, `courses[${index}].${key}`) };
    }
  }
  if (typeof fields['name'] !== 'string' || typeof fields['dayOfWeek'] !== 'number' ||
    typeof fields['startTime'] !== 'string' || typeof fields['endTime'] !== 'string' ||
    !Array.isArray(fields['weeks'])) {
    return { issueField: fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${index}]`) };
  }
  const weeks: number[] = [];
  const rawWeeks = fields['weeks'] as Object[];
  for (let i = 0; i < rawWeeks.length; i++) {
    if (typeof rawWeeks[i] !== 'number' || !Number.isFinite(rawWeeks[i] as number)) {
      return { issueField: fieldIssue(TimetableParseIssueCode.INVALID_FIELD, `courses[${index}].weeks`) };
    }
    weeks.push(rawWeeks[i] as number);
  }
  const course: CourseDraft = {
    name: fields['name'] as string,
    teacher: readOptionalString(fields, 'teacher'),
    location: readOptionalString(fields, 'location'),
    dayOfWeek: fields['dayOfWeek'] as number,
    startTime: fields['startTime'] as string,
    endTime: fields['endTime'] as string,
    weeks: weeks
  };
  return { course: course };
}

export function parseTimetableData(rawResponse: string): TimetableDataParseResult {
  const root: Object | undefined = parseJsonObject(rawResponse);
  if (root === undefined) {
    return { issues: [issue(TimetableParseIssueCode.INVALID_JSON, undefined, '课程表数据不是合法 JSON')] };
  }
  if (root === null || typeof root !== 'object' || Array.isArray(root)) {
    return { issues: [fieldIssue(TimetableParseIssueCode.INVALID_FIELD, undefined)] };
  }
  const fields = root as Record<string, Object | null>;
  const keys: string[] = Object.keys(fields);
  for (const key of ['semesterName', 'anchorDate', 'anchorWeek', 'courses']) {
    if (!keys.includes(key)) {
      return { issues: [fieldIssue(TimetableParseIssueCode.MISSING_FIELD, key)] };
    }
  }
  if (typeof fields['semesterName'] !== 'string' || typeof fields['anchorDate'] !== 'string' ||
    typeof fields['anchorWeek'] !== 'number' || !Array.isArray(fields['courses'])) {
    return { issues: [fieldIssue(TimetableParseIssueCode.INVALID_FIELD, undefined)] };
  }
  const courses: CourseDraft[] = [];
  const rawCourses = fields['courses'] as Object[];
  for (let i = 0; i < rawCourses.length; i++) {
    const parsed = parseCourse(rawCourses[i], i.toString());
    if (parsed.issueField !== undefined) {
      return { issues: [parsed.issueField] };
    }
    courses.push(parsed.course as CourseDraft);
  }
  const draft: TimetableDraft = {
    semesterName: fields['semesterName'] as string,
    anchorDate: fields['anchorDate'] as string,
    anchorWeek: fields['anchorWeek'] as number,
    courses: courses
  };
  const validation: TimetableParseIssue[] = validateTimetableDraft(draft);
  if (validation.length > 0) {
    return { issues: validation };
  }
  return { value: draft, issues: [] };
}
