import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';

@Component
export struct EmptyState {
  title: string = '';
  subtitle: string = '';
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  build() {
    Column({ space: StyleConstants.SPACE_XS }) {
        Text(this.title)
          .fontSize(StyleConstants.FONT_TITLE)
          .fontWeight(900)
          .fontColor(this.uiMode === UiMode.JOURNAL ? $r('app.color.archive_ink') : Theme.text(this.uiMode))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontColor(this.uiMode === UiMode.JOURNAL ? $r('app.color.archive_ink') : Theme.sub(this.uiMode))
            .opacity(0.72)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(StyleConstants.SPACE_LG)
    // 灰粉票根：和下方「新建提醒（海盐）/ 草稿箱（琥珀）」都区分开，浅而不抢
    .backgroundImage(this.uiMode === UiMode.JOURNAL ? $r('app.media.ticket_pink') : undefined)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .backgroundColor(this.uiMode === UiMode.JOURNAL ? Color.Transparent : Theme.surface(this.uiMode))
  }
}
