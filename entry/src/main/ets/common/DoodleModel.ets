/**
 * 涂鸦笔迹的模型与序列化。
 *
 * 一根笔画：颜色 + 线宽（相对 300vp 宽度的比例）+ 归一化坐标点。
 * 归一化之后，同一条笔迹在便签缩略图和全屏画布上都能等比还原。
 */
/** 笔型：钢笔 / 铅笔 / 马克笔 / 荧光笔 */
export class PenStyle {
  static readonly PEN: string = 'pen';
  static readonly PENCIL: string = 'pencil';
  static readonly MARKER: string = 'marker';
  static readonly HIGHLIGHTER: string = 'highlighter';

  static all(): string[] {
    return [PenStyle.PEN, PenStyle.PENCIL, PenStyle.MARKER, PenStyle.HIGHLIGHTER];
  }

  static label(style: string): string {
    if (style === PenStyle.PENCIL) {
      return '铅笔';
    }
    if (style === PenStyle.MARKER) {
      return '马克笔';
    }
    if (style === PenStyle.HIGHLIGHTER) {
      return '荧光笔';
    }
    return '钢笔';
  }

  /** 线宽倍数、透明度、笔帽形状 */
  static widthFactor(style: string): number {
    if (style === PenStyle.HIGHLIGHTER) {
      return 3.2;
    }
    if (style === PenStyle.MARKER) {
      return 1.9;
    }
    if (style === PenStyle.PENCIL) {
      return 0.75;
    }
    return 1;
  }

  static alpha(style: string): number {
    if (style === PenStyle.HIGHLIGHTER) {
      return 0.35;
    }
    if (style === PenStyle.MARKER) {
      return 0.85;
    }
    if (style === PenStyle.PENCIL) {
      return 0.7;
    }
    return 1;
  }
}

export class DoodleStroke {
  readonly color: string;
  /** 线宽（vp，按 300vp 参考宽度定义） */
  readonly width: number;
  readonly penStyle: string;
  /** 归一化坐标：[x0,y0,x1,y1,...]，取值 0~1 */
  readonly points: number[];

  constructor(color: string, width: number, points: number[], penStyle: string = PenStyle.PEN) {
    this.color = color;
    this.width = width;
    this.penStyle = penStyle;
    this.points = points;
  }
}

/** 参考宽度：笔迹线宽按这个宽度下的 vp 值记录 */
export const DOODLE_REF_WIDTH: number = 300;

export function serializeDoodle(strokes: DoodleStroke[]): string {
  let out: string = '';
  for (let i = 0; i < strokes.length; i++) {
    const s: DoodleStroke = strokes[i];
    if (s.points.length < 2) {
      continue;
    }
    if (out !== '') {
      out += ';';
    }
    out += `${s.color}|${s.width}|${s.penStyle}|`;
    for (let p = 0; p + 1 < s.points.length; p += 2) {
      if (p > 0) {
        out += ' ';
      }
      out += `${Math.round(s.points[p] * 10000) / 10000},${Math.round(s.points[p + 1] * 10000) / 10000}`;
    }
  }
  return out;
}

export function parseDoodle(data: string): DoodleStroke[] {
  const out: DoodleStroke[] = [];
  if (data === '') {
    return out;
  }
  const strokes: string[] = data.split(';');
  for (let i = 0; i < strokes.length; i++) {
    const head: string = strokes[i];
    if (head === '') {
      continue;
    }
    const parts: string[] = head.split('|');
    if (parts.length < 3) {
      continue;
    }
    // 兼容旧格式：color|width|points（无笔型）
    const hasStyle: boolean = parts.length >= 4;
    const width: number = parseFloat(parts[1]);
    const penStyle: string = hasStyle ? parts[2] : PenStyle.PEN;
    const points: number[] = [];
    const pairs: string[] = (hasStyle ? parts[3] : parts[2]).split(' ');
    for (let p = 0; p < pairs.length; p++) {
      const xy: string[] = pairs[p].split(',');
      if (xy.length !== 2) {
        continue;
      }
      const x: number = parseFloat(xy[0]);
      const y: number = parseFloat(xy[1]);
      if (Number.isNaN(x) || Number.isNaN(y)) {
        continue;
      }
      points.push(x);
      points.push(y);
    }
    if (points.length >= 2) {
      out.push(new DoodleStroke(parts[0], Number.isNaN(width) ? 2 : width, points, penStyle));
    }
  }
  return out;
}
