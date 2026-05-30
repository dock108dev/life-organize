# Abend Handling Audit

Date: 2026-05-30  
Scope: full repository, with focus on production-path error handling, suppressed/downgraded failures, retries, fallbacks, environment-specific strictness, and observability guardrails.

## Condensed Executive One-Pager

Overall verdict: **Prod posture has notable risk areas.** Most handled failures are intentional and reasonable: backend calls fail closed with sanitized client errors and admin events, iOS extraction failures are persisted into reviewable states, automation-specific fail-fast paths are constrained to tests/screenshot runs, and CI/scripts generally fail closed except for cleanup/log capture.

The main concern is not broad silent failure everywhere. The concern is that a few "best effort" paths either have weak telemetry or can turn resilience into hidden operational risk. The highest priority item is the backend admin event stream: `AdminEventBus.emit()` pushes to bounded subscriber queues with `put_nowait()` and does not isolate queue backpressure. A slow or stuck admin log stream can raise from security/request logging paths and break unrelated API requests.

Severity counts:

| Severity | Count |
|---|---:|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 8 |
| Note | 7 |

Category counts:

| Category | Count |
|---|---:|
| Backend observability/error mapping | 6 |
| iOS extraction/retry/fallback | 5 |
| iOS local data/UI error handling | 4 |
| Runtime/environment strictness | 3 |
| CI/scripts/tooling suppression | 3 |

Top 5 items to address first:

1. **AH-01:** Isolate admin event subscriber queue failures so observability cannot break request handling.
2. **AH-08:** Add local telemetry or durable diagnostic events for automatic pending-message retry failures.
3. **AH-10:** Stop silently collapsing corrupted metadata/evidence JSON to empty arrays without a repair signal.
4. **AH-11:** Avoid showing an empty review queue when queue-entry construction fails.
5. **AH-12:** Add actionable telemetry for launch maintenance repair failures.

## Full Detailed Report

### Section 1: Executive Summary

The repo is a SwiftUI/iOS local-first app backed by a FastAPI service that proxies AI extraction and web requests to OpenAI. The backend has device-token auth, admin log routes, rate limiting, security headers, request-size limits, and production/staging config fail-fast checks. The iOS app persists source messages and extraction attempts locally, maps extraction/network failures into retryable/reviewable state, exposes developer diagnostics behind debug/internal/automation gates, and uses scripts/CI for verification.

Current production suppressions are **mostly intentional and acceptable**, but not all are "notes only." The dominant healthy pattern is controlled downgrade: raw external errors become sanitized app errors, failed extraction attempts become reviewable local records, and automation-only setup failures fail fast. The weaker pattern is missing telemetry around local fallback and corrupted local JSON blobs.

The highest operational risk is that backend observability is not fully isolated from the request path: a bounded SSE subscriber queue can raise from `admin_events.emit()` and convert logging into request failure. The highest data-integrity risk is silent local decode fallback for persisted metadata/review evidence. The highest observability risk is automatic iOS retry and launch maintenance failures that become user-facing generic state but lack a durable diagnostic/audit channel.

### Section 2: Detailed Findings Table

