import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { TimetableDemoData, DemoCourse } from '../common/TimetableDemoData';
import { SectionSchedule, PeriodDef, minutesOfTime } from '../common/SectionSchedule';
import { TimetableStore } from '../common/TimetableStore';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { CourseDetailSheet } from './CourseDetailSheet';
import { CourseEditSheet } from './CourseEditSheet';
import { ScheduleCalibratorSheet } from './ScheduleCalibratorSheet';

const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const DAY_NUMBERS: number[] = [1, 2, 3, 4, 5, 6, 7];

const DAY_START_HOUR: number = 6;
/** 时间轴视觉边界：24:00（当天第 1440 分钟），只作为刻度和空档末端，课程不会落在这里 */
const DAY_END_HOUR: number = 24;
/** 可填写的最晚时刻 23:59：时间选择器只支持 0-23 时，表单不接受 24:00 */
const MAX_EDIT_MINUTES: number = 23 * 60 + 59;
const HOUR_HEIGHT: number = 56;
const GUTTER_WIDTH: number = 42;
/** 七日课表：一行 = 一个节次，左栏显示节号与真实开始时间 */
const PERIOD_ROW_HEIGHT: number = 46;
/** 午休在表格里占一条横向留白带 */
const LUNCH_ROW_HEIGHT: number = 24;
/** 晚餐在表格里同样占一条留白带 */
const DINNER_ROW_HEIGHT: number = 22;
const PERIOD_GUTTER_WIDTH: number = 34;

/** 演示用周锚点：第 8 周的周一是 2026-10-19 */
const ANCHOR_YEAR: number = 2026;
const ANCHOR_MONTH: number = 9;
const ANCHOR_DAY: number = 19;
const ANCHOR_WEEK: number = 8;

const MODE_WEEK: string = 'week';
const MODE_DAY: string = 'day';

/**
 * 日程中心 → 课表视图。
 *
 * 两种模式：
 *   整周（默认）：以「节次」为行的七日表格。七列固定可见，左侧显示节号与真实开始时间，
 *                 跨节课程跨行展示，午休是一条横向留白带；
 *   单日时间轴：点某天表头进入。按真实时间线性排布，用于看具体某一节的间隔。
 * 点课程打开详情并可编辑/删除；「作息」打开时间轴校准器。
 *
 * 数据来自 `TimetableDemoData`（UI 演示数据），接入 TimetableService 后替换数据源。
 */
