import { StyleConstants } from '../common/StyleConstants';

/**
 * 怀表母题（Pocketwatch motif）—— 时间系统的视觉隐喻。
 *
 * 品牌三层视觉语言中的"时间"层：
 *   Pocketwatch  → 时间
 *   Monocle      → 观察 / 情境
 *   Otter        → 品牌人格
 * 本组件只表达"时间"，不与水獭插画耦合：水獭资源就位后由独立的插画元素承担人格表达，
 * 不得让怀表"冒充"水獭。
 *
 * 全部由 ArkUI 基础图形（Circle / Column / rotate）绘制，不依赖任何图片资源。
 * 角度约定：0 度为 12 点方向，顺时针为正。默认指针停在与"观察"姿态相关的 10:10。
 */
@Component
export struct PocketwatchMark {
  dialSize: number = StyleConstants.DIAL_HEADER;
  showHands: boolean = true;
  hourAngle: number = 300;
  minuteAngle: number = 60;

  private tickAngles: number[] = [0, 30, 60, 90, 120, 150];

  /** 单根刻度：整点（0/90/180/270 度）更长更重，其余为细刻度。 */
  @Builder
  Tick(baseAngle: number) {
    Column()
      .width(baseAngle % 90 === 0 ? 2 : 1)
      .height(baseAngle % 90 === 0 ? StyleConstants.SPACE_MD : StyleConstants.SPACE_XS)
      .backgroundColor(baseAngle % 90 === 0
        ? $r('app.color.brand_primary')
        : $r('app.color.accent_secondary'))
      .opacity(baseAngle % 90 === 0 ? 0.9 : 0.5)
  }

  /** 一对刻度容器（顶部 + 底部），整体旋转即形成刻度环。 */
  @Builder
  TickRingItem(baseAngle: number) {
    Column() {
      this.Tick(baseAngle)
      Blank()
      this.Tick(baseAngle)
    }
    .width(this.dialSize)
    .height(this.dialSize)
    .padding(StyleConstants.SPACE_SM)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(HorizontalAlign.Center)
    .rotate({ angle: baseAngle })
  }

  /**
   * 指针：整表盘大小的容器，指针置于容器顶部并向下延伸至表盘中心，
   * 再整体绕容器中心旋转 —— 等效于指针绕表盘中心旋转。
   */
  @Builder
  Hand(length: number, thickness: number, color: ResourceColor, angle: number) {
    Column() {
      Column()
        .width(thickness)
        .height(length)
        .backgroundColor(color)
        .borderRadius(thickness / 2)
    }
    .width(this.dialSize)
    .height(this.dialSize)
    .padding({ top: this.dialSize / 2 - length })
    .alignItems(HorizontalAlign.Center)
    .rotate({ angle: angle })
  }

  build() {
    Stack() {
      // 表盘外圈（Otter Blue）：用 borderRadius + border 绘制圆环。
      // 不用 Circle.stroke/fill —— 它们是 API 26 才支持的，与工程 compatibleSdkVersion 6.1.1(24) 不符。
      Column()
        .width(this.dialSize)
        .height(this.dialSize)
        .borderRadius(this.dialSize / 2)
        .border({ width: 2, color: $r('app.color.brand_primary') })

      // 内圈（Antique Brass 细节）
      Column()
        .width(this.dialSize - StyleConstants.SPACE_LG)
        .height(this.dialSize - StyleConstants.SPACE_LG)
        .borderRadius((this.dialSize - StyleConstants.SPACE_LG) / 2)
        .border({ width: 1, color: $r('app.color.accent_secondary') })
        .opacity(0.5)

      // 刻度环
      ForEach(this.tickAngles, (baseAngle: number) => {
        this.TickRingItem(baseAngle)
      }, (baseAngle: number) => `tick-${baseAngle}`)

      if (this.showHands) {
        // 时针：短而重，Charcoal
        this.Hand(this.dialSize * 0.24, 3.5, $r('app.color.text_primary'), this.hourAngle)
        // 分针：长而细，Pocketwatch Orange —— 暖橙作为"时间的现在"出现
        this.Hand(this.dialSize * 0.36, 2, $r('app.color.accent_primary'), this.minuteAngle)
        // 中心轴
        Column()
          .width(9)
          .height(9)
          .borderRadius(4.5)
          .backgroundColor($r('app.color.accent_primary'))
        Column()
          .width(3)
          .height(3)
          .borderRadius(1.5)
          .backgroundColor($r('app.color.surface_primary'))
      }
    }
    .width(this.dialSize)
    .height(this.dialSize)
  }
}
