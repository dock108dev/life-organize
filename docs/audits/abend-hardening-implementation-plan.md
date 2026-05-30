# Abend Hardening Implementation Plan

Date: 2026-05-30  
Source audit: `docs/audits/abend-handling-audit.md`  
Goal: address all identified abend-handling risks, improve observability and tests, and define a practical production-readiness path.

## Executive Plan

The repo is close to a healthy posture, but it is not yet "prod ready" for abend handling because a few best-effort paths can either hide meaningful failures or, in one case, allow observability backpressure to affect request handling.

Production readiness should be treated as three tracks:

1. **Release blockers:** fix paths that can break production behavior or hide critical recovery state.
2. **Production hardening:** add durable diagnostics, validation, and tests so handled failures remain visible.
3. **Operational maturity:** document suppression conventions and add CI/platform checks to prevent regressions.

Recommended execution order:

| Phase | Scope | Target outcome |
|---|---|---|
| Phase 0 | Confirm scope and baseline | Current tests pass; report and plan are accepted as the source of truth |
| Phase 1 | Release blockers | No logging backpressure failures; retry/review/corruption paths no longer fail silently |
| Phase 2 | Production diagnostics | Non-fatal iOS/backend failures have local/admin-visible diagnostic signals |
| Phase 3 | Test and CI hardening | Regression tests cover accepted suppressions and risky fallbacks |
| Phase 4 | Ops and documentation | Engineers know which suppressions are allowed, monitored, and release-gated |

Recommended production gate: **do not broaden production exposure until Phase 1 is complete and verified.** Phase 2 should be completed before relying on production support workflows at scale.

## Risk-to-Work Mapping

| Finding | Risk summary | Plan item(s) | Release gate |
|---|---|---|---|
| AH-01 | Admin event subscriber backpressure can break request paths | P1-01 | Yes |
| AH-02 | OpenAI network errors are sanitized and logged | P3-01, P4-01 | No |
| AH-03 | OpenAI parse broad catch needs bounded tests/docs | P3-01, P4-01 | No |
| AH-04 | Malformed content length has acceptable fallback | P3-02, P4-01 | No |
| AH-05 | SSE keepalive is intentional | P4-01 | No |
| AH-06 | Prod config fail-closed | P3-03 | Yes, keep tested |
| AH-07 | Prod docs hidden | P3-03 | Yes, keep tested |
| AH-08 | Automatic retry after token setup is silently discarded | P1-02, P2-01, P3-04 | Yes |
| AH-09 | Extraction failures are persisted but lack broader telemetry | P2-01, P3-05 | No |
| AH-10 | Web answer fallback lacks durable error signal | P2-01, P3-05 | No |
| AH-11 | Corrupt persisted JSON collapses to empty/nil | P1-03, P2-02, P3-06 | Yes |
| AH-12 | Review queue failure looks empty | P1-04, P3-07 | Yes |
| AH-13 | Launch maintenance failure is generic only | P1-05, P2-01, P3-08 | Yes |
| AH-14 | Settings failures lack diagnostic detail | P2-01, P3-09 | No |
| AH-15 | Unsafe AI base URL safely defaults | P3-10, P4-01 | No |
| AH-16 | Bad automation args silently default | P2-03, P3-10 | No |
| AH-17 | Startup/model setup fail-fast | P4-01, P4-03 | No |
| AH-18 | Bad QA fixtures can be omitted | P3-11 | No |
| AH-19 | `xcodebuild` exit 65 false-negative handling | P3-12, P4-01 | No |
| AH-20 | Cleanup/log capture `|| true` | P4-01 | No |
| AH-21 | Secret scanner is lightweight/incomplete | P3-13, P4-02 | No, but required before release branch |
| AH-22 | Smoke checks opt-in locally | P4-04 | No |

## Phase 0: Baseline and Ownership

### P0-01: Establish Current Baseline

- Summary: Run current backend and iOS test gates before making hardening changes.
- Why it matters: separates security hardening regressions from pre-existing dirty-worktree or environment failures.
- Implementation approach:
  - Backend: `python -m pytest Backend/tests --no-cov`, `ruff check Backend/app Backend/tests Backend/infra/scripts`, `python -m compileall Backend/app Backend/tests Backend/infra/scripts`.
  - iOS: run the focused test suites for runtime config, retry/review, export validation, and maintenance before full simulator gate.
  - Scripts: run `python Scripts/secret_scan.py` and `git diff --check`.
