import { StyleConstants } from '../common/StyleConstants';
import { UiReminderStatus, UiTriggerType, UiReminderSource, UiLocationTriggerMode } from '../common/UiReminderSemantics';

function formatClockText(epochMs: number | undefined): string {
  if (epochMs === undefined) {
    return '时间待定';
  }
  if (epochMs <= 0) {
    return '时间待定';
  }
  const d: Date = new Date(epochMs);
  const h: number = d.getHours();
  const m: number = d.getMinutes();
  const hText: string = h < 10 ? `0${h}` : `${h}`;
  const mText: string = m < 10 ? `0${m}` : `${m}`;
  return `${hText}:${mText}`;
}

/**
 * 提醒展示用占位视图模型（非团队公共 Reminder 数据模型）。
 * 字段语义对齐《ContextCue 公共架构与 AI 模块开发规范 v1.0》§5.2；
 * 展示文案全部由这些字段派生，本文件不改变任何字段语义。
 */
export class ReminderCardData {
  readonly id: string;
  readonly content: string;
  readonly triggerType: string;
  readonly source: string;
  readonly status: string;
  readonly triggerTime?: number;
  readonly sceneId?: string;
  readonly sceneName?: string;
  readonly locationTriggerMode?: string;

  constructor(id: string, content: string, triggerType: string, source: string, status: string,
    triggerTime?: number, sceneId?: string, sceneName?: string, locationTriggerMode?: string) {
    this.id = id;
    this.content = content;
    this.triggerType = triggerType;
    this.source = source;
    this.status = status;
    this.triggerTime = triggerTime;
    this.sceneId = sceneId;
    this.sceneName = sceneName;
    this.locationTriggerMode = locationTriggerMode;
  }

  primaryText(): string {
    if (this.triggerType === UiTriggerType.LOCATION) {
      return this.sceneName ? this.sceneName : '地点待定';
    }
    return formatClockText(this.triggerTime);
  }

  timeText(): string {
    if (this.triggerType === UiTriggerType.LOCATION) {
      return '—';
    }
    return formatClockText(this.triggerTime);
  }

  typeText(): string {
    if (this.triggerType === UiTriggerType.BOTH) {
      return '时间+地点';
    }
    if (this.triggerType === UiTriggerType.LOCATION) {
      return '地点提醒';
    }
    return '时间提醒';
  }

  sourceText(): string {
    return this.source === UiReminderSource.AI ? 'AI 解析' : '手动创建';
  }

  statusText(): string {
    if (this.status === UiReminderStatus.TRIGGERED) {
      return '已触发';
    }
    if (this.status === UiReminderStatus.COMPLETED) {
      return '已完成';
    }
    if (this.status === UiReminderStatus.DISABLED) {
      return '已禁用';
    }
    return '进行中';
  }

  locationText(): string {
    const scene: string = this.sceneName ? this.sceneName : '';
    if (scene === '') {
      return '未设置';
    }
    const mode: string = this.locationTriggerMode === UiLocationTriggerMode.EXIT ? '离开时' : '进入时';
    return `${scene}（${mode}）`;
  }

  /** 触发方式文案，由真实 locationTriggerMode 派生（V1 仅 ENTER 可用）。 */
  locationModeText(): string {
    return this.locationTriggerMode === UiLocationTriggerMode.EXIT ? '离开场景时触发' : '进入场景时触发';
  }

  isCompleted(): boolean {
    return this.status === UiReminderStatus.COMPLETED;
  }

  isLocationOnly(): boolean {
    return this.triggerType === UiTriggerType.LOCATION;
  }

  isDualFocus(): boolean {
    return this.triggerType === UiTriggerType.BOTH;
  }

  hasLocation(): boolean {
    return this.triggerType !== UiTriggerType.TIME;
  }

  /** ForEach 渲染键：时间/状态/内容变化时强制重建，避免复用旧组件。 */
  renderKey(): string {
    const t: string = this.triggerTime === undefined ? 'x' : `${this.triggerTime}`;
    return `${this.id}-${t}-${this.status}-${this.content}`;
  }
}

