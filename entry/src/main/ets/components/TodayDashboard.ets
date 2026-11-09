import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { UiReminderStore } from '../common/UiReminderStore';
import { ReminderCardData, ReminderCard, SlipRole } from './ReminderCard';
import { OtterSlot, OtterState } from './OtterSlot';
import { EmptyState } from './EmptyState';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';

const VIEW_ARCHIVE: string = 'archive';
const VIEW_TIMELINE: string = 'timeline';

/**
 * 时间差 → 视觉间距（vp）。对数压缩，单调且有上限。
 * 只有两端都有真实 triggerTime 时才计算；地点提醒没有时间时不虚构。
 */
function gapHeightVp(prev: ReminderCardData, cur: ReminderCardData): number {
  if (prev.triggerTime === undefined || cur.triggerTime === undefined) {
    return StyleConstants.GAP_MIN;
  }
  const minutes: number = (cur.triggerTime - prev.triggerTime) / 60000;
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return StyleConstants.GAP_MIN;
  }
  const raw: number = StyleConstants.GAP_BASE + StyleConstants.GAP_K * Math.log(1 + minutes / 60);
  return Math.min(StyleConstants.GAP_MAX, Math.max(StyleConstants.GAP_MIN, raw));
}

/** 时间差批注：＋45 分钟 / ＋6 小时 / ＋4 小时 30 分钟；无法计算时返回空串。 */
function formatGap(prev: ReminderCardData, cur: ReminderCardData): string {
  if (prev.triggerTime === undefined || cur.triggerTime === undefined) {
    return '';
  }
  const minutes: number = (cur.triggerTime - prev.triggerTime) / 60000;
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return '';
  }
  const total: number = Math.round(minutes);
  if (total < 60) {
    return `＋${total} 分钟`;
  }
  const hours: number = Math.floor(total / 60);
  const rest: number = total % 60;
  return rest === 0 ? `＋${hours} 小时` : `＋${hours} 小时 ${rest} 分钟`;
}

/**
 * 拼贴版面角色分配（确定性规则，与业务枚举无关）：
 *   已完成 → ARCHIVE；第一条 → LEAD；带地点且偶数位 → FIELD；
 *   每三条一次 → EDITORIAL；其余 → SLIP。
 */
function resolveSlipRole(item: ReminderCardData, index: number): string {
  if (item.isCompleted()) {
    return SlipRole.ARCHIVE;
  }
  // 只有「纯地点提醒」才进入 FIELD 版式；
  // 时间+地点（BOTH）必须以时间为主信息，否则会看起来像纯地点提醒。
  if (item.isLocationOnly() && index % 2 === 0) {
    return SlipRole.FIELD;
  }
  // 其余全部使用开放式排版：不再为普通提醒增加容器
  return SlipRole.EDITORIAL;
}

/** 今日页由日期、待办列表与完成归档组成。时间轴复用同一份提醒。 */
@Component
export struct TodayDashboard {
  pathStack: NavPathStack = new NavPathStack();
  @State todayDateLabel: string = '';
  @State todayWeekday: string = '';
  @State viewMode: string = VIEW_ARCHIVE;
  // 版本号变化 → 重渲染 → 通过方法读取最新数据
  @StorageLink('uiReminderVersion') storeVersion: number = 0;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  /** 首页按真实时间排序：修改时间后条目位置会随之改变。 */
  private activeItems(): ReminderCardData[] {
    return UiReminderStore.sortedActive();
  }

  private doneItems(): ReminderCardData[] {
    return UiReminderStore.getDone();
  }

  aboutToAppear(): void {
    const now: Date = new Date();
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const month: number = now.getMonth() + 1;
    const day: number = now.getDate();
    this.todayDateLabel = `${month} / ${day}`;
    this.todayWeekday = weekdays[now.getDay()];
  }

  private gapHeightAt(prevIndex: number, index: number): number {
    return gapHeightVp(this.activeItems()[prevIndex], this.activeItems()[index]);
  }

  private gapLabelAt(prevIndex: number, index: number): string {
    return formatGap(this.activeItems()[prevIndex], this.activeItems()[index]);
  }

