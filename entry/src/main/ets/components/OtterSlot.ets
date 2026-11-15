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
 * 水獭角色插槽。
 *
 * 资源约定：图片平铺在 resources/base/media/ 下（HarmonyOS 的 media 目录不支持子目录），
 * 因此引用形式为 $r('app.media.otter_reminder') 这类平铺名称。
 *
 * 缩放：按原图宽高比渲染（aspectRatio），objectFit 为 Contain，保证不变形；
 * 纸边跟随透明角色图的轮廓。目前只保留 otter_reminder 一张图（今日报头），其余状态图已删除。
 *
 * 降级：图片加载失败时回退为几何怀表母题，不引用任何不存在的资源路径。
 */
@Component
export struct OtterSlot {
  /** 显示宽度（vp）；高度由原图宽高比自动推导。不能命名为 width —— 与自定义组件的 width 属性冲突。 */
  slotWidth: number = StyleConstants.OTTER_HEADER;

  @State loadFailed: boolean = false;

  /** 唯一的角色图：今日报头那只「在提醒/记录」的水獭。 */
  private imageSource(): Resource {
    return $r('app.media.otter_reminder');
  }

  /** 原图宽高比（507 x 512），避免缩放变形。 */
  private imageAspect(): number {
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
