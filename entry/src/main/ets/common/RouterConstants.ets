/**
 * Navigation 组件导航体系的路由名称与页面参数。
 * 本工程仅使用 Navigation/NavPathStack 组件导航，不使用 router 多页面路由。
 *
 * 接入公共层后导航参数只带 id：详情页与编辑页用 ReminderService.findById(id) 取最新数据，
 * 不把整份提醒塞进导航参数，避免页面显示编辑前的旧快照。
 */
export class RouterConstants {
  static readonly PAGE_REMINDER_DETAIL: string = 'reminderDetail';
  static readonly PAGE_REMINDER_EDIT: string = 'reminderEdit';
  /** 设置页：由首页右上角齿轮进入，不再作为底部 Tab */
  static readonly PAGE_SETTINGS: string = 'settings';
  /** 草稿箱 */
  static readonly PAGE_DRAFT_LIST: string = 'draftList';
  static readonly EDIT_MODE_CREATE: string = 'create';
  static readonly EDIT_MODE_EDIT: string = 'edit';
}

/** 详情页导航参数：只带 reminderId */
export class ReminderDetailNavParam {
  readonly id: string;

  constructor(id: string) {
    this.id = id;
  }
}

/**
 * 编辑页导航参数：mode 取 RouterConstants.EDIT_MODE_CREATE / EDIT_MODE_EDIT。
 * id 仅在编辑模式下传入；页面按 id 查询最新提醒再填表。
 */
export class ReminderEditNavParam {
  readonly mode: string;
  readonly id: string;
  /** 从草稿箱进入时带上草稿键，编辑页据此恢复并更新同一条草稿 */
  readonly draftKey?: string;

  constructor(mode: string, id: string = '', draftKey?: string) {
    this.mode = mode;
    this.id = id;
    this.draftKey = draftKey;
  }
}
