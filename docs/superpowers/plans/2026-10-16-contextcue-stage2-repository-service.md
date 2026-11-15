# ContextCue Stage 2 Repository and Service Implementation Plan

> **For agentic workers:** Execute this plan task by task. Use small steps, test-first RED-GREEN-REFACTOR, and verify each Task before continuing. No specific plugin, skill, sub-agent framework, or agent tool is required. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the shared asynchronous Reminder repository contract, a testable in-memory implementation, and a ReminderService that owns creation, lifecycle and trigger synchronization.

**Architecture:** `ReminderService` is the only writer of Reminder state and depends on `ReminderRepository` plus the two minimal public Trigger ports. Production HarmonyOS scheduling, geofencing, notification and Scene management remain outside this phase. The in-memory repository proves behavior but is not durable storage.

**Tech Stack:** ArkTS, HarmonyOS 6.1.1 (API 24), Hvigor 6.26.8, Hypium 1.0.25.

**Spec:** `docs/superpowers/specs/contextcue-foundation-design.md` (the current user-renamed working-tree file; preserve that rename when committing).

## Global Constraints

- Work on `feature-ai` only. Preserve the user's pending spec-file rename; never silently restore the old path.
- Reuse `Reminder`, `CreateReminderInput`, `OperationResult`, `validateCreateReminderInput` and `canTransitionReminderStatus` without changing their wire fields.
- `save()` has upsert semantics. The repository performs data I/O only; the service owns business validation and state transitions.
- One-shot reminders only. `TRIGGERED` means notification succeeded; `COMPLETED` means the user confirmed completion.
- `EXIT` stays a model reservation and cannot be activated. Missing location mode defaults to `ENTER` in the service.
- No real AI provider, UI, time scheduler, Notification, Location Kit, geofence or Scene business implementation.
- No secrets, local configuration or generated output in commits.
- Use the Stage 1 plan's process-local DevEco SDK/JBR settings and Hvigor unit-test / `assembleHap` commands; verify both after each task that adds production ArkTS.

## Stage Boundary Decision for Review

`ReminderService` cannot honestly report an ACTIVE create/enable operation without its trigger dependencies. Bring only `TimeTriggerPort.schedule/cancel` and `LocationTriggerPort.register/unregister/isInsideScene` contract declarations forward from the architecture spec. The UI and location owners still implement the formal system adapters in their own branches later. Test fakes live under `entry/src/test/` and must be removable without changing service contracts.

The service accepts injected `ReminderRepository`, `TimeTriggerPort`, `LocationTriggerPort`, a clock and an ID factory. This makes timestamps and IDs deterministic in tests without adding HarmonyOS dependencies. Service public methods return `OperationResult<T>` instead of leaking exceptions; repository and port interfaces remain Promise based and may reject.

Service error codes are fixed for this phase: `REMINDER_NOT_FOUND` and `INVALID_STATUS_TRANSITION` (`retryable: false`); `REPOSITORY_ERROR`, `TRIGGER_REGISTRATION_ERROR`, and `TRIGGER_CLEANUP_ERROR` (`retryable: true`). Input errors retain the exact codes from `ReminderModelRules`. For `markTriggered`, a cleanup failure after a successful save returns `success: false`, `data: persisted TRIGGERED Reminder`, and `error: TRIGGER_CLEANUP_ERROR`; consumers must inspect the persisted state and must not send another notification.

Because same-status calls are no-ops, a separate `retryTriggerCleanup(id)` service method retries cleanup for an already TRIGGERED Reminder. A retry never sends a notification or changes the status. Its existence does not imply an automatic background retry in this phase.

Review finding resolved during implementation: serialize all mutations for the same Reminder ID within one service instance, including create, transition, edit, delete and cleanup retry. Otherwise overlapping awaits can overwrite TRIGGERED/COMPLETED with a stale ACTIVE snapshot. This is process-local; the later durable adapter must define cross-process coordination. An injected ID collision is rejected before registration to avoid upsert overwriting an existing Reminder.

## Review Focus