/** 兼容旧的形态参数（外部若仍按 HERO / COMPACT 调用，会映射到 LEAD / EDITORIAL）。 */
export class ReminderCardVariant {
  static readonly HERO: string = 'hero';
  static readonly COMPACT: string = 'compact';
}

/**
 * 拼贴版面角色 —— 布局角色，与业务枚举的颜色分配无关。
 *   LEAD      头版：炭黑块、56fp 时间、右侧出血
 *   EDITORIAL 无纸面：时间挂在左侧栅格，栏线有意中断
 *   FIELD     情境：鼠尾草色块 + 奶油纸片上下叠压
 *   SLIP      窄纸条：时间与地点两级，带底纸与切角
 *   ARCHIVE   封存：无纸面，朱红标记 + 降权文字
 */
export class SlipRole {
  static readonly LEAD: string = 'lead';
  static readonly EDITORIAL: string = 'editorial';
  static readonly FIELD: string = 'field';
  static readonly ARCHIVE: string = 'archive';
}

@Component
export struct ReminderCard {
  data: ReminderCardData = new ReminderCardData('', '', UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE);
  variant: string = ReminderCardVariant.HERO;
  role: string = '';
  isNext: boolean = false;
  indexLabel: string = '';
  entryNo: string = '';
  tagTone: number = 0;
  dateLabel: string = '';
  onCardClick: () => void = () => {};

  private resolvedRole(): string {
    if (this.role !== '') {
      return this.role;
    }
    return this.variant === ReminderCardVariant.COMPACT ? SlipRole.EDITORIAL : SlipRole.LEAD;
  }

  /** 复古套色轮换：按行变化，而不是按业务类型堆同一个红色 */
  private tagColor(): Resource {
    const tones: Resource[] = [
      $r('app.color.accent_vermilion'),
      $r('app.color.brand_primary'),
      $r('app.color.accent_burgundy'),
      $r('app.color.accent_olive'),
      $r('app.color.accent_terracotta')
    ];
    return tones[this.tagTone % tones.length];
  }

  build() {
    if (this.resolvedRole() === SlipRole.LEAD) {
      this.LeadStory()
    } else if (this.resolvedRole() === SlipRole.FIELD) {
      this.FieldNote()
    } else if (this.resolvedRole() === SlipRole.ARCHIVE) {
      this.ArchiveRecord()
    } else {
      this.EditorialRow()
    }
  }

  // ---------- 1. Lead Story：炭黑头版，右侧出血 ----------

