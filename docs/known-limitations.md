# Known Limitations and Unsupported Paths

This document lists current intentional boundaries that are enforced by code, tests, or workflow configuration. It does not include planned features unless the current repository already exposes a relevant guardrail.

## iOS App

- The app is local-first and stores the ledger in SwiftData. There is no server-side ledger sync, account system, multi-device merge, widget target, watch target, TestFlight deploy target, or App Store deploy workflow in this repository.
- AI extraction and web-backed requests must go through the private FastAPI backend. The iOS app does not support direct provider credentials, manual API-key entry, or user-managed device-token setup.
- The app-managed device token is stored outside SwiftData through Keychain in normal app runs. Clearing local ledger data removes SwiftData records but does not remove the device token.
- Local search is substring-based over local ledger records and timeline slices. It is not a remote search service and is not semantic/vector search.
- Lifecycle commands for reminders are local prefix matches. Current completion/pause phrases include `i completed`, `i finished`, `i'm done with`, `completed`, `finished`, `done with`, `pause`, and `stop`; unmatched wording falls back to the normal chat-intent path.

## Backend

- The backend owns provider credentials and request logging only. It does not store the user's ledger.
- Device-token auto-enrollment is always on for first-seen valid-length tokens. `AUTO_ENROLL_DEVICE_TOKENS` is not read by current code.
- Admin log sessions are process-local. The current production Compose path runs one API process; shared admin-session storage is intentionally not implemented.
- FastAPI docs, ReDoc, and OpenAPI JSON are disabled in `production` and `staging`.

## Automation and CI

- Automation launch arguments use single-dash forms such as `-ui-testing` and `-seed-scenario=...`. Legacy double-dash aliases are intentionally unsupported.
- Screenshot baselines are maintained for the committed light-appearance matrix only. CI requires the iPhone 17 Pro portrait light comparison; broader iPhone/iPad matrix checks are local or manually dispatched unless the workflow changes.
- Stage Manager and narrow iPad window classes are not covered by the command-line adaptive validation script because CoreSimulator CLI does not reliably create that XCTest window class.
- iOS GitHub Actions build, test, check coverage, and compare screenshots only. They do not sign, archive, upload, deploy to TestFlight, or deploy to the App Store.
