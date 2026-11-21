import { describe, it, expect } from '@ohos/hypium';
import { geoLocationManager } from '@kit.LocationKit';
import { Scene } from '../../main/ets/model/Scene';
import { LocationPermissionManager, PermissionGateway } from '../../main/ets/location/platform/LocationPermissionManager';
import { HarmonyLocationPlatform, LocationNativeApi } from '../../main/ets/location/platform/HarmonyLocationPlatform';
import { PreferencesSceneStorage, ScenePreferences } from '../../main/ets/location/repository/PreferencesSceneStorage';

class PermissionStub implements PermissionGateway {
  granted: boolean = true;
  enabled: boolean = true;
  grantOnRequest: boolean = true;
  requests: number = 0;
  hasPreciseLocation(): boolean { return this.granted; }
  isLocationEnabled(): boolean { return this.enabled; }
  async requestPreciseLocation(): Promise<void> { this.requests++; this.granted = this.grantOnRequest; }
}
class NativeStub implements LocationNativeApi {
  request?: geoLocationManager.GnssGeofenceRequest;
  removed: number = -1;
  async active(): Promise<Map<number, geoLocationManager.Geofence>> {
    const fences = new Map<number, geoLocationManager.Geofence>();
    fences.set(4, { latitude: 31, longitude: 121, radius: 100, expiration: 10000 });
    return fences;
  }
  async current(): Promise<geoLocationManager.Location> {
    return { latitude: 31, longitude: 121, altitude: 0, accuracy: 5, speed: 0,
      timeStamp: 100000, direction: 0, timeSinceBoot: 0, additions: [], additionSize: 0 };
  }
  supportsWgs84(): boolean { return true; }
  async add(request: geoLocationManager.GnssGeofenceRequest): Promise<number> { this.request = request; return 7; }
  async remove(id: number): Promise<void> { this.removed = id; }
}
class PreferenceStub implements ScenePreferences {
  value: string = '';
  failFlush: boolean = false;
  flushed: number = 0;
  async get(): Promise<string> { return this.value; }
  async put(value: string): Promise<void> { this.value = value; }
  async flush(): Promise<void> { this.flushed++; if (this.failFlush) { throw new Error('FLUSH_FAILED'); } }
}
export default function locationPlatformTest() {
  describe('LocationPlatform', () => {
    it('requests_permission_explicitly_and_rechecks_denial_and_switch', 0, async () => {
      const gateway = new PermissionStub();
      gateway.granted = false;
      gateway.grantOnRequest = false;
      const permission = new LocationPermissionManager(gateway);
      expect(gateway.requests).assertEqual(0);
      let failed: boolean = false;
      try { await permission.request(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      expect(gateway.requests).assertEqual(1);
      gateway.grantOnRequest = true;
      await permission.request();
      await permission.checkReady();
      gateway.enabled = false;
      failed = false;
      try { await permission.checkReady(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('maps_native_fix_and_fence_without_direct_notification', 0, async () => {
      const native = new NativeStub();
      const platform = new HarmonyLocationPlatform(new LocationPermissionManager(new PermissionStub()), native);
      const fix = await platform.getCurrentPosition();
      expect(fix.occurredAt).assertEqual(100000);
      expect(fix.accuracy).assertEqual(5);
      const scene: Scene = { id: 's', name: '家', latitude: 31, longitude: 121, radius: 100, createdAt: 1 };
      const id = await platform.addFence(scene, () => {}, () => {});
      expect(id).assertEqual(7);
      expect(native.request?.geofence.latitude).assertEqual(31);
      expect(native.request?.geofence.radius).assertEqual(100);
      expect(native.request?.notifications === undefined).assertTrue();
      // V1 cannot deliver fence events after process death, so it must not delegate to an extension.
      expect(native.request?.fenceExtensionAbilityName === undefined).assertTrue();
      await platform.removeFence(id);
      expect(native.removed).assertEqual(7);
    });
    it('explicit_restart_recovery_removes_app_orphans', 0, async () => {
      const native = new NativeStub();
      const platform = new HarmonyLocationPlatform(new LocationPermissionManager(new PermissionStub()), native);
      await platform.recoverOrphanFences();
      expect(native.removed).assertEqual(4);
    });
    it('storage_is_lazy_and_flushes_before_success', 0, async () => {
      const preference = new PreferenceStub();
      let opens: number = 0;
      const storage = new PreferencesSceneStorage(async (): Promise<ScenePreferences> => { opens++; return preference; });
      expect(opens).assertEqual(0);
      expect(await storage.read() === undefined).assertTrue();
      await storage.write('first');
      expect(preference.flushed).assertEqual(1);
      expect(await storage.read()).assertEqual('first');
      expect(opens).assertEqual(1);
      preference.failFlush = true;
      let failed: boolean = false;
      try { await storage.write('second'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      // A failed durable write must not be presented as a successful read from the cache.
      failed = false;
      try { await storage.read(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
  });
}
