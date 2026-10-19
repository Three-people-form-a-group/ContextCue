import { ReminderCardData } from '../components/ReminderCard';
import { UiReminderStatus, UiTriggerType, UiReminderSource, UiLocationTriggerMode } from './UiReminderSemantics';

/**
 * 占位数据（Mock）：仅用于 UI 骨架阶段展示页面结构与视觉效果。
 * 字段与取值对齐《ContextCue 公共架构与 AI 模块开发规范 v1.0》§5 的 Reminder 模型：
 *   - 字段：content / triggerType / source / status / triggerTime / sceneId / sceneName / locationTriggerMode
 *   - 枚举值对齐 §5.1：TriggerType、ReminderSource、ReminderStatus、LocationTriggerMode
 *   - 遵循 §5.4 不变量：TIME 不携带地点字段；LOCATION 不携带 triggerTime；BOTH 同时具备时间与地点字段
 * triggerTime 为 Unix Epoch 毫秒值；LOCATION 项不传 triggerTime（undefined）。
 * 不代表真实业务数据，也不是团队公共数据结构；接入真实数据源后整体删除本文件。
 */
function atHourToday(hour: number, minute: number): number {
  const d: Date = new Date();
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

function atDayOffset(offsetDays: number, hour: number, minute: number): number {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

export class ReminderGroupData {
  readonly groupOverline: string;
  readonly groupLabel: string;
  readonly items: ReminderCardData[];

  constructor(groupOverline: string, groupLabel: string, items: ReminderCardData[]) {
    this.groupOverline = groupOverline;
    this.groupLabel = groupLabel;
    this.items = items;
  }
}

export class MockReminderData {
  static readonly TODAY_ACTIVE: ReminderCardData[] = [
    new ReminderCardData('today-1', '团队周会：同步 ContextCue 开发进度',
      UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atHourToday(9, 30)),
    new ReminderCardData('today-2', '给 UI 评审准备导航骨架截图',
      UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atHourToday(14, 0)),
    new ReminderCardData('today-3', '到达实验室后同步今日进展',
      UiTriggerType.LOCATION, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE,
      undefined, 'scene-lab', '实验室', UiLocationTriggerMode.ENTER),
    new ReminderCardData('today-4', '晚上 8 点到家后复盘周会纪要',
      UiTriggerType.BOTH, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE,
      atHourToday(20, 0), 'scene-home', '家', UiLocationTriggerMode.ENTER)
  ];

  static readonly TODAY_DONE: ReminderCardData[] = [
    new ReminderCardData('today-5', '回复队友关于路由方案的问题',
      UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.COMPLETED, atHourToday(8, 15))
  ];

  static readonly ALL_GROUPS: ReminderGroupData[] = [
    new ReminderGroupData('TODAY', '今天', [
      new ReminderCardData('today-1', '团队周会：同步 ContextCue 开发进度',
        UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atHourToday(9, 30)),
      new ReminderCardData('today-2', '给 UI 评审准备导航骨架截图',
        UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atHourToday(14, 0)),
      new ReminderCardData('today-3', '到达实验室后同步今日进展',
        UiTriggerType.LOCATION, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE,
        undefined, 'scene-lab', '实验室', UiLocationTriggerMode.ENTER),
      new ReminderCardData('today-4', '晚上 8 点到家后复盘周会纪要',
        UiTriggerType.BOTH, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE,
        atHourToday(20, 0), 'scene-home', '家', UiLocationTriggerMode.ENTER)
    ]),
    new ReminderGroupData('TOMORROW', '明天', [
      new ReminderCardData('tomorrow-1', '提交 UI 骨架 PR 到 develop 分支',
        UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atDayOffset(1, 10, 0)),
      new ReminderCardData('tomorrow-2', '预约牙医复诊',
        UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atDayOffset(1, 16, 30)),
      // 此条为 AI 自然语言解析来源的占位示例，用于展示 source 字段的两种取值。
      new ReminderCardData('tomorrow-3', '到图书馆后归还参考书',
        UiTriggerType.LOCATION, UiReminderSource.AI, UiReminderStatus.ACTIVE,
        undefined, 'scene-library', '图书馆', UiLocationTriggerMode.ENTER)
    ]),
    new ReminderGroupData('LATER', '本周稍后', [
      new ReminderCardData('later-1', '整理本阶段视觉走查清单',
        UiTriggerType.TIME, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE, atDayOffset(2, 18, 0)),
      new ReminderCardData('later-2', '晚饭后到家整理实验数据',
        UiTriggerType.BOTH, UiReminderSource.MANUAL, UiReminderStatus.ACTIVE,
        atDayOffset(2, 19, 30), 'scene-home', '家', UiLocationTriggerMode.ENTER)
    ])
  ];
}
