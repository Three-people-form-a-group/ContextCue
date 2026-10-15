# ContextCue Stage 1 Public Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement ContextCue's shared Reminder/Scene types, deterministic creation-input validation, lifecycle transition rules, and ArkTS unit tests without implementing UI or HarmonyOS system capabilities.

**Architecture:** Keep all Stage 1 production code in the platform-independent `model` package. ArkTS interfaces define the shared data contracts; `ReminderModelRules.ets` supplies the runtime behavior needed to enforce and test model invariants, and will later be reused by `ReminderService` rather than duplicated there.

**Tech Stack:** ArkTS, HarmonyOS 6.1.1 (API 24), Hvigor 6.26.8, Hypium 1.0.25.

**Spec:** `docs/superpowers/specs/2026-10-15-contextcue-foundation-design.md`

## Global Constraints

- Work only on `feature-ai`; do not modify `main`, `develop`, `feature-ui`, or `feature-location`.
- Keep the application as one `entry` module compatible with HarmonyOS 6.1.1 (API 24).
- Do not implement ArkUI pages, time scheduling, notifications, location, geofencing, or Scene persistence/management.
- Do not add a real AI provider or any API key, secret, token, password, or local credential file.
- All Reminder instances are one-shot reminders; trigger success and user completion remain distinct states.
- Use Unix Epoch milliseconds for all domain timestamps.
- Follow test-first RED-GREEN-REFACTOR for every production function.
- Run all commands from `E:\HarmonyProjects\ContextCue`.

## Verification Commands

Unit tests:

```powershell
$env:DEVECO_SDK_HOME = "E:/DevEco Studio/sdk"
$env:JAVA_HOME = "E:/DevEco Studio/jbr"
$env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
& "E:/DevEco Studio/tools/hvigor/bin/hvigorw.bat" --mode module -p product=default -p module=entry@default -p buildMode=debug test --no-daemon --stacktrace
```

Debug HAP build:

```powershell
$env:DEVECO_SDK_HOME = "E:/DevEco Studio/sdk"
$env:JAVA_HOME = "E:/DevEco Studio/jbr"
$env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
& "E:/DevEco Studio/tools/hvigor/bin/hvigorw.bat" --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon --stacktrace
```

## Review Focus

- Whitespace-only content must yield `EMPTY_CONTENT`; pinned by Task 3.
- BOTH with neither condition must report both `MISSING_TRIGGER_TIME` and `MISSING_SCENE_ID`, not stop after the first error; pinned by Task 3.
- A finite `triggerTime` equal to `now` is valid, while non-finite or earlier values are rejected; pinned by Task 3.
- `sceneName` without a nonblank `sceneId` cannot activate LOCATION or BOTH; pinned by Task 3.
- Repeating the same status is idempotent, but `COMPLETED` cannot return to any active state; pinned by Task 4.

---

### Task 1: Protect Local Build and Configuration Files

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Existing project-local `.hvigor/` directory and `local.properties` file.
- Produces: Git ignore rules that keep both local paths out of future commits.

- [ ] **Step 1: Add repository-root ignore entries**

Add exactly:

```gitignore
# HarmonyOS local build state
.hvigor/
local.properties
```

Keep the existing `build/`, `.idea/`, `oh_modules/`, `node_modules/`, log, and temporary-file rules.

- [ ] **Step 2: Verify both current paths are ignored**

Run:

```powershell
git check-ignore -v .hvigor local.properties
```

Expected: two lines whose matching rules come from the repository-root `.gitignore`.

- [ ] **Step 3: Verify the tracked diff contains only the intended ignore rules**

Run:

```powershell
git diff --check
git diff -- .gitignore
```

Expected: no whitespace errors and no unrelated `.gitignore` changes.

- [ ] **Step 4: Commit**

```powershell
git add -- .gitignore
git commit -m "chore: ignore HarmonyOS local files"
```

### Task 2: Define Shared Enums and Data Contracts