  private noShort(index: number): string {
    const n: number = index + 1;
    return n < 10 ? `0${n}` : `${n}`;
  }

  private allItems(): ReminderCardData[] {
    return this.activeItems().concat(this.doneItems());
  }

  /** 带时间的提醒，按真实时间升序；没有时间的不参与时间轴节点。 */
  private timedItems(): ReminderCardData[] {
    const timed: ReminderCardData[] = this.allItems().filter((item: ReminderCardData) => {
      return item.triggerTime !== undefined;
    });
    timed.sort((a: ReminderCardData, b: ReminderCardData) => {
      const ta: number | undefined = a.triggerTime;
      const tb: number | undefined = b.triggerTime;
      const va: number = ta === undefined ? 0 : ta;
      const vb: number = tb === undefined ? 0 : tb;
      return va - vb;
    });
    return timed;
  }

  private untimedItems(): ReminderCardData[] {
    return this.allItems().filter((item: ReminderCardData) => item.triggerTime === undefined);
  }

  /** 时间轴上相邻两个真实节点之间的压缩间距（复用档案视图同一对数映射）。 */
  private timelineGapHeightAt(prevIndex: number, index: number): number {
    const list: ReminderCardData[] = this.timedItems();
    return gapHeightVp(list[prevIndex], list[index]);
  }

  private timelineGapLabelAt(prevIndex: number, index: number): string {
    const list: ReminderCardData[] = this.timedItems();
    return formatGap(list[prevIndex], list[index]);
  }

