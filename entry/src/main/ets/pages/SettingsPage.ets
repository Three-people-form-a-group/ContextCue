import { StyleConstants } from '../common/StyleConstants';
import { TopBar } from '../components/TopBar';

/**
 * 设置页 —— 整份报纸的「出版说明」（COLOPHON）。
 *
 * 不再使用纸片容器：层级完全由「悬挂大编号 + 栏目标题 + 粗细线 + 悬挂行」构成。
 * 编号以低不透明度压在左边距，正文行与标题对齐，形成真正的编辑式两栏结构。
 */

@Component
struct SettingToggleRow {
  @Prop label: string = '';
  @Prop desc: string = '';
  @Prop initialOn: boolean = false;
  @State isOn: boolean = false;

  aboutToAppear(): void {
    this.isOn = this.initialOn;
  }

  build() {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        if (this.desc !== '') {
          Text(this.desc)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .onChange((value: boolean) => {
          this.isOn = value;
        })
    }
    .width('100%')
    .padding({
      top: StyleConstants.SPACE_MD,
      bottom: StyleConstants.SPACE_MD
    })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
struct SettingValueRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop desc: string = '';

  build() {
    Row({ space: StyleConstants.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        if (this.desc !== '') {
          Text(this.desc)
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.value)
        .fontSize(StyleConstants.FONT_BODY)
        .fontWeight(900)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
    }
    .width('100%')
    .padding({
      top: StyleConstants.SPACE_MD,
      bottom: StyleConstants.SPACE_MD
    })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct SettingsPage {
  pathStack: NavPathStack = new NavPathStack();

  build() {
    Column() {
      TopBar({
        title: '出版说明',
        showBack: true,
        onBack: () => {
          this.pathStack.pop();
        }
      })
      Scroll() {
        Column() {
          this.MastheadBlock()
          this.ReminderSection()
          this.ContextSection()
          this.AiSection()
          this.AboutSection()
          this.FooterBlock()
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
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }

  @Builder
  MastheadBlock() {
    Column() {
      Row() {
        Text('COLOPHON')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(2)
        Blank()
        Text('ISSUE 017')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .letterSpacing(2)
      }
      .width('100%')
      .height(20)
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor($r('app.color.text_primary'))

      Row() {
        Text('出版说明')
          .fontSize(StyleConstants.FONT_DISPLAY)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Column()
          .width(36)
          .height(4)
          .backgroundColor($r('app.color.accent_vermilion'))
          .margin({ top: StyleConstants.SPACE_XL })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: StyleConstants.SPACE_SM })

      Text('ContextCue · 时间公报')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(1)
        .margin({ top: StyleConstants.SPACE_XS })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 悬挂大编号 + 栏目标题 + 中粗线；行内容与标题左对齐 */
  @Builder
  SectionHeader(no: string, title: string) {
    Row({ space: StyleConstants.SPACE_MD }) {
      Text(no)
        .fontSize(StyleConstants.FONT_DISPLAY)
        .fontWeight(900)
        .fontColor($r('app.color.text_primary'))
        .opacity(0.16)
        .width(48)
      Column({ space: StyleConstants.SPACE_XS }) {
        Text(title)
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Column()
          .width('100%')
          .height(StyleConstants.RULE_MEDIUM)
          .backgroundColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({
      top: StyleConstants.SPACE_SECTION,
      bottom: StyleConstants.SPACE_XS
    })
  }

  @Builder
  Rule() {
    Column()
      .width('100%')
      .height(StyleConstants.HAIRLINE_HEIGHT)
      .backgroundColor($r('app.color.border_subtle'))
  }

  @Builder
  ReminderSection() {
    Column() {
      this.SectionHeader('01', '提醒偏好')
      Column() {
        SettingToggleRow({
          label: '提醒通知',
          desc: '到点后通过系统通知提醒（占位开关）',
          initialOn: true
        })
        this.Rule()
        SettingValueRow({
          label: '免打扰时段',
          desc: '该时段内不发送通知（占位）',
          value: '22:00 – 07:00'
        })
      }
      .width('100%')
      .padding({ left: 60 })
    }
    .width('100%')
  }

  @Builder
  ContextSection() {
    Column() {
      this.SectionHeader('02', '情境与权限')
      Column() {
        SettingValueRow({
          label: '地点权限',
          desc: '地点提醒需要定位权限（尚未接入）',
          value: '未请求'
        })
        this.Rule()
        SettingValueRow({
          label: '地点触发',
          desc: 'V1 仅支持进入场景时触发',
          value: 'ENTER'
        })
      }
      .width('100%')
      .padding({ left: 60 })
    }
    .width('100%')
  }

  @Builder
  AiSection() {
    Column() {
      this.SectionHeader('03', 'AI 与辅助')
      Column() {
        SettingToggleRow({
          label: '智能建议',
          desc: '根据自然语言生成时间与地点建议（占位开关）',
          initialOn: false
        })
      }
      .width('100%')
      .padding({ left: 60 })
    }
    .width('100%')
  }

  @Builder
  AboutSection() {
    Column() {
      this.SectionHeader('04', '关于 ContextCue')
      Column() {
        SettingValueRow({
          label: '版本',
          desc: '当前为 UI 骨架阶段',
          value: '0.1.0'
        })
        this.Rule()
        SettingValueRow({
          label: '设计语言',
          desc: '复古报纸 × 实验性编辑设计',
          value: 'Temporal Gazette'
        })
      }
      .width('100%')
      .padding({ left: 60 })
    }
    .width('100%')
  }

  @Builder
  FooterBlock() {
    Column({ space: StyleConstants.SPACE_XS }) {
      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))
        .margin({ bottom: StyleConstants.SPACE_MD })

      Text('CONTEXTCUE · THE DAILY GAZETTE')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(2)
      Text('由水獭编辑员整理 · 占位页面，暂无持久化设置')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontColor($r('app.color.text_secondary'))
        .opacity(0.8)
        .textAlign(TextAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SECTION })
  }
}
