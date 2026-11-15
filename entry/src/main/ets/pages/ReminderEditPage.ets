import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { RouterConstants, ReminderEditNavParam } from '../common/RouterConstants';
import { getAppServices } from '../app/AppServiceRegistry';
import { RefreshSignal } from '../common/RefreshSignal';
import { Reminder } from '../model/Reminder';
import { CreateReminderInput } from '../model/CreateReminderInput';
import { DraftStore, ReminderDraft } from '../common/DraftStore';
import { parseTimeInput, TimeParseResult } from '../common/UiTimeInputParser';
import { ReminderSource, TriggerType } from '../model/ReminderEnums';
import { AIParseOutcome, AIParseStatus } from '../ai/model/AIParseResult';
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
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;
  @State pageTitle: string = '新建提醒';
  @State pageOverline: string = '草稿';
  @State titleInput: string = '';
  @State selectedTimeMs: number = 0;
  @State manualInput: string = '';
  @State saveError: string = '';
  /** 触发方式选择：时间 / 地点 / 时间+地点 */
  @State typeSel: TriggerType = TriggerType.TIME;
  /** 地点名称（V1 用文本占位，等地点选择器接入） */
  @State sceneInput: string = '';
  /** 自然语言输入与解析状态 */
  @State nlText: string = '';
  @State nlBusy: boolean = false;
  @State nlMessage: string = '';
  @State nlRetryable: boolean = false;
  /** 本次内容是否来自 AI 解析（保存时写入 source） */
  private sourceFromAi: boolean = false;

  /** 编辑模式下的提醒 id；空串表示新建 */
  private originalId: string = '';
  private originalSource: ReminderSource = ReminderSource.MANUAL;
  private originalSceneId: string = '';
  private draftKeyValue: string = '';
  private initialTitle: string = '';
  private initialTimeMs: number = 0;

  aboutToAppear(): void {
    const params: Array<Object> =
      this.pathStack.getParamByName(RouterConstants.PAGE_REMINDER_EDIT) as Array<Object>;
    if (params.length > 0) {
      const last: Object = params[params.length - 1];
      if (last instanceof ReminderEditNavParam) {
        if (last.draftKey !== undefined && last.draftKey !== '') {
          this.draftKeyValue = last.draftKey;
        }
        if (last.mode === RouterConstants.EDIT_MODE_EDIT) {
          this.pageTitle = '编辑提醒';
          this.pageOverline = '修改中';
          this.originalId = last.id;
        }
      }
    }
    if (this.originalId !== '') {
      this.loadOriginal();
    }
    if (this.selectedTimeMs === 0) {
      const next: Date = new Date();
      next.setMinutes(0, 0, 0);
      next.setHours(next.getHours() + 1);
      this.selectedTimeMs = next.getTime();
    }
    // 没有显式传入草稿键时：编辑已有提醒用它的 id，新建则生成一个新的草稿键
    if (this.draftKeyValue === '') {
      this.draftKeyValue = this.originalId === '' ? `draft-${Date.now()}` : this.originalId;
    }
    // 有草稿就恢复，并提示用户
    const draft: ReminderDraft | undefined = DraftStore.get(this.draftKeyValue);
    if (draft !== undefined) {
      this.titleInput = draft.title;
      if (draft.timeMs > 0) {
        this.selectedTimeMs = draft.timeMs;
      }
      this.typeSel = this.toTriggerType(draft.triggerType);
      this.sceneInput = draft.sceneName;
      this.pageOverline = '已恢复草稿';
    }
    this.initialTitle = this.titleInput;
    this.initialTimeMs = this.selectedTimeMs;
  }

  /** 编辑模式：按 id 从服务读最新提醒填表（导航参数只带 id） */
  private async loadOriginal(): Promise<void> {
    const result = await getAppServices().reminderService.findById(this.originalId);
    if (!result.success || result.data === undefined) {
      this.saveError = result.error === undefined ? '读取提醒失败' : result.error.message;
      return;
    }
    const r: Reminder = result.data;
    this.originalSource = r.source;
    this.originalSceneId = r.sceneId === undefined ? '' : r.sceneId;
    // 有草稿时以草稿为准：服务里的旧内容不能覆盖用户尚未保存的编辑
    if (DraftStore.get(this.draftKeyValue) !== undefined) {
      return;
    }
    this.titleInput = r.content;
    if (r.triggerTime !== undefined) {
      this.selectedTimeMs = r.triggerTime;
    }
    this.typeSel = r.triggerType;
    this.sceneInput = r.sceneName === undefined ? '' : r.sceneName;
    this.initialTitle = this.titleInput;
    this.initialTimeMs = this.selectedTimeMs;
  }

  private toTriggerType(value: string): TriggerType {
    if (value === TriggerType.LOCATION) {
      return TriggerType.LOCATION;
    }
    if (value === TriggerType.BOTH) {
      return TriggerType.BOTH;
    }
    return TriggerType.TIME;
  }

  private draftKey(): string {
    return this.draftKeyValue;
  }

  private buildDraft(): ReminderDraft {
    return new ReminderDraft(this.titleInput, this.selectedTimeMs, this.typeSel, this.sceneInput, Date.now());
  }

  /** 页内「存草稿」：存完留在当前页，继续写 */
  private saveDraftInPlace(): void {
    DraftStore.save(getContext(this), this.draftKey(), this.buildDraft());
    // 草稿已落盘，再把基线对齐，离开时就不会重复追问
    this.initialTitle = this.titleInput;
    this.initialTimeMs = this.selectedTimeMs;
    this.pageOverline = '草稿已保存';
    this.getUIContext().getPromptAction().showToast({ message: '已存为草稿' });
  }

  private saveDraftAndExit(): void {
    DraftStore.save(getContext(this), this.draftKey(), this.buildDraft());
    this.pathStack.pop();
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
      message: '改动尚未保存。可以存成草稿，下次进来继续写。',
      buttons: [
        { text: '存草稿', color: $r('app.color.text_secondary') },
        { text: '放弃', color: $r('app.color.text_secondary') },
        { text: '保存', color: $r('app.color.detail_ink') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 0) {
        this.saveDraftAndExit();
      } else if (result.index === 1) {
        DraftStore.clear(getContext(this), this.draftKey());
        this.pathStack.pop();
      } else if (result.index === 2) {
        this.save();
      }
    }).catch(() => {
    });
  }

  private placeRelevant(): boolean {
    return this.typeSel !== TriggerType.TIME;
  }

  /**
   * 区块编号统一由这里算：按固定顺序累加"可见"区块，
   * 隐藏的区块不占号，避免出现 01 02 03 03 这种重复。
   */
  /** 区块颜色：极简统一近黑；手账按区块区分，相邻区块不重色 */
  private sectionColor(kind: string): ResourceColor {
    if (this.uiMode !== UiMode.JOURNAL) {
      return Theme.text(this.uiMode);
    }
    if (kind === 'nl') {
      return $r('app.color.accent_mint');
    }
    if (kind === 'content') {
      return $r('app.color.accent_coral');
    }
    if (kind === 'trigger') {
      return $r('app.color.accent_sky');
    }
    if (kind === 'time') {
      return $r('app.color.accent_mustard');
    }
    return $r('app.color.accent_sage');
  }

  private sectionNo(kind: string): string {
    let n: number = 0;
    n += 1;
    if (kind === 'nl') {
      return n < 10 ? `0${n}` : `${n}`;
    }
    n += 1;
    if (kind === 'content') {
      return n < 10 ? `0${n}` : `${n}`;
    }
    n += 1;
    if (kind === 'trigger') {
      return n < 10 ? `0${n}` : `${n}`;
    }
    if (this.timeRelevant()) {
      n += 1;
      if (kind === 'time') {
        return n < 10 ? `0${n}` : `${n}`;
      }
    }
    if (this.placeRelevant()) {
      n += 1;
      if (kind === 'place') {
        return n < 10 ? `0${n}` : `${n}`;
      }
    }
    return '';
  }

  /** 调 AIService 解析自然语言；解析本身不保存任何东西，只回填表单 */
  private async parseNaturalLanguage(): Promise<void> {
    const text: string = this.nlText.trim();
    if (text === '') {
      this.nlMessage = '先输入一句话，例如“明天下午五点去图书馆还书”';
      this.nlRetryable = false;
      return;
    }
    this.nlBusy = true;
    this.nlMessage = '';
    this.nlRetryable = false;
    try {
      const outcome: AIParseOutcome = await getAppServices().aiService.parseReminder(text, {
        now: Date.now(),
        timeZone: 'Asia/Shanghai',
        locale: 'zh-CN'
      });
      this.applyParsed(outcome);
    } catch (_) {
      this.nlMessage = '解析失败，请稍后重试';
      this.nlRetryable = true;
    } finally {
      this.nlBusy = false;
    }
  }

  private applyParsed(outcome: AIParseOutcome): void {
    let issuesText: string = '';
    for (let i = 0; i < outcome.issues.length && i < 2; i++) {
      if (issuesText !== '') {
        issuesText += '；';
      }
      issuesText += outcome.issues[i].message;
    }
    if (outcome.draft !== undefined) {
      const draft: CreateReminderInput = outcome.draft;
      if (draft.content.trim() !== '') {
        this.titleInput = draft.content;
      }
      this.typeSel = draft.triggerType;
      if (draft.triggerTime !== undefined) {
        this.selectedTimeMs = draft.triggerTime;
      }
      if (draft.sceneName !== undefined && draft.sceneName !== '') {
        this.sceneInput = draft.sceneName;
      }
      this.sourceFromAi = true;
      this.saveError = '';
    }
    if (outcome.status === AIParseStatus.READY) {
      this.nlMessage = '已提取，请核对下面的内容、提醒方式' +
        (this.timeRelevant() ? '、时间' : '') + (this.placeRelevant() ? '、地点' : '');
      this.nlRetryable = false;
    } else if (outcome.status === AIParseStatus.NEEDS_CONFIRMATION) {
      this.nlMessage = issuesText === '' ? '已提取部分信息，请补充确认' : `需要确认：${issuesText}`;
      this.nlRetryable = true;
    } else {
      this.nlMessage = issuesText === '' ? '没能理解这句话，换个说法再试试' : issuesText;
      this.nlRetryable = true;
    }
  }

  private triggerType(): string {
    return this.typeSel;
  }

  private triggerTypeText(): string {
    const t: string = this.triggerType();
    if (t === TriggerType.LOCATION) {
      return '地点提醒';
    }
    if (t === TriggerType.BOTH) {
      return '时间 + 地点';
    }
    return '时间提醒';
  }

  private timeRelevant(): boolean {
    return this.typeSel !== TriggerType.LOCATION;
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
        if (next.getTime() < Date.now()) {
          this.getUIContext().getPromptAction().showToast({ message: '这个时间已经过去，保存前请调整' });
        }
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
        if (next.getTime() < Date.now()) {
          this.getUIContext().getPromptAction().showToast({ message: '这个时间已经过去，保存前请调整' });
        }
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
    if (this.typeSel !== TriggerType.TIME && this.sceneInput.trim() === '') {
      this.saveError = '请填写地点名称';
      return;
    }
    const input: CreateReminderInput = {
      content: content,
      triggerType: this.typeSel,
      triggerTime: this.timeRelevant() ? this.selectedTimeMs : undefined,
      sceneId: this.typeSel === TriggerType.TIME ? undefined : (this.originalSceneId === '' ? undefined : this.originalSceneId),
      sceneName: this.typeSel === TriggerType.TIME ? undefined : this.sceneInput.trim(),
      source: this.sourceFromAi ? ReminderSource.AI : this.originalSource
    };
    if (this.timeRelevant() && this.isPastSelected()) {
      // 2026-11-15 起允许记录过去的时间：只提醒，不拦截
      this.confirmPastSave(input);
      return;
    }
    this.submit(input);
  }

  /** 过去时间保存前的确认：允许记录已经发生/错过的事 */
  private confirmPastSave(input: CreateReminderInput): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '时间已经过去',
      message: '所选时间早于当前时间。仍然保存这条提醒吗？它会出现在逾期列表里。',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '仍然保存', color: $r('app.color.detail_ink') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.submit(input);
      }
    }).catch(() => {
    });
  }

  /** 新建 / 更新统一走 ReminderService；id、状态与时间戳由服务生成或保留 */
  private async submit(input: CreateReminderInput): Promise<void> {
    const services = getAppServices();
    const result = this.originalId === ''
      ? await services.reminderService.create(input)
      : await services.reminderService.update(this.originalId, input);
    if (!result.success) {
      this.saveError = result.error === undefined ? '保存失败' : result.error.message;
      if (result.error !== undefined && result.error.code === 'TRIGGER_REGISTRATION_ERROR') {
        this.saveError += '（到点提醒需要系统通知权限：设置 → 通知和状态栏 → ContextCue → 允许通知；' +
          '若已开启仍失败，请确认真机/模拟器安装的是签名包）';
      }
      return;
    }
    DraftStore.clear(getContext(this), this.draftKey());
    RefreshSignal.bump();
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
            this.NlSection()
            this.ContentSection()
            this.TriggerSection()
            // 时间/地点按提醒方式自动显隐；编号跟着可见区块顺延
            if (this.timeRelevant()) {
              this.TimeSection()
            }
            if (this.placeRelevant()) {
              this.PlaceSection()
            }
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
          .backgroundColor(Theme.surface(this.uiMode))
          .borderRadius({
            topLeft: 0,
            topRight: 18,
            bottomLeft: 0,
            bottomRight: 0
          })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 14, right: 14, top: 7, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg(this.uiMode))
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.bg(this.uiMode))
    .onBackPressed(() => {
      this.requestExit();
      return true;
    })
  }

  @Builder
  MastheadBlock() {
    Row({ space: 6 }) {
      Text(this.pageTitle)
        .fontSize(30)
        .fontWeight(900)
        .fontColor(Theme.text(this.uiMode))
        .layoutWeight(1)
      Text(this.pageOverline)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.archive_ink'))
        .padding({ left: 11, right: 11, top: 7, bottom: 7 })
        .backgroundImage(this.uiMode === UiMode.JOURNAL ? $r('app.media.ticket_coral') : undefined)
        .backgroundImageSize({ width: '100%', height: '100%' })
        .rotate({ angle: this.uiMode === UiMode.JOURNAL ? -3 : 0 })
    }
    .width('100%')
    .padding({ bottom: 9 })
    .border({ width: { bottom: 2 }, color: Theme.rule(this.uiMode) })
    .alignItems(VerticalAlign.Center)
  }

  /** 悬挂大编号：编号和颜色都在 builder 内按 kind 计算，切换提醒方式时不会残留旧值 */
  @Builder
  SectionNumber(kind: string) {
    Text(this.sectionNo(kind))
      .fontSize(StyleConstants.FONT_DISPLAY)
      .fontWeight(900)
      .fontColor(this.sectionColor(kind))
      .opacity(0.30)
      .width(48)
  }

  /** 栏目标题 + 中粗线 */
  @Builder
  SectionHead(title: string, kind: string) {
    Column({ space: StyleConstants.SPACE_XS }) {
      Row({ space: StyleConstants.SPACE_SM }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(this.sectionColor(kind))
        Text(title)
          .fontSize(StyleConstants.FONT_TITLE_LG)
          .fontWeight(900)
          .fontColor(Theme.text(this.uiMode))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column()
        .width('100%')
        .height(StyleConstants.RULE_MEDIUM)
        .backgroundColor(Theme.text(this.uiMode))
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
  NlSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('nl')
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('自然语言解析', 'nl')

        TextArea({
          placeholder: '例如：明天下午五点去图书馆还书',
          text: this.nlText
        })
          .onChange((value: string) => {
            this.nlText = value;
          })
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(FontWeight.Regular)
          .fontColor(Theme.text(this.uiMode))
          .placeholderColor(Theme.sub(this.uiMode))
          .backgroundColor(Color.Transparent)
          .padding({
            left: 8,
            right: 8,
            top: StyleConstants.SPACE_SM,
            bottom: StyleConstants.SPACE_SM
          })
          .lineHeight(26)
          .height(84)
          .width('100%')
          .border({ width: { bottom: 1 }, color: Theme.rule(this.uiMode) })

        Row({ space: 10 }) {
          Text(this.nlBusy ? '解析中…' : '解析')
            .fontSize(StyleConstants.FONT_SECTION_INDEX)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.nlBusy ? Theme.sub(this.uiMode) : Theme.text(this.uiMode))
            .decoration({ type: TextDecorationType.Underline })
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (!this.nlBusy) {
                this.parseNaturalLanguage();
              }
            })
          Text(this.nlMessage !== ''
            ? this.nlMessage
            : '把一句话解析成时间、地点和事件，结果可以在下面微调')
            .fontSize(10)
            .fontColor(this.nlRetryable ? Theme.alert(this.uiMode) : Theme.sub(this.uiMode))
            .layoutWeight(1)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  ContentSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('content')
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('提醒内容', 'content')

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
          .fontColor(Theme.text(this.uiMode))
          .placeholderColor(Theme.sub(this.uiMode))
          .backgroundColor(Color.Transparent)
          .padding({
            left: 8,
            right: 8,
            top: StyleConstants.SPACE_SM,
            bottom: StyleConstants.SPACE_SM
          })
          .lineHeight(32)
          .height(this.inputHeight())
          .width('100%')
          .border({ width: { bottom: 1 }, color: Theme.rule(this.uiMode) })
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
      this.SectionNumber('time')
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('日期与时间', 'time')
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
            .fontColor(Theme.text(this.uiMode))
            .margin({ top: StyleConstants.SPACE_XS })
        }
        this.ManualTimeRow()
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
          .fontColor(Theme.text(this.uiMode))
          .placeholderColor(Theme.sub(this.uiMode))
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .height(48)
          .layoutWeight(1)

        Text('解析')
          .fontSize(StyleConstants.FONT_SECTION_INDEX)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.uiMode))
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
        color: Theme.rule(this.uiMode)
      })

      Text('支持 15:30、下午3点半、明天、2027年3月5日、10月20日 15:30 等写法')
        .fontSize(StyleConstants.FONT_SECTION_INDEX)
        .fontColor(Theme.sub(this.uiMode))
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
      this.SectionNumber('trigger')
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('提醒方式', 'trigger')

        Row({ space: 8 }) {
          this.TypeChip('时间', TriggerType.TIME)
          this.TypeChip('地点', TriggerType.LOCATION)
          this.TypeChip('时间 + 地点', TriggerType.BOTH)
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: StyleConstants.SPACE_SECTION })
  }

  @Builder
  TypeChip(label: string, type: TriggerType) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.typeSel === type ? 900 : FontWeight.Medium)
      .fontColor(this.typeSel === type ? $r('app.color.archive_paper') : Theme.text(this.uiMode))
      .height(34)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.typeSel === type ? Theme.text(this.uiMode) : Color.Transparent)
      .border({
        width: this.typeSel === type ? 0 : 1,
        color: Theme.rule(this.uiMode)
      })
      .borderRadius({
        topLeft: 0,
        topRight: 8,
        bottomLeft: 0,
        bottomRight: 8
      })
      .onClick(() => {
        if (this.typeSel === type) {
          return;
        }
        // 切换会改变时间区块的内容高度；动画过渡，避免整页猛地上下弹
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
          this.typeSel = type;
          this.saveError = '';
        });
      })
  }

  /** 地点区块：编号跟着"时间是否可见"顺延（有时间为 04，否则为 03） */
  @Builder
  PlaceSection() {
    Row({ space: StyleConstants.SPACE_MD }) {
      this.SectionNumber('place')
      Column({ space: StyleConstants.SPACE_XS }) {
        this.SectionHead('地点', 'place')

        TextInput({
          placeholder: '地点名称，例如 家 / 公司',
          text: this.sceneInput
        })
          .onChange((value: string) => {
            this.sceneInput = value;
            this.saveError = '';
          })
          .fontSize(StyleConstants.FONT_BODY)
          .fontColor(Theme.text(this.uiMode))
          .placeholderColor(Theme.sub(this.uiMode))
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .height(44)
          .width('100%')
        Column()
          .width('100%')
          .height(StyleConstants.HAIRLINE_HEIGHT)
          .backgroundColor(Theme.rule(this.uiMode))

        Text('地点提醒需要定位与场景服务；当前只保存名称，等位置模块接入后生效。')
          .fontSize(9)
          .fontColor(Theme.sub(this.uiMode))
          .opacity(0.8)
          .maxLines(2)
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
          .fontColor(Theme.text(this.uiMode))
          .maxLines(2)
          .width('100%')
      }
      Text('存草稿')
        .fontSize(StyleConstants.FONT_BODY_SM)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.sub(this.uiMode))
        .decoration({ type: TextDecorationType.Underline })
        .height(StyleConstants.TOUCH_TARGET_MIN)
        .width('100%')
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.saveDraftInPlace();
        })

      Row() {
        Text('保存提醒')
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(900)
          .fontColor($r('app.color.archive_paper'))
        Blank()
        Text('→')
          .fontSize(StyleConstants.FONT_BODY)
          .fontWeight(900)
          .fontColor($r('app.color.archive_paper'))
      }
      .width('100%')
      .height(52)
      .padding({
        left: StyleConstants.SPACE_LG,
        right: StyleConstants.SPACE_LG
      })
      .backgroundColor($r('app.color.archive_ink'))
      .onClick(() => {
        this.save();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: StyleConstants.SPACE_SECTION })
  }
}
