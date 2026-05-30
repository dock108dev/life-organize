# Architecture

LifeOrganize is a local-first iOS app with a small private backend for AI-backed extraction and web request modes. The iOS app owns the user ledger and can run without backend connectivity. The backend owns provider credentials, device-token enforcement, rate limits, request logging, and admin log surfaces.

## Repository Shape

- `LifeOrganize/`: SwiftUI app target, SwiftData models, app services, runtime configuration, and shared UI code.
- `LifeOrganizeTests/`: unit and integration-style tests for app services, persistence, layout contracts, export contracts, review logic, and guardrails.
- `LifeOrganizeUITests/`: UI, screenshot, Dynamic Type, adaptive shell, and journey tests.
- `Backend/`: FastAPI app, SQLAlchemy models, Alembic migrations, Docker/Caddy deployment files, and backend tests.
- `Scripts/`: local verification, iOS coverage, layout guard, screenshot, simulator, backend smoke, and secret scanning scripts.
- `Tests/ScreenshotBaselines/`: committed visual regression baselines.
- `.github/workflows/`: backend CI/CD, iOS CI, and selected-image backend deploy workflows.

There are no widget, watch, TestFlight, App Store, or iOS deploy targets in this repository.

## iOS App

`LifeOrganizeApp` reads `AppRuntimeConfiguration`, applies screenshot/runtime overrides, resets isolated automation state when requested, creates the model container through `ModelContainerFactory`, loads requested seed scenarios, creates the device token store, and renders `AppRootView`.

`AppRootView` chooses the shell by horizontal size class:

- Compact width uses a `TabView` with Timeline, Things, and Carry Forward tabs. Settings, local search, and Review open from toolbar-driven sheets.
- Regular width uses `NavigationSplitView` with Timeline, Things, Carry Forward, Search, Review, and Settings in the sidebar. Review appears only when at least one review item is ambiently visible.

On launch and scene activation, the app runs local maintenance through `LaunchMaintenanceService`. The underlying repairs include interrupted extraction recovery, derived-field repair, local data integrity checks, diagnostic recording, and review item refresh. Failures are recorded and surfaced instead of silently converting the load to an empty success state.

## User-Facing Surfaces

- Timeline: chat composer plus timeline feed. `ChatSendService` persists raw user messages first, then routes extraction, recall, search, web lookup, or web import behavior based on `ChatIntentClassifier`.
- Things: list/detail views for `Thing` records, local Thing search, previews, history, related reminders, aliases, identity details, and manual add/edit flows.
- Carry Forward: `LedgerRule` reminder continuity grouped into Now, Coming Up, Review, and Paused lanes by `ReminderContinuityPresentationService`.
- Search: local substring search across things, events, reminders, notes, user messages, and timeline slices. Search is not a remote or semantic search service.
- Review: `LedgerReviewItem` queue for local recovery, extraction review, interval candidates, overdue reminders, duplicate Things, conflicting dates, and normalization candidates.
- Settings: AI service token state, local JSON export, local data clearing, and gated developer diagnostics.

## AI and Web Request Flow

The iOS app talks to the backend through `AIServiceClient`:

- `POST /api/v1/extractions` for extraction requests.
- `POST /api/v1/web-requests` for web lookup answer mode or web import extraction mode.

The app sends a per-device service token in the `X-LifeOrganize-Device-Token` header. The backend hashes the token with `DEVICE_TOKEN_SIGNING_SECRET`, requires a matching active `device_clients` row, rate-limits per token and endpoint, then sends provider requests through `OpenAIGateway`.

The backend returns either raw extraction payloads or assistant text for web answer mode. The app parses extraction payloads through `ExtractionService`, applies `TemporalPriorityResolver`, creates SwiftData records, records extraction attempts, and refreshes review items.

## Local-First Behavior

The ledger is stored locally in SwiftData. If the backend is unavailable or no device token is configured, the app keeps the user message locally and marks extraction as pending service setup or retryable depending on the error class. The AI service device token is stored separately in Keychain through `KeychainDeviceTokenStore`; local data clearing does not remove it.

Network, timeout, rate-limit, invalid credential, server, invalid JSON, schema validation, and partial validation failures are mapped to explicit extraction states and error metadata. Retry is blocked for assistant/system messages, already-running extraction, succeeded extraction, messages that do not need extraction, and messages that already created records.

## Developer and Automation Surfaces

Developer diagnostics are gated by `DeveloperModeState` and `DebugAccessPolicy`. Developer mode is available in Debug builds, `INTERNAL_DIAGNOSTICS` builds, or UI testing when `-enable-developer-mode` is present. Automation can force it unavailable with `-disable-developer-mode`, and can unlock it with `-unlock-developer-mode`.

Automation and screenshot modes use isolated `UserDefaults`, deterministic store paths under Application Support unless in-memory storage is requested, deterministic extraction when requested, and optional fixed date/locale/time zone/calendar/appearance overrides.

Legacy double-dash automation aliases and backend device-token auto-enrollment are intentionally unsupported.