- Complexity: small.
- Change risk: low.
- Owner: platform/backend/frontend jointly.
- Acceptance criteria:
  - Baseline results are recorded in the PR or tracking issue.
  - Any pre-existing failures are explicitly separated from hardening changes.

### P0-02: Create Work Tracking from This Plan

- Summary: Convert Phase 1 and Phase 2 items into implementation tickets.
- Why it matters: AH-01, AH-08, AH-11, AH-12, and AH-13 touch different ownership areas.
- Implementation approach:
  - Create one ticket per P1 item.
  - Create one shared diagnostics design ticket for P2-01/P2-02.
  - Tag release blockers clearly.
- Complexity: small.
- Change risk: low.
- Owner: engineering lead/security.
- Acceptance criteria:
  - Every audit finding AH-01 through AH-22 maps to a ticket, explicit acceptance, or documented no-op.

## Phase 1: Release Blockers

### P1-01: Make Admin Event Delivery Non-Throwing

- Covers: AH-01.
- Summary: Ensure admin log streaming backpressure cannot break request/auth/rate-limit paths.
- Why it matters: observability must never become a production request dependency.
- Implementation approach:
  - In `Backend/app/admin_events.py`, wrap each subscriber `put_nowait` in `try/except asyncio.QueueFull`.
  - On full queue, remove the subscriber or drop that event for that subscriber.
  - Maintain bounded in-memory counters such as `dropped_subscriber_events` if useful.
  - Avoid recursively emitting admin events from inside the queue-full handler.
- Expected complexity: small.
- Expected risk of change: low.
- Owner: backend.
- Tests:
  - Unit test that fills a subscriber queue and verifies `emit()` does not raise.
  - Regression test that `emit()` still appends to recent events.
  - Optional route-level test where a full log stream does not break an auth rejection or OpenAI request log.
- Acceptance criteria:
  - `AdminEventBus.emit()` is non-throwing for subscriber queue backpressure.
  - Request/security paths still return their expected response under log-stream pressure.
  - Existing admin log stream behavior remains functional.

### P1-02: Replace Silent Pending Retry Suppression

- Covers: AH-08.
- Summary: Remove `try?` around automatic retry after service token setup.
- Why it matters: token reconnect currently reports success even if pending-message recovery silently fails.
- Implementation approach:
  - In `SettingsView.prepareServiceToken()`, replace `try? await retryService.retryRecentPendingMessages()` with explicit `do/catch`.
  - On failure, keep messages retryable and show a non-alarming but accurate feedback state, for example "Connected. Some saved entries will retry later."
  - Record a local diagnostic event through P2-01 if available; otherwise create a temporary internal status path.
- Expected complexity: small/medium.
- Expected risk of change: medium, because user feedback and async state can be brittle.
- Owner: frontend.
- Tests:
  - Unit/view-model test where retry throws after token creation.
  - Assert pending messages remain `.pendingRetry`.
  - Assert feedback is not the same as a clean retry success.
- Acceptance criteria:
  - No `try?` remains on this recovery path.
  - Failed auto-retry is visible and recoverable.
  - Token save itself still succeeds when retry fails.

### P1-03: Detect Corrupt Persisted JSON Blobs

- Covers: AH-11.
- Summary: Stop silently treating corrupt metadata/evidence/envelope JSON as empty state without a repair signal.
- Why it matters: persisted JSON corruption can hide event metadata, review evidence, or extraction context.
- Implementation approach:
  - Keep non-throwing model accessors if needed for UI stability.
  - Add a validation/diagnostic layer that can detect decode failures for:
    - `LedgerEvent.metadataJSONText`
    - `LedgerReviewItem.evidenceJSONText`
    - `ExtractionAttempt.normalizedJSONText`
  - Introduce a small diagnostic model or service result that records record id, field name, and sanitized error type.
  - Ensure export validation can surface these problems rather than exporting silently empty data.
