import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderDetailNavParam, ReminderEditNavParam } from '../common/RouterConstants';
import { MockReminderData, ReminderGroupData } from '../common/MockReminderData';
import { UiReminderStore } from '../common/UiReminderStore';
import { ReminderCardData, ReminderCard, SlipRole } from '../components/ReminderCard';
import { SettingsGear } from '../components/SettingsGear';
import { EmptyState } from '../components/EmptyState';

/**
 * 全部提醒页 —— 报纸的栏目索引。
 *
 * 与首页（视觉个性）分工不同：本页强调查找效率。
 * 用粗黑栏目标题 + 粗细分隔线 + 宽松文字行组织，而不是重复首页的拼贴效果。
 */
@Component
export struct ReminderListPage {
  pathStack: NavPathStack = new NavPathStack();
  groups: ReminderGroupData[] = MockReminderData.ALL_GROUPS;
  // 编辑页保存后由 AppStorage 通知刷新；按 id 用最新记录替换分组里的旧对象
  // 版本号变化 → 重渲染 → 从 UI 数据源读取最新记录
  @StorageLink('uiReminderVersion') storeVersion: number = 0;
  /** 'index' 索引视图 / 'calendar' 日历视图 */
  @State viewMode: string = 'index';
  @State calYear: number = 0;
  @State calMonth: number = 0;
  @State selectedDay: number = 0;

  aboutToAppear(): void {
    const now: Date = new Date();
    this.calYear = now.getFullYear();
    this.calMonth = now.getMonth() + 1;
  }

