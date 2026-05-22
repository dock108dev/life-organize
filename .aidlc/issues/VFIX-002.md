# VFIX-002: Fix: = Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch com.local.lifeorganiz

**Priority**: high
**Labels**: validation, auto-generated, test-fix
**Dependencies**: none
**Status**: implemented

## Description

Test `= Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch com.local.lifeorganize.uit` is failing and needs to be fixed.


**Instructions:**
- Read the test to understand what it expects
- Read the implementation code at the location above
- Fix the root cause — do not modify the test unless the test itself is wrong
- Ensure the fix doesn't break other tests

## Acceptance Criteria

- [ ] Test `= Error Domain=FBSOpenApplicationServiceErrorDomain Code=1 "Simulator device failed to launch com.local.lifeorganize.uit` passes
- [ ] No new test failures introduced by the fix

## Implementation Notes


Attempt 1: Serialized the LifeOrganize UI test target in the shared Xcode scheme so UI automation no longer launches concurrent cloned runner/app sessions against the same deterministic reset state.