| ID | File path | Function / area | Category | Exact behavior | Trigger / failure mode | Current handling | Prod impact | Observability impact | Data integrity risk | Security risk | Reliability risk | Recommended disposition | Severity | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AH-01 | `Backend/app/admin_events.py:69` | `AdminEventBus.emit` | Observability guardrail | Uses `subscriber.put_nowait(event)` with no isolation | Slow/stuck admin SSE consumer fills queue | Exception can escape logging path | Request/security paths that emit events can fail | High: logging transport affects app flow | None direct | Medium: auth/rate-limit logging path can be impacted | High | Fix now | High | High |
| AH-02 | `Backend/app/services/openai_gateway.py:158` | OpenAI gateway network calls | Backend error mapping | Catches timeout/network errors, emits admin events, raises sanitized `OpenAIGatewayError` | OpenAI timeout/network failure | Logged, converted to bounded client error | Acceptable controlled failure | Good, but in-memory only | None | Low, details sanitized | Low | Accept as intentional | Note | High |
| AH-03 | `Backend/app/services/openai_gateway.py:203` | OpenAI response parse | Backend downgrade | Broad `except Exception` converts malformed/missing output to `invalid_model_response` | Non-JSON response, missing output text, schema drift | Emits admin event, returns 422 via route | Acceptable, but broad catch should remain scoped | Good event, no body leak | Low | Low | Low | Document and test | Low | High |
| AH-04 | `Backend/app/middleware/request_size.py:23` | Request size middleware | Input fallback | Invalid `Content-Length` is ignored and body-stream limit is used for body methods | Malformed header | `pass`; POST/PUT/PATCH still stream-limited | Acceptable for write methods | No event for malformed header | None | Low | Low | Accept; optional metric | Note | High |
| AH-05 | `Backend/app/admin_events.py:84` | SSE stream | Retry/keepalive | `TimeoutError` becomes keepalive comment | No events for 15s | Sends SSE keepalive | Healthy behavior | Explicit connection liveness | None | None | Low | Accept | Note | High |
| AH-06 | `Backend/app/config.py:37`, `Backend/infra/api-entrypoint.sh:6` | Runtime config | Env strictness | Production/staging missing secrets fail at startup; dev uses defaults | Missing prod env or localhost DB URL | Raises error / shell parameter expansion | Strong fail-closed posture | Startup error is visible | None | Lowers secret misuse risk | Low | Accept | Note | High |
| AH-07 | `Backend/main.py:15` | FastAPI docs | Prod quieting | Docs/OpenAPI hidden in production/staging | `ENVIRONMENT=production|staging` | Routes disabled | Appropriate prod quieting | Intent verified by tests | None | Lowers recon surface | Low | Accept | Note | High |
| AH-08 | `LifeOrganize/Features/Settings/SettingsView.swift:379` | Token save automatic retry | Silent async fallback | Starts `retryRecentPendingMessages()` with `try?` | Auto retry fails after token reconnect | Failure is discarded; user only sees token saved | Pending work may remain stale until manual action | Medium blind spot | Medium: pending entries not retried as expected | None | Medium | Fix soon | Medium | High |
| AH-09 | `LifeOrganize/Services/ChatSendService.swift:59` | Extraction send | Resilience | Catches extraction errors and persists failed/pending states | Network/server/token/model failure | Saved source message, attempt failure, review/retry state | Good local-first behavior | Local state visible; no external telemetry | Low | None | Low | Accept with better telemetry | Low | High |
| AH-10 | `LifeOrganize/Services/ChatSendService.swift:130` | Web answer mode | Downgrade | Web answer errors become generic assistant unavailable message | Backend/web/OpenAI failure for answer-only request | No failed attempt; generic assistant message saved | User sees graceful degradation | Low detail; no durable error code | Low for answer mode | None | Low | Document; optional diagnostics | Low | Medium |
| AH-11 | `LifeOrganize/Models/Event.swift:82`, `LifeOrganize/Models/LedgerReviewItem.swift:137` | Persisted JSON blobs | Silent data fallback | Decode failure returns `[]`; encode failure returns `"[]"` | Corrupted metadata/evidence JSON or encoding failure | Data silently disappears from UI/model access | Can hide local corruption | High blind spot | Medium: metadata/review evidence loss | Low | Medium | Tighten before prod | Medium | High |
| AH-12 | `LifeOrganize/Features/Shared/LedgerReviewQueueView.swift:41` | Review queue rendering | Silent UI fallback | `try? queueService.entries(...) ?? []` | Queue entry construction fails | Review queue appears empty | Hidden review backlog | Medium blind spot | Medium: user may miss review items | None | Medium | Fix soon | Medium | Medium |
| AH-13 | `LifeOrganize/AppRootView.swift:282` | Launch maintenance | Logged-to-UI only | Catches maintenance repair errors and sets generic banner | Derived field/review generation repair fails | Generic user message | App continues, but stale derived fields possible | Medium: no technical detail channel | Medium: stale counts/review state | None | Medium | Add telemetry/diagnostics | Medium | High |
| AH-14 | `LifeOrganize/Features/Settings/SettingsView.swift:347` | Settings token/export/clear flows | User-facing catch | Generic feedback on keychain/export/clear failures | Keychain, file write, delete, model save failure | UI feedback only | Acceptable UX | Debug detail not retained | Low to medium depending action | Low | Low | Keep; add diagnostics for clear/export | Low | High |
| AH-15 | `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:274` | Runtime argument parsing | Safe defaulting | Invalid AI base URL or non-HTTPS production URL falls back to default | Bad launch arg or unsafe HTTP URL | Default service URL used | Safer than fail-open | Can hide typo in tests | None | Lowers transport risk | Low | Accept; test/document | Note | High |
| AH-16 | `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:294` | Screenshot/runtime args | Silent automation defaults | Bad locale/time zone/calendar/fixed date returns nil/default | Bad automation arg | Default runtime behavior | Test determinism can silently drift | Low | None | None | Low | Document or assert in automation | Low | Medium |
| AH-17 | `LifeOrganize/LifeOrganizeApp.swift:35`, `LifeOrganize/Persistence/ModelContainerFactory.swift:35` | Startup/model setup | Fail-fast | Catches startup/model errors and `preconditionFailure`s | Store/migration/seed load failure | App crashes early | Appropriate for unrecoverable local store boot | Crash signal visible; no graceful recovery | Prevents partial corrupt state | None | Medium but intentional | Accept, document | Note | High |
| AH-18 | `LifeOrganize/Persistence/SeedScenarioLoader.swift:11`, `LifeOrganize/Features/Debug/QAInternalServices.swift:66` | Seed fixtures | Automation-only fallback | Seeds ignored outside automation; bad QA fixture descriptors skipped | Prod launch with seed args; corrupt QA fixture | No prod load; QA list omits bad descriptor | Acceptable non-prod behavior | QA omission can hide bad fixture | None prod | None | Low | Accept; add fixture validation in CI | Low | High |
| AH-19 | `Scripts/verify-ios.sh:150` | iOS verification | Downgraded tool failure | Accepts nonzero `xcodebuild` if xcresult/log prove clean pass and build errors absent | Xcode exits 65 after clean XCTest | Continues, then runs coverage | Practical CI false-negative handling | Prints explicit warning | None | None | Low if parser regresses | Accept; keep tests | Note | High |
| AH-20 | `Scripts/simulator-common.sh:52`, `.github/workflows/backend-ci-cd.yml:404` | Scripts/deploy cleanup | Suppressed cleanup/log errors | `|| true` around simulator resets, Docker prune, log capture | Cleanup command unsupported/fails | Continue | Mostly acceptable best effort | Low unless cleanup failure causes flakes | None | None | Low | Accept; document | Note | High |
| AH-21 | `Scripts/secret_scan.py:74` | Secret scanning | Tooling suppression | Unicode decode failures return no findings; allowlist suppresses known fixture/docs strings | Tracked binary/non-UTF8 file or allowlisted test/doc string | File skipped or rule suppressed | CI can miss secrets in binary/non-UTF8 tracked files | Low blind spot | None runtime | Medium if real secret lands in skipped class | Low | Improve later | Low | Medium |
| AH-22 | `Scripts/verify-all.sh:59`, `Scripts/verify-backend.sh:92` | Local verification | Optional strictness | Backend Docker smoke and prod smoke are opt-in locally | Engineers run default full verify | Smoke drift not checked locally | CI/deploy still cover prod health | Low | None | Low | Low | Accept, document command expectations | Low | High |