  /** 所有提醒：Mock 分组 + 数据源里新增的条目，按 id 去重 */
  private allReminders(): ReminderCardData[] {
    const out: ReminderCardData[] = [];
    const seen: string[] = [];
    for (let g = 0; g < this.groups.length; g++) {
      const group: ReminderGroupData = this.groups[g];
      for (let i = 0; i < group.items.length; i++) {
        const item: ReminderCardData = this.resolve(group.items[i]);
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

  /** 日历选中日的版面角色：与首页同一套语言 */
  private dayRole(item: ReminderCardData, index: number): string {
    if (item.isCompleted()) {
      return SlipRole.ARCHIVE;
    }
    if (index === 0) {
      return SlipRole.LEAD;
    }
    if (item.isLocationOnly()) {
      return SlipRole.FIELD;
    }
    return SlipRole.EDITORIAL;
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
      resolved.push(this.resolve(group.items[i]));
    }
    return this.sortItems(resolved);
  }

  /**
   * 实际渲染用的分组条目。
   * 今日组会追加数据源里「不属于任何 Mock 分组」的新建提醒，
   * 否则新建的提醒永远不会出现在全部页。
   */
  private liveGroupItems(group: ReminderGroupData, groupIndex: number): ReminderCardData[] {
    const base: ReminderCardData[] = this.sortedGroupItems(group);
    if (groupIndex !== 0) {
      return base;
    }
    const known: string[] = [];
    for (let g = 0; g < this.groups.length; g++) {
      for (let i = 0; i < this.groups[g].items.length; i++) {
        known.push(this.groups[g].items[i].id);
      }
    }
    const extra: ReminderCardData[] = [];
    const storeItems: ReminderCardData[] = UiReminderStore.getActive();
    for (let i = 0; i < storeItems.length; i++) {
      if (known.indexOf(storeItems[i].id) < 0) {
        extra.push(storeItems[i]);
      }
    }
    return this.sortItems(base.concat(extra));
  }

  /** 索引页的版面角色：只突出今日第一条，其余用无纸面文字栏，地点用情境色块。 */
  private roleOf(item: ReminderCardData, groupIndex: number, itemIndex: number): string {
    if (groupIndex === 0 && itemIndex === 0) {
      return SlipRole.LEAD;
    }
    if (item.hasLocation()) {
      return SlipRole.FIELD;
    }
    return SlipRole.EDITORIAL;
  }

  build() {
    Scroll() {
      Column() {
        this.HeaderBlock()
        if (this.viewMode === 'index') {
          this.GroupListBlock()
          this.PlacesBlock()
        } else {
          this.CalendarBlock()
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
  }

  @Builder
  NewEntryTag() {
    Row({ space: StyleConstants.SPACE_XS }) {
      Text('+')
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(900)
        .fontColor($r('app.color.text_primary'))
      Text('新建')
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
    }
    .height(StyleConstants.TOUCH_TARGET_MIN)
    .padding({
      left: StyleConstants.SPACE_LG,
      right: StyleConstants.SPACE_LG
    })
    .backgroundColor($r('app.color.accent_primary'))
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.pathStack.pushPathByName(RouterConstants.PAGE_REMINDER_EDIT,
        new ReminderEditNavParam(RouterConstants.EDIT_MODE_CREATE));
    })
  }

  @Builder
  HeaderBlock() {
    Column() {
      Row({ space: StyleConstants.SPACE_SM }) {
        Text('INDEX')
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
        // 设置不再是底部 Tab，索引页同样提供入口
        SettingsGear({
          onTap: () => {
            this.pathStack.pushPathByName(RouterConstants.PAGE_SETTINGS, '');
          }
        })
      }
      .width('100%')
      .height(StyleConstants.TOUCH_TARGET_MIN)
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor($r('app.color.text_primary'))

      Row({ space: StyleConstants.SPACE_MD }) {
        Column({ space: StyleConstants.SPACE_XS }) {
          Text('全部提醒')
            .fontSize(StyleConstants.FONT_DISPLAY)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Text('按日期编排的提醒索引')
            .fontSize(StyleConstants.FONT_CAPTION)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.NewEntryTag()
      }
      .width('100%')
      .margin({ top: StyleConstants.SPACE_MD, bottom: StyleConstants.SPACE_SM })

      Column()
        .width('100%')
        .height(StyleConstants.HAIRLINE_HEIGHT)
        .backgroundColor($r('app.color.accent_secondary'))

      Row({ space: StyleConstants.SPACE_XS }) {
        Blank()
        Text(this.viewMode === 'index' ? '日历视图' : '返回索引')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.detail_ink'))
          .decoration({ type: TextDecorationType.Underline })
        Text(this.viewMode === 'index' ? '→' : '←')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.detail_ink'))
      }
      .width('100%')
      .height(StyleConstants.TOUCH_TARGET_MIN)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.viewMode = this.viewMode === 'index' ? 'calendar' : 'index';
        this.selectedDay = 0;
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: StyleConstants.SPACE_LG })
  }

  @Builder
  GroupHeader(group: ReminderGroupData, groupIndex: number) {
    Column() {
      Row({ space: StyleConstants.SPACE_SM }) {
        Text(group.groupOverline)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_vermilion'))
          .letterSpacing(2)
        Text(group.groupLabel)
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`${this.liveGroupItems(group, groupIndex).length}`)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: StyleConstants.SPACE_XS })

      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: StyleConstants.SPACE_SM })
  }

  @Builder
  GroupListBlock() {
    Column({ space: StyleConstants.SPACE_SECTION }) {
      ForEach(this.groups, (group: ReminderGroupData, groupIndex: number) => {
        Column() {
          this.GroupHeader(group, groupIndex)
          ForEach(this.liveGroupItems(group, groupIndex), (item: ReminderCardData, itemIndex: number) => {
            ReminderCard({
              data: item,
              role: this.roleOf(item, groupIndex, itemIndex),
              tagTone: groupIndex * 3 + itemIndex,
              dateLabel: this.dateLabelOf(item),
              onCardClick: () => {
                this.goDetail(item);
              }
            })
          }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
        }
        .width('100%')
      }, (group: ReminderGroupData) => group.groupOverline)
    }
    .width('100%')
  }

  @Builder
  PlacesBlock() {
    Column() {
      Row({ space: StyleConstants.SPACE_SM }) {
        Text('PLACES')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_sage'))
          .letterSpacing(2)
        Text('地点索引')
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: StyleConstants.SPACE_XS })

      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))
        .margin({ bottom: StyleConstants.SPACE_SM })