**Files:**
- Create: `entry/src/main/ets/model/ReminderEnums.ets`
- Create: `entry/src/main/ets/model/Reminder.ets`
- Create: `entry/src/main/ets/model/Scene.ets`
- Create: `entry/src/main/ets/model/CreateReminderInput.ets`
- Create: `entry/src/main/ets/model/OperationResult.ets`
- Create: `entry/src/test/ReminderModel.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: None.
- Produces: `TriggerType`, `ReminderSource`, `ReminderStatus`, `LocationTriggerMode`, `Reminder`, `Scene`, `CreateReminderInput`, `OperationError`, and `OperationResult<T>` with the exact fields in the v1.0 spec.

- [ ] **Step 1: Write the failing contract tests**

Create `reminderModelTest()` and register it from `List.test.ets`. Add tests that assert the exact string values for all four enums, including:

```ts
expect(TriggerType.TIME).assertEqual('TIME')
expect(ReminderStatus.TRIGGERED).assertEqual('TRIGGERED')
expect(LocationTriggerMode.EXIT).assertEqual('EXIT')
```

Also construct typed TIME, LOCATION, and BOTH `Reminder` values, a `Scene`, an AI `CreateReminderInput`, and success/failure `OperationResult` values. Assert representative runtime fields so the compiler and Hypium both exercise the contracts.

- [ ] **Step 2: Run the unit suite and verify RED**

Run the Unit tests command from **Verification Commands**.

Expected: FAIL during ArkTS unit-test compilation because the new `model` modules do not exist. This is the expected missing-feature failure, not an import typo.

- [ ] **Step 3: Implement the minimal type declarations**

Implement only the enums and interfaces specified in Sections 5.1-5.5 of the spec:

- `ReminderEnums.ets`: the four string enums.
- `Reminder.ets`: the Reminder interface with optional condition and lifecycle timestamps.
- `Scene.ets`: the six-field public Scene interface.
- `CreateReminderInput.ets`: the shared AI/manual creation input without lifecycle fields.
- `OperationResult.ets`: `OperationError` and generic `OperationResult<T>`.

Do not add factories, repository code, service code, HarmonyOS imports, or extra persistence fields.

- [ ] **Step 4: Run the full unit suite and verify GREEN**

Run the Unit tests command from **Verification Commands**.

Expected: `BUILD SUCCESSFUL`; the template test and all new contract tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- entry/src/main/ets/model entry/src/test/ReminderModel.test.ets entry/src/test/List.test.ets
git commit -m "feat: add shared reminder models"
```

### Task 3: Enforce CreateReminderInput Invariants

**Files:**
- Create: `entry/src/main/ets/model/ReminderModelRules.ets`
- Modify: `entry/src/test/ReminderModel.test.ets`

**Interfaces:**
- Consumes: `CreateReminderInput`, `TriggerType`, and `OperationError` from Task 2.
- Produces: `validateCreateReminderInput(input: CreateReminderInput, now: number): OperationError[]`.

- [ ] **Step 1: Write failing validation tests**

Add focused Hypium tests with deterministic `now = 1_000` that assert:

- Valid TIME (`triggerTime = 1_001`), LOCATION (nonblank `sceneId`), and BOTH inputs return no errors.
- Whitespace-only content returns `EMPTY_CONTENT` on field `content`.
- TIME without `triggerTime` returns `MISSING_TRIGGER_TIME`.
- `Number.NaN` or positive infinity returns `INVALID_TRIGGER_TIME`.
- `triggerTime = 999` returns `PAST_TRIGGER_TIME`, while `triggerTime = 1_000` is accepted.
- LOCATION with only `sceneName` or a whitespace-only `sceneId` returns `MISSING_SCENE_ID`.
- BOTH with neither `triggerTime` nor `sceneId` returns both missing-field errors in that order.

- [ ] **Step 2: Run the unit suite and verify RED**

Run the Unit tests command from **Verification Commands**.

Expected: FAIL during ArkTS unit-test compilation because `validateCreateReminderInput` is not implemented.

- [ ] **Step 3: Implement `validateCreateReminderInput`**

