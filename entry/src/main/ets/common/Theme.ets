import { UiMode } from './UiMode';

/**
 * 按模式返回颜色。
 *
 * 极简模式：冷灰白底 + 近黑字 + 一条浅灰分隔线，几乎不用彩色；
 * 手账模式：沿用拼贴色板（$r 资源）。
 *
 * 用法：组件里先 `@StorageLink('uiMode') uiMode: string`，
 * 再把颜色写成 `Theme.text(this.uiMode)`，模式切换时页面会重绘。
 */
export class Theme {
  // ---------- 极简模式色值 ----------
  private static readonly MIN_BG: string = '#F7F7F5';
  private static readonly MIN_SURFACE: string = '#FFFFFF';
  private static readonly MIN_TEXT: string = '#1F2328';
  private static readonly MIN_SUB: string = '#6B7280';
  private static readonly MIN_RULE: string = '#E5E7EB';
  private static readonly MIN_ACCENT: string = '#1F2328';

  static isMinimal(mode: string): boolean {
    return UiMode.isMinimal(mode);
  }

  /** 页面画布 */
  static bg(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_BG : $r('app.color.background_primary');
  }

  /** 卡片 / 纸面 */
  static surface(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_SURFACE : $r('app.color.surface_primary');
  }

  /** 主文字 */
  static text(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_TEXT : $r('app.color.text_primary');
  }

  /** 次级文字 */
  static sub(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_SUB : $r('app.color.text_secondary');
  }

  /** 分隔线 / 细线 */
  static rule(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_RULE : $r('app.color.archive_rule');
  }

  /** 强调：极简模式下不用彩色，直接用近黑 */
  static accent(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_ACCENT : $r('app.color.accent_primary');
  }

  /** 次级底色（块、留白带） */
  static subtleBg(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? '#F3F4F6' : $r('app.color.surface_secondary');
  }

  /** 弱强调块（标签底、次级底色） */
  static accentSoft(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? '#EFF1F3' : $r('app.color.accent_mustard');
  }

  /** 提醒色：极简模式用更深的橙，作为唯一的"需要处理"信号 */
  static alert(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? '#C2410C' : $r('app.color.accent_primary');
  }

  /** 标题色：手账用午夜蓝，极简用近黑 */
  static ink(mode: string): ResourceColor {
    return Theme.isMinimal(mode) ? Theme.MIN_TEXT : $r('app.color.brand_primary');
  }
}
