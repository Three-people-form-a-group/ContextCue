/**
 * UI 占位语义常量：取值严格对齐《ContextCue 公共架构与 AI 模块开发规范 v1.0》§5.1 的枚举值，
 * 仅用于 UI 骨架阶段的占位数据与展示判断。这不是团队公共模型；公共 model 目录冻结后
 * （model/ReminderEnums.ets 中的 TriggerType / ReminderSource / ReminderStatus / LocationTriggerMode）
 * 由正式枚举整体替换本文件。
 *
 * 规范 v1.0：阶段 1 地点触发仅支持 ENTER，EXIT 仅作为公共模型预留、不允许正式激活。
 * 因此 UiLocationTriggerMode 保留 EXIT 常量，但 UI 阶段不会用它创建提醒。
 */
export class UiTriggerType {
  static readonly TIME: string = 'TIME';
  static readonly LOCATION: string = 'LOCATION';
  static readonly BOTH: string = 'BOTH';
}

export class UiReminderSource {
  static readonly MANUAL: string = 'MANUAL';
  static readonly AI: string = 'AI';
}

export class UiReminderStatus {
  static readonly ACTIVE: string = 'ACTIVE';
  static readonly TRIGGERED: string = 'TRIGGERED';
  static readonly COMPLETED: string = 'COMPLETED';
  static readonly DISABLED: string = 'DISABLED';
}

export class UiLocationTriggerMode {
  static readonly ENTER: string = 'ENTER';
  static readonly EXIT: string = 'EXIT';
}
