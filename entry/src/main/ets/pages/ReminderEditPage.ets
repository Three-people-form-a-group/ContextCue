import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants, ReminderEditNavParam } from '../common/RouterConstants';
import { UiReminderStore } from '../common/UiReminderStore';
import { parseTimeInput, TimeParseResult } from '../common/UiTimeInputParser';
import { UiReminderSource, UiReminderStatus, UiTriggerType } from '../common/UiReminderSemantics';
import { ReminderCardData } from '../components/ReminderCard';
import { TopBar } from '../components/TopBar';
import { FormItem } from '../components/FormItem';

/**
 * 提醒编辑页 —— 报纸编辑工作台。
 *
 * 版面：灰蓝桌面 + 悬挂大编号（01–04）+ 粗细分隔线 + 下划线输入。
 * 不使用纸片容器，层级完全由编号、字号、栏线与留白构成。
 * 业务逻辑保持不变：带入原提醒、保存写入临时 UI 数据源、日期/时间选择器、
 * 手动解析与确认、离开前询问、过期时间弹窗。
 */
@Component
export struct ReminderEditPage {
  pathStack: NavPathStack = new NavPathStack();
  @State pageTitle: string = '新建提醒';
  @State pageOverline: string = 'NEW REMINDER';
  @State titleInput: string = '';
  @State selectedTimeMs: number = 0;
  @State manualInput: string = '';
  @State saveError: string = '';

  private original: ReminderCardData | undefined = undefined;
  private initialTitle: string = '';
  private initialTimeMs: number = 0;

  aboutToAppear(): void {
    const params: Array<Object> =
      this.pathStack.getParamByName(RouterConstants.PAGE_REMINDER_EDIT) as Array<Object>;
    if (params.length > 0) {
      const last: Object = params[params.length - 1];
      if (last instanceof ReminderEditNavParam && last.mode === RouterConstants.EDIT_MODE_EDIT) {
        this.pageTitle = '编辑提醒';
        this.pageOverline = 'EDIT REMINDER';
        if (last.data !== undefined) {
          this.original = last.data;
          this.titleInput = last.data.content;
          if (last.data.triggerTime !== undefined) {
            this.selectedTimeMs = last.data.triggerTime;
          }
        }
      }
    }
    if (this.selectedTimeMs === 0) {
      const next: Date = new Date();
      next.setMinutes(0, 0, 0);
      next.setHours(next.getHours() + 1);
      this.selectedTimeMs = next.getTime();
    }
    this.initialTitle = this.titleInput;
    this.initialTimeMs = this.selectedTimeMs;
  }

  private isDirty(): boolean {
    return this.titleInput !== this.initialTitle || this.selectedTimeMs !== this.initialTimeMs;
  }

  private requestExit(): void {
    if (!this.isDirty()) {
      this.pathStack.pop();
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '离开编辑',
      message: '改动尚未保存，是否保存？',
      buttons: [
        { text: '不保存', color: $r('app.color.text_secondary') },
        { text: '保存', color: $r('app.color.detail_ink') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.save();
      } else if (result.index === 0) {
        this.pathStack.pop();
      }
    }).catch(() => {
    });
  }

  private triggerType(): string {
    return this.original === undefined ? UiTriggerType.TIME : this.original.triggerType;
  }

  private triggerTypeText(): string {
    const t: string = this.triggerType();
    if (t === UiTriggerType.LOCATION) {
      return '地点提醒';
    }
    if (t === UiTriggerType.BOTH) {
      return '时间 + 地点';
    }
    return '时间提醒';
  }

  private timeRelevant(): boolean {
    return this.triggerType() !== UiTriggerType.LOCATION;
  }

  private dateLabel(): string {
    const d: Date = new Date(this.selectedTimeMs);
    const y: number = d.getFullYear();
    const thisYear: number = new Date().getFullYear();
    return y === thisYear
      ? `${d.getMonth() + 1}月${d.getDate()}日`
      : `${y}年${d.getMonth() + 1}月${d.getDate()}日`;
  }

  private timeLabel(): string {
    const d: Date = new Date(this.selectedTimeMs);
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    const hText: string = h < 10 ? `0${h}` : `${h}`;
    const mText: string = m < 10 ? `0${m}` : `${m}`;
    return `${hText}:${mText}`;
  }

  private isPastSelected(): boolean {
    return this.selectedTimeMs < Date.now();
  }

