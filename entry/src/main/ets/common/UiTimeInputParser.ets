/**
 * 手动输入时间的解析器（纯函数，无 UI 依赖）。
 *
 * 支持常见写法：
 *   15:30 / 15：30 / 1530
 *   15点30分 / 15点30 / 15点半 / 15点
 *   下午3点半 / 晚上八点 / 上午十点二十分 / 中午12点 / 凌晨1点
 *   今天15:30 / 明天下午3点 / 后天 09:00
 *   10月20日 15:30 / 10-20 15:30 / 2026年10月20日 15:30 / 2026-10-20 15:30
 *
 * 解析失败时返回稳定错误提示，不猜测用户意图、不自动改写过去时间。
 */

export class TimeParseResult {
  readonly ok: boolean;
  /** 成功时为 Unix Epoch 毫秒，失败为 0 */
  readonly timestamp: number;
  /** 成功时的可读描述，如「10月20日 15:30」 */
  readonly label: string;
  /** 失败时的提示文案 */
  readonly message: string;
  /** 是否早于当前时间（成功时才有意义） */
  readonly isPast: boolean;
  /** 「凌晨」类输入在今天已过去时，是否自动顺延到了次日 */
  readonly dateShifted: boolean;

  constructor(ok: boolean, timestamp: number, label: string, message: string,
    isPast: boolean, dateShifted: boolean) {
    this.ok = ok;
    this.timestamp = timestamp;
    this.label = label;
    this.message = message;
    this.isPast = isPast;
    this.dateShifted = dateShifted;
  }
}

function fail(message: string): TimeParseResult {
  return new TimeParseResult(false, 0, '', message, false, false);
}

function cnDigit(ch: string): number {
  if (ch === '零' || ch === '〇') {
    return 0;
  }
  if (ch === '一') {
    return 1;
  }
  if (ch === '二' || ch === '两') {
    return 2;
  }
  if (ch === '三') {
    return 3;
  }
  if (ch === '四') {
    return 4;
  }
  if (ch === '五') {
    return 5;
  }
  if (ch === '六') {
    return 6;
  }
  if (ch === '七') {
    return 7;
  }
  if (ch === '八') {
    return 8;
  }
  if (ch === '九') {
    return 9;
  }
  return -1;
}

/** 「十」→10，「十一」→11，「二十」→20，「二十三」→23；纯阿拉伯数字直接解析。 */
function toNumber(text: string): number {
  if (text === '') {
    return -1;
  }
  let allDigit: boolean = true;
  for (let i = 0; i < text.length; i++) {
    const c: string = text.charAt(i);
    if (c < '0' || c > '9') {
      allDigit = false;
      break;
    }
  }
  if (allDigit) {
    return parseInt(text, 10);
  }
  if (text === '十') {
    return 10;
  }
  const tenIndex: number = text.indexOf('十');
  if (tenIndex >= 0) {
    const high: number = tenIndex === 0 ? 1 : cnDigit(text.charAt(0));
    const lowText: string = text.substring(tenIndex + 1);
    const low: number = lowText === '' ? 0 : cnDigit(lowText.charAt(0));
    if (high < 0 || low < 0) {
      return -1;
    }
    return high * 10 + low;
  }
  return cnDigit(text.charAt(0));
}

/** 全角数字与中文标点归一化。 */
function normalize(input: string): string {
  const full: string = '０１２３４５６７８９';
  let out: string = '';
  for (let i = 0; i < input.length; i++) {
    const ch: string = input.charAt(i);
    const idx: number = full.indexOf(ch);
    out += idx >= 0 ? `${idx}` : ch;
  }
  out = out.replace(/：/g, ':');
  out = out.replace(/／/g, '/');
  out = out.replace(/－/g, '-');
  out = out.replace(/—/g, '-');
  return out;
}

function pad2(v: number): string {
  return v < 10 ? `0${v}` : `${v}`;
}