### Section 3: Finding Details

#### AH-01: Admin event delivery can break request handling

Locations:

- `Backend/app/admin_events.py:69`
- `Backend/app/admin_events.py:80`
- Event emitters in `Backend/app/auth.py`, `Backend/app/routers/ai.py`, and `Backend/app/services/openai_gateway.py`

The admin event bus is clearly intended as bounded, in-memory, best-effort observability: recent events are capped and SSE subscribers have queues capped at 100. However, `emit()` calls `subscriber.put_nowait(event)` directly. If a subscriber queue fills, `asyncio.QueueFull` can propagate out of `emit()`. Since `emit()` is used in auth rejection, rate limiting, OpenAI request logging, startup events, and admin actions, a slow admin log stream can turn observability backpressure into request failures.

Why it exists: the code is intentionally lightweight and avoids blocking request handlers on SSE subscribers.

Why it may be safe: in normal use, browsers consume SSE quickly and the in-memory queue is enough.

Why it is risky: the failure mode crosses a trust boundary. A read-only admin diagnostic page should not be able to destabilize API request paths. It also affects security-event logging paths.

Recommendation: catch `asyncio.QueueFull` in `emit()`, drop the event for that subscriber or remove the subscriber, and emit/drop a single bounded diagnostic counter if a metrics channel exists. Add a unit test that fills a subscriber queue and verifies `emit()` does not raise.

Disposition: **Fix now.**

#### AH-02: OpenAI timeout/network failures are intentionally sanitized

Location: `Backend/app/services/openai_gateway.py:158`

The gateway catches `httpx.TimeoutException` and `httpx.HTTPError`, emits admin events, and raises `OpenAIGatewayError` values with bounded codes such as `timeout` and `network_unavailable`. Routes convert these into structured HTTP errors and write request logs.

This is healthy resilience. It prevents raw exception details, API keys, request payloads, or upstream response bodies from leaking to clients while preserving admin-visible status and request metadata.

