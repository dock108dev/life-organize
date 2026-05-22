# Product Stabilization Notes

LifeOrganize is continuity software, not a simple CRUD app. The durable product risks are subtle relationship drift, chronology errors, visual density regressions, duplicate Things, disconnected reminders, inconsistent extraction recovery, and review queue confusion.

The current quality strategy is to keep product behavior deterministic enough to inspect repeatedly:

- Fresh-install launches reset local state with `--reset-db`.
- Seed scenarios load known histories through `--seed-scenario=<id>`.
- Fake extraction mode uses deterministic fixture payloads instead of live model output.
- UI walkthroughs exercise the primary surfaces in Simulator.
- Screenshot baselines catch visual regression across Timeline, Things, Carry Forward, Review, Search, and first launch states.
- Internal QA diagnostics expose extraction attempts, recovery state, export comparison, and scenario artifacts for debug builds.

Future contributor guidance:

- Treat scenario fixtures as product contracts. Update them intentionally when behavior changes.
- Prefer deterministic tests over live AI calls.
- Verify relationship integrity when changing extraction, review queue, reminders, Things, search, or timeline projections.
- Preserve timeline readability and density; regressions here are product bugs even when data is technically correct.
- Keep backend provider behavior behind the backend boundary. The iOS app should know only the LifeOrganize AI service contract.

