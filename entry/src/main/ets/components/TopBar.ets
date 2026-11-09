import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';

/**
 * 页面顶部栏：返回键 + 标题 + 右侧文字操作区。
 * 返回行为通过回调交由调用方处理（Navigation 场景下为 pathStack.pop()）。
 */
@Component
export struct TopBar {
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  title: string = '';
  showBack: boolean = false;
  onBack: () => void = () => {};
  actionLabel: string = '';
  onAction: () => void = () => {};
  onDark: boolean = false;

  build() {
    Row({ space: StyleConstants.SPACE_MD }) {
      if (this.showBack) {
        Text('←')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.onDark ? $r('app.color.archive_paper') : Theme.text(this.uiMode))
          .width(StyleConstants.TOUCH_TARGET_MIN)
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => this.onBack())
      }
      Text(this.title)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.onDark ? $r('app.color.archive_paper') : Theme.text(this.uiMode))
        .layoutWeight(1)
      if (this.actionLabel !== '') {
        Text(this.actionLabel)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.onDark ? $r('app.color.archive_accent') : Theme.ink(this.uiMode))
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .onClick(() => this.onAction())
      }
    }
    .alignItems(VerticalAlign.Center)
    .height(StyleConstants.TOP_BAR_HEIGHT)
    .padding({
      left: StyleConstants.SPACE_SM,
      right: StyleConstants.SPACE_LG
    })
  }
}
