# ContextCue Stage 3 Fake AI Parsing Implementation Plan

> **For implementers:** Execute one task at a time with test-first RED–GREEN–REFACTOR, and verify each task before continuing. No particular plugin, agent framework, or delegation method is required. Checkboxes track progress.

**Goal:** Turn a provider's strict JSON response into a validated, provider-neutral `CreateReminderInput` without calling a real AI API or saving a Reminder.

**Architecture:** `DefaultAIService` orchestrates `AIModelProvider → AIResponseParser → AIParseValidator → SceneResolver → ReminderMapper`. The provider returns response text or a typed failure; only `READY` exposes a complete `draft`. The Fake provider supplies deterministic fixtures for integration and tests, not general natural-language understanding.

**Tech Stack:** ArkTS, HarmonyOS 6.1.1 (API 24), Hvigor 6.26.8, Hypium 1.0.25.

**Spec:** `docs/superpowers/specs/contextcue-foundation-design.md`, especially Sections 5.3–5.4, 6, 8 and 14.

## Global Constraints

- Work only on `feature-ai`; preserve existing public Reminder fields and Stage 2 service behavior.
- AI never calls `ReminderService` or `ReminderRepository`, and never creates `id`, `status` or `createdAt`.
- No real provider, network call, API key, server project, UI, scheduling, notification, Scene storage, positioning or geofence implementation.
- Time values are Unix Epoch milliseconds. The provider receives explicit `now`, `timeZone` and `locale`; no implicit device clock or time-zone interpretation in the parser.
- Only `READY` may carry `draft: CreateReminderInput`. `NEEDS_CONFIRMATION` and `FAILED` carry issues and no saveable draft; the caller keeps the original text for correction.
- Run the full Hypium unit suite and debug `assembleHap` after every task adding production ArkTS. A valid RED is a missing symbol or failing behavioral assertion, not an SDK or test-runner error. Inspect test output, not only exit code.
- Do not push, merge or modify `main`, `develop`, `feature-ui` or `feature-location` without a separate submission decision.

## Wire Contract Decisions

The Stage 3 provider-neutral response is one JSON object with exactly these keys:

```json
{"content":"带电脑","triggerType":"BOTH","triggerTime":1799992800000,"sceneName":"实验室","ambiguous":false}
```

`content` and `triggerType` must be strings, and `ambiguous` must be a boolean. `triggerTime` is a finite Epoch-millisecond number or `null`; `sceneName` is a string or `null`. All five keys must be present, even when the value is `null`; reject extra keys, arrays, primitive JSON and Markdown fences. Empty strings and unsupported trigger values are semantic validation errors. `TIME` requires time and `sceneName: null`; `LOCATION` requires scene name and `triggerTime: null`; `BOTH` requires both. The validator rejects contradictory field combinations rather than guessing a different trigger type. A past time is not silently shifted forward.

Provider failures are values, not provider-specific exceptions: `AIProviderResult` has `rawResponse?: string` on success or a `failure` with `NETWORK_ERROR` / `PROVIDER_ERROR` and `retryable`. An unexpected thrown exception is mapped to retryable `PROVIDER_ERROR` without exposing its text to the UI. Fake fixtures are exact-text lookups injected at construction; unknown text returns non-retryable `PROVIDER_ERROR`, never fabricated AI understanding.

`SceneResolver.resolveByName(sceneName)` follows the existing spec: `RESOLVED` plus one `match`, `AMBIGUOUS` plus candidates, or `NOT_FOUND`. Only a nonblank `match.id` is usable. Resolver rejection is a retryable infrastructure failure, while ambiguous/not-found/malformed results require user confirmation. The formal resolver implementation remains with the location teammate.

## File Map

Production paths in this table are relative to `entry/src/main/ets/`.

| File | Responsibility |
| --- | --- |
| `ai/contract/AIService.ets` | Public `AIParseContext` and `AIService.parseReminder()` contract. |
| `ai/model/AIParseResult.ets` | `AIParseStatus`, issue codes, issues and outcome. |
| `ai/model/AIParsedReminder.ets` | Typed provider-response fields after structural parsing. |
| `ai/provider/AIModelProvider.ets` | Provider request/result/failure contracts. |
| `ai/provider/FakeAIModelProvider.ets` | Deterministic injectable fixture provider. |
| `ai/parser/AIResponseParser.ets` | Strict JSON and schema parsing; no semantic inference. |
| `ai/validator/AIParseValidator.ets` | Trigger combination, content, ambiguity and time checks. |
| `reminder/contract/SceneResolver.ets` | Shared location-name resolution contract; no implementation. |
| `ai/mapper/ReminderMapper.ets` | Validated fields + resolved scene → shared creation input. |
| `ai/DefaultAIService.ets` | Pipeline orchestration and error/status mapping. |
| `entry/src/test/AI*.test.ets`, `List.test.ets` | Unit and end-to-end fake-pipeline tests. |