- Expected complexity: medium.
- Expected risk of change: medium.
- Owner: frontend.
- Tests:
  - Corrupt event metadata JSON creates a diagnostic and does not silently pass validation.
  - Corrupt review evidence JSON creates a diagnostic.
  - Corrupt extraction envelope JSON is detectable by review-generation/export validation.
- Acceptance criteria:
  - UI remains crash-resistant.
  - Corrupt persisted blobs are visible in diagnostics/export validation.
  - No sensitive raw user text is added to diagnostics.

### P1-04: Do Not Render Review Queue Failures as Empty Success

- Covers: AH-12.
- Summary: Replace `(try? queueService.entries(...)) ?? []` with explicit error state.
- Why it matters: Review is the recovery surface. A failed queue build must not look like no work exists.
- Implementation approach:
  - Move queue-entry construction into a small view model or computed state object.
  - Represent states explicitly: `loaded(entries)`, `empty`, `failed(errorSummary)`.
  - Render a visible "Review could not load" state with a retry/reopen option.
  - Record a local diagnostic event once P2-01 exists.
- Expected complexity: medium.
- Expected risk of change: medium.
- Owner: frontend.
- Tests:
  - Inject a throwing queue service and assert the failed state renders.
  - Existing empty queue still renders as empty.
  - Existing queue entries still render normally.
- Acceptance criteria:
  - Review failure cannot be confused with an empty queue.
  - The user can recover by retrying/reopening without data loss.

### P1-05: Split Launch Maintenance Error Handling

- Covers: AH-13.
- Summary: Identify which launch maintenance repair failed instead of one generic catch.
- Why it matters: stale derived fields, recovery repair, and review generation have different impact and remediation paths.
- Implementation approach:
  - In `AppRootView.repairDerivedFields()`, run:
    - `ExtractionRecoveryMaintenanceService.repairInterruptedEntries()`
    - `DerivedFieldMaintenanceService.repairAll()`
    - `LedgerReviewItemGenerationService.refresh()`
    in individually named `do/catch` blocks.
  - Continue running independent repairs when safe.
  - Preserve a generic user banner, but store operation-specific local diagnostics.
- Expected complexity: small/medium.
- Expected risk of change: low/medium.
- Owner: frontend.
- Tests:
  - One repair failure records the correct operation name.
  - Independent later repair still runs when appropriate.
  - User-facing banner remains generic.
- Acceptance criteria:
  - Launch maintenance failures are diagnosable by operation.
  - The app continues only where it is safe to continue.

## Phase 2: Production Diagnostics and Observability

### P2-01: Add a Privacy-Safe Local Diagnostic Event Service

- Covers: AH-08, AH-09, AH-10, AH-13, AH-14.
- Summary: Add a local diagnostic channel for non-fatal iOS failures.
- Why it matters: the iOS app intentionally works offline/local-first, but production support needs visibility into hidden failure classes without collecting sensitive user content.
- Implementation approach:
  - Add a lightweight `LocalDiagnosticEvent` model or in-memory-plus-export service.
  - Fields:
    - `id`
    - `createdAt`
    - `category`
    - `operation`
    - `severity`
    - `errorKind`
    - optional affected local record id
    - non-sensitive metadata only
  - Explicitly prohibit raw user text, request JSON, raw model output, tokens, and backend responses.
  - Record events from:
    - automatic pending retry failure
    - extraction retry/service failure summaries
    - web answer fallback failure
    - launch maintenance failure
    - Settings keychain/export/clear failure
  - Expose in Developer Diagnostics and include counts in local JSON export.
- Expected complexity: medium.
- Expected risk of change: medium.
- Owner: frontend/security.
- Tests:
  - Event creation redacts/prohibits sensitive fields.
  - Each targeted catch path records operation and error kind.
  - Export includes diagnostic counts or records without sensitive payloads.
- Acceptance criteria:
  - Non-fatal production failures are supportable without raw private content.
  - Diagnostics are bounded or manageable for local storage.

### P2-02: Add Data Integrity Validation and Repair Reporting

- Covers: AH-11.
- Summary: Create a central local data-integrity pass for silent fallback classes.
- Why it matters: corruption and migration mistakes should become visible before they affect user trust.
- Implementation approach:
  - Add `LocalDataIntegrityValidator` that scans persisted JSON fields and relationship/review invariants.
  - Reuse existing relationship/export validation where possible.
  - Return structured validation findings with severity and affected record id.
  - Surface findings in Developer Diagnostics and export validation.
  - Do not auto-delete or rewrite corrupted fields in the first implementation.
