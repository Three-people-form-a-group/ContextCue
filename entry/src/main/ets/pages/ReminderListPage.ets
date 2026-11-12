import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { MockReminderData, ReminderGroupData } from '../common/MockReminderData';
import { UiReminderStore } from '../common/UiReminderStore';
import { ReminderCardData } from '../components/ReminderCard';
import { UiTriggerType, UiLocationTriggerMode } from '../common/UiReminderSemantics';
import { TimetableView } from '../components/TimetableView';

/**
 * 日程页：列表内嵌月历，课表使用独立滚动区域。
 *
 * 与首页（视觉个性）分工不同：本页强调查找效率。
 * 用粗黑栏目标题 + 粗细分隔线 + 宽松文字行组织，而不是重复首页的拼贴效果。
 * 设置只由底部 Tab 进入，本页不再提供齿轮入口，避免重复入口。
 */
@Component
export struct ReminderListPage {
  pathStack: NavPathStack = new NavPathStack();
  groups: ReminderGroupData[] = MockReminderData.ALL_GROUPS;
  // 编辑页保存后由 AppStorage 通知刷新；按 id 用最新记录替换分组里的旧对象
  // 版本号变化 → 重渲染 → 从 UI 数据源读取最新记录
  @StorageLink('uiReminderVersion') storeVersion: number = 0;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  /** 'index' 列表视图（含内嵌月历）/ 'timetable' 课表视图 */
  @State viewMode: string = 'index';
  @State calYear: number = 0;
  @State calMonth: number = 0;
  /** 0 表示不按日期筛选，显示全部 */
  @State selectedDay: number = 0;
  /** 月历默认收起，避免长期占用列表空间 */
  @State calExpanded: boolean = false;

  aboutToAppear(): void {
    const now: Date = new Date();
    this.calYear = now.getFullYear();
    this.calMonth = now.getMonth() + 1;
  }


  /** 左栏时间：纯地点提醒写"到达时"，时间+地点写"20:00 后" */
  private timeLabel(item: ReminderCardData): string {
    if (item.triggerType === UiTriggerType.LOCATION) {
      return '到达时';
    }
    if (item.triggerType === UiTriggerType.BOTH) {
      return `${item.timeText()} 后`;
    }
    return item.timeText();
  }

  /** 地点补充行：把"进入/离开"和提醒关系写清楚 */
  private placeLabel(item: ReminderCardData): string {
    if (!item.hasLocation()) {
      return '';
    }
    const scene: string = item.sceneName === undefined || item.sceneName === '' ? '未设置地点' : item.sceneName;
    const mode: string = item.locationTriggerMode === UiLocationTriggerMode.EXIT ? '离开时' : '到达时';
    return `${scene}（${mode}提醒）`;
  }

  /** 分组对应的日期（今天 / 明天），用于在标题旁突出"日" */
  private groupDate(groupIndex: number): Date | undefined {
    if (groupIndex > 1) {
      return undefined;
    }
    const now: Date = new Date();
    if (groupIndex === 1) {
      now.setDate(now.getDate() + 1);
    }
    return now;
  }

  /** 回到今天：月历与列表一起复位 */
  private backToToday(): void {
    const now: Date = new Date();
    this.calYear = now.getFullYear();
    this.calMonth = now.getMonth() + 1;
    this.selectedDay = now.getDate();
  }

  /** 所有提醒：Mock 分组 + 数据源里新增的条目，按 id 去重 */
  private allReminders(): ReminderCardData[] {
    const out: ReminderCardData[] = [];
    const seen: string[] = [];
    for (let g = 0; g < this.groups.length; g++) {
      const group: ReminderGroupData = this.groups[g];
      for (let i = 0; i < group.items.length; i++) {
        const item: ReminderCardData = this.resolve(group.items[i]);
        if (UiReminderStore.isDeleted(item.id)) {
          continue;
        }
        if (seen.indexOf(item.id) < 0) {
          seen.push(item.id);
          out.push(item);
        }
      }
    }
    const store: ReminderCardData[] = UiReminderStore.getActive();
    for (let i = 0; i < store.length; i++) {
      if (seen.indexOf(store[i].id) < 0) {
        seen.push(store[i].id);
        out.push(store[i]);
      }
    }
    return out;
  }

