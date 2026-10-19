import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { UiReminderStore } from '../common/UiReminderStore';
import { ReminderCardData, ReminderCard, SlipRole } from './ReminderCard';
import { OtterSlot, OtterState } from './OtterSlot';
import { SettingsGear } from './SettingsGear';
import { EmptyState } from './EmptyState';

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

/** 时间差批注：+45 MIN / +6 H / +4 H 30 M；无法计算时返回空串。 */
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
    return `+${total} MIN`;
  }
  const hours: number = Math.floor(total / 60);
  const rest: number = total % 60;
  return rest === 0 ? `+${hours} H` : `+${hours} H ${rest} M`;
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
  if (index === 0) {
    return SlipRole.LEAD;
  }
  // 只有「纯地点提醒」才进入 FIELD 版式；
  // 时间+地点（BOTH）必须以时间为主信息，否则会看起来像纯地点提醒。
  if (item.isLocationOnly() && index % 2 === 0) {
    return SlipRole.FIELD;
  }
  // 其余全部使用开放式排版：不再为普通提醒增加容器
  return SlipRole.EDITORIAL;
}

/**
 * 今日页面 —— ContextCue · Temporal Gazette 头版。
 *
 * 报头：小号英文刊名 + 期号 + 粗细分隔线 + 日期 + 巨型「今日」+ 水獭编辑员。
 * 正文：时间装订线 + 报纸版面（头版重点 / 栏目 / 情境标记 / 无版面），
 *       相邻间距由真实时间差压缩得出。
 * 已完成事项移入 SEALED RECORDS 归档版面。
 * 右上角齿轮进入设置页；统计行右侧可切换档案 / 时间轴两种视图。
 */
@Component
export struct TodayDashboard {
  pathStack: NavPathStack = new NavPathStack();
  @State todayDateLabel: string = '';
  @State todayWeekday: string = '';
  @State viewMode: string = VIEW_ARCHIVE;
  // 版本号变化 → 重渲染 → 通过方法读取最新数据
  @StorageLink('uiReminderVersion') storeVersion: number = 0;

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

  private noLabel(index: number): string {
    const n: number = index + 1;
    return n < 10 ? `No. 0${n}` : `No. ${n}`;
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
  }

