import { CreateReminderInput } from '../model/CreateReminderInput';
import { OperationError, OperationResult } from '../model/OperationResult';
import { Reminder } from '../model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { ReminderService } from '../service/ReminderService';
import { computeCurrentWeek, formatCalendarDate, localDayCanonical, mondayOfWeek,
  occurrenceEpochMs, parseCalendarDate, validateTimetableDraft, validateTimetableSchedule
} from './parse/TimetableDataParser';
import { OccurrenceRecord, StoredCourse, StoredTimetable, TimetableDeleteSummary,
  TimetableDraft, TimetableReminderSummary, TimetableSaveResult, TimetableSchedule,
  WeekInfo } from './model/TimetableTypes';
import { TimetableRepository } from './repository/TimetableRepository';

function serviceError(code: string, message: string, retryable: boolean): OperationError {
  return { code: code, message: message, retryable: retryable };
}

const TIMETABLE_ID: string = 'timetable-1';

/**
 * 课程表业务入口。职责：保存课程表、计算当前周次、把"某课程某周"落地成
 * 一次性 TIME 提醒（内容含教室，走 ReminderService 公共创建链，不直接碰
 * ReminderRepository）。V1 每个用户一张课程表；重新导入会替换旧表并级联
 * 清理旧的未来提醒，已触发/已完成的保留作历史。
 */
export class TimetableService {
  private repository: TimetableRepository;
  private reminderService: ReminderService;
  private now: () => number;

  constructor(repository: TimetableRepository, reminderService: ReminderService, now: () => number) {
    this.repository = repository;
    this.reminderService = reminderService;
    this.now = now;
  }

  async getTimetable(): Promise<OperationResult<StoredTimetable>> {
    try {
      const stored = await this.repository.find();
      return { success: true, data: stored };
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表读取失败', true) };
    }
  }

  async getWeekInfo(): Promise<OperationResult<WeekInfo>> {
    let stored: StoredTimetable | undefined;
    try {
      stored = await this.repository.find();
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表读取失败', true) };
    }
    if (stored === undefined) {
      return { success: false, error: serviceError('TIMETABLE_NOT_FOUND', '尚未导入课程表', false) };
    }
    const anchorDateMs: number = parseCalendarDate(stored.anchorDate) as number;
    const currentWeek: number = computeCurrentWeek(anchorDateMs, stored.anchorWeek, this.now());
    let totalWeeks: number = 0;
    for (const course of stored.courses) {
      for (const week of course.weeks) {
        if (week > totalWeeks) {
          totalWeeks = week;
        }
      }
    }
    const mondayNow: number = mondayOfWeek(localDayCanonical(this.now()));
    const info: WeekInfo = {
      semesterName: stored.semesterName,
      currentWeek: currentWeek,
      totalWeeks: totalWeeks,
      weekStartDate: formatCalendarDate(mondayNow),
      weekEndDate: formatCalendarDate(mondayNow + 6 * 86400000)
    };
    return { success: true, data: info };
  }

