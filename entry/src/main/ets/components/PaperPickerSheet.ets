import { StyleConstants } from '../common/StyleConstants';
import { PaperStyle } from '../common/PaperStyle';

/**
 * 选纸弹层：给一条事项挑一张纸。
 * 缩略图直接用纸张素材铺底，选中项加一圈深色描边。
 */
@Component
export struct PaperPickerSheet {
  current: string = PaperStyle.LARGE_WARM;
  onPick: (paper: string) => void = () => {};
  onClose: () => void = () => {};

  @Builder
  PaperOption(paper: string) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(PaperStyle.resource(paper))
          .width('100%')
          .height(58)
          .objectFit(ImageFit.Fill)
        if (this.current === paper) {
          Text('✓')
            .fontSize(16)
            .fontWeight(900)
            .fontColor($r('app.color.archive_paper'))
            .backgroundColor($r('app.color.archive_ink'))
            .width(24)
            .height(24)
            .borderRadius(12)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .height(58)
      .border({
        width: this.current === paper ? 2 : 1,
        color: this.current === paper ? $r('app.color.archive_ink') : $r('app.color.archive_rule')
      })

      Text(PaperStyle.label(paper))
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .width('31%')
    .margin({ bottom: 12 })
    .onClick(() => {
      this.onPick(paper);
    })
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
          Text('换一张纸')
            .fontSize(StyleConstants.FONT_TITLE_LG)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('×')
            .fontSize(22)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
            .width(StyleConstants.TOUCH_TARGET_MIN)
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')

        Text('选中的纸会用在今日页这一条便签上')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2, bottom: 12 })

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(PaperStyle.all(), (paper: string) => {
              this.PaperOption(paper)
            }, (paper: string) => `paper-${paper}`)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: 320 })
      }
      .width('100%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor($r('app.color.background_primary'))
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
