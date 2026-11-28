import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { initializeAppServices } from '../app/AppBootstrap';
import { reconcileOnAppForeground } from '../app/IntegratedServices';
import { readLocalAIProviderConfig } from '../ai/provider/LocalAIConfigReader';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 冷启动由提醒通知拉起时，先把目标提醒交给页面（Index 消费后清空）
    this.routeFromWant(want);
    // 本地配置（沙箱 files/ai.config.local.json）存在则启用真实 Provider，否则 Fake。
    const aiConfig = readLocalAIProviderConfig(this.context.filesDir);
    const services = initializeAppServices(aiConfig, this.context);
    hilog.info(DOMAIN, 'ContextCue', 'App services initialized, mode=%{public}s', services.mode);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用已在运行时点击提醒通知
    this.routeFromWant(want);
  }

  /** 通知的 wantAgent 带 reminderId；写入 AppStorage 由根页面跳到详情 */
  private routeFromWant(want: Want): void {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return;
    }
    const reminderId = parameters['reminderId'];
    if (typeof reminderId === 'string' && reminderId !== '') {
      AppStorage.setOrCreate<string>('ccPendingReminderId', reminderId);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 回前台对账：用户可能刚在系统设置里打开通知授权，或围栏/排期状态有变化；
    // 投递分离后注册失败的提醒也在这里补排（INTEGRATED 模式，开发模式为空操作）
    reconcileOnAppForeground();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
