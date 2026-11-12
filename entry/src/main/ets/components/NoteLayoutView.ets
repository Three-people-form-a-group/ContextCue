import { NoteLayout, PartLayout, parseLayout, serializeLayout } from '../common/NoteLayoutModel';

const PART_TIME: string = 'time';
const PART_TITLE: string = 'title';
const PART_PLACE: string = 'place';

/**
 * 角标：圆心正好落在文字框的角上（一半在框外、一半压住框角）。
 * 因此组件不能有任何 padding / margin —— 位置坐标的原点必须就是框的左上角。
 */
const HANDLE_SIZE: number = 18;
const HANDLE_HALF: number = HANDLE_SIZE / 2;

/**
 * 便签的文字层：今日页只读，涂鸦弹层可编辑。
 *
 * 编辑交互：
 *   按下文字 → 选中（虚线框贴合文字实际大小）
 *   拖动文字 → 移动；拖右下角 ⤢ → 旋转/缩放；两指 → 缩放；左上角 × → 单独隐藏
 * 手势过程中的位移/缩放只更新组件内部状态，松手才回写，避免每帧重排导致的抖动。
 */
@Component
export struct NoteLayoutView {
  @Prop @Watch('syncFromProp') layoutData: string = '';
  @Prop time: string = '';
  @Prop title: string = '';
  @Prop place: string = '';
  @Prop featured: boolean = false;
  @Prop editable: boolean = false;
  /** 画笔/橡皮激活时，文字层不接收触摸，避免挡住画布 */
  @Prop textInteractive: boolean = true;
  @Prop entryNo: string = '';
  onChange: (data: string) => void = () => {};
  onSelectPart: (part: string) => void = () => {};

  @State local: NoteLayout = NoteLayout.defaults();
  @Prop activePart: string = '';
  @State sizeTime: number[] = [0, 0];
  @State sizeTitle: number[] = [0, 0];
  @State sizePlace: number[] = [0, 0];
  @State viewW: number = 300;
  @State viewH: number = 180;

  private dragging: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private startScale: number = 1;
  private startRot: number = 0;
  private halfW: number = 40;
  private halfH: number = 20;
  private baseDist: number = 1;
  private baseAngle: number = 0;
  // 角标拖拽用屏幕绝对坐标算，避免 offset 是否已随组件旋转带来的歧义
  private startGX: number = 0;
  private startGY: number = 0;
  private hasStartG: boolean = false;

  aboutToAppear(): void {
    this.local = parseLayout(this.layoutData);
  }

  syncFromProp(): void {
    if (!this.dragging) {
      this.local = parseLayout(this.layoutData);
    }
  }

  private part(name: string): PartLayout {
    if (name === PART_TITLE) {
      return this.local.title;
    }
    if (name === PART_PLACE) {
      return this.local.place;
    }
    return this.local.time;
  }

  private setPart(name: string, next: PartLayout): void {
    const clone: NoteLayout = this.local.clone();
    if (name === PART_TITLE) {
      clone.title = next;
    } else if (name === PART_PLACE) {
      clone.place = next;
    } else {
      clone.time = next;
    }
    this.local = clone;
  }

  private commit(): void {
    this.onChange(serializeLayout(this.local));
  }

  private partText(name: string): string {
    if (name === PART_TITLE) {
      return this.title;
    }
    if (name === PART_PLACE) {
      return this.place;
    }
    return this.time;
  }

  private fontSize(name: string): number {
    if (name === PART_TITLE) {
      return this.featured ? 26 : 24;
    }
    if (name === PART_PLACE) {
      return this.featured ? 12 : 14;
    }
    return this.featured ? 20 : 44;
  }

  private lineHeightOf(name: string): number {
    if (name === PART_TITLE) {
      return this.featured ? 34 : 32;
    }
    return 0;
  }

