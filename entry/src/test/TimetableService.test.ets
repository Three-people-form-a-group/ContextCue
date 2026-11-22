import { describe, it, expect } from '@ohos/hypium';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { ReminderService } from '../main/ets/service/ReminderService';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';
import { TimetableDraft } from '../main/ets/timetable/model/TimetableTypes';
import { InMemoryTimetableRepository } from '../main/ets/timetable/repository/InMemoryTimetableRepository';
import { TimetableService } from '../main/ets/timetable/TimetableService';

class StubTimePort implements TimeTriggerPort {
  scheduled: string[] = [];
  cancelled: string[] = [];
  async schedule(reminder: Reminder): Promise<void> { this.scheduled.push(reminder.id); }
  async cancel(id: string): Promise<void> { this.cancelled.push(id); }
}

class StubLocationPort implements LocationTriggerPort {
  registered: string[] = [];
  unregistered: string[] = [];
  async register(reminder: Reminder): Promise<void> { this.registered.push(reminder.id); }
  async unregister(id: string): Promise<void> { this.unregistered.push(id); }
  async isInsideScene(_sceneId: string): Promise<boolean> { return false; }
}

const MATH_WEEK8: number = new Date(2026, 9, 26, 8, 0).getTime();
const ENGLISH_WEEK8: number = new Date(2026, 9, 28, 14, 0).getTime();

function draft(): TimetableDraft {
  const mathWeeks: number[] = [];
  for (let w = 1; w <= 16; w++) {
    mathWeeks.push(w);
  }
  return {
    semesterName: '2026-2027学年第一学期',
    anchorDate: '2026-10-26',
    anchorWeek: 8,
    courses: [
      { name: '高等数学', location: '教三-401', dayOfWeek: 1, startTime: '08:00', endTime: '09:40', weeks: mathWeeks },
      { name: '大学英语', teacher: '李老师', dayOfWeek: 3, startTime: '14:00', endTime: '15:40', weeks: [8, 9, 10] }
    ]
  };
}

class Stack {
  timePort: StubTimePort = new StubTimePort();
  locationPort: StubLocationPort = new StubLocationPort();
  reminderRepository: InMemoryReminderRepository = new InMemoryReminderRepository();
  timetableRepository: InMemoryTimetableRepository = new InMemoryTimetableRepository();
  reminderService: ReminderService;
  timetableService: TimetableService;
  nowMs: number;

  constructor(nowMs: number) {
    this.nowMs = nowMs;
    let seq: number = 0;
    const clock = (): number => this.nowMs;
    this.reminderService = new ReminderService(this.reminderRepository, this.timePort, this.locationPort,
      clock, (): string => {
        seq++;
        return `rem-${seq}`;
      });
    this.timetableService = new TimetableService(this.timetableRepository, this.reminderService, clock);
  }
}

