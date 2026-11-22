import { TimeTriggerPort } from '../contract/TimeTriggerPort';
import { ReminderNotificationPort } from '../contract/ReminderNotificationPort';
import { TriggerEventSink } from '../contract/TriggerEventSink';
import { ReminderAgentTimePort } from './ReminderAgentTimePort';
import { SystemNotificationPort } from './SystemNotificationPort';

/**
 * 系统级适配器工厂：给 app/AppBootstrap 组合根使用。
 *
 *   createAppServices({
 *     mode: AppRuntimeMode.INTEGRATED,
 *     repository, timetableRepository,
 *     createTimePort: createSystemTimePort,
 *     createLocationPort: <兰铮的位置适配器>,
 *     notificationPort: createSystemNotificationPort(),
 *     sceneResolver: <位置模块>,
 *     aiProvider, now, newId
 *   })
 *
 * 注意：时间提醒由系统提醒代理在到点时直接展示，不会回调 TriggerEventSink，
 * 因此时间提醒的状态不会自动变成 TRIGGERED。
 */
export function createSystemTimePort(_sink: TriggerEventSink): ReminderAgentTimePort {
  return new ReminderAgentTimePort();
}

export function createSystemNotificationPort(): ReminderNotificationPort {
  return new SystemNotificationPort();
}
