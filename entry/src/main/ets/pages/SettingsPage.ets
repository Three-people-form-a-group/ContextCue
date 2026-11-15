import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { TopBar } from '../components/TopBar';
import { getAppServices } from '../app/AppServiceRegistry';
import { AppRuntimeMode } from '../app/AppServices';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { NotifyPref } from '../common/NotifyPref';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LOCAL_AI_CONFIG_FILENAME } from '../ai/provider/LocalAIConfigReader';
import { AiConfigSheet } from '../components/AiConfigSheet';
import { ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { CreateReminderInput } from '../model/CreateReminderInput';

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
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

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
            .fontColor(Theme.sub(this.uiMode))
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
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
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
            .fontColor(Theme.sub(this.uiMode))
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
  /** 作为底部 Tab 使用时隐藏返回按钮 */
  @Prop showBack: boolean = true;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  /** 系统通知是否已开启（提醒代理发布的前提） */
  @State notificationEnabled: boolean = true;
  /** 应用内「到点提醒」开关 */
  @State notifyOn: boolean = true;
  /** AI 配置弹层与当前是否已配置 */
  @State showAiConfig: boolean = false;
  @State aiConfigured: boolean = false;

  aboutToAppear(): void {
    this.notificationEnabled = notificationManager.isNotificationEnabledSync();
    this.notifyOn = NotifyPref.enabled();
    this.aiConfigured = this.aiConfigExists();
  }

  private aiConfigExists(): boolean {
    try {
      return fs.accessSync(`${getContext(this).filesDir}/${LOCAL_AI_CONFIG_FILENAME}`);
    } catch (_) {
      return false;
    }
  }

  /** 开关切换：关掉时清掉已排期的系统提醒；打开时补排现有待办 */
  private async toggleNotify(on: boolean): Promise<void> {
    if (!on) {
      this.notifyOn = false;
      await NotifyPref.save(getContext(this), false);
      try {
        await reminderAgentManager.cancelAllReminders();
      } catch (_) {
      }
      this.getUIContext().getPromptAction().showToast({ message: '已关闭到点提醒' });
      return;
    }
    // 打开前先确认系统通知权限
    this.notificationEnabled = notificationManager.isNotificationEnabledSync();
    if (!this.notificationEnabled) {
      await this.askNotification();
      this.notificationEnabled = notificationManager.isNotificationEnabledSync();
      if (!this.notificationEnabled) {
        this.notifyOn = false;
        this.getUIContext().getPromptAction().showToast({ message: '需要先允许 ContextCue 的通知' });
        return;
      }
    }
    this.notifyOn = true;
    await NotifyPref.save(getContext(this), true);
    await this.rescheduleActive();
    this.getUIContext().getPromptAction().showToast({ message: '已开启到点提醒' });
  }

  /** 重新把当前待办排进系统提醒代理（只排未来的时间提醒） */
  private async rescheduleActive(): Promise<void> {
    const services = getAppServices();
    const result = await services.reminderService.findAll();
    if (result.success && result.data !== undefined) {
      for (let i = 0; i < result.data.length; i++) {
        const r = result.data[i];
        if (r.status !== ReminderStatus.ACTIVE || r.triggerType === TriggerType.LOCATION ||
          r.triggerTime === undefined || r.triggerTime <= Date.now()) {
          continue;
        }
        const input: CreateReminderInput = {
          content: r.content,
          triggerType: r.triggerType,
          triggerTime: r.triggerTime,
          sceneId: r.sceneId,
          sceneName: r.sceneName,
          locationTriggerMode: r.locationTriggerMode,
          source: r.source
        };
        await services.reminderService.update(r.id, input);
      }
    }
    await services.timetableService.ensureUpcomingReminders();
  }

  /** 打开系统通知授权；回到设置页时再同步一次状态 */
  private async askNotification(): Promise<void> {
    if (this.notificationEnabled) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (_) {
    }
    this.notificationEnabled = notificationManager.isNotificationEnabledSync();
    if (this.notificationEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: '已开启通知' });
      return;
    }
    // 系统弹窗没能开启时，直接带用户到本应用的通知设置页
    try {
      await notificationManager.openNotificationSettings(context);
    } catch (_) {
    }
    this.getUIContext().getPromptAction().showToast({ message: '请在系统设置中允许 ContextCue 的通知' });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      TopBar({
        title: '设置',
        showBack: this.showBack,
        onBack: () => {
          this.pathStack.pop();
        }
      })
      Scroll() {
        Column() {
          this.MastheadBlock()
          this.ModeSection()
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
    .backgroundColor(Theme.bg(this.uiMode))

      if (this.showAiConfig) {
        AiConfigSheet({
          onClose: () => {
            this.showAiConfig = false;
            this.aiConfigured = this.aiConfigExists();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 界面模式：极简 / 手账 */
  @Builder
  ModeSection() {
    Column({ space: 8 }) {
      Row() {
        Text('界面模式')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
        Blank()
        Text(this.uiMode === UiMode.MINIMAL ? '极简' : '手账')
          .fontSize(11)
          .fontColor(Theme.sub(this.uiMode))
      }
      .width('100%')

      Row({ space: 8 }) {
        this.ModeOption('极简', UiMode.MINIMAL)
        this.ModeOption('手账', UiMode.JOURNAL)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  ModeOption(label: string, mode: string) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(900)
        .fontColor(this.uiMode === mode ? Theme.bg(this.uiMode) : Theme.text(this.uiMode))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.uiMode === mode ? Theme.text(this.uiMode) : Theme.surface(this.uiMode))
    .borderRadius({
      topLeft: 0,
      topRight: 10,
      bottomLeft: 0,
      bottomRight: 10
    })
    .border({
      width: this.uiMode === mode ? 0 : 1,
      color: Theme.rule(this.uiMode)
    })
    .onClick(() => {
      UiMode.setMode(getContext(this), mode);
    })
  }

  @Builder
  MastheadBlock() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Column()
          .width(8)
          .height(30)
          .backgroundColor(this.uiMode === UiMode.JOURNAL
            ? $r('app.color.accent_mint')
            : Theme.text(this.uiMode))
        Text('设置')
          .fontSize(30)
          .fontWeight(900)
          .fontColor(Theme.text(this.uiMode))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_HEAVY)
        .backgroundColor(Theme.text(this.uiMode))
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
        .opacity(0.18)
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
        Row({ space: StyleConstants.SPACE_MD }) {
          Column({ space: 2 }) {
            Text('到点提醒')
              .fontSize(StyleConstants.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.notifyOn
              ? (this.notificationEnabled
                ? '到点由系统提醒代理弹出通知'
                : '系统通知未开启：点这里去开启')
              : '已关闭：不会再排入系统提醒')
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontColor(!this.notifyOn || this.notificationEnabled
                ? Theme.sub(this.uiMode)
                : Theme.alert(this.uiMode))
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.notifyOn })
            .selectedColor(Theme.accent(this.uiMode))
            .onChange((isOn: boolean) => {
              this.toggleNotify(isOn);
            })
        }
        .width('100%')
        .padding({
          top: StyleConstants.SPACE_MD,
          bottom: StyleConstants.SPACE_MD
        })
        .alignItems(VerticalAlign.Center)

        if (this.notifyOn && !this.notificationEnabled) {
          Text('点此允许系统通知 ›')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.alert(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.askNotification();
            })
        }
        this.Rule()
        // 免打扰由系统统一管理，这里不再放一个不起作用的假设置
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
        Row({ space: StyleConstants.SPACE_MD }) {
          Column({ space: 2 }) {
            Text('AI 配置')
              .fontSize(StyleConstants.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.aiConfigured
              ? '已配置真实模型，重启应用后生效'
              : '未配置：使用示例数据，可在编辑台体验解析三态')
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontColor(Theme.sub(this.uiMode))
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.aiConfigured ? '修改 ›' : '去配置 ›')
            .fontSize(StyleConstants.FONT_BODY)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .maxLines(1)
        }
        .width('100%')
        .padding({
          top: StyleConstants.SPACE_MD,
          bottom: StyleConstants.SPACE_MD
        })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showAiConfig = true;
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
          desc: '已接入公共 ReminderService（开发组合）',
          value: '0.1.0'
        })
        SettingValueRow({
          label: '运行模式',
          desc: '提醒只保存在本次进程，重启会丢失；暂无自动触发与系统通知',
          value: this.runtimeModeLabel()
        })
      }
      .width('100%')
      .padding({ left: 60 })
    }
    .width('100%')
  }

  private runtimeModeLabel(): string {
    try {
      return getAppServices().mode === AppRuntimeMode.DEVELOPMENT ? '开发联调' : '集成';
    } catch (err) {
      return '未初始化';
    }
  }

  @Builder
  FooterBlock() {
    Column({ space: StyleConstants.SPACE_XS }) {
      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))
        .margin({ bottom: StyleConstants.SPACE_MD })

      Text('占位页面 · 暂无持久化设置')
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
