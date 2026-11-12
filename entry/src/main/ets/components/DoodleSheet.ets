import { promptAction } from '@kit.ArkUI';
import { StyleConstants } from '../common/StyleConstants';
import { DoodleStroke, PenStyle, parseDoodle, serializeDoodle } from '../common/DoodleModel';
import { PaperStyle } from '../common/PaperStyle';
import { DoodleView } from './DoodleView';
import { NoteLayoutView } from './NoteLayoutView';
import { NoteLayout, parseLayout, serializeLayout } from '../common/NoteLayoutModel';
import { DoodleStore } from '../common/DoodleStore';

const TOOL_BRUSH: string = 'brush';
const TOOL_ERASER: string = 'eraser';

/** 固定色板：每次进来都一样，不记录使用过的颜色（草稿会带上当时的颜色） */
const PRESET_COLORS: string[] = [
  '#1F2328', '#263C61', '#B5563F', '#E86E54', '#E8C45B',
  '#8FB7B0', '#526B83', '#8F5AA8', '#5F6B4A', '#D9A3B0'
];

/** 大小轴 0~100 → 实际线宽 2~14vp（按 300vp 参考宽度记录） */
function sizeToWidth(v: number): number {
  return 2 + (Math.max(0, Math.min(100, v)) / 100) * 12;
}