  @Builder
  LeadStory() {
    Column({ space: StyleConstants.SPACE_SM }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        // 朱红套印标记（色块，不承载小字）
        Column()
          .width(3)
          .height(18)
          .backgroundColor($r('app.color.accent_vermilion'))
        Text(this.indexLabel)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.surface_primary'))
          .opacity(0.65)
          .letterSpacing(2)
        Blank()
        if (this.dateLabel !== '') {
          Text(this.dateLabel)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.surface_primary'))
            .opacity(0.65)
            .letterSpacing(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.data.primaryText())
        .fontSize(this.data.isLocationOnly()
          ? StyleConstants.FONT_TITLE_LG
          : StyleConstants.FONT_HEADLINE_TIME)
        .fontWeight(900)
        .fontColor($r('app.color.surface_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.data.content)
        .fontSize(StyleConstants.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.surface_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.data.isDualFocus()) {
        Row({ space: StyleConstants.SPACE_SM }) {
          Column()
            .width(8)
            .height(8)
            .backgroundColor($r('app.color.accent_sage'))
          Text(this.data.locationText())
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.surface_primary'))
            .opacity(0.82)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(StyleConstants.SPACE_LG)
    .backgroundColor($r('app.color.text_primary'))
    // 视觉上向右出血到屏幕边缘（offset 不改布局，不会撑破滚动区）
    .offset({ x: StyleConstants.PAGE_PADDING_H })
    .onClick(() => this.onCardClick())
  }

  // ---------- 2. Editorial Brief：窄长色标 + 大号时间 + 开放式正文 ----------

  @Builder
  EditorialRow() {
    Row({ space: StyleConstants.SPACE_MD }) {
      // 窄长色标：编号压在上面，颜色按情境区分（时间=朱红 / 时间+地点=鼠尾草）
      Column() {
        Text(this.entryNo)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(900)
          .fontColor($r('app.color.surface_primary'))
          .letterSpacing(1)
      }
      .width(26)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.tagColor())

      Column({ space: StyleConstants.SPACE_XS }) {
        Row({ space: StyleConstants.SPACE_SM }) {
          Text(this.data.primaryText())
            .fontSize(StyleConstants.FONT_EDITORIAL_TIME + 14)
            .minFontSize(34)
            .maxFontSize(StyleConstants.FONT_EDITORIAL_TIME + 14)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
            .letterSpacing(-1)
            .maxLines(1)
          Column()
            .width(StyleConstants.SPACE_XL)
            .height(StyleConstants.RULE_HEAVY)
            .backgroundColor($r('app.color.text_primary'))
          Blank()
          if (this.dateLabel !== '') {
            Text(this.dateLabel)
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing(1)
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.data.content)
          .fontSize(StyleConstants.FONT_TITLE + 4)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(32)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.data.isDualFocus()) {
          Row({ space: StyleConstants.SPACE_XS }) {
            Column()
              .width(6)
              .height(6)
              .backgroundColor($r('app.color.accent_sage'))
            Text(this.data.locationText())
              .fontSize(StyleConstants.FONT_BODY_SM)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        Column()
          .width(StyleConstants.RULE_SHORT_WIDTH)
          .height(StyleConstants.RULE_MEDIUM)
          .backgroundColor($r('app.color.text_primary'))
          .margin({ top: StyleConstants.SPACE_XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      left: StyleConstants.SPACE_LG,
      right: StyleConstants.SPACE_LG,
      top: StyleConstants.SPACE_MD,
      bottom: StyleConstants.SPACE_LG
    })
    .onClick(() => this.onCardClick())
  }

  // ---------- 3. Field Note：情境色块 + 开放式正文（无纸面容器） ----------

  @Builder
  FieldNote() {
    Row({ space: StyleConstants.SPACE_LG }) {
      // 真实的情境色域：只放地名，文字足够大以保证对比度
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(this.data.primaryText())
          .fontSize(StyleConstants.FONT_FIELD_NAME)
          .fontWeight(900)
          .fontColor($r('app.color.surface_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('44%')
      .alignItems(HorizontalAlign.Start)
      .padding(StyleConstants.SPACE_MD)
      .backgroundColor($r('app.color.accent_sage'))
      // 圆角必须远小于色块高度，否则上下圆弧会在边缘重叠，滚动时出现折角伪影
      .borderRadius({
        topLeft: 0,
        topRight: 10,
        bottomLeft: 0,
        bottomRight: 3
      })

      // 正文直接排在编辑底色上，不再套第二层纸
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(this.data.content)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.data.locationModeText())
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.onCardClick())
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      left: StyleConstants.SLIP_INDENT,
      top: StyleConstants.SPACE_XS,
      bottom: StyleConstants.SPACE_XS
    })
  }

  // ---------- 5. Archive：封存档案，无纸面 ----------

  @Builder
  ArchiveRecord() {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column().width(StyleConstants.SLIP_INDENT_ARCHIVE)
      Column({ space: StyleConstants.SPACE_XS }) {
        Row({ space: StyleConstants.SPACE_XS }) {
          Column()
            .width(4)
            .height(4)
            .backgroundColor($r('app.color.accent_vermilion'))
          Text('SEALED')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(2)
          Blank()
          Text('已完成')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.data.primaryText())
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.data.content)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .decoration({ type: TextDecorationType.LineThrough })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Column()
          .width(StyleConstants.RULE_SHORT_WIDTH)
          .height(StyleConstants.HAIRLINE_HEIGHT)
          .backgroundColor($r('app.color.border_subtle'))
          .margin({ top: StyleConstants.SPACE_XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({
        top: StyleConstants.SPACE_MD,
        bottom: StyleConstants.SPACE_MD
      })
      .onClick(() => this.onCardClick())
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