Recommendation: accept. Keep tests around timeout/network mapping and admin event sanitization.

Disposition: **Accepted prod note.**

#### AH-03: OpenAI response parsing uses a broad catch by design

Location: `Backend/app/services/openai_gateway.py:203`

The gateway catches any exception while parsing `response.json()` and `_output_text(body)`, emits an admin error, and raises `invalid_model_response`.

This is intentionally broad at a narrow boundary. The code already avoids returning raw upstream body details to clients and includes the OpenAI request id in the admin event when present.

Risk: broad catches can hide schema drift if admin events are not monitored. This is not a direct security issue because the response body is not reflected to the user.

Recommendation: keep the broad catch scoped here, but ensure tests cover malformed JSON, missing output, and OpenAI response-shape changes.

Disposition: **Accept, document, test.**

#### AH-04: Malformed Content-Length is ignored but body-stream enforcement remains

Location: `Backend/app/middleware/request_size.py:23`

Invalid `Content-Length` is caught with `except ValueError: pass`. For `POST`, `PUT`, and `PATCH`, the middleware still reads and enforces `MAX_REQUEST_BYTES` against the stream. Non-body methods pass through.

This is acceptable. It avoids trusting a malformed header and still enforces the body limit where it matters.

Recommendation: optional low-value metric for malformed content length. No functional change required.

Disposition: **Accepted prod note.**

#### AH-05: Admin SSE keepalive converts idle timeout to a comment

Location: `Backend/app/admin_events.py:84`

`asyncio.wait_for(queue.get(), timeout=15)` catches `TimeoutError` and yields `: keepalive`. This is correct SSE behavior and not an error suppression.

Recommendation: accept.

Disposition: **Accepted prod note.**

#### AH-06: Production config is fail-closed while development has defaults

Locations:

- `Backend/app/config.py:37`
- `Backend/infra/api-entrypoint.sh:6`

Production and staging require OpenAI key, admin key, device-token signing secret, and non-localhost DB URL. Development defaults remain permissive for local setup.

This is a healthy environment-specific strictness difference. It is intentionally quieter/permissive in development and stricter in production.

Recommendation: accept. Keep tests in `Backend/tests/test_auth_config.py`.

Disposition: **Accepted prod note.**

#### AH-07: Backend docs and OpenAPI are intentionally hidden in prod/staging

Location: `Backend/main.py:15`

FastAPI docs, ReDoc, and OpenAPI routes are disabled for production/staging. Tests verify the behavior in `Backend/tests/test_app_entrypoint.py:233`.

This is acceptable production quieting.

Recommendation: accept.

Disposition: **Accepted prod note.**

#### AH-08: Automatic retry after token creation is silently discarded

Location: `LifeOrganize/Features/Settings/SettingsView.swift:379`

After creating/loading a service token, Settings marks pending-token messages retryable, then starts an async retry task with `try? await retryService.retryRecentPendingMessages()`. Any failure is discarded.

Why it exists: token setup should remain responsive, and failed entries can still be retried later.

Why it may be safe: messages are already persisted locally, marked retryable, and manual retry paths exist.

Why it is risky: the user receives `deviceTokenSaved` feedback even if the immediate recovery attempt fails. There is no durable diagnostic event, count, or UI hint that backlog processing did not run.

Recommendation: replace `try?` with a small catch that records a local diagnostic status or sets feedback such as "connected; retry will continue later" when retry fails. Tests should cover failed retry does not lose pending messages and surfaces a diagnosable state.

Disposition: **Fix soon.**

#### AH-09: Extraction failures are persisted as reviewable/retryable state

Locations:

- `LifeOrganize/Services/ChatSendService.swift:59`
- `LifeOrganize/Services/ChatSendServiceRetry.swift:20`

The send and retry flows catch extraction client errors and call `fail(...)`, which maps errors to local extraction statuses, error codes, normalized warning JSON, assistant messages, and retry timing.

This is good local-first behavior. It avoids losing the user-entered text and makes failure recoverable.

Risk: iOS has no external telemetry channel, so fleet-level failure rates are only visible if users export/debug local data or backend logs see failed requests.

Recommendation: accept the pattern; add local diagnostics or privacy-safe aggregate telemetry if production support requires fleet visibility.

Disposition: **Accept with telemetry improvement.**

#### AH-10: Web answer failures downgrade to a generic assistant response

Location: `LifeOrganize/Services/ChatSendService.swift:130`

For answer-only web lookup mode, failures are caught and a generic "unavailable" assistant message is persisted. No extraction attempt exists because no structured import is expected.

