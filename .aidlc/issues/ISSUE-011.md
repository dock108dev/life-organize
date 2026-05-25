# ISSUE-011: Add iOS CI workflow without deployment

**Priority**: high
**Labels**: ios, github-actions, ci, new-feature
**Dependencies**: ISSUE-010, ISSUE-022, ISSUE-023
**Status**: implemented

## Description

Add the new GitHub iOS CI workflow requested by BRAINDUMP, with an explicit no-deploy contract. Use `.aidlc/research/ios-ci-workflow-scope-no-deploy.md`, `.aidlc/research/ios-ci-runner-simulator-pin.md`, and `.aidlc/research/ios-ui-test-live-network-boundary.md`. The workflow should build and test iOS, prove production backend default configuration, run coverage, and upload failure artifacts, while deliberately excluding signing, archive, TestFlight, App Store, notarization, SSH, Docker, deployment permissions, and provider secrets.

## Acceptance Criteria

- [ ] A dedicated `.github/workflows/ios-ci.yml` triggers on PRs and pushes touching the iOS app, iOS tests, screenshot scripts/baselines, fastlane, workflow file, or Xcode project.
- [ ] The workflow uses least-privilege permissions such as `contents: read` and does not request package write, deployment, OIDC, SSH, or Apple signing permissions.
- [ ] The workflow builds and tests the `LifeOrganize` scheme on the pinned simulator destination with `CODE_SIGNING_ALLOWED=NO` and code coverage enabled.
- [ ] The workflow runs the shared iOS coverage parser from ISSUE-010 and exposes a stable `ios / coverage >= 80` check.
- [ ] Routine tests mock or stub network at the client boundary and do not make live OpenAI/provider calls.
- [ ] Configuration tests prove the default frontend backend is `https://life.dock108.dev`, while local backend use is only possible through explicit launch arguments.
- [ ] The workflow contains no archive, export, notarization, TestFlight, App Store upload, deploy, or mobile provisioning steps.
- [ ] Failure artifacts include the xcresult bundle and relevant simulator/test logs.

## Implementation Notes


Attempt 1: Added dedicated iOS CI workflow with scoped triggers, read-only permissions, pinned simulator build/test, coverage gate check, and failure artifacts; hardened verify-ios signing/DerivedData handling and added workflow/script contract tests.