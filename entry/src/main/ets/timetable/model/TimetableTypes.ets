// 课程表模块内部类型。全部位于 timetable/ 内部，不进入公共 model/**，
// 不修改任何冻结接口；生成正式提醒统一通过 ReminderService 完成。

export interface CourseDraft {
  name: string;
  teacher?: string;
  location?: string;
  /** 1=周一 … 7=周日 */
  dayOfWeek: number;
  /** "HH:mm"，设备本地时区的墙上时间 */
  startTime: string;
  endTime: string;
  /** 上课周次列表，1..30；单双周由导入方展开成列表 */
  weeks: number[];
}

/** 单节手动覆盖：index 为第几节 */
export interface ScheduleOverride {
  index: number;
  start: string;
  end: string;
}

/** 作息（仅展示用）：决定周表怎么画行、午休/晚餐带放哪；不参与提醒生成链路。 */
export interface TimetableSchedule {
  firstStart: string;
  duration: number;
  breakMinutes: number;
  lunchStart?: string;
  lunchEnd?: string;
  dinnerStart?: string;
  dinnerEnd?: string;
  overrides?: ScheduleOverride[];
  locked?: number[];
}

export interface TimetableDraft {
  semesterName: string;
  /** 锚点日期 "YYYY-MM-DD"，该日期属于 anchorWeek 周 */
  anchorDate: string;
  anchorWeek: number;
  /** 三态：undefined=沿用已存作息；null=清空；值=替换 */
  schedule?: TimetableSchedule | null;
  courses: CourseDraft[];
}

export interface StoredCourse {
  id: string;
  name: string;
  teacher?: string;
  location?: string;
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  weeks: number[];
}

export interface StoredTimetable {
  id: string;
  semesterName: string;
  anchorDate: string;
  anchorWeek: number;
  courses: StoredCourse[];
  /** undefined = 未设置作息 */
  schedule?: TimetableSchedule;
}

/** 一次"某课程某周"的上课实例与已创建提醒的对应关系（去重与级联删除的依据） */
export interface OccurrenceRecord {
  key: string;
  reminderId: string;
  week: number;
  courseId: string;
}

export interface WeekInfo {
  semesterName: string;
  currentWeek: number;
  totalWeeks: number;
  weekStartDate: string;
  weekEndDate: string;
}

export interface TimetableReminderSummary {
  createdCount: number;
  skippedExistingCount: number;
  skippedPastCount: number;
  failedCount: number;
  failures: string[];
}

export interface TimetableDeleteSummary {
  deletedCount: number;
  keptHistoryCount: number;
  failedCount: number;
}

export interface TimetableSaveResult {
  timetable: StoredTimetable;
  reminders: TimetableReminderSummary;
}

export enum TimetableParseIssueCode {
  INVALID_JSON = 'INVALID_JSON',
  MISSING_FIELD = 'MISSING_FIELD',
  INVALID_FIELD = 'INVALID_FIELD'
}

export interface TimetableParseIssue {
  code: TimetableParseIssueCode;
  field?: string;
  message: string;
}