  private sizeOf(name: string): number[] {
    let size: number[] = this.sizeTime;
    if (name === PART_TITLE) {
      size = this.sizeTitle;
    } else if (name === PART_PLACE) {
      size = this.sizePlace;
    }
    if (size[0] <= 0 || size[1] <= 0) {
      return [80, 28];
    }
    return size;
  }

  private rememberSize(name: string, w: number, h: number): void {
    if (name === PART_TITLE) {
      this.sizeTitle = [w, h];
    } else if (name === PART_PLACE) {
      this.sizePlace = [w, h];
    } else {
      this.sizeTime = [w, h];
    }
    // 量到尺寸后把越界的位置拉回来：整块被纸边裁掉的话就再也点不到了
    if (this.editable && w > 0 && h > 0) {
      this.repairPosition(name);
    }
  }

  /** 至少留 10% 的宽度留在纸内，保证还能点中、拖回来 */
  private minX(name: string): number {
    const w: number = this.sizeOf(name)[0] * this.part(name).scale / Math.max(1, this.viewW);
    return Math.min(-0.05, 0.1 - w);
  }

  private maxX(): number {
    return 0.9;
  }

  /** y 是垂直中心：上下各留 10% 在纸内 */
  private minY(name: string): number {
    const h: number = this.sizeOf(name)[1] * this.part(name).scale / Math.max(1, this.viewH) / 2;
    return 0.1 - h;
  }

  private maxY(name: string): number {
    const h: number = this.sizeOf(name)[1] * this.part(name).scale / Math.max(1, this.viewH) / 2;
    return 0.9 + h;
  }

  private clampScale(v: number): number {
    return Math.max(0.4, Math.min(3, v));
  }

  private repairPosition(name: string): void {
    if (this.viewW <= 0 || this.viewH <= 0) {
      return;
    }
    const p: PartLayout = this.part(name);
    const nx: number = Math.max(this.minX(name), Math.min(this.maxX(), p.x));
    const ny: number = Math.max(this.minY(name), Math.min(this.maxY(name), p.y));
    if (Math.abs(nx - p.x) > 0.001 || Math.abs(ny - p.y) > 0.001) {
      const next: PartLayout = p.clone();
      next.x = nx;
      next.y = ny;
      this.setPart(name, next);
      this.commit();
    }
  }

  /** 记录手势起点（屏幕坐标）；个别版本 onActionStart 里 fingerList 还是空的，留给第一次 update 补 */
  private captureStart(event: GestureEvent): void {
    if (event.fingerList.length === 0) {
      return;
    }
    this.startGX = event.fingerList[0].globalX;
    this.startGY = event.fingerList[0].globalY;
    this.hasStartG = true;
  }

  private isActive(name: string): boolean {
    return this.editable && this.textInteractive && this.activePart === name;
  }

