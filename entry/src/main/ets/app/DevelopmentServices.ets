import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { OhosAIChatClient } from '../ai/provider/OhosAIChatClient';
import { ZhipuAIModelProvider } from '../ai/provider/ZhipuAIModelProvider';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Reminder } from '../model/Reminder';
import { InMemoryReminderRepository } from '../repository/InMemoryReminderRepository';
import { InMemoryTimetableRepository } from '../timetable/repository/InMemoryTimetableRepository';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../reminder/contract/ReminderNotificationPort';
import { SceneResolver, SceneResolveResult, SceneResolveStatus } from '../reminder/contract/SceneResolver';
import { TriggerEventSink } from '../reminder/contract/TriggerEventSink';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';

// 开发联调内置样例：让页面在无真实 Key 时联调 AI 三态展示（READY/待确认/FAILED）。
// 时间用 epoch 数字格式（解析器兼容路径），构造时动态计算以保持恒为未来。
export function buildDevFixtures(): Map<string, string> {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  tomorrow.setHours(14, 0, 0, 0);
  const fixtures = new Map<string, string>();
  fixtures.set('明天下午两点提醒我提交实验报告',
    '{"content":"提交实验报告","triggerType":"TIME","triggerTime":' + tomorrow.getTime().toString() + ',"sceneName":null,"ambiguous":false}');
  fixtures.set('到实验室时提醒我把实验数据拷贝到服务器',
    '{"content":"把实验数据拷贝到服务器","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}');
  fixtures.set('明天下午两点去实验室，提醒我带电脑',
    '{"content":"带电脑","triggerType":"BOTH","triggerTime":' + tomorrow.getTime().toString() + ',"sceneName":"实验室","ambiguous":true}');
  fixtures.set('提醒我买礼物',
    '{"content":"买礼物","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}');
  fixtures.set('讲个笑话', '{broken');
  return fixtures;
}

// Development-only no-op registration: supports page CRUD, never schedules a system reminder.
class DevelopmentTimePort implements TimeTriggerPort {
  async schedule(_reminder: Reminder): Promise<void> {}
  async cancel(_id: string): Promise<void> {}
}

class DevelopmentLocationPort implements LocationTriggerPort, SceneResolver {
  async register(_reminder: Reminder): Promise<void> {}
  async unregister(_id: string): Promise<void> {}
  async isInsideScene(_sceneId: string): Promise<boolean> { return false; }
  async resolveByName(sceneName: string): Promise<SceneResolveResult> {
    // 开发桩：认识两个场景名，让 LOCATION/BOTH 的 READY 流程可联调
    if (sceneName === '实验室') {
      return { status: SceneResolveStatus.RESOLVED, match: { id: 'dev-lab', name: sceneName }, candidates: [] };
    }
    if (sceneName === '家') {
      return { status: SceneResolveStatus.RESOLVED, match: { id: 'dev-home', name: sceneName }, candidates: [] };
    }
    return { status: SceneResolveStatus.NOT_FOUND, candidates: [] };
  }
}

class UnavailableNotificationPort implements ReminderNotificationPort {
  async notify(_reminder: Reminder): Promise<void> {
    // Never claim a real notification was delivered by a placeholder.
    throw new Error('SYSTEM_NOTIFICATION_NOT_CONNECTED');
  }
}

/**
 * Development composition: volatile data, no triggers/notifications.
 * config 提供时注入阶段性真实 Provider（智谱 GLM）；缺省保持 Fake（含联调样例）。
 */
export function createDevelopmentServices(config?: AIProviderConfig): AppServices {
  const location = new DevelopmentLocationPort();
  let sequence = 0;
  const services = createAppServices({
    mode: AppRuntimeMode.DEVELOPMENT,
    repository: new InMemoryReminderRepository(),
    timetableRepository: new InMemoryTimetableRepository(),
    createTimePort: (_sink: TriggerEventSink): TimeTriggerPort => new DevelopmentTimePort(),
    createLocationPort: (_sink: TriggerEventSink): LocationTriggerPort => location,
    notificationPort: new UnavailableNotificationPort(),
    sceneResolver: location,
    // No canned interpretation of arbitrary input except the dev fixtures above.
    aiProvider: config === undefined
      ? new FakeAIModelProvider(buildDevFixtures())
      : new ZhipuAIModelProvider(config, new OhosAIChatClient()),
    now: () => Date.now(),
    newId: () => 'dev-' + Date.now().toString() + '-' + (++sequence).toString()
  });
  hilog.info(0x0000, 'ContextCue', 'AI provider: %{public}s',
    config === undefined ? 'Fake(dev fixtures)' : 'Zhipu(GLM)');
  return services;
}
