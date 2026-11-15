import { CourseDraft, StoredCourse } from '../timetable/model/TimetableTypes';

/**
 * 课表页的展示用课程：字段来自公共 `StoredCourse`，
 * `tone` 只用于分配课程块颜色（由 id 散列稳定生成）。
 */
export class TimetableCourse {
  readonly id: string;
  readonly name: string;
  readonly teacher: string;
  readonly location: string;
  /** 1=周一 … 7=周日 */
  readonly dayOfWeek: number;
  /** "HH:mm" */
  readonly startTime: string;
  readonly endTime: string;
  readonly weeks: number[];
  readonly tone: number;

  constructor(id: string, name: string, teacher: string, location: string, dayOfWeek: number,
    startTime: string, endTime: string, weeks: number[], tone: number) {
    this.id = id;
    this.name = name;
    this.teacher = teacher;
    this.location = location;
    this.dayOfWeek = dayOfWeek;
    this.startTime = startTime;
    this.endTime = endTime;
    this.weeks = weeks;
    this.tone = tone;
  }

  static fromStored(c: StoredCourse): TimetableCourse {
    // 用课程名散列：服务每次保存会重新分配 course-N 的 id，按 id 取色会随位置变化
    let h: number = 0;
    const seed: string = `${c.name}|${c.dayOfWeek}|${c.startTime}`;
    for (let i = 0; i < seed.length; i++) {
      h = (h * 31 + seed.charCodeAt(i)) % 997;
    }
    return new TimetableCourse(
      c.id,
      c.name,
      c.teacher === undefined ? '' : c.teacher,
      c.location === undefined ? '' : c.location,
      c.dayOfWeek,
      c.startTime,
      c.endTime,
      c.weeks,
      Math.abs(h) % 6
    );
  }

  toDraft(): CourseDraft {
    const d: CourseDraft = {
      name: this.name,
      dayOfWeek: this.dayOfWeek,
      startTime: this.startTime,
      endTime: this.endTime,
      weeks: this.weeks
    };
    if (this.teacher !== '') {
      d.teacher = this.teacher;
    }
    if (this.location !== '') {
      d.location = this.location;
    }
    return d;
  }
}

/** 七天表格的一行：由课程时间推导出的"节次" */
export class PeriodRow {
  readonly index: number;
  readonly startMinutes: number;
  readonly endMinutes: number;
  readonly start: string;
  readonly end: string;

  constructor(index: number, startMinutes: number, endMinutes: number) {
    this.index = index;
    this.startMinutes = startMinutes;
    this.endMinutes = endMinutes;
    this.start = hmText(startMinutes);
    this.end = hmText(endMinutes);
  }
}

export function minutesOfHm(text: string): number {
  const parts: string[] = text.split(':');
  if (parts.length < 2) {
    return 0;
  }
  return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
}

export function hmText(minutes: number): string {
  const h: number = Math.floor(minutes / 60);
  const m: number = minutes % 60;
  return `${h < 10 ? `0${h}` : `${h}`}:${m < 10 ? `0${m}` : `${m}`}`;
}

/**
 * 由课程时间推导表格行：把所有课程的时间区间合并（重叠/相接的并成一段），
 * 每段一行，按开始时间排序。这样不用再维护一份"作息表"，
 * 课程改了时间，表格结构随之变化。
 */
export function derivePeriods(courses: TimetableCourse[]): PeriodRow[] {
  const intervals: number[][] = [];
  for (let i = 0; i < courses.length; i++) {
    const s: number = minutesOfHm(courses[i].startTime);
    const e: number = minutesOfHm(courses[i].endTime);
    if (e > s) {
      intervals.push([s, e]);
    }
  }
  intervals.sort((a: number[], b: number[]) => a[0] - b[0]);
  const merged: number[][] = [];
  for (let i = 0; i < intervals.length; i++) {
    const iv: number[] = intervals[i];
    if (merged.length === 0) {
      merged.push([iv[0], iv[1]]);
      continue;
    }
    const last: number[] = merged[merged.length - 1];
    if (iv[0] <= last[1]) {
      if (iv[1] > last[1]) {
        last[1] = iv[1];
      }
    } else {
      merged.push([iv[0], iv[1]]);
    }
  }
  const rows: PeriodRow[] = [];
  for (let i = 0; i < merged.length; i++) {
    rows.push(new PeriodRow(i + 1, merged[i][0], merged[i][1]));
  }
  return rows;
}
