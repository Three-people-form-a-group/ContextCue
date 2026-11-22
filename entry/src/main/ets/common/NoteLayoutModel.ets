/**
 * 便签文字的排版位置（时间 / 标题 / 地点三块各自独立）。
 *
 * 位置用相对纸张的归一化中心点记录：x、y 取 0~1，
 * 缩放 1 为默认大小，旋转角度单位为度。三块互不影响，可各自隐藏。
 */
export class PartLayout {
  x: number;
  y: number;
  scale: number;
  rot: number;
  hidden: boolean;

  constructor(x: number, y: number, scale: number, rot: number, hidden: boolean) {
    this.x = x;
    this.y = y;
    this.scale = scale;
    this.rot = rot;
    this.hidden = hidden;
  }

  clone(): PartLayout {
    return new PartLayout(this.x, this.y, this.scale, this.rot, this.hidden);
  }
}

export class NoteLayout {
  time: PartLayout;
  title: PartLayout;
  place: PartLayout;

  constructor(time: PartLayout, title: PartLayout, place: PartLayout) {
    this.time = time;
    this.title = title;
    this.place = place;
  }

  /** 默认位置：复刻现在便签的排版观感 */
  static defaults(): NoteLayout {
    return new NoteLayout(
      new PartLayout(0.12, 0.19, 1, 0, false),
      new PartLayout(0.12, 0.55, 1, 0, false),
      new PartLayout(0.12, 0.85, 1, 0, false)
    );
  }

  clone(): NoteLayout {
    return new NoteLayout(this.time.clone(), this.title.clone(), this.place.clone());
  }
}

export function serializeLayout(layout: NoteLayout): string {
  const one = (p: PartLayout): string =>
    `${p.x.toFixed(3)},${p.y.toFixed(3)},${p.scale.toFixed(2)},${p.rot.toFixed(1)},${p.hidden ? 1 : 0}`;
  return `time:${one(layout.time)}|title:${one(layout.title)}|place:${one(layout.place)}`;
}

export function parseLayout(data: string): NoteLayout {
  const layout: NoteLayout = NoteLayout.defaults();
  if (data === '') {
    return layout;
  }
  const parts: string[] = data.split('|');
  for (let i = 0; i < parts.length; i++) {
    const kv: string[] = parts[i].split(':');
    if (kv.length !== 2) {
      continue;
    }
    const nums: string[] = kv[1].split(',');
    if (nums.length < 5) {
      continue;
    }
    const parsed: PartLayout = new PartLayout(
      parseFloat(nums[0]),
      parseFloat(nums[1]),
      parseFloat(nums[2]),
      parseFloat(nums[3]),
      nums[4] === '1'
    );
    if (kv[0] === 'time') {
      layout.time = parsed;
    } else if (kv[0] === 'title') {
      layout.title = parsed;
    } else if (kv[0] === 'place') {
      layout.place = parsed;
    }
  }
  return layout;
}
