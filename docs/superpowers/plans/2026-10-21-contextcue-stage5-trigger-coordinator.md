# ContextCue Stage 5 TriggerCoordinator Implementation Plan

**Goal:** Complete the last shared reminder-trigger business component so TIME, LOCATION and BOTH condition events reach one coordinator, send at most one final notification during normal processing, and update reminder state only after notification succeeds.

**Architecture:** `TriggerCoordinator` implements `TriggerEventSink` and depends only on `ReminderService`, `LocationTriggerPort`, `ReminderNotificationPort` and an injected clock. It never accesses `ReminderRepository` directly and contains no HarmonyOS system API. Per-reminder processing is serialized to prevent two concurrent events from both notifying before the first state update finishes. The `processActiveTrigger` callback must not await another ReminderService mutation for the same reminder ID; notification adapters remain side-effect adapters and must not re-enter same-ID service mutation from `notify`.

**Public-scope boundary:** This stage completes the shared code listed in the approved foundation design. It does not implement ArkUI pages, time scheduling, HarmonyOS Notification, Location Kit, permissions, geofencing, Scene storage or any teammate adapter.

## Fixed behavior

- Ignore events whose condition is not relevant to the reminder type, events with `satisfied = false`, stale events for missing reminders, and reminders not in `ACTIVE` state.
- TIME triggers only when a TIME event is satisfied and the injected current time has reached `triggerTime`.
- LOCATION triggers only when a LOCATION event is satisfied and `LocationTriggerPort.isInsideScene(sceneId)` confirms the current location.
- BOTH uses AND semantics on every event: current time must have reached `triggerTime` and the current location must be inside `sceneId`. No historical in-memory condition flag is treated as authoritative.
- Revalidate and commit the trigger through `ReminderService.processActiveTrigger` so an update, disable, completion or deletion that finishes during a location query invalidates the stale event before notification.
- Inside that serialized service action, call `ReminderNotificationPort.notify(reminder)` before the ACTIVE → TRIGGERED state update.
- A notification failure leaves the reminder ACTIVE. A successful notification followed by a repository state-save failure is surfaced as an error; without an idempotent notification adapter, a later retry in the same process or after restart can notify again. Exactly-once delivery remains a documented adapter/integration limitation.
- If the state reaches TRIGGERED but trigger cleanup fails, preserve TRIGGERED and reject the event with a visible cleanup error; cleanup can be retried through the existing `ReminderService.retryTriggerCleanup` API.

## Task 1: Pin coordinator behavior with tests

**Files:** Create `entry/src/test/TriggerCoordinator.test.ets`; modify `entry/src/test/List.test.ets`.

- Add deterministic fakes for time/location ports and notification delivery.
- Cover TIME early/false/wrong-condition filtering and successful notification/state transition.
- Cover LOCATION outside/inside behavior.
- Cover BOTH time-first, location-later, already-inside-at-time and location-before-time behavior.
- Cover missing/disabled/terminal reminders, notification failure, location-query failure, repository state-save failure, cleanup failure, and concurrent duplicate events.
- Run the test task before implementation and retain the expected missing-module failure as the RED step.

## Task 2: Implement TriggerCoordinator

**Files:** Create `entry/src/main/ets/reminder/TriggerCoordinator.ets`.

- Implement the fixed behavior above without importing HarmonyOS SDK modules.
- Serialize work by reminder ID and always clear completed gates.
- Convert dependency failures to short, non-sensitive coordinator errors; do not log reminder content, credentials or provider details.

## Task 3: Verify and submit

- Run the full Hypium test task.
- Run API 24 debug `assembleHap`.
- Run Git diff/whitespace and credential checks.
- Independently review the final diff against the foundation design.
- Commit with `feat: implement trigger coordinator` on `feature-ai`.
- Produce a complete Chinese public-interface file list for the two teammates, including ownership, method meaning and integration constraints.