      EmptyState({
        title: '地点提醒（占位）',
        subtitle: '基于位置的提醒将在这里展示，本阶段仅作视觉占位'
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  DayCell(day: number) {
    if (day === 0) {
      Column()
        .width('14.28%')
        .height(52)
    } else {
      Column({ space: 4 }) {
        Text(`${day}`)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(this.selectedDay === day || this.isToday(day) ? 900 : FontWeight.Medium)
          .fontColor(this.selectedDay === day
            ? $r('app.color.surface_primary')
            : (this.isToday(day) ? $r('app.color.detail_ink') : $r('app.color.text_primary')))
        if (this.hasReminder(day)) {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.selectedDay === day
              ? $r('app.color.surface_primary')
              : $r('app.color.detail_ink'))
        } else {
          Column()
            .width(4)
            .height(4)
        }
      }
      .width('14.28%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.selectedDay === day ? $r('app.color.text_primary') : Color.Transparent)
      .onClick(() => {
        this.selectedDay = day;
      })
    }
  }

  @Builder
  CalendarBlock() {
    Column({ space: StyleConstants.SPACE_MD }) {
      Row() {
        Text('‹')
          .fontSize(22)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .width(StyleConstants.TOUCH_TARGET_MIN)
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftMonth(-1);
          })
        Blank()
        Column({ space: 2 }) {
          Text(`${this.calYear} / ${this.calMonth}`)
            .fontSize(StyleConstants.FONT_TITLE)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Text('MONTH')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(2)
        }
        .alignItems(HorizontalAlign.Center)
        Blank()
        Text('›')
          .fontSize(22)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .width(StyleConstants.TOUCH_TARGET_MIN)
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.shiftMonth(1);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (w: string) => {
          Text(w)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .width('14.28%')
            .textAlign(TextAlign.Center)
        }, (w: string) => `week-${w}`)
      }
      .width('100%')

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

      Text('有提醒的日期带一个红点；无固定时间的提醒不进入日历')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontColor($r('app.color.text_secondary'))
        .opacity(0.8)
    }
    .width('100%')
    .padding(StyleConstants.SPACE_MD)
    .backgroundColor($r('app.color.surface_primary'))
    .borderRadius({
      topLeft: 0,
      topRight: 18,
      bottomLeft: 0,
      bottomRight: 0
    })
  }

  @Builder
  CalendarDayList() {
    Column({ space: StyleConstants.SPACE_MD }) {
      if (this.selectedDay === 0) {
        Text('选择一个日期')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(1)
      } else {
        // 日期头条：巨大的日数 + 年月与星期
        Row() {
          Text(`${this.selectedDay}`)
            .fontSize(64)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Column({ space: 2 }) {
            Text(`${this.calYear} / ${this.calMonth}`)
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .letterSpacing(1)
            Text(this.weekdayOf(this.selectedDay))
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontColor($r('app.color.text_secondary'))
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
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Column()
          .width('100%')
          .height(StyleConstants.RULE_HEAVY)
          .backgroundColor($r('app.color.text_primary'))

        if (this.itemsOnDate(this.selectedDay).length === 0) {
          Text('这一天没有提醒')
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontColor($r('app.color.text_secondary'))
            .padding({
              top: StyleConstants.SPACE_MD,
              bottom: StyleConstants.SPACE_MD
            })
        } else {
          ForEach(this.itemsOnDate(this.selectedDay), (item: ReminderCardData, index: number) => {
            ReminderCard({
              data: item,
              role: this.dayRole(item, index),
              indexLabel: index === 0 ? 'No. 01' : '',
              entryNo: index < 9 ? `0${index + 1}` : `${index + 1}`,
              tagTone: index,
              onCardClick: () => {
                this.goDetail(item);
              }
            })
          }, (item: ReminderCardData) => `${this.storeVersion}-${item.renderKey()}`)
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