This is reasonable for answer-only requests, but it can make service outages appear as normal conversational fallback in local history.

Recommendation: optionally attach a non-sensitive local error code to the assistant message or internal diagnostics so support can distinguish "no answer" from backend failure.

Disposition: **Accept but document.**

#### AH-11: Persisted metadata/evidence decode failures silently become empty arrays

Locations:

- `LifeOrganize/Models/Event.swift:82`
- `LifeOrganize/Models/LedgerReviewItem.swift:137`
- `LifeOrganize/Services/LedgerReviewItemGenerationSupport.swift:52`

Corrupt or incompatible JSON blobs for event metadata, review item evidence, or normalized extraction envelopes are decoded with `try?` and collapse to `[]` or `nil`.

Why it exists: model accessors stay non-throwing and UI rendering remains stable.

Why it may be safe: these blobs are app-generated, not arbitrary network input, and the fallback prevents crashes.

Why it is risky: local corruption or migration mistakes can erase important context from UI and exports without any repair signal. This is a data-integrity and observability risk rather than a classic security issue.

Recommendation: keep non-throwing accessors if needed, but add a validation/repair path that records corrupt blob counts, marks affected records for review, and includes corrupted-field diagnostics in developer tools/export validation.

Disposition: **Tighten before broader production reliance.**

#### AH-12: Review queue construction failure appears as an empty queue

Location: `LifeOrganize/Features/Shared/LedgerReviewQueueView.swift:41`

The queue view computes entries with `(try? queueService.entries(from: reviewItems, origin: origin)) ?? []`. Any construction failure becomes an empty queue.

Why it exists: it keeps the view from throwing during rendering.

Why it is risky: review is the app's recovery surface. Showing no review items when entries failed to build can hide pending/corrupt/ambiguous records from the user.

Recommendation: compute queue entries in a view model or service boundary where errors can set an explicit "Review could not load" state. Add tests for a throwing queue service.

Disposition: **Fix soon.**

#### AH-13: Launch maintenance failures are reduced to a generic banner

Location: `LifeOrganize/AppRootView.swift:282`

Launch maintenance repairs interrupted extractions, derived fields, and review items. Errors set `maintenanceErrorMessage = "Some cached ledger fields could not be refreshed."`.

Why it exists: the app should still open if derived caches cannot be repaired immediately.

Why it is risky: stale derived fields and review state can persist without a durable diagnostic trail. Users may see a generic banner, but engineers cannot distinguish migration failure, review-generation failure, or data corruption.

Recommendation: split the three maintenance operations into separately named diagnostics and store a local developer-mode event. Preserve the generic user message.

Disposition: **Add telemetry/diagnostics.**

#### AH-14: Settings token/export/clear failures use generic user feedback only

Locations:

- `LifeOrganize/Features/Settings/SettingsView.swift:347`
- `LifeOrganize/Features/Settings/SettingsView.swift:388`
- `LifeOrganize/Features/Settings/SettingsView.swift:404`

Settings catches keychain read/write/delete, local clear, and export failures, then maps them to generic feedback states.

This is acceptable user-facing error handling. It avoids exposing OSStatus/internal file details in UI.

Risk: support/debugging is limited if clear/export fails repeatedly.

Recommendation: keep generic UI, add internal diagnostics for operation name and sanitized error type.

Disposition: **Low-priority improvement.**

#### AH-15: Unsafe or invalid AI service base URLs fall back to the production default

Location: `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:274`

The app accepts HTTPS URLs, accepts HTTP only for automation/loopback, and otherwise returns `defaultAIServiceBaseURL`.

This is security-positive. It avoids fail-open to plaintext remote HTTP and protects users from unsafe launch arguments.

Risk: in automation, a typo can silently target production default instead of the intended test service.

Recommendation: accept for production; consider stricter assertions in UI-test mode when `-ai-service-base-url` is present but invalid.

Disposition: **Accepted prod note.**

#### AH-16: Invalid screenshot/runtime arguments silently default

Locations:

- `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:255`
- `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:294`
- `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:301`
- `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:308`

Bad fixed-date, locale, timezone, or calendar arguments fall back to default runtime values.

This is mostly an automation determinism concern, not production risk.

Recommendation: add an automation-only diagnostic or precondition when an argument prefix is present but invalid.

Disposition: **Document or improve later.**

#### AH-17: Startup/model setup fails fast

Locations:

- `LifeOrganize/LifeOrganizeApp.swift:35`
- `LifeOrganize/Persistence/ModelContainerFactory.swift:35`
- `LifeOrganize/Utilities/AppRuntimeConfiguration.swift:349`

