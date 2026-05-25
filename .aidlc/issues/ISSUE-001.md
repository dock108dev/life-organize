# ISSUE-001: Align backend Python runtime and coverage tooling

**Priority**: high
**Labels**: backend, coverage, ci, infra
**Dependencies**: none
**Status**: implemented

## Description

Implement the backend runtime/test foundation from BRAINDUMP's backend coverage and Python-pin gaps. Use `.aidlc/discovery/findings.md`, `.aidlc/research/backend-python-version-pin.md`, and `.aidlc/research/backend-coverage-gate-shape.md`: choose a stable production/CI runtime such as Python 3.13 while preserving the declared `>=3.11` support contract unless intentionally changed; add `pytest-cov`; configure coverage for `Backend/app` and `Backend/main.py`; exclude Alembic boilerplate deliberately and visibly.

## Acceptance Criteria

- [ ] `Backend/requirements.txt` includes a pinned `pytest-cov` dependency consistent with the repo's exact-pin style.
- [ ] `Backend/pyproject.toml` configures pytest coverage for `app` and `main` with `--cov-fail-under=80` and term-missing output.
- [ ] Alembic paths are explicitly omitted from coverage or otherwise reported as deliberate exclusions, not silently hidden by accident.
- [ ] Backend CI and Docker runtime pins are aligned to the chosen stable Python version, or the implementation documents and tests the intentional decision to stay on Python 3.14.
- [ ] `requires-python` and Ruff target remain coherent with the selected compatibility contract.
- [ ] If `requires-python = ">=3.11"` remains, the plan either adds a lightweight compatibility check for the lower bound or explicitly narrows the support contract with matching Ruff/project metadata.

## Implementation Notes


Attempt 1: Added pinned pytest-cov, Backend coverage config for app/main with Alembic omissions, Python 3.13 CI/Docker pins, Python 3.11 compatibility CI, and backend tests for routes/config/middleware/gateway.