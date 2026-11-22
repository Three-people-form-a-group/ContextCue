import { DoodleStroke, PenStyle, parseDoodle, DOODLE_REF_WIDTH } from '../common/DoodleModel';

/**
 * 只读的涂鸦层：把归一化笔迹画到便签上。
 * 不接收触摸（hitTestBehavior None），点击仍然落到便签本身。
 */
@Component
export struct DoodleView {
  data: string = '';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.draw();
      })
  }

  private draw(): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, w, h);
    const strokes: DoodleStroke[] = parseDoodle(this.data);
    const scale: number = w / DOODLE_REF_WIDTH;
    for (let i = 0; i < strokes.length; i++) {
      const s: DoodleStroke = strokes[i];
      if (s.points.length < 2) {
        continue;
      }
      const flat: boolean = s.penStyle === PenStyle.MARKER || s.penStyle === PenStyle.HIGHLIGHTER;
      this.ctx.beginPath();
      this.ctx.strokeStyle = s.color;
      this.ctx.globalAlpha = PenStyle.alpha(s.penStyle);
      this.ctx.lineWidth = Math.max(0.6, s.width * PenStyle.widthFactor(s.penStyle) * scale);
      this.ctx.lineCap = flat ? 'butt' : 'round';
      this.ctx.lineJoin = 'round';
      this.ctx.moveTo(s.points[0] * w, s.points[1] * h);
      for (let p = 2; p + 1 < s.points.length; p += 2) {
        this.ctx.lineTo(s.points[p] * w, s.points[p + 1] * h);
      }
      this.ctx.stroke();
      this.ctx.globalAlpha = 1;
    }
    this.ctx.closePath();
  }
}