  /**
   * 保存课程表（手动表单、教务 JSON、AI 图片确认后的统一入口）。
   * 保存成功后自动为本周与下周生成上课提醒；生成结果在 reminders 中逐项汇报。
   */
  async saveTimetable(draft: TimetableDraft): Promise<OperationResult<TimetableSaveResult>> {
    const issues = validateTimetableDraft(draft);
    if (issues.length > 0) {
      const first = issues[0];
      return { success: false, error: serviceError('TIMETABLE_INVALID_DRAFT',
        `${first.message}${first.field === undefined ? '' : ': ' + first.field}`, false) };
    }
    if (draft.schedule !== undefined && draft.schedule !== null) {
      const scheduleIssues = validateTimetableSchedule(draft.schedule);
      if (scheduleIssues.length > 0) {
        const first = scheduleIssues[0];
        return { success: false, error: serviceError('TIMETABLE_INVALID_DRAFT',
          `${first.message}${first.field === undefined ? '' : ': ' + first.field}`, false) };
      }
    }
    // 作息三态：undefined=沿用已存、null=清空、对象=替换
    let previous: StoredTimetable | undefined = undefined;
    try {
      previous = await this.repository.find();
    } catch (_) {
      previous = undefined;
    }
    try {
      await this.cascadeExisting();
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '旧课程表清理失败', true) };
    }
    const courses: StoredCourse[] = [];
    for (let i = 0; i < draft.courses.length; i++) {
      const course = draft.courses[i];
      courses.push({
        id: `course-${i + 1}`,
        name: course.name.trim(),
        teacher: course.teacher,
        location: course.location,
        dayOfWeek: course.dayOfWeek,
        startTime: course.startTime,
        endTime: course.endTime,
        weeks: course.weeks
      });
    }
    const stored: StoredTimetable = {
      id: TIMETABLE_ID,
      semesterName: draft.semesterName.trim(),
      anchorDate: draft.anchorDate,
      anchorWeek: draft.anchorWeek,
      courses: courses
    };
    let resolvedSchedule: TimetableSchedule | null | undefined;
    if (draft.schedule === undefined) {
      resolvedSchedule = previous === undefined ? undefined : previous.schedule;
    } else {
      resolvedSchedule = draft.schedule;
    }
    if (resolvedSchedule !== undefined) {
      stored.schedule = resolvedSchedule;
    }
    try {
      await this.repository.save(stored, []);
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表保存失败', true) };
    }
    const reminders = await this.ensureUpcomingReminders();
    return { success: true, data: { timetable: stored, reminders: reminders.data as TimetableReminderSummary } };
  }

  /**
   * 为本周与下周生成上课提醒（重复调用安全：已生成的按台账跳过）。
   * 应用启动/回到前台时由集成入口调用，保证滚动窗口内的提醒始终存在。
   */
  async ensureUpcomingReminders(): Promise<OperationResult<TimetableReminderSummary>> {
    let stored: StoredTimetable | undefined;
    let occurrences: OccurrenceRecord[];
    try {
      stored = await this.repository.find();
      occurrences = await this.repository.findOccurrences();
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表读取失败', true) };
    }
    if (stored === undefined) {
      return { success: false, error: serviceError('TIMETABLE_NOT_FOUND', '尚未导入课程表', false) };
    }
    const summary: TimetableReminderSummary = {
      createdCount: 0, skippedExistingCount: 0, skippedPastCount: 0, failedCount: 0, failures: []
    };
    const knownKeys = new Set<string>();
    for (const occ of occurrences) {
      knownKeys.add(occ.key);
    }
    const anchorDateMs: number = parseCalendarDate(stored.anchorDate) as number;
    const nowMs: number = this.now();
    const currentWeek: number = computeCurrentWeek(anchorDateMs, stored.anchorWeek, nowMs);
    const newOccurrences: OccurrenceRecord[] = [];
    for (const weekOffset of [0, 1]) {
      const week: number = currentWeek + weekOffset;
      for (const course of stored.courses) {
        if (!course.weeks.includes(week)) {
          continue;
        }
        const key: string = `${course.id}|w${week}`;
        if (knownKeys.has(key)) {
          summary.skippedExistingCount++;
          continue;
        }
        const triggerTime: number | undefined =
          occurrenceEpochMs(anchorDateMs, stored.anchorWeek, week, course.dayOfWeek, course.startTime);
        if (triggerTime === undefined) {
          summary.failedCount++;
          summary.failures.push(`${key}: INVALID_START_TIME`);
          continue;
        }
        if (triggerTime <= nowMs) {
          summary.skippedPastCount++;
          continue;
        }
        const input: CreateReminderInput = {
          content: course.location === undefined || course.location.trim().length === 0
            ? course.name : `${course.name} @ ${course.location.trim()}`,
          triggerType: TriggerType.TIME,
          triggerTime: triggerTime,
          source: ReminderSource.MANUAL
        };
        const created = await this.reminderService.create(input);
        if (created.success && created.data !== undefined) {
          newOccurrences.push({ key: key, reminderId: created.data.id, week: week, courseId: course.id });
          knownKeys.add(key);
          summary.createdCount++;
        } else {
          summary.failedCount++;
          summary.failures.push(`${key}: ${created.error === undefined ? 'UNKNOWN' : created.error.code}`);
        }
      }
    }
    if (newOccurrences.length > 0) {
      try {
        await this.repository.save(stored, occurrences.concat(newOccurrences));
      } catch (_) {
        return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '生成记录保存失败', true) };
      }
    }
    return { success: true, data: summary };
  }

  /** 删除课程表：清理其创建的未触发提醒；已触发/已完成的保留作历史。 */
  async deleteTimetable(): Promise<OperationResult<TimetableDeleteSummary>> {
    let stored: StoredTimetable | undefined;
    let occurrences: OccurrenceRecord[];
    try {
      stored = await this.repository.find();
      occurrences = await this.repository.findOccurrences();
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表读取失败', true) };
    }
    if (stored === undefined) {
      return { success: false, error: serviceError('TIMETABLE_NOT_FOUND', '尚未导入课程表', false) };
    }
    const summary: TimetableDeleteSummary = { deletedCount: 0, keptHistoryCount: 0, failedCount: 0 };
    for (const occ of occurrences) {
      const loaded: OperationResult<Reminder> = await this.reminderService.findById(occ.reminderId);
      if (!loaded.success || loaded.data === undefined) {
        summary.failedCount++;
        continue;
      }
      const status: ReminderStatus = loaded.data.status;
      if (status === ReminderStatus.TRIGGERED || status === ReminderStatus.COMPLETED) {
        summary.keptHistoryCount++;
        continue;
      }
      const deleted = await this.reminderService.delete(occ.reminderId);
      if (deleted.success) {
        summary.deletedCount++;
      } else {
        summary.failedCount++;
      }
    }
    try {
      await this.repository.clear();
    } catch (_) {
      return { success: false, error: serviceError('TIMETABLE_STORE_ERROR', '课程表清理失败', true) };
    }
    return { success: true, data: summary };
  }

  /** 替换导入前清理旧表的未来提醒；已触发/已完成的同样保留。 */
  private async cascadeExisting(): Promise<void> {
    const stored = await this.repository.find();
    if (stored === undefined) {
      return;
    }
    const occurrences = await this.repository.findOccurrences();
    for (const occ of occurrences) {
      const loaded: OperationResult<Reminder> = await this.reminderService.findById(occ.reminderId);
      if (!loaded.success || loaded.data === undefined) {
        continue;
      }
      const status: ReminderStatus = loaded.data.status;
      if (status === ReminderStatus.TRIGGERED || status === ReminderStatus.COMPLETED) {
        continue;
      }
      await this.reminderService.delete(occ.reminderId);
    }
    await this.repository.clear();
  }
}