- Expected complexity: medium.
- Expected risk of change: low/medium if read-only.
- Owner: frontend.
- Tests:
  - Valid data has zero findings.
  - Corrupt JSON yields targeted findings.
  - Validator does not mutate records.
- Acceptance criteria:
  - Engineers can distinguish "no metadata" from "metadata failed to decode."

### P2-03: Make Automation Argument Failures Visible

- Covers: AH-16.
- Summary: Treat invalid automation/screenshot arguments as test-owner-visible failures.
- Why it matters: silent defaults cause false deterministic screenshots/tests.
- Implementation approach:
  - Track when a known argument prefix is present but invalid.
  - In automation runtime, fail fast or record an explicit automation configuration error.
  - Keep production behavior safe: invalid production launch args still default safely unless a product decision says otherwise.
- Expected complexity: small.
- Expected risk of change: low.
- Owner: frontend/platform.
- Tests:
  - Invalid screenshot time zone/calendar/fixed date in automation is visible.
  - Invalid remote HTTP AI base URL still falls back safely outside automation.
- Acceptance criteria:
  - Bad automation configuration cannot silently pass as a valid deterministic run.

### P2-04: Add Backend Metrics or Structured Operational Logs

- Covers: AH-02, AH-03, AH-04, AH-06, AH-07.
- Summary: Preserve admin events, but add a production-grade signal that survives process restarts and can alert.
- Why it matters: in-memory admin events are useful diagnostics, not durable monitoring.
- Implementation approach:
  - Add structured Python logging for security and OpenAI gateway event categories.
  - Include safe fields only: category, status code, error code, model name, latency, request id, endpoint.
  - Avoid token hashes, request text, request JSON, OpenAI body, headers, and cookies.
  - If a metrics stack exists later, add counters for auth rejects, rate limits, OpenAI error classes, and malformed content length.
- Expected complexity: medium.
- Expected risk of change: low.
- Owner: backend/devops.
- Tests:
  - Logging helper redacts blocked fields.
  - Gateway failures emit structured log records in tests.
- Acceptance criteria:
  - Production operators have a durable signal outside the admin SSE page.

## Phase 3: Test and CI Hardening

### P3-01: Lock Down OpenAI Error-Mapping Contracts

- Covers: AH-02, AH-03.
- Summary: Ensure external-service failure mapping stays sanitized and intentional.
- Tests:
  - Timeout maps to `timeout` and 408.
  - `httpx.HTTPError` maps to `network_unavailable`.
  - 429 maps to `rate_limited`.
  - 401/403 maps to `openai_auth_error`.
  - 5xx maps to `openai_server_error`.
  - malformed JSON/missing output maps to `invalid_model_response`.
  - No test response includes raw upstream body or API key.
- Owner: backend.
- Complexity: small.

### P3-02: Add Request Size Fallback Tests

- Covers: AH-04.
- Summary: Prove malformed `Content-Length` does not bypass body limits.
- Tests:
  - Malformed content length with oversized streaming body returns 413.
  - Malformed content length with small valid body passes.
  - Non-body method behavior is unchanged.
- Owner: backend.
- Complexity: small.

### P3-03: Keep Production Strictness Under Test

- Covers: AH-06, AH-07.
- Summary: Treat prod config/docs behavior as regression-sensitive.
- Tests:
  - Missing prod/staging secrets fail settings validation.
  - Localhost DB URL fails in prod/staging.
  - Docs/OpenAPI are 404 in prod/staging and available in dev.
- Owner: backend.
- Complexity: small.

### P3-04: Pending Retry Recovery Tests

- Covers: AH-08.
- Summary: Verify service-token reconnect does not hide failed retry.
- Tests:
  - Retry failure after token setup records diagnostic.
  - Pending messages remain retryable.
  - User feedback distinguishes clean success from partial recovery.
- Owner: frontend.
- Complexity: small/medium.

### P3-05: Extraction and Web Fallback Diagnostics Tests