Implement the exact signature from the Interfaces block. Accumulate errors in stable order: content, time, then scene. Return `OperationError` values with the exact codes from the tests, matching `field`, a user-displayable message, and `retryable: false`.

Validation behavior:

- TIME/BOTH require a finite `triggerTime` greater than or equal to `now`.
- LOCATION/BOTH require a nonblank `sceneId`; `sceneName` never substitutes for it.
- Missing `locationTriggerMode` is accepted at this layer because ReminderService will default it to `ENTER` in Stage 3.

- [ ] **Step 4: Run the full unit suite and verify GREEN**

Run the Unit tests command from **Verification Commands**.

Expected: `BUILD SUCCESSFUL`; all template, contract, and input-validation tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- entry/src/main/ets/model/ReminderModelRules.ets entry/src/test/ReminderModel.test.ets
git commit -m "feat: validate reminder creation input"
```

### Task 4: Define Reminder Lifecycle Transitions

**Files:**
- Modify: `entry/src/main/ets/model/ReminderModelRules.ets`
- Modify: `entry/src/test/ReminderModel.test.ets`

**Interfaces:**
- Consumes: `ReminderStatus` from Task 2.
- Produces: `canTransitionReminderStatus(current: ReminderStatus, next: ReminderStatus): boolean`.

- [ ] **Step 1: Write failing lifecycle tests**

Add parameterized or individually named tests proving:

- Every status can transition to itself as an idempotent no-op.
- ACTIVE can transition to TRIGGERED, COMPLETED, or DISABLED.
- DISABLED can transition to ACTIVE or COMPLETED, but not directly to TRIGGERED.
- TRIGGERED can transition to COMPLETED, but not ACTIVE or DISABLED.
- COMPLETED cannot transition to ACTIVE, TRIGGERED, or DISABLED.

- [ ] **Step 2: Run the unit suite and verify RED**

Run the Unit tests command from **Verification Commands**.

Expected: FAIL during ArkTS unit-test compilation because `canTransitionReminderStatus` is not exported.

- [ ] **Step 3: Implement `canTransitionReminderStatus`**

Implement the exact signature and transition matrix in the spec. Keep it pure: no time reads, repository access, side effects, logging, or HarmonyOS imports.

- [ ] **Step 4: Run the full unit suite and verify GREEN**

Run the Unit tests command from **Verification Commands**.

Expected: `BUILD SUCCESSFUL`; all lifecycle and earlier tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- entry/src/main/ets/model/ReminderModelRules.ets entry/src/test/ReminderModel.test.ets
git commit -m "feat: define reminder lifecycle rules"
```

### Task 5: Verify and Report Stage 1

**Files:**
- Verify only; do not add UI, repository, service, AI, trigger, time, notification, or location implementation files.

**Interfaces:**
- Consumes: All Stage 1 contracts and rules from Tasks 2-4.
- Produces: Fresh unit-test, build, Git hygiene, and scope evidence for the phase report.

- [ ] **Step 1: Run the complete local unit-test suite**

Run the Unit tests command from **Verification Commands**.

Expected: exit code 0 and `BUILD SUCCESSFUL`.

- [ ] **Step 2: Run a complete debug HAP build**

Run the Debug HAP build command from **Verification Commands**.

Expected: exit code 0, `BUILD SUCCESSFUL`, and an unsigned HAP under `entry/build/default/outputs/default/` because signing is not configured.

- [ ] **Step 3: Verify source hygiene and scope**

Run:

```powershell
git diff --check
git status --short --branch
rg -n -i "api[_-]?key|authorization|secret|token|password" entry/src/main/ets
```

Expected: no whitespace errors; no uncommitted source changes; no credential-like source matches; branch remains `feature-ai`.

- [ ] **Step 4: Report the phase result and stop**

Report added and modified files, unit-test and debug-build evidence, any unsigned-packaging warning, and the explicitly unimplemented areas: Repository, ReminderService, AI, TriggerCoordinator, UI, time scheduling, notification, location, geofencing, and Scene management.

Wait for user confirmation before starting the ReminderRepository phase.
