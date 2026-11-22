import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Scene } from '../../model/Scene';
import { FenceDelivery, FenceRegistry, LocationFix, LocationPlatform } from './LocationPlatform';
import { LocationPermissionManager } from './LocationPermissionManager';

/** The native boundary is replaceable in unit tests; device behavior is verified separately. */
export interface LocationNativeApi {
  current(): Promise<geoLocationManager.Location>;
  supportsWgs84(): boolean;
  active(): Promise<Map<number, geoLocationManager.Geofence>>;
  add(request: geoLocationManager.GnssGeofenceRequest): Promise<number>;
  remove(id: number): Promise<void>;
}

export class HarmonyLocationApi implements LocationNativeApi {
  async current(): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      timeoutMs: 10000, maxAccuracy: 100
    };
    return geoLocationManager.getCurrentLocation(request);
  }
  supportsWgs84(): boolean {
    try {
      // API 26+ exposes an explicit service check. The guard keeps API 24 devices working.
      if (typeof geoLocationManager.isGnssFenceServiceSupported === 'function' &&
        !geoLocationManager.isGnssFenceServiceSupported()) {
        return false;
      }
      return geoLocationManager.getGeofenceSupportedCoordTypes().includes(geoLocationManager.CoordinateSystemType.WGS84);
    } catch (_) {
      // Emulators and devices without a GNSS fence implementation can throw or return no types.
      return false;
    }
  }
  async add(request: geoLocationManager.GnssGeofenceRequest): Promise<number> {
    return geoLocationManager.addGnssGeofence(request);
  }
  async remove(id: number): Promise<void> { await geoLocationManager.removeGnssGeofence(id); }
  async active(): Promise<Map<number, geoLocationManager.Geofence>> {
    return geoLocationManager.getActiveGeoFences();
  }
}

export class HarmonyLocationPlatform implements LocationPlatform {
  private permission: LocationPermissionManager;
  private native: LocationNativeApi;

  constructor(permission: LocationPermissionManager, native: LocationNativeApi = new HarmonyLocationApi()) {
    this.permission = permission;
    this.native = native;
  }

  async checkReady(): Promise<void> {
    await this.permission.checkReady();
    if (!this.native.supportsWgs84()) { throw new Error('LOCATION_WGS84_FENCE_UNSUPPORTED'); }
  }

  async getCurrentPosition(): Promise<LocationFix> {
    await this.permission.checkReady();
    const location = await this.native.current();
    return { latitude: location.latitude, longitude: location.longitude,
      accuracy: location.accuracy, occurredAt: location.timeStamp };
  }

  async addFence(scene: Scene, enter: () => void, error: (code: string) => void,
    delivery?: FenceDelivery): Promise<number> {
    await this.checkReady();
    const request: geoLocationManager.GnssGeofenceRequest = {
      geofence: { latitude: scene.latitude, longitude: scene.longitude, radius: scene.radius,
        coordinateSystemType: geoLocationManager.CoordinateSystemType.WGS84,
        // Positive millisecond lifetime. No undocumented negative/zero "forever" value.
        expiration: Number.MAX_SAFE_INTEGER },
      monitorTransitionEvents: [geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER],
      geofenceTransitionCallback: (failure: BusinessError, transition: geoLocationManager.GeofenceTransition): void => {
        // With a fence extension configured the extension owns delivery. The in-process callback
        // may still fire on some devices (recorded in docs/location/geofence-verification.md); it
        // stays silent on purpose so one crossing cannot notify twice or bypass the BOTH gate.
        if (delivery !== undefined) {
          return;
        }
        if (failure !== undefined && failure !== null && failure.code !== 0) {
          error('LOCATION_NATIVE_CALLBACK_FAILED');
          return;
        }
        if (transition !== undefined && transition !== null &&
          transition.transitionEvent === geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER) {
          enter();
        }
      }
    };
    // The callback above is mandatory even when the extension is used; fenceExtensionAbilityName
    // additionally lets the system start the extension process after this app was killed.
    // See docs/location/geofence-lifecycle.md.
    if (delivery !== undefined) {
      request.fenceExtensionAbilityName = delivery.fenceExtensionAbilityName;
    }
    return this.native.add(request);
  }

  async removeFence(id: number): Promise<void> { await this.native.remove(id); }

  async activeFenceIds(): Promise<number[]> {
    const fences = await this.native.active();
    const ids: number[] = [];
    for (const id of fences.keys()) { ids.push(id); }
    return ids;
  }

  /**
   * Run once on a fresh process, before reminders are reconciled.
   *
   * A fence is "orphan" only when no durable mapping claims it. Mapped fences are kept even when
   * this process knows nothing about them, because the fence extension may deliver their events
   * after the process died. Reminder-level accounting (mapping without an ACTIVE reminder) is
   * LocationReminderAdapter.reconcile()'s job.
   */
  async recoverOrphanFences(registry: FenceRegistry): Promise<void> {
    await this.checkReady();
    const mapped = await registry.list();
    const claimed: Map<number, boolean> = new Map<number, boolean>();
    for (let index = 0; index < mapped.length; index++) { claimed.set(mapped[index].fenceId, true); }
    const fences = await this.native.active();
    for (const id of fences.keys()) {
      if (!claimed.has(id)) { await this.native.remove(id); }
    }
  }
}
