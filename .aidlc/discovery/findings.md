# Findings

## Runtime Launch Modes And Fresh Install Reset

`LifeOrganize/Utilities/AppRuntimeConfiguration.swift` is the central runtime flag parser. It supports `-ui-testing`, `-use-fake-extractor`, `-reset-store`, `-reset-api-key`, `-enable-developer-mode`, and `-fixed-now=...`. The BRAINDUMP's requested `--reset-db` flag is not present; the current equivalent is `-reset-store`, and it only resets the UI-testing store path when `-ui-testing` is also set.

`LifeOrganize/LifeOrganizeApp.swift` reads `AppRuntimeConfiguration.current`, resets the API key when `-reset-api-key` is present, and creates the SwiftData container through `ModelContainerFactory`.

`LifeOrganize/Persistence/ModelContainerFactory.swift` supports `.standard`, `.inMemory`, and `.store(url:)`. The UI testing mode uses a deterministic SQLite file under Application Support via `AppRuntimeConfiguration.uiTestingStoreURL()`.

`LifeOrganize/Services/LocalDataClearService.swift` clears ledger data from the active `ModelContext`: entity links, review items, extraction attempts, events, reminders, notes, things, and chat messages. It does not clear API keys; tests assert the key is preserved in `LifeOrganizeTests/ContinuityScenarioRegressionTests.swift`.

Missing/stubbed: no `--reset-db` alias, no production-app reset flag outside UI testing, no launch-time clearing of reminders/review queue/extraction cache except through the UI-testing store deletion, and no explicit reset of app `UserDefaults`/developer-mode state.

## Seeded Scenario Mode

There is no `--seed-scenario=...` launch argument in `LifeOrganize/Utilities/AppRuntimeConfiguration.swift`.

There is no `Tests/Fixtures/` or JSON scenario fixture directory on disk. `LifeOrganize/Services/DeterministicExtractionFixtures.swift` contains Swift helper functions that produce canonical extraction JSON strings, but it is compiled as app code rather than being a separate fixture library.

Current seeded scenario coverage is programmatic inside tests. `LifeOrganizeTests/ContinuityScenarioRegressionTests.swift` manually constructs home filters, dog food, car maintenance, work-security normalization, local recovery, export, and clear-data scenarios using in-memory SwiftData. `LifeOrganizeTests/TestDoubles.swift` provides `makeInMemoryModelContext()`, `TestDateProvider`, and static/throwing extraction clients.

Missing/stubbed: no named scenario registry, no scenario loader, no app launch path that seeds SwiftData before first screen render, no heavy-history fixture generator, and no mapping for `car_maintenance`, `dog_continuity`, `heavy_timeline`, or similar names.

## Mock Extraction Mode

`LifeOrganize/Utilities/AppRuntimeConfiguration.swift` wires `-use-fake-extractor` to `DeterministicMessageExtractionClient`; otherwise it uses `OpenAIMessageExtractionClient`.

`LifeOrganize/Services/DeterministicExtractionClient.swift` implements deterministic extraction with hard-coded substring branches. It covers oil changes, furnace/HVAC filters, air filters, dog food, printer paper, garage cleaning, dentist records, smoke detector batteries, dryer vent cleaning, passport renewal, reminders, notes, invalid JSON, partial validation, recall, and some work/project examples. It returns `requestJSON` as `{"mode":"deterministic"}` and model name `deterministic-extractor`.

`LifeOrganizeTests/DeterministicExtractionClientTests.swift` validates many deterministic inputs, temporal priority fixtures, invalid JSON, partial success, reminders, notes, and recall.

Missing/stubbed: deterministic inputs are code branches, not fixture-file mappings from `message -> payload`; no external JSON fixture library exists; no app-visible toggle exists for mock extraction beyond launch args; the BRAINDUMP example `"Replace air filter in 2 months"` exists but resolves to `"Air Filters"` rather than `"Home Air Filters"`.

## OpenAI Extraction And Parsing

`LifeOrganize/Services/ExtractionService.swift` defines `MessageExtractionClient`, `OpenAIMessageExtractionClient`, strict prompt instructions, schema request construction, JSON isolation, parsing, and normalization. It uses `ExtractionContract.modelName`, strict JSON schema from `LifeOrganize/DTOs/OpenAIExtractionSchema.swift`, and current date/time from the runtime date provider.

