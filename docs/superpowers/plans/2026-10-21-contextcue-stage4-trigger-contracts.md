# ContextCue Stage 4 Trigger Contracts Implementation Plan

> **For implementers:** Execute this single task with test-first RED-GREEN-REFACTOR. No particular plugin, skill, sub-agent framework, or agent tool is required.

**Goal:** Complete the public trigger-event and notification contracts needed by the time, location and coordinator modules.

**Architecture:** Keep each shared contract in a focused file under `reminder/contract/`. Reuse the existing `Reminder`, `TimeTriggerPort`, `LocationTriggerPort` and `SceneResolver` without changing their signatures. This stage defines data flow only; Stage 5 owns `TriggerCoordinator` behavior.

**Tech Stack:** ArkTS, HarmonyOS 6.1.1 (API 24), Hvigor 6.26.8, Hypium 1.0.25.

**Spec:** `docs/superpowers/specs/contextcue-foundation-design.md`, Section 8 and Section 14 step 4.

## Global Constraints

- Work only on `feature-ai`.
- Do not implement HarmonyOS scheduling, notifications, positioning, geofencing or Scene storage.
- Do not implement `TriggerCoordinator` in this stage.
- Do not change existing Reminder wire fields or the signatures of `TimeTriggerPort`, `LocationTriggerPort` and `SceneResolver`.
- `TriggerConditionEvent` carries only `reminderId`, `condition`, `satisfied` and `occurredAt`; `occurredAt` is Unix Epoch milliseconds.
- V1 event semantics distinguish `TIME` and `LOCATION` only. They do not add ENTER/EXIT to the event contract.
- Run the full unit suite and debug `assembleHap`; inspect test output for assertion errors because Hvigor can still exit successfully when Hypium reports a failed assertion.

## Review Focus

- TIME and LOCATION enum values remain stable strings for cross-branch use.
- `TriggerConditionEvent` contains no HarmonyOS SDK objects or adapter-specific fields.
- `TriggerEventSink` accepts both satisfied and unsatisfied condition changes.
- `ReminderNotificationPort` consumes the shared `Reminder` model and does not update repository state.
- Existing Stage 2 and Stage 3 tests continue to compile without interface changes.

---

### Task 1: Complete Shared Trigger Contracts

**Files:** Create `entry/src/main/ets/reminder/contract/TriggerConditionEvent.ets`, `TriggerEventSink.ets`, `ReminderNotificationPort.ets`; create `entry/src/test/ReminderEventContract.test.ets`; modify `entry/src/test/List.test.ets`.

**Interfaces:**

- `TriggerCondition.TIME = 'TIME'`, `TriggerCondition.LOCATION = 'LOCATION'`.
- `TriggerConditionEvent { reminderId: string; condition: TriggerCondition; satisfied: boolean; occurredAt: number }`.
- `TriggerEventSink.onConditionChanged(event: TriggerConditionEvent): Promise<void>`.
- `ReminderNotificationPort.notify(reminder: Reminder): Promise<void>`.

- [ ] Write compile-time behavioral tests with tiny in-test sink and notification implementations. Send TIME/satisfied and LOCATION/unsatisfied events, assert all event fields survive unchanged, and assert notification receives the same shared Reminder fields.
- [ ] Register the test in `List.test.ets`, run the complete Hypium suite, and confirm RED is caused by missing contract modules.
- [ ] Add the three minimal contract files with no production implementation or HarmonyOS imports.
- [ ] Run the complete Hypium suite and debug `assembleHap`; require `BUILD SUCCESSFUL` and no assertion-error lines.
- [ ] Run `git diff --check`, inspect changed files, scan for credentials/generated output, and commit: `feat: complete reminder trigger contracts`.

## Phase Handoff

Tell the UI/time owner to implement `TimeTriggerPort` and `ReminderNotificationPort`, and the location owner to implement `LocationTriggerPort` and `SceneResolver`. Both owners publish condition changes through `TriggerEventSink`. Stage 5 will implement `TriggerCoordinator` against these contracts. Do not push or merge without a separate submission decision.