  @Builder
  ViewToggle() {
    Row({ space: StyleConstants.SPACE_XS }) {
      Text(this.viewMode === VIEW_ARCHIVE ? '时间轴' : '版面')
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .letterSpacing(1)
        .maxLines(1)
      Text(this.viewMode === VIEW_ARCHIVE ? '→' : '←')
        .fontSize(StyleConstants.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent_vermilion'))
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

  /**
   * 报纸报头：英文刊名、期号、粗细线、日期、巨型中文标题、水獭编辑员。
   * 绘制顺序：奶油纸块 → 水獭 → 文字，文字永远在最上层。
   */
  @Builder
  MastheadBlock() {
    Column() {
      // 刊名行
      Row() {
        Text('THE DAILY GAZETTE')
          .fontSize(StyleConstants.FONT_CAPTION)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(2)
          .maxLines(1)
        Blank()
        Text('NO.017')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(2)
          .maxLines(1)
      }
      .width('100%')
      .height(20)
      .alignItems(VerticalAlign.Center)

      // 粗线
      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor($r('app.color.text_primary'))

      // 日期行 + 设置入口
      Row({ space: StyleConstants.SPACE_SM }) {
        Text(this.todayDateLabel)
          .fontSize(StyleConstants.FONT_CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(2)
        Text(this.todayWeekday)
          .fontSize(StyleConstants.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(1)
        Blank()
        SettingsGear({
          onTap: () => {
            this.pathStack.pushPathByName(RouterConstants.PAGE_SETTINGS, '');
          }
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)

      // 细线
      Column()
        .width('100%')
        .height(StyleConstants.HAIRLINE_HEIGHT)
        .backgroundColor($r('app.color.accent_secondary'))

      // 主标题 + 水獭编辑员：底纸错位 + 主纸切角 + 朱红套印条
      Stack({ alignContent: Alignment.TopStart }) {
        // 主纸 + 右上切角
        Stack({ alignContent: Alignment.TopEnd }) {
          Column()
            .width('100%')
            .height(76)
            .backgroundColor($r('app.color.surface_primary'))
            .backgroundImage($r('app.media.newsprint_grain'), ImageRepeat.XY)
            .backgroundImageSize({ width: 256, height: 256 })
          Column()
            .width(12)
            .height(12)
            .backgroundColor($r('app.color.background_primary'))
            .offset({ x: 6, y: -6 })
        }
        .width('72%')
        .offset({ x: -StyleConstants.PAGE_PADDING_H, y: 26 })

        Row() {
          OtterSlot({
            state: OtterState.IDLE,
            slotWidth: StyleConstants.OTTER_MASTHEAD
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .offset({ x: 8, y: -2 })

        Column() {
          Text('今')
            .fontSize(StyleConstants.FONT_MASTHEAD_TITLE)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Text('日')
            .fontSize(StyleConstants.FONT_MASTHEAD_TITLE)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: StyleConstants.SPACE_XL })
          // 朱红套印条：编辑标记，不承载文字
          Column()
            .width(36)
            .height(4)
            .backgroundColor($r('app.color.accent_vermilion'))
            .margin({ left: StyleConstants.SPACE_XS, top: StyleConstants.SPACE_XS })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .width('100%')
      .height(130)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))

      // 头版引导行
      Row({ space: StyleConstants.SPACE_SM }) {
        Text('TODAY’S LEAD')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_vermilion'))
          .letterSpacing(2)
          .maxLines(1)
        Text(`${this.activeItems().length}`)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
        Blank()
        this.ViewToggle()
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: StyleConstants.SPACE_MD })
  }

  @Builder
  GapRow(prevIndex: number, index: number) {
    Row() {
      Column() {
        if (this.gapLabelAt(prevIndex, index) !== '') {
          Row({ space: StyleConstants.SPACE_XS }) {
            Column()
              .width(2)
              .height(12)
              .backgroundColor($r('app.color.accent_vermilion'))
            Text(this.gapLabelAt(prevIndex, index))
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .letterSpacing(2)
              .maxLines(1)
          }
          .padding({
            left: 8,
            right: 10,
            top: 4,
            bottom: 4
          })
          .backgroundColor($r('app.color.surface_primary'))
          .rotate({ angle: -2 })
        }
      }
      .padding({ left: StyleConstants.SPACE_LG })
      Blank()
    }
    .width('100%')
    .height(this.gapHeightAt(prevIndex, index))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SlipRow(item: ReminderCardData, index: number) {
    ReminderCard({
      data: item,
      role: resolveSlipRole(item, index),
      isNext: index === 0,
      indexLabel: this.noLabel(index),
      entryNo: this.noShort(index),
      tagTone: index,
      onCardClick: () => {
        this.goDetail(item);
      }
    })
  }

  @Builder
  ArchiveBlock() {
    Column() {
      if (this.activeItems().length === 0) {
        EmptyState({
          title: '今天没有待办提醒',
          subtitle: '时间公报还是空白的'
        })
      } else {
        ForEach(this.activeItems(), (item: ReminderCardData, index: number) => {
          if (index > 0) {
            this.GapRow(index - 1, index)
          }
          this.SlipRow(item, index)
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
          Text('SEALED RECORDS')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(2)
          Text(`${this.doneItems().length}`)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent_secondary'))
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
          .height(StyleConstants.RULE_HEAVY)
          .backgroundColor(item.isCompleted()
            ? $r('app.color.border_subtle')
            : $r('app.color.text_primary'))
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
          .height(this.timelineGapHeightAt(prevIndex, index))
          .backgroundColor($r('app.color.brand_primary'))
          .opacity(0.5)
      }
      .width(StyleConstants.TIMELINE_MARK_WIDTH)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text(this.timelineGapLabelAt(prevIndex, index))
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.85)
          .letterSpacing(2)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(this.timelineGapHeightAt(prevIndex, index))
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
          .backgroundColor($r('app.color.accent_vermilion'))
        Text('TIMELINE')
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
            Text('NO FIXED TIME')
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

  /**
   * 新建入口：右偏置的"表冠"操作。高度 52vp（≥44），文案明确，
   * 位于 Scroll 内，不会被底部 TabBar 遮挡。
   */
  @Builder
  NewEntryBlock() {
    Row({ space: StyleConstants.SPACE_MD }) {
      // 一条短栏线代替原来的虚线与轴标记：轴已经不存在，装饰也随之删除
      Column()
        .width(StyleConstants.SPACE_XXL)
        .height(StyleConstants.HAIRLINE_HEIGHT)
        .backgroundColor($r('app.color.text_primary'))

      Blank()

      Row({ space: StyleConstants.SPACE_MD }) {
        Row({ space: 3 }) {
          Column()
            .width(2)
            .height(StyleConstants.SPACE_SM)
            .backgroundColor($r('app.color.text_primary'))
            .opacity(0.5)
          Column()
            .width(2)
            .height(StyleConstants.SPACE_MD)
            .backgroundColor($r('app.color.text_primary'))
            .opacity(0.72)
          Column()
            .width(2)
            .height(StyleConstants.SPACE_LG)
            .backgroundColor($r('app.color.text_primary'))
        }
        .alignItems(VerticalAlign.Center)

        Text('新建提醒')
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
      }
      .padding({
        left: StyleConstants.SPACE_XL,
        right: StyleConstants.SPACE_XL
      })
      .height(52)
      .backgroundColor($r('app.color.accent_primary'))
      .onClick(() => {
        this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
          new ReminderEditNavParam(RouterConstants.EDIT_MODE_CREATE));
      })
    }
    .width('100%')
    .margin({ top: StyleConstants.SPACE_XXL })
  }

  goDetail(item: ReminderCardData): void {
    this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_DETAIL, new ReminderDetailNavParam(item));
  }
}
