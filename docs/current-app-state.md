# Current App State

This document summarizes behavior present in the current codebase.

## App Surface

`LifeOrganizeApp` reads `AppRuntimeConfiguration`, creates the AI service credential store, creates the SwiftData model container through `ModelContainerFactory`, loads requested seed scenarios, and renders `AppRootView`. `AppRootView` owns the Timeline, Things, and Carry Forward tabs, injects `AppSessionState` and `DeveloperModeState`, and opens Settings, ledger search, and the review queue from toolbar buttons.

On launch and whenever the scene becomes active, the root view runs `ExtractionRecoveryMaintenanceService.repairInterruptedEntries()`, `DerivedFieldMaintenanceService.repairAll()`, and `LedgerReviewItemGenerationService.refresh()`. If this maintenance fails, the app shows an alert that cached ledger fields could not be refreshed.

The Timeline tab contains the chat composer and timeline feed. `LedgerFeedProjection` builds feed rows from events, reminders, notes, and user messages that still need primary attention because extraction is pending, retrying, waiting for service setup, failed, partially succeeded, or needs review. Rows are grouped by timeline day. Current-day sections render as Today, prior sections render as Yesterday, weekday, month/day, or month/day/year labels, and future-dated sections are marked with an Upcoming subtitle. Logging intents run through `ChatSendService`; recall and search-style questions are answered locally by `ChatRecallResponseService`, `RecallService`, `RuleLookupService`, and `SearchService`. Web lookup and web import intents also route through `ChatSendService` when the classifier recognizes schedule-style requests.

The review queue is backed by `LedgerReviewItem`. `LedgerReviewItemGenerationService` creates review items for interval reminder candidates, overdue reminders, local extraction recovery, extraction review, duplicate Things, conflicting dates, and normalization candidates. `LedgerReviewQueueService` exposes quick review, duplicate-Thing merge, record reassignment, and reminder timing adjustment actions, with action blocking when the target or required AI service credential is missing.

The Things tab lists `Thing` records, sorts them by latest event and update time, supports local Thing search, and opens detail screens. Thing rows use `ThingPreviewSnapshot` to show latest event details, reminder state, upcoming reminder dates, metadata highlights, note snippets, aliases, record counts, and review-item pills when those values exist. Thing detail uses `ThingDetailSnapshot` for operational status, reminder summaries, recent activity, event chronology, notes, identity details, timeline entry points, and manual add/edit flows for events, reminders, notes, and the thing itself. Source metadata and extraction identifiers are shown only when developer diagnostics are unlocked.

The Carry Forward tab lists `LedgerRule` records in Now, Coming Up, Review, and Paused lanes from `ReminderContinuityPresentationService`. Reminder detail supports edit, reschedule, end-date, dismiss, and delete actions according to `ReminderDetailActionPolicy`. Reminder status is derived by `RuleStatusService` while the persisted model remains `LedgerRule`.

Settings contains AI service token status, local JSON export, and local data clearing. Extraction attempt lists for all attempts and failed attempts are developer diagnostics: they appear only when `DebugAccessPolicy.allowsExtractionDebugScreens` is true. Developer mode is available in Debug builds, `INTERNAL_DIAGNOSTICS` builds, or UI testing when `-enable-developer-mode` is passed; it is unlocked from the Settings version footer long press and can be locked again in Settings.

## Persistence

SwiftData models in scope are `ChatMessage`, `ExtractionAttempt`, `EntityLink`, `Thing`, `LedgerEvent`, `LedgerRule`, `LedgerNote`, and `LedgerReviewItem`. `LifeOrganizeSchemaV3.models` builds the active SwiftData schema. `LifeOrganizeMigrationPlan` defines lightweight migrations from schema V1 to V2 and V2 to V3.

`ChatMessage` stores original text, role, creation time, extraction status, optional raw LLM response, optional extraction error metadata, extraction version, retry counters and timestamps, and relationships to extracted events, reminders, notes, and extraction attempts.

`LedgerEvent` stores event type and metadata entries. Event type values include generic, maintenance, purchase, visit, replacement, cleaning, renewal, appointment, project, note, reminder, measurement, status change, and other. Metadata entries can store string, number, date, and boolean values with optional unit and source text.

`LedgerRule` is the persisted model behind reminders. It stores rule type, inferred continuity behavior, start date, optional expiration date, active state, lifecycle state, manual deactivation timestamp, linked thing, source message, and source extraction run.

`Thing` stores name, normalized key, details, aliases, optional category, source message and extraction attempt IDs, event count, last event date, and relationships to events, reminders, and notes.

`LedgerReviewItem` stores generated review decisions with a dedupe key, kind, state, title, detail, optional action title, target type and ID, confidence, evidence JSON, timestamps, snooze/expiration fields, and optional failure reason.

`ExtractionAttempt` stores request JSON, raw response text, normalized JSON text, model name, prompt version, schema version, status, error metadata, timestamps, created entity IDs, and source message.

`LocalDataClearService` deletes entity links, review items, extraction attempts, events, reminders, notes, things, and chat messages, then saves the model context. The AI service device token is stored separately through `KeychainDeviceTokenStore` and is not cleared by that service.