- Invalid input or explicit EXIT causes no repository write and no trigger registration (Task 3).
- `BOTH` fails partway through registration: the earlier registration is cancelled, and the record does not remain ACTIVE (Task 3).
- Repository save fails after registration: successful registrations are cancelled, no Reminder from the failed create is persisted, and success is never reported (Task 3).
- Disabling and completing clear both ports. `markTriggered` saves TRIGGERED first, then clears both ports; cleanup failure never restores ACTIVE (Task 4).
- An invalid lifecycle transition, such as `COMPLETED` to `ACTIVE`, changes neither repository nor ports (Task 4).
- Repeating the same state returns the unchanged Reminder without a repository write, a port call, or a timestamp change (Task 4).
- Overlapping mutations for the same ID are serialized, so a later completion is not overwritten by an earlier in-flight disable (Task 4 review fix).
- Editing from BOTH to TIME removes the old location registration before scheduling the new condition (Task 5).
- An update save failure after new registration cancels new triggers and attempts to restore old triggers, while the repository still contains the old Reminder (Task 5).
- A cleanup or repository failure returns a retryable error; only `markTriggered` may have already persisted its target state when cleanup fails (Tasks 4-5).

---

### Task 1: Asynchronous Repository Contract and In-Memory Implementation

**Files:** Create `entry/src/main/ets/repository/ReminderRepository.ets`, `entry/src/main/ets/repository/InMemoryReminderRepository.ets`, `entry/src/test/ReminderRepository.test.ets`; modify `entry/src/test/List.test.ets`.

**Interfaces:** `ReminderRepository.save(reminder: Reminder): Promise<void>`, `findById(id: string): Promise<Reminder | undefined>`, `findAll(): Promise<Reminder[]>`, `deleteById(id: string): Promise<boolean>`. `InMemoryReminderRepository implements ReminderRepository`.

- [ ] Write tests for insert/upsert, missing ID, list, delete return value, and defensive copies on save/read so callers cannot mutate stored state without `save()`.
- [ ] Run the whole Hypium suite; RED must be missing repository symbols, not test syntax or SDK configuration.
- [ ] Implement the interface and minimum in-memory map; no status logic or system APIs.
- [ ] Run the whole unit suite and debug `assembleHap`; both must show `BUILD SUCCESSFUL`.
- [ ] Commit only the repository and test files: `feat: add reminder repository contract`.

### Task 2: Minimal Trigger Ports Needed by the Service

**Files:** Create `entry/src/main/ets/reminder/contract/TimeTriggerPort.ets`, `LocationTriggerPort.ets`; add a contract test under `entry/src/test/ReminderTriggerPort.test.ets`; register it in `List.test.ets`.

**Interfaces:** Match the exact port signatures in spec Section 8. No port implementation under `src/main`.

- [ ] Write compile-time contract tests with tiny in-test implementations; assert calls receive a Reminder/reminderId and an `isInsideScene` result.
- [ ] Run the unit suite; RED must be missing contract modules.
- [ ] Add only the two public interfaces, then run the full unit suite and `assembleHap`.
- [ ] Commit only the interfaces and tests: `feat: define reminder trigger ports`.

### Task 3: Creation, Validation and Activation

**Files:** Create `entry/src/main/ets/service/ReminderService.ets`; add `entry/src/test/ReminderService.test.ets`; register it in `List.test.ets`.

**Interfaces:** `create(input: CreateReminderInput): Promise<OperationResult<Reminder>>`, `findById(id: string): Promise<OperationResult<Reminder>>`, `findAll(): Promise<OperationResult<Reminder[]>>`. Constructor injects repository, two ports, `now(): number`, and `newId(): string`.

