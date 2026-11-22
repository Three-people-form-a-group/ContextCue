import { AppServices } from './AppServices';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { appServiceRegistry } from './AppServiceRegistry';
import { common } from '@kit.AbilityKit';
import { createDevelopmentServices } from './DevelopmentServices';
import { createIntegratedServices } from './IntegratedServices';

/** Group lead owns dependency selection. With a UIAbility context the formal
 *  composition is used; without it (unit tests) the development composition stays. */
export function initializeAppServices(config?: AIProviderConfig, context?: common.UIAbilityContext): AppServices {
  return appServiceRegistry.initialize((): AppServices => context === undefined
    ? createDevelopmentServices(config)
    : createIntegratedServices(config, context));
}
