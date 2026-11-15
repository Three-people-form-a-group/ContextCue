import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { ReminderCard, SlipRole } from './ReminderCard';
import { Reminder } from '../model/Reminder';
import { getAppServices } from '../app/AppServiceRegistry';
import {
  hasLocation,
  isCompleted,
  isLocationOnly,
  isPending,
  reminderLocationModeText,
  reminderLocationText,
  reminderPrimaryText,
  reminderRenderKey,
  reminderTimeText
} from '../common/ReminderView';
import { OtterSlot } from './OtterSlot';
import { EmptyState } from './EmptyState';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { RefreshSignal } from '../common/RefreshSignal';
import { PaperStyle } from '../common/PaperStyle';
import { PaperStore } from '../common/PaperStore';
import { DraftStore } from '../common/DraftStore';
import { DoodleStore } from '../common/DoodleStore';
import { DoodleView } from './DoodleView';
import { NoteLayoutView } from './NoteLayoutView';
import { NoteLayoutStore } from '../common/NoteLayoutStore';
import { parseLayout } from '../common/NoteLayoutModel';
import { DoodleSheet } from './DoodleSheet';

const VIEW_ARCHIVE: string = 'archive';
const VIEW_TIMELINE: string = 'timeline';

/**
 * 时间差 → 视觉间距（vp）。对数压缩，单调且有上限。
 * 只有两端都有真实 triggerTime 时才计算；地点提醒没有时间时不虚构。
 */
