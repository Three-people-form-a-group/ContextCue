/**
 * 手账模式下的纸张样式。
 * 每条事项可以挑一张纸，今日页把它渲染成一张便签。
 * 这里只定义"纸"，不负责任何业务字段。
 */
export class PaperStyle {
  static readonly BINDER_GRID: string = 'binder_grid';
  static readonly COTTON_LILAC: string = 'cotton_lilac';
  static readonly DOT_INDEX: string = 'dot_index';
  static readonly GRID_TORN: string = 'grid_torn';
  static readonly KRAFT: string = 'kraft';
  static readonly WARM_WHITE: string = 'warm_white';
  static readonly LEDGER: string = 'ledger';
  static readonly LETTER_RULED: string = 'letter_ruled';
  static readonly RULED_WHITE: string = 'ruled_white';
  static readonly NEWSPRINT: string = 'newsprint_blank';
  static readonly LARGE_WARM: string = 'large_warm_white';

  /** 全部可用纸张（都是浅色纸，文字统一用深墨） */
  static all(): string[] {
    return [
      PaperStyle.LARGE_WARM,
      PaperStyle.KRAFT,
      PaperStyle.RULED_WHITE,
      PaperStyle.GRID_TORN,
      PaperStyle.COTTON_LILAC,
      PaperStyle.DOT_INDEX,
      PaperStyle.BINDER_GRID,
      PaperStyle.LEDGER,
      PaperStyle.LETTER_RULED,
      PaperStyle.NEWSPRINT
    ];
  }

  static label(paper: string): string {
    if (paper === PaperStyle.BINDER_GRID) {
      return '六孔网格活页';
    }
    if (paper === PaperStyle.COTTON_LILAC) {
      return '灰紫棉纸';
    }
    if (paper === PaperStyle.DOT_INDEX) {
      return '点阵索引卡';
    }
    if (paper === PaperStyle.GRID_TORN) {
      return '斜撕网格纸';
    }
    if (paper === PaperStyle.KRAFT) {
      return '牛皮便签';
    }
    if (paper === PaperStyle.LEDGER) {
      return '旧账簿纸';
    }
    if (paper === PaperStyle.LETTER_RULED) {
      return '三线信笺';
    }
    if (paper === PaperStyle.RULED_WHITE) {
      return '横线笔记纸';
    }
    if (paper === PaperStyle.NEWSPRINT) {
      return '无字报纸';
    }
    return '暖白手账纸';
  }

  static resource(paper: string): Resource {
    if (paper === PaperStyle.BINDER_GRID) {
      return $r('app.media.journal_paper_binder_grid');
    }
    if (paper === PaperStyle.COTTON_LILAC) {
      return $r('app.media.journal_paper_cotton_lilac');
    }
    if (paper === PaperStyle.DOT_INDEX) {
      return $r('app.media.journal_paper_dot_index');
    }
    if (paper === PaperStyle.GRID_TORN) {
      return $r('app.media.journal_paper_grid_torn');
    }
    if (paper === PaperStyle.KRAFT) {
      return $r('app.media.journal_paper_kraft_blank');
    }
    if (paper === PaperStyle.LEDGER) {
      return $r('app.media.journal_paper_ledger');
    }
    if (paper === PaperStyle.LETTER_RULED) {
      return $r('app.media.journal_paper_letter_ruled');
    }
    if (paper === PaperStyle.RULED_WHITE) {
      return $r('app.media.journal_paper_ruled_white');
    }
    if (paper === PaperStyle.NEWSPRINT) {
      return $r('app.media.journal_paper_newsprint_blank');
    }
    return $r('app.media.journal_paper_large_warm_white');
  }

  /** 目前所有纸都是浅色，字统一深墨 */
  static isDark(paper: string): boolean {
    return false;
  }

  /** 没选过纸时按 id 稳定分配一张，保证同一条事项每次都是同一张纸 */
  static defaultFor(id: string): string {
    const list: string[] = PaperStyle.all();
    let sum: number = 0;
    for (let i = 0; i < id.length; i++) {
      sum += id.charCodeAt(i);
    }
    return list[sum % list.length];
  }
}