- Covers: AH-09, AH-10.
- Summary: Keep good local-first behavior while making failures diagnosable.
- Tests:
  - Extraction failure persists user message and attempt state.
  - Web answer failure persists generic assistant response and diagnostic code.
  - No raw user text is included in diagnostic event metadata.
- Owner: frontend.
- Complexity: medium.

### P3-06: Persisted JSON Corruption Tests

- Covers: AH-11.
- Summary: Corrupt local fields must be visible to validators/diagnostics.
- Tests:
  - Corrupt event metadata JSON yields a data-integrity finding.
  - Corrupt review evidence JSON yields a finding.
  - Corrupt normalized extraction envelope yields a finding.
  - UI accessors remain non-crashing if that design is retained.
- Owner: frontend.
- Complexity: medium.

### P3-07: Review Queue Failure-State Tests

- Covers: AH-12.
- Summary: Queue construction failure cannot render as empty queue.
- Tests:
  - Throwing queue service renders explicit failed state.
  - Empty successful queue renders empty state.
  - Successful populated queue renders entries.
- Owner: frontend.
- Complexity: small/medium.

### P3-08: Launch Maintenance Diagnostics Tests

- Covers: AH-13.
- Summary: Maintenance failures are operation-specific.
- Tests:
  - Recovery repair failure recorded as recovery repair.
  - Derived field repair failure recorded as derived field repair.
  - Review refresh failure recorded as review refresh.
  - Generic user message remains generic.
- Owner: frontend.
- Complexity: medium.

### P3-09: Settings Failure Diagnostics Tests

- Covers: AH-14.
- Summary: Settings catches remain user-safe but diagnosable.
- Tests:
  - Keychain read/write/delete failure records sanitized diagnostic.
  - Export failure records sanitized diagnostic.
  - Clear-data failure records sanitized diagnostic.
  - UI does not expose OSStatus/internal path details unless explicitly in developer diagnostics.
- Owner: frontend.
- Complexity: medium.

### P3-10: Runtime Configuration Strictness Tests

- Covers: AH-15, AH-16.
- Summary: Safe defaults remain safe; automation mistakes become visible.
- Tests:
  - HTTPS AI base URL accepted.
  - Loopback HTTP accepted.
  - Remote HTTP rejected/falls back.
  - Invalid automation screenshot args are visible/fail fast.
- Owner: frontend/platform.
- Complexity: small.

### P3-11: Seed Fixture Validation Gate

- Covers: AH-18.
- Summary: Bad QA fixtures should fail CI rather than disappear from debug lists.
- Implementation approach:
  - Add a script or XCTest that loads every `SeedScenario` fixture and validates it.
  - Run it in the iOS CI gate or local verify script.
- Owner: frontend/platform.
- Complexity: small/medium.

### P3-12: Preserve `xcodebuild` False-Negative Handling Tests

- Covers: AH-19.
- Summary: Keep verifier flexibility but avoid masking real failures.
- Tests:
  - Nonzero xcodebuild with clean final XCTest summary and no build errors continues.
  - Nonzero xcodebuild with failed tests exits nonzero.
  - Nonzero xcodebuild with build errors exits nonzero.
- Owner: platform.
- Complexity: small.

### P3-13: Strengthen Secret Scanning Coverage

- Covers: AH-21.
- Summary: Keep lightweight repo scan and add stronger platform coverage.
- Implementation approach:
  - Keep `Scripts/secret_scan.py` in CI for fast feedback.
  - Add explicit reporting of skipped non-UTF8 tracked files, or fail if unexpected text-like files cannot be scanned.
  - Review allowlist entries quarterly or when rules change.
  - Enable GitHub/provider secret scanning and push protection where available.
- Owner: security/devops.
- Complexity: medium.

## Phase 4: Operations and Documentation

### P4-01: Document Allowed Suppression Patterns

- Covers: AH-02, AH-03, AH-04, AH-05, AH-15, AH-17, AH-19, AH-20.
- Summary: Create a repo convention for safe catches, `try?`, broad exceptions, and `|| true`.
- Required rules:
  - Broad catch is allowed at external-service boundaries only when mapped to typed sanitized errors.
  - `try?` is allowed for pure formatting/debug display, not recovery or integrity paths unless a diagnostic is recorded.
  - `|| true` is allowed for cleanup/log capture/environment normalization only.
  - Production quieting must have tests.
  - Fail-fast is preferred for unrecoverable persistence/bootstrap failures.