`LifeOrganize/Services/ChatSendService.swift` persists the raw user message first, creates an `ExtractionAttempt`, invokes the extractor, applies `TemporalPriorityResolver`, creates Things/events/reminders/notes, writes entity links, and records assistant confirmations or review/failure messages.

`LifeOrganize/Models/ExtractionAttempt.swift` stores request JSON, raw response, normalized JSON, model name, prompt/schema versions, status, errors, timestamps, and created entity IDs. `LifeOrganize/Models/ChatMessage.swift` stores extraction status/error metadata and retry timestamps.

Missing/stubbed: no dedicated extraction quality dashboard; no aggregate counters for deterministic-vs-AI, review rate, duplicate creation, or temporal failure rate beyond per-record fields and debug lists.

## Temporal QA

`LifeOrganize/Services/TemporalPriorityResolver.swift` applies deterministic post-processing when source text contains review/reminder language plus relative durations. It prioritizes actionable durations like `in 90 days` over long-term context like `next year`, can split standing restrictions from review reminders, and records `TemporalResolutionDecision` entries in the normalized envelope.

`LifeOrganizeTests/TemporalPriorityResolutionTests.swift` covers reevaluation in 90 days, standing restriction plus future review, pending retry, and manual retry paths. `LifeOrganizeTests/DeterministicExtractionClientTests.swift` covers `in 2 months`, `tomorrow`, `yesterday`, appointment dates, and mixed event/reminder cases.

Missing/stubbed: no dedicated scenario matrix for all BRAINDUMP temporal examples (`next year`, `later this month`, `revisit next season`, etc.); current duration parsing in `TemporalPriorityResolver` is numeric `in/after N day/week/month/year`, so vague phrases require model output or other logic.

## Thing Identity, Duplicate Prevention, And Normalization

`LifeOrganize/Utilities/ThingNormalizer.swift` normalizes Thing keys, applies seeds for Oil Change, Home Air Filters, Engine Air Filter, Cabin Air Filter, and Domains, blocks ambiguous contexts, and exposes candidate matching.

`LifeOrganize/Services/ThingResolver.swift` uses `ThingNormalizer.candidates` and existing Things to reuse or create Things. Automatic merges occur only when candidates allow it; ambiguous non-automatic matches generate `LedgerReviewItem` normalization candidates.

`LifeOrganize/Services/LedgerReviewItemGenerationService.swift` also generates duplicate Thing and normalization review items from current Things.

`LifeOrganizeTests/ThingIdentityContinuityTests.swift`, `LifeOrganizeTests/ThingResolutionTests.swift`, `LifeOrganizeTests/ThingNormalizationCandidateTests.swift`, and `LifeOrganizeTests/ContinuityScenarioRegressionTests.swift` cover identity continuity and review-based correction.

Missing/stubbed: no global relationship-integrity validation pass that checks all seeded scenarios for duplicate creation or broken links; duplicate detection is review-driven, not a deterministic scenario assertion framework.

## Relationship Integrity

`LifeOrganize/Models/EntityLink.swift` persists typed links between chat messages, events, notes, rules, and things. Relations include `about_thing`, `extracted_from`, `mentions_thing`, `primary_thing`, and `same_message`.

`LifeOrganize/Services/EntityLinkWriter.swift` writes extraction-created links from messages to extracted records and Things, primary links from records to Things, note-about-Thing links, and same-message sibling links.

`LifeOrganize/Services/DerivedFieldMaintenanceService.swift` synchronizes Thing links when events, rules, and notes are inserted, updated, reassigned, merged, or deleted. It can retarget links during Thing merges and delete links when records are deleted.

`LifeOrganize/Services/RelationshipTraversalService.swift` derives related records from direct links, shared source messages, shared Things, and optional text overlap. `LifeOrganizeTests/RelationshipTraversalServiceTests.swift` validates traversal ordering, missing-target filtering, shared source/Thing behavior, and work-security context.

Missing/stubbed: no whole-store validator that asserts every event/rule/note/review reference points to an existing object; no seeded scenario relationship audit runner.

## Review Queue And Continuity QA

`LifeOrganize/Models/LedgerReviewItem.swift` stores review items with dedupe keys, kind, state, target, confidence, and evidence JSON.