export function parseTimeInput(input: string, nowMs: number): TimeParseResult {
  const raw: string = input.trim();
  if (raw === '') {
    return fail('请输入时间，例如「明天下午3点半」');
  }
  const s: string = normalize(raw);
  const now: Date = new Date(nowMs);

  // ---- 日期 ----
  let year: number = now.getFullYear();
  let month: number = now.getMonth() + 1;
  let day: number = now.getDate();

  let hasDate: boolean = false;
  if (s.indexOf('今天') >= 0 || s.indexOf('今日') >= 0) {
    hasDate = true;
  } else if (s.indexOf('后天') >= 0) {
    hasDate = true;
    const d: Date = new Date(year, month - 1, day + 2);
    year = d.getFullYear();
    month = d.getMonth() + 1;
    day = d.getDate();
  } else if (s.indexOf('明天') >= 0 || s.indexOf('明日') >= 0) {
    hasDate = true;
    const d: Date = new Date(year, month - 1, day + 1);
    year = d.getFullYear();
    month = d.getMonth() + 1;
    day = d.getDate();
  }

  const ymd = s.match(/(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})/);
  if (ymd !== null) {
    year = parseInt(ymd[1], 10);
    month = parseInt(ymd[2], 10);
    day = parseInt(ymd[3], 10);
    hasDate = true;
  } else {
    const md = s.match(/(\d{1,2})[-/月](\d{1,2})/);
    if (md !== null) {
      month = parseInt(md[1], 10);
      day = parseInt(md[2], 10);
      hasDate = true;
    }
  }

  // ---- 时段词 ----
  let period: string = '';
  if (s.indexOf('凌晨') >= 0) {
    period = 'dawn';
  } else if (s.indexOf('早上') >= 0 || s.indexOf('早晨') >= 0 || s.indexOf('上午') >= 0) {
    period = 'am';
  } else if (s.indexOf('中午') >= 0) {
    period = 'noon';
  } else if (s.indexOf('下午') >= 0) {
    period = 'pm';
  } else if (s.indexOf('傍晚') >= 0 || s.indexOf('晚上') >= 0 || s.indexOf('今晚') >= 0 ||
    s.indexOf('夜里') >= 0 || s.indexOf('夜间') >= 0) {
    period = 'night';
  }

  // ---- 时间 ----
  let hour: number = -1;
  let minute: number = -1;

  const hm = s.match(/(\d{1,2}):(\d{1,2})/);
  if (hm !== null) {
    hour = parseInt(hm[1], 10);
    minute = parseInt(hm[2], 10);
  }

  if (hour < 0) {
    const cn = s.match(/([0-9零〇一二三四五六七八九十两]{1,3})\s*[点时]\s*([0-9零〇一二三四五六七八九十两]{1,3}|半)?\s*分?/);
    if (cn !== null) {
      hour = toNumber(cn[1]);
      const mText: string | undefined = cn[2];
      if (mText === undefined || mText === '') {
        minute = 0;
      } else if (mText === '半') {
        minute = 30;
      } else {
        minute = toNumber(mText);
      }
    }
  }

  if (hour < 0) {
    const hhmm = s.match(/(?:^|\s)(\d{4})(?:$|\s)/);
    if (hhmm !== null) {
      hour = Math.floor(parseInt(hhmm[1], 10) / 100);
      minute = parseInt(hhmm[1], 10) % 100;
    }
  }

  // 只写了日期（如「2027年3月5日」「明天」）：沿用当前时分，仍算有效输入
  if (hour < 0 && hasDate) {
    hour = now.getHours();
    minute = now.getMinutes();
  }

  if (hour < 0 || minute < 0) {
    return fail('没有识别到时间或日期，可写成「15:30」「下午3点半」「明天」或「2027年3月5日 09:00」');
  }

  // ---- 时段修正 ----
  // 晚上十二点 = 次日 00:00
  let dayShift: number = 0;
  if (period === 'pm' || period === 'night') {
    if (hour < 12) {
      hour += 12;
    } else if (period === 'night' && hour === 12) {
      hour = 0;
      dayShift = 1;
    }
  } else if (period === 'noon') {
    if (hour < 11) {
      hour += 12;
    }
  } else if (period === 'am' || period === 'dawn') {
    if (hour === 12) {
      hour = 0;
    }
  }

  if (hour > 23) {
    return fail('小时超出范围（0-23），请重新输入');
  }
  if (minute > 59) {
    return fail('分钟超出范围（0-59），请重新输入');
  }

  // 先校验原始日期，再应用「次日」偏移
  const base: Date = new Date(year, month - 1, day, 0, 0, 0, 0);
  if (base.getFullYear() !== year || base.getMonth() !== month - 1 || base.getDate() !== day) {
    return fail('日期无效，请检查月份和日期');
  }

  let result: Date = new Date(year, month - 1, day + dayShift, hour, minute, 0, 0);

  // 「凌晨」的语义通常是"即将到来的那个凌晨"。如果今天凌晨已经过去，
  // 自动顺延到次日，并由调用方在确认框中明确提示，避免用户误设成过去时间。
  let shifted: boolean = false;
  if (period === 'dawn' && result.getTime() < nowMs) {
    result = new Date(year, month - 1, day + dayShift + 1, hour, minute, 0, 0);
    shifted = true;
  }

  const datePart: string = result.getFullYear() === now.getFullYear()
    ? `${result.getMonth() + 1}月${result.getDate()}日`
    : `${result.getFullYear()}年${result.getMonth() + 1}月${result.getDate()}日`;
  const label: string = `${datePart} ${pad2(hour)}:${pad2(minute)}`;
  return new TimeParseResult(true, result.getTime(), label, '', result.getTime() < nowMs, shifted);
}
