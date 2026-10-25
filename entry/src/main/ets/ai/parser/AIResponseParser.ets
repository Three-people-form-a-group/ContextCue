import { AIParsedReminder } from '../model/AIParsedReminder';
import { AIParseIssue, AIParseIssueCode } from '../model/AIParseResult';

export interface AIResponseParseResult {
  value?: AIParsedReminder;
  issues: AIParseIssue[];
}

const EXPECTED_KEYS: string[] = ['content', 'triggerType', 'triggerTime', 'sceneName', 'ambiguous'];

function issue(code: AIParseIssueCode, field?: string): AIParseIssue {
  return { code: code, field: field, message: 'AI 响应格式不正确', retryable: false };
}

function issueTime(field: string): AIParseIssue {
  return { code: AIParseIssueCode.INVALID_TIME, field: field, message: '时间格式无法解析', retryable: false };
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

/**
 * 把带时区偏移的 ISO-8601 时间字符串换算为 Unix Epoch 毫秒。
 * 真实模型自己计算 Epoch 毫秒容易出错，因此 Provider 输出约定使用 ISO-8601；
 * 偏移量必须存在（Z 或 ±HH:mm），缺省偏移的字符串无法确定时刻，按无效处理。
 * 转换失败返回 undefined，由调用方转为 INVALID_TIME 交给用户确认。
 */
export function convertIsoToEpochMs(text: string): number | undefined {
  const s: string = text.trim();
  if (s.length < 17) {
    return undefined;
  }
  if (s.charAt(4) !== '-' || s.charAt(7) !== '-') {
    return undefined;
  }
  const year: number | undefined = toDigits(s.substring(0, 4));
  const month: number | undefined = toDigits(s.substring(5, 7));
  const day: number | undefined = toDigits(s.substring(8, 10));
  const timeSep: string = s.charAt(10);
  if (year === undefined || month === undefined || day === undefined) {
    return undefined;
  }
  if (year < 1000 || (timeSep !== 'T' && timeSep !== ' ')) {
    return undefined;
  }
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    return undefined;
  }
  if (s.charAt(13) !== ':') {
    return undefined;
  }
  const hour: number | undefined = toDigits(s.substring(11, 13));
  const minute: number | undefined = toDigits(s.substring(14, 16));
  if (hour === undefined || minute === undefined || hour > 23 || minute > 59) {
    return undefined;
  }
  let pos: number = 16;
  let second: number = 0;
  if (s.charAt(pos) === ':') {
    const parsedSecond: number | undefined = toDigits(s.substring(pos + 1, pos + 3));
    if (parsedSecond === undefined || parsedSecond > 59) {
      return undefined;
    }
    second = parsedSecond;
    pos += 3;
  }
  let msPart: number = 0;
  if (s.charAt(pos) === '.') {
    let end: number = pos + 1;
    while (end < s.length && isDigit(s.charAt(end))) {
      end++;
    }
    const digits: string = s.substring(pos + 1, end);
    if (digits.length === 0) {
      return undefined;
    }
    const padded: string = (digits + '00').substring(0, 3);
    const parsedMs: number | undefined = toDigits(padded);
    if (parsedMs === undefined) {
      return undefined;
    }
    msPart = parsedMs;
    pos = end;
  }
  const zone: string = s.substring(pos);
  let offsetMinutes: number = 0;
  if (zone === 'Z') {
    offsetMinutes = 0;
  } else if (zone.length === 6 && (zone.charAt(0) === '+' || zone.charAt(0) === '-') && zone.charAt(3) === ':') {
    const zoneHour: number | undefined = toDigits(zone.substring(1, 3));
    const zoneMinute: number | undefined = toDigits(zone.substring(4, 6));
    if (zoneHour === undefined || zoneMinute === undefined || zoneHour > 23 || zoneMinute > 59) {
      return undefined;
    }
    offsetMinutes = (zone.charAt(0) === '-' ? -1 : 1) * (zoneHour * 60 + zoneMinute);
  } else {
    return undefined;
  }
  const utcMs: number = Date.UTC(year, month - 1, day, hour, minute, second, msPart);
  return utcMs - offsetMinutes * 60000;
}

function tryParseJson(text: string): Object | undefined {
  try {
    return JSON.parse(text) as Object;
  } catch (_) {
    return undefined;
  }
}

/**
 * 真实模型可能用 markdown 代码块或说明文字包裹 JSON；
 * 直接解析失败时截取首个 { 到最后一个 } 再试一次，仍失败才报 INVALID_JSON。
 */
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

export function parseAIResponse(rawResponse: string): AIResponseParseResult {
  const root: Object | undefined = parseJsonObject(rawResponse);
  if (root === undefined) {
    return { issues: [issue(AIParseIssueCode.INVALID_JSON)] };
  }
  if (root === null || typeof root !== 'object' || Array.isArray(root)) {
    return { issues: [issue(AIParseIssueCode.INVALID_FIELD)] };
  }
  const fields = root as Record<string, Object | null>;
  const keys = Object.keys(fields);
  for (const key of EXPECTED_KEYS) {
    if (!keys.includes(key)) {
      return { issues: [issue(AIParseIssueCode.MISSING_FIELD, key)] };
    }
  }
  // 真实模型可能附带约定外的字段；多余键一律忽略，不影响解析结果。
  if (typeof fields['content'] !== 'string' || typeof fields['triggerType'] !== 'string' ||
    (fields['sceneName'] !== null && typeof fields['sceneName'] !== 'string') ||
    typeof fields['ambiguous'] !== 'boolean') {
    return { issues: [issue(AIParseIssueCode.INVALID_FIELD)] };
  }
  let triggerTime: number | null = null;
  const rawTime: Object | null = fields['triggerTime'];
  if (rawTime !== null) {
    if (typeof rawTime === 'number' && Number.isFinite(rawTime)) {
      // 兼容旧的 epoch 毫秒数字契约：模型违反 ISO 约定输出数字时仍可安全接受。
      triggerTime = rawTime;
    } else if (typeof rawTime === 'string') {
      const converted: number | undefined = convertIsoToEpochMs(rawTime);
      if (converted === undefined) {
        return { issues: [issueTime('triggerTime')] };
      }
      triggerTime = converted;
    } else {
      return { issues: [issue(AIParseIssueCode.INVALID_FIELD, 'triggerTime')] };
    }
  }
  const value: AIParsedReminder = {
    content: fields['content'] as string,
    triggerType: fields['triggerType'] as string,
    triggerTime: triggerTime,
    sceneName: fields['sceneName'] as string | null,
    ambiguous: fields['ambiguous'] as boolean
  };
  return { value: value, issues: [] };
}