`LifeOrganize/Services/LedgerReviewItemGenerationService.swift` generates review items for interval reminder candidates, overdue reminders, local recovery, extraction review, duplicate Things, conflicting dates, and normalization candidates.

`LifeOrganize/Services/LedgerReviewQueueService.swift` exposes actions: retry entry, dismiss, mark reviewed, save as note, merge duplicate Things, reassign records, and adjust reminder timing. It blocks retry when the target or API key state makes the action unavailable.

`LifeOrganize/Features/Shared/LedgerReviewQueueView.swift` renders the review list and detail navigation. `LifeOrganize/AppRootView.swift` shows a toolbar "Review Items" button when ambiently visible review items exist.

Missing/stubbed: no deterministic scenario runner verifies review queue consistency across first launch, ambiguous entry, heavy history, and relaunch; no review queue screenshot mode; no quality dashboard on review rates or correction classes.

## Timeline, Chronology, And Density

`LifeOrganize/Features/Chat/LedgerFeed.swift` builds primary timeline feed sections from messages requiring attention, events, reminders within a 45-day horizon, and notes. It sorts newest-first by timeline date, creation date, kind rank, and ID, and groups sections by day.

`LifeOrganize/Features/Chat/ChatView.swift` renders the timeline with fixed layout constants in `LedgerFeedTimelineLayout`, empty state, suggestion bar, and composer. It auto-scrolls to the top/new message.

`LifeOrganize/Services/TimelineSliceProjection.swift` projects messages, things, events, reminders, notes, and entity links into replayable timeline rows with date filtering, linked-Thing filtering, relationship context, and stable sorting.

`LifeOrganizeTests/LedgerDensityContractTests.swift`, `LifeOrganizeTests/LedgerTimelineChromeTests.swift`, `LifeOrganizeTests/LedgerFeedProjectionTests.swift`, and `LifeOrganizeTests/TimelineSliceProjectionTests.swift` lock several layout constants, row density assignments, divider alignment, projection sorting, and line counts.

Missing/stubbed: no screenshot regression suite for timeline visual rhythm; no heavy-history scroll/performance scenario; no automated pixel/image comparison.

## Search QA

`LifeOrganize/Services/SearchService.swift` builds local substring search records for Things, events, reminders, notes, chat messages, and timeline slices. Search fields include names, aliases, categories, titles, event types, raw text, notes, metadata, reminder behavior/status/dates, linked Thing names, and chat text.

`LifeOrganize/Services/SearchService+Ranking.swift` scores field weights, exact match, match breadth, structured-record boost, date range boost, linked Thing boost, and temporal boost. Results sort by score, date, source kind, title, and stable ID.

`LifeOrganize/Services/LocalSearchTimingParser.swift` parses date phrases like today, yesterday, this/last week, this/last month, this/last year, upcoming, since/from month, month year, and year.

`LifeOrganizeTests/TimelineAwareSearchTests.swift`, `LifeOrganizeTests/SearchRecallServiceTests.swift`, `LifeOrganizeTests/SearchLandingExperienceTests.swift`, and `LifeOrganizeTests/LocalFirstSearchVisibilityTests.swift` cover date-range search, timeline replay destinations, metadata, inactive reminder inclusion, search landing, and local visibility.

Missing/stubbed: no explicit fuzzy search engine; search is substring-based. No dedicated tests for aliases plus fragments plus reminders plus notes plus timeline recall as one scenario matrix.

## Screenshot And Simulator Automation

`LifeOrganizeUITests/LifeOrganizeUITests.swift` is the only UI automation suite. It launches with `-ui-testing`, `-ApplePersistenceIgnoreState YES`, `-use-fake-extractor`, and `-fixed-now=2027-01-15T08:00:00-05:00`; it optionally appends `-reset-store` and `-reset-api-key`. Tests cover tabs, fake extraction, persistence across relaunch, first-run empty states, Settings/API key, root search, rendered flows, and review queue access.

`LifeOrganize.xcodeproj/xcshareddata/xcschemes/LifeOrganize.xcscheme` includes the app target, `LifeOrganizeTests`, and `LifeOrganizeUITests` in the shared scheme.

Missing/stubbed: no Fastlane directory, no snapshot configuration, no screenshot artifact directory, no simulator launch scripts, no visual diff/baseline infrastructure, and no automated capture set for Timeline, Things, Thing detail, Carry Forward, Search, Review queue, empty states, heavy states, or first launch.