- Owner: security/platform.
- Complexity: small.

### P4-02: Define Platform Security Controls

- Covers: AH-21.
- Summary: Specify which controls are repo-owned vs platform-owned.
- Platform-owned:
  - Secret scanning and push protection.
  - Dependency vulnerability scanning.
  - Container image scanning.
  - Alerting/log aggregation for backend production.
- Repo-owned:
  - Local regex secret scan.
  - Pinned CI gates.
  - Redaction tests.
- Owner: security/devops.
- Complexity: small/medium.

### P4-03: Document Production Recovery Posture

- Covers: AH-17.
- Summary: Clarify what happens when local persistence cannot boot.
- Implementation approach:
  - Document fail-fast model container behavior.
  - Decide whether a future safe-mode/reset/export recovery UX is needed.
  - Do not implement destructive reset without product approval.
- Owner: product/frontend/security.
- Complexity: small for docs, large if safe-mode UX is chosen.

### P4-04: Document Release Verification Commands

- Covers: AH-22.
- Summary: Make release/smoke expectations explicit.
- Implementation approach:
  - Update deployment or release docs with:
    - `Scripts/verify-all.sh`
    - `Scripts/verify-backend.sh --with-smoke`
    - deployment workflow health checks
    - when production smoke should be run locally
  - Clarify that local smoke is optional for normal feature work but required for release/deploy validation.
- Owner: platform/devops.
- Complexity: small.

## Production Readiness Gates

### Must Pass Before Broader Production Exposure

- P1-01 through P1-05 implemented.
- Backend test suite passes.
- Focused iOS tests for retry/review/maintenance/data-integrity pass.
- `Scripts/secret_scan.py` passes.
- `git diff --check` passes.
- No raw token, request JSON, raw model output, or user text appears in new diagnostics/logs.

### Should Pass Before Public/Scaled Release

- P2-01 local diagnostic event service implemented.
- P2-02 data-integrity validator implemented.
- P2-04 durable backend structured logs or metrics implemented.
- P3-01 through P3-13 either implemented or explicitly accepted with owner/date.
- Release verification docs updated.

### Can Follow After Initial Production Hardening

- Full platform secret scanning and dependency scanning if handled outside repo.
- Safe-mode/reset UX for unrecoverable local persistence boot failures.
- Privacy-reviewed aggregate telemetry for iOS fleet-level error rates.

## Suggested PR Breakdown

### PR 1: Backend Observability Isolation

- Implement P1-01.
- Add backend tests.
- Low risk, high value.

### PR 2: iOS Retry and Review Release Blockers

- Implement P1-02 and P1-04.
- Add focused tests for retry and review failure states.
- Medium risk because UI feedback changes.

### PR 3: iOS Data Integrity and Maintenance Diagnostics

- Implement P1-03 and P1-05.
- Add validator/diagnostic scaffolding needed by P2.
- Medium risk.

### PR 4: Local Diagnostic Event Service

- Implement P2-01 and wire AH-09/AH-10/AH-14.
- Add redaction/privacy tests.
- Medium risk; product/security should review diagnostic fields.

### PR 5: Test/CI Hardening

- Implement P3 test items and seed fixture validation.
- Strengthen secret-scan reporting.
- Low/medium risk.

### PR 6: Ops Documentation and Platform Controls

- Implement P4 docs.
- Capture platform-owned controls and release verification expectations.
- Low risk.

## Definition of Done

The abend-handling hardening effort is complete when:

- Every AH finding is either fixed, covered by tests, or documented as an accepted pattern with rationale.
- No production request path can fail because best-effort logging/diagnostics failed.
- Recovery paths that preserve user data also surface enough diagnostic state to support production incidents.
- Corrupt local persisted JSON is detectable without crashing the app.
- Review/retry surfaces fail visibly instead of appearing empty or successful.
- CI catches regressions in security-sensitive suppressions and production strictness.
- Documentation clearly states which suppressions are allowed and which are prohibited.

## Immediate Next Step

Start with **PR 1: Backend Observability Isolation**. It is the only high-severity finding, has the smallest implementation footprint, and removes the clearest production blocker.