function hslToRgb(h: number, s: number, l: number): number[] {
  const sat: number = Math.max(0, Math.min(100, s)) / 100;
  const light: number = Math.max(0, Math.min(100, l)) / 100;
  const c: number = (1 - Math.abs(2 * light - 1)) * sat;
  const hp: number = (h % 360) / 60;
  const x: number = c * (1 - Math.abs(hp % 2 - 1));
  let r: number = 0;
  let g: number = 0;
  let b: number = 0;
  if (hp < 1) {
    r = c; g = x;
  } else if (hp < 2) {
    r = x; g = c;
  } else if (hp < 3) {
    g = c; b = x;
  } else if (hp < 4) {
    g = x; b = c;
  } else if (hp < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  const m: number = light - c / 2;
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

function hslToHex(h: number, s: number, l: number): string {
  const rgb: number[] = hslToRgb(h, s, l);
  const to = (v: number): string => (v < 16 ? `0${v.toString(16)}` : v.toString(16));
  return `#${to(rgb[0])}${to(rgb[1])}${to(rgb[2])}`;
}

function hexToRgba(hex: string, alpha: number): string {
  let h: string = hex.replace('#', '');
  if (h.length === 3) {
    h = `${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}`;
  }
  const r: number = parseInt(h.substring(0, 2), 16);
  const g: number = parseInt(h.substring(2, 4), 16);
  const b: number = parseInt(h.substring(4, 6), 16);
  return `rgba(${Number.isNaN(r) ? 0 : r},${Number.isNaN(g) ? 0 : g},${Number.isNaN(b) ? 0 : b},${alpha})`;
}

const RING_SIZE: number = 88;
const RING_RADIUS: number = 33;
const PAD_HEIGHT: number = 64;

/**
 * 涂鸦弹层。
 *
 * 画幅固定 206vp、工具区固定高度：展开任何面板都不会让画布上下跳动。
 * 「涂鸦笔」里用两个符号切换笔/擦，大小与透明度各一条轴；
 * 颜色先给参考色与最近用色，点当前色才展开色环 + 精细色板。
 */
@Component
export struct DoodleSheet {
  paper: string = PaperStyle.LARGE_WARM;
  initial: string = '';
  title: string = '';
  timeText: string = '';
  placeText: string = '';
  featured: boolean = false;
  reminderId: string = '';
  initialLayout: string = '';
  onSave: (data: string) => void = () => {};
  onSaveLayout: (layout: string) => void = () => {};
  onClose: () => void = () => {};

  @State penMode: string = '';
  @State toolPanel: boolean = false;
  @State textPanel: boolean = false;
  @State showColorPicker: boolean = false;
  // 两根轴都按 0~100 定量，且每次打开弹层都回到 50 / 50
  @State brushSize: number = 50;
  @State inkOpacity: number = 50;
  @State pen: string = PenStyle.PEN;
  @State hue: number = 350;
  @State sat: number = 72;
  @State light: number = 45;
  @State pickedColor: string = '';
  @State strokeCount: number = 0;
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State preview: boolean = false;
  @State layoutData: string = '';
  @State selectedPart: string = '';

  private strokes: DoodleStroke[] = [];
  private current: number[] = [];
  private drawing: boolean = false;
  private lastX: number = 0;
  private lastY: number = 0;

  // 撤销 / 重做：整份笔迹做快照，橡皮的分段擦除也能正确回退
  private past: string[] = [];
  private future: string[] = [];
  private eraseDirty: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ringCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private padCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.layoutData = this.initialLayout;
    if (this.reminderId !== '') {
      const draft: string = DoodleStore.get(`${this.reminderId}.draft`);
      if (draft !== '') {
        // 草稿 = 笔迹 @@ 排版 @@ 当时的颜色
        const parts: string[] = draft.split('@@');
        this.strokes = parseDoodle(parts[0]);
        if (parts.length > 1 && parts[1] !== '') {
          this.layoutData = parts[1];
        }
        if (parts.length > 2 && parts[2] !== '') {
          this.pickedColor = parts[2];
        }
        this.strokeCount = this.strokes.length;
        return;
      }
    }
    this.strokes = parseDoodle(this.initial);
    this.strokeCount = this.strokes.length;
  }

  private currentColor(alpha: number): string {
    if (this.pickedColor !== '') {
      return hexToRgba(this.pickedColor, alpha);
    }
    const rgb: number[] = hslToRgb(this.hue, this.sat, this.light);
    return `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${alpha})`;
  }

  private currentHex(): string {
    return this.pickedColor !== '' ? this.pickedColor : hslToHex(this.hue, this.sat, this.light);
  }

  /** 0~100 的大小轴 → 实际线宽 */
  private strokeWidth(): number {
    return sizeToWidth(this.brushSize);
  }

  private inkAlpha(): number {
    const base: number = this.inkOpacity / 100;
    return this.pen === PenStyle.HIGHLIGHTER ? base * 0.45 : base;
  }

  // ---------- 撤销 / 重做 ----------

  private syncHistory(): void {
    this.canUndo = this.past.length > 0;
    this.canRedo = this.future.length > 0;
  }

  /** 一条历史 = 笔迹 + 文字排版，笔和文字共用同一套上一步/下一步 */
  private snapshot(): string {
    return serializeDoodle(this.strokes) + '@@' + this.layoutData;
  }

  /** 记录改动前的状态；新动作会清空重做栈 */
  private pushHistory(): void {
    this.past.push(this.snapshot());
    if (this.past.length > 40) {
      this.past.shift();
    }
    this.future = [];
    this.syncHistory();
  }

  private undoStroke(): void {
    const prev: string | undefined = this.past.pop();
    if (prev === undefined) {
      return;
    }
    this.future.push(this.snapshot());
    this.applyHistory(prev);
  }

  private redoStroke(): void {
    const next: string | undefined = this.future.pop();
    if (next === undefined) {
      return;
    }
    this.past.push(this.snapshot());
    this.applyHistory(next);
  }

  private applyHistory(data: string): void {
    const parts: string[] = data.split('@@');
    this.strokes = parseDoodle(parts[0]);
    if (parts.length > 1) {
      this.layoutData = parts[1];
    }
    this.strokeCount = this.strokes.length;
    this.current = [];
    this.drawing = false;
    this.syncHistory();
    this.redraw();
  }

  private pointCount(list: DoodleStroke[]): number {
    let n: number = 0;
    for (let i = 0; i < list.length; i++) {
      n += list[i].points.length;
    }
    return n;
  }

  // ---------- 绘制 ----------

  private redraw(): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < this.strokes.length; i++) {
      this.paintStroke(this.strokes[i], w, h);
    }
    if (this.current.length >= 2) {
      const alpha: number = this.inkAlpha();
      this.paintStroke(new DoodleStroke(this.currentColor(alpha), this.strokeWidth(), this.current, this.pen), w, h);
    }
  }

  private paintStroke(stroke: DoodleStroke, w: number, h: number): void {
    if (stroke.points.length < 2) {
      return;
    }
    const flat: boolean = stroke.penStyle === PenStyle.MARKER || stroke.penStyle === PenStyle.HIGHLIGHTER;
    this.ctx.beginPath();
    this.ctx.strokeStyle = stroke.color;
    this.ctx.lineWidth = Math.max(0.6, stroke.width * PenStyle.widthFactor(stroke.penStyle) * (w / 300));
    this.ctx.lineCap = flat ? 'butt' : 'round';
    this.ctx.lineJoin = 'round';
    this.ctx.moveTo(stroke.points[0] * w, stroke.points[1] * h);
    for (let p = 2; p + 1 < stroke.points.length; p += 2) {
      this.ctx.lineTo(stroke.points[p] * w, stroke.points[p + 1] * h);
    }
    this.ctx.stroke();
  }

  private drawRing(): void {
    const cx: number = RING_SIZE / 2;
    const cy: number = RING_SIZE / 2;
    this.ringCtx.clearRect(0, 0, RING_SIZE, RING_SIZE);
    for (let i = 0; i < 120; i++) {
      const a0: number = ((i * 3) - 90) * Math.PI / 180;
      const a1: number = (((i + 1) * 3) - 90) * Math.PI / 180;
      this.ringCtx.beginPath();
      this.ringCtx.strokeStyle = hslToHex(i * 3, 72, 55);
      this.ringCtx.lineWidth = 9;
      this.ringCtx.arc(cx, cy, RING_RADIUS, a0, a1);
      this.ringCtx.stroke();
    }
    const angle: number = (this.hue - 90) * Math.PI / 180;
    this.ringCtx.beginPath();
    this.ringCtx.fillStyle = '#1F2328';
    this.ringCtx.arc(cx + Math.cos(angle) * RING_RADIUS, cy + Math.sin(angle) * RING_RADIUS, 3, 0, Math.PI * 2);
    this.ringCtx.fill();
  }

  private drawPad(): void {
    const w: number = this.padCtx.width;
    const h: number = this.padCtx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.padCtx.clearRect(0, 0, w, h);
    const cols: number = 44;
    const rows: number = 14;
    const cw: number = w / cols;
    const ch: number = h / rows;
    for (let c = 0; c < cols; c++) {
      const s: number = 20 + (80 * c) / (cols - 1);
      for (let r = 0; r < rows; r++) {
        const l: number = 92 - (77 * r) / (rows - 1);
        this.padCtx.fillStyle = hslToHex(this.hue, s, l);
        this.padCtx.fillRect(c * cw, r * ch, cw + 0.6, ch + 0.6);
      }
    }
    const px: number = ((this.sat - 20) / 80) * w;
    const py: number = ((92 - this.light) / 77) * h;
    this.padCtx.beginPath();
    this.padCtx.strokeStyle = '#1F2328';
    this.padCtx.lineWidth = 1.4;
    this.padCtx.arc(px, py, 6, 0, Math.PI * 2);
    this.padCtx.stroke();
  }

  private pickHue(x: number, y: number): void {
    const cx: number = RING_SIZE / 2;
    const cy: number = RING_SIZE / 2;
    const deg: number = Math.atan2(y - cy, x - cx) * 180 / Math.PI;
    let h: number = (deg + 90) % 360;
    if (h < 0) {
      h += 360;
    }
    this.hue = Math.round(h);
    this.pickedColor = '';
    this.drawRing();
    this.drawPad();
  }

  /** 色环/色板上挂 PanGesture 取色：手势阈值比外层 Scroll 小，
   *  拖动色环时不会被面板的上下滚动抢走。 */
  private pickRingEvent(event: GestureEvent): void {
    if (event.fingerList.length === 0) {
      return;
    }
    this.pickHue(event.fingerList[0].localX, event.fingerList[0].localY);
  }

  private pickPadEvent(event: GestureEvent): void {
    if (event.fingerList.length === 0) {
      return;
    }
    this.pickShade(event.fingerList[0].localX, event.fingerList[0].localY);
  }

  private pickShade(x: number, y: number): void {
    const w: number = this.padCtx.width;
    const h: number = this.padCtx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.sat = Math.round(20 + 80 * Math.max(0, Math.min(1, x / w)));
    this.light = Math.round(92 - 77 * Math.max(0, Math.min(1, y / h)));
    this.pickedColor = '';
    this.drawPad();
  }

  // ---------- 触摸 ----------

  private eraseAt(nx: number, ny: number, radiusNorm: number): void {
    const next: DoodleStroke[] = [];
    for (let i = 0; i < this.strokes.length; i++) {
      const stroke: DoodleStroke = this.strokes[i];
      let segment: number[] = [];
      for (let p = 0; p + 1 < stroke.points.length; p += 2) {
        const dx: number = stroke.points[p] - nx;
        const dy: number = stroke.points[p + 1] - ny;
        if (dx * dx + dy * dy > radiusNorm * radiusNorm) {
          segment.push(stroke.points[p]);
          segment.push(stroke.points[p + 1]);
        } else if (segment.length >= 4) {
          next.push(new DoodleStroke(stroke.color, stroke.width, segment, stroke.penStyle));
          segment = [];
        } else {
          segment = [];
        }
      }
      if (segment.length >= 4) {
        next.push(new DoodleStroke(stroke.color, stroke.width, segment, stroke.penStyle));
      }
    }
    // 一次擦除手势只记一条历史；真的擦掉了东西才记
    if (!this.eraseDirty && this.pointCount(next) !== this.pointCount(this.strokes)) {
      this.pushHistory();
      this.eraseDirty = true;
    }
    this.strokes = next;
    this.strokeCount = next.length;
  }

  private onDown(x: number, y: number): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0 || this.penMode === '') {
      return;
    }
    const nx: number = Math.max(0, Math.min(1, x / w));
    const ny: number = Math.max(0, Math.min(1, y / h));
    if (this.penMode === TOOL_ERASER) {
      this.eraseDirty = false;
      this.eraseAt(nx, ny, (this.strokeWidth() * 1.6) / w);
      this.redraw();
      return;
    }
    this.drawing = true;
    this.current = [nx, ny];
    this.lastX = nx;
    this.lastY = ny;
    this.redraw();
  }

  private onMove(x: number, y: number): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const nx: number = Math.max(0, Math.min(1, x / w));
    const ny: number = Math.max(0, Math.min(1, y / h));
    if (this.penMode === TOOL_ERASER) {
      this.eraseAt(nx, ny, (this.strokeWidth() * 1.6) / w);
      this.redraw();
      return;
    }
    if (!this.drawing) {
      return;
    }
    const dx: number = nx - this.lastX;
    const dy: number = ny - this.lastY;
    const distVp: number = Math.sqrt((dx * w) * (dx * w) + (dy * h) * (dy * h));
    const steps: number = Math.max(1, Math.ceil(distVp / 2));
    for (let i = 1; i <= steps; i++) {
      this.current.push(this.lastX + (dx * i) / steps);
      this.current.push(this.lastY + (dy * i) / steps);
    }
    this.lastX = nx;
    this.lastY = ny;
    this.redraw();
  }

  private onUp(): void {
    if (!this.drawing) {
      return;
    }
    this.drawing = false;
    if (this.current.length >= 4) {
      this.pushHistory();
      this.strokes.push(new DoodleStroke(this.currentColor(this.inkAlpha()), this.strokeWidth(),
        this.current, this.pen));
      this.strokeCount = this.strokes.length;
    }
    this.current = [];
    this.redraw();
  }

  // ---------- 草稿 ----------

  private leave(): void {
    const changed: boolean = this.strokeCount !== parseDoodle(this.initial).length ||
      this.layoutData !== this.initialLayout;
    if (!changed) {
      this.onClose();
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '还没画完',
      message: '保存成草稿，下次进来接着画？',
      buttons: [
        { text: '继续编辑', color: $r('app.color.text_secondary') },
        { text: '丢弃', color: $r('app.color.text_secondary') },
        { text: '存草稿', color: $r('app.color.detail_ink') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        if (this.reminderId !== '') {
          DoodleStore.clear(getContext(this), `${this.reminderId}.draft`);
        }
        this.onClose();
      } else if (res.index === 2) {
        if (this.reminderId !== '') {
          DoodleStore.save(getContext(this), `${this.reminderId}.draft`,
            serializeDoodle(this.strokes) + '@@' + this.layoutData + '@@' + this.currentHex());
        }
        this.onClose();
      }
    }).catch(() => {
    });
  }

  // ---------- 视图 ----------

  private toolChipLabel(): string {
    if (this.penMode === TOOL_BRUSH) {
      return '涂鸦笔 · 画';
    }
    if (this.penMode === TOOL_ERASER) {
      return '涂鸦笔 · 擦';
    }
    return '涂鸦笔';
  }

  /** 展开工具面板时清掉笔/擦，收起时也清掉：不在面板里就不该再落笔 */
  private toggleToolPanel(): void {
    this.toolPanel = !this.toolPanel;
    this.textPanel = false;
    if (!this.toolPanel) {
      this.penMode = '';
      this.showColorPicker = false;
    }
  }

  private toggleTextPanel(): void {
    this.textPanel = !this.textPanel;
    this.toolPanel = false;
    if (this.textPanel) {
      this.penMode = '';
      this.showColorPicker = false;
    }
  }

  // 状态直接读 this，避免 @Builder 按值传参不刷新的老问题
  @Builder
  ToolChip() {
    Text(this.toolChipLabel())
      .fontSize(12)
      .fontWeight(this.toolPanel ? 900 : FontWeight.Medium)
      .fontColor(this.toolPanel ? $r('app.color.archive_paper') : $r('app.color.text_primary'))
      .height(30)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.toolPanel ? $r('app.color.archive_ink') : Color.Transparent)
      .border({ width: this.toolPanel ? 0 : 1, color: $r('app.color.archive_rule') })
      .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
      .onClick(() => {
        this.toggleToolPanel();
      })
  }

  @Builder
  TextChip() {
    Text('文字')
      .fontSize(12)
      .fontWeight(this.textPanel ? 900 : FontWeight.Medium)
      .fontColor(this.textPanel ? $r('app.color.archive_paper') : $r('app.color.text_primary'))
      .height(30)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.textPanel ? $r('app.color.archive_ink') : Color.Transparent)
      .border({ width: this.textPanel ? 0 : 1, color: $r('app.color.archive_rule') })
      .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
      .onClick(() => {
        this.toggleTextPanel();
      })
  }

  @Builder
  PenChip(label: string, pen: string) {
    Text(label)
      .fontSize(10)
      .fontWeight(this.pen === pen ? 900 : FontWeight.Medium)
      .fontColor(this.pen === pen ? $r('app.color.archive_paper') : $r('app.color.text_primary'))
      .height(26)
      .padding({ left: 8, right: 8 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.pen === pen ? $r('app.color.archive_ink') : Color.Transparent)
      .border({ width: this.pen === pen ? 0 : 1, color: $r('app.color.archive_rule') })
      .borderRadius({ topLeft: 0, topRight: 6, bottomLeft: 0, bottomRight: 6 })
      .onClick(() => {
        this.pen = pen;
      })
  }

  @Builder
  ColorDot(hex: string) {
    Column()
      .width(20)
      .height(20)
      .borderRadius(10)
      .backgroundColor(hex)
      .border({ width: 1, color: $r('app.color.archive_rule') })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.pickedColor = hex;
      })
  }

  @Builder
  PreviewNote(editable: boolean) {
    NoteLayoutView({
      layoutData: this.layoutData,
      time: this.timeText,
      title: this.title,
      place: this.placeText,
      featured: this.featured,
      editable: editable,
      // 只要打开了涂鸦笔面板，哪怕还没选笔，也不允许选中/拖动文字
      textInteractive: this.penMode === '' && !this.toolPanel,
      activePart: this.selectedPart,
      onChange: (data: string) => {
        if (data === this.layoutData) {
          return;
        }
        this.pushHistory();
        this.layoutData = data;
      },
      onSelectPart: (part: string) => {
        this.selectedPart = part;
      }
    })
  }

  @Builder
  TextToggleRow(label: string, part: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(this.partHidden(part) ? '已隐藏 · 点此显示' : '显示中 · 点此隐藏')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.partHidden(part) ? $r('app.color.accent_primary') : $r('app.color.text_secondary'))
        .height(28)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.togglePart(part);
        })
    }
    .width('100%')
    .height(30)
    .alignItems(VerticalAlign.Center)
  }

  private partHidden(part: string): boolean {
    const l: NoteLayout = parseLayout(this.layoutData);
    if (part === 'title') {
      return l.title.hidden;
    }
    if (part === 'place') {
      return l.place.hidden;
    }
    return l.time.hidden;
  }

  private togglePart(part: string): void {
    const l: NoteLayout = parseLayout(this.layoutData);
    if (part === 'title') {
      l.title.hidden = !l.title.hidden;
    } else if (part === 'place') {
      l.place.hidden = !l.place.hidden;
    } else {
      l.time.hidden = !l.time.hidden;
    }
    this.pushHistory();
    this.layoutData = serializeLayout(l);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.archive_ink'))
        .opacity(0.35)
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text('取消')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.leave();
            })
          Blank()
          Text('涂鸦')
            .fontSize(15)
            .fontWeight(900)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('预览')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 10, right: 10 })
            .textAlign(TextAlign.Center)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.preview = true;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.preview = false;
              }
            })
          Text('完成')
            .fontSize(14)
            .fontWeight(900)
            .fontColor($r('app.color.accent_primary'))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onSave(serializeDoodle(this.strokes));
              this.onSaveLayout(this.layoutData);
              if (this.reminderId !== '') {
                DoodleStore.clear(getContext(this), `${this.reminderId}.draft`);
              }
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Stack({ alignContent: Alignment.TopStart }) {
          Image(PaperStyle.resource(this.paper))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)

          if (this.preview) {
            Stack({ alignContent: Alignment.TopStart }) {
              DoodleView({ data: serializeDoodle(this.strokes) })
                .width('100%')
                .height('100%')
              Column() {
                this.PreviewNote(false)
              }
              .width('100%')
              .height('100%')
            }
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
          } else {
            Canvas(this.ctx)
              .width('100%')
              .height('100%')
              .onReady(() => {
                this.redraw();
              })
              .onTouch((event: TouchEvent) => {
                const t: TouchObject = event.touches.length > 0
                  ? event.touches[0]
                  : event.changedTouches[0];
                if (t === undefined) {
                  return;
                }
                if (event.type === TouchType.Down) {
                  if (this.selectedPart !== '') {
                    this.onSaveLayout(this.layoutData);
                    this.selectedPart = '';
                  }
                  this.onDown(t.x, t.y);
                } else if (event.type === TouchType.Move) {
                  this.onMove(t.x, t.y);
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.onUp();
                }
              })
            Column() {
              this.PreviewNote(true)
            }
            .width('100%')
            .height('100%')
            .opacity(0.5)
            // 编辑文字时必须挡住下面的画布：Transparent 会让画布也收到按下，
            // 画布一取消选中，角标就在抬手前被移除了，×/⤢ 永远点不中。
            .hitTestBehavior(this.penMode === '' && !this.toolPanel
              ? HitTestMode.Default
              : HitTestMode.Transparent)
          }
        }
        .height(206)
        .width('100%')
        .borderRadius({ topLeft: 0, topRight: 12, bottomLeft: 0, bottomRight: 12 })
        .clip(true)

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            this.ToolChip()
            this.TextChip()
            Blank()
            Text('撤销')
              .fontSize(11)
              .fontColor(this.canUndo ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .opacity(this.canUndo ? 1 : 0.35)
              .height(30)
              .padding({ left: 8, right: 8 })
              .textAlign(TextAlign.Center)
              .enabled(this.canUndo)
              .onClick(() => {
                this.undoStroke();
              })
            Text('重做')
              .fontSize(11)
              .fontColor(this.canRedo ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .opacity(this.canRedo ? 1 : 0.35)
              .height(30)
              .padding({ left: 8, right: 8 })
              .textAlign(TextAlign.Center)
              .enabled(this.canRedo)
              .onClick(() => {
                this.redoStroke();
              })
            Text('清空')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .height(30)
              .padding({ left: 8, right: 8 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (this.strokes.length === 0) {
                  return;
                }
                this.pushHistory();
                this.strokes = [];
                this.strokeCount = 0;
                this.redraw();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Scroll() {
            Column({ space: 8 }) {
              if (this.toolPanel) {
                Row({ space: 8 }) {
                  Text('✎')
                    .fontSize(20)
                    .width(40)
                    .height(32)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.penMode === TOOL_BRUSH ? $r('app.color.archive_paper') : $r('app.color.text_primary'))
                    .backgroundColor(this.penMode === TOOL_BRUSH ? $r('app.color.archive_ink') : Color.Transparent)
                    .border({ width: this.penMode === TOOL_BRUSH ? 0 : 1, color: $r('app.color.archive_rule') })
                    .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
                    .onClick(() => {
                      this.penMode = this.penMode === TOOL_BRUSH ? '' : TOOL_BRUSH;
                      if (this.penMode !== '') {
                        this.selectedPart = '';
                      }
                    })
                  Text('⌫')
                    .fontSize(18)
                    .width(40)
                    .height(32)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.penMode === TOOL_ERASER ? $r('app.color.archive_paper') : $r('app.color.text_primary'))
                    .backgroundColor(this.penMode === TOOL_ERASER ? $r('app.color.archive_ink') : Color.Transparent)
                    .border({ width: this.penMode === TOOL_ERASER ? 0 : 1, color: $r('app.color.archive_rule') })
                    .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
                    .onClick(() => {
                      this.penMode = this.penMode === TOOL_ERASER ? '' : TOOL_ERASER;
                      if (this.penMode !== '') {
                        this.selectedPart = '';
                      }
                    })
                  Column()
                    .width(this.strokeWidth() * 2)
                    .height(this.strokeWidth() * 2)
                    .borderRadius(this.strokeWidth())
                    .backgroundColor(this.penMode === TOOL_ERASER
                      ? Color.Transparent
                      : this.currentColor(this.inkAlpha()))
                    .border({ width: 1, color: $r('app.color.archive_rule') })
                  Blank()
                  this.PenChip('钢笔', PenStyle.PEN)
                  this.PenChip('铅笔', PenStyle.PENCIL)
                  this.PenChip('马克', PenStyle.MARKER)
                  this.PenChip('荧光', PenStyle.HIGHLIGHTER)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Row({ space: 8 }) {
                  Text('大小')
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width(28)
                  Slider({ value: this.brushSize, min: 0, max: 100, step: 1 })
                    .layoutWeight(1)
                    .onChange((value: number) => {
                      this.brushSize = Math.round(value);
                    })
                  Text(`${this.brushSize}`)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width(24)
                    .textAlign(TextAlign.End)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Row({ space: 8 }) {
                  Text('透明')
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width(28)
                  Slider({ value: this.inkOpacity, min: 0, max: 100, step: 1 })
                    .layoutWeight(1)
                    .onChange((value: number) => {
                      this.inkOpacity = Math.round(value);
                    })
                  Text(`${this.inkOpacity}`)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .width(24)
                    .textAlign(TextAlign.End)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                // 固定色板：每次进来都是这一组，不记录用过的颜色
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  Column()
                    .width(24)
                    .height(24)
                    .borderRadius(12)
                    .backgroundColor(this.currentHex())
                    .border({ width: 1.5, color: $r('app.color.archive_ink') })
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => {
                      this.showColorPicker = !this.showColorPicker;
                    })
                  ForEach(PRESET_COLORS, (hex: string) => {
                    this.ColorDot(hex)
                  }, (hex: string) => `preset-${hex}`)
                }
                .width('100%')

                if (this.showColorPicker) {
                  Row({ space: 10 }) {
                    Canvas(this.ringCtx)
                      .width(RING_SIZE)
                      .height(RING_SIZE)
                      .onReady(() => {
                        this.drawRing();
                        this.drawPad();
                      })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down || event.type === TouchType.Move) {
                          const t: TouchObject = event.touches.length > 0
                            ? event.touches[0]
                            : event.changedTouches[0];
                          if (t !== undefined) {
                            this.pickHue(t.x, t.y);
                          }
                        }
                      })
                      .gesture(
                        PanGesture({ distance: 1 })
                          .onActionStart((event: GestureEvent) => {
                            this.pickRingEvent(event);
                          })
                          .onActionUpdate((event: GestureEvent) => {
                            this.pickRingEvent(event);
                          })
                      )
                    Canvas(this.padCtx)
                      .layoutWeight(1)
                      .height(PAD_HEIGHT)
                      .border({ width: 1, color: $r('app.color.archive_rule') })
                      .onReady(() => {
                        this.drawPad();
                      })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down || event.type === TouchType.Move) {
                          const t: TouchObject = event.touches.length > 0
                            ? event.touches[0]
                            : event.changedTouches[0];
                          if (t !== undefined) {
                            this.pickShade(t.x, t.y);
                          }
                        }
                      })
                      .gesture(
                        PanGesture({ distance: 1 })
                          .onActionStart((event: GestureEvent) => {
                            this.pickPadEvent(event);
                          })
                          .onActionUpdate((event: GestureEvent) => {
                            this.pickPadEvent(event);
                          })
                      )
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
              }

              if (this.textPanel) {
                this.TextToggleRow('时间', 'time')
                this.TextToggleRow('标题', 'title')
                this.TextToggleRow('地点', 'place')
                Row() {
                  Blank()
                  Text('恢复默认排版')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .height(28)
                    .padding({ left: 8, right: 8 })
                    .textAlign(TextAlign.Center)
                    .onClick(() => {
                      this.pushHistory();
                      this.layoutData = serializeLayout(NoteLayout.defaults());
                    })
                }
                .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 10, bottom: 8 })
      }
      .width('100%')
      .height('88%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor($r('app.color.background_primary'))
      .borderRadius({ topLeft: StyleConstants.RADIUS_LG, topRight: 0, bottomLeft: 0, bottomRight: 0 })
    }
    .width('100%')
    .height('100%')
  }
}
