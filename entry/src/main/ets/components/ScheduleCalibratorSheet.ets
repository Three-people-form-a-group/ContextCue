import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import {
  SectionSchedule,
  PeriodDef,
  PeriodOverride,
  minutesOfTime,
  formatMinutesOf
} from '../common/SectionSchedule';

const TEMPLATE_REGULAR: string = 'regular';
const TEMPLATE_BLOCK: string = 'block';
const TEMPLATE_EARLY: string = 'early';
const TEMPLATE_SHORT_LUNCH: string = 'short_lunch';

const DURATION_MIN: number = 25;
const DURATION_MAX: number = 120;
const BREAK_MIN: number = 0;
const BREAK_MAX: number = 30;
const STEP: number = 5;

/**
 * 时间轴校准器：先配置规律，再修改例外。
 *
 * 第一步选模板 → 第二步只填 4 个关键参数 → 第三步在实时预览里单独调整 / 锁定某节。
 * 所有修改都在本地即时重算，点「应用」才写回课表。
 *
 * 注意：当前只做「节次 → 真实时间」的换算，课程仍按真实时间存储。
 * 真正要让改作息后自动重排课程、同步提醒，需要公共层支持作息规则。
 */
@Component
export struct ScheduleCalibratorSheet {
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  initial: SectionSchedule = SectionSchedule.regular();
  onApply: (schedule: SectionSchedule) => void = () => {};
  onClose: () => void = () => {};

  @State template: string = TEMPLATE_REGULAR;
  @State firstStart: string = '08:00';
  @State duration: number = 45;
  @State breakMinutes: number = 10;
  @State lunchStart: string = '12:00';
  @State lunchEnd: string = '14:00';
  @State dinnerStart: string = '17:30';
  @State dinnerEnd: string = '18:30';
  @State overrides: PeriodOverride[] = [];
  @State locked: number[] = [];

  aboutToAppear(): void {
    this.load(this.initial);
  }

  private load(schedule: SectionSchedule): void {
    this.firstStart = schedule.firstStart;
    this.duration = schedule.duration;
    this.breakMinutes = schedule.breakMinutes;
    this.lunchStart = schedule.lunchStart;
    this.lunchEnd = schedule.lunchEnd;
    this.dinnerStart = schedule.dinnerStart;
    this.dinnerEnd = schedule.dinnerEnd;
    this.overrides = schedule.overrides.slice();
    this.locked = schedule.locked.slice();
  }

  private buildSchedule(): SectionSchedule {
    return new SectionSchedule(this.firstStart, this.duration, this.breakMinutes,
      this.lunchStart, this.lunchEnd, this.dinnerStart, this.dinnerEnd,
      this.overrides.slice(), this.locked.slice());
  }

  private previewPeriods(): PeriodDef[] {
    return this.buildSchedule().periods();
  }

  private lunchStartMinutes(): number {
    return minutesOfTime(this.lunchStart);
  }

  // ---------- 模板 ----------

  private applyTemplate(key: string): void {
    this.template = key;
    if (key === TEMPLATE_REGULAR) {
      this.load(SectionSchedule.regular());
    } else if (key === TEMPLATE_BLOCK) {
      this.load(SectionSchedule.block());
    } else if (key === TEMPLATE_EARLY) {
      this.load(SectionSchedule.early());
    } else if (key === TEMPLATE_SHORT_LUNCH) {
      this.load(SectionSchedule.shortLunch());
    }
  }

  // ---------- 参数 ----------

  private stepDuration(delta: number): void {
    this.duration = Math.min(DURATION_MAX, Math.max(DURATION_MIN, this.duration + delta));
  }

  private stepBreak(delta: number): void {
    this.breakMinutes = Math.min(BREAK_MAX, Math.max(BREAK_MIN, this.breakMinutes + delta));
  }

