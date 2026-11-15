import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { PaperStyle } from '../common/PaperStyle';
import { PaperStore } from '../common/PaperStore';
import { PaperPickerSheet } from '../components/PaperPickerSheet';
import { DoodleStore } from '../common/DoodleStore';
import { DoodleSheet } from '../components/DoodleSheet';
import { NoteLayoutStore } from '../common/NoteLayoutStore';
import { parseLayout } from '../common/NoteLayoutModel';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { Reminder } from '../model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { getAppServices } from '../app/AppServiceRegistry';
import { RefreshSignal } from '../common/RefreshSignal';
import {
  isCompleted,
  isLocationOnly,
  isPending,
  reminderLocationText,
  reminderPrimaryText,
  reminderSourceText,
  reminderStatusText,
  reminderTimeText,
  reminderTypeText,
  hasLocation
} from '../common/ReminderView';
import { TopBar } from '../components/TopBar';

/**
 * 提醒详情 —— 报纸中的一篇专题文章。
 *
 * 整页使用新闻纸底色；上方是日期与状态，中间是大号时间与标题，
 * 下方用规整的字段表展示元信息。视觉对比来自标题与分隔线，而不是堆叠圆角卡片。
 * 元信息字段对齐《ContextCue 公共架构与 AI 模块开发规范 v1.0》§5.2，
 * 全部由公共 model/Reminder 派生。
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
  @State card: Reminder = {
    id: '', content: '', triggerType: TriggerType.TIME,
    status: ReminderStatus.ACTIVE, source: ReminderSource.MANUAL, createdAt: 0
  };
  @State loaded: boolean = false;
  @State loadError: string = '';
  // 提醒被编辑/完成后版本号变化 → 按 id 重新查询服务
  @StorageLink('ccDataVersion') @Watch('onStoreChanged') dataVersion: number = 0;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  @State showPaperPicker: boolean = false;
  @State paper: string = PaperStyle.LARGE_WARM;
  @State textHidden: boolean = false;
  @State showDoodle: boolean = false;
  /** 今日页第一条是大字号排版；这里跟着用同样的字号，预览才对得上。 */
  @State featured: boolean = false;

  aboutToAppear(): void {
    const params: Array<Object> =
      this.pathStack.getParamByName(RouterConstants.PAGE_REMINDER_DETAIL) as Array<Object>;
    if (params.length > 0) {
      const last: Object = params[params.length - 1];
      if (last instanceof ReminderDetailNavParam) {
        this.card.id = last.id;
      }
    }
    this.paper = PaperStore.paperOf(this.card.id);
    DoodleStore.load(getContext(this), this.card.id);
    NoteLayoutStore.load(getContext(this), this.card.id);
    this.textHidden = PaperStore.isTextHidden(this.card.id);
    this.refreshFromStore();
  }

  private onStoreChanged(): void {
    this.refreshFromStore();
  }

  /** 按 id 从 ReminderService 取最新记录（导航参数里只有 id） */
  private async refreshFromStore(): Promise<void> {
    if (this.card.id === '') {
      return;
    }
    const result = await getAppServices().reminderService.findById(this.card.id);
    if (result.success && result.data !== undefined) {
      this.card = result.data;
      this.loaded = true;
      this.loadError = '';
    } else {
      this.loadError = result.error === undefined ? '读取提醒失败' : result.error.message;
    }
    const all = await getAppServices().reminderService.findAll();
    if (all.success && all.data !== undefined) {
      const pending: Reminder[] = all.data.filter((r: Reminder) => isPending(r));
      this.featured = pending.length > 0 && pending[0].id === this.card.id;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
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
                .backgroundColor(Theme.ink(this.uiMode))

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

        if (this.showDoodle) {
          DoodleSheet({
            paper: this.paper,
            initial: DoodleStore.get(this.card.id),
            title: this.card.content,
            timeText: isLocationOnly(this.card) ? '到达时' : reminderTimeText(this.card),
            placeText: hasLocation(this.card) ? reminderLocationText(this.card) : '',
            featured: this.featured,
            reminderId: this.card.id,
            // 和今日页共用同一份排版，否则这里看到的是默认排版、改完也回不到今日页
            initialLayout: NoteLayoutStore.data(this.card.id),
            onSave: (data: string) => {
              DoodleStore.save(getContext(this), this.card.id, data);
              const v: number = AppStorage.get<number>('doodleVersion') ?? 1;
              AppStorage.setOrCreate<number>('doodleVersion', v + 1);
              this.showDoodle = false;
            },
            onSaveLayout: (layout: string) => {
              NoteLayoutStore.save(getContext(this), this.card.id, parseLayout(layout));
            },
            onClose: () => {
              this.showDoodle = false;
            }
          })
        }

        if (this.showPaperPicker) {
          PaperPickerSheet({
            current: this.paper,
            onPick: (paper: string) => {
              this.paper = paper;
              this.showPaperPicker = false;
              PaperStore.setPaper(getContext(this), this.card.id, paper);
            },
            onClose: () => {
              this.showPaperPicker = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
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
          .backgroundColor(Theme.ink(this.uiMode))
        Text(isLocationOnly(this.card) ? '地点便笺' : '事项详情')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
          .letterSpacing(2)
        Blank()
        Text(reminderStatusText(this.card))
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

      Text(formatDateLabel(this.card.triggerTime))
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.detail_note'))
        .letterSpacing(2)
        .margin({ top: StyleConstants.SPACE_SM })

      Text(isLocationOnly(this.card)
        ? reminderPrimaryText(this.card)
        : reminderTimeText(this.card))
        .fontSize(isLocationOnly(this.card)
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

      Text(this.card.content === '' ? '未命名提醒' : this.card.content)
        .fontSize(StyleConstants.FONT_TITLE_LG)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text(this.uiMode))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: StyleConstants.SPACE_XS })

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
          .fontColor(Theme.ink(this.uiMode))
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
  CompletionStatus() {
    if (isCompleted(this.card)) {
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
    }
  }

  @Builder
  MetaBlock() {
    Column() {
      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor(Theme.text(this.uiMode))
      this.MetaRow('触发类型', reminderTypeText(this.card), false)
      this.MetaRow('提醒来源', reminderSourceText(this.card), false)
      this.MetaRow('当前状态', reminderStatusText(this.card), false)
      this.MetaRow('地点', reminderLocationText(this.card), hasLocation(this.card))
      if (this.uiMode === UiMode.JOURNAL) {
        Column()
          .width('100%')
          .height(StyleConstants.HAIRLINE_HEIGHT)
          .backgroundColor(Theme.rule(this.uiMode))
          .margin({ top: StyleConstants.SPACE_SM, bottom: StyleConstants.SPACE_SM })

        Row() {
          Text('纸张')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
            .letterSpacing(1)
            .width(52)
          Text(PaperStyle.label(this.paper))
            .fontSize(StyleConstants.FONT_BODY)
            .fontColor(Theme.text(this.uiMode))
            .layoutWeight(1)
          Text('更换 ›')
            .fontSize(11)
            .fontColor(Theme.ink(this.uiMode))
        }
        .width('100%')
        .padding({ top: StyleConstants.SPACE_SM, bottom: StyleConstants.SPACE_SM })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showPaperPicker = true;
        })

        Row() {
          Text('涂鸦')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
            .letterSpacing(1)
            .width(52)
          Text(DoodleStore.get(this.card.id) === '' ? '还没有笔迹' : '已有笔迹')
            .fontSize(StyleConstants.FONT_BODY)
            .fontColor(Theme.text(this.uiMode))
            .layoutWeight(1)
          Text('去画 ›')
            .fontSize(11)
            .fontColor(Theme.ink(this.uiMode))
        }
        .width('100%')
        .padding({ top: StyleConstants.SPACE_SM, bottom: StyleConstants.SPACE_SM })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showDoodle = true;
        })

        Row() {
          Text('文字')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
            .letterSpacing(1)
            .width(52)
          Text(this.textHidden ? '已隐藏，留白手写' : '显示中')
            .fontSize(StyleConstants.FONT_BODY)
            .fontColor(Theme.text(this.uiMode))
            .layoutWeight(1)
          Text(this.textHidden ? '显示 ›' : '隐藏 ›')
            .fontSize(11)
            .fontColor(Theme.ink(this.uiMode))
        }
        .width('100%')
        .padding({ top: StyleConstants.SPACE_SM, bottom: StyleConstants.SPACE_SM })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.textHidden = !this.textHidden;
          PaperStore.setTextHidden(getContext(this), this.card.id, this.textHidden);
        })
      }
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
        .fontColor(Theme.ink(this.uiMode))
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

  private async deleteReminder(): Promise<void> {
    const result = await getAppServices().reminderService.delete(this.card.id);
    if (!result.success) {
      this.getUIContext().getPromptAction().showToast({
        message: result.error === undefined ? '删除失败' : result.error.message
      });
      return;
    }
    RefreshSignal.bump();
    this.pathStack.pop();
  }

  private confirmDelete(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除提醒',
      message: '删除后不可恢复，确定删除吗？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.detail_ink') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.deleteReminder();
      }
    }).catch(() => {
    });
  }

  @Builder
  EditEntryBlock() {
    Column({ space: StyleConstants.SPACE_SM }) {
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
            new ReminderEditNavParam(RouterConstants.EDIT_MODE_EDIT, this.card.id));
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text('删除此提醒')
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.sub(this.uiMode))
        .decoration({ type: TextDecorationType.Underline })
        .height(StyleConstants.TOUCH_TARGET_MIN)
        .padding({ left: StyleConstants.SPACE_LG, right: StyleConstants.SPACE_LG })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.confirmDelete();
        })

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
