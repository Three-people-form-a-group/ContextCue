import { StyleConstants } from '../common/StyleConstants';

/**
 * 主要操作按钮：暖橙主色块 + 炭黑文字 + 非对称圆角。
 */
@Component
export struct PrimaryButton {
  label: string = '';
  showPlus: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row({ space: StyleConstants.SPACE_SM }) {
      if (this.showPlus) {
        Text('+')
          .fontSize(22)
          .fontWeight(900)
          .fontColor($r('app.color.archive_paper'))
      }
      Text(this.label)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.archive_paper'))
    }
    .justifyContent(FlexAlign.Center)
    .height(48)
    .padding({
      left: StyleConstants.SPACE_XXL,
      right: StyleConstants.SPACE_XXL
    })
    .backgroundColor($r('app.color.accent_primary'))
    .borderRadius({
      topLeft: StyleConstants.RADIUS_MD,
      topRight: 0,
      bottomLeft: 0,
      bottomRight: StyleConstants.RADIUS_MD
    })
    .onClick(() => this.onTap())
  }
}