Model container creation, launch seed loading, and automation storage setup use `preconditionFailure` after catching errors.

This is intentional fail-fast behavior. It prevents the app from continuing with a broken persistence stack or invalid automation state.

Recommendation: accept. For production user recovery, consider a future safe-mode/reset UX for model container creation failure, but do not silently continue.

Disposition: **Accepted prod note.**

#### AH-18: Seed fixtures are automation-only; QA descriptor loading skips bad fixtures

Locations:

- `LifeOrganize/Persistence/SeedScenarioLoader.swift:11`
- `LifeOrganize/Features/Debug/QAInternalServices.swift:66`

Seed scenarios are ignored unless the runtime is automation. Debug QA descriptor enumeration uses `try?`, so bad fixtures are omitted from the list.

This is acceptable outside production. The only concern is test/QA coverage: a bad fixture may disappear instead of failing the QA lab list.

Recommendation: keep production guard. Add fixture validation to CI so bad fixtures fail visibly.

Disposition: **Low-priority tooling improvement.**

#### AH-19: iOS verifier downgrades some `xcodebuild` exit 65 cases

Location: `Scripts/verify-ios.sh:150`

The script runs `xcodebuild` under `set +e`, then accepts a nonzero exit only when xcresult/log parsing shows tests passed and the build summary has no errors.

This is deliberate handling of a known Xcode false-negative shape. The script emits a warning when it continues.

Risk: parser drift could mask a real issue if xcresult formats change. The current logic checks executed tests, failure details, final log, and build errors, which is appropriately defensive.

Recommendation: accept. Keep `Tests/verify_scripts/test_verify_scripts.py` coverage for this behavior.

Disposition: **Accepted prod note.**

#### AH-20: Cleanup and log-capture errors are intentionally non-fatal

Locations:

- `Scripts/simulator-common.sh:52`
- `Scripts/simulator-common.sh:56`
- `Scripts/simulator-common.sh:58`
- `Backend/infra/scripts/docker_smoke.sh:30`
- `.github/workflows/backend-ci-cd.yml:404`

Several scripts use `|| true` for cleanup, simulator UI reset, Docker prune, and best-effort log capture.

These are acceptable suppressions because they are ancillary. The primary build/test/deploy checks remain fail-closed.

Recommendation: document this convention: `|| true` is allowed only for cleanup/log capture/environment normalization, not for validation or deploy success criteria.

Disposition: **Accepted prod note.**

#### AH-21: Secret scan skips unreadable files and has narrow allowlists

Location: `Scripts/secret_scan.py:74`

The scanner catches `UnicodeDecodeError` and returns no findings for that file. It also allowlists known fixture/docs strings and only scans `git ls-files`.

This is reasonable for a lightweight repo-local scan, but it is not a full secret-detection platform.

Recommendation: keep this fast CI check, add or rely on platform-level secret scanning for binary/untracked/history coverage, and periodically review the allowlist.

Disposition: **Improve later / platform-level.**

#### AH-22: Local smoke checks are opt-in

Locations:

- `Scripts/verify-all.sh:59`
- `Scripts/verify-backend.sh:92`

Default local verification runs backend checks, iOS tests, coverage, and screenshots. Backend Docker smoke and production smoke are opt-in.

This is acceptable for developer ergonomics because deploy workflows include health checks. The gap is documentation: engineers need to know when release validation requires opt-in smoke.

Recommendation: document release commands and add CI schedules if production drift detection becomes important.

Disposition: **Low-priority documentation.**

### Section 4: Findings Buckets

#### Acceptable prod notes

- AH-02: OpenAI timeout/network sanitization.
- AH-04: Malformed `Content-Length` falls back to stream enforcement.
- AH-05: SSE idle timeout keepalive.
- AH-06: Production/staging config fail-closed; dev defaults.
- AH-07: Prod/staging docs hidden.
- AH-15: Unsafe AI base URL falls back to HTTPS default.
- AH-17: Startup/model setup fail-fast.
- AH-19: `xcodebuild` exit 65 false-negative handling with independent proof.
- AH-20: Cleanup/log-capture `|| true`.

#### Acceptable but should be documented

- AH-03: Broad OpenAI parse catch is acceptable only at this narrow boundary.
- AH-10: Web answer fallback is acceptable for answer-only mode.
- AH-18: Automation-only seed behavior and QA descriptor skipping.
- AH-22: Local smoke checks are opt-in.

#### Acceptable but needs better telemetry