- [ ] Write tests for TIME/LOCATION/BOTH creation, generated ID/time/status/source, content and sceneId canonicalized by trimming, default ENTER, validation rejection, partial registration failure, and final repository save failure. Failed create must leave no record. Use deterministic in-test ports and repository failures.
- [ ] Run the whole suite and observe a missing-service RED.
- [ ] Implement create in this order: validate input; trim content and sceneId and apply default ENTER; construct final ACTIVE Reminder in memory; register required ports; save ACTIVE once. On registration failure, cancel any completed registration and do not write the repository. On save failure, cancel all newly registered triggers; return `REPOSITORY_ERROR` without leaving a Reminder from this create. Use the fixed error codes above; read methods map repository rejection to `REPOSITORY_ERROR`.
- [ ] Run the complete suite and `assembleHap`; both must pass. Confirm no real adapter files were added.
- [ ] Commit: `feat: create reminders through service`.

### Task 4: Lifecycle and Trigger Cleanup

**Files:** Modify `ReminderService.ets` and `ReminderService.test.ets`.

**Interfaces:** `enable(id: string)`, `disable(id: string)`, `complete(id: string)`, `markTriggered(id: string, occurredAt: number)`, `retryTriggerCleanup(id: string)` each return `Promise<OperationResult<Reminder>>`.

- [ ] Write tests for every allowed/forbidden transition, triggeredAt/completedAt ownership, registration on enable, cleanup on disable/complete/trigger, missing reminder, and port/repository failures. For every same-status call, assert unchanged data and timestamps with zero `save`, `schedule/register`, and `cancel/unregister` calls. For `markTriggered`, assert save-before-cleanup, retained TRIGGERED on cleanup failure, and `success: false` with persisted TRIGGERED data and `TRIGGER_CLEANUP_ERROR`. Assert `retryTriggerCleanup` can clear a previously failed registration without another save or notification.
- [ ] Run the full suite and observe missing-method RED.
- [ ] Implement transitions through `canTransitionReminderStatus`. If current and target status match, return the current Reminder unchanged with no write or port call. For enable, register required ports before saving ACTIVE; compensate on save failure. For disable/complete, clean ports before saving the target status and compensate a failed save by restoring old registrations where possible. Treat `markTriggered` separately: notification has already succeeded, so save TRIGGERED and `triggeredAt` first, then cancel/unregister; a cleanup failure returns retryable `TRIGGER_CLEANUP_ERROR` with persisted TRIGGERED data and never writes ACTIVE. A failed TRIGGERED save is a distinct `REPOSITORY_ERROR`; it cannot prove notification deduplication, so document this for the later coordinator phase.
- [ ] Run full unit tests and `assembleHap`; commit: `feat: manage reminder lifecycle`.

### Task 5: Edit, Delete, Final Consistency Review

**Files:** Modify `ReminderService.ets` and `ReminderService.test.ets`.

**Interfaces:** `update(id: string, input: CreateReminderInput): Promise<OperationResult<Reminder>>`; `delete(id: string): Promise<OperationResult<boolean>>`.

- [ ] Write tests for active edit across trigger types, disabled edit without registration, preservation of ID/createdAt, rejection of invalid/EXIT input, delete cleanup before repository deletion, missing ID, cleanup failure and save/delete failure.
- [ ] Run the full suite and observe missing-method RED.
- [ ] For ACTIVE update: validate; construct new Reminder preserving `id`, `createdAt`, and `status`; clear old triggers; register new triggers; save the new Reminder last. On failure, cancel any new triggers, attempt to restore old triggers, keep the old repository record, and return the fixed retryable error. For DISABLED update, validate and save without registering. Delete only after cleanup; on failed delete, attempt to restore old registrations.
- [ ] Run full unit tests, debug `assembleHap`, `git diff --check`, a credential scan of `entry/src/main/ets`, and an explicit file-scope review. Confirm branch `feature-ai`, no generated files staged, and no uncommitted source changes.
- [ ] Commit: `feat: update and delete reminders`.

## Phase Handoff

Report the exact test/build results, repository's in-memory (non-durable) limit, any compensation limitation found in failure-injection tests, and the public-port contract change to both teammates. In particular, a repository failure while saving TRIGGERED after notification succeeds cannot by itself prevent duplicate notification after a restart; the later TriggerCoordinator/Notification integration must define recovery or deduplication. Do not start AI, UI, scheduling, notification or location implementations in this phase. Do not push or merge without a separate submission decision.
