import { AppServices } from './AppServices';

/** One registry per application process. Do not recreate or clear it when a page/Ability closes. */
export class AppServiceRegistry {
  private services?: AppServices;
  private initializing: boolean = false;

  initialize(factory: () => AppServices): AppServices {
    if (this.services !== undefined) {
      return this.services;
    }
    if (this.initializing) {
      throw new Error('APP_SERVICES_INITIALIZATION_REENTRY');
    }
    this.initializing = true;
    try {
      const services = factory();
      this.services = services;
      return services;
    } finally {
      this.initializing = false;
    }
  }

  get(): AppServices {
    if (this.services === undefined) {
      throw new Error('APP_SERVICES_NOT_INITIALIZED');
    }
    return this.services;
  }
}

// Only the bootstrap initializes this registry; pages use getAppServices().
export const appServiceRegistry: AppServiceRegistry = new AppServiceRegistry();

export function getAppServices(): AppServices {
  return appServiceRegistry.get();
}
