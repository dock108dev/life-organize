BRAINDUMP — PHASE 7

Product Stabilization, Scenario Testing, and Operational QA Infrastructure

Headline Goal

The app is now entering:

real product territory

You are no longer:

* proving the idea
* proving the UI
* proving extraction

You are now solving:

consistency, trust, continuity, and product quality over time.

This phase is about:

* stabilization
* repeatability
* deterministic testing
* visual regression prevention
* extraction quality
* timeline coherence
* relationship integrity

This is the phase where:

prototype energy dies

and:

product discipline begins

⸻

MOST IMPORTANT REALIZATION

This app is NOT:

simple CRUD

It is:

continuity software

Continuity products are uniquely sensitive to:

* subtle regressions
* relationship drift
* extraction weirdness
* chronology issues
* density inconsistencies
* object-link breakage
* visual rhythm decay

That means:

quality infrastructure now matters more than feature velocity.

⸻

CORE PHASE 7 OBJECTIVES

1. Build deterministic scenario testing

2. Build full simulator walkthrough automation

3. Build screenshot regression infrastructure

4. Build seeded app states

5. Build mock AI extraction mode

6. Build internal QA tooling

7. Prevent continuity drift over time

⸻

THE BIGGEST PRODUCT RISK NOW

NOT:

crashes

The biggest risk is:

subtle incoherence

Examples:

* reminders disconnected from Things
* duplicate Things created
* weird chronology ordering
* visual hierarchy decay
* extraction over-normalization
* review queue inconsistency
* timeline density regressions
* “this feels messy now”

This is where products quietly rot.

You need:

deterministic quality systems

⸻

TESTING PHILOSOPHY

The app should increasingly be tested like:

a state engine

NOT:

a normal app

Because:

* relationships matter
* accumulated history matters
* continuity matters
* chronology matters

You need:

persistent-state validation

⸻

REQUIRED TEST MODES

1. Fresh Install Mode

Critical.

Every major scenario test should support:

fresh app install

Meaning:

* no DB
* no reminders
* no Things
* no extraction cache
* no review queue
* no stale local state

⸻

Launch flag

--reset-db

This becomes:

baseline deterministic startup

⸻

2. Seeded Scenario Mode

The app should launch directly into:

* predefined histories
* reminder states
* Things
* extraction conditions

Examples:

--seed-scenario=car_maintenance
--seed-scenario=dog_continuity
--seed-scenario=heavy_timeline

This becomes:

the backbone of visual/product QA

⸻

3. Mock Extraction Mode

THIS IS EXTREMELY IMPORTANT.

DO NOT:

* rely on live OpenAI during testing
* rely on variable extraction outputs
* rely on changing model behavior

Instead:

message → deterministic fixture payload

⸻

MOCK EXTRACTION FLOW

User Input

Replace air filter in 2 months

Test Fixture

{
  "type": "reminder",
  "thing": "Home Air Filters",
  "window": "2 months"
}

Now:

* screenshots remain stable
* timeline remains deterministic
* UI regression testing works

This is critical.

⸻

FIXTURE LIBRARY

Build:

Tests/Fixtures/

Examples:

car_maintenance.json
ambiguous_dog_grooming.json
work_continuity.json
heavy_history.json
timeline_search.json

⸻

SCENARIO TEST SUITE

You now need:

product scenarios

NOT just:

unit tests

⸻

REQUIRED SCENARIOS

Scenario 1 — First Launch

Fresh install.

Verify:

* first screen feel
* timeline empty state
* entry flow
* onboarding copy
* no dead visual space

⸻

Scenario 2 — Operational Home

Logs:

* air filters
* oil changes
* Costco purchases
* garage cleaning
* recurring maintenance

Verify:

* continuity accumulation
* Thing grouping
* reminder inference

⸻

Scenario 3 — Ambiguous Human Entry

Input:

I think bogey needs a haircut in a week or two

Verify:

* review state
* review queue
* suggested interpretation
* relationship linking

⸻

Scenario 4 — Work Continuity

Logs:

* AWS
* Sonar
* Vulns
* monorepo
* migrations

Verify:

* relationship graph
* continuity grouping
* timeline coherence

⸻

Scenario 5 — Heavy History

Seed:

* 500+ entries
* multi-month timeline
* reminders
* notes
* reviews
* searches

Verify:

* performance
* chronology
* density
* scrolling
* visual continuity

⸻

VISUAL REGRESSION INFRASTRUCTURE

This is now mandatory.

Because:

visual quality is becoming the product

⸻

AUTOMATED SCREENSHOT SYSTEM

Use:

* XCUITest
* Fastlane Snapshot
* simulator launch scripts

Capture:

* Timeline
* Things
* Thing detail
* Carry Forward
* Search
* Review queue
* Empty states
* Heavy states
* First launch

EVERY RUN.

⸻

WHY THIS MATTERS

You are now at the stage where:

* 2px spacing changes matter
* hierarchy drift matters
* density drift matters
* typography inconsistencies matter

You need:

visual continuity enforcement

⸻

SCREENSHOT MODE

Build:

screenshot mode

When enabled:

* fixed time
* fixed battery
* fixed notifications
* fixed dates
* deterministic timeline

This makes:

* App Store screenshots
* regression testing
* design review

massively easier.

⸻

INTERNAL QA MODE

Build hidden:

QA mode

Enables:

* mock extraction
* fixture loading
* reset DB
* timeline jumping
* fake dates
* extraction debug
* relationship graph inspection
* reprocess entry

This becomes:

developer continuity tooling

You will use this constantly.

⸻

EXTRACTION QUALITY DASHBOARD

INTERNAL ONLY.

Track:

* deterministic vs AI
* review rate
* extraction confidence
* duplicate Thing creation
* failed temporal interpretation

You need:

quality telemetry

NOT:

user analytics dashboards

⸻

TEMPORAL QA

One of the highest-risk systems now.

Need dedicated tests for:

* “in 90 days”
* “next year”
* “later this month”
* “revisit next season”
* “replace in 2 months”

Because temporal ambiguity is currently:

the biggest coherence threat

⸻

SEARCH QA

Search is becoming:

the power feature

Need tests for:

* fragments
* aliases
* date slices
* fuzzy matches
* Things
* reminders
* notes
* timeline recall

⸻

RELATIONSHIP INTEGRITY TESTING

Critical.

Every seeded scenario should verify:

* Thing links
* reminder links
* event links
* review references
* timeline continuity

Because:

broken relationships silently destroy trust

⸻

MOST IMPORTANT PRODUCT INSIGHT

The app’s moat is becoming:

coherent continuity over time

NOT:

* AI
* reminders
* notes
* tasks

Continuity quality.

That is the real product now.

⸻

MOST IMPORTANT QA QUESTION

NOT:

did the parser succeed?

Instead:

does this still feel coherent and trustworthy after months of accumulation?

That is the real product quality bar.

⸻

PHASE 7 ACCEPTANCE CRITERIA

Infrastructure

* deterministic launch states
* seeded scenarios
* mock extraction system
* screenshot automation

⸻

QA

* repeatable simulator runs
* visual regression coverage
* relationship integrity testing

⸻

Product

* continuity remains coherent over large histories
* extraction edge cases manageable
* review system remains trustworthy

⸻

UX

* visual consistency maintained
* density stable
* chronology stable
* timeline quality preserved

⸻

Product Feel

The app begins behaving like:

a stable continuity operating layer

instead of:

an evolving prototype held together by AI parsing