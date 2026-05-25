# AIDLC Planning Index

## Intent Source (authoritative)
- BRAINDUMP.md

## Reference Docs (optional context — never expand scope)
- README.md

## Discovery (pre-built — current repo state)
- .aidlc/discovery/findings.md
- .aidlc/discovery/topics.json

## Research (pre-built — answers to discovery topics)
- .aidlc/research/ai-client-error-shape-parity.md
- .aidlc/research/backend-admin-log-redaction-and-sse.md
- .aidlc/research/backend-caddy-helper-contract.md
- .aidlc/research/backend-ci-status-check-splitting.md
- .aidlc/research/backend-coverage-gate-shape.md
- .aidlc/research/backend-database-migration-smoke.md
- .aidlc/research/backend-docker-health-and-migrations.md
- .aidlc/research/backend-middleware-test-surface.md
- .aidlc/research/backend-openai-gateway-error-mapping.md
- .aidlc/research/backend-post-deploy-public-smoke.md
- .aidlc/research/backend-python-version-pin.md
- .aidlc/research/backend-rate-limit-contract.md
- .aidlc/research/backend-request-contract-parity.md
- .aidlc/research/backend-route-auth-test-matrix.md
- .aidlc/research/branch-protection-check-names.md
- .aidlc/research/chat-send-idempotency-contract.md
- .aidlc/research/chat-send-local-first-failure-matrix.md
- .aidlc/research/deployment-rollback-migration-constraint.md
- .aidlc/research/docs-state-drift.md
- .aidlc/research/frontend-default-backend-contract.md
- .aidlc/research/frontend-secret-surface-guardrails.md
- .aidlc/research/ios-ci-runner-simulator-pin.md
- .aidlc/research/ios-ci-workflow-scope-no-deploy.md
- .aidlc/research/ios-ui-test-live-network-boundary.md
- .aidlc/research/ios-xccov-app-target-parser.md
- .aidlc/research/local-verify-script-composition.md
- .aidlc/research/screenshot-ci-cadence-and-artifacts.md
- .aidlc/research/swiftdata-coverage-denominator.md

## Existing Issues (23 files in .aidlc/issues/)
Read individual issue files for full specs:
- .aidlc/issues/ISSUE-001.md
- .aidlc/issues/ISSUE-002.md
- .aidlc/issues/ISSUE-003.md
- .aidlc/issues/ISSUE-004.md
- .aidlc/issues/ISSUE-005.md
- .aidlc/issues/ISSUE-006.md
- .aidlc/issues/ISSUE-007.md
- .aidlc/issues/ISSUE-008.md
- .aidlc/issues/ISSUE-009.md
- .aidlc/issues/ISSUE-010.md
- .aidlc/issues/ISSUE-011.md
- .aidlc/issues/ISSUE-012.md
- .aidlc/issues/ISSUE-013.md
- .aidlc/issues/ISSUE-014.md
- .aidlc/issues/ISSUE-015.md
- .aidlc/issues/ISSUE-016.md
- .aidlc/issues/ISSUE-017.md
- .aidlc/issues/ISSUE-018.md
- .aidlc/issues/ISSUE-019.md
- .aidlc/issues/ISSUE-020.md
- .aidlc/issues/ISSUE-021.md
- .aidlc/issues/ISSUE-022.md
- .aidlc/issues/ISSUE-023.md

## Issue Backlog Summary
- Total issues: 23
- Completion: 0/23 (0.0%)
- Priority totals: high=21, medium=2, low=0
- Status totals: pending=23

### Category Rollup (Labels)
- tests: 13
- ios: 11
- backend: 10
- functionality: 6
- new-feature: 6
- ci: 5
- usability-flow: 5
- design-visual: 4
- github-actions: 3
- infra: 3
- coverage: 2
- deployment: 2
- docker: 2
- frontend-contract: 2
- local-first: 2
- scripts: 2
- smoke: 2
- admin-logs: 1
- ai-service-client: 1
- auth: 1
- branch-protection: 1
- caddy: 1
- chat: 1
- configuration: 1
- copy-contracts: 1
- database: 1
- middleware: 1
- offline: 1
- openai-gateway: 1
- persistence: 1
- rate-limit: 1
- redaction: 1
- reminders: 1
- review-queue: 1
- rules: 1
- screenshots: 1
- search: 1
- security: 1
- swiftdata: 1
- things: 1
- timeline: 1
- ui-tests: 1
- verification: 1