## Review Focus

- A valid JSON string containing an array, extra key, wrong type or Markdown wrapper is rejected; no draft escapes (Task 2).
- Missing or contradictory fields and `NaN`/infinite/past times never become `READY` (Tasks 2–3).
- A location name that is absent, duplicated or resolved without a usable ID never becomes a saveable draft (Tasks 4–5).
- A provider failure, malformed JSON or resolver rejection does not call ReminderService or save anything; retryability distinguishes infrastructure from content problems (Task 5).
- The same TIME, LOCATION and BOTH output maps to the single public `CreateReminderInput` with `source: AI`; no AI-only Reminder format is created (Tasks 4–5).

---

### Task 1: Public AI and Scene Contracts, Fake Provider

**Files:** Create `entry/src/main/ets/ai/contract/AIService.ets`, `ai/model/AIParseResult.ets`, `ai/model/AIParsedReminder.ets`, `ai/provider/AIModelProvider.ets`, `ai/provider/FakeAIModelProvider.ets`, `reminder/contract/SceneResolver.ets`; create `entry/src/test/AIContracts.test.ets`; modify `entry/src/test/List.test.ets`.

**Interfaces:** Preserve `AIService.parseReminder(text: string, context: AIParseContext): Promise<AIParseOutcome>` and spec Section 8's `SceneResolver.resolveByName(sceneName: string): Promise<SceneResolveResult>`. Define `AIModelProvider.requestParse(text: string, context: AIParseContext): Promise<AIProviderResult>`. `AIParseIssueCode` contains the seven spec codes plus `INVALID_FIELD`, `INVALID_INPUT` and `SCENE_RESOLVER_ERROR`.

- [ ] Write compile-time contract tests for all status values, the spec's Scene resolve shapes, Fake exact fixture hit and unknown-text failure. A fixture returns raw JSON unchanged; unknown text returns `PROVIDER_ERROR`.
- [ ] Run the full Hypium suite and confirm RED is missing modules/symbols.
- [ ] Add contracts and minimal Fake provider. Do not add a default live provider or hardcoded credentials.
- [ ] Run the full suite and debug `assembleHap`; require `BUILD SUCCESSFUL` and no test assertion errors.
- [ ] Review and commit only Task 1 files: `feat: define fake AI and scene resolution contracts`.

### Task 2: Strict Response Parser

**Files:** Create `entry/src/main/ets/ai/parser/AIResponseParser.ets` and `entry/src/test/AIResponseParser.test.ets`; modify `List.test.ets`.

**Interface:** `parseAIResponse(rawResponse: string): AIResponseParseResult`, where success contains `AIParsedReminder` and failure contains `AIParseIssue[]`. A syntax failure uses `INVALID_JSON`; missing keys use `MISSING_FIELD`; wrong types, extra keys and wrong root shape use `INVALID_FIELD`. Parser does not resolve scenes or compare time to `now`.

- [ ] Write tests for a valid TIME/LOCATION/BOTH object, malformed JSON, Markdown fences, array/primitive roots, omitted keys, extra keys, wrong types, and `NaN`/infinite time (non-JSON forms fail parsing).
- [ ] Run full suite; confirm behavioral RED.
- [ ] Implement strict structural parsing with the five-key schema and no coercion from strings to numbers or booleans.
- [ ] Run full suite and debug `assembleHap`; require both successful.
- [ ] Commit Task 2 files: `feat: parse strict AI reminder responses`.

### Task 3: Semantic Validation

**Files:** Create `entry/src/main/ets/ai/validator/AIParseValidator.ets`, `entry/src/test/AIParseValidator.test.ets`; modify `List.test.ets`.

**Interface:** `validateAIParsedReminder(parsed: AIParsedReminder, context: AIParseContext): AIParseIssue[]`. It reports all applicable issues in stable order: content → trigger combination → time → location → ambiguity. No issue means candidate fields are semantically usable, subject to scene resolution.