  private itemsOnDate(day: number): ReminderCardData[] {
    const out: ReminderCardData[] = [];
    const all: ReminderCardData[] = this.allReminders();
    for (let i = 0; i < all.length; i++) {
      const t: number | undefined = all[i].triggerTime;
      if (t === undefined) {
        continue;
      }
      const d: Date = new Date(t);
      if (d.getFullYear() === this.calYear && d.getMonth() + 1 === this.calMonth && d.getDate() === day) {
        out.push(all[i]);
      }
    }
    return this.sortItems(out);
  }

  private hasReminder(day: number): boolean {
    return this.itemsOnDate(day).length > 0;
  }

  private isToday(day: number): boolean {
    const now: Date = new Date();
    return now.getFullYear() === this.calYear && now.getMonth() + 1 === this.calMonth && now.getDate() === day;
  }

  /** 按星期排布的月份网格；0 表示空位 */
  private calendarRows(): number[][] {
    const first: number = new Date(this.calYear, this.calMonth - 1, 1).getDay();
    const days: number = new Date(this.calYear, this.calMonth, 0).getDate();
    const cells: number[] = [];
    for (let i = 0; i < first; i++) {
      cells.push(0);
    }
    for (let d = 1; d <= days; d++) {
      cells.push(d);
    }
    while (cells.length % 7 !== 0) {
      cells.push(0);
    }
    const rows: number[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      rows.push(cells.slice(i, i + 7));
    }
    return rows;
  }

  /** 条目自己的日期：M/D 周X */
  private dateLabelOf(item: ReminderCardData): string {
    const t: number | undefined = item.triggerTime;
    if (t === undefined) {
      return '';
    }
    const d: Date = new Date(t);
    const wd: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return `${d.getMonth() + 1}/${d.getDate()} ${wd[d.getDay()]}`;
  }

  private weekdayOf(day: number): string {
    const wd: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return wd[new Date(this.calYear, this.calMonth - 1, day).getDay()];
  }

  private shiftMonth(delta: number): void {
    let m: number = this.calMonth + delta;
    let y: number = this.calYear;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    if (m > 12) {
      m = 1;
      y += 1;
    }
    this.calYear = y;
    this.calMonth = m;
    this.selectedDay = 0;
  }

