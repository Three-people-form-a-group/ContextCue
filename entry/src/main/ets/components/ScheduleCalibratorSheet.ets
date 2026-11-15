import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { ScheduleModel } from '../common/ScheduleModel';
import { PeriodRow, hmText, minutesOfHm } from '../common/TimetableCourse';
import { ScheduleOverride } from '../timetable/model/TimetableTypes';

/**
 * 作息校准器：调第一节开始 / 每节时长 / 课间 / 午休晚餐 / 单节覆盖 / 锁定节次。
 *
 * 作息只是课表的展示规则（行怎么画），不参与提醒生成；
 * 「同时按新作息平移课程」会把课程真实时间整体移动，再保存课程表。
 */
@Component
export struct ScheduleCalibratorSheet {
  @Prop initial: string = '';
  onApply: (model: ScheduleModel, shiftCourses: boolean) => void = () => {};
  onClose: () => void = () => {};

  @State firstStart: string = '08:00';
  @State duration: number = 45;
  @State breakMinutes: number = 10;
  @State lunchStart: string = '12:00';
  @State lunchEnd: string = '14:00';
  @State dinnerStart: string = '17:30';
  @State dinnerEnd: string = '18:30';
  @State overrides: ScheduleOverride[] = [];
  @State locked: number[] = [];
  @State shiftCourses: boolean = false;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  aboutToAppear(): void {
    // initial 是 ScheduleModel 序列化后的结果，页面传 JSON 过来避免传对象
    if (this.initial !== '') {
      this.loadFromJson(this.initial);
    }
  }

  private loadFromJson(text: string): void {
    try {
      const raw = JSON.parse(text) as Record<string, Object>;
      this.firstStart = raw['firstStart'] as string;
      this.duration = raw['duration'] as number;
      this.breakMinutes = raw['breakMinutes'] as number;
      this.lunchStart = raw['lunchStart'] as string;
      this.lunchEnd = raw['lunchEnd'] as string;
      this.dinnerStart = raw['dinnerStart'] as string;
      this.dinnerEnd = raw['dinnerEnd'] as string;
      this.overrides = raw['overrides'] === undefined ? [] : raw['overrides'] as ScheduleOverride[];
      this.locked = raw['locked'] === undefined ? [] : raw['locked'] as number[];
    } catch (_) {
    }
  }

  private modelNow(): ScheduleModel {
    return new ScheduleModel(this.firstStart, this.duration, this.breakMinutes,
      this.lunchStart, this.lunchEnd, this.dinnerStart, this.dinnerEnd,
      this.overrides.slice(), this.locked.slice());
  }

  private applyTemplate(kind: string): void {
    const t: ScheduleModel = kind === 'block' ? ScheduleModel.block()
      : kind === 'early' ? ScheduleModel.early()
        : kind === 'shortLunch' ? ScheduleModel.shortLunch() : ScheduleModel.regular();
    this.firstStart = t.firstStart;
    this.duration = t.duration;
    this.breakMinutes = t.breakMinutes;
    this.lunchStart = t.lunchStart;
    this.lunchEnd = t.lunchEnd;
    this.dinnerStart = t.dinnerStart;
    this.dinnerEnd = t.dinnerEnd;
    this.overrides = [];
    this.locked = [];
  }

