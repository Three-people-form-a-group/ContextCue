import { ReminderCardData } from '../components/ReminderCard';

/**
 * Navigation 组件导航体系的路由名称与页面参数。
 * 本工程仅使用 Navigation/NavPathStack 组件导航，不使用 router 多页面路由。
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

/**
 * 详情页导航参数：承载整张卡片的展示数据（UI 骨架阶段的轻量导航参数，
 * 不是团队公共 Reminder 数据模型）。接入 ReminderService 后改为仅传 reminderId，
 * 由详情页通过服务按 id 查询真实数据。
 */
export class ReminderDetailNavParam {
  readonly data: ReminderCardData;

  constructor(data: ReminderCardData) {
    this.data = data;
  }
}

/**
 * 编辑页导航参数：mode 取 RouterConstants.EDIT_MODE_CREATE / EDIT_MODE_EDIT。
 * data 仅在编辑模式下传入，用于把原始提醒带入表单（时间、内容等）。
 * 这是 UI 骨架阶段的轻量导航参数，不是团队公共 Reminder 数据模型。
 */
export class ReminderEditNavParam {
  readonly mode: string;
  readonly data?: ReminderCardData;
  /** 从草稿箱进入时带上草稿键，编辑页据此恢复并更新同一条草稿 */
  readonly draftKey?: string;

  constructor(mode: string, data?: ReminderCardData, draftKey?: string) {
    this.mode = mode;
    this.data = data;
    this.draftKey = draftKey;
  }
}
