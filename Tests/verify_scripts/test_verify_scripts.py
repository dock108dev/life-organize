import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class VerifyScriptContractTests(unittest.TestCase):
    def script(self, relative_path):
        return ROOT / relative_path

    def read_script(self, relative_path):
        return self.script(relative_path).read_text(encoding="utf-8")

    def test_top_level_scripts_are_executable(self):
        for relative_path in [
            "Scripts/verify-backend.sh",
            "Scripts/verify-ios.sh",
            "Scripts/verify-all.sh",
            "Scripts/run-adaptive-screen-validation.sh",
            "Scripts/ios_static_layout_guard.py",
            "Scripts/simulator-common.sh",
        ]:
            path = self.script(relative_path)
            self.assertTrue(path.exists(), relative_path)
            self.assertTrue(os.access(path, os.X_OK), relative_path)

    def test_backend_script_runs_configured_static_and_coverage_gates(self):
        text = self.read_script("Scripts/verify-backend.sh")

        self.assertIn('"$PYTHON_BIN" -m venv', text)
        self.assertIn("-m pip install -r", text)
        self.assertIn("ruff check app tests infra/scripts", text)
        self.assertIn("compileall app tests infra/scripts", text)
        self.assertIn("pytest tests", text)
        self.assertIn("BACKEND_SMOKE_URL", text)
        self.assertIn("smoke)", text)

    def test_ios_script_runs_tests_with_coverage_and_parser(self):
        text = self.read_script("Scripts/verify-ios.sh")

        self.assertIn("IOS_DESTINATION", text)
        self.assertIn("IOS_DEVICE_NAME", text)
        self.assertIn("IOS_DEVICE_OS", text)
        self.assertIn("IOS_RESULT_BUNDLE", text)
        self.assertIn("IOS_DERIVED_DATA", text)
        self.assertIn("IOS_TEST_LOG", text)
        self.assertIn("simulator-common.sh", text)
        self.assertIn("simulator_udid_for", text)
        self.assertIn("configure_simulator_for_ui_capture", text)
        self.assertIn("platform=iOS Simulator,id=$SIMULATOR_UDID", text)
        self.assertIn("-enableCodeCoverage YES", text)
        self.assertIn("-derivedDataPath \"$DERIVED_DATA\"", text)
        self.assertIn("-resultBundlePath \"$RESULT_BUNDLE\"", text)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", text)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", text)
        self.assertIn("IOS_SKIP_COVERAGE_GATE", text)
        self.assertIn("ios_static_layout_guard.py", text)
        self.assertLess(text.index("ios_static_layout_guard.py"), text.index("xcodebuild test"))
        self.assertIn("xcodebuild_result_bundle_passed", text)
        self.assertIn("xcresulttool get test-results summary", text)
        self.assertIn("xcresulttool get build-results", text)
        self.assertIn("collect_values(tests, \"passedTests\")", text)
        self.assertIn("collect_values(tests, \"totalTestCount\")", text)
        self.assertIn("executed_count > 0", text)
        self.assertIn("failed_count == 0", text)
        self.assertIn("has_failure_details", text)
        self.assertIn("xcresult summary counts", text)
        self.assertIn("finalLogPassed", text)
        self.assertIn("retained failure details", text)
        self.assertIn('tee "$TEST_LOG"', text)
        self.assertIn("xcresult test summary did not report a clean pass", text)
        self.assertIn("xcresult build summary reported build errors", text)
        self.assertIn("xcodebuild exited", text)
        self.assertIn("ios_coverage_gate.py", text)

    def test_ios_script_accepts_clean_xcresult_when_xcodebuild_exits_65(self):
        completed = self.run_verify_ios_with_fake_xcresult(
            test_summary='{"devicesAndConfigurations":[{"failedTests":0,"passedTests":33}],"failedTests":0,"skippedTests":3,"testFailures":[]}',
            build_summary='{"errorCount":0,"errors":[],"status":"succeeded"}',
        )

        self.assertEqual(
            completed.returncode,
            0,
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
        )
        self.assertIn("xcodebuild exited 65", completed.stderr)

    def test_ios_script_accepts_clean_counts_when_xcresult_action_is_failed(self):
        completed = self.run_verify_ios_with_fake_xcresult(
            test_summary='{"result":"Failed","totalTestCount":36,"failedTests":0,"skippedTests":3,"testFailures":[]}',
            build_summary='{"errorCount":0,"errors":[],"status":"succeeded"}',
        )

        self.assertEqual(
            completed.returncode,
            0,
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
        )
        self.assertIn("xcodebuild exited 65", completed.stderr)

    def test_ios_script_accepts_retained_xcresult_failure_when_final_log_passes(self):
        completed = self.run_verify_ios_with_fake_xcresult(
            test_summary='{"result":"Failed","totalTestCount":627,"passedTests":623,"failedTests":1,"skippedTests":3,"testFailures":[{"testName":"RetainedAttempt"}]}',
            build_summary='{"errorCount":0,"errors":[],"status":"succeeded"}',
            xcodebuild_log=(
                "Test Suite 'All tests' passed at 2026-05-28 03:07:52.943.\\n"
                "\\t Executed 33 tests, with 0 failures (0 unexpected) in 671.004 seconds\\n"
                "** TEST FAILED **\\n"
            ),
        )

        self.assertEqual(
            completed.returncode,
            0,
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
        )
        self.assertIn("retained failure details", completed.stderr)
        self.assertIn("xcodebuild exited 65", completed.stderr)

    def test_ios_script_rejects_xcresult_with_failed_test_count_without_final_pass_log(self):
        completed = self.run_verify_ios_with_fake_xcresult(
            test_summary='{"result":"Failed","totalTestCount":36,"failedTests":1,"skippedTests":3,"testFailures":[]}',
            build_summary='{"errorCount":0,"errors":[],"status":"succeeded"}',
            xcodebuild_log="** TEST FAILED **\\n",
        )

        self.assertEqual(
            completed.returncode,
            65,
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
        )
        self.assertIn("xcresult test summary did not report a clean pass", completed.stderr)
        self.assertIn("failed=1", completed.stderr)

    def run_verify_ios_with_fake_xcresult(self, test_summary, build_summary, xcodebuild_log=None):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            result_bundle = temp_path / "LifeOrganizeTests.xcresult"

            xcodebuild = fake_bin / "xcodebuild"
            xcodebuild.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    while [[ "$#" -gt 0 ]]; do
                      if [[ "$1" == "-resultBundlePath" ]]; then
                        result_bundle="$2"
                        shift 2
                        continue
                      fi
                      shift
                    done
                    mkdir -p "$result_bundle"
                    touch "$result_bundle/Info.plist"
                    printf '%b' "$XCODEBUILD_FAKE_LOG"
                    exit 65
                    """
                ),
                encoding="utf-8",
            )
            xcodebuild.chmod(0o755)

            xcrun = fake_bin / "xcrun"
            xcrun.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    if [[ "$1" == "xcresulttool" && "$2" == "get" && "$3" == "test-results" ]]; then
                      printf '%s\\n' "$XCRESULT_TEST_SUMMARY"
                      exit 0
                    fi
                    if [[ "$1" == "xcresulttool" && "$2" == "get" && "$3" == "build-results" ]]; then
                      printf '%s\\n' "$XCRESULT_BUILD_SUMMARY"
                      exit 0
                    fi
                    printf 'unexpected xcrun invocation: %s\\n' "$*" >&2
                    exit 1
                    """
                ),
                encoding="utf-8",
            )
            xcrun.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{fake_bin}{os.pathsep}{env['PATH']}",
                    "IOS_DESTINATION": "platform=iOS Simulator,id=fake-device",
                    "IOS_RESULT_BUNDLE": str(result_bundle),
                    "IOS_DERIVED_DATA": str(temp_path / "DerivedData"),
                    "IOS_TEST_LOG": str(temp_path / "xcodebuild-test.log"),
                    "IOS_SKIP_COVERAGE_GATE": "1",
                    "XCRESULT_TEST_SUMMARY": test_summary,
                    "XCRESULT_BUILD_SUMMARY": build_summary,
                    "XCODEBUILD_FAKE_LOG": xcodebuild_log
                    or (
                        "Test Suite 'All tests' passed at 2026-05-28 03:07:52.943.\\n"
                        "\\t Executed 33 tests, with 0 failures (0 unexpected) in 671.004 seconds\\n"
                        "** TEST FAILED **\\n"
                    ),
                }
            )

            return subprocess.run(
                [str(self.script("Scripts/verify-ios.sh"))],
                cwd=ROOT,
                env=env,
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

    def test_ios_static_layout_guard_contract(self):
        text = self.read_script("Scripts/ios_static_layout_guard.py")

        for expected in [
            '"LifeOrganize"',
            '"LifeOrganizeTests"',
            '"LifeOrganizeUITests"',
            "UIScreen",
            "UIDevice",
            "SUSPICIOUS_WIDTH_MIN = 300",
            "SUSPICIOUS_HEIGHT_MIN = 500",
            "layout-guard:",
            '"iPhone_17_Pro", "landscape", "light"',
            '"iPad_Pro_13-inch_M5", "portrait", "light"',
            '"iPad_Pro_13-inch_M5", "landscape", "light"',
            '"timeline_empty"',
            "missing screenshot baseline",
        ]:
            self.assertIn(expected, text)

    def test_ios_workflow_is_ci_only_with_stable_checks(self):
        text = self.read_script(".github/workflows/ios-ci.yml")

        self.assertIn("name: iOS CI", text)
        self.assertIn("contents: read", text)
        self.assertIn("name: ios / build", text)
        self.assertIn("name: ios / unit and ui tests", text)
        self.assertIn("name: ios / coverage >= 80", text)
        self.assertIn("name: ios / screenshots", text)
        self.assertIn("platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2", text)
        self.assertIn("xcodebuild build-for-testing", text)
        self.assertIn("Scripts/verify-ios.sh", text)
        self.assertIn("IOS_SKIP_COVERAGE_GATE: \"1\"", text)
        self.assertIn("IOS_RESULT_PACKAGE: \"BuildArtifacts/LifeOrganizeTests.xcresult.tar.gz\"", text)
        self.assertIn("Package iOS test result bundle for coverage", text)
        self.assertIn("tar -czf \"$IOS_RESULT_PACKAGE\" -C BuildArtifacts LifeOrganizeTests.xcresult", text)
        self.assertIn("Extract iOS test result bundle", text)
        self.assertIn("tar -xzf \"$IOS_RESULT_PACKAGE\" -C BuildArtifacts", text)
        self.assertIn("test -f \"$IOS_RESULT_BUNDLE/Info.plist\"", text)
        self.assertIn("actions/download-artifact@v4", text)
        self.assertIn("ios-test-result-bundle-${{ github.sha }}", text)
        self.assertIn("Scripts/screenshots/run-screenshot-tests.sh compare", text)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", text)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", text)
        self.assertIn("actions/upload-artifact@v4", text)
        self.assertIn("BuildArtifacts/LifeOrganizeTests.xcresult", text)
        self.assertIn("BuildArtifacts/ScreenshotTests-iPhone_17_Pro-portrait-light.xcresult", text)
        self.assertIn("BuildArtifacts/Logs/test.log", text)
        self.assertIn("BuildArtifacts/screenshots/compare.log", text)

    def test_ios_workflow_triggers_on_ios_and_screenshot_paths(self):
        text = self.read_script(".github/workflows/ios-ci.yml")

        for expected_path in [
            "LifeOrganize/**",
            "LifeOrganizeTests/**",
            "LifeOrganizeUITests/**",
            "LifeOrganize.xcodeproj/**",
            "Scripts/ios_coverage_gate.py",
            "Scripts/ios_static_layout_guard.py",
            "Scripts/verify-ios.sh",
            "Scripts/verify-common.sh",
            "Scripts/simulator-common.sh",
            "Scripts/screenshots/**",
            "Tests/ScreenshotBaselines/**",
            "fastlane/**",
            "docs/screenshot-baselines.md",
            "**/*.strings",
            "**/*.xcassets/**",
            "**/*.png",
            ".github/workflows/ios-ci.yml",
        ]:
            self.assertIn(expected_path, text)

        push_section = text.split("pull_request:", maxsplit=1)[0]
        self.assertNotIn("paths:", push_section)

    def test_screenshot_workflow_uploads_recovery_artifacts(self):
        text = self.read_script(".github/workflows/ios-ci.yml")

        for expected in [
            "SCREENSHOT_DEVICE_NAME: \"iPhone 17 Pro\"",
            "SCREENSHOT_DEVICE_OS: \"26.2\"",
            "SCREENSHOT_TARGET_KEY: \"iPhone_17_Pro\"",
            "SCREENSHOT_ORIENTATION: \"portrait\"",
            "SCREENSHOT_APPEARANCE: \"light\"",
            "SCREENSHOT_RESULT_BUNDLE: \"BuildArtifacts/ScreenshotTests-iPhone_17_Pro-portrait-light.xcresult\"",
            "SCREENSHOT_ACTUAL_DIR: \"BuildArtifacts/screenshots/actual/iPhone_17_Pro/portrait/light\"",
            "SCREENSHOT_DIFF_DIR: \"BuildArtifacts/screenshots/diff/iPhone_17_Pro/portrait/light\"",
            "SCREENSHOT_BASELINE_DIR: \"Tests/ScreenshotBaselines/iPhone_17_Pro/portrait/light\"",
            "BuildArtifacts/screenshots/actual/iPhone_17_Pro/portrait/light",
            "BuildArtifacts/screenshots/diff/iPhone_17_Pro/portrait/light",
            "BuildArtifacts/screenshots/compare.log",
            "screenshot-failure-iPhone_17_Pro-light-${{ github.sha }}",
            "screenshot_profile",
            "SCREENSHOT_TARGET_KEY: \"iPad_Pro_13-inch_M5\"",
            "SCREENSHOT_DEVICE_NAME: \"iPad Pro 13-inch (M5)\"",
            "BuildArtifacts/screenshots/actual/iPad_Pro_13-inch_M5/portrait/light",
            "Tests/ScreenshotBaselines/iPad_Pro_13-inch_M5/portrait/light",
            "ios / screenshots / iPad portrait",
        ]:
            self.assertIn(expected, text)

    def test_ios_workflow_does_not_request_release_or_deploy_capabilities(self):
        text = self.read_script(".github/workflows/ios-ci.yml").lower()

        for forbidden in [
            "packages: write",
            "id-token: write",
            "deployments: write",
            "archive",
            "exportarchive",
            "notar",
            "testflight",
            "app-store",
            "appstore",
            "mobileprovision",
            "provisioning_profile",
            "app_store_connect",
            "apple_id",
            "fastlane_session",
            "docker",
            "ssh",
            "openai_api_key",
        ]:
            self.assertNotIn(forbidden, text)

    def test_branch_protection_contract_lists_required_checks_and_boundaries(self):
        text = self.read_script("docs/ops/branch-protection.md")

        for check in [
            "`backend / tests`",
            "`backend / lint`",
            "`backend / compile`",
            "`backend / coverage >= 80`",
            "`backend / docker build`",
            "`ios / build`",
            "`ios / unit and ui tests`",
            "`ios / coverage >= 80`",
            "`ios / screenshots`",
            "`prod / healthz smoke`",
        ]:
            self.assertIn(check, text)

        self.assertIn("Do not require deploy-only jobs on pull requests", text)
        self.assertIn("Keep it out of pull request required checks", text)
        self.assertIn("`ios / screenshots` is the required pull request visual check", text)
        self.assertIn("`ios / screenshots / iPad portrait` is a non-required iOS CI job", text)
        self.assertIn("screenshot_profile=ipad_portrait", text)
        self.assertIn("screenshot_profile=all_light", text)
        self.assertIn("Scripts/run-adaptive-screen-validation.sh compare", text)
        self.assertIn("Keep iPad landscape screenshots, Dynamic Type smoke, and broader simulator matrix checks manual or nightly", text)
        self.assertIn("GitHub Actions to Hetzner", text)
        self.assertIn("must not sign, archive", text)
        self.assertIn("update branch protection in the same", text)

    def test_verify_all_runs_disciplines_in_braindump_order(self):
        text = self.read_script("Scripts/verify-all.sh")

        backend = text.index("Scripts/verify-backend.sh")
        ios = text.index("Scripts/verify-ios.sh")
        screenshots = text.index("Scripts/screenshots/run-screenshot-tests.sh")
        backend_smoke = text.rindex("Scripts/verify-backend.sh")
        production_smoke = text.index("run curl --fail")

        self.assertLess(backend, ios)
        self.assertLess(ios, screenshots)
        self.assertLess(screenshots, backend_smoke)
        self.assertIn("--with-backend-smoke", text)
        self.assertIn("--with-production-smoke", text)
        self.assertIn("BACKEND_SMOKE_URL", text)
        self.assertIn("IOS_DESTINATION", text)
        self.assertLess(backend_smoke, production_smoke)

    def test_adaptive_screen_validation_matrix_contract(self):
        text = self.read_script("Scripts/run-adaptive-screen-validation.sh")

        for expected in [
            "iPhone_17_Pro|$IPHONE_DEVICE|portrait",
            "iPhone_17_Pro|$IPHONE_DEVICE|landscape",
            "iPad_Pro_13-inch_M5|$IPAD_PRO_DEVICE|portrait",
            "iPad_Pro_13-inch_M5|$IPAD_PRO_DEVICE|landscape",
            "iPad mini (A17 Pro)|iPad (A16)|iPad Air 11-inch (M3)|iPad Pro 11-inch (M5)",
            "stage_manager_narrow_window=not covered",
            "CoreSimulator CLI cannot reliably create or size Stage Manager windows",
            "BuildArtifacts/AdaptiveScreenValidation",
            "ADAPTIVE_SCREEN_SCREENSHOT_ATTEMPTS",
            "screenshot_attempts=%s",
            "Retrying screenshot matrix cell after failed capture or comparison",
            "SCREENSHOT_RESULT_BUNDLE=\"$ARTIFACT_ROOT/ScreenshotTests-$target_key-$orientation-$APPEARANCE.xcresult\"",
            "SCREENSHOT_ACTUAL_DIR=\"BuildArtifacts/screenshots/actual/$target_key/$orientation/$APPEARANCE\"",
            "SCREENSHOT_DIFF_DIR=\"BuildArtifacts/screenshots/diff/$target_key/$orientation/$APPEARANCE\"",
            "SCREENSHOT_BASELINE_DIR=\"Tests/ScreenshotBaselines/$target_key/$orientation/$APPEARANCE\"",
            "\"$SCRIPT_DIR/screenshots/run-screenshot-tests.sh\" \"$MODE\"",
            "DYNAMIC_TYPE_RESULT_ROOT=\"$ARTIFACT_ROOT/DynamicTypeSmoke\"",
            "\"$SCRIPT_DIR/run-dynamic-type-ui-smoke.sh\"",
            "LifeOrganizeUITests/AdaptiveShellUITests/testCompactLaunchKeepsTabsAndUtilityModals",
            "LifeOrganizeUITests/AdaptiveShellUITests/testRegularWidthSidebarShowsWorkspaceUtilitiesAndConditionalReview",
            "LifeOrganizeUITests/AdaptiveShellUITests/testRegularWidthScreenshotStartsRouteToSidebarDestinations",
            "LifeOrganizeUITests/AdaptiveShellUITests/testPadPortraitShellKeepsCoreDestinationsReachable",
            "AdaptiveShell-$label.xcresult",
            "compare|update",
        ]:
            self.assertIn(expected, text)

    def test_dynamic_type_smoke_script_runs_required_accessibility_sizes(self):
        text = self.read_script("Scripts/run-dynamic-type-ui-smoke.sh")

        for expected in [
            "large|large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testLargeTextSizeCoreControlsStayReachable",
            "accessibility-large|accessibility-large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testAccessibilityLargeTextSizeCoreControlsStayReachable",
            "accessibility-extra-extra-extra-large|accessibility-extra-extra-extra-large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testAccessibilityXXXLTextSizeCoreControlsStayReachable",
            "DYNAMIC_TYPE_TEST_EXECUTION_ALLOWANCE",
            "Usage: Scripts/run-dynamic-type-ui-smoke.sh",
            "-h|--help",
            "-test-timeouts-enabled YES",
            "-default-test-execution-time-allowance \"$TEST_EXECUTION_ALLOWANCE\"",
            "-maximum-test-execution-time-allowance \"$TEST_EXECUTION_ALLOWANCE\"",
        ]:
            self.assertIn(expected, text)

    def test_adaptive_shell_ui_tests_include_pad_portrait_smoke(self):
        text = self.read_script("LifeOrganizeUITests/AdaptiveShellUITests.swift")

        for expected in [
            "testPadPortraitShellKeepsCoreDestinationsReachable",
            "XCUIDevice.shared.orientation = .portrait",
            "--seed-scenario=operational_home",
            "sidebar-section-timeline",
            "tabBars.buttons[\"Timeline\"]",
            "root-search-entry",
            "settings-entry",
        ]:
            self.assertIn(expected, text)

    def test_screenshot_script_targets_current_screenshot_methods(self):
        text = self.read_script("Scripts/screenshots/run-screenshot-tests.sh")

        self.assertIn("LifeOrganizeScenarioUITests/testFirstLaunchAndEmptyTimelineScreenshots", text)
        self.assertIn("LifeOrganizeScenarioUITests/testTimelineScreenshot", text)
        self.assertIn("LifeOrganizeScenarioUITests/testThingsAndThingDetailScreenshots", text)
        self.assertIn("LifeOrganizeScenarioUITests/testCarryForwardScreenshot", text)
        self.assertIn("LifeOrganizeScenarioUITests/testSearchScreenshot", text)
        self.assertIn("LifeOrganizeScenarioUITests/testReviewQueueScreenshot", text)
        self.assertIn("LifeOrganizeScenarioUITests/testHeavyTimelineScreenshot", text)
        self.assertIn("extract-xcresult-screenshots.sh", text)
        self.assertIn("SCREENSHOT_TARGET_KEY", text)
        self.assertIn("SCREENSHOT_ORIENTATION", text)
        self.assertIn("portrait|landscape", text)
        self.assertIn("BuildArtifacts/screenshots/orientation.txt", text)
        self.assertIn("BuildArtifacts/ScreenshotTests-$TARGET_KEY-$ORIENTATION-$APPEARANCE.xcresult", text)
        self.assertIn("BuildArtifacts/screenshots/actual/$TARGET_KEY/$ORIENTATION/$APPEARANCE", text)
        self.assertIn("Tests/ScreenshotBaselines/$TARGET_KEY/$ORIENTATION/$APPEARANCE", text)
        self.assertIn("LEGACY_BASELINE_DIR", text)
        self.assertIn("simulator-common.sh", text)
        self.assertIn("configure_simulator_for_ui_capture", text)
        self.assertIn("Scripts/screenshots/run-screenshot-tests.sh update", text)

    def test_simulator_common_script_owns_ui_capture_setup(self):
        text = self.read_script("Scripts/simulator-common.sh")

        for expected in [
            "simulator_udid_for()",
            '"Booted"',
            "user_app_bundle_ids_for()",
            "configure_simulator_for_ui_capture()",
            "xcrun simctl status_bar",
            "xcrun simctl ui \"$udid\" appearance",
            "xcrun simctl ui \"$udid\" content_size",
        ]:
            self.assertIn(expected, text)

    def test_screenshot_compare_output_distinguishes_failure_modes(self):
        text = self.read_script("Scripts/screenshots/compare-screenshots.swift")

        for expected in [
            "missing actual",
            "size mismatch",
            "unexpected screenshot",
            "pixel-diff",
            "baseline:",
            "actual:",
            "diff:",
            "Scripts/screenshots/run-screenshot-tests.sh update",
        ]:
            self.assertIn(expected, text)


if __name__ == "__main__":
    unittest.main()
