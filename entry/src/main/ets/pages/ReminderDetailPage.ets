import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { UiReminderSource, UiReminderStatus, UiTriggerType } from '../common/UiReminderSemantics';
import { UiReminderStore } from '../common/UiReminderStore';
import { ReminderCardData } from '../components/ReminderCard';
import { TopBar } from '../components/TopBar';

/**
 * 提醒详情 —— 报纸中的一篇专题文章。
 *
 * 整页使用新闻纸底色；上方是日期与状态，中间是大号时间与标题，
 * 下方用规整的字段表展示元信息。视觉对比来自标题与分隔线，而不是堆叠圆角卡片。
 * 元信息字段对齐《ContextCue 公共架构与 AI 模块开发规范 v1.0》§5.2，
 * 全部由 ReminderCardData 派生。
 */
function formatDateLabel(epochMs: number | undefined): string {
  if (epochMs === undefined) {
    return '时间待定';
  }
  if (epochMs <= 0) {
    return '时间待定';
  }
  const d: Date = new Date(epochMs);
  const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return `${d.getMonth() + 1} / ${d.getDate()} · ${weekdays[d.getDay()]}`;
}

@Component
export struct ReminderDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @State card: ReminderCardData =
    new ReminderCardData('', '', UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE);
  // 编辑页保存后数据会改变；按 id 取最新记录，避免显示旧快照。
  // 版本号变化 → 重渲染 → 从 UI 数据源读取最新记录
  @StorageLink('uiReminderVersion') storeVersion: number = 0;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  aboutToAppear(): void {
    const params: Array<Object> =
      this.pathStack.getParamByName(RouterConstants.PAGE_REMINDER_DETAIL) as Array<Object>;
    if (params.length > 0) {
      const last: Object = params[params.length - 1];
      if (last instanceof ReminderDetailNavParam) {
        this.card = last.data;
      }
    }
  }

  private displayCard(): ReminderCardData {
    const id: string = this.card.id;
    if (id === '') {
      return this.card;
    }
    const active: ReminderCardData[] = UiReminderStore.getActive();
    for (let i = 0; i < active.length; i++) {
      if (active[i].id === id) {
        return active[i];
      }
    }
    const done: ReminderCardData[] = UiReminderStore.getDone();
    for (let i = 0; i < done.length; i++) {
      if (done[i].id === id) {
        return done[i];
      }
    }
    return this.card;
  }

  /** 页面重新显示时（例如从编辑页返回）从数据源取最新记录。 */
  private refreshFromStore(): void {
    const latest: ReminderCardData | undefined = UiReminderStore.findById(this.card.id);
    if (latest !== undefined) {
      this.card = latest;
    }
  }

  build() {
    NavDestination() {
      Column() {
        TopBar({
          title: '专题',
          showBack: true,
          onBack: () => {
            this.pathStack.pop();
          }
        })
        Scroll() {
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              // 专题纸页：顶部一道复古深蓝色带
              Column()
                .width('100%')
                .height(6)
                .backgroundColor(Theme.accent(this.uiMode))

              Column() {
                this.ArticleHead()
                this.CompletionStatus()
                this.MetaBlock()
                this.EditorNote()
                this.EditEntryBlock()
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({
                left: StyleConstants.PAGE_PADDING_H,
                right: StyleConstants.PAGE_PADDING_H,
                top: StyleConstants.SPACE_LG,
                bottom: StyleConstants.SPACE_XXL
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .backgroundColor(Theme.surface(this.uiMode))
            .borderRadius({
              topLeft: 0,
              topRight: StyleConstants.RADIUS_LG,
              bottomLeft: 0,
              bottomRight: 0
            })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)

          .borderRadius({
            topLeft: 0,
            topRight: StyleConstants.RADIUS_LG,
            bottomLeft: 0,
            bottomRight: 0
          })
          .margin({
            left: 12,
            right: 12,
            top: 12,
            bottom: 12
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
      this.refreshFromStore();
    })
  }

  @Builder
  ArticleHead() {
    Column({ space: StyleConstants.SPACE_SM }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        // 朱红套印标记（色块，不承载小字）
        Column()
          .width(3)
          .height(14)
          .backgroundColor(Theme.accent(this.uiMode))
        Text(this.displayCard().isLocationOnly() ? '地点便笺' : '事项详情')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
          .letterSpacing(2)
        Blank()
        Text(this.displayCard().statusText())
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.detail_note'))
          .letterSpacing(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor(Theme.text(this.uiMode))

      Text(formatDateLabel(this.displayCard().triggerTime))
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.detail_note'))
        .letterSpacing(2)
        .margin({ top: StyleConstants.SPACE_SM })

      Text(this.displayCard().isLocationOnly()
        ? this.displayCard().primaryText()
        : this.displayCard().timeText())
        .fontSize(this.displayCard().isLocationOnly()
          ? StyleConstants.FONT_TITLE_LG
          : StyleConstants.FONT_TIME_DISPLAY)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 连续下划线：标在时间数字正下方
        .decoration({
          type: TextDecorationType.Underline,
          color: $r('app.color.detail_ink')
        })

      Text(this.displayCard().content === '' ? '未命名提醒' : this.displayCard().content)
        .fontSize(StyleConstants.FONT_TITLE_LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text(this.uiMode))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: StyleConstants.SPACE_XS })

      // 栏线有意只走到 62%，与右侧负空间形成中断
      Column()
        .width(StyleConstants.RULE_SHORT_WIDTH)
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor(Theme.text(this.uiMode))
        .margin({ top: StyleConstants.SPACE_SM })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /**
   * 字段行：标签在左、值在右。
   * asTag=true 时，地点值用朱褐墨色和下划线标记。
   */
  @Builder
  MetaRow(label: string, value: string, asTag: boolean) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Text(label)
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.detail_note'))
        .letterSpacing(1)
        .width(72)

      if (asTag) {
        Text(value)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent(this.uiMode))
          .decoration({ type: TextDecorationType.Underline })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      } else {
        Text(value)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text(this.uiMode))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({
      top: StyleConstants.SPACE_MD,
      bottom: StyleConstants.SPACE_MD
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  MetaDivider() {
    Column()
      .width('100%')
      .height(StyleConstants.HAIRLINE_HEIGHT)
      .backgroundColor($r('app.color.detail_note'))
      .opacity(0.35)
  }

  @Builder
  CompletionStatus() {
    if (this.displayCard().isCompleted()) {
      Row({ space: 8 }) {
        Text('✓')
          .fontSize(17)
          .fontWeight(900)
          .fontColor(Theme.ink(this.uiMode))
        Text('已完成')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.sub(this.uiMode))
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .margin({ top: 12 })
      .border({ width: { top: 1, bottom: 1 }, color: Theme.rule(this.uiMode) })
    }
  }

  @Builder
  MetaBlock() {
    Column() {
      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor(Theme.text(this.uiMode))
      this.MetaRow('触发类型', this.displayCard().typeText(), false)
      this.MetaDivider()
      this.MetaRow('提醒来源', this.displayCard().sourceText(), false)
      this.MetaDivider()
      this.MetaRow('当前状态', this.displayCard().statusText(), false)
      this.MetaDivider()
      this.MetaRow('地点', this.displayCard().locationText(), this.displayCard().hasLocation())
      this.MetaDivider()
    }
    .width('100%')
    .margin({ top: StyleConstants.SPACE_LG })
  }

  @Builder
  EditorNote() {
    Column({ space: StyleConstants.SPACE_XS }) {
      Text('编辑批注')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.accent(this.uiMode))
        .letterSpacing(2)
      Text('AI 辅助与情境建议将在这里以批注形式出现')
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontColor($r('app.color.detail_note'))
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(StyleConstants.SPACE_LG)
    .margin({ top: StyleConstants.SPACE_XL })
    .border({
      width: StyleConstants.RULE_MEDIUM,
      color: $r('app.color.detail_ink'),
      style: BorderStyle.Dashed
    })
  }

  @Builder
  EditEntryBlock() {
    Column({ space: StyleConstants.SPACE_SM }) {
      Column()
        .width('100%')
        .height(StyleConstants.HAIRLINE_HEIGHT)
        .backgroundColor($r('app.color.detail_note'))
        .opacity(0.35)
        .margin({ bottom: StyleConstants.SPACE_MD })

      // 炭黑排版动作：与头版同一套语言，不再使用橙色通用按钮
      Row() {
        Row({ space: StyleConstants.SPACE_MD }) {
          Text('编辑此提醒')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor($r('app.color.archive_paper'))
          Text('→')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor($r('app.color.archive_paper'))
        }
        .height(52)
        .padding({
          left: StyleConstants.SPACE_XXXL,
          right: StyleConstants.SPACE_XXXL
        })
        .backgroundColor(Theme.text(this.uiMode))
        .borderRadius({
          topLeft: 0,
          topRight: StyleConstants.RADIUS_MD,
          bottomLeft: 0,
          bottomRight: StyleConstants.RADIUS_MD
        })
        .onClick(() => {
          this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
            new ReminderEditNavParam(RouterConstants.EDIT_MODE_EDIT, this.displayCard()));
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text('修改会保存在本次演示的临时数据中')
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontColor($r('app.color.detail_note'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_XL })
  }
}
