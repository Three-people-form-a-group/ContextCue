/**
 * 全局设计常量：间距、字号、字距、圆角与关键布局尺寸。
 * 颜色不在代码中定义，统一由 resources/base/element/color.json 的语义资源管理。
 */
export class StyleConstants {
  // 间距（vp）
  static readonly SPACE_XS: number = 4;
  static readonly SPACE_SM: number = 8;
  static readonly SPACE_MD: number = 12;
  static readonly SPACE_LG: number = 16;
  static readonly SPACE_XL: number = 24;
  static readonly SPACE_XXL: number = 32;
  static readonly SPACE_XXXL: number = 44;

  // 字号（fp）
  static readonly FONT_DISPLAY_XL: number = 56;
  static readonly FONT_DISPLAY: number = 38;
  static readonly FONT_TIME_DISPLAY: number = 48;
  static readonly FONT_TITLE_LG: number = 28;
  static readonly FONT_TITLE: number = 20;
  static readonly FONT_BODY: number = 16;
  static readonly FONT_BODY_SM: number = 14;
  static readonly FONT_CAPTION: number = 12;

  // 字距（fp）：小标签（overline）统一字距
  static readonly LETTER_SPACING_OVERLINE: number = 3;

  // 圆角（vp）
  static readonly RADIUS_SM: number = 6;
  static readonly RADIUS_MD: number = 12;
  static readonly RADIUS_LG: number = 20;

  // 布局尺寸（vp）
  static readonly PAGE_PADDING_H: number = 20;
  static readonly TOP_BAR_HEIGHT: number = 56;
  static readonly TAB_BAR_HEIGHT: number = 64;
  static readonly TOUCH_TARGET_MIN: number = 44;
  static readonly HAIRLINE_HEIGHT: number = 1;

  // 时间轴（vp）：页面左侧的纵向时间轴。"分段"而非连续——段与段之间的空隙语义为"时间之间的等待"。
  static readonly AXIS_WIDTH: number = 26;
  static readonly AXIS_SEGMENT: number = 20;
  static readonly AXIS_NODE: number = 9;
  static readonly AXIS_NODE_FOCUS: number = 13;

  // 怀表母题（vp）
  static readonly DIAL_HEADER: number = 132;
  static readonly DIAL_EMPTY: number = 72;
  /** 辅助怀表符号：出现在统计行左侧，与右上角的水獭角色分开，避免争夺焦点 */
  static readonly DIAL_ACCESSORY: number = 44;

  // 水獭角色插槽（vp）
  /** 报头中水獭的显示宽度；高度由原图宽高比推导 */
  static readonly OTTER_HEADER: number = 136;
  /** 空状态中的水獭 */
  static readonly OTTER_EMPTY: number = 72;

  // 时间差映射（vp）：对数压缩，长间隔有上限，避免把后续内容推出屏幕。
  // visualGap = clamp(BASE + K * ln(1 + minutes / 60), MIN, MAX)
  static readonly GAP_BASE: number = 14;
  static readonly GAP_K: number = 24;
  static readonly GAP_MIN: number = 14;
  static readonly GAP_MAX: number = 92;

  // 纸片错位（vp）：不同版式角色之间的水平偏移，制造反网格
  static readonly SLIP_INDENT: number = 8;
  static readonly SLIP_INDENT_BARE: number = 12;
  static readonly SLIP_INDENT_ARCHIVE: number = 24;
  /** 窄边注纸片的宽度占比 */
  static readonly SLIP_NARROW_WIDTH: string = '68%';

  // ===== Temporal Gazette 版式 token =====
  /** 报纸分隔线：粗 / 中 / 细（细线复用 HAIRLINE_HEIGHT=1vp） */
  static readonly RULE_HEAVY: number = 2;
  static readonly RULE_MEDIUM: number = 1.5;
  /** 栏目之间的留白 */
  static readonly SPACE_SECTION: number = 28;
  /** 分隔线与文字之间的呼吸 */
  static readonly SPACE_RULE_GAP: number = 10;
  /** 报头刊名高度 */
  static readonly MASTHEAD_HEIGHT: number = 44;
  /** 头版大时间 */
  static readonly FONT_HEADLINE_TIME: number = 72;
  /** 栏目标题（FORM / 01 这类编号） */
  static readonly FONT_SECTION_INDEX: number = 11;
  /** 报头中文主标题 */
  static readonly FONT_MASTHEAD_TITLE: number = 44;
  /** 报头水獭宽度（比首版更紧凑） */
  static readonly OTTER_MASTHEAD: number = 104;
  /** 报头辅助怀表 */
  static readonly DIAL_MASTHEAD: number = 30;

  // ===== 拼贴纸张（vp）=====
  /** 底纸相对主纸的错位量 */
  static readonly PAPER_UNDER_OFFSET: number = 5;
  /** 纸片切角尺寸 */
  static readonly PAPER_CUT: number = 14;
  /** 短栏线的长度占比（有意中断，不铺满整行） */
  static readonly RULE_SHORT_WIDTH: string = '62%';
  /**
   * 无纸面时间栏的栅格宽度。
   * 必须容纳 30fp 的完整 HH:mm（"16:30" 约 78vp），并与标题列彻底分开。
   */
  static readonly EDITORIAL_TIME_GUTTER: number = 92;
  /** 无纸面版式的时间字号：保证完整显示 HH:mm，同时保持编辑式的大字号 */
  static readonly FONT_EDITORIAL_TIME: number = 30;

  // ===== 时间长卷（vp）=====
  /** 时间轴左侧时间栏宽度，容纳 24fp 的 HH:mm */
  static readonly TIMELINE_TIME_GUTTER: number = 72;
  /** 时间轴节点标记列 */
  static readonly TIMELINE_MARK_WIDTH: number = 18;
  /** 情境色块中的地点名字号 */
  static readonly FONT_FIELD_NAME: number = 24;
  /** 编辑台主输入（提醒内容）字号 */
  static readonly FONT_FORM_TITLE: number = 30;
}