- [ ] Write tests for empty content, unknown trigger type, all three valid combinations, a missing/invalid/past time, missing scene name, fields inconsistent with TIME or LOCATION, and `ambiguous: true`. Verify issues identify affected fields, are non-retryable, and do not auto-correct values.
- [ ] Run full suite; confirm behavioral RED.
- [ ] Implement minimal pure validation. Map unrecognizable time to `INVALID_TIME`, absent required field to `MISSING_FIELD`, contradictory fields/explicit ambiguity to `AMBIGUOUS_RESULT`.
- [ ] Run full suite and debug `assembleHap`; require both successful.
- [ ] Commit Task 3 files: `feat: validate AI reminder semantics`.

### Task 4: Shared Reminder Mapper and Scene Resolution

**Files:** Create `entry/src/main/ets/ai/mapper/ReminderMapper.ets`, `entry/src/test/ReminderMapper.test.ets`; modify `List.test.ets`.

**Interface:** `mapAIParsedReminder(parsed: AIParsedReminder, scene?: SceneCandidate): CreateReminderInput`. Call only after Task 3 validation and, for LOCATION/BOTH, a `RESOLVED` scene. The result has `source: ReminderSource.AI`; LOCATION/BOTH have `sceneId`, resolved `sceneName` snapshot and `locationTriggerMode: ENTER`; TIME has no location fields.

- [ ] Write tests mapping TIME, LOCATION and BOTH to the exact public input fields; ensure no `id`, `status`, `createdAt` or provider-specific field is introduced.
- [ ] Run full suite; confirm missing-mapper RED.
- [ ] Implement the pure mapper. Do not perform repository writes, trigger registration or scene lookup here.
- [ ] Run full suite and debug `assembleHap`; require both successful.
- [ ] Commit Task 4 files: `feat: map AI results to reminder input`.

### Task 5: AIService Pipeline and Failure Boundaries

**Files:** Create `entry/src/main/ets/ai/DefaultAIService.ets`, `entry/src/test/AIService.test.ets`; modify `List.test.ets`.

**Interface:** `DefaultAIService implements AIService`, constructor-injected `AIModelProvider` and `SceneResolver`. `parseReminder(text, context)` returns `READY` with a single valid draft, `NEEDS_CONFIRMATION` with field-level content issues, or `FAILED` with infrastructure / JSON issues. Before `READY`, run the shared `validateCreateReminderInput(draft, context.now)` as a final invariant check.

- [ ] Write end-to-end Fake-provider tests for TIME, LOCATION, BOTH, ambiguous result, invalid/past time, missing content, scene `NOT_FOUND`/`AMBIGUOUS`/invalid `RESOLVED`, provider network/API failure, unexpected provider throw, resolver rejection and invalid JSON. Assert no `draft` unless `READY`, no resolver call for TIME or earlier-stage failures, and no source-text/exception leakage in infrastructure messages.
- [ ] Run full suite; confirm missing-service RED.
- [ ] Implement orchestration in order: trim/check input → provider → parser → validator → conditional resolver → mapper → shared model validation. Map provider/network/JSON/resolver failures to `FAILED`; incomplete or ambiguous content to `NEEDS_CONFIRMATION`. Never call `ReminderService`.
- [ ] Run full Hypium suite and debug `assembleHap`; require `BUILD SUCCESSFUL` and no assertion errors. Then run `git diff --check`, review `git status`, and scan added files for credentials and unintended system APIs.
- [ ] Commit Task 5 files: `feat: orchestrate fake AI reminder parsing`.

## Phase Handoff

Report exact test/build output, the deterministic Fake provider's inability to understand arbitrary text, the `READY`-only draft rule, SceneResolver's public contract for the location teammate, and the UI handoff (`AIParseOutcome` → user confirmation → `ReminderService.create(draft)`). Keep the real AI provider and any security configuration for the later integration stage. Do not push or merge without a separate submission decision.

Use process-local PowerShell environment settings and these verification commands for each task:

```powershell
$env:DEVECO_SDK_HOME = 'E:/DevEco Studio/sdk'
$env:JAVA_HOME = 'E:/DevEco Studio/jbr'
$env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
& 'E:/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p product=default -p module=entry@default -p buildMode=debug test --no-daemon --stacktrace
& 'E:/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon --stacktrace
```