  @Builder
  PartInner(name: string) {
    // 整棵子树没有任何 padding / margin：Stack 的原点就是文字框左上角，
    // 角标 position 的 (-9,-9) / (W-9,H-9) 正好把圆心压在两个角上。
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Text(this.partText(name))
          .fontFamily(name === PART_TIME ? 'serif' : 'sans-serif')
          .fontSize(this.fontSize(name))
          .fontWeight(name === PART_PLACE ? FontWeight.Regular : 900)
          .fontColor($r('app.color.archive_ink'))
          .lineHeight(this.lineHeightOf(name))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 250 })
          .padding(3)
      }
      // 边框宽度恒定、只切颜色：选中/取消时组件尺寸不变，文字才不会位移
      .border({
        width: 1,
        color: this.isActive(name) ? $r('app.color.archive_ink') : Color.Transparent,
        style: BorderStyle.Dashed
      })
      .onAreaChange((_old: Area, area: Area) => {
        this.rememberSize(name, Number(area.width), Number(area.height));
      })

      if (this.isActive(name)) {
        // 角标放在一个"尺寸锁定为文字框"的叠层里：position 的子节点不参与叠层测量，
        // 组件尺寸就不会因为角标伸出而变大（否则选中/取消时文字会上下跳半个角标）。
        Stack({ alignContent: Alignment.TopStart }) {
          Text('×')
          .fontSize(13)
          .fontWeight(900)
          .fontColor($r('app.color.archive_paper'))
          .width(HANDLE_SIZE)
          .height(HANDLE_SIZE)
          .lineHeight(HANDLE_SIZE)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.archive_ink'))
          .borderRadius(HANDLE_HALF)
          .scale({ x: 1 / this.part(name).scale, y: 1 / this.part(name).scale })
          .position({ x: -HANDLE_HALF, y: -HANDLE_HALF })
          .responseRegion({
            x: -5,
            y: -5,
            width: HANDLE_SIZE + 10,
            height: HANDLE_SIZE + 10
          })
          .onClick(() => {
            const p: PartLayout = this.part(name).clone();
            p.hidden = true;
            this.setPart(name, p);
            this.commit();
            this.onSelectPart('');
          })

        Text('⤢')
          .fontSize(13)
          .fontWeight(900)
          .fontColor($r('app.color.archive_ink'))
          .width(HANDLE_SIZE)
          .height(HANDLE_SIZE)
          .lineHeight(HANDLE_SIZE)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.archive_paper'))
          .border({ width: 1, color: $r('app.color.archive_ink') })
          .borderRadius(HANDLE_HALF)
          .scale({ x: 1 / this.part(name).scale, y: 1 / this.part(name).scale })
          .position({
            x: this.sizeOf(name)[0] - HANDLE_HALF,
            y: this.sizeOf(name)[1] - HANDLE_HALF
          })
          .responseRegion({
            x: -5,
            y: -5,
            width: HANDLE_SIZE + 10,
            height: HANDLE_SIZE + 10
          })
          .gesture(
            // 阈值要小于文字拖动（4），否则父级 Pan 会先抢走，变成"只能位移"
            PanGesture({ distance: 1 })
              .onActionStart((event: GestureEvent) => {
                this.dragging = true;
                this.startScale = this.part(name).scale;
                this.startRot = this.part(name).rot;
                const size: number[] = this.sizeOf(name);
                this.halfW = Math.max(12, size[0] / 2);
                this.halfH = Math.max(12, size[1] / 2);
                this.baseDist = Math.sqrt(this.halfW * this.halfW + this.halfH * this.halfH);
                this.baseAngle = Math.atan2(this.halfH, this.halfW) * 180 / Math.PI;
                this.hasStartG = false;
                this.captureStart(event);
              })
              .onActionUpdate((event: GestureEvent) => {
                let dx: number = 0;
                let dy: number = 0;
                let haveGlobal: boolean = false;
                if (event.fingerList.length > 0) {
                  if (!this.hasStartG) {
                    this.captureStart(event);
                    return;
                  }
                  dx = event.fingerList[0].globalX - this.startGX;
                  dy = event.fingerList[0].globalY - this.startGY;
                  haveGlobal = true;
                }
                let vx: number = 0;
                let vy: number = 0;
                if (haveGlobal) {
                  const rad: number = this.startRot * Math.PI / 180;
                  const cos: number = Math.cos(rad);
                  const sin: number = Math.sin(rad);
                  // 屏幕位移 → 文字自己的坐标系：先转回去，再除掉当前缩放。
                  // 少了旋转，转过的块拖起来方向就是反的；少了除法，放大一次之后就会失控。
                  vx = this.halfW + (dx * cos + dy * sin) / this.startScale;
                  vy = this.halfH + (-dx * sin + dy * cos) / this.startScale;
                } else {
                  // 拿不到屏幕坐标的版本：退回 offset（它已随组件旋转）
                  vx = this.halfW + event.offsetX / this.startScale;
                  vy = this.halfH + event.offsetY / this.startScale;
                }
                const dist: number = Math.sqrt(vx * vx + vy * vy);
                const p: PartLayout = this.part(name).clone();
                p.scale = this.clampScale(this.startScale * (dist / this.baseDist));
                // 手指靠近框中心时角度不稳定，跳过旋转，避免突然翻 180°
                if (dist > this.baseDist * 0.25) {
                  const angle: number = Math.atan2(vy, vx) * 180 / Math.PI;
                  p.rot = this.startRot + (angle - this.baseAngle);
                }
                this.setPart(name, p);
              })
              .onActionEnd(() => {
                this.dragging = false;
                this.commit();
              })
              .onActionCancel(() => {
                this.dragging = false;
                this.commit();
              })
          )
        }
        .width(this.sizeOf(name)[0])
        .height(this.sizeOf(name)[1])
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
  }

  @Builder
  PartView(name: string) {
    if (this.partText(name) !== '' && !this.part(name).hidden) {
      if (this.editable && this.textInteractive) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 缩放/旋转放在内层：外层只负责位置，平移量不会跟着旋转/缩放跑偏
          Stack({ alignContent: Alignment.TopStart }) {
            this.PartInner(name)
          }
          .scale({ x: this.part(name).scale, y: this.part(name).scale })
          .rotate({ angle: this.part(name).rot })
        }
        .position({
          x: `${this.part(name).x * 100}%`,
          y: `${this.part(name).y * 100}%`
        })
        .translate({ x: '0%', y: '-50%' })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.onSelectPart(name);
          }
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture()
              .onAction(() => {
                this.onSelectPart(name);
              }),
            PanGesture({ distance: 4 })
              .onActionStart(() => {
                this.dragging = true;
                const p: PartLayout = this.part(name);
                this.startX = p.x;
                this.startY = p.y;
              })
              .onActionUpdate((event: GestureEvent) => {
                const p: PartLayout = this.part(name).clone();
                p.x = Math.max(this.minX(name),
                  Math.min(this.maxX(), this.startX + event.offsetX / this.viewW));
                p.y = Math.max(this.minY(name),
                  Math.min(this.maxY(name), this.startY + event.offsetY / this.viewH));
                this.setPart(name, p);
              })
              .onActionEnd(() => {
                this.dragging = false;
                this.commit();
              })
              .onActionCancel(() => {
                this.dragging = false;
                this.commit();
              }),
            PinchGesture()
              .onActionStart(() => {
                this.dragging = true;
                this.startScale = this.part(name).scale;
              })
              .onActionUpdate((event: GestureEvent) => {
                const p: PartLayout = this.part(name).clone();
                p.scale = this.clampScale(this.startScale * event.scale);
                this.setPart(name, p);
              })
              .onActionEnd(() => {
                this.dragging = false;
                this.commit();
              })
              .onActionCancel(() => {
                this.dragging = false;
                this.commit();
              })
          )
        )
      } else {
        // 只读 / 画笔激活：不挂任何手势，触摸留给画布和页面
        Stack({ alignContent: Alignment.TopStart }) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.PartInner(name)
          }
          .scale({ x: this.part(name).scale, y: this.part(name).scale })
          .rotate({ angle: this.part(name).rot })
        }
        .position({
          x: `${this.part(name).x * 100}%`,
          y: `${this.part(name).y * 100}%`
        })
        .translate({ x: '0%', y: '-50%' })
        .hitTestBehavior(HitTestMode.None)
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 空白处的点击只负责取消选中；文字块盖在它上面，所以点文字不会误取消
      if (this.editable && this.textInteractive) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            if (this.activePart !== '') {
              this.onSelectPart('');
            }
          })
      }
      this.PartView(PART_TIME)
      this.PartView(PART_TITLE)
      this.PartView(PART_PLACE)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.viewW = Number(area.width);
      this.viewH = Number(area.height);
    })
    .hitTestBehavior(this.editable && this.textInteractive
      ? HitTestMode.Default
      : HitTestMode.None)
  }
}
