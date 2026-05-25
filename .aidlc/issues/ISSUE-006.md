# ISSUE-006: Add backend database migration and Docker smoke tests

**Priority**: high
**Labels**: backend, docker, database, smoke
**Dependencies**: ISSUE-001, ISSUE-016
**Status**: implemented

## Description

Add the database and container smoke layer BRAINDUMP calls out: empty Postgres migration, migration idempotency, request metadata persistence, Docker image start, and `/healthz`. Use `.aidlc/research/backend-database-migration-smoke.md` and `.aidlc/research/backend-docker-health-and-migrations.md`, with ISSUE-016 providing any reusable app/session fixtures.

## Acceptance Criteria

- [ ] A migration smoke path upgrades a truly empty PostgreSQL database to Alembic head and verifies the expected application tables, indexes, and version row.
- [ ] Running migrations a second time is tested or smoked as idempotent.
- [ ] Application-level tests prove `AIRequestLog` request metadata persists and can be read back without storing raw device tokens or raw user text.
- [ ] Database connection or transaction failure behavior is tested as controlled failure rather than silent success or partial writes.
- [ ] A Docker compose smoke builds the API image, starts Postgres, runs migrations, starts API, waits for container health, and curls `http://127.0.0.1:8787/healthz`.

## Implementation Notes


Attempt 1: Added Postgres-backed Alembic/idempotency, AIRequestLog persistence, rollback, and unreachable-DB tests in Backend/tests/test_database_migrations.py; added Docker compose smoke script and wired backend CI to run Postgres integration and Docker health smoke before image publish.