import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';

export interface PermissionGateway {
  hasPreciseLocation(): boolean;
  requestPreciseLocation(): Promise<void>;
  isLocationEnabled(): boolean;
}

export class HarmonyPermissionGateway implements PermissionGateway {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  hasPreciseLocation(): boolean {
    const manager = abilityAccessCtrl.createAtManager();
    const token = this.context.applicationInfo.accessTokenId;
    return manager.checkAccessTokenSync(token, 'ohos.permission.LOCATION') === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
      manager.checkAccessTokenSync(token, 'ohos.permission.APPROXIMATELY_LOCATION') === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  async requestPreciseLocation(): Promise<void> {
    const permissions: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, permissions);
  }

  isLocationEnabled(): boolean { return geoLocationManager.isLocationEnabled(); }
}

export class LocationPermissionManager {
  private gateway: PermissionGateway;
  constructor(gateway: PermissionGateway) { this.gateway = gateway; }

  async request(): Promise<void> {
    if (!this.gateway.hasPreciseLocation()) { await this.gateway.requestPreciseLocation(); }
    await this.checkReady();
  }

  async checkReady(): Promise<void> {
    if (!this.gateway.hasPreciseLocation()) { throw new Error('LOCATION_PERMISSION_DENIED'); }
    if (!this.gateway.isLocationEnabled()) { throw new Error('LOCATION_SWITCH_OFF'); }
  }
}