  private pickDate(): void {
    const current: Date = new Date(this.selectedTimeMs);
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: current,
      onDateAccept: (value: Date) => {
        const next: Date = new Date(
          value.getFullYear(), value.getMonth(), value.getDate(),
          current.getHours(), current.getMinutes(), 0, 0
        );
        this.selectedTimeMs = next.getTime();
      }
    });
  }

  private pickTime(): void {
    const current: Date = new Date(this.selectedTimeMs);
    this.getUIContext().showTimePickerDialog({
      selected: current,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const next: Date = new Date(
          current.getFullYear(), current.getMonth(), current.getDate(),
          value.hour, value.minute, 0, 0
        );
        this.selectedTimeMs = next.getTime();
      }
    });
  }

  private showParseError(message: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '无法识别时间',
      message: message,
      buttons: [
        { text: '知道了', color: $r('app.color.detail_ink') }
      ]
    }).then(() => {
    }).catch(() => {
    });
  }

  private showPastTimeWarning(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '时间已经过去',
      message: '所选时间早于当前时间，请重新选择日期或时间后再保存。',
      buttons: [
        { text: '知道了', color: $r('app.color.detail_ink') }
      ]
    }).then(() => {
    }).catch(() => {
    });
  }

  private applyManualInput(): void {
    const result: TimeParseResult = parseTimeInput(this.manualInput, Date.now());
    if (!result.ok) {
      this.showParseError(result.message);
      return;
    }
    let message: string;
    if (result.dateShifted) {
      message = `「${this.manualInput.trim()}」在今天已经过去，将改为 ${result.label}（次日凌晨），是否确认？`;
    } else if (result.isPast) {
      message = `将改为 ${result.label}。该时间已经过去，仍要使用吗？`;
    } else {
      message = `将改为 ${result.label}，是否确认？`;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '确认修改时间',
      message: message,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '确认修改', color: $r('app.color.detail_ink') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.selectedTimeMs = result.timestamp;
        this.manualInput = '';
      }
    }).catch(() => {
    });
  }

  private save(): void {
    const content: string = this.titleInput.trim();
    if (content === '') {
      this.saveError = '请填写提醒内容';
      return;
    }
    if (this.timeRelevant() && this.isPastSelected()) {
      this.saveError = '所选时间已过去，请重新选择';
      this.showPastTimeWarning();
      return;
    }

    let next: ReminderCardData;
    if (this.original === undefined) {
      next = new ReminderCardData(
        `ui-${Date.now()}`,
        content,
        UiTriggerType.TIME,
        UiReminderSource.MANUAL,
        UiReminderStatus.ACTIVE,
        this.selectedTimeMs
      );
    } else {
      next = new ReminderCardData(
        this.original.id,
        content,
        this.original.triggerType,
        this.original.source,
        this.original.status,
        this.timeRelevant() ? this.selectedTimeMs : undefined,
        this.original.sceneId,
        this.original.sceneName,
        this.original.locationTriggerMode
      );
    }

    UiReminderStore.upsert(next);
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        TopBar({
          title: '编辑台',
          showBack: true,
          onBack: () => {
            this.requestExit();
          }
        })
        Scroll() {
          Column() {
            this.MastheadBlock()
            this.ContentSection()
            this.TimeSection()
            this.TriggerSection()
            this.EditorNote()
            this.SaveBlock()
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({
            left: StyleConstants.PAGE_PADDING_H,
            right: StyleConstants.PAGE_PADDING_H,
            top: StyleConstants.SPACE_LG,
            bottom: StyleConstants.SPACE_XXL
          })
          .backgroundColor($r('app.color.surface_primary'))
          .borderRadius({
            topLeft: 0,
            topRight: StyleConstants.RADIUS_LG,
            bottomLeft: 0,
            bottomRight: 0
          })
          .margin({
            left: 12,
            right: 12,
            top: 8,
            bottom: 12
          })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.background_primary'))
    .onBackPressed(() => {
      this.requestExit();
      return true;
    })
  }

  @Builder
  MastheadBlock() {
    Column() {
      Row() {
        Text('FORM')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(2)
        Blank()
        Text(this.pageOverline)
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
        Text(this.pageTitle)
          .fontSize(StyleConstants.FONT_DISPLAY)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Column()
          .width(36)
          .height(4)
          .backgroundColor($r('app.color.detail_ink'))
          .margin({ top: StyleConstants.SPACE_XL })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: StyleConstants.SPACE_SM })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 悬挂大编号 */
  @Builder
  SectionNumber(no: string, color: ResourceColor) {
    Text(no)
      .fontSize(StyleConstants.FONT_DISPLAY)
      .fontWeight(900)
      .fontColor(color)
      .opacity(0.30)
      .width(48)
  }

  /** 栏目标题 + 中粗线 */
  @Builder
  SectionHead(title: string, color: ResourceColor) {
    Column({ space: StyleConstants.SPACE_XS }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(color)
        Text(title)
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor($r('app.color.text_primary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 每行可容纳的宽度（以 em 计），用于估算换行与高亮宽度 */
  private lineCapacity: number = 10.2;

  private charWidth(ch: string): number {
    return ch.charCodeAt(0) > 127 ? 1.0 : 0.55;
  }

  /** 按字数拆行：高亮条与整体高度都从这里派生 */
  private highlightLines(): string[] {
    const text: string = this.titleInput;
    const lines: string[] = [];
    if (text === '') {
      return lines;
    }
    let cur: string = '';
    let w: number = 0;
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch.charCodeAt(0) === 10) {
        lines.push(cur);
        cur = '';
        w = 0;
        continue;
      }
      const cw: number = this.charWidth(ch);
      if (cur !== '' && w + cw > this.lineCapacity) {
        lines.push(cur);
        cur = '';
        w = 0;
      }
      cur += ch;
      w += cw;
    }
    lines.push(cur);
    return lines;
  }


  private inputHeight(): number {
    const n: number = Math.max(1, this.highlightLines().length);
    return n * 30 + StyleConstants.SPACE_MD * 2;
  }

  @Builder
  ContentSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('01', $r('app.color.detail_ink'))
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('提醒内容', $r('app.color.detail_ink'))

        TextArea({
          placeholder: '输入提醒内容',
          text: this.titleInput
        })
          .onChange((value: string) => {
            this.titleInput = value;
            this.saveError = '';
          })
          .fontSize(StyleConstants.FONT_BODY + 2)
          .fontWeight(FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .padding({
            left: 0,
            right: 0,
            top: StyleConstants.SPACE_SM,
            bottom: StyleConstants.SPACE_SM
          })
          .lineHeight(32)
          .height(this.inputHeight())
          .width('100%')
          // 连续下划线：跟随实际换行，颜色与详情页同一支红
          .decoration({
            type: TextDecorationType.Underline,
            color: $r('app.color.detail_ink')
          })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  TimeSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('02', $r('app.color.brand_primary'))
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('日期与时间', $r('app.color.brand_primary'))
        if (this.timeRelevant()) {
          FormItem({
            label: '日期',
            value: this.dateLabel(),
            placeholder: '',
            onTap: () => {
              this.pickDate();
            }
          })
          FormItem({
            label: '时间',
            value: this.timeLabel(),
            placeholder: '',
            highlightValue: true,
            onTap: () => {
              this.pickTime();
            }
          })
          if (this.isPastSelected()) {
            Text('所选时间已过去，请重新选择')
              .fontSize(StyleConstants.FONT_SECTION_INDEX)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: StyleConstants.SPACE_XS })
          }
          this.ManualTimeRow()
        } else {
          Text('地点提醒不含固定时间')
            .fontSize(StyleConstants.FONT_BODY_SM)
            .fontColor($r('app.color.text_secondary'))
            .padding({
              top: StyleConstants.SPACE_MD,
              bottom: StyleConstants.SPACE_MD
            })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  ManualTimeRow() {
    Column({ space: StyleConstants.SPACE_XS }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        TextInput({
          placeholder: '手动输入，如：明天下午3点半',
          text: this.manualInput
        })
          .onChange((value: string) => {
            this.manualInput = value;
          })
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .height(48)
          .layoutWeight(1)

        Text('解析')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .decoration({ type: TextDecorationType.Underline })
          .textAlign(TextAlign.Center)
          .height(StyleConstants.TOUCH_TARGET_MIN)
          .padding({
            left: StyleConstants.SPACE_SM,
            right: StyleConstants.SPACE_SM
          })
          .onClick(() => {
            this.applyManualInput();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .border({
        width: { bottom: StyleConstants.HAIRLINE_HEIGHT },
        color: $r('app.color.border_subtle')
      })

      Text('支持 15:30、下午3点半、明天、2027年3月5日、10月20日 15:30 等写法')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontColor($r('app.color.text_secondary'))
        .opacity(0.85)
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SM })
  }

  @Builder
  TriggerSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('03', $r('app.color.accent_olive'))
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('触发条件', $r('app.color.accent_olive'))
        FormItem({
          label: '触发类型',
          value: this.triggerTypeText(),
          placeholder: '',
          onTap: () => {
          }
        })
        FormItem({
          label: '地点',
          value: this.original !== undefined && this.original.sceneName !== undefined
            ? this.original.sceneName
            : '',
          placeholder: '未设置',
          badgeLabel: '进入时',
          onTap: () => {
          }
        })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  EditorNote() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('04', $r('app.color.detail_ink'))
      Column({ space: StyleConstants.SPACE_XS }) {
        Row({ space: StyleConstants.SPACE_SM }) {
          Column()
            .width(3)
            .height(14)
            .backgroundColor($r('app.color.detail_ink'))
          Text('AI 辅助')
            .fontSize(StyleConstants.FONT_TITLE_LG)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text('接入 AI 模块后，这里会根据自然语言生成时间与地点建议')
          .fontSize(StyleConstants.FONT_BODY_SM)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .padding(StyleConstants.SPACE_MD)
          .border({
            width: StyleConstants.RULE_MEDIUM,
            color: $r('app.color.detail_ink'),
            style: BorderStyle.Dashed
          })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  SaveBlock() {
    Column({ space: StyleConstants.SPACE_SM }) {
      if (this.saveError !== '') {
        Text(this.saveError)
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .width('100%')
      }
      // 印刷式操作条：整条暖橙，文字在左、箭头在右
      Row() {
        Text('保存提醒')
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('→')
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(900)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(52)
      .padding({
        left: StyleConstants.SPACE_LG,
        right: StyleConstants.SPACE_LG
      })
      .backgroundColor($r('app.color.accent_primary'))
      .onClick(() => {
        this.save();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SECTION })
  }
}
