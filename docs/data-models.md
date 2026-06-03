# Data Models

This document covers persistent data owned by the app and backend. It intentionally describes current model ownership and relationships, not historical migrations in detail.

## iOS SwiftData

The active app schema is `LifeOrganizeSchemaV3`. It includes:

- `ChatMessage`
- `ExtractionAttempt`
- `EntityLink`
- `Thing`
- `LedgerEvent`
- `LedgerRule`
- `LedgerNote`
- `LedgerReviewItem`

`LifeOrganizeMigrationPlan` defines lightweight migrations from schema V1 to V2 and V2 to V3.

## Primary Records

`ChatMessage` stores original conversation text, role, creation time, raw model response when present, extraction status, optional extraction error metadata, extraction schema version, retry counters/timestamps, and relationships to extracted events, reminders, notes, and extraction attempts.

`ExtractionAttempt` stores request JSON, raw response text, normalized JSON text, model name, prompt version, schema version, status, error metadata, timestamps, created record IDs, and its source message.

`Thing` stores canonical object/person/place/project identity: name, normalized key, details, aliases, optional category, source message and extraction attempt IDs, event count, last event date, and relationships to events, reminders, and notes.

`LedgerEvent` stores factual timeline events with title, occurrence date, raw text, optional note, event type, structured metadata entries, linked Thing, source message, and source extraction run ID.

`LedgerRule` is the persisted model behind Carry Forward reminders. It stores title, reason/raw text, start and optional expiration dates, active state, lifecycle state, manual deactivation timestamp, rule type, continuity behavior, linked Thing, source message, and source extraction run ID.

`LedgerNote` stores note text, timestamps, source identifiers, source message, and linked Things.

`LedgerReviewItem` stores generated review decisions with a dedupe key, kind, state, title/detail/action text, target type and ID, confidence, evidence JSON, timestamps, snooze/expiration fields, and optional failure reason.

`EntityLink` stores typed relationships between records, including source/target type and ID, relation, confidence, creator, creation time, and optional source message ID.

## Important Status Enums

Chat extraction statuses are `not_required`, `pending`, `pending_token`, `pending_retry`, `extracting`, `succeeded`, `partially_succeeded`, `failed`, `failed_needs_review`, and `needs_review`.

Extraction attempts are `pending`, `succeeded`, `failed`, `partially_succeeded`, and `superseded`.

Review item states include candidate, ready, presented, accepted, dismissed, snoozed, superseded, expired, and failed.

Review item kinds include interval reminder, overdue reminder review, local recovery, extraction review, duplicate Thing, conflicting date, and normalization candidate.

Ledger event types include generic, maintenance, purchase, visit, replacement, cleaning, renewal, appointment, project, note, reminder, measurement, status change, and other.

Reminder rule types include restriction, reminder, preference, deadline, waiting period, and other. Reminder continuity behavior is persisted as ongoing, date-based reminder, time-limited window, or recurring text.

Thing categories include admin, finance, food, health, home, home maintenance, maintenance, person, pet, place, project, purchase, rule topic, subscription, travel, vehicle, work, and other.

## Export Format

`LocalJSONExportService` exports schema version `3`. Exports include chat messages, extraction runs, things, events, reminders, notes, review items, and entity links.

Chat message extraction provenance uses:

- `extractionRunIds`
- `latestExtractionRunId`
- `successfulExtractionRunIds`

The old singular chat-message `extractionRunId` compatibility field is not part of current exports.

`LocalJSONExportValidation`, scenario fixture validators, and export comparison tests enforce reference integrity between exported records and extraction run IDs.

## Data Clearing

`LocalDataClearService` deletes local ledger data from SwiftData: entity links, review items, extraction attempts, events, reminders, notes, things, and chat messages. It then saves the model context.

The app-managed device token is not stored in SwiftData and is not cleared by `LocalDataClearService`.

## Backend Database

The backend database is Postgres and is managed by Alembic. Current backend tables are:

- `device_clients`: token hash, first/last seen timestamps, request count, status, and revoked timestamp.
- `ai_request_logs`: token hash, endpoint, status code, latency, model name, provider request ID, error code, creation time, and notes.

Device tokens are never stored raw by the backend. The backend stores only HMAC hashes derived from the provided token and `DEVICE_TOKEN_SIGNING_SECRET`.