  build() {
    Scroll() {
      Column() {
        this.MastheadBlock()
        if (this.viewMode === VIEW_ARCHIVE) {
          this.ArchiveBlock()
          this.SealedBlock()
        } else {
          this.TimelineBlock()
        }
        this.NewEntryBlock()
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({
        left: StyleConstants.PAGE_PADDING_H,
        right: StyleConstants.PAGE_PADDING_H,
        top: StyleConstants.SPACE_LG,
        bottom: StyleConstants.SPACE_XXXL
      })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg(this.uiMode))
  }

  @Builder
  ViewToggle() {
    Row({ space: StyleConstants.SPACE_XS }) {
      Text(this.viewMode === VIEW_ARCHIVE ? '时间轴' : '列表')
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(1)
        .maxLines(1)
      Text(this.viewMode === VIEW_ARCHIVE ? '→' : '←')
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_secondary'))
    }
    .height(StyleConstants.TOUCH_TARGET_MIN)
    .padding({
      left: StyleConstants.SPACE_MD,
      right: StyleConstants.SPACE_MD
    })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.viewMode = this.viewMode === VIEW_ARCHIVE ? VIEW_TIMELINE : VIEW_ARCHIVE;
    })
  }

  @Builder
  MastheadBlock() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 手账模式：深蓝撕纸 + 胶带 + 贴纸水獭；极简模式：一块干净的白卡
        if (this.uiMode === UiMode.JOURNAL) {
          Image($r('app.media.torn_note_deep_blue'))
            .width('90%')
            .aspectRatio(700 / 420)
            .objectFit(ImageFit.Fill)
        }

        Column({ space: 6 }) {
          Row({ space: 0 }) {
            Text('今')
              .fontSize(54)
              .fontWeight(900)
              .fontColor(this.uiMode === UiMode.JOURNAL
                ? $r('app.color.archive_paper')
                : Theme.text(this.uiMode))
              .maxLines(1)
            Text('日')
              .fontSize(54)
              .fontWeight(900)
              .fontColor(this.uiMode === UiMode.JOURNAL
                ? $r('app.color.accent_mustard')
                : Theme.text(this.uiMode))
              .offset({ y: 6 })
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Top)

          Row({ space: 8 }) {
            Text(this.todayDateLabel)
              .fontFamily('serif')
              .fontSize(14)
              .fontWeight(900)
              .fontColor(this.uiMode === UiMode.JOURNAL
                ? $r('app.color.archive_ink')
                : Theme.sub(this.uiMode))
              .maxLines(1)
            Text(this.todayWeekday)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.uiMode === UiMode.JOURNAL
                ? $r('app.color.archive_ink')
                : Theme.sub(this.uiMode))
              .maxLines(1)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundImage(this.uiMode === UiMode.JOURNAL ? $r('app.media.ticket_coral') : undefined)
          .backgroundImageSize({ width: '100%', height: '100%' })
          .rotate({ angle: this.uiMode === UiMode.JOURNAL ? -2 : 0 })
        }
        .width(this.uiMode === UiMode.JOURNAL ? '90%' : '100%')
        .padding({
          left: this.uiMode === UiMode.JOURNAL ? 44 : 4,
          top: this.uiMode === UiMode.JOURNAL ? 40 : 6
        })
        .alignItems(HorizontalAlign.Start)

        if (this.uiMode === UiMode.JOURNAL) {
          Row() {
            Blank()
            OtterSlot({ state: OtterState.IDLE, slotWidth: 108 })
              .rotate({ angle: 8 })
          }
          .width('100%')
          .offset({ x: 22, y: 52 })
        }

        if (this.uiMode === UiMode.JOURNAL) {
          Image($r('app.media.washi_grid_corner'))
            .width(100)
            .height(42)
            .rotate({ angle: 18 })
            .offset({ x: 4, y: -10 })
        }
      }
      .width('100%')
      .height(this.uiMode === UiMode.JOURNAL ? 180 : 132)

      Row({ space: 8 }) {
        if (this.uiMode === UiMode.JOURNAL) {
          Text(`${this.activeItems().length < 10 ? '0' : ''}${this.activeItems().length}`)
            .fontSize(18)
            .fontWeight(900)
            .fontColor($r('app.color.archive_ink'))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundImage($r('app.media.ticket_amber'))
            .backgroundImageSize({ width: '100%', height: '100%' })
            .rotate({ angle: -1.5 })
        } else {
          Text(`${this.activeItems().length}`)
            .fontSize(18)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
        }
        Text('项待办')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.sub(this.uiMode))
          .maxLines(1)
        Blank()
        this.ViewToggle()
      }
      .width('100%')
      .height(48)
      .border({ width: { bottom: 1 }, color: Theme.rule(this.uiMode) })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  /** 间隔票根按位置轮换四种颜色，避免整页同一个紫 */
  private gapTicket(index: number): Resource {
    const tickets: Resource[] = [
      $r('app.media.ticket_coral'),
      $r('app.media.ticket_amber'),
      $r('app.media.ticket_salt'),
      $r('app.media.ticket_pink')
    ];
    return tickets[index % tickets.length];
  }

  @Builder
  GapTicket(label: string, index: number) {
    Text(label)
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.uiMode === UiMode.JOURNAL ? $r('app.color.archive_ink') : Theme.sub(this.uiMode))
      .padding({ left: this.uiMode === UiMode.JOURNAL ? 11 : 0, right: this.uiMode === UiMode.JOURNAL ? 11 : 0, top: 6, bottom: 6 })
      .backgroundImage(this.uiMode === UiMode.JOURNAL ? this.gapTicket(index) : undefined)
      .backgroundImageSize({ width: '100%', height: '100%' })
      .rotate({ angle: this.uiMode === UiMode.JOURNAL ? -1.5 : 0 })
      .maxLines(1)
  }

  @Builder
  GapRow(prevIndex: number, index: number) {
    Row({ space: 9 }) {
      if (this.gapLabelAt(prevIndex, index) !== '') {
        this.GapTicket(this.gapLabelAt(prevIndex, index), index)
        Column()
          .height(1)
          .layoutWeight(1)
          .backgroundColor($r('app.color.archive_rule'))
          .opacity(0.35)
      }
    }
    .width('100%')
    .height(this.gapLabelAt(prevIndex, index) === '' ?
      this.gapHeightAt(prevIndex, index) : Math.max(29, this.gapHeightAt(prevIndex, index)))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SlipRow(item: ReminderCardData, index: number) {
    ReminderCard({
      data: item,
      role: resolveSlipRole(item, index),
      isNext: index === 0,
      indexLabel: `第 ${this.noShort(index)} 则`,
      entryNo: this.noShort(index),
      onCardClick: () => {
        this.goDetail(item);
      }
    })
  }


  /** 当前最紧的一条：靠错位、字重和一条细线强调，而不是整块填色 */
  @Builder
  CurrentEntry(item: ReminderCardData, index: number) {
    Row() {
      Column().width(14)
      Column({ space: 6 }) {
        Row({ space: 10 }) {
          Text('当前')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent_primary'))
            .letterSpacing(2)
          Column()
            .width(40)
            .height(1.5)
            .backgroundColor(this.uiMode === UiMode.JOURNAL
              ? $r('app.color.accent_mustard')
              : Theme.rule(this.uiMode))
          Blank()
          Text(item.timeText())
            .fontFamily('serif')
            .fontSize(20)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(item.content)
          .fontSize(26)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(34)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.hasLocation()) {
          Text(item.locationText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 14 })
      .border({ width: { bottom: 1.5 }, color: $r('app.color.archive_rule') })
      .onClick(() => this.goDetail(item))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 6 })
  }

  @Builder
  ArchiveBlock() {
    Column() {
      if (this.activeItems().length === 0) {
        EmptyState({
          title: '今天没有待办提醒',
          subtitle: '可以记下今天想做的事'
        })
      } else {
        ForEach(this.activeItems(), (item: ReminderCardData, index: number) => {
          if (index > 0) {
            this.GapRow(index - 1, index)
          }
          if (index === 0) {
            this.CurrentEntry(item, index)
          } else {
            this.SlipRow(item, index)
          }
        }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
      }
    }
    .width('100%')
  }

  @Builder
  SealedBlock() {
    if (this.doneItems().length > 0) {
      Column({ space: StyleConstants.SPACE_SM }) {
        Row({ space: StyleConstants.SPACE_SM }) {
          Text('完成归档')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(2)
          Text(`${this.doneItems().length} 条`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.archive_rule'))
          Blank()
          Column()
            .width(StyleConstants.SPACE_XXL)
            .height(StyleConstants.HAIRLINE_HEIGHT)
            .backgroundColor($r('app.color.border_subtle'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        ForEach(this.doneItems(), (item: ReminderCardData) => {
          ReminderCard({
            data: item,
            role: SlipRole.ARCHIVE,
            onCardClick: () => {
              this.goDetail(item);
            }
          })
        }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
      }
      .width('100%')
      .margin({ top: StyleConstants.SPACE_XL })
    }
  }

  // ---------- 时间长卷 ----------

  /** 节点：时间在左栏，短刻度连接，内容在右。刻度只属于本节点，不跨行。 */
  private timelineInk(item: ReminderCardData): ResourceColor {
    if (Theme.isMinimal(this.uiMode)) {
      return Theme.text(this.uiMode);
    }
    return item.hasLocation() ? $r('app.color.accent_coral') : $r('app.color.accent_sky');
  }

  @Builder
  TimelineNode(item: ReminderCardData) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Text(item.timeText())
        .fontSize(StyleConstants.FONT_TITLE)
        .minFontSize(16)
        .maxFontSize(StyleConstants.FONT_TITLE)
        .fontWeight(900)
        .fontColor(item.isCompleted()
          ? $r('app.color.text_secondary')
          : $r('app.color.text_primary'))
        .width(StyleConstants.TIMELINE_TIME_GUTTER)
        .textAlign(TextAlign.End)
        .maxLines(1)

      Column() {
        Column()
          .width(14)
          .height(3)
          .backgroundColor(item.isCompleted()
            ? $r('app.color.border_subtle')
            : this.timelineInk(item))
      }
      .width(StyleConstants.TIMELINE_MARK_WIDTH)
      .alignItems(HorizontalAlign.Center)

      Column({ space: StyleConstants.SPACE_XS }) {
        Text(item.content)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.isCompleted()
            ? $r('app.color.text_secondary')
            : $r('app.color.text_primary'))
          .decoration({
            type: item.isCompleted() ? TextDecorationType.LineThrough : TextDecorationType.None
          })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.hasLocation()) {
          Row({ space: StyleConstants.SPACE_XS }) {
            Column()
              .width(6)
              .height(6)
              .backgroundColor($r('app.color.accent_sage'))
            Text(item.locationText())
              .fontSize(StyleConstants.FONT_CAPTION)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({
        top: StyleConstants.SPACE_SM,
        bottom: StyleConstants.SPACE_SM
      })
      .onClick(() => this.goDetail(item))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 间隔：只画一段可中断的竖线 + 一条真实时长批注 */
  @Builder
  TimelineGapRow(prevIndex: number, index: number) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column().width(StyleConstants.TIMELINE_TIME_GUTTER)

      Column() {
        Column()
          .width(StyleConstants.HAIRLINE_HEIGHT)
          .height(Math.max(29, this.timelineGapHeightAt(prevIndex, index)))
          .backgroundColor($r('app.color.brand_primary'))
          .opacity(0.5)
      }
      .width(StyleConstants.TIMELINE_MARK_WIDTH)
      .alignItems(HorizontalAlign.Center)

      Column() {
        if (this.timelineGapLabelAt(prevIndex, index) !== '') {
          this.GapTicket(this.timelineGapLabelAt(prevIndex, index), index)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(Math.max(29, this.timelineGapHeightAt(prevIndex, index)))
    .alignItems(VerticalAlign.Center)
  }

  /** 无固定时间的提醒：不虚构节点与间隔，单独成区。 */
  @Builder
  UntimedNode(item: ReminderCardData) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column()
        .width(4)
        .height(48)
        .backgroundColor($r('app.color.accent_sage'))

      Column({ space: StyleConstants.SPACE_XS }) {
        Text(item.primaryText())
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.content)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.locationModeText())
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.8)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.goDetail(item))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      top: StyleConstants.SPACE_SM,
      bottom: StyleConstants.SPACE_SM
    })
  }

  @Builder
  TimelineBlock() {
    Column() {
      Row({ space: StyleConstants.SPACE_SM }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor($r('app.color.archive_rule'))
        Text('时序索引')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(2)
        Blank()
        Text('按真实时间排列')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.75)
      }
      .width('100%')
      .margin({ bottom: StyleConstants.SPACE_MD })

      if (this.timedItems().length === 0) {
        Text('今天没有带时间的提醒')
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_secondary'))
          .padding({
            top: StyleConstants.SPACE_MD,
            bottom: StyleConstants.SPACE_MD
          })
      } else {
        ForEach(this.timedItems(), (item: ReminderCardData, index: number) => {
          if (index > 0) {
            this.TimelineGapRow(index - 1, index)
          }
          this.TimelineNode(item)
        }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
      }

      if (this.untimedItems().length > 0) {
        Column() {
          Row({ space: StyleConstants.SPACE_SM }) {
            Column()
              .width(3)
              .height(14)
              .backgroundColor($r('app.color.accent_sage'))
            Text('地点便笺')
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .letterSpacing(2)
            Blank()
            Text('无固定时间')
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({
            top: StyleConstants.SPACE_SECTION,
            bottom: StyleConstants.SPACE_SM
          })

          ForEach(this.untimedItems(), (item: ReminderCardData) => {
            this.UntimedNode(item)
          }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  NewEntryBlock() {
    Row({ space: StyleConstants.SPACE_MD }) {
      Text('＋ 新建提醒')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.archive_ink'))
        .padding({ left: 14, right: 14 })
        .height(46)
        .backgroundImage(this.uiMode === UiMode.JOURNAL ? $r('app.media.ticket_salt') : undefined)
        .backgroundImageSize({ width: '100%', height: '100%' })
        .onClick(() => {
          this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
            new ReminderEditNavParam(RouterConstants.EDIT_MODE_CREATE));
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding({ top: 12 })
    .margin({ top: StyleConstants.SPACE_SECTION })
    .border({ width: { top: 1 }, color: $r('app.color.border_subtle') })
  }

  goDetail(item: ReminderCardData): void {
    this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_DETAIL, new ReminderDetailNavParam(item));
  }
}
