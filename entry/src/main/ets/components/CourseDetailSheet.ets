import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { TimetableCourse } from '../common/TimetableCourse';

/**
 * 课程详情弹层：点击课程格后从底部升起。
 * 课程格只显示短名与开始时间，完整信息在这里呈现（教师/教室/时间/周次）。
 */
@Component
export struct CourseDetailSheet {
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  course: TimetableCourse = new TimetableCourse('', '', '', '', 1, '00:00', '00:00', [], 0);
  onClose: () => void = () => {};
  onEdit: () => void = () => {};
  onDelete: () => void = () => {};

  /** 周次压缩显示：1-16 周 / 1-16 周（单周）/ 1、3、5 周 */
  private formatWeeks(weeks: number[]): string {
    if (weeks.length === 0) {
      return '未设置';
    }
    const first: number = weeks[0];
    const last: number = weeks[weeks.length - 1];
    let consecutive: boolean = true;
    let stepTwo: boolean = true;
    for (let i = 1; i < weeks.length; i++) {
      const diff: number = weeks[i] - weeks[i - 1];
      if (diff !== 1) {
        consecutive = false;
      }
      if (diff !== 2) {
        stepTwo = false;
      }
    }
    if (consecutive) {
      return `${first}-${last} 周`;
    }
    if (stepTwo && weeks.length > 1) {
      return `${first}-${last} 周（${first % 2 === 1 ? '单' : '双'}周）`;
    }
    return `${weeks.join('、')} 周`;
  }

  @Builder
  MetaRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.sub(this.uiMode))
        .letterSpacing(1)
        .width(52)
      Text(value)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text(this.uiMode))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      top: StyleConstants.SPACE_SM,
      bottom: StyleConstants.SPACE_SM
    })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  Divider() {
    Column()
      .width('100%')
      .height(StyleConstants.HAIRLINE_HEIGHT)
      .backgroundColor(Theme.rule(this.uiMode))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩：点击空白处关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.text(this.uiMode))
        .opacity(0.35)
        .onClick(() => {
          this.onClose();
        })

      Column({ space: StyleConstants.SPACE_XS }) {
        Row() {
          Text(this.course.name)
            .fontSize(StyleConstants.FONT_TITLE_LG)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .layoutWeight(1)
            .maxLines(2)
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

        this.MetaRow('教师', this.course.teacher !== '' ? this.course.teacher : '未填写')
        this.Divider()
        this.MetaRow('教室', this.course.location !== '' ? this.course.location : '未填写')
        this.Divider()
        this.MetaRow('时间', `${this.course.startTime} – ${this.course.endTime}`)
        this.Divider()
        this.MetaRow('周次', this.formatWeeks(this.course.weeks))

        // 编辑 / 删除
        Row({ space: StyleConstants.SPACE_MD }) {
          Text('删除')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({
              left: StyleConstants.SPACE_LG,
              right: StyleConstants.SPACE_LG
            })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onDelete();
            })
          Blank()
          Row({ space: StyleConstants.SPACE_SM }) {
            Text('编辑')
              .fontSize(StyleConstants.FONT_BODY)
              .fontWeight(900)
              .fontColor($r('app.color.archive_paper'))
            Text('→')
              .fontSize(StyleConstants.FONT_BODY)
              .fontWeight(900)
              .fontColor($r('app.color.archive_paper'))
          }
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .padding({
            left: StyleConstants.SPACE_XL,
            right: StyleConstants.SPACE_XL
          })
          .backgroundColor(Theme.text(this.uiMode))
          .borderRadius({
            topLeft: 0,
            topRight: StyleConstants.RADIUS_SM,
            bottomLeft: 0,
            bottomRight: StyleConstants.RADIUS_SM
          })
          .onClick(() => {
            this.onEdit();
          })
        }
        .width('100%')
        .margin({ top: StyleConstants.SPACE_MD })
        .alignItems(VerticalAlign.Center)

        Text('点击空白处关闭')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontColor(Theme.sub(this.uiMode))
          .opacity(0.75)
          .margin({ top: StyleConstants.SPACE_XS })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
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
