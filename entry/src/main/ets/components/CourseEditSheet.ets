import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { TimetableCourse } from '../common/TimetableCourse';

const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const DAY_NUMBERS: number[] = [1, 2, 3, 4, 5, 6, 7];
/**
 * 可编辑的最晚时刻 23:59（当天第 1439 分钟）。
 * 时间轴视觉上延伸到 24:00，但表单不允许填 24:00：系统时间选择器只支持 0-23 时，
 * 若允许 24:00 会出现"选不出来、写进去也回读成次日 00:00"的自相矛盾状态。
 */
const MAX_EDIT_MINUTES: number = 23 * 60 + 59;

/**
 * 课程添加 / 编辑表单（底部弹层）。
 * 支持修改课程名、教师、教室、星期、开始/结束时间与上课周次；
 * 时间使用系统时间选择器，不再假设"下午固定两点"。
 * 当前操作的是 UI 演示数据，接入 TimetableService 后改为调用 saveTimetable。
 */
@Component
export struct CourseEditSheet {
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  initial: TimetableCourse = new TimetableCourse('', '', '', '', 1, '00:00', '00:00', [], 0);
  isNew: boolean = true;
  onSave: (course: TimetableCourse) => void = () => {};
  onClose: () => void = () => {};

  @State name: string = '';
  @State teacher: string = '';
  @State location: string = '';
  @State day: number = 1;
  @State start: string = '08:00';
  @State end: string = '09:40';
  @State weeksText: string = '1-16';
  @State error: string = '';

  aboutToAppear(): void {
    // 新建时也接受预填（点空闲时段添加课程会带上开始/结束时间）
    this.day = this.initial.dayOfWeek;
    this.start = this.initial.startTime;
    this.end = this.initial.endTime;
    if (!this.isNew) {
      this.name = this.initial.name;
      this.teacher = this.initial.teacher;
      this.location = this.initial.location;
      this.weeksText = this.formatWeeks(this.initial.weeks);
    }
  }

  private formatWeeks(weeks: number[]): string {
    if (weeks.length === 0) {
      return '';
    }
    let consecutive: boolean = true;
    for (let i = 1; i < weeks.length; i++) {
      if (weeks[i] - weeks[i - 1] !== 1) {
        consecutive = false;
      }
    }
    if (consecutive) {
      return `${weeks[0]}-${weeks[weeks.length - 1]}`;
    }
    return weeks.join(',');
  }