  private pickClock(current: string, onPick: (value: string) => void): void {
    const minutes: number = minutesOfHm(current);
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2026, 0, 1, Math.floor(minutes / 60), minutes % 60),
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        onPick(hmText(value.hour * 60 + value.minute));
      }
    });
  }

  private editOverride(period: PeriodRow): void {
    this.pickClock(period.start, (start: string) => {
      this.pickClock(period.end, (end: string) => {
        if (minutesOfHm(end) <= minutesOfHm(start)) {
          this.getUIContext().getPromptAction().showToast({ message: '结束时间要晚于开始时间' });
          return;
        }
        const next: ScheduleOverride[] = [];
        for (let i = 0; i < this.overrides.length; i++) {
          if (this.overrides[i].index !== period.index) {
            next.push(this.overrides[i]);
          }
        }
        next.push({ index: period.index, start: start, end: end });
        this.overrides = next;
      });
    });
  }

  private clearOverride(index: number): void {
    const next: ScheduleOverride[] = [];
    for (let i = 0; i < this.overrides.length; i++) {
      if (this.overrides[i].index !== index) {
        next.push(this.overrides[i]);
      }
    }
    this.overrides = next;
  }

  private hasOverride(index: number): boolean {
    for (let i = 0; i < this.overrides.length; i++) {
      if (this.overrides[i].index === index) {
        return true;
      }
    }
    return false;
  }

  private toggleLock(index: number): void {
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

  private isLocked(index: number): boolean {
    return this.locked.indexOf(index) >= 0;
  }

  @Builder
  TemplateChip(label: string, kind: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.text(this.uiMode))
      .height(30)
      .padding({ left: 10, right: 10 })
      .textAlign(TextAlign.Center)
      .border({ width: 1, color: Theme.rule(this.uiMode) })
      .borderRadius({ topLeft: 0, topRight: 7, bottomLeft: 0, bottomRight: 7 })
      .onClick(() => {
        this.applyTemplate(kind);
      })
  }

  @Builder
  ClockRow(label: string, value: string, onPick: (value: string) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(11)
        .fontColor(Theme.sub(this.uiMode))
        .width(70)
      Text(value)
        .fontSize(14)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      Text('›')
        .fontSize(14)
        .fontColor(Theme.sub(this.uiMode))
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: StyleConstants.HAIRLINE_HEIGHT }, color: Theme.rule(this.uiMode) })
    .onClick(() => {
      this.pickClock(value, onPick);
    })
  }

  @Builder
  NumberRow(label: string, value: number, min: number, max: number, step: number,
    onChange: (value: number) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(11)
        .fontColor(Theme.sub(this.uiMode))
        .width(70)
      Blank()
      Text('－')
        .fontSize(16)
        .fontColor(Theme.text(this.uiMode))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          onChange(Math.max(min, value - step));
        })
      Text(`${value}`)
        .fontSize(14)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .width(42)
        .textAlign(TextAlign.Center)
      Text('＋')
        .fontSize(16)
        .fontColor(Theme.text(this.uiMode))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          onChange(Math.min(max, value + step));
        })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: StyleConstants.HAIRLINE_HEIGHT }, color: Theme.rule(this.uiMode) })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.archive_ink'))
        .opacity(0.35)
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text('取消')
            .fontSize(14)
            .fontColor(Theme.sub(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
          Blank()
          Text('作息')
            .fontSize(15)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
          Blank()
          Text('应用')
            .fontSize(14)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onApply(this.modelNow(), this.shiftCourses);
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            Text('作息只决定课表的行和午休/晚餐留白，不改变提醒时间。')
              .fontSize(10)
              .fontColor(Theme.sub(this.uiMode))
              .width('100%')

            Row({ space: 6 }) {
              this.TemplateChip('常规', 'regular')
              this.TemplateChip('大节', 'block')
              this.TemplateChip('早课', 'early')
              this.TemplateChip('短午休', 'shortLunch')
            }
            .width('100%')

            this.ClockRow('第一节开始', this.firstStart, (v: string) => {
              this.firstStart = v;
            })
            this.NumberRow('每节时长', this.duration, 30, 120, 5, (v: number) => {
              this.duration = v;
            })
            this.NumberRow('课间', this.breakMinutes, 0, 30, 5, (v: number) => {
              this.breakMinutes = v;
            })
            this.ClockRow('午休开始', this.lunchStart, (v: string) => {
              this.lunchStart = v;
            })
            this.ClockRow('午休结束', this.lunchEnd, (v: string) => {
              this.lunchEnd = v;
            })
            this.ClockRow('晚餐开始', this.dinnerStart, (v: string) => {
              this.dinnerStart = v;
            })
            this.ClockRow('晚餐结束', this.dinnerEnd, (v: string) => {
              this.dinnerEnd = v;
            })

            Text('节次预览（点一行改单节时间，右侧锁定不参与平移）')
              .fontSize(10)
              .fontColor(Theme.sub(this.uiMode))
              .width('100%')
              .margin({ top: 4 })

            Column() {
              ForEach(this.modelNow().periods(), (p: PeriodRow) => {
                Row({ space: 8 }) {
                  Text(`${p.index}`)
                    .fontSize(12)
                    .fontWeight(900)
                    .fontColor(Theme.text(this.uiMode))
                    .width(20)
                  Text(`${p.start} - ${p.end}`)
                    .fontSize(12)
                    .fontColor(Theme.text(this.uiMode))
                    .layoutWeight(1)
                  if (this.hasOverride(p.index)) {
                    Text('已改')
                      .fontSize(9)
                      .fontColor(Theme.sub(this.uiMode))
                      .onClick(() => {
                        this.clearOverride(p.index);
                      })
                  }
                  Text(this.isLocked(p.index) ? '已锁' : '锁定')
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isLocked(p.index) ? Theme.alert(this.uiMode) : Theme.sub(this.uiMode))
                    .padding({ left: 6, right: 6 })
                    .onClick(() => {
                      this.toggleLock(p.index);
                    })
                }
                .width('100%')
                .height(36)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.editOverride(p);
                })
              }, (p: PeriodRow) => `period-${p.index}-${p.start}-${p.end}-${this.isLocked(p.index)}`)
            }
            .width('100%')

            Row({ space: 8 }) {
              Checkbox({ name: 'shift' }).select(this.shiftCourses).onChange((value: boolean) => {
                this.shiftCourses = value;
              })
              Text('同时按新作息平移课程（会重新生成上课提醒）')
                .fontSize(11)
                .fontColor(Theme.text(this.uiMode))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 10, bottom: 14 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('88%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor(Theme.surface(this.uiMode))
      .borderRadius({ topLeft: 0, topRight: StyleConstants.RADIUS_LG, bottomLeft: 0, bottomRight: 0 })
    }
    .width('100%')
    .height('100%')
  }
}