### Active Issues
- ISSUE-001 [pending] [high] — Align backend Python runtime and coverage tooling labels: backend, coverage, ci, infra
- ISSUE-002 [pending] [high] — Expand backend config auth and rate-limit tests labels: backend, tests, auth, rate-limit
- ISSUE-003 [pending] [high] — Cover backend middleware and health contracts labels: backend, tests, middleware
- ISSUE-004 [pending] [high] — Stabilize backend gateway and DTO error contracts labels: backend, frontend-contract, tests, openai-gateway
- ISSUE-005 [pending] [high] — Test backend admin logs redaction and SSE labels: backend, tests, admin-logs, redaction
- ISSUE-006 [pending] [high] — Add backend database migration and Docker smoke tests labels: backend, docker, database, smoke
- ISSUE-007 [pending] [high] — Create local full verification scripts labels: scripts, verification, infra, usability-flow, new-feature
- ISSUE-008 [pending] [high] — Lock frontend backend-default and secret guardrails labels: ios, tests, configuration, security, copy-contracts
- ISSUE-009 [pending] [high] — Expand iOS chat send reliability tests labels: ios, tests, chat, local-first, functionality
- ISSUE-010 [pending] [high] — Define iOS coverage denominator and parser labels: ios, coverage, scripts, usability-flow, new-feature
- ISSUE-011 [pending] [high] — Add iOS CI workflow without deployment labels: ios, github-actions, ci, new-feature
- ISSUE-012 [pending] [medium] — Integrate screenshot comparison into iOS CI labels: ios, screenshots, ci, usability-flow, design-visual
- ISSUE-013 [pending] [high] — Split backend CI gates and add Docker smoke labels: backend, github-actions, ci, docker, new-feature
- ISSUE-014 [pending] [high] — Add production health smoke after backend deploy labels: backend, deployment, smoke, new-feature
- ISSUE-015 [pending] [medium] — Document final branch protection check set labels: github-actions, branch-protection, ci, new-feature
- ISSUE-016 [pending] [high] — Build backend route test fixture harness labels: backend, tests, infra
- ISSUE-017 [pending] [high] — Test backend deployment helper and rollback contracts labels: backend, deployment, tests, caddy
- ISSUE-018 [pending] [high] — Expand iOS SwiftData persistence coverage labels: ios, tests, swiftdata, persistence, functionality
- ISSUE-019 [pending] [high] — Expand iOS search recall timeline and things tests labels: ios, tests, search, timeline, things, functionality, design-visual
- ISSUE-020 [pending] [high] — Expand iOS reminder and rule lifecycle tests labels: ios, tests, reminders, rules, functionality
- ISSUE-021 [pending] [high] — Expand iOS ledger review queue tests labels: ios, tests, review-queue, functionality, design-visual
- ISSUE-022 [pending] [high] — Expand iOS UI journey and offline coverage labels: ios, ui-tests, offline, local-first, functionality, usability-flow, design-visual
- ISSUE-023 [pending] [high] — Expand iOS AI service client contract tests labels: ios, tests, ai-service-client, frontend-contract, usability-flow

### Completed Issues
- none

## Other Project Docs
- docs/backend.md
- docs/current-app-state.md
- docs/ops/deployment.md
- docs/product-stabilization-notes.md
- docs/screenshot-baselines.md
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibInstallName-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibPath-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-ExecutorLinkFileList-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/XCBuildData/06e8da148b3d4f340c480fda746fb566.xcbuilddata/target-graph.txt
- .build/DerivedData/Build/Intermediates.noindex/XCBuildData/545ee10e2160c7f203e01b0120e4be52.xcbuilddata/target-graph.txt
- .build/DerivedData/Build/Intermediates.noindex/XCBuildData/7d328b12769164cd494f2e94be426865.xcbuilddata/target-graph.txt
- .build/DerivedData/Build/Intermediates.noindex/XCBuildData/a63bb8e714f43c444a97d6b9e2c545cc.xcbuilddata/target-graph.txt
- BRAINDUMP.md
- Backend/.pytest_cache/README.md
- Backend/requirements.txt
