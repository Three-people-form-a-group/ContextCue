import { ScheduleOverride, TimetableSchedule } from '../timetable/model/TimetableTypes';
import { PeriodRow, hmText, minutesOfHm } from './TimetableCourse';

const MAX_PERIODS: number = 12;
const DAY_LIMIT_MINUTES: number = 22 * 60;

/**
 * 作息的 UI 侧计算模型：由公共 `TimetableSchedule` 包一层，
 * 负责「第一节开始 + 每节时长 + 课间 + 午休/晚餐 + 单节覆盖」推算节次。
 * 它只是展示规则，不参与提醒生成；课程时间仍是提醒的唯一依据。
 */
export class ScheduleModel {
  firstStart: string;
  duration: number;
  breakMinutes: number;
  lunchStart: string;
  lunchEnd: string;
  dinnerStart: string;
  dinnerEnd: string;
  overrides: ScheduleOverride[];
  locked: number[];

  constructor(firstStart: string, duration: number, breakMinutes: number,
    lunchStart: string, lunchEnd: string, dinnerStart: string, dinnerEnd: string,
    overrides: ScheduleOverride[], locked: number[]) {
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
  static regular(): ScheduleModel {
    return new ScheduleModel('08:00', 45, 10, '12:00', '14:00', '17:30', '18:30', [], []);
  }

  /** 大节连排：90 分钟一节，课间 20 */
  static block(): ScheduleModel {
    return new ScheduleModel('08:00', 90, 20, '12:00', '14:00', '17:30', '18:30', [], []);
  }

  /** 早课紧凑：07:30 开始，40 分钟，课间 5，午休 11:40–13:30 */
  static early(): ScheduleModel {
    return new ScheduleModel('07:30', 40, 5, '11:40', '13:30', '17:00', '18:00', [], []);
  }

  /** 短午休：08:00 开始，45 分钟，午休只到 13:30 */
  static shortLunch(): ScheduleModel {
    return new ScheduleModel('08:00', 45, 10, '12:00', '13:30', '17:30', '18:30', [], []);
  }

  /** null / undefined / 空对象都表示"没有作息" */
  static fromStored(schedule: TimetableSchedule | null | undefined): ScheduleModel | undefined {
    if (schedule === undefined || schedule === null) {
      return undefined;
    }
    return new ScheduleModel(
      schedule.firstStart,
      schedule.duration,
      schedule.breakMinutes,
      schedule.lunchStart === undefined ? '12:00' : schedule.lunchStart,
      schedule.lunchEnd === undefined ? '14:00' : schedule.lunchEnd,
      schedule.dinnerStart === undefined ? '17:30' : schedule.dinnerStart,
      schedule.dinnerEnd === undefined ? '18:30' : schedule.dinnerEnd,
      schedule.overrides === undefined ? [] : schedule.overrides,
      schedule.locked === undefined ? [] : schedule.locked
    );
  }

  toStored(): TimetableSchedule {
    const stored: TimetableSchedule = {
      firstStart: this.firstStart,
      duration: this.duration,
      breakMinutes: this.breakMinutes,
      lunchStart: this.lunchStart,
      lunchEnd: this.lunchEnd,
      dinnerStart: this.dinnerStart,
      dinnerEnd: this.dinnerEnd
    };
    if (this.overrides.length > 0) {
      stored.overrides = this.overrides;
    }
    if (this.locked.length > 0) {
      stored.locked = this.locked;
    }
    return stored;
  }

  clone(): ScheduleModel {
    return new ScheduleModel(this.firstStart, this.duration, this.breakMinutes,
      this.lunchStart, this.lunchEnd, this.dinnerStart, this.dinnerEnd,
      this.overrides.slice(), this.locked.slice());
  }

  overrideFor(index: number): ScheduleOverride | undefined {
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

  /** 自动推算全部节次：遇午休/晚餐自动跳到窗口结束，overrides 覆盖单节 */
  periods(): PeriodRow[] {
    const out: PeriodRow[] = [];
    const lunchS: number = minutesOfHm(this.lunchStart);
    const lunchE: number = minutesOfHm(this.lunchEnd);
    const dinnerS: number = minutesOfHm(this.dinnerStart);
    const dinnerE: number = minutesOfHm(this.dinnerEnd);
    let cursor: number = minutesOfHm(this.firstStart);

    for (let i = 1; i <= MAX_PERIODS; i++) {
      let start: number = cursor;
      let end: number = start + this.duration;

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

      const override: ScheduleOverride | undefined = this.overrideFor(i);
      if (override !== undefined) {
        start = minutesOfHm(override.start);
        end = minutesOfHm(override.end);
      }

      if (start >= DAY_LIMIT_MINUTES || end > DAY_LIMIT_MINUTES || end <= start) {
        break;
      }

      out.push(new PeriodRow(i, start, end));
      cursor = end + this.breakMinutes;
      if (cursor >= DAY_LIMIT_MINUTES) {
        break;
      }
    }
    return out;
  }

  /** 第 index 节的开始时间（没有该节时返回空串） */
  startOf(index: number): string {
    const list: PeriodRow[] = this.periods();
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        return list[i].start;
      }
    }
    return '';
  }

  endOf(index: number): string {
    const list: PeriodRow[] = this.periods();
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        return list[i].end;
      }
    }
    return '';
  }

  /** 设置/清除某一节的覆盖 */
  setOverride(index: number, start: string, end: string): void {
    const next: ScheduleOverride[] = [];
    for (let i = 0; i < this.overrides.length; i++) {
      if (this.overrides[i].index !== index) {
        next.push(this.overrides[i]);
      }
    }
    if (start !== '' && end !== '' && minutesOfHm(end) > minutesOfHm(start)) {
      next.push({ index: index, start: start, end: end });
    }
    this.overrides = next;
  }

  /** 切换某节的锁定状态 */
  toggleLock(index: number): void {
    const next: number[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.locked.length; i++) {
      if (this.locked[i] === index) {
        removed = true;
      } else {
        next.push(this.locked[i]);
      }
    }
    if (!removed) {
      next.push(index);
    }
    next.sort((a: number, b: number) => a - b);
    this.locked = next;
  }

  /** 某时刻落在第几节（取开始时间不晚于它的最后一节；没有则返回 0） */
  periodIndexAt(minutes: number): number {
    const list: PeriodRow[] = this.periods();
    let index: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i].startMinutes <= minutes) {
        index = list[i].index;
      }
    }
    return index;
  }
}