- AH-09: Extraction failures are persisted locally but not surfaced as fleet metrics.
- AH-13: Launch maintenance failure needs structured local diagnostics.
- AH-14: Settings failures need sanitized internal diagnostics.
- AH-16: Invalid automation args should be visible to test owners.

#### Should be tightened before prod

- AH-08: Silent automatic retry failure after token setup.
- AH-11: Corrupt persisted metadata/evidence collapsing to empty arrays.
- AH-12: Review queue entry failure showing an empty queue.

#### High risk / hidden failure

- AH-01: Admin event subscriber queue backpressure can escape observability code and fail request paths.

#### Security-sensitive suppression

- AH-01: Affects security-event emitters and auth/rate-limit request paths.
- AH-02/AH-03: Sanitizes upstream OpenAI failures appropriately.
- AH-06/AH-07/AH-15: Security-positive environment/default behavior.
- AH-21: Lightweight secret scanning has acceptable but incomplete coverage.

#### Data loss / corruption risk

- AH-11: Silent JSON decode fallback hides corrupted metadata/evidence.
- AH-12: Review queue empty fallback may hide reviewable records.
- AH-13: Maintenance failure may leave stale derived fields.

#### Observability blind spot

- AH-08: Silent automatic retry failure.
- AH-10: Web answer failures indistinguishable from generic unavailable answer.
- AH-13/AH-14: Generic UI feedback without durable diagnostic details.
- AH-16: Invalid automation arguments silently default.
- AH-21: Secret scan intentionally incomplete for binary/history/untracked coverage.

### Section 5: Environment Review

Where prod is quieter than non-prod:

- Backend docs/OpenAPI are disabled in production/staging (`Backend/main.py:15`).
- Admin page security headers include no-store/noindex behavior (`Backend/app/routers/admin.py:112`).
- iOS developer diagnostics are limited to debug/internal builds or automation gates (`LifeOrganize/Utilities/AppRuntimeConfiguration.swift:90`).

Where prod is more permissive than non-prod:

- The iOS app allows normal local-first capture even when AI service token/backend work fails. This is intentional product behavior, not an auth bypass.
- Backend development allows missing admin/OpenAI/device-token secrets; production/staging fail closed.

Where prod may fail open:

- No confirmed production fail-open auth path was found in this audit.
- `AUTO_ENROLL_DEVICE_TOKENS` remains a security/product posture setting; it is not an error suppression, but production should explicitly decide whether unknown device tokens should auto-enroll.

Where prod may hide actionable errors:

- Local iOS automatic retry failures after token setup.
- Local metadata/evidence decode failures.
- Review queue construction failures.
- Launch maintenance failures.
- Secret scanner skipped binary/non-UTF8 tracked files.

Reasonableness:

Most environment differences are reasonable. The main exception is observability: production paths need durable enough signals that fallback behavior does not become invisible support debt.

### Section 6: Recommended Remediation Plan

#### Quick wins

| Priority | Summary | Why it matters | Rough implementation approach | Complexity | Change risk | Owner |
|---:|---|---|---|---|---|---|
| 1 | Isolate `AdminEventBus.emit()` from subscriber backpressure | Prevents diagnostics from breaking request paths | Catch `asyncio.QueueFull`, drop/remove subscriber, add test with full queue | Small | Low | Backend |
| 2 | Replace Settings retry `try?` with explicit catch | Makes reconnect recovery failures visible | Catch error, preserve retryable state, set diagnostic/feedback | Small | Low | Frontend |
| 3 | Add a review queue load error state | Avoids hidden review backlog | Replace `try? ?? []` with explicit error state/view model | Small/Medium | Medium | Frontend |
| 4 | Document accepted suppression conventions | Prevents future misuse of `try?`, `|| true`, broad catches | Add short engineering note to docs | Small | Low | Security/Platform |

#### Medium effort cleanup

| Priority | Summary | Why it matters | Rough implementation approach | Complexity | Change risk | Owner |
|---:|---|---|---|---|---|---|
| 5 | Add local diagnostic event store for iOS non-fatal failures | Gives support/debug tools durable visibility | Store operation, sanitized error type, timestamp; expose in developer diagnostics/export | Medium | Medium | Frontend |
| 6 | Validate persisted JSON blobs and surface corrupt fields | Prevents silent data/evidence loss | Add validation service for metadata/evidence/envelopes; mark affected records | Medium | Medium | Frontend |
| 7 | Split launch maintenance diagnostics by operation | Identifies which repair failed | Catch each maintenance call separately; store sanitized diagnostic | Small/Medium | Low | Frontend |
| 8 | Add automation-argument strictness when arg prefix is present | Reduces false deterministic test runs | Precondition or test failure for invalid screenshot/runtime args in automation | Small | Low | Frontend |

