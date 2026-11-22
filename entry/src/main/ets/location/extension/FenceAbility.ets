import { FenceExtensionAbility, geoLocationManager } from '@kit.LocationKit';
import { createFileFenceRegistry } from '../repository/FenceRegistryStore';
import { FenceEventHandler, FenceEventReport } from './FenceEventHandler';
import { SystemFenceNotifier } from './FenceNotificationPublisher';
import { createFenceReminderStore } from './FenceReminderSource';

/**
 * Entry point the system starts when a GNSS fence transitions, even if the app process is dead.
 * It is declared in module.json5 as type "fence" and named by
 * GnssGeofenceRequest.fenceExtensionAbilityName (see FENCE_EXTENSION_ABILITY_NAME).
 *
 * The process is short lived: everything it needs is on disk (fence registry + persistent
 * reminders), and every failure is logged instead of thrown, because a crashed extension cannot
 * retry and the user would silently lose the reminder.
 */
export default class LocationFenceAbility extends FenceExtensionAbility {
  private handler: FenceEventHandler | undefined = undefined;

  onFenceStatusChange(transition: geoLocationManager.GeofenceTransition,
    additions: Record<string, string>): void {
    if (transition === undefined || transition === null) { return; }
    const fenceId: number = transition.geofenceId;
    const enter: boolean =
      transition.transitionEvent === geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER;
    this.handlerFor().handle(fenceId, enter).then((report: FenceEventReport): void => {
      console.info(`ContextCue fence ${report.fenceId}: ${report.result} ${report.outcome === undefined ? '' : report.outcome}`);
    }).catch((error: Object): void => {
      console.error(`ContextCue fence ${fenceId} failed: ${String(error)}`);
    });
  }

  onDestroy(): void {
    this.handler = undefined;
  }

  private handlerFor(): FenceEventHandler {
    if (this.handler !== undefined) { return this.handler; }
    const filesDir: string = this.context.filesDir;
    const handler = new FenceEventHandler(
      createFileFenceRegistry(filesDir),
      createFenceReminderStore(filesDir),
      new SystemFenceNotifier(),
      (fenceId: number): Promise<void> => geoLocationManager.removeGnssGeofence(fenceId),
      (): number => Date.now(),
      (code: string): void => { console.error(`ContextCue fence handler error: ${code}`); });
    this.handler = handler;
    return handler;
  }
}
