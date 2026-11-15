import { AppServices } from './AppServices';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { appServiceRegistry } from './AppServiceRegistry';
import { createDevelopmentServices } from './DevelopmentServices';

/** Group lead owns dependency selection. Replace this factory when formal adapters are integrated. */
export function initializeAppServices(config?: AIProviderConfig): AppServices {
  return appServiceRegistry.initialize(() => createDevelopmentServices(config));
}
