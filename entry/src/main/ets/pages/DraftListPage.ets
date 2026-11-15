import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderEditNavParam } from '../common/RouterConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { DraftStore, DraftItem, ReminderDraft } from '../common/DraftStore';
import { TriggerType } from '../model/ReminderEnums';
import { TopBar } from '../components/TopBar';

/**
 * 草稿箱：列出所有未完成的编辑草稿。
 * 点一条继续写（带着草稿键进入编辑台），右侧可以删除。
 */
@Component
export struct DraftListPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  @State drafts: DraftItem[] = [];
  @State refreshTick: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.drafts = DraftStore.all();
    this.refreshTick = this.refreshTick + 1;
  }

  private timeText(draft: ReminderDraft): string {
    if (draft.triggerType === TriggerType.LOCATION) {
      return draft.sceneName === '' ? '地点未填写' : `到达 ${draft.sceneName} 时`;
    }
    if (draft.timeMs <= 0) {
      return '时间待定';
    }
    const d: Date = new Date(draft.timeMs);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    const hText: string = h < 10 ? `0${h}` : `${h}`;
    const mText: string = m < 10 ? `0${m}` : `${m}`;
    const type: string = draft.triggerType === TriggerType.BOTH ? ' · 时间+地点' : '';
    return `${d.getMonth() + 1}月${d.getDate()}日 ${hText}:${mText}${type}`;
  }

  private updatedText(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d: Date = new Date(ms);
    return `保存于 ${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${d.getMinutes() < 10 ? '0' : ''}${d.getMinutes()}`;
  }

  private openDraft(item: DraftItem): void {
    this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
      new ReminderEditNavParam(RouterConstants.EDIT_MODE_CREATE, undefined, item.key));
  }

  private confirmDelete(item: DraftItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除草稿',
      message: '这条草稿删除后无法恢复。',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.detail_ink') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        DraftStore.clear(getContext(this), item.key);
        this.reload();
      }
    }).catch(() => {
    });
  }

  @Builder
  DraftRow(item: DraftItem) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column({ space: 4 }) {
        Text(item.draft.title.trim() === '' ? '未命名草稿' : item.draft.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.draft.title.trim() === ''
            ? Theme.sub(this.uiMode)
            : Theme.text(this.uiMode))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.timeText(item.draft))
          .fontSize(12)
          .fontColor(Theme.sub(this.uiMode))
          .maxLines(1)
        Text(this.updatedText(item.draft.updatedAt))
          .fontSize(9)
          .fontColor(Theme.sub(this.uiMode))
          .opacity(0.75)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, bottom: 10 })
      .border({
        width: { left: 1, bottom: StyleConstants.HAIRLINE_HEIGHT },
        color: Theme.rule(this.uiMode)
      })

      Text('删除')
        .fontSize(11)
        .fontColor(Theme.sub(this.uiMode))
        .height(StyleConstants.TOUCH_TARGET_MIN)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.confirmDelete(item);
        })

      Text('›')
        .fontSize(15)
        .fontColor(Theme.sub(this.uiMode))
        .accessibilityLevel('no')
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 4, right: 4, top: 12, bottom: 2 })
    .onClick(() => {
      this.openDraft(item);
    })
  }

  build() {
    NavDestination() {
      Column() {
        TopBar({
          title: '草稿箱',
          showBack: true,
          onBack: () => {
            this.pathStack.pop();
          }
        })
        Scroll() {
          Column({ space: 0 }) {
            if (this.drafts.length === 0) {
              // 空状态：两行说明 + 一条短色条，不放图标和水獭
              Column({ space: 14 }) {
                Column({ space: 6 }) {
                  Text('还没有草稿')
                    .fontSize(17)
                    .fontWeight(900)
                    .fontColor(Theme.text(this.uiMode))
                  Text('在编辑台点「存草稿」，没写完的内容会留在这里')
                    .fontSize(12)
                    .fontColor(Theme.sub(this.uiMode))
                    .textAlign(TextAlign.Center)
                    .lineHeight(20)
                }
                .alignItems(HorizontalAlign.Center)

                Column()
                  .width(36)
                  .height(2)
                  .backgroundColor(this.uiMode === UiMode.JOURNAL
                    ? $r('app.color.accent_primary')
                    : Theme.rule(this.uiMode))
              }
              .width('100%')
              .padding({ top: 64, bottom: 40 })
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.drafts, (item: DraftItem) => {
                this.DraftRow(item)
              }, (item: DraftItem) => `${this.refreshTick}-${item.key}-${item.draft.updatedAt}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({
            left: StyleConstants.PAGE_PADDING_H,
            right: StyleConstants.PAGE_PADDING_H,
            top: StyleConstants.SPACE_MD,
            bottom: StyleConstants.SPACE_XXXL
          })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg(this.uiMode))
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.bg(this.uiMode))
    .onShown(() => {
      this.reload();
    })
  }
}
