/**
 * 学校作息规则（课表 UI 层的本地模型，不是公共层模型）。
 *
 * 作用：把「第几节」换算成真实起止时间，供七日课表按节次排布、供表单按节次选择。
 *
 * 重要边界：
 *   当前公共 CourseDraft 只有 dayOfWeek / startTime / endTime / weeks，没有
 *   startPeriod / endPeriod。所以这一版是「节次 → 真实时间」的单向换算（兼容当前接口），
 *   课程仍然只存真实时间。要做到「改作息后自动重排全部课程、并同步提醒」，
 *   需要 TimetableService 存独立的作息规则和课程的节次信息，
 *   这部分必须由组长确认后才能落地。
 */

const DAY_LIMIT_MINUTES: number = 22 * 60;
const MAX_PERIODS: number = 12;

export function minutesOfTime(time: string): number {
  const parts: string[] = time.split(':');
  if (parts.length < 2) {
    return 0;
  }
  const h: number = parseInt(parts[0], 10);
  const m: number = parseInt(parts[1], 10);
  if (Number.isNaN(h) || Number.isNaN(m)) {
    return 0;
  }
  return h * 60 + m;
}

export function formatMinutesOf(minutes: number): string {
  const h: number = Math.floor(minutes / 60);
  const m: number = minutes % 60;
  return `${h < 10 ? `0${h}` : `${h}`}:${m < 10 ? `0${m}` : `${m}`}`;
}

/** 单个节次：节号 + 真实起止 */
export class PeriodDef {
  readonly index: number;
  readonly start: string;
  readonly end: string;
  readonly startMinutes: number;
  readonly endMinutes: number;

  constructor(index: number, startMinutes: number, endMinutes: number) {
    this.index = index;
    this.startMinutes = startMinutes;
    this.endMinutes = endMinutes;
    this.start = formatMinutesOf(startMinutes);
    this.end = formatMinutesOf(endMinutes);
  }

  duration(): number {
    return this.endMinutes - this.startMinutes;
  }
}

/** 某一节的单独调整（覆盖推算值） */
export class PeriodOverride {
  readonly index: number;
  readonly start: string;
  readonly end: string;

  constructor(index: number, start: string, end: string) {
    this.index = index;
    this.start = start;
    this.end = end;
  }
}

/**
 * 作息规则：第一节开始 + 每节时长 + 课间 + 午休，自动推算其余节次。
 * overrides 里是用户单独改过的节次；locked 里的节次不参与批量平移。
 */
export class SectionSchedule {
  static readonly MAX_PERIODS: number = MAX_PERIODS;
  static readonly DAY_LIMIT: number = DAY_LIMIT_MINUTES;

  readonly firstStart: string;
  readonly duration: number;
  readonly breakMinutes: number;
  readonly lunchStart: string;
  readonly lunchEnd: string;
  readonly dinnerStart: string;
  readonly dinnerEnd: string;
  readonly overrides: PeriodOverride[];
  readonly locked: number[];

  constructor(firstStart: string, duration: number, breakMinutes: number,
    lunchStart: string, lunchEnd: string, dinnerStart: string, dinnerEnd: string,
    overrides: PeriodOverride[], locked: number[]) {
    this.firstStart = firstStart;
    this.duration = duration;
    this.breakMinutes = breakMinutes;
    this.lunchStart = lunchStart;
    this.lunchEnd = lunchEnd;
    this.dinnerStart = dinnerStart;
    this.dinnerEnd = dinnerEnd;
    this.overrides = overrides;
    this.locked = locked;
  }

  /** 常规课时：08:00 开始，45 分钟一节，课间 10，午休 12:00–14:00 */
  static regular(): SectionSchedule {
    return new SectionSchedule('08:00', 45, 10, '12:00', '14:00', '17:30', '18:30', [], []);
  }

  /** 大节连排：两小节并成一节（90 分钟），课间 20，一天节数更少 */
  static block(): SectionSchedule {
    return new SectionSchedule('08:00', 90, 20, '12:00', '14:00', '17:30', '18:30', [], []);
  }

  /** 早课紧凑：07:30 开始，40 分钟一节，课间 5，午休 11:40–13:30 */
  static early(): SectionSchedule {
    return new SectionSchedule('07:30', 40, 5, '11:40', '13:30', '17:00', '18:00', [], []);
  }

  /** 短午休：08:00 开始，45 分钟，午休只到 13:30，下午课更早开始 */
  static shortLunch(): SectionSchedule {
    return new SectionSchedule('08:00', 45, 10, '12:00', '13:30', '17:30', '18:30', [], []);
  }

  overrideFor(index: number): PeriodOverride | undefined {
    for (let i = 0; i < this.overrides.length; i++) {
      if (this.overrides[i].index === index) {
        return this.overrides[i];
      }
    }
    return undefined;
  }

  isLocked(index: number): boolean {
    return this.locked.indexOf(index) >= 0;
  }

  /** 自动推算全部节次：遇午休自动跳到午休结束 */
  periods(): PeriodDef[] {
    const out: PeriodDef[] = [];
    const lunchS: number = minutesOfTime(this.lunchStart);
    const lunchE: number = minutesOfTime(this.lunchEnd);
    let cursor: number = minutesOfTime(this.firstStart);

    for (let i = 1; i <= MAX_PERIODS; i++) {
      let start: number = cursor;
      let end: number = start + this.duration;

      const dinnerS: number = minutesOfTime(this.dinnerStart);
      const dinnerE: number = minutesOfTime(this.dinnerEnd);

      // 落在午休/晚餐里、或会跨进它们的节次，整体推后
      if (start >= lunchS && start < lunchE) {
        start = lunchE;
        end = start + this.duration;
      } else if (start < lunchS && end > lunchS) {
        start = lunchE;
        end = start + this.duration;
      }
      if (start >= dinnerS && start < dinnerE) {
        start = dinnerE;
        end = start + this.duration;
      } else if (start < dinnerS && end > dinnerS) {
        start = dinnerE;
        end = start + this.duration;
      }

      const override: PeriodOverride | undefined = this.overrideFor(i);
      if (override !== undefined) {
        start = minutesOfTime(override.start);
        end = minutesOfTime(override.end);
      }

      if (start >= DAY_LIMIT_MINUTES || end > DAY_LIMIT_MINUTES || end <= start) {
        break;
      }

      out.push(new PeriodDef(i, start, end));
      cursor = end + this.breakMinutes;
      if (cursor >= DAY_LIMIT_MINUTES) {
        break;
      }
    }
    return out;
  }

  /** 上午节次数（午休之前），用于在表格里插入午休行 */
  morningCount(): number {
    const lunchS: number = minutesOfTime(this.lunchStart);
    const list: PeriodDef[] = this.periods();
    let count: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i].startMinutes < lunchS) {
        count += 1;
      }
    }
    return count;
  }
}