@Component
export struct TimetableView {
  @State selectedWeek: number = TimetableDemoData.CURRENT_WEEK;
  @State selectedDay: number = 1;
  @State mode: string = MODE_WEEK;
  @State courses: DemoCourse[] = TimetableStore.courses();
  @State showDetail: boolean = false;
  @State detailCourse: DemoCourse = TimetableDemoData.EMPTY_COURSE;
  @State showEdit: boolean = false;
  @State editCourse: DemoCourse = TimetableDemoData.EMPTY_COURSE;
  @State editIsNew: boolean = true;
  /** 学校作息：决定七天表格的行（节次）与每节真实时间 */
  @State schedule: SectionSchedule = TimetableStore.schedule();
  @State showCalibrator: boolean = false;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 组件可能被重建（切视图 / 切 Tab / 从详情返回），这里把最新改动读回来
    this.courses = TimetableStore.courses();
    this.schedule = TimetableStore.schedule();
    const weekday: number = new Date().getDay();
    this.selectedDay = weekday === 0 ? 7 : weekday;
  }

  // ---------- 日期 ----------

  private mondayOfWeek(week: number): Date {
    const base: Date = new Date(ANCHOR_YEAR, ANCHOR_MONTH, ANCHOR_DAY);
    base.setDate(base.getDate() + (week - ANCHOR_WEEK) * 7);
    return base;
  }

  private dateOfDay(day: number): Date {
    const monday: Date = this.mondayOfWeek(this.selectedWeek);
    return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + (day - 1));
  }

  private isToday(day: number): boolean {
    const weekday: number = new Date().getDay();
    return (weekday === 0 ? 7 : weekday) === day && this.selectedWeek === TimetableDemoData.CURRENT_WEEK;
  }

  /** 单日视图标题：第 8 周 · 周三 10.21 */
  private dayTitle(): string {
    const date: Date = this.dateOfDay(this.selectedDay);
    return `第 ${this.selectedWeek} 周 · 周${DAY_LABELS[this.selectedDay - 1]} ${date.getMonth() + 1}.${date.getDate()}`;
  }

  // ---------- 时间 ----------

  private hours(): number[] {
    const out: number[] = [];
    for (let h = DAY_START_HOUR; h < DAY_END_HOUR; h++) {
      out.push(h);
    }
    return out;
  }

  private gridHeight(): number {
    return this.hours().length * HOUR_HEIGHT;
  }

  private hourLabel(hour: number): string {
    return hour < 10 ? `0${hour}:00` : `${hour}:00`;
  }

  private minutesOf(time: string): number {
    const parts: string[] = time.split(':');
    if (parts.length < 2) {
      return 0;
    }
    return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
  }

  private formatMinutes(minutes: number): string {
    const h: number = Math.floor(minutes / 60);
    const m: number = minutes % 60;
    return `${h < 10 ? `0${h}` : `${h}`}:${m < 10 ? `0${m}` : `${m}`}`;
  }

  private blockTop(course: DemoCourse): number {
    const minutes: number = this.minutesOf(course.startTime) - DAY_START_HOUR * 60;
    return Math.max(0, (minutes / 60) * HOUR_HEIGHT);
  }

  private blockHeight(course: DemoCourse): number {
    const span: number = this.minutesOf(course.endTime) - this.minutesOf(course.startTime);
    return Math.max(26, (span / 60) * HOUR_HEIGHT);
  }

  private gapTop(gap: number[]): number {
    return Math.max(0, ((gap[0] - DAY_START_HOUR * 60) / 60) * HOUR_HEIGHT);
  }

  private gapHeight(gap: number[]): number {
    return ((gap[1] - gap[0]) / 60) * HOUR_HEIGHT;
  }

  // ---------- 节次表格的换算 ----------

  private periods(): PeriodDef[] {
    return this.schedule.periods();
  }

  private morningCount(): number {
    return this.schedule.morningCount();
  }

  /** 第 idx 节之前要插入哪条休息带：'lunch' / 'dinner' / '' */
  private bandBefore(idx: number): string {
    const list: PeriodDef[] = this.periods();
    if (idx <= 0 || idx >= list.length) {
      return '';
    }
    const prev: PeriodDef = list[idx - 1];
    const cur: PeriodDef = list[idx];
    const lunchS: number = minutesOfTime(this.schedule.lunchStart);
    const lunchE: number = minutesOfTime(this.schedule.lunchEnd);
    const dinnerS: number = minutesOfTime(this.schedule.dinnerStart);
    const dinnerE: number = minutesOfTime(this.schedule.dinnerEnd);
    if (prev.startMinutes < lunchS && cur.startMinutes >= lunchE) {
      return 'lunch';
    }
    if (prev.startMinutes < dinnerS && cur.startMinutes >= dinnerE) {
      return 'dinner';
    }
    return '';
  }

  private bandHeight(band: string): number {
    if (band === 'lunch') {
      return LUNCH_ROW_HEIGHT;
    }
    if (band === 'dinner') {
      return DINNER_ROW_HEIGHT;
    }
    return 0;
  }

  /** 整个表格的高度（含休息带） */
  private tableHeight(): number {
    const list: PeriodDef[] = this.periods();
    let height: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (i > 0) {
        height += this.bandHeight(this.bandBefore(i));
      }
      height += PERIOD_ROW_HEIGHT;
    }
    return height;
  }

  /** 第 index 节所在行的纵向位置 */
  private rowOffset(index: number): number {
    const list: PeriodDef[] = this.periods();
    let offset: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (i > 0) {
        offset += this.bandHeight(this.bandBefore(i));
      }
      if (list[i].index === index) {
        return offset;
      }
      offset += PERIOD_ROW_HEIGHT;
    }
    return offset;
  }

  /** 某一时刻落在第几节（取开始时间不晚于它的最后一节） */
  private periodIndexAt(minutes: number): number {
    const list: PeriodDef[] = this.periods();
    if (list.length === 0) {
      return 1;
    }
    let index: number = list[0].index;
    for (let i = 0; i < list.length; i++) {
      if (list[i].startMinutes <= minutes) {
        index = list[i].index;
      }
    }
    return index;
  }

  private startPeriodOf(course: DemoCourse): number {
    return this.periodIndexAt(this.minutesOf(course.startTime));
  }

  /** 结束节次：用 end-1 分钟判定，避免「09:40 恰好等于第二节结束」被算到下一节 */
  private endPeriodOf(course: DemoCourse): number {
    const startPeriod: number = this.startPeriodOf(course);
    const endMinutes: number = Math.max(this.minutesOf(course.endTime) - 1, this.minutesOf(course.startTime));
    return Math.max(startPeriod, this.periodIndexAt(endMinutes));
  }

  private courseTop(course: DemoCourse): number {
    return this.rowOffset(this.startPeriodOf(course));
  }

  private courseHeight(course: DemoCourse): number {
    const span: number = this.endPeriodOf(course) - this.startPeriodOf(course) + 1;
    return span * PERIOD_ROW_HEIGHT;
  }



  /** 当前时刻在时间轴上的纵向位置 */
  private nowTop(): number {
    const now: Date = new Date();
    const minutes: number = now.getHours() * 60 + now.getMinutes() - DAY_START_HOUR * 60;
    return Math.max(0, (minutes / 60) * HOUR_HEIGHT);
  }

  /** 当前时刻是否落在时间轴覆盖的 06:00–24:00 内 */
  private nowWithinAxis(): boolean {
    const now: Date = new Date();
    const minutes: number = now.getHours() * 60 + now.getMinutes();
    return minutes >= DAY_START_HOUR * 60 && minutes <= DAY_END_HOUR * 60;
  }

  // ---------- 课程与空档 ----------

  private coursesOnDay(day: number): DemoCourse[] {
    const out: DemoCourse[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const c: DemoCourse = this.courses[i];
      if (c.dayOfWeek === day && c.weeks.indexOf(this.selectedWeek) >= 0) {
        out.push(c);
      }
    }
    out.sort((a: DemoCourse, b: DemoCourse) => this.minutesOf(a.startTime) - this.minutesOf(b.startTime));
    return out;
  }

  private dayCourses(): DemoCourse[] {
    return this.coursesOnDay(this.selectedDay);
  }

  /** 某一天内的重叠分栏：周览表格与单日时间轴共用同一套排布规则 */
  private lanesOfDay(day: number): DemoCourse[][] {
    const list: DemoCourse[] = this.coursesOnDay(day);
    const lanes: DemoCourse[][] = [];
    for (let i = 0; i < list.length; i++) {
      const c: DemoCourse = list[i];
      let placed: boolean = false;
      for (let l = 0; l < lanes.length; l++) {
        const lane: DemoCourse[] = lanes[l];
        const last: DemoCourse = lane[lane.length - 1];
        if (this.minutesOf(last.endTime) <= this.minutesOf(c.startTime)) {
          lane.push(c);
          placed = true;
          break;
        }
      }
      if (!placed) {
        const nextLane: DemoCourse[] = [];
        nextLane.push(c);
        lanes.push(nextLane);
      }
    }
    return lanes;
  }

  private lanes(): DemoCourse[][] {
    return this.lanesOfDay(this.selectedDay);
  }

  private mergedIntervals(): number[][] {
    const list: DemoCourse[] = this.dayCourses();
    const intervals: number[][] = [];
    for (let i = 0; i < list.length; i++) {
      intervals.push([this.minutesOf(list[i].startTime), this.minutesOf(list[i].endTime)]);
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
    return merged;
  }

  private gaps(): number[][] {
    const merged: number[][] = this.mergedIntervals();
    const out: number[][] = [];
    let cursor: number = DAY_START_HOUR * 60;
    const end: number = DAY_END_HOUR * 60;
    for (let i = 0; i < merged.length; i++) {
      const iv: number[] = merged[i];
      if (iv[0] > cursor) {
        out.push([cursor, iv[0]]);
      }
      if (iv[1] > cursor) {
        cursor = iv[1];
      }
    }
    if (cursor < end) {
      out.push([cursor, end]);
    }
    const filtered: number[][] = [];
    for (let i = 0; i < out.length; i++) {
      if (out[i][1] - out[i][0] >= 30) {
        filtered.push(out[i]);
      }
    }
    return filtered;
  }

  /**
   * 课程色板：低饱和的旧纸色 + 同色系深墨左缘。
   * 只有 5 组、亮度接近，目标是像印刷品的套色，而不是一排彩色标签。
   * 顺序固定，同一门课在整周表格和单日时间轴里始终同色。
   */
  private tint(course: DemoCourse): ResourceColor {
    if (Theme.isMinimal(this.uiMode)) {
      return Theme.surface(this.uiMode);
    }
    const palette: Resource[] = [
      $r('app.color.course_tint_1'),
      $r('app.color.course_tint_2'),
      $r('app.color.course_tint_3'),
      $r('app.color.course_tint_4'),
      $r('app.color.course_tint_5'),
      $r('app.color.course_tint_6')
    ];
    return palette[course.tone % palette.length];
  }

  private edge(course: DemoCourse): ResourceColor {
    if (Theme.isMinimal(this.uiMode)) {
      return Theme.rule(this.uiMode);
    }
    const palette: Resource[] = [
      $r('app.color.course_edge_1'),
      $r('app.color.course_edge_2'),
      $r('app.color.course_edge_3'),
      $r('app.color.course_edge_4'),
      $r('app.color.course_edge_5'),
      $r('app.color.course_edge_6')
    ];
    return palette[course.tone % palette.length];
  }

  /**
   * 课程块的 ForEach key 必须带上会被编辑的字段。
   * 只写 id 的话，编辑保存后 id 不变，ArkUI 判定该项未变化而跳过重建，
   * 课程块就会停在旧的时间/标题上——这是"编辑后课表不刷新"的第二处原因。
   */
  private courseKey(course: DemoCourse): string {
    return `${course.id}|${course.dayOfWeek}|${course.startTime}|${course.endTime}` +
      `|${course.name}|${course.teacher}|${course.location}|${course.tone}|${course.weeks.join(',')}`;
  }

  /** 泳道 key 同样要跟着课程内容变化，否则整个泳道容器不会被重建 */
  private laneKey(day: number, lane: DemoCourse[], laneIndex: number): string {
    let key: string = `lane-${this.selectedWeek}-${day}-${laneIndex}`;
    for (let i = 0; i < lane.length; i++) {
      key += `#${this.courseKey(lane[i])}`;
    }
    return key;
  }

  // ---------- 交互 ----------

  private shiftWeek(delta: number): void {
    const next: number = this.selectedWeek + delta;
    if (next >= 1 && next <= TimetableDemoData.TOTAL_WEEKS) {
      this.selectedWeek = next;
    }
  }

  /** 单日翻页：跨周时自动落到相邻周的周一 / 周日 */
  private shiftDay(delta: number): void {
    let day: number = this.selectedDay + delta;
    if (day > 7) {
      if (this.selectedWeek < TimetableDemoData.TOTAL_WEEKS) {
        this.selectedWeek += 1;
        day = 1;
      } else {
        day = 7;
      }
    } else if (day < 1) {
      if (this.selectedWeek > 1) {
        this.selectedWeek -= 1;
        day = 7;
      } else {
        day = 1;
      }
    }
    this.selectedDay = day;
  }

  /** 左右滑：周览翻周，单日翻日 */
  private swipeNext(): void {
    if (this.mode === MODE_WEEK) {
      this.shiftWeek(1);
    } else {
      this.shiftDay(1);
    }
  }

  private swipePrev(): void {
    if (this.mode === MODE_WEEK) {
      this.shiftWeek(-1);
    } else {
      this.shiftDay(-1);
    }
  }

  /** 进入单日视图后把时间轴滚到第一节课，避免每次都从 06:00 的空白看起 */
  private enterDayMode(): void {
    this.mode = MODE_DAY;
    setTimeout(() => {
      this.scrollToFirstCourse();
    }, 80);
  }

  /**
   * 打开添加表单。
   * @param startTime 预填开始时间（点空档时传入空档起点）
   * @param gapEnd 可选：空档结束时间（当天第几分钟），用于把结束时间夹在空档内，
   *               避免点 30 分钟的空档却造出一门压到下一节课上的课程
   */
  private openAdd(startTime: string, gapEnd?: number): void {
    let startMinutes: number = this.minutesOf(startTime !== '' ? startTime : '08:00');
    if (startMinutes > MAX_EDIT_MINUTES - 15) {
      startMinutes = MAX_EDIT_MINUTES - 15;
    }
    let limit: number = MAX_EDIT_MINUTES;
    if (gapEnd !== undefined && gapEnd < limit) {
      limit = gapEnd;
    }
    let endMinutes: number = startMinutes + 100;
    if (endMinutes > limit) {
      endMinutes = limit;
    }
    if (endMinutes <= startMinutes) {
      endMinutes = Math.min(MAX_EDIT_MINUTES, startMinutes + 15);
    }
    this.editCourse = new DemoCourse('', '', '', '', this.selectedDay,
      this.formatMinutes(startMinutes), this.formatMinutes(endMinutes), [], 0);
    this.editIsNew = true;
    this.showEdit = true;
  }

  private openEdit(course: DemoCourse): void {
    this.showDetail = false;
    this.editCourse = course;
    this.editIsNew = false;
    this.showEdit = true;
  }

  private saveCourse(course: DemoCourse): void {
    const next: DemoCourse[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].id === course.id) {
        next.push(course);
        replaced = true;
      } else {
        next.push(this.courses[i]);
      }
    }
    if (!replaced) {
      next.push(course);
    }
    this.courses = next;
    // 同步写进进程内存储，组件重建后仍然是最新数据
    TimetableStore.save(course);
    this.showEdit = false;
    this.selectedDay = course.dayOfWeek;
  }

  private deleteCourse(course: DemoCourse): void {
    const next: DemoCourse[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].id !== course.id) {
        next.push(this.courses[i]);
      }
    }
    this.courses = next;
    TimetableStore.remove(course.id);
    this.showDetail = false;
  }

  private confirmDelete(course: DemoCourse): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除课程',
      message: `确定删除「${course.name}」吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.detail_ink') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.deleteCourse(course);
      }
    }).catch(() => {
    });
  }

  private showImportHint(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '导入课程表',
      message: 'JSON / 图片导入需要公共解析器（parseTimetableData、FakeTimetableImageParser），当前分支尚未接入。可先点空闲时段或「＋ 添加」手动录入。',
      buttons: [
        { text: '知道了', color: $r('app.color.detail_ink') }
      ]
    }).then(() => {
    }).catch(() => {
    });
  }

  private scrollToFirstCourse(): void {
    const list: DemoCourse[] = this.dayCourses();
    if (list.length === 0) {
      return;
    }
    const top: number = this.blockTop(list[0]) - 16;
    this.scroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, top), animation: true });
  }

  // ---------- 视图 ----------

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.ToolbarBlock()
        if (this.mode === MODE_WEEK) {
          this.WeekTableBlock()
        } else {
          this.WeekStripBlock()
          this.DayTimelineBlock()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg(this.uiMode))

      if (this.showDetail) {
        CourseDetailSheet({
          course: this.detailCourse,
          onClose: () => {
            this.showDetail = false;
          },
          onEdit: () => {
            this.openEdit(this.detailCourse);
          },
          onDelete: () => {
            this.confirmDelete(this.detailCourse);
          }
        })
      }

      if (this.showEdit) {
        CourseEditSheet({
          initial: this.editCourse,
          isNew: this.editIsNew,
          onSave: (course: DemoCourse) => {
            this.saveCourse(course);
          },
          onClose: () => {
            this.showEdit = false;
          }
        })
      }

      if (this.showCalibrator) {
        ScheduleCalibratorSheet({
          initial: this.schedule,
          onApply: (schedule: SectionSchedule) => {
            this.schedule = schedule;
            TimetableStore.setSchedule(schedule);
            this.showCalibrator = false;
          },
          onClose: () => {
            this.showCalibrator = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 左右滑：周览翻周、单日翻日。只接管水平方向，竖向滚动不受影响
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
        .onActionEnd((event: GestureEvent) => {
          // 任何弹层打开时都不翻页，避免在表单上横滑把底下的课表换掉
          if (this.showDetail || this.showEdit || this.showCalibrator) {
            return;
          }
          if (event.offsetX <= -48) {
            this.swipeNext();
          } else if (event.offsetX >= 48) {
            this.swipePrev();
          }
        })
    )
  }

  /**
   * 顶部工具条：整周只显示周次 + 学期；单日显示返回整周 + 当天日期。
   * 日程页本身已有标题栏，课表不能再叠一层大报头，否则课表被挤出屏幕。
   */
  @Builder
  ToolbarBlock() {
    Column() {
      if (this.mode === MODE_DAY) {
        Row({ space: 2 }) {
          Text('‹ 整周')
            .fontSize(12)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .height(36)
            .padding({ right: 6 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.mode = MODE_WEEK;
            })
          Blank()
          Column({ space: 1 }) {
            Text(this.dayTitle())
              .fontSize(13)
              .fontWeight(900)
              .fontColor(Theme.text(this.uiMode))
            Text('单日时间轴')
              .fontSize(8)
              .fontColor(Theme.sub(this.uiMode))
              .letterSpacing(1)
          }
          .alignItems(HorizontalAlign.Center)
          Blank()
          Text('＋')
            .fontSize(16)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .width(26)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openAdd('');
            })
        }
        .width('100%')
        .height(42)
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: 2 }) {
          Text('‹')
            .fontSize(18)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .width(22)
            .height(36)
            .textAlign(TextAlign.Center)
            .opacity(this.selectedWeek > 1 ? 1 : 0.25)
            .onClick(() => {
              this.shiftWeek(-1);
            })
          Column({ space: 1 }) {
            Text(`第 ${this.selectedWeek} 周`)
              .fontSize(17)
              .fontWeight(900)
              .fontColor(Theme.ink(this.uiMode))
            Text(TimetableDemoData.SEMESTER_NAME)
              .fontSize(8)
              .fontColor(Theme.sub(this.uiMode))
          }
          .alignItems(HorizontalAlign.Start)
          Text('›')
            .fontSize(18)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .width(22)
            .height(36)
            .textAlign(TextAlign.Center)
            .opacity(this.selectedWeek < TimetableDemoData.TOTAL_WEEKS ? 1 : 0.25)
            .onClick(() => {
              this.shiftWeek(1);
            })
          Blank()
          Text('作息')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.accent(this.uiMode))
            .height(36)
            .padding({ left: 5, right: 5 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showCalibrator = true;
            })
          Text('导入')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.accent(this.uiMode))
            .decoration({ type: TextDecorationType.Underline })
            .height(36)
            .padding({ left: 5, right: 5 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showImportHint();
            })
          Text('＋')
            .fontSize(16)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .width(26)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openAdd('');
            })
        }
        .width('100%')
        .height(42)
        .alignItems(VerticalAlign.Center)
      }

      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor(Theme.ink(this.uiMode))
    }
    .width('100%')
    .padding({
      left: StyleConstants.PAGE_PADDING_H,
      right: StyleConstants.PAGE_PADDING_H
    })
  }

  /**
   * 周览：表格形式。
   * 左侧时间栏 + 周一至周日七列；课程按开始时间占行、按时长跨行，
   * 一眼看出哪天哪一段有课、哪一段空着。点表头某天进入单日时间轴。
   */
  @Builder
  WeekTableBlock() {
    Column() {
      // 表头：星期行固定在顶部，七列始终可见
      Row() {
        Column()
          .width(PERIOD_GUTTER_WIDTH)
        ForEach(DAY_NUMBERS, (day: number) => {
          Column({ space: 1 }) {
            Text(DAY_LABELS[day - 1])
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isToday(day)
                ? Theme.accent(this.uiMode)
                : Theme.sub(this.uiMode))
            Text(`${this.dateOfDay(day).getDate()}`)
              .fontSize(14)
              .fontWeight(900)
              .fontColor(this.isToday(day)
                ? Theme.accent(this.uiMode)
                : Theme.text(this.uiMode))
            // 今天：小型砖红标记，而不是整格填色
            Column()
              .width(12)
              .height(3)
              .borderRadius(2)
              .backgroundColor(this.isToday(day)
                ? Theme.accent(this.uiMode)
                : Color.Transparent)
          }
          .layoutWeight(1)
          .height(46)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .border({
            width: { left: StyleConstants.HAIRLINE_HEIGHT },
            color: Theme.rule(this.uiMode)
          })
          .onClick(() => {
            this.selectedDay = day;
            this.enterDayMode();
          })
        }, (day: number) => `week-head-${day}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .border({
        width: { bottom: StyleConstants.RULE_HEAVY },
        color: Theme.ink(this.uiMode)
      })

      // 表体：节次栏 + 七列
      Scroll() {
        Row() {
          // 节次栏：节号 + 真实开始时间
          Column() {
            ForEach(this.periods(), (p: PeriodDef, idx: number) => {
              if (this.bandBefore(idx) !== '') {
                Column() {
                  Text(this.bandBefore(idx) === 'lunch' ? '午休' : '晚餐')
                    .fontSize(7)
                    .fontColor(Theme.sub(this.uiMode))
                }
                .width('100%')
                .height(this.bandHeight(this.bandBefore(idx)))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.End)
                .padding({ right: 3 })
                .backgroundColor(Theme.subtleBg(this.uiMode))
              }
              Column({ space: 0 }) {
                Text(`${p.index}`)
                  .fontSize(11)
                  .fontWeight(900)
                  .fontColor(Theme.text(this.uiMode))
                Text(p.start)
                  .fontSize(7)
                  .fontColor(Theme.sub(this.uiMode))
              }
              .width('100%')
              .height(PERIOD_ROW_HEIGHT)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.End)
              .padding({ right: 3 })
            }, (p: PeriodDef) => `gutter-${p.index}-${p.start}-${p.end}`)
          }
          .width(PERIOD_GUTTER_WIDTH)
          .height(this.tableHeight())

          // 七天
          ForEach(DAY_NUMBERS, (day: number) => {
            Stack({ alignContent: Alignment.TopStart }) {
              // 行网格 + 午休留白带
              Column() {
                ForEach(this.periods(), (p: PeriodDef, idx: number) => {
                  if (this.bandBefore(idx) !== '') {
                    Column()
                      .width('100%')
                      .height(this.bandHeight(this.bandBefore(idx)))
                      .backgroundColor(Theme.subtleBg(this.uiMode))
                  }
                  Column()
                    .width('100%')
                    .height(PERIOD_ROW_HEIGHT)
                    .border({
                      width: { top: StyleConstants.HAIRLINE_HEIGHT },
                      color: Theme.rule(this.uiMode)
                    })
                }, (p: PeriodDef) => `row-${day}-${p.index}`)
              }
              .width('100%')

              // 课程：跨节时跨行；同一天重叠时横向分栏
              Row() {
                ForEach(this.lanesOfDay(day), (lane: DemoCourse[], laneIndex: number) => {
                  Stack({ alignContent: Alignment.TopStart }) {
                    ForEach(lane, (course: DemoCourse) => {
                      this.PeriodCourseCell(course)
                    }, (course: DemoCourse) => `cell-${day}-${this.courseKey(course)}`)
                  }
                  .layoutWeight(1)
                  .height(this.tableHeight())
                }, (lane: DemoCourse[], laneIndex: number) => `lane-${day}-${this.laneKey(day, lane, laneIndex)}`)
              }
              .width('100%')
              .height(this.tableHeight())
            }
            .layoutWeight(1)
            .height(this.tableHeight())
            .border({
              width: { left: StyleConstants.HAIRLINE_HEIGHT },
              color: Theme.rule(this.uiMode)
            })
          }, (day: number) => `col-${day}`)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: StyleConstants.PAGE_PADDING_H,
      right: StyleConstants.PAGE_PADDING_H
    })
  }

  /** 课程块：列窄，只放短名；跨节之后高度足够才补教室 */
  @Builder
  PeriodCourseCell(course: DemoCourse) {
    Column({ space: 2 }) {
      Text(course.name)
        .fontSize(11)
        .fontWeight(900)
        .fontColor($r('app.color.ink_on_paper'))
        .maxLines(this.courseHeight(course) >= PERIOD_ROW_HEIGHT * 2 ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`${course.startTime}–${course.endTime}`)
        .fontSize(8)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink_on_paper'))
        .opacity(0.7)
        .maxLines(1)
        .width('100%')
      if (this.courseHeight(course) >= PERIOD_ROW_HEIGHT * 2) {
        if (course.location !== '') {
          Text(course.location)
            .fontSize(8)
            .fontColor($r('app.color.ink_on_paper'))
            .opacity(0.75)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (course.teacher !== '') {
          Text(course.teacher)
            .fontSize(8)
            .fontColor($r('app.color.ink_on_paper'))
            .opacity(0.6)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('96%')
    .height(this.courseHeight(course) - 3)
    .padding({
      left: 3,
      right: 2,
      top: 3,
      bottom: 2
    })
    .backgroundColor(this.tint(course))
    .border({
      width: { top: 2 },
      color: this.edge(course)
    })
    .position({ y: this.courseTop(course) })
    .onClick(() => {
      this.detailCourse = course;
      this.showDetail = true;
    })
  }

  @Builder
  WeekStripBlock() {
    Row() {
      ForEach(DAY_NUMBERS, (day: number) => {
        Column({ space: 2 }) {
          Text(DAY_LABELS[day - 1])
            .fontSize(10)
            .fontWeight(this.selectedDay === day ? 900 : FontWeight.Medium)
            .fontColor(this.selectedDay === day
              ? Theme.surface(this.uiMode)
              : (this.isToday(day) ? Theme.accent(this.uiMode) : Theme.sub(this.uiMode)))
          Text(`${this.dateOfDay(day).getDate()}`)
            .fontSize(18)
            .fontWeight(900)
            .fontColor(this.selectedDay === day
              ? Theme.surface(this.uiMode)
              : Theme.text(this.uiMode))
          Text(`${this.coursesOnDay(day).length}`)
            .fontSize(9)
            .fontColor(this.selectedDay === day
              ? Theme.surface(this.uiMode)
              : Theme.sub(this.uiMode))
          Row({ space: 2 }) {
            ForEach(this.coursesOnDay(day).slice(0, 3), (course: DemoCourse) => {
              Column()
                .width(4)
                .height(4)
                .borderRadius(2)
                .backgroundColor(this.selectedDay === day
                  ? Theme.surface(this.uiMode)
                  : this.edge(course))
            }, (course: DemoCourse) => `dot-${this.courseKey(course)}`)
          }
          .height(5)
        }
        .layoutWeight(1)
        .height(78)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.selectedDay === day ? Theme.ink(this.uiMode) : Color.Transparent)
        .borderRadius({
          topLeft: 0,
          topRight: 10,
          bottomLeft: 0,
          bottomRight: 10
        })
        .onClick(() => {
          this.selectedDay = day;
        })
      }, (day: number) => `strip-${day}`)
    }
    .width('100%')
    .padding({
      left: StyleConstants.PAGE_PADDING_H,
      right: StyleConstants.PAGE_PADDING_H
    })
    .margin({ bottom: StyleConstants.SPACE_XS })
  }

  @Builder
  DayTimelineBlock() {
    Scroll(this.scroller) {
      Row() {
        Column() {
          ForEach(this.hours(), (hour: number) => {
            Column() {
              Text(this.hourLabel(hour))
                .fontSize(9)
                .fontColor(Theme.sub(this.uiMode))
              Blank()
            }
            .width('100%')
            .height(HOUR_HEIGHT)
            .padding({ right: 5 })
            .alignItems(HorizontalAlign.End)
          }, (hour: number) => `hour-${hour}`)
        }
        .width(GUTTER_WIDTH)
        .height(this.gridHeight())
        // 时间轴主线：让左侧刻度读起来是一条连续的轴，而不是孤立的数字
        .border({
          width: { right: 1.5 },
          color: Theme.ink(this.uiMode)
        })

        Stack({ alignContent: Alignment.TopStart }) {
          // 整点刻度：只在轴线上往外留一小段短线。
          // 不再铺满整行的横线——那会让它读成"日历格子"，而不是时间轴。
          Column() {
            ForEach(this.hours(), (hour: number) => {
              Column() {
                Column()
                  .width(7)
                  .height(1)
                  .backgroundColor(Theme.sub(this.uiMode))
                  .opacity(0.45)
              }
              .width('100%')
              .height(HOUR_HEIGHT)
              .alignItems(HorizontalAlign.Start)
            }, (hour: number) => `tick-${hour}`)
          }
          .width('100%')

          Row() {
            ForEach(this.lanes(), (lane: DemoCourse[], laneIndex: number) => {
              Stack({ alignContent: Alignment.TopStart }) {
                ForEach(lane, (course: DemoCourse) => {
                  this.TimelineCourseBlock(course)
                }, (course: DemoCourse) => this.courseKey(course))
              }
              .layoutWeight(1)
              .height(this.gridHeight())
            }, (lane: DemoCourse[], laneIndex: number) => this.laneKey(this.selectedDay, lane, laneIndex))
          }
          .width('100%')
          .height(this.gridHeight())

          ForEach(this.gaps(), (gap: number[], gapIndex: number) => {
            this.GapBlock(gap)
          }, (gap: number[], gapIndex: number) => `gap-${gap[0]}-${gap[1]}`)

          // 当前时刻：只有看的正是今天时才出现
          if (this.isToday(this.selectedDay) && this.nowWithinAxis()) {
            Row() {
              Column()
                .width(7)
                .height(7)
                .borderRadius(4)
                .backgroundColor(Theme.accent(this.uiMode))
                .margin({ right: 2 })
              Column()
                .layoutWeight(1)
                .height(2)
                .backgroundColor(Theme.accent(this.uiMode))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .position({ x: 0, y: this.nowTop() })
          }
        }
        .layoutWeight(1)
        .height(this.gridHeight())
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  TimelineCourseBlock(course: DemoCourse) {
    Column({ space: 1 }) {
      Text(`${course.startTime} – ${course.endTime}`)
        .fontSize(9)
        .fontWeight(900)
        .fontColor(this.edge(course))
        .maxLines(1)
      Text(course.name)
        .fontSize(14)
        .fontWeight(900)
        .fontColor($r('app.color.ink_on_paper'))
        .maxLines(this.blockHeight(course) >= 70 ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.blockHeight(course) >= 70 && course.location !== '') {
        Text(course.location)
          .fontSize(9)
          .fontColor($r('app.color.ink_on_paper'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(this.blockHeight(course))
    .padding({
      left: 6,
      right: 6,
      top: 4,
      bottom: 4
    })
    .backgroundColor(this.tint(course))
    .border({
      width: { left: 2 },
      color: this.edge(course)
    })
    .position({ y: this.blockTop(course) })
    .onClick(() => {
      this.detailCourse = course;
      this.showDetail = true;
    })
  }

  /** 空闲时段：只留一行小字，不画边框，让课程块继续当主角 */
  @Builder
  GapBlock(gap: number[]) {
    Row() {
      Text(this.gapHeight(gap) >= 40
        ? `${this.formatMinutes(gap[0])}–${this.formatMinutes(gap[1])} 空闲 · 点击添加`
        : '＋')
        .fontSize(9)
        .fontColor(Theme.sub(this.uiMode))
        .opacity(0.7)
    }
    .width('100%')
    .height(this.gapHeight(gap))
    .padding({ left: 10 })
    .alignItems(VerticalAlign.Center)
    .position({ y: this.gapTop(gap) })
    .onClick(() => {
      this.openAdd(this.formatMinutes(gap[0]), gap[1]);
    })
  }
}
