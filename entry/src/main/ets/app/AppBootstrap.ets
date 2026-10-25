import { AppServices } from './AppServices';
import { appServiceRegistry } from './AppServiceRegistry';
import { createDevelopmentServices } from './DevelopmentServices';

/** Group lead owns dependency selection. Replace this factory when formal adapters are integrated. */
export function initializeAppServices(): AppServices {
  return appServiceRegistry.initialize(() => createDevelopmentServices());
}
