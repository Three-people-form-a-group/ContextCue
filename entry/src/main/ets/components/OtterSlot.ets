import { StyleConstants } from '../common/StyleConstants';
import { PocketwatchMark } from './PocketwatchMark';

// 保留透明通道，让裁边沿海獭轮廓出现。
const PAPER_EDGE: ColorFilter = new ColorFilter([
  0, 0, 0, 0, 0.99,
  0, 0, 0, 0, 0.96,
  0, 0, 0, 0, 0.89,
  0, 0, 0, 1, 0
]);
const PRINT_INK: ColorFilter = new ColorFilter([
  0.59, 0.29, 0.06, 0, 0.04,
  0.17, 0.66, 0.06, 0, 0.04,
  0.14, 0.28, 0.45, 0, 0.03,
  0, 0, 0, 1, 0
]);

/**
 * 水獭角色状态。本阶段只用于选择静态图片，不实现状态机与动画。
 * 未来接入 Lottie 时，只需替换本组件内部的渲染实现，所有调用点保持不变。
 */
export class OtterState {
  /** 普通首页：水獭在提醒 / 记录 */
  static readonly IDLE: string = 'idle';
  /** 没有提醒：水獭在等待 / 疑惑 */
  static readonly EMPTY: string = 'empty';
  /** AI 分析情境：水獭在看怀表思考 */
  static readonly THINKING: string = 'thinking';
  /** 创建或完成后的反馈 */
  static readonly SUCCESS: string = 'success';
}

/**
 * 水獭角色插槽。
 *
 * 资源约定：图片平铺在 resources/base/media/ 下（HarmonyOS 的 media 目录不支持子目录），
 * 因此引用形式为 $r('app.media.otter_reminder') 这类平铺名称。
 *
 * 缩放：按原图宽高比渲染（aspectRatio），objectFit 为 Contain，保证不变形；
 * 纸边跟随透明角色图的轮廓，四种角色状态共用同一种印刷调色。
 *
 * 降级：图片加载失败时回退为几何怀表母题，不引用任何不存在的资源路径。
 */
@Component
export struct OtterSlot {
  /** 角色状态，取值见 OtterState */
  state: string = OtterState.IDLE;
  /** 显示宽度（vp）；高度由原图宽高比自动推导。不能命名为 width —— 与自定义组件的 width 属性冲突。 */
  slotWidth: number = StyleConstants.OTTER_HEADER;

  @State loadFailed: boolean = false;

  /** 状态 → 真实图片资源。四张图均已存在于 resources/base/media/。 */
  private imageSource(): Resource {
    if (this.state === OtterState.EMPTY) {
      return $r('app.media.otter_doubt');
    }
    if (this.state === OtterState.THINKING) {
      return $r('app.media.otter_checkingtime');
    }
    if (this.state === OtterState.SUCCESS) {
      return $r('app.media.otter_finish');
    }
    return $r('app.media.otter_reminder');
  }

  /** 各状态图片的宽高比（宽 / 高），避免缩放变形。数值取自压缩后的实际尺寸。 */
  private imageAspect(): number {
    if (this.state === OtterState.EMPTY) {
      // otter_doubt.png: 512 x 505
      return 512 / 505;
    }
    if (this.state === OtterState.THINKING) {
      // otter_checkingtime.png: 446 x 512
      return 446 / 512;
    }
    if (this.state === OtterState.SUCCESS) {
      // otter_finish.png: 512 x 341
      return 512 / 341;
    }
    // otter_reminder.png: 507 x 512
    return 507 / 512;
  }

  build() {
    if (this.loadFailed) {
      // 降级：不引用缺失资源，用已有几何母题兜底
      PocketwatchMark({ dialSize: this.slotWidth * 0.62 })
    } else {
      Stack({ alignContent: Alignment.Center }) {
        ForEach([0, 1, 2, 3], (edge: number) => {
          Image(this.imageSource())
            .width('94%')
            .height('94%')
            .objectFit(ImageFit.Contain)
            .colorFilter(PAPER_EDGE)
            .offset({ x: edge < 2 ? (edge === 0 ? -1.5 : 1.5) : 0,
              y: edge >= 2 ? (edge === 2 ? -1.5 : 1.5) : 0 })
            .accessibilityLevel('no')
        }, (edge: number) => `${edge}`)

        Image(this.imageSource())
          .width('94%')
          .height('94%')
          .objectFit(ImageFit.Contain)
          .colorFilter(PRINT_INK)
          .interpolation(ImageInterpolation.High)
          .onError(() => {
            this.loadFailed = true;
          })
      }
      .width(this.slotWidth)
      .aspectRatio(this.imageAspect())
    }
  }
}