`LocalJSONExportService` exports chat messages, extraction runs, things, events, reminders, notes, ledger review items, and entity links to a JSON file in the temporary directory before presenting it through the share sheet. The export envelope uses schema version `3` and includes source metadata, extraction state, event metadata, reminder continuity fields, review-item fields, and entity links.

## AI Service Integration

`V1ScopeContract` permits AI-service use for extraction, normalization, date parsing, recall formatting, web lookup, and web import. The iOS app sends extraction and web requests to the LifeOrganize backend through `AIServiceClient`, defaulting to `https://life.dock108.dev` and accepting `-ai-service-base-url=...` for local development. The backend owns the provider credential, builds provider requests, and stores only device/rate-limit/request metadata in Postgres.

Device tokens are saved in the iOS Keychain under the app bundle identifier service and `lifeorganize_device_token` account. If no token is available or the backend rejects it, `ChatSendService` records the message locally and marks extraction as pending service setup.

Extraction parsing normalizes the model response through `ExtractionService`. `ChatSendService` then applies `TemporalPriorityResolver`, which prioritizes explicit review or reminder language plus actionable relative durations before long-term contextual references such as next year. Matching cases create or update reminder rules with the actionable date and record temporal resolution decisions in the normalized extraction envelope.

Network, timeout, rate-limit, invalid-credential, server, invalid-JSON, schema-validation, and partial-validation failures are mapped to extraction status and error metadata on chat messages and extraction attempts. Network, timeout, rate-limit, server, and unknown extraction errors are marked for retry with `nextExtractionRetryAt`; invalid or missing credentials are marked as pending service setup.

Preparing the AI service token marks pending-service messages retryable through `PendingExtractionRetryService` and starts retrying recent pending messages. Manual retry is exposed through review queue recovery actions and developer extraction debug views. Retry is blocked for assistant or system messages, already-running extraction, already-succeeded extraction, messages that do not need extraction, and messages that already created records.

## Search And Recall

Search is local substring matching. `SearchService.activeMode` is `localSubstring`, and search records are built from things, events, reminders, notes, user chat messages, and timeline slices. The root search toolbar opens `UnifiedSearchView`, and the Things tab has a local Thing search field. Search fields include thing names, aliases, categories, event titles, event types, event metadata, reminder type, reminder behavior, reminder lane, reminder status text, reminder dates, note bodies, linked thing names, timeline text, and chat text. Results are scored by field weight, exact-match and breadth boosts, structured-record boost, date-range boost, linked-thing boost, temporal boost, then sorted by date, source kind, title, and stable ID.

Recall support is local. `ChatIntentClassifier` routes last-time questions, reminder lookups, today-agenda lookups, prior-note lookups, explicit local search requests, web lookup or import requests, unsupported questions, and create-event/create-rule/create-note messages.

## Runtime And Tests

`AppRuntimeConfiguration` supports UI-test, screenshot, and diagnostic launch arguments: `-ui-testing`, `-screenshot-mode`, `-use-fake-extractor`, `-reset-store`, `--reset-db`, `-reset-device-token`, `-skip-launch-maintenance`, `--skip-launch-maintenance`, `-use-in-memory-store`, `--use-in-memory-store`, `-enable-developer-mode`, `-fixed-now=...`, `-ai-service-base-url=...`, `--ai-service-base-url=...`, `-seed-scenario=<id>`, `--seed-scenario=<id>`, `-initial-tab=...`, `--initial-tab=...`, `-screenshot-seed=...`, `-screenshot-start=...`, `-screenshot-search-query=...`, `-screenshot-locale=...`, `-screenshot-time-zone=...`, `-screenshot-calendar=...`, `-screenshot-appearance=...`, and `-disable-animations`. `--reset-db` is the fresh-install reset alias for deterministic automation launches. Automation uses `InMemoryDeviceTokenStore`, isolated UserDefaults, and a deterministic store path under Application Support unless in-memory storage is requested. `-use-fake-extractor` selects `DeterministicMessageExtractionClient`, and deterministic screenshot mode also disables animations. UI test support reads `LIFE_ORGANIZE_SCENARIO_ARTIFACTS_DIR` to pass a scenario-artifacts launch argument and `LIFE_ORGANIZE_SCENARIO_SCREENSHOTS_DIR` to copy attached screenshots to a caller-provided directory.

The shared Xcode scheme is `LifeOrganize`. It includes the app target, `LifeOrganizeTests`, and `LifeOrganizeUITests`. The project has Debug and Release configurations and an iOS deployment target of `17.0`. `Scripts/screenshots/run-screenshot-tests.sh` runs `LifeOrganizeUITests/LifeOrganizeScreenshotTests`, extracts `screenshot__*` PNG attachments, and compares or updates baselines. `fastlane/Fastfile` exposes only `screenshots` and `update_screenshots` lanes that call that script.

## Deployment Boundary

This repository contains an Xcode project, app/test targets, a small FastAPI backend under `Backend/`, `.swiftlint.yml`, `.gitignore`, screenshot comparison scripts, screenshot baselines, and Fastlane lanes for screenshot comparison or baseline updates. It does not contain visible GitHub Actions workflows, cloud sync, analytics configuration, notification configuration, widgets, watch targets, or App Store release automation. The backend uses Docker, Alembic, Postgres, and a Caddy example for `life.dock108.dev`; the app entitlement file configures the Keychain access group.
