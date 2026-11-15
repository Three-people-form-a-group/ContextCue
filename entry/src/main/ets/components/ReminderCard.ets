import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { Reminder } from '../model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../model/ReminderEnums';
import {
  isDualFocus,
  isLocationOnly,
  reminderLocationModeText,
  reminderLocationText,
  reminderPrimaryText
} from '../common/ReminderView';

/** 兼容旧的形态参数（外部若仍按 HERO / COMPACT 调用，会映射到 LEAD / EDITORIAL）。 */
export class ReminderCardVariant {
  static readonly HERO: string = 'hero';
  static readonly COMPACT: string = 'compact';
}

/**
 * 拼贴版面角色 —— 布局角色，与业务枚举的颜色分配无关。
 *   LEAD      头条：浅纸、刊线、大号时间
 *   EDITORIAL 无纸面：时间挂在左侧栅格，栏线有意中断
 *   FIELD     情境：地名边栏 + 开放式正文
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
  data: Reminder = {
    id: '', content: '', triggerType: TriggerType.TIME,
    status: ReminderStatus.ACTIVE, source: ReminderSource.MANUAL, createdAt: 0
  };
  variant: string = ReminderCardVariant.HERO;
  role: string = '';
  isNext: boolean = false;
  // 用 @Prop：切换极简/手账时要能把编号清空，普通成员只在创建时赋值
  @Prop indexLabel: string = '';
  @Prop entryNo: string = '';
  dateLabel: string = '';
  onCardClick: () => void = () => {};
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  private resolvedRole(): string {
    if (this.role !== '') {
      return this.role;
    }
    return this.variant === ReminderCardVariant.COMPACT ? SlipRole.EDITORIAL : SlipRole.LEAD;
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

  /** 首条事项用整张裁边剪报承载，编号、时间和正文共享同一栏线。 */
  @Builder
  LeadStory() {
    Column({ space: 9 }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        if (this.uiMode === UiMode.JOURNAL && this.indexLabel !== '') {
          Text(this.indexLabel)
            .fontSize(11)
            .fontWeight(900)
            .fontColor($r('app.color.ink_on_paper'))
            .letterSpacing(0.8)
        }
        if (this.dateLabel !== '') {
          Text(this.dateLabel)
            .fontSize(11)
            .fontColor($r('app.color.ink_on_paper'))
        }
      }
      .width('100%')
      .padding({ bottom: 6 })
      .border({ width: { bottom: 1 }, color: Theme.rule(this.uiMode) })

      Row({ space: 10 }) {
        Text(reminderPrimaryText(this.data))
          .fontSize(isLocationOnly(this.data) ? 19 : 32)
          .minFontSize(16)
          .fontFamily(isLocationOnly(this.data) ? 'sans-serif' : 'serif')
          .fontWeight(900)
          .fontColor(Theme.accent(this.uiMode))
          .width(85)
          .maxLines(isLocationOnly(this.data) ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Column({ space: 5 }) {
          Text(this.data.content)
            .fontSize(21)
            .fontWeight(900)
            .fontColor($r('app.color.ink_on_paper'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (isDualFocus(this.data)) {
            Text(reminderLocationText(this.data))
              .fontSize(12)
              .fontColor($r('app.color.ink_on_paper'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 10 })
        .border({ width: { left: 1 }, color: Theme.rule(this.uiMode) })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 13, right: 13, top: 15, bottom: 20 })
    .backgroundColor($r('app.color.archive_paper'))
    .backgroundImage($r('app.media.torn_note_cream'))
    .backgroundImageSize({ width: '100%', height: '100%' })
    .border({ width: { left: 4 }, color: $r('app.color.accent_coral') })
    .onClick(() => this.onCardClick())
  }

  // ---------- 2. Editorial Brief：印刷编号 + 大号时间 + 开放式正文 ----------

  @Builder
  EditorialRow() {
    Row({ space: StyleConstants.SPACE_MD }) {
      // 编号是页边索引，给时间和正文让出视觉重量；极简模式没有编号这一栏
      if (this.uiMode === UiMode.JOURNAL) {
        Column() {
          Text(this.entryNo)
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontWeight(900)
            .fontColor(Theme.ink(this.uiMode))
            .letterSpacing(1)
        }
        .width(26)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .border({ width: { bottom: 1 }, color: $r('app.color.accent_sky') })
      }

      Column({ space: StyleConstants.SPACE_XS }) {
        Row({ space: StyleConstants.SPACE_SM }) {
          Text(reminderPrimaryText(this.data))
            .fontSize(StyleConstants.FONT_EDITORIAL_TIME + 14)
            .minFontSize(34)
            .maxFontSize(StyleConstants.FONT_EDITORIAL_TIME + 14)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
            .letterSpacing(-1)
            .maxLines(1)
          Column()
            .width(StyleConstants.SPACE_XL)
            .height(StyleConstants.RULE_HEAVY)
            .backgroundColor(Theme.text(this.uiMode))
          Blank()
          if (this.dateLabel !== '') {
            Text(this.dateLabel)
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.sub(this.uiMode))
              .letterSpacing(1)
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.data.content)
          .fontSize(StyleConstants.FONT_TITLE + 4)
          .fontWeight(900)
          .fontColor(Theme.text(this.uiMode))
          .lineHeight(32)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (isDualFocus(this.data)) {
          Row({ space: StyleConstants.SPACE_XS }) {
            Column()
              .width(6)
              .height(6)
              .backgroundColor($r('app.color.accent_sage'))
            Text(reminderLocationText(this.data))
              .fontSize(StyleConstants.FONT_BODY_SM)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text(this.uiMode))
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
          .backgroundColor(Theme.text(this.uiMode))
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

  // ---------- 3. Field Note：索引栏 + 开放式正文 ----------

  @Builder
  FieldNote() {
    Row({ space: StyleConstants.SPACE_LG }) {
      // 地名和触发条件排成边栏。
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(reminderPrimaryText(this.data))
          .fontSize(StyleConstants.FONT_FIELD_NAME)
          .fontWeight(900)
          .fontColor(Theme.ink(this.uiMode))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('34%')
      .alignItems(HorizontalAlign.Start)
      .padding({ right: StyleConstants.SPACE_SM })
      .border({ width: { right: 1 }, color: Theme.rule(this.uiMode) })

      // 正文直接排在编辑底色上，不再套第二层纸
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(this.data.content)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(reminderLocationModeText(this.data))
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.sub(this.uiMode))
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
            .backgroundColor(Theme.rule(this.uiMode))
          Text('已完成')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.sub(this.uiMode))
            .letterSpacing(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(reminderPrimaryText(this.data))
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor(Theme.sub(this.uiMode))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.data.content)
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.sub(this.uiMode))
          .decoration({ type: TextDecorationType.LineThrough })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Column()
          .width(StyleConstants.RULE_SHORT_WIDTH)
          .height(StyleConstants.HAIRLINE_HEIGHT)
          .backgroundColor(Theme.rule(this.uiMode))
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