  private resolve(item: ReminderCardData): ReminderCardData {
    const list: ReminderCardData[] = UiReminderStore.getActive();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === item.id) {
        return list[i];
      }
    }
    return item;
  }

  /** 按真实时间排序；无时间的条目排在末尾。 */
  private sortItems(items: ReminderCardData[]): ReminderCardData[] {
    const timed: ReminderCardData[] = [];
    const untimed: ReminderCardData[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: ReminderCardData = items[i];
      if (item.triggerTime === undefined) {
        untimed.push(item);
      } else {
        timed.push(item);
      }
    }
    timed.sort((a: ReminderCardData, b: ReminderCardData) => {
      const ta: number | undefined = a.triggerTime;
      const tb: number | undefined = b.triggerTime;
      const va: number = ta === undefined ? 0 : ta;
      const vb: number = tb === undefined ? 0 : tb;
      return va - vb;
    });
    return timed.concat(untimed);
  }

  private sortedGroupItems(group: ReminderGroupData): ReminderCardData[] {
    const resolved: ReminderCardData[] = [];
    for (let i = 0; i < group.items.length; i++) {
      const item: ReminderCardData = this.resolve(group.items[i]);
      if (!UiReminderStore.isDeleted(item.id)) {
        resolved.push(item);
      }
    }
    return this.sortItems(resolved);
  }

  /**
   * 实际渲染用的分组条目。
   * 今日组会追加数据源里「不属于任何 Mock 分组」的新建提醒，
   * 否则新建的提醒永远不会出现在全部页。
   */
  /** 一条提醒应该落在哪个分组：今天 / 明天 / 本周稍后 */
  private groupIndexOfDate(ms: number | undefined): number {
    if (ms === undefined) {
      return this.groups.length - 1;
    }
    const target: Date = new Date(ms);
    const now: Date = new Date();
    const a: number = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    const b: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const days: number = Math.floor((a - b) / 86400000);
    if (days <= 0) {
      return 0;
    }
    if (days === 1) {
      return 1;
    }
    return 2;
  }

  /**
   * 实际渲染用的分组条目。
   * 数据源里不属于任何 Mock 分组的条目，按日期落到 今天 / 明天 / 本周稍后。
   */
  private liveGroupItems(group: ReminderGroupData, groupIndex: number): ReminderCardData[] {
    const base: ReminderCardData[] = this.sortedGroupItems(group);
    const known: string[] = [];
    for (let g = 0; g < this.groups.length; g++) {
      for (let i = 0; i < this.groups[g].items.length; i++) {
        known.push(this.groups[g].items[i].id);
      }
    }
    const extra: ReminderCardData[] = [];
    const storeItems: ReminderCardData[] = UiReminderStore.getActive();
    for (let i = 0; i < storeItems.length; i++) {
      const item: ReminderCardData = storeItems[i];
      if (known.indexOf(item.id) >= 0 || UiReminderStore.isDeleted(item.id)) {
        continue;
      }
      if (this.groupIndexOfDate(item.triggerTime) === groupIndex) {
        extra.push(item);
      }
    }
    return this.sortItems(base.concat(extra));
  }


  build() {
    if (this.viewMode === 'timetable') {
      // 课表视图自带 Scroll，不能再套在外层 Scroll 里，否则内层滚动失效
      Column() {
        Column() {
          this.HeaderBlock()
        }
        .width('100%')
        .padding({
          left: StyleConstants.PAGE_PADDING_H,
          right: StyleConstants.PAGE_PADDING_H,
          top: StyleConstants.SPACE_LG
        })

        Column() {
          TimetableView()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    } else {
      Scroll() {
        Column() {
          this.HeaderBlock()
          // 日历不再是独立视图，而是列表页顶部可展开的一块
          this.CalendarBlock()
          if (this.selectedDay === 0) {
            this.GroupListBlock()
          } else {
            this.CalendarDayList()
          }
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
  }

  /**
   * 页头：不对称排版 —— 左侧标题块，右侧细小的视图切换；
   * 下方粗线只走 78%，右侧留白。
   */
  @Builder
  HeaderBlock() {
    Column() {
      Row() {
        Column({ space: 1 }) {
          Text('日程')
            .fontSize(28)
            .fontWeight(900)
            .fontColor(Theme.ink(this.uiMode))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        this.ViewModeItem('列表', 'index')
        this.ViewModeItem('课表', 'timetable')
        if (this.viewMode !== 'timetable') {
          Text('＋')
            .fontSize(18)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .width(StyleConstants.TOUCH_TARGET_MIN)
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
                new ReminderEditNavParam(RouterConstants.EDIT_MODE_CREATE));
            })
        }
      }
      .width('100%')
      .height(54)
      .alignItems(VerticalAlign.Bottom)

      Row() {
        Column()
          .width('78%')
          .height(StyleConstants.RULE_HEAVY)
          .backgroundColor(Theme.ink(this.uiMode))
        Blank()
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: StyleConstants.SPACE_MD })
  }

  @Builder
  ViewModeItem(label: string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.viewMode === mode ? 900 : FontWeight.Medium)
      .fontColor(this.viewMode === mode
        ? Theme.ink(this.uiMode)
        : Theme.sub(this.uiMode))
      .height(44)
      .padding({ left: 8, right: 8 })
      .textAlign(TextAlign.Center)
      .decoration({
        type: this.viewMode === mode ? TextDecorationType.Underline : TextDecorationType.None,
        color: Theme.accent(this.uiMode)
      })
      .onClick(() => {
        this.viewMode = mode;
        this.selectedDay = 0;
      })
  }

  /** 分组配色轮换：珊瑚 / 芥末 / 薄荷 / 天蓝，让整页有节奏而不是一片墨色 */
  private groupAccent(index: number): Resource {
    const tones: Resource[] = [
      $r('app.color.accent_coral'),
      $r('app.color.accent_mustard'),
      $r('app.color.accent_mint'),
      $r('app.color.accent_sky')
    ];
    return tones[index % tones.length];
  }

  /** 分组标题：衬线大编号 + 组名 + 条数，分隔线从编号右侧起、不到底。 */
  @Builder
  GroupHeader(group: ReminderGroupData, groupIndex: number) {
    Column() {
      Row({ space: 12 }) {
        // 手账：一天一组时，左侧一块日期牌（今天朱橙、明天暖灰），作为整页唯一的视觉焦点
        if (this.uiMode === UiMode.JOURNAL && this.groupDate(groupIndex) !== undefined) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(54)
              .height(56)
              .backgroundColor(groupIndex === 0
                ? $r('app.color.accent_primary')
                : $r('app.color.plate_alt'))
              .borderRadius({
                topLeft: 0,
                topRight: 10,
                bottomLeft: 0,
                bottomRight: 0
              })
            Text(`${this.groupDate(groupIndex)!.getDate()}`)
              .fontFamily('serif')
              .fontSize(30)
              .fontWeight(900)
              .fontColor(groupIndex === 0 ? $r('app.color.archive_paper') : Theme.ink(this.uiMode))
          }
          .width(54)
          .height(56)
        }

        Column({ space: 3 }) {
          Row({ space: 6 }) {
            if (this.uiMode === UiMode.MINIMAL) {
              Column()
                .width(groupIndex === 0 ? 8 : 7)
                .height(groupIndex === 0 ? 8 : 7)
                .borderRadius(4)
                .backgroundColor(groupIndex === 0 ? Theme.alert(this.uiMode) : Color.Transparent)
                .border({
                  width: groupIndex === 1 ? 1.5 : 0,
                  color: Theme.alert(this.uiMode)
                })
                .opacity(groupIndex > 1 ? 0.35 : 1)
            }
            Text(group.groupLabel)
              .fontSize(24)
              .fontWeight(900)
              .fontColor(Theme.ink(this.uiMode))
          }
          .alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            if (this.groupDate(groupIndex) !== undefined) {
              Text(`${this.groupDate(groupIndex)!.getMonth() + 1} 月`)
                .fontSize(11)
                .fontColor(Theme.sub(this.uiMode))
            }
            Text(`${this.liveGroupItems(group, groupIndex).length} 条`)
              .fontSize(11)
              .fontColor(Theme.sub(this.uiMode))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 18, bottom: 6 })
  }

  /**
   * 时间栏固定在左、事项在右，两侧起点恒定。
   * 条目不再画 L 形边框：手账模式只用留白分隔，极简模式保留一条很淡的底线。
   * 颜色只表示"下一项"——橙点 + 一行小字，避免颜色无意义地出现。
   */
  @Builder
  ScheduleEntry(item: ReminderCardData, featured: boolean, showDate: boolean, index: number) {
    Row({ space: StyleConstants.SPACE_MD }) {
      // 左：窄时间栏（固定 64vp，圆点槽固定 10vp，保证时间永远从同一位置起笔）
      Column({ space: 2 }) {
        Row({ space: 2 }) {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(featured && !item.isCompleted() ? Theme.alert(this.uiMode) : Color.Transparent)
          Text(this.timeLabel(item))
            .fontFamily('serif')
            .fontSize(15)
            .fontWeight(900)
            .fontColor(item.isCompleted() ? Theme.sub(this.uiMode) : Theme.ink(this.uiMode))
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)

        if (featured && !item.isCompleted()) {
          Text('下一项')
            .fontSize(9)
            .fontColor(Theme.alert(this.uiMode))
            .letterSpacing(1)
            .padding({ left: 8 })
        }
      }
      .width(64)
      .alignItems(HorizontalAlign.Start)

      // 右：内容栏
      Column({ space: 4 }) {
        Text(item.content)
          .fontSize(featured ? 19 : 16)
          .fontWeight(featured ? 900 : FontWeight.Bold)
          .fontColor(item.isCompleted()
            ? Theme.sub(this.uiMode)
            : Theme.text(this.uiMode))
          .decoration({ type: item.isCompleted() ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (item.hasLocation()) {
          Text(this.placeLabel(item))
            .fontSize(12)
            .fontWeight(FontWeight.Regular)
            .fontColor(Theme.sub(this.uiMode))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (item.isCompleted()) {
          Text(item.statusText())
            .fontSize(10)
            .fontColor(Theme.sub(this.uiMode))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({
        left: 10,
        bottom: 10
      })
      .border({
        width: {
          bottom: this.uiMode === UiMode.MINIMAL ? StyleConstants.HAIRLINE_HEIGHT : 0
        },
        color: Theme.rule(this.uiMode)
      })

      Text('›')
        .fontSize(15)
        .fontColor(Theme.sub(this.uiMode))
        .accessibilityLevel('no')
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 4, right: 4, top: featured ? 12 : 10, bottom: 2 })
    .onClick(() => {
      this.goDetail(item);
    })
  }

  @Builder
  GroupListBlock() {
    Column({ space: StyleConstants.SPACE_SECTION }) {
      ForEach(this.groups, (group: ReminderGroupData, groupIndex: number) => {
        Column() {
          this.GroupHeader(group, groupIndex)
          ForEach(this.liveGroupItems(group, groupIndex), (item: ReminderCardData, itemIndex: number) => {
            this.ScheduleEntry(item, groupIndex === 0 && itemIndex === 0 && !item.isCompleted(), true, itemIndex)
          }, (item: ReminderCardData, itemIndex: number) => `${this.storeVersion}-${item.renderKey()}-${itemIndex}`)
        }
        .width('100%')
      }, (group: ReminderGroupData) => group.groupOverline)
    }
    .width('100%')
  }

  @Builder
  DayCell(day: number) {
    if (day === 0) {
      Column()
        .width('14.28%')
        .height(50)
    } else {
      Column({ space: 2 }) {
        // 选中 = 墨蓝绿圆形底；今天 = 印章砖红；普通提醒 = 砖红小点
        Column() {
          Text(`${day}`)
            .fontSize(13)
            .fontWeight(this.selectedDay === day || this.isToday(day) ? 900 : FontWeight.Medium)
            .fontColor(this.selectedDay === day
              ? $r('app.color.archive_paper')
              : (this.isToday(day) ? Theme.alert(this.uiMode) : Theme.text(this.uiMode)))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.selectedDay === day ? Theme.accent(this.uiMode) : Color.Transparent)

        Row({ space: 3 }) {
          if (this.isToday(day)) {
            Column()
              .width(10)
              .height(3)
              .borderRadius(2)
              .backgroundColor(Theme.alert(this.uiMode))
          }
          if (this.hasReminder(day)) {
            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(Theme.alert(this.uiMode))
          }
        }
        .height(5)
        .alignItems(VerticalAlign.Center)
      }
      .width('14.28%')
      .height(50)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.selectedDay = day;
      })
    }
  }

  /**
   * 列表页内嵌的月历：不再是一页，而是列表顶部可展开的一块。
   * 收起时只占一行；展开后点某天就把下面的列表筛成那一天。
   */
  @Builder
  CalendarBlock() {
    Column({ space: StyleConstants.SPACE_XS }) {
      Row({ space: 2 }) {
        Text('日历')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.sub(this.uiMode))
          .letterSpacing(1)
        Blank()
        if (this.selectedDay !== 0) {
          Text('全部')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ink(this.uiMode))
            .height(28)
            .padding({ left: 6, right: 6 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.selectedDay = 0;
            })
        }
        Text('‹')
          .fontSize(18)
          .fontWeight(900)
          .fontColor(Theme.ink(this.uiMode))
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftMonth(-1);
            this.calExpanded = true;
          })
        Text(`${this.calYear} / ${this.calMonth}`)
          .fontSize(13)
          .fontWeight(900)
          .fontColor(Theme.ink(this.uiMode))
          .width(80)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.calExpanded = !this.calExpanded;
          })
        Text('›')
          .fontSize(18)
          .fontWeight(900)
          .fontColor(Theme.ink(this.uiMode))
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftMonth(1);
            this.calExpanded = true;
          })
        if (this.selectedDay !== 0) {
          Text('回到今天')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ink(this.uiMode))
            .height(28)
            .padding({ left: 6, right: 6 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.backToToday();
            })
        }
        Text(this.calExpanded ? '收起日历' : '展开日历')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent(this.uiMode))
          .height(28)
          .padding({ left: 6, right: 6 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.calExpanded = !this.calExpanded;
          })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)

      if (this.calExpanded) {
        Row() {
          ForEach(['日', '一', '二', '三', '四', '五', '六'], (w: string) => {
            Text(w)
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.sub(this.uiMode))
              .width('14.28%')
              .textAlign(TextAlign.Center)
          }, (w: string) => `week-${w}`)
        }
        .width('100%')
        .padding({ bottom: 2 })
        .border({
          width: { bottom: StyleConstants.HAIRLINE_HEIGHT },
          color: Theme.rule(this.uiMode)
        })

        Column() {
          ForEach(this.calendarRows(), (row: number[], ri: number) => {
            Row() {
              ForEach(row, (day: number, ci: number) => {
                this.DayCell(day)
              }, (day: number, ci: number) => `${ri}-${ci}-${day}`)
            }
            .width('100%')
          }, (row: number[], ri: number) => `row-${ri}`)
        }
        .width('100%')

        Text('有提醒的日期带一个点；点某天只看那天的安排')
          .fontSize(9)
          .fontColor(Theme.sub(this.uiMode))
          .opacity(0.8)
      }
    }
    .width('100%')
    .padding({ top: StyleConstants.SPACE_XS, bottom: StyleConstants.SPACE_SM })
    .border({
      width: { bottom: StyleConstants.HAIRLINE_HEIGHT },
      color: Theme.rule(this.uiMode)
    })
    .margin({ bottom: StyleConstants.SPACE_SM })
  }

  @Builder
  CalendarDayList() {
    Column({ space: StyleConstants.SPACE_MD }) {
      if (this.selectedDay === 0) {
        Text('选择一个日期')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
          .letterSpacing(1)
      } else {
        // 日期头条：巨大的日数 + 年月与星期
        Row() {
          Text(`${this.selectedDay}`)
            .fontSize(64)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
          Column({ space: 2 }) {
            Text(`${this.calYear} / ${this.calMonth}`)
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text(this.uiMode))
              .letterSpacing(1)
            Text(this.weekdayOf(this.selectedDay))
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontColor(Theme.sub(this.uiMode))
              .letterSpacing(1)
          }
          .alignItems(HorizontalAlign.Start)
          .margin({
            left: StyleConstants.SPACE_SM,
            bottom: StyleConstants.SPACE_SM
          })
          Blank()
          Text(`${this.itemsOnDate(this.selectedDay).length} 条`)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Column()
          .width('100%')
          .height(StyleConstants.RULE_HEAVY)
          .backgroundColor(Theme.text(this.uiMode))

        if (this.itemsOnDate(this.selectedDay).length === 0) {
          Text('这一天没有提醒')
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontColor(Theme.sub(this.uiMode))
            .padding({
              top: StyleConstants.SPACE_MD,
              bottom: StyleConstants.SPACE_MD
            })
        } else {
          Column() {
            ForEach(this.itemsOnDate(this.selectedDay), (item: ReminderCardData, index: number) => {
              this.ScheduleEntry(item, index === 0 && !item.isCompleted(), false, index)
            }, (item: ReminderCardData, index: number) => `${this.storeVersion}-${item.renderKey()}-${index}`)
          }
          .width('100%')
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_LG })
  }

  goDetail(item: ReminderCardData): void {
    this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_DETAIL, new ReminderDetailNavParam(item));
  }
}