  private minutesOf(time: string): number {
    const parts: string[] = time.split(':');
    if (parts.length < 2) {
      return 0;
    }
    return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private pickStart(): void {
    const now: Date = new Date();
    const minutes: number = Math.min(this.minutesOf(this.start), MAX_EDIT_MINUTES);
    now.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: now,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.start = `${this.pad(value.hour)}:${this.pad(value.minute)}`;
        this.error = '';
      }
    });
  }

  private pickEnd(): void {
    const now: Date = new Date();
    const minutes: number = Math.min(this.minutesOf(this.end), MAX_EDIT_MINUTES);
    now.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: now,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.end = `${this.pad(value.hour)}:${this.pad(value.minute)}`;
        this.error = '';
      }
    });
  }

  /** 新课程按名称 + 星期取一个稳定的配色序号，避免同一天新建的课撞成同一个颜色 */
  private toneFor(name: string): number {
    let sum: number = 0;
    for (let i = 0; i < name.length; i++) {
      sum += name.charCodeAt(i);
    }
    return (sum + this.day) % 6;
  }

  /** 支持 "1-16" 连续周次与 "1,3,5" 离散周次 */
  private parseWeeks(text: string): number[] {
    const out: number[] = [];
    const parts: string[] = text.split(',');
    for (let i = 0; i < parts.length; i++) {
      const token: string = parts[i].trim();
      if (token === '') {
        continue;
      }
      const dash: number = token.indexOf('-');
      if (dash > 0) {
        const from: number = parseInt(token.substring(0, dash), 10);
        const to: number = parseInt(token.substring(dash + 1), 10);
        if (!Number.isNaN(from) && !Number.isNaN(to) && to >= from) {
          for (let w = from; w <= to; w++) {
            if (out.indexOf(w) < 0) {
              out.push(w);
            }
          }
        }
      } else {
        const single: number = parseInt(token, 10);
        if (!Number.isNaN(single) && single > 0 && out.indexOf(single) < 0) {
          out.push(single);
        }
      }
    }
    out.sort((a: number, b: number) => a - b);
    return out;
  }

  private save(): void {
    const trimmedName: string = this.name.trim();
    if (trimmedName === '') {
      this.error = '请填写课程名';
      return;
    }
    if (this.minutesOf(this.start) >= MAX_EDIT_MINUTES) {
      this.error = '开始时间必须早于 23:59';
      return;
    }
    if (this.minutesOf(this.end) > MAX_EDIT_MINUTES) {
      this.error = '结束时间最晚填 23:59';
      return;
    }
    if (this.minutesOf(this.end) <= this.minutesOf(this.start)) {
      this.error = '结束时间必须晚于开始时间';
      return;
    }
    const weeks: number[] = this.parseWeeks(this.weeksText);
    if (weeks.length === 0) {
      this.error = '请填写上课周次，例如 1-16 或 1,3,5';
      return;
    }
    const next: TimetableCourse = new TimetableCourse(
      this.isNew ? `demo-${Date.now()}` : this.initial.id,
      trimmedName,
      this.teacher.trim(),
      this.location.trim(),
      this.day,
      this.start,
      this.end,
      weeks,
      this.isNew ? this.toneFor(trimmedName) : this.initial.tone
    );
    this.onSave(next);
  }

  @Builder
  FieldLabel(label: string) {
    Text(label)
      .fontSize(StyleConstants.FONT_SECTION_INDEX)
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.sub(this.uiMode))
      .letterSpacing(1)
      .margin({ top: StyleConstants.SPACE_SM })
  }

  @Builder
  FieldRule() {
    Column()
      .width('100%')
      .height(StyleConstants.HAIRLINE_HEIGHT)
      .backgroundColor(Theme.rule(this.uiMode))
  }

  /**
   * 注意：这里只能传「是不是开始时间」这个常量，时间值必须从 this 读。
   * @Builder 的按值参数是一次性快照——如果把 this.start 传进来，选择器改变状态后
   * 这一行文字不会刷新（这正是"改完时间表单不更新"的原因）。
   */
  @Builder
  TimeRow(isStart: boolean) {
    Row() {
      Text(isStart ? this.start : this.end)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
      Blank()
      Text('›')
        .fontSize(16)
        .fontColor(Theme.sub(this.uiMode))
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (isStart) {
        this.pickStart();
      } else {
        this.pickEnd();
      }
    })
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
          Text(this.isNew ? '添加课程' : '编辑课程')
            .fontSize(StyleConstants.FONT_TITLE_LG)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
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
            this.FieldLabel('课程名')
            TextInput({
              placeholder: '例如 高等数学',
              text: this.name
            })
              .onChange((value: string) => {
                this.name = value;
                this.error = '';
              })
              .fontSize(StyleConstants.FONT_BODY)
              .fontColor(Theme.text(this.uiMode))
              .placeholderColor(Theme.sub(this.uiMode))
              .backgroundColor(Color.Transparent)
              .padding({ left: 0, right: 0 })
              .height(42)
            this.FieldRule()

            Row({ space: StyleConstants.SPACE_LG }) {
              Column() {
                this.FieldLabel('教师')
                TextInput({
                  placeholder: '选填',
                  text: this.teacher
                })
                  .onChange((value: string) => {
                    this.teacher = value;
                  })
                  .fontSize(StyleConstants.FONT_BODY)
                  .fontColor(Theme.text(this.uiMode))
                  .placeholderColor(Theme.sub(this.uiMode))
                  .backgroundColor(Color.Transparent)
                  .padding({ left: 0, right: 0 })
                  .height(42)
                this.FieldRule()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column() {
                this.FieldLabel('教室')
                TextInput({
                  placeholder: '选填',
                  text: this.location
                })
                  .onChange((value: string) => {
                    this.location = value;
                  })
                  .fontSize(StyleConstants.FONT_BODY)
                  .fontColor(Theme.text(this.uiMode))
                  .placeholderColor(Theme.sub(this.uiMode))
                  .backgroundColor(Color.Transparent)
                  .padding({ left: 0, right: 0 })
                  .height(42)
                this.FieldRule()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            this.FieldLabel('星期')
            Row({ space: 4 }) {
              ForEach(DAY_NUMBERS, (d: number) => {
                Text(DAY_LABELS[d - 1])
                  .fontSize(StyleConstants.FONT_BODY_SM)
                  .fontWeight(900)
                  .fontColor(this.day === d
                    ? Theme.surface(this.uiMode)
                    : Theme.text(this.uiMode))
                  .layoutWeight(1)
                  .height(40)
                  .textAlign(TextAlign.Center)
                  .backgroundColor(this.day === d
                    ? Theme.text(this.uiMode)
                    : Theme.subtleBg(this.uiMode))
                  .onClick(() => {
                    this.day = d;
                  })
              }, (d: number) => `edit-day-${d}`)
            }
            .width('100%')

            Row({ space: StyleConstants.SPACE_LG }) {
              Column() {
                this.FieldLabel('开始时间')
                this.TimeRow(true)
                this.FieldRule()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column() {
                this.FieldLabel('结束时间')
                this.TimeRow(false)
                this.FieldRule()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            Text('时间轴显示至 24:00；这里最晚可填 23:59')
              .fontSize(9)
              .fontColor(Theme.sub(this.uiMode))
              .opacity(0.75)
              .margin({ top: 4 })

            this.FieldLabel('上课周次')
            TextInput({
              placeholder: '1-16 或 1,3,5',
              text: this.weeksText
            })
              .onChange((value: string) => {
                this.weeksText = value;
                this.error = '';
              })
              .fontSize(StyleConstants.FONT_BODY)
              .fontColor(Theme.text(this.uiMode))
              .placeholderColor(Theme.sub(this.uiMode))
              .backgroundColor(Color.Transparent)
              .padding({ left: 0, right: 0 })
              .height(42)
            this.FieldRule()

            Text('支持「1-16」连续周次，或「1,3,5」离散周次')
              .fontSize(9)
              .fontColor(Theme.sub(this.uiMode))
              .opacity(0.75)
              .margin({ top: 4 })

            if (!this.isNew) {
              Text('修改会作用于这门课在所有周次的固定安排；暂不支持只调整某一次课。')
                .fontSize(9)
                .fontColor(Theme.accent(this.uiMode))
                .opacity(0.9)
                .maxLines(2)
                .margin({ top: StyleConstants.SPACE_SM })
            }

            if (this.error !== '') {
              Text(this.error)
                .fontSize(StyleConstants.FONT_SECTION_INDEX)
                .fontWeight(FontWeight.Bold)
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
          Text(this.isNew ? '添加' : '保存')
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
          this.save();
        })
      }
      .width('100%')
      .height('84%')
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
}