#### High value hardening

| Priority | Summary | Why it matters | Rough implementation approach | Complexity | Change risk | Owner |
|---:|---|---|---|---|---|---|
| 9 | Add backend metrics/log sink beyond in-memory admin events | In-memory logs disappear on restart and are not alertable | Add structured app logger or metrics counters for OpenAI failures/auth rejects/rate limits | Medium | Low/Medium | Backend/DevOps |
| 10 | Add privacy-safe iOS failure aggregates if product permits | Supports production support without collecting raw user text | Count error classes only; never include message text/raw model output | Medium/Large | Product/privacy review needed | Product/Security/Frontend |
| 11 | Platform secret scanning | Local regex scanner is not full coverage | Enable provider secret scanning and history scanning outside repo | Medium | Low | DevOps/Security |

#### Documentation gaps

- Define allowed suppression patterns:
  - broad catch allowed at external service boundaries only when mapped to sanitized typed errors
  - `try?` allowed in pure formatting/debug helpers, not in recovery surfaces unless a diagnostic is recorded
  - `|| true` allowed for cleanup/log capture only
  - production quieting must be covered by tests
- Document release validation commands including `Scripts/verify-backend.sh --with-smoke` and deploy smoke behavior.
- Document `AUTO_ENROLL_DEVICE_TOKENS` as a production posture decision.

#### Test gaps

- Unit test `AdminEventBus.emit()` with a full subscriber queue.
- Settings token reconnect test where pending retry throws and the message remains retryable with visible diagnostic.
- Review queue view/model test where entry generation throws and the UI does not show an empty success state.
- Local JSON blob corruption tests for event metadata, review evidence, and normalized extraction envelopes.
- Launch maintenance test that one repair failure is recorded without blocking other safe repairs.
- Automation runtime tests for invalid `-ai-service-base-url`, screenshot time zone, calendar, and fixed date.

#### Telemetry / alerting gaps

- Backend: counters for OpenAI timeout/network/auth/model-response failures, device-token rejects, revoked-token rejects, rate-limit rejects, admin-auth misconfiguration.
- iOS local diagnostics: operation name, sanitized error class, affected local record id, timestamp; no raw user text, request JSON, or model output.
- CI: continue using `secret_scan.py`, but pair it with platform secret scanning and dependency audit gates.

## Prioritized Remediation Checklist

- [ ] AH-01: Make admin event subscribers best-effort and non-throwing.
- [ ] AH-08: Remove `try?` from automatic pending retry and record/surface failure.
- [ ] AH-12: Replace review queue empty fallback with explicit load error state.
- [ ] AH-11: Add corruption diagnostics for persisted metadata/evidence/envelope JSON.
- [ ] AH-13: Split launch maintenance errors by repair operation.
- [ ] AH-14: Add sanitized local diagnostics for settings clear/export/keychain failures.
- [ ] AH-16: Add automation-only validation for invalid runtime arguments.
- [ ] AH-18: Add seed fixture validation to CI.
- [ ] AH-21: Pair repo regex secret scan with platform-level secret scanning.
- [ ] AH-22: Document smoke-check expectations for releases.

## Leadership Summary

The codebase does not show a pattern of careless blanket swallowing in production. Most suppressions are purposeful resilience: backend errors are sanitized and logged, iOS preserves user input through extraction failures, and scripts fail closed on real validation steps.

The biggest actual risks are operational and data-integrity blind spots:

- Admin event streaming can currently make logging backpressure break request paths.
- Some iOS recovery failures are silently discarded or reduced to generic UI state.
- Corrupt local JSON blobs can collapse to empty data without a repair signal.
- Review queue generation can fail into an empty-looking queue.

What is already reasonably okay:

- Backend OpenAI timeout/network/error mapping.
- Production config fail-closed behavior.
- Production docs/OpenAPI quieting.
- Request body size fallback enforcement.
- CI `xcodebuild` false-negative handling with independent proof.
- Cleanup/log-capture suppressions in scripts.

What should be fixed before broader exposure:

- AH-01, AH-08, AH-11, AH-12, and AH-13.

What can be phased later:

- Better local diagnostics, platform-level secret scanning, automation-argument strictness, fixture validation, and release-smoke documentation.

Direct verdict: **Prod posture has notable risk areas**, mainly around observability isolation and hidden local recovery/data-integrity failures. The posture is not broadly unsafe, but it is not yet “notes only.”
