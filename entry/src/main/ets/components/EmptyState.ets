import { StyleConstants } from '../common/StyleConstants';
import { OtterSlot, OtterState } from './OtterSlot';

/**
 * 空状态：一张"空白档案页"。
 * 左侧是静止的怀表刻线（时间还没到），右侧是等待中的水獭角色。
 * 怀表承担时间语义、水獭承担人格语义，两者分居两端，不互相冒充。
 */
@Component
export struct EmptyState {
  title: string = '';
  subtitle: string = '';

  @Builder
  StaticDial() {
    Stack() {
      // 空心表盘：border 绘制圆环，兼容 API 24
      Column()
        .width(56)
        .height(56)
        .borderRadius(28)
        .border({ width: 1.5, color: $r('app.color.brand_primary') })
        .opacity(0.5)

      // 静止指针：自中心向左下停住，表示"时间还没到"
      Column() {
        Column()
          .width(2)
          .height(16)
          .backgroundColor($r('app.color.accent_secondary'))
          .borderRadius(1)
      }
      .width(56)
      .height(56)
      .padding({ top: 28 })
      .alignItems(HorizontalAlign.Center)
      .rotate({ angle: 205 })

      // 中心轴
      Column()
        .width(5)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor($r('app.color.accent_secondary'))
    }
    .width(56)
    .height(56)
  }

  build() {
    Column({ space: StyleConstants.SPACE_MD }) {
      // 黄铜短线：档案页的版式标记
      Column()
        .width(StyleConstants.SPACE_XXL)
        .height(StyleConstants.HAIRLINE_HEIGHT)
        .backgroundColor($r('app.color.accent_secondary'))

      // 时间母题 与 水獭角色 分居左右，中间留出呼吸的空白
      Row() {
        this.StaticDial()
        Blank()
        OtterSlot({
          state: OtterState.EMPTY,
          slotWidth: StyleConstants.OTTER_EMPTY
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.title)
        .fontSize(StyleConstants.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.subtitle !== '') {
        Text(this.subtitle)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: StyleConstants.SPACE_LG,
      right: StyleConstants.SPACE_LG,
      top: StyleConstants.SPACE_XL,
      bottom: StyleConstants.SPACE_XL
    })
    .backgroundColor($r('app.color.surface_primary'))
    .borderRadius({
      topLeft: StyleConstants.RADIUS_LG,
      topRight: 0,
      bottomLeft: 0,
      bottomRight: StyleConstants.RADIUS_LG
    })
  }
}