export default function timetableServiceTest() {
  describe('timetableServiceTest', () => {
    it('saves a timetable and auto creates this and next week reminders', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      const saved = await stack.timetableService.saveTimetable(draft());
      expect(saved.success).assertTrue();
      expect(saved.data?.reminders.createdCount).assertEqual(4);
      expect(saved.data?.reminders.skippedPastCount).assertEqual(0);
      expect(stack.timePort.scheduled.length).assertEqual(4);
      const all = await stack.reminderService.findAll();
      expect(all.data?.length).assertEqual(4);
    });
    it('creates TIME reminders with classroom in content and manual source', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const all = (await stack.reminderService.findAll()).data as Reminder[];
      const math = all.find((r: Reminder): boolean => r.triggerTime === MATH_WEEK8);
      const english = all.find((r: Reminder): boolean => r.triggerTime === ENGLISH_WEEK8);
      expect(math?.content).assertEqual('高等数学 @ 教三-401');
      expect(math?.triggerType).assertEqual(TriggerType.TIME);
      expect(math?.source).assertEqual(ReminderSource.MANUAL);
      expect(math?.status).assertEqual(ReminderStatus.ACTIVE);
      expect(english?.content).assertEqual('大学英语');
      expect(english?.triggerTime).assertEqual(ENGLISH_WEEK8);
    });
    it('skips already generated occurrences on repeated calls', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const again = await stack.timetableService.ensureUpcomingReminders();
      expect(again.success).assertTrue();
      expect(again.data?.createdCount).assertEqual(0);
      expect(again.data?.skippedExistingCount).assertEqual(4);
      expect(stack.timePort.scheduled.length).assertEqual(4);
      const all = await stack.reminderService.findAll();
      expect(all.data?.length).assertEqual(4);
    });
    it('skips past slots of the current week without creating them', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 10, 0).getTime());
      const saved = await stack.timetableService.saveTimetable(draft());
      expect(saved.data?.reminders.createdCount).assertEqual(3);
      expect(saved.data?.reminders.skippedPastCount).assertEqual(1);
      const all = (await stack.reminderService.findAll()).data as Reminder[];
      expect(all.find((r: Reminder): boolean => r.triggerTime === MATH_WEEK8)).assertUndefined();
    });
    it('only generates courses scheduled in the window weeks', 0, async () => {
      const stack = new Stack(new Date(2026, 10, 9, 7, 0).getTime());
      const saved = await stack.timetableService.saveTimetable(draft());
      expect(saved.data?.reminders.createdCount).assertEqual(3);
      const all = (await stack.reminderService.findAll()).data as Reminder[];
      // Nov 9 starts week 10: English still runs on Nov 11, but not in week 11 (Nov 18).
      expect(all.find((r: Reminder): boolean => r.content === '大学英语')?.triggerTime)
        .assertEqual(new Date(2026, 10, 11, 14, 0).getTime());
      expect(all.find((r: Reminder): boolean => r.triggerTime === new Date(2026, 10, 18, 14, 0).getTime()))
        .assertUndefined();
    });
    it('reports current week and semester boundaries', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const info = await stack.timetableService.getWeekInfo();
      expect(info.success).assertTrue();
      expect(info.data?.currentWeek).assertEqual(8);
      expect(info.data?.totalWeeks).assertEqual(16);
      expect(info.data?.weekStartDate).assertEqual('2026-10-26');
      expect(info.data?.weekEndDate).assertEqual('2026-11-01');
      stack.nowMs = new Date(2026, 10, 1, 23, 59).getTime();
      expect((await stack.timetableService.getWeekInfo()).data?.currentWeek).assertEqual(8);
      stack.nowMs = new Date(2026, 10, 2, 0, 1).getTime();
      expect((await stack.timetableService.getWeekInfo()).data?.currentWeek).assertEqual(9);
    });
    it('fails week info and ensure before any timetable is imported', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      const info = await stack.timetableService.getWeekInfo();
      expect(info.success).assertFalse();
      expect(info.error?.code).assertEqual('TIMETABLE_NOT_FOUND');
      const ensure = await stack.timetableService.ensureUpcomingReminders();
      expect(ensure.error?.code).assertEqual('TIMETABLE_NOT_FOUND');
    });
    it('rejects invalid drafts without storing anything', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      const bad: TimetableDraft = {
        semesterName: '学期', anchorDate: '2026-10-26', anchorWeek: 8,
        courses: [{ name: '   ', dayOfWeek: 1, startTime: '08:00', endTime: '09:40', weeks: [8] }]
      };
      const saved = await stack.timetableService.saveTimetable(bad);
      expect(saved.success).assertFalse();
      expect(saved.error?.code).assertEqual('TIMETABLE_INVALID_DRAFT');
      const stored = await stack.timetableService.getTimetable();
      expect(stored.data).assertUndefined();
      const all = await stack.reminderService.findAll();
      expect(all.data?.length).assertEqual(0);
    });
    it('replaces a re-imported timetable without leaving duplicates', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const second = await stack.timetableService.saveTimetable(draft());
      expect(second.data?.reminders.createdCount).assertEqual(4);
      const all = await stack.reminderService.findAll();
      expect(all.data?.length).assertEqual(4);
      const occs = await stack.timetableRepository.findOccurrences();
      expect(occs.length).assertEqual(4);
    });
    it('cascades deletion of old reminders when a changed timetable is imported', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const replacement: TimetableDraft = {
        semesterName: '2026-2027学年第一学期', anchorDate: '2026-10-26', anchorWeek: 8,
        courses: [{ name: '大学英语', dayOfWeek: 3, startTime: '14:00', endTime: '15:40', weeks: [8, 9, 10] }]
      };
      const saved = await stack.timetableService.saveTimetable(replacement);
      expect(saved.data?.reminders.createdCount).assertEqual(2);
      const all = (await stack.reminderService.findAll()).data as Reminder[];
      expect(all.length).assertEqual(2);
      expect(all.find((r: Reminder): boolean => r.content === '高等数学 @ 教三-401')).assertUndefined();
      expect(stack.timePort.cancelled.length).assertEqual(4);
    });
    it('keeps triggered reminders as history when the timetable is deleted', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const all = (await stack.reminderService.findAll()).data as Reminder[];
      const math = all.find((r: Reminder): boolean => r.triggerTime === MATH_WEEK8) as Reminder;
      const marked = await stack.reminderService.markTriggered(math.id, stack.nowMs);
      expect(marked.success).assertTrue();
      const deleted = await stack.timetableService.deleteTimetable();
      expect(deleted.data?.deletedCount).assertEqual(3);
      expect(deleted.data?.keptHistoryCount).assertEqual(1);
      expect(deleted.data?.failedCount).assertEqual(0);
      const remaining = (await stack.reminderService.findAll()).data as Reminder[];
      expect(remaining.length).assertEqual(1);
      expect(remaining[0].status).assertEqual(ReminderStatus.TRIGGERED);
      const info = await stack.timetableService.getWeekInfo();
      expect(info.error?.code).assertEqual('TIMETABLE_NOT_FOUND');
    });
    it('deletes the timetable with all untriggered reminders', 0, async () => {
      const stack = new Stack(new Date(2026, 9, 26, 7, 0).getTime());
      await stack.timetableService.saveTimetable(draft());
      const deleted = await stack.timetableService.deleteTimetable();
      expect(deleted.data?.deletedCount).assertEqual(4);
      const all = await stack.reminderService.findAll();
      expect(all.data?.length).assertEqual(0);
      expect(stack.timePort.cancelled.length).assertEqual(4);
    });
    it('stores schedule, keeps it on schedule-less re-imports, clears on explicit null', 0, async () => {
      const stack = new Stack(new Date(2026, 10, 16, 7, 0).getTime());
      const withSchedule = draft();
      withSchedule.schedule = { firstStart: '08:00', duration: 45, breakMinutes: 10 };
      await stack.timetableService.saveTimetable(withSchedule);
      expect((await stack.timetableService.getTimetable()).data?.schedule?.firstStart).assertEqual('08:00');
      await stack.timetableService.saveTimetable(draft());
      expect((await stack.timetableService.getTimetable()).data?.schedule?.firstStart).assertEqual('08:00');
      const cleared = draft();
      cleared.schedule = null;
      await stack.timetableService.saveTimetable(cleared);
      // 清空语义：存储表示 null 或 undefined 均视为无作息（罗鸿程实现保留 null）
      const clearedSchedule = (await stack.timetableService.getTimetable()).data?.schedule;
      expect(clearedSchedule === undefined || clearedSchedule === null).assertTrue();
    });
    it('rejects an invalid schedule in the draft', 0, async () => {
      const stack = new Stack(new Date(2026, 10, 16, 7, 0).getTime());
      const bad = draft();
      bad.schedule = { firstStart: '08:00', duration: 0, breakMinutes: 10 };
      const saved = await stack.timetableService.saveTimetable(bad);
      expect(saved.success).assertFalse();
      expect(saved.error?.code).assertEqual('TIMETABLE_INVALID_DRAFT');
      expect((await stack.reminderService.findAll()).data?.length).assertEqual(0);
    });
  });
}
