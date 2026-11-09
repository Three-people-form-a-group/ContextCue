import { StyleConstants } from '../common/StyleConstants';

/**
 * 表单选择行（编辑工作台用）。
 * 不再是填色盒子：标签为小号全大写式、值为主字号，底部一条细线定义可编辑边界。
 * 必须用 @Prop：普通变量只在初始化时接收一次，父组件重渲染不会同步。
 */
@Component
export struct FormItem {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  @Prop badgeLabel: string = '';
  @Prop highlightValue: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row({ space: StyleConstants.SPACE_SM }) {
      Text(this.label)
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(1)

      if (this.badgeLabel !== '') {
        Text(this.badgeLabel)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.archive_paper'))
          .backgroundColor($r('app.color.accent_olive'))
          .padding({
            left: 6,
            right: 6,
            top: 2,
            bottom: 2
          })
      }

      Blank()

      if (this.value !== '') {
        Text(this.value)
          .fontSize(this.highlightValue ? StyleConstants.FONT_TITLE_LG : StyleConstants.FONT_TITLE)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
      } else {
        Text(this.placeholder)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_secondary'))
      }

      Column()
        .width(4)
        .height(4)
        .backgroundColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .border({
      width: { bottom: StyleConstants.HAIRLINE_HEIGHT },
      color: $r('app.color.border_subtle')
    })
    .onClick(() => this.onTap())
  }
}
