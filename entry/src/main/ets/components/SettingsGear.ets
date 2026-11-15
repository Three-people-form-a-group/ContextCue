import { StyleConstants } from '../common/StyleConstants';

/**
 * 设置入口（齿轮）。
 * 设置不再是底部 Tab，因此首页与索引页都需要一个一致的入口。
 * 图形用 ArkUI 通用属性绘制（圆环 + 8 齿），不依赖系统图标资源与字体字形，兼容 API 24。
 */
@Component
export struct SettingsGear {
  onTap: () => void = () => {};

  private angles: number[] = [0, 45, 90, 135, 180, 225, 270, 315];

  @Builder
  Glyph(size: number, color: ResourceColor) {
    Stack() {
      ForEach(this.angles, (angle: number) => {
        Column() {
          Column()
            .width(2.5)
            .height(size * 0.14)
            .backgroundColor(color)
        }
        .width(size)
        .height(size)
        .padding({ top: size * 0.08 })
        .alignItems(HorizontalAlign.Center)
        .rotate({ angle: angle })
      }, (angle: number) => `gear-${angle}`)

      Column()
        .width(size * 0.56)
        .height(size * 0.56)
        .borderRadius(size * 0.28)
        .border({ width: 2, color: color })

      Column()
        .width(size * 0.14)
        .height(size * 0.14)
        .borderRadius(size * 0.07)
        .backgroundColor(color)
    }
    .width(size)
    .height(size)
  }

  build() {
    Column() {
      this.Glyph(20, $r('app.color.text_primary'))
    }
    .width(StyleConstants.TOUCH_TARGET_MIN)
    .height(StyleConstants.TOUCH_TARGET_MIN)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}
