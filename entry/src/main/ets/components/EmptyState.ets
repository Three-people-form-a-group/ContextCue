import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { OtterSlot, OtterState } from './OtterSlot';

@Component
export struct EmptyState {
  title: string = '';
  subtitle: string = '';
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  build() {
    Row({ space: StyleConstants.SPACE_SM }) {
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(this.title)
          .fontSize(StyleConstants.FONT_TITLE)
          .fontWeight(900)
          .fontColor(this.uiMode === UiMode.JOURNAL ? $r('app.color.archive_paper') : Theme.text(this.uiMode))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontColor(this.uiMode === UiMode.JOURNAL ? $r('app.color.accent_light_a') : Theme.sub(this.uiMode))
            .opacity(0.8)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      OtterSlot({ state: OtterState.EMPTY, slotWidth: 68 })
        .rotate({ angle: -7 })
        .offset({ y: 8 })
    }
    .width('100%')
    .padding(StyleConstants.SPACE_LG)
    .backgroundImage(this.uiMode === UiMode.JOURNAL ? $r('app.media.torn_note_deep_blue') : undefined)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .backgroundColor(this.uiMode === UiMode.JOURNAL ? Color.Transparent : Theme.surface(this.uiMode))
    .border({ width: { left: 4 }, color: $r('app.color.accent_mustard') })
  }
}