## Screenshot Mode Determinism

`LifeOrganize/Utilities/AppRuntimeConfiguration.swift` supports fixed logical time through `-fixed-now=...`, and services consume it through `DateProvider`. `LifeOrganizeUITests/LifeOrganizeUITests.swift` uses a fixed date for UI tests.

Missing/stubbed: no explicit `screenshot mode` flag; no code fixes battery, status bar, notifications, locale, text size, appearance, animation behavior, network state, or deterministic seeded timeline for screenshots.

## Internal QA / Developer Diagnostics

`LifeOrganize/Utilities/DeveloperModeState.swift` defines `DebugAccessPolicy`; developer mode is available in Debug, `INTERNAL_DIAGNOSTICS`, or UI testing with `-enable-developer-mode`, and it persists unlocked state in `UserDefaults`.

`LifeOrganize/Features/Settings/SettingsView.swift` unlocks developer mode by long-pressing the version footer and exposes "Developer Diagnostics" only when unlocked. The current diagnostics section links to all extraction attempts and failed extractions.

`LifeOrganize/Features/Debug/ExtractionDebugListView.swift`, `ExtractionAttemptDebugView.swift`, `ChatMessageExtractionDebugView.swift`, and retry/debug components show extraction attempt lists, filters, raw/normalized payloads, failure details, and retry affordances.

Missing/stubbed: no hidden QA panel for fixture loading, seed scenario selection, reset DB, timeline jumping, fake dates, relationship graph inspection, or reprocess-entry controls beyond existing extraction debug/retry surfaces and Settings clear-data flow.

## Extraction Quality Dashboard / Telemetry

Per-record quality signals exist in `ChatMessage`, `ExtractionAttempt`, `LedgerReviewItem`, `EntityLink`, and normalized extraction JSON. Debug screens expose attempt-level data.

`LifeOrganize/Services/LedgerReviewItemGenerationService.swift` generates local recovery, extraction review, duplicate, conflicting date, interval, and normalization items that could feed quality metrics.

Missing/stubbed: no aggregate dashboard, no internal metrics model, no counters for deterministic vs AI extraction, review rate, confidence trends, duplicate Thing creation, failed temporal interpretation, or review queue consistency.

## Persistence, Export, And State Snapshots

SwiftData models are in `LifeOrganize/Models/*.swift`; schema and migrations are in `LifeOrganize/Persistence/LifeOrganizeSchemaV2.swift`, `LifeOrganize/Persistence/LifeOrganizeSchemaV3.swift`, `LifeOrganize/Persistence/LifeOrganizeSchemas.swift`, and `LifeOrganize/Persistence/LifeOrganizeMigrationPlan.swift`.

`LifeOrganize/Services/LocalJSONExportService.swift` exports chat messages, extraction runs, Things, events, reminders, notes, review items, and entity links to JSON. `LifeOrganize/Services/LocalJSONExportValidation.swift` validates export content. Settings surfaces export-before-clear through `LifeOrganize/Features/Settings/SettingsClearDataFlow.swift` and `SettingsView.swift`.

Missing/stubbed: export is user/share-sheet oriented, not a scenario snapshot format; there is no import/seed-from-export path and no baseline state comparison runner.

## Product Surface Coverage

Primary app surfaces are wired in `LifeOrganize/AppRootView.swift`: Timeline, Things, Carry Forward, Settings, Search, and Review queue.

Empty-state copy is centralized through `LedgerEmptyStateContent` in `LifeOrganize/Features/Shared/LedgerEmptyStateView.swift` and tested in `LifeOrganizeTests/FirstRunEmptyStateTests.swift`.

Things and detail continuity are surfaced through `LifeOrganize/Features/Things/ThingsListView.swift`, `ThingPreviewSnapshot.swift`, and `ThingDetailSnapshot.swift`, with tests in `ThingPreviewSnapshotTests.swift` and `ThingDetailSnapshotTests.swift`.

Carry Forward/reminders use `LifeOrganize/Features/Rules/RulesListView.swift`, `RuleDetailView.swift`, `ReminderContinuityPresentation.swift`, `ReminderDetailSummary.swift`, and related tests.

Missing/stubbed: no full simulator walkthrough that traverses all product surfaces under named seeded states; no visual QA automation for each surface.