  private pickTime(current: string, onAccept: (minutes: number) => void): void {
    const date: Date = new Date();
    const minutes: number = minutesOfTime(current);
    date.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: date,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        onAccept(value.hour * 60 + value.minute);
      }
    });
  }

  private pickFirstStart(): void {
    this.pickTime(this.firstStart, (minutes: number) => {
      this.firstStart = formatMinutesOf(minutes);
      // 改基准起点时，未锁定的单独调整会失去意义，清掉以免出现奇怪的空档
      const kept: PeriodOverride[] = [];
      for (let i = 0; i < this.overrides.length; i++) {
        if (this.locked.indexOf(this.overrides[i].index) >= 0) {
          kept.push(this.overrides[i]);
        }
      }
      this.overrides = kept;
    });
  }

  private pickLunchStart(): void {
    this.pickTime(this.lunchStart, (minutes: number) => {
      this.lunchStart = formatMinutesOf(minutes);
    });
  }

  private pickLunchEnd(): void {
    this.pickTime(this.lunchEnd, (minutes: number) => {
      this.lunchEnd = formatMinutesOf(minutes);
    });
  }

  private pickDinnerStart(): void {
    this.pickTime(this.dinnerStart, (minutes: number) => {
      this.dinnerStart = formatMinutesOf(minutes);
    });
  }

  private pickDinnerEnd(): void {
    this.pickTime(this.dinnerEnd, (minutes: number) => {
      this.dinnerEnd = formatMinutesOf(minutes);
    });
  }

  // ---------- 单节调整 ----------

  private pickPeriod(index: number): void {
    const list: PeriodDef[] = this.previewPeriods();
    let target: PeriodDef | undefined = undefined;
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        target = list[i];
      }
    }
    if (target === undefined) {
      return;
    }
    const current: PeriodDef = target;
    this.pickTime(current.start, (minutes: number) => {
      this.askShift(index, minutes);
    });
  }

  /** 改某一节时，问清楚是只动这一节，还是带动后续 */
  private askShift(index: number, newStart: number): void {
    const list: PeriodDef[] = this.previewPeriods();
    let target: PeriodDef | undefined = undefined;
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        target = list[i];
      }
    }
    if (target === undefined || target.startMinutes === newStart) {
      return;
    }
    const isLast: boolean = list[list.length - 1].index === index;

    if (isLast) {
      this.applyOnlyThis(index, newStart);
      return;
    }

    this.getUIContext().getPromptAction().showDialog({
      title: `第 ${index} 节改到 ${formatMinutesOf(newStart)}`,
      message: '后续节次要跟着一起移动，还是只调整这一节？锁定过的节次不会被移动。',
      buttons: [
        { text: '取消', color: $r('app.color.detail_ink') },
        { text: '只改本节', color: $r('app.color.detail_ink') },
        { text: '本节及后续', color: $r('app.color.detail_ink') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.applyOnlyThis(index, newStart);
      } else if (result.index === 2) {
        this.applyCascade(index, newStart);
      }
    }).catch(() => {
    });
  }

  private applyOnlyThis(index: number, newStart: number): void {
    const list: PeriodDef[] = this.previewPeriods();
    let target: PeriodDef | undefined = undefined;
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        target = list[i];
      }
    }
    if (target === undefined) {
      return;
    }
    this.overrides = this.withOverride(this.overrides, index,
      newStart, newStart + target.duration());
  }

  private applyCascade(index: number, newStart: number): void {
    const list: PeriodDef[] = this.previewPeriods();
    let delta: number = 0;
    let isFirst: boolean = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].index === index) {
        delta = newStart - list[i].startMinutes;
        isFirst = i === 0;
      }
    }
    if (delta === 0) {
      return;
    }

    if (isFirst) {
      // 第一节整体后移：改基准即可，锁定的节次保留它自己的时间
      this.firstStart = formatMinutesOf(newStart);
      const kept: PeriodOverride[] = [];
      for (let i = 0; i < this.overrides.length; i++) {
        if (this.locked.indexOf(this.overrides[i].index) >= 0) {
          kept.push(this.overrides[i]);
        }
      }
      this.overrides = kept;
      return;
    }

    let next: PeriodOverride[] = this.overrides.slice();
    for (let i = 0; i < list.length; i++) {
      const p: PeriodDef = list[i];
      if (p.index < index || this.locked.indexOf(p.index) >= 0) {
        continue;
      }
      next = this.withOverride(next, p.index, p.startMinutes + delta, p.endMinutes + delta);
    }
    this.overrides = next;
  }

  private withOverride(source: PeriodOverride[], index: number,
    startMinutes: number, endMinutes: number): PeriodOverride[] {
    const next: PeriodOverride[] = [];
    for (let i = 0; i < source.length; i++) {
      if (source[i].index !== index) {
        next.push(source[i]);
      }
    }
    next.push(new PeriodOverride(index, formatMinutesOf(startMinutes), formatMinutesOf(endMinutes)));
    return next;
  }

  private toggleLock(index: number): void {
    const next: number[] = this.locked.slice();
    const at: number = next.indexOf(index);
    if (at >= 0) {
      next.splice(at, 1);
    } else {
      next.push(index);
    }
    this.locked = next;
  }

  private isOverridden(index: number): boolean {
    return this.buildSchedule().overrideFor(index) !== undefined;
  }

  // ---------- 视图 ----------

  @Builder
  SectionLabel(text: string) {
    Text(text)
      .fontSize(StyleConstants.FONT_SECTION_INDEX)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.sub(this.uiMode))
      .letterSpacing(1)
      .margin({ top: StyleConstants.SPACE_MD })
  }

  @Builder
  TemplateChip(label: string, key: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.template === key ? 900 : FontWeight.Medium)
      .fontColor(this.template === key ? Theme.surface(this.uiMode) : Theme.text(this.uiMode))
      .height(30)
      .padding({ left: 10, right: 10 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.template === key ? Theme.text(this.uiMode) : Theme.subtleBg(this.uiMode))
      .margin({ right: StyleConstants.SPACE_XS, top: StyleConstants.SPACE_XS })
      .onClick(() => {
        this.applyTemplate(key);
      })
  }

  @Builder
  ParamRow(label: string, isFirstStart: boolean) {
    Row() {
      Text(label)
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontColor(Theme.sub(this.uiMode))
      Blank()
      Text(isFirstStart ? this.firstStart : this.lunchStart)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
      Text('›')
        .fontSize(14)
        .fontColor(Theme.sub(this.uiMode))
        .margin({ left: 4 })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (isFirstStart) {
        this.pickFirstStart();
      } else {
        this.pickLunchStart();
      }
    })
  }

  @Builder
  StepperRow(label: string, isDuration: boolean) {
    Row() {
      Text(label)
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontColor(Theme.sub(this.uiMode))
      Blank()
      Text('−')
        .fontSize(18)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (isDuration) {
            this.stepDuration(-STEP);
          } else {
            this.stepBreak(-STEP);
          }
        })
      Text(`${isDuration ? this.duration : this.breakMinutes} 分钟`)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .width(66)
        .textAlign(TextAlign.Center)
      Text('+')
        .fontSize(16)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (isDuration) {
            this.stepDuration(STEP);
          } else {
            this.stepBreak(STEP);
          }
        })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PeriodRow(p: PeriodDef) {
    Row() {
      // 只有「节号 + 时间」这一块负责打开时间选择器，
      // 锁定按钮是它的兄弟节点，避免点锁定时误触发改时间
      Row() {
        Text(`${p.index}`)
          .fontSize(13)
          .fontWeight(900)
          .fontColor(Theme.text(this.uiMode))
          .width(20)
        Text(`${p.start} – ${p.end}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
          .width(96)
      }
      .height(36)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.pickPeriod(p.index);
      })

      Text(`${p.duration()} 分钟`)
        .fontSize(10)
        .fontColor(Theme.sub(this.uiMode))
        .layoutWeight(1)
      if (this.isOverridden(p.index)) {
        Text('已调整')
          .fontSize(8)
          .fontColor(Theme.accent(this.uiMode))
          .margin({ right: 4 })
      }
      Text(this.locked.indexOf(p.index) >= 0 ? '已锁' : '锁定')
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.locked.indexOf(p.index) >= 0
          ? Theme.surface(this.uiMode)
          : Theme.sub(this.uiMode))
        .height(22)
        .padding({ left: 6, right: 6 })
        .textAlign(TextAlign.Center)
        .backgroundColor(this.locked.indexOf(p.index) >= 0
          ? Theme.accent(this.uiMode)
          : Color.Transparent)
        .border({
          width: this.locked.indexOf(p.index) >= 0 ? 0 : 1,
          color: Theme.rule(this.uiMode)
        })
        .borderRadius(4)
        .onClick(() => {
          this.toggleLock(p.index);
        })
    }
    .width('100%')
    .height(36)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  DinnerRow() {
    Row() {
      Text(`晚餐 ${this.dinnerStart} – ${this.dinnerEnd}`)
        .fontSize(9)
        .fontColor(Theme.sub(this.uiMode))
        .letterSpacing(1)
    }
    .width('100%')
    .height(26)
    .padding({ left: 20 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Theme.subtleBg(this.uiMode))
  }

  @Builder
  LunchRow() {
    Row() {
      Text(`午休 ${this.lunchStart} – ${this.lunchEnd}`)
        .fontSize(9)
        .fontColor(Theme.sub(this.uiMode))
        .letterSpacing(1)
    }
    .width('100%')
    .height(26)
    .padding({ left: 20 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Theme.subtleBg(this.uiMode))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.text(this.uiMode))
        .opacity(0.35)
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Column({ space: 1 }) {
            Text('TIME CALIBRATION')
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.sub(this.uiMode))
              .letterSpacing(2)
            Text('作息校准')
              .fontSize(StyleConstants.FONT_TITLE_LG)
              .fontWeight(900)
              .fontColor(Theme.text(this.uiMode))
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text('×')
            .fontSize(22)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .width(StyleConstants.TOUCH_TARGET_MIN)
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Column()
          .width('100%')
          .height(StyleConstants.RULE_HEAVY)
          .backgroundColor(Theme.text(this.uiMode))

        Scroll() {
          Column() {
            this.SectionLabel('① 先选一个接近的作息模板')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.TemplateChip('常规 45 分钟', TEMPLATE_REGULAR)
              this.TemplateChip('大节连排 90 分钟', TEMPLATE_BLOCK)
              this.TemplateChip('早课 07:30', TEMPLATE_EARLY)
              this.TemplateChip('短午休 13:30', TEMPLATE_SHORT_LUNCH)
            }
            .width('100%')

            this.SectionLabel('② 只需要填这几个关键参数')
            this.ParamRow('第一节开始', true)
            this.StepperRow('每节课时长', true)
            this.StepperRow('课间休息', false)
            Row() {
              Text('午休')
                .fontSize(StyleConstants.FONT_BODY_SM)
                .fontColor(Theme.sub(this.uiMode))
              Blank()
              Text(`${this.lunchStart} – ${this.lunchEnd}`)
                .fontSize(StyleConstants.FONT_BODY)
                .fontWeight(900)
                .fontColor(Theme.text(this.uiMode))
                .onClick(() => {
                  this.pickLunchStart();
                })
              Text('›')
                .fontSize(14)
                .fontColor(Theme.sub(this.uiMode))
                .margin({ left: 4 })
                .onClick(() => {
                  this.pickLunchEnd();
                })
            }
            .width('100%')
            .height(40)
            .alignItems(VerticalAlign.Center)

            Row() {
              Text('晚餐')
                .fontSize(StyleConstants.FONT_BODY_SM)
                .fontColor(Theme.sub(this.uiMode))
              Blank()
              Text(`${this.dinnerStart} – ${this.dinnerEnd}`)
                .fontSize(StyleConstants.FONT_BODY)
                .fontWeight(900)
                .fontColor(Theme.text(this.uiMode))
                .onClick(() => {
                  this.pickDinnerStart();
                })
              Text('›')
                .fontSize(14)
                .fontColor(Theme.sub(this.uiMode))
                .margin({ left: 4 })
                .onClick(() => {
                  this.pickDinnerEnd();
                })
            }
            .width('100%')
            .height(40)
            .alignItems(VerticalAlign.Center)

            this.SectionLabel('③ 预览，点某一节可单独调整或锁定')
            Text('修改参数后下面会立即重算；带「已调整」的节次有单独时间，锁定后不参与批量移动。')
              .fontSize(9)
              .fontColor(Theme.sub(this.uiMode))
              .opacity(0.8)
              .margin({ top: 2, bottom: 4 })

            ForEach(this.previewPeriods(), (p: PeriodDef, idx: number) => {
              if (this.lunchBefore(idx)) {
                this.LunchRow()
              }
              if (this.dinnerBefore(idx)) {
                this.DinnerRow()
              }
              this.PeriodRow(p)
            }, (p: PeriodDef) => `period-${p.index}-${p.start}-${p.end}-${this.locked.indexOf(p.index) >= 0 ? 1 : 0}`)

            if (this.previewPeriods().length === 0) {
              Text('当前参数无法算出任何节次，请检查起始时间与午休区间。')
                .fontSize(11)
                .fontColor(Theme.accent(this.uiMode))
                .margin({ top: StyleConstants.SPACE_SM })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ bottom: StyleConstants.SPACE_LG })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        Row() {
          Text('应用作息')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor($r('app.color.archive_paper'))
          Blank()
          Text('→')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor($r('app.color.archive_paper'))
        }
        .width('100%')
        .height(52)
        .padding({
          left: StyleConstants.SPACE_LG,
          right: StyleConstants.SPACE_LG
        })
        .backgroundColor(Theme.accent(this.uiMode))
        .margin({ top: StyleConstants.SPACE_SM })
        .onClick(() => {
          this.onApply(this.buildSchedule());
        })
      }
      .width('100%')
      .height('88%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor(Theme.surface(this.uiMode))
      .borderRadius({
        topLeft: StyleConstants.RADIUS_LG,
        topRight: 0,
        bottomLeft: 0,
        bottomRight: 0
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 第 idx 节之前是否需要插入午休行 */
  private dinnerBefore(idx: number): boolean {
    const list: PeriodDef[] = this.previewPeriods();
    if (idx <= 0 || idx >= list.length) {
      return false;
    }
    const dinnerS: number = minutesOfTime(this.dinnerStart);
    const dinnerE: number = minutesOfTime(this.dinnerEnd);
    return list[idx - 1].startMinutes < dinnerS && list[idx].startMinutes >= dinnerE;
  }

  private lunchBefore(idx: number): boolean {
    const list: PeriodDef[] = this.previewPeriods();
    if (idx === 0 || idx >= list.length) {
      return false;
    }
    const lunchS: number = this.lunchStartMinutes();
    return list[idx - 1].startMinutes < lunchS && list[idx].startMinutes >= minutesOfTime(this.lunchEnd);
  }
}