function gapHeightVp(prev: Reminder, cur: Reminder): number {
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
function formatGap(prev: Reminder, cur: Reminder): string {
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

/** 今日页由日期、待办列表与完成归档组成。时间轴复用同一份提醒。 */
@Component
export struct TodayDashboard {
  pathStack: NavPathStack = new NavPathStack();
  @State todayDateLabel: string = '';
  @State todayWeekday: string = '';
  /** 今天 0 点的毫秒值；跨 0 点会更新，今日筛选随之重算 */
  @State todayStartMs: number = 0;
  private dayTimer: number = -1;
  private todayKey: string = '';
  @State viewMode: string = VIEW_ARCHIVE;
  // 数据变更信号：提醒被创建/编辑/完成/删除后，其它页面据此重新查询服务
  @StorageLink('ccDataVersion') @Watch('onDataChanged') dataVersion: number = 0;
  @State items: Reminder[] = [];
  @State loadError: string = '';
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  @StorageLink('paperVersion') paperVersion: number = 1;
  @StorageLink('draftVersion') draftVersion: number = 1;
  @StorageLink('doodleVersion') doodleVersion: number = 1;
  @StorageLink('layoutVersion') layoutVersion: number = 1;
  @State doodleItemId: string = '';
  @State doodlePaper: string = '';
  @State showDoodle: boolean = false;
  @State doodleTitle: string = '';
  @State doodleTime: string = '';
  @State doodlePlace: string = '';
  @State doodleFeatured: boolean = false;
  /** 正在播放打勾动画的提醒 id；同一时间只播一个 */
  @State completingId: string = '';
  /** 打勾之后、移入归档之前：先划线淡出停留一会儿 */
  @State struckId: string = '';
  /** 长按后紧跟着的点击要忽略，否则会跳进详情页 */
  private longPressAt: number = 0;

  /**
   * 今日只显示「今天」的提醒 + 没有时间的纯地点提醒。
   * 昨天及更早未完成的（逾期）归到日程页的逾期区，跨 0 点自动换日。
   */
  private activeItems(): Reminder[] {
    const start: number = this.todayStartMs;
    const end: number = start + 24 * 3600 * 1000;
    const out: Reminder[] = [];
    const pending: Reminder[] = this.pendingItems();
    for (let i = 0; i < pending.length; i++) {
      const t: number | undefined = pending[i].triggerTime;
      if (start <= 0 || t === undefined || (t >= start && t < end)) {
        out.push(pending[i]);
      }
    }
    return out;
  }

  /** 全部待办（ACTIVE + TRIGGERED），按真实时间升序；没有时间的排最后 */
  private pendingItems(): Reminder[] {
    const timed: Reminder[] = [];
    const untimed: Reminder[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: Reminder = this.items[i];
      if (!isPending(item)) {
        continue;
      }
      if (item.triggerTime === undefined) {
        untimed.push(item);
      } else {
        timed.push(item);
      }
    }
    timed.sort((a: Reminder, b: Reminder) => {
      const ta: number = a.triggerTime === undefined ? 0 : a.triggerTime;
      const tb: number = b.triggerTime === undefined ? 0 : b.triggerTime;
      return ta - tb;
    });
    return timed.concat(untimed);
  }

  private doneItems(): Reminder[] {
    return this.items.filter((item: Reminder) => isCompleted(item));
  }

  aboutToAppear(): void {
    this.refreshToday();
    this.loadItems();
    // 每分钟看一眼日期：跨 0 点后重新计算标题与今日列表
    this.dayTimer = setInterval(() => {
      this.refreshToday();
    }, 60000);
  }

  /** 提醒数据只从 ReminderService 读取，页面自己持有响应式副本 */
  private async loadItems(): Promise<void> {
    const result = await getAppServices().reminderService.findAll();
    if (result.success && result.data !== undefined) {
      this.items = result.data;
      this.loadError = '';
      const active: Reminder[] = this.activeItems();
      for (let i = 0; i < active.length; i++) {
        DoodleStore.load(getContext(this), active[i].id);
        NoteLayoutStore.load(getContext(this), active[i].id);
      }
    } else {
      this.loadError = result.error === undefined ? '读取提醒失败' : result.error.message;
    }
  }

  onDataChanged(): void {
    this.loadItems();
  }

  aboutToDisappear(): void {
    if (this.dayTimer >= 0) {
      clearInterval(this.dayTimer);
      this.dayTimer = -1;
    }
  }

  private refreshToday(): void {
    const now: Date = new Date();
    const key: string = `${now.getFullYear()}-${now.getMonth()}-${now.getDate()}`;
    if (key === this.todayKey) {
      return;
    }
    this.todayKey = key;
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    this.todayDateLabel = `${now.getMonth() + 1} / ${now.getDate()}`;
    this.todayWeekday = weekdays[now.getDay()];
    this.todayStartMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
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

  private allItems(): Reminder[] {
    return this.activeItems().concat(this.doneItems());
  }

  /** 带时间的提醒，按真实时间升序；没有时间的不参与时间轴节点。 */
  private timedItems(): Reminder[] {
    const timed: Reminder[] = this.allItems().filter((item: Reminder) => {
      return item.triggerTime !== undefined;
    });
    timed.sort((a: Reminder, b: Reminder) => {
      const ta: number | undefined = a.triggerTime;
      const tb: number | undefined = b.triggerTime;
      const va: number = ta === undefined ? 0 : ta;
      const vb: number = tb === undefined ? 0 : tb;
      return va - vb;
    });
    return timed;
  }

  private untimedItems(): Reminder[] {
    return this.allItems().filter((item: Reminder) => item.triggerTime === undefined);
  }

  /** 时间轴上相邻两个真实节点之间的压缩间距（复用档案视图同一对数映射）。 */
  private timelineGapHeightAt(prevIndex: number, index: number): number {
    const list: Reminder[] = this.timedItems();
    return gapHeightVp(list[prevIndex], list[index]);
  }

  private timelineGapLabelAt(prevIndex: number, index: number): string {
    const list: Reminder[] = this.timedItems();
    return formatGap(list[prevIndex], list[index]);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          this.MastheadBlock()
          if (this.loadError !== '') {
            Text(this.loadError)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.alert(this.uiMode))
              .width('100%')
              .margin({ top: 8, bottom: 8 })
          }
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

      if (this.showDoodle) {
        DoodleSheet({
          paper: this.doodlePaper,
          initial: DoodleStore.get(this.doodleItemId),
          title: this.doodleTitle,
          timeText: this.doodleTime,
          placeText: this.doodlePlace,
          featured: this.doodleFeatured,
          reminderId: this.doodleItemId,
          initialLayout: NoteLayoutStore.data(this.doodleItemId),
          onSave: (data: string) => {
            DoodleStore.save(getContext(this), this.doodleItemId, data);
            const v: number = AppStorage.get<number>('doodleVersion') ?? 1;
            AppStorage.setOrCreate<number>('doodleVersion', v + 1);
            this.showDoodle = false;
          },
          onSaveLayout: (layout: string) => {
            NoteLayoutStore.save(getContext(this), this.doodleItemId, parseLayout(layout));
          },
          onClose: () => {
            this.showDoodle = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
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

        if (this.uiMode === UiMode.JOURNAL) {
          Column({ space: 6 }) {
            Row({ space: 0 }) {
              Text('今')
                .fontSize(54)
                .fontWeight(900)
                .fontColor($r('app.color.archive_paper'))
                .maxLines(1)
              Text('日')
                .fontSize(54)
                .fontWeight(900)
                .fontColor($r('app.color.accent_mustard'))
                .offset({ y: 6 })
                .maxLines(1)
            }
            .alignItems(VerticalAlign.Top)

            Row({ space: 8 }) {
              Text(this.todayDateLabel)
                .fontFamily('serif')
                .fontSize(14)
                .fontWeight(900)
                .fontColor($r('app.color.archive_ink'))
                .maxLines(1)
              Text(this.todayWeekday)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.archive_ink'))
                .maxLines(1)
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundImage($r('app.media.ticket_coral'))
            .backgroundImageSize({ width: '100%', height: '100%' })
            .rotate({ angle: -2 })
          }
          .width('90%')
          .padding({ left: 44, top: 40 })
          .alignItems(HorizontalAlign.Start)
        } else {
          // 极简：字号收一档；标题错落、计数贴右、日期与切换器同一行，短线只走 58%
          Column({ space: 12 }) {
            Row() {
              Row({ space: 0 }) {
                Text('今')
                  .fontSize(46)
                  .fontWeight(900)
                  .fontColor(Theme.text(this.uiMode))
                  .maxLines(1)
                Text('日')
                  .fontSize(46)
                  .fontWeight(900)
                  .fontColor(Theme.text(this.uiMode))
                  .offset({ y: 7 })
                  .maxLines(1)
              }
              .alignItems(VerticalAlign.Top)

              Blank()

              Column({ space: 1 }) {
                Text(`${this.activeItems().length}`)
                  .fontSize(24)
                  .fontWeight(900)
                  .fontColor(Theme.text(this.uiMode))
                Text('项待办')
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.sub(this.uiMode))
                  .letterSpacing(1)
              }
              .alignItems(HorizontalAlign.End)
              .padding({ bottom: 4 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)

            Row({ space: 8 }) {
              Text(this.todayDateLabel)
                .fontFamily('serif')
                .fontSize(13)
                .fontWeight(900)
                .fontColor(Theme.text(this.uiMode))
                .maxLines(1)
              Text(this.todayWeekday)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.sub(this.uiMode))
                .letterSpacing(1)
                .maxLines(1)
              Blank()
              this.ViewToggle()
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Column()
              .width('58%')
              .height(1)
              .backgroundColor(Theme.rule(this.uiMode))
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 10 })
          .alignItems(HorizontalAlign.Start)
        }

        if (this.uiMode === UiMode.JOURNAL) {
          Row() {
            Blank()
            OtterSlot({ slotWidth: 108 })
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

      if (this.uiMode === UiMode.JOURNAL) {
        Row({ space: 8 }) {
          Text(`${this.activeItems().length < 10 ? '0' : ''}${this.activeItems().length}`)
            .fontSize(18)
            .fontWeight(900)
            .fontColor($r('app.color.archive_ink'))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundImage($r('app.media.ticket_amber'))
            .backgroundImageSize({ width: '100%', height: '100%' })
            .rotate({ angle: -1.5 })
          Text('项待办')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
            .maxLines(1)
          Text('· 长按便签可涂鸦')
            .fontSize(10)
            .fontColor(Theme.sub(this.uiMode))
            .opacity(0.75)
            .maxLines(1)
          Blank()
          this.ViewToggle()
        }
        .width('100%')
        .height(48)
        .border({ width: { bottom: 1 }, color: Theme.rule(this.uiMode) })
        .alignItems(VerticalAlign.Center)
      }
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
        // 极简模式行本身已有细线，间隔不再重复画一条
        if (this.uiMode === UiMode.JOURNAL) {
          Column()
            .height(1)
            .layoutWeight(1)
            .backgroundColor($r('app.color.archive_rule'))
            .opacity(0.35)
        }
      }
    }
    .width('100%')
    .height(this.gapLabelAt(prevIndex, index) === '' ?
      this.gapHeightAt(prevIndex, index) : Math.max(29, this.gapHeightAt(prevIndex, index)))
    .alignItems(VerticalAlign.Center)
  }

  /** 极简模式的普通事项行：窄时间栏 + 正文，底部一条内收的细线 */
  @Builder
  SlipRow(item: Reminder, index: number) {
    Column() {
    Row({ space: 12 }) {
      Text(reminderTimeText(item))
        .fontFamily('serif')
        .fontSize(16)
        .fontWeight(900)
        .fontColor(isCompleted(item) ? Theme.rule(this.uiMode) : Theme.sub(this.uiMode))
        .width(48)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .padding({ top: 5 })

      Column({ space: 3 }) {
        Text(item.content)
          .fontSize(20)
          .fontWeight(900)
          .fontColor(Theme.text(this.uiMode))
          .lineHeight(28)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .decoration({
            type: this.struckId === item.id ? TextDecorationType.LineThrough : TextDecorationType.None
          })
          .opacity(this.struckId === item.id ? 0.45 : 1)
          .width('100%')
        if (hasLocation(item)) {
          Text(reminderLocationText(item))
            .fontSize(12)
            .fontColor(Theme.sub(this.uiMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.DoneCircle(item)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.minimalIndent(item), right: 0, top: 10, bottom: 10 })
    .onClick(() => this.goDetail(item))

    // 细线跟着文字的缩进走，而不是横贯整行
    Column()
      .width('100%')
      .height(StyleConstants.HAIRLINE_HEIGHT)
      .backgroundColor(Theme.rule(this.uiMode))
      .margin({ left: this.minimalIndent(item), bottom: 2 })
    }
  }

  /** 当前最紧的一条：靠错位、字重和一条细线强调，而不是整块填色 */
  /** 极简模式的当前事项：白卡 + 强调色左边条，视线先落这一条 */
  @Builder
  CurrentEntry(item: Reminder, index: number) {
    Row() {
      Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('当前')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.alert(this.uiMode))
          .letterSpacing(2)
        Blank()
        Text(reminderTimeText(item))
          .fontFamily('serif')
          .fontSize(14)
          .fontWeight(900)
          .fontColor(Theme.sub(this.uiMode))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(item.content)
        .fontSize(26)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .lineHeight(34)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .decoration({
          type: this.struckId === item.id ? TextDecorationType.LineThrough : TextDecorationType.None
        })
        .opacity(this.struckId === item.id ? 0.45 : 1)
        .width('100%')

      if (hasLocation(item)) {
        Text(reminderLocationText(item))
          .fontSize(12)
          .fontColor(Theme.sub(this.uiMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.goDetail(item))

      this.DoneCircle(item)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 8, top: 14, bottom: 16 })
    .backgroundColor(Theme.surface(this.uiMode))
    .border({ width: { left: 3 }, color: Theme.alert(this.uiMode) })
  }

  /** 完成按钮：点一下先播打勾动画（圆圈填色 + 勾弹出），再写入服务 */
  @Builder
  DoneCircle(item: Reminder) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(this.completingId === item.id ? Theme.ink(this.uiMode) : Color.Transparent)
        .border({
          width: 1.2,
          color: this.completingId === item.id ? Theme.ink(this.uiMode) : Theme.rule(this.uiMode)
        })
        .scale({
          x: this.completingId === item.id ? 1.12 : 1,
          y: this.completingId === item.id ? 1.12 : 1
        })
      Text('✓')
        .fontSize(11)
        .fontWeight(900)
        .fontColor(this.completingId === item.id
          ? Theme.surface(this.uiMode)
          : Theme.sub(this.uiMode))
        .opacity(this.completingId === item.id ? 1 : 0.5)
        .scale({
          x: this.completingId === item.id ? 1 : 0.6,
          y: this.completingId === item.id ? 1 : 0.6
        })
    }
    .width(32)
    .height(32)
    .onClick(() => {
      this.playComplete(item);
    })
  }

  /** 先播动画再提交：圆圈填墨、勾从 0.6 弹到 1，约 180ms 后写入服务 */
  private playComplete(item: Reminder): void {
    if (this.completingId !== '') {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.completingId = item.id;
    });
    setTimeout(() => {
      this.completeItem(item);
    }, 240);
  }

  private async completeItem(item: Reminder): Promise<void> {
    const result = await getAppServices().reminderService.complete(item.id);
    if (!result.success) {
      this.getUIContext().getPromptAction().showToast({
        message: result.error === undefined ? '标记完成失败' : result.error.message
      });
      this.completingId = '';
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已完成' });
    // 先停在该行上划线、淡出，约半秒后再真正移走，避免"打完勾瞬间消失"的突兀感
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.struckId = item.id;
    });
    setTimeout(() => {
      this.struckId = '';
      this.completingId = '';
      RefreshSignal.bump();
    }, 480);
  }

  /** 极简列表的轻微错位：用 id 散列，避免一眼看出交替规律 */
  private minimalIndent(item: Reminder): number {
    let h: number = 0;
    for (let i = 0; i < item.id.length; i++) {
      h = (h * 31 + item.id.charCodeAt(i)) % 997;
    }
    const step: number = h % 3;
    if (step === 0) {
      return 0;
    }
    return step === 1 ? 18 : 7;
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
        ForEach(this.activeItems(), (item: Reminder, index: number) => {
          if (index > 0) {
            this.GapRow(index - 1, index)
          }
          if (this.uiMode === UiMode.JOURNAL) {
            // 手账模式：每条事项就是一张便签；长按进入涂鸦
            Stack({ alignContent: Alignment.TopStart }) {
              if (DoodleStore.get(item.id) !== '') {
                DoodleView({ data: DoodleStore.get(item.id) })
                  .width('100%')
                  .height('100%')
              }
              Column() {
                if (PaperStore.isTextHidden(item.id)) {
                // 隐藏系统文字：只留一个小时间标记，其余留白给用户手写/涂鸦
                // 只留时间，但整块依然可点：点进去就能看到内容/取消隐藏
                Row() {
                  Text(reminderTimeText(item))
                    .fontFamily('serif')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.sub(this.uiMode))
                  Blank()
                  Text('…')
                    .fontSize(12)
                    .fontColor(Theme.sub(this.uiMode))
                    .opacity(0.6)
                }
                .width('100%')
                .padding({ left: 4, top: 2, right: 2 })
                .onClick(() => this.goDetail(item))
                } else {
                  NoteLayoutView({
                    layoutData: NoteLayoutStore.data(item.id),
                    time: isLocationOnly(item) ? '到达时' : reminderTimeText(item),
                    title: item.content,
                    place: hasLocation(item) ? reminderLocationText(item) : '',
                    featured: index === 0,
                    editable: false
                  })
                  .width('100%')
                  .height(180)
                  .clip(true)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              // 便签右上角的完成圈；不吃其它触摸
              Row() {
                Blank()
                this.DoneCircle(item)
              }
              .width('100%')
              .hitTestBehavior(HitTestMode.Transparent)
            }
            .width('104%')
            .height(214)
            .padding({ left: 18, right: 16, top: 14, bottom: 18 })
            .backgroundImage(PaperStyle.resource(PaperStore.paperOf(item.id)))
            .backgroundImageSize({ width: '100%', height: '100%' })
            .rotate({ angle: index % 2 === 0 ? -0.8 : 0.7 })
            .offset({ x: index % 2 === 0 ? 0 : -4 })
            .opacity(this.struckId === item.id ? 0.45 : 1)
            .onClick(() => {
              // 便签本身可点：进详情（长按刚结束时这次点击会被 goDetail 吞掉）
              this.goDetail(item);
            })
            .parallelGesture(
              LongPressGesture()
                .onAction(() => {
                  this.longPressAt = Date.now();
                  this.doodleItemId = item.id;
                  this.doodlePaper = PaperStore.paperOf(item.id);
                  this.doodleTitle = item.content;
                  this.doodleTime = isLocationOnly(item) ? '到达时' : reminderTimeText(item);
                  this.doodlePlace = hasLocation(item) ? reminderLocationText(item) : '';
                  this.doodleFeatured = index === 0;
                  this.showDoodle = true;
                })
            )
          } else if (index === 0) {
            this.CurrentEntry(item, index)
          } else {
            this.SlipRow(item, index)
          }
        }, (item: Reminder) => `${this.dataVersion}-${this.paperVersion}-${reminderRenderKey(item)}` +
            `-${PaperStore.paperOf(item.id)}-${PaperStore.isTextHidden(item.id) ? 'h' : 's'}` +
            `-${this.doodleVersion}-${DoodleStore.get(item.id).length}-${this.layoutVersion}`)
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

        ForEach(this.doneItems(), (item: Reminder) => {
          ReminderCard({
            data: item,
            role: SlipRole.ARCHIVE,
            onCardClick: () => {
              this.goDetail(item);
            }
          })
        }, (item: Reminder) => `${this.dataVersion}-${this.paperVersion}-${reminderRenderKey(item)}` +
            `-${PaperStore.paperOf(item.id)}-${PaperStore.isTextHidden(item.id) ? 'h' : 's'}` +
            `-${this.doodleVersion}-${DoodleStore.get(item.id).length}-${this.layoutVersion}`)
      }
      .width('100%')
      .margin({ top: StyleConstants.SPACE_XL })
    }
  }

  // ---------- 时间长卷 ----------

  /** 节点：时间在左栏，短刻度连接，内容在右。刻度只属于本节点，不跨行。 */
  private timelineInk(item: Reminder): ResourceColor {
    if (Theme.isMinimal(this.uiMode)) {
      return Theme.text(this.uiMode);
    }
    return hasLocation(item) ? $r('app.color.accent_coral') : $r('app.color.accent_sky');
  }

  @Builder
  TimelineNode(item: Reminder) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Text(reminderTimeText(item))
        .fontSize(StyleConstants.FONT_TITLE)
        .minFontSize(16)
        .maxFontSize(StyleConstants.FONT_TITLE)
        .fontWeight(900)
        .lineHeight(24)
        .fontColor(isCompleted(item)
          ? $r('app.color.text_secondary')
          : $r('app.color.text_primary'))
        .width(StyleConstants.TIMELINE_TIME_GUTTER)
        .textAlign(TextAlign.End)
        .maxLines(1)

      // 竖轴用左边框画（高度随内容自动延伸），刻度压在边框上，
      // 这样行与行之间、行内的横竖线都是连起来的
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: StyleConstants.SPACE_XS }) {
          Text(item.content)
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .lineHeight(24)
            .fontColor(isCompleted(item)
              ? $r('app.color.text_secondary')
              : $r('app.color.text_primary'))
            .decoration({
              type: isCompleted(item) || this.struckId === item.id
                ? TextDecorationType.LineThrough
                : TextDecorationType.None
            })
            .opacity(this.struckId === item.id ? 0.45 : 1)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (hasLocation(item)) {
            Row({ space: StyleConstants.SPACE_XS }) {
              Column()
                .width(6)
                .height(6)
                .backgroundColor($r('app.color.accent_sage'))
              Text(reminderLocationText(item))
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
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, bottom: StyleConstants.SPACE_SM })

        Column()
          .width(14)
          .height(3)
          .backgroundColor(isCompleted(item)
            ? $r('app.color.border_subtle')
            : this.timelineInk(item))
          .position({ x: -7, y: 10.5 })
      }
      .layoutWeight(1)
      .border({ width: { left: 1 }, color: '#80263C61' })
      .onClick(() => this.goDetail(item))

      this.DoneCircle(item)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 间隔：竖轴继续贯通，只在右侧标注真实时长 */
  @Builder
  TimelineGapRow(prevIndex: number, index: number) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column().width(StyleConstants.TIMELINE_TIME_GUTTER)

      Column() {
        if (this.timelineGapLabelAt(prevIndex, index) !== '') {
          this.GapTicket(this.timelineGapLabelAt(prevIndex, index), index)
        }
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.End)
      .border({ width: { left: 1 }, color: '#80263C61' })
    }
    .width('100%')
    .height(Math.max(29, this.timelineGapHeightAt(prevIndex, index)))
    .alignItems(VerticalAlign.Center)
  }

  /** 无固定时间的提醒：不虚构节点与间隔，单独成区。 */
  @Builder
  UntimedNode(item: Reminder) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column()
        .width(4)
        .height(48)
        .backgroundColor($r('app.color.accent_sage'))

      Column({ space: StyleConstants.SPACE_XS }) {
        Text(reminderPrimaryText(item))
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
        Text(reminderLocationModeText(item))
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
      if (this.timedItems().length === 0) {
        Text('今天没有带时间的提醒')
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_secondary'))
          .padding({
            top: StyleConstants.SPACE_MD,
            bottom: StyleConstants.SPACE_MD
          })
      } else {
        ForEach(this.timedItems(), (item: Reminder, index: number) => {
          if (index > 0) {
            this.TimelineGapRow(index - 1, index)
          }
          this.TimelineNode(item)
        }, (item: Reminder) => `${this.dataVersion}-${this.paperVersion}-${reminderRenderKey(item)}` +
            `-${PaperStore.paperOf(item.id)}-${PaperStore.isTextHidden(item.id) ? 'h' : 's'}` +
            `-${this.doodleVersion}-${DoodleStore.get(item.id).length}-${this.layoutVersion}`)
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

          ForEach(this.untimedItems(), (item: Reminder) => {
            this.UntimedNode(item)
          }, (item: Reminder) => `${this.dataVersion}-${this.paperVersion}-${reminderRenderKey(item)}` +
            `-${PaperStore.paperOf(item.id)}-${PaperStore.isTextHidden(item.id) ? 'h' : 's'}` +
            `-${this.doodleVersion}-${DoodleStore.get(item.id).length}-${this.layoutVersion}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  NewEntryBlock() {
    Column({ space: 8 }) {
      // 第一行：新建提醒（右对齐）
      Row() {
        Blank()
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

      // 第二行：草稿箱，同样右对齐
      Row() {
        Blank()
        if (this.uiMode === UiMode.JOURNAL) {
          Column({ space: 1 }) {
            Text('草稿箱')
              .fontSize(9)
              .fontColor($r('app.color.archive_ink'))
              .opacity(0.75)
            Text(`${this.draftCount()}`)
              .fontSize(17)
              .fontWeight(900)
              .fontColor($r('app.color.archive_ink'))
          }
          .width(64)
          .padding({ top: 5, bottom: 5 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundImage($r('app.media.ticket_amber'))
          .backgroundImageSize({ width: '100%', height: '100%' })
          .rotate({ angle: 2 })
          .onClick(() => {
            this.pathStack.pushPathByName(RouterConstants.PAGE_DRAFT_LIST, '');
          })
        } else {
          Row({ space: 6 }) {
            // 线条信封：一个描边矩形 + 一道封口折线，比文字行高略小一点，不抢视线
            Stack({ alignContent: Alignment.TopStart }) {
              Column()
                .width(20)
                .height(14)
                .border({ width: 1.1, color: $r('app.color.archive_ink') })
              Shape() {
                Path()
                  .commands('M0.9 0.9 L10 7.2 L19.1 0.9')
              }
              .width(20)
              .height(14)
              .strokeWidth(1.1)
              .stroke($r('app.color.archive_ink'))
              .fill(Color.Transparent)
            }
            .width(20)
            .height(14)

            Text('草稿箱')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.archive_ink'))
              .maxLines(1)
            // 条数徽标：和手账票根上的数字对应，始终显示（含 0）
            Text(`${this.draftCount()}`)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ink(this.uiMode))
              .textAlign(TextAlign.Center)
              .height(16)
              .constraintSize({ minWidth: 16 })
              .padding({ left: 4, right: 4 })
              .borderRadius(8)
              .border({ width: 1, color: Theme.rule(this.uiMode) })
          }
          .height(44)
          .padding({ left: 4, right: 4 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.pathStack.pushPathByName(RouterConstants.PAGE_DRAFT_LIST, '');
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
    .padding({ top: 12 })
    .margin({ top: StyleConstants.SPACE_SECTION })
    .border({ width: { top: 1 }, color: $r('app.color.border_subtle') })
  }

  /** 草稿数：读一次 draftVersion 建立刷新依赖，存/删草稿后这里才会重新求值 */
  private draftCount(): number {
    if (this.draftVersion < 0) {
      return 0;
    }
    return DraftStore.count();
  }

  goDetail(item: Reminder): void {
    // 长按刚结束时，子组件还会补发一次点击——这里吞掉，避免误跳详情
    if (Date.now() - this.longPressAt < 900) {
      return;
    }
    this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_DETAIL, new ReminderDetailNavParam(item.id));
  }
}
