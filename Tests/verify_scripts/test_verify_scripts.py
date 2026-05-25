import os
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
        self.assertIn("IOS_RESULT_BUNDLE", text)
        self.assertIn("IOS_DERIVED_DATA", text)
        self.assertIn("-enableCodeCoverage YES", text)
        self.assertIn("-derivedDataPath \"$DERIVED_DATA\"", text)
        self.assertIn("-resultBundlePath \"$RESULT_BUNDLE\"", text)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", text)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", text)
        self.assertIn("IOS_SKIP_COVERAGE_GATE", text)
        self.assertIn("ios_coverage_gate.py", text)

    def test_ios_workflow_is_ci_only_with_stable_checks(self):
        text = self.read_script(".github/workflows/ios-ci.yml")

        self.assertIn("name: iOS CI", text)
        self.assertIn("contents: read", text)
        self.assertIn("name: ios / build", text)
        self.assertIn("name: ios / unit and ui tests", text)
        self.assertIn("name: ios / coverage >= 80", text)
        self.assertIn("name: ios / screenshots", text)
        self.assertIn("platform=iOS Simulator,name=iPhone 16,OS=18.6", text)
        self.assertIn("xcodebuild build-for-testing", text)
        self.assertIn("Scripts/verify-ios.sh", text)
        self.assertIn("IOS_SKIP_COVERAGE_GATE: \"1\"", text)
        self.assertIn("actions/download-artifact@v4", text)
        self.assertIn("ios-test-result-bundle-${{ github.sha }}", text)
        self.assertIn("Scripts/screenshots/run-screenshot-tests.sh compare", text)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", text)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", text)
        self.assertIn("actions/upload-artifact@v4", text)
        self.assertIn("BuildArtifacts/LifeOrganizeTests.xcresult", text)
        self.assertIn("BuildArtifacts/ScreenshotTests.xcresult", text)
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
            "Scripts/verify-ios.sh",
            "Scripts/verify-common.sh",
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
            "SCREENSHOT_DEVICE_NAME: \"iPhone 16\"",
            "SCREENSHOT_DEVICE_OS: \"18.6\"",
            "SCREENSHOT_APPEARANCE: \"light\"",
            "SCREENSHOT_RESULT_BUNDLE: \"BuildArtifacts/ScreenshotTests.xcresult\"",
            "SCREENSHOT_ACTUAL_DIR: \"BuildArtifacts/screenshots/actual/iPhone_16/light\"",
            "SCREENSHOT_DIFF_DIR: \"BuildArtifacts/screenshots/diff/iPhone_16/light\"",
            "SCREENSHOT_BASELINE_DIR: \"Tests/ScreenshotBaselines/iPhone_16/light\"",
            "BuildArtifacts/screenshots/actual/iPhone_16/light",
            "BuildArtifacts/screenshots/diff/iPhone_16/light",
            "BuildArtifacts/screenshots/compare.log",
            "screenshot-failure-iPhone_16-light-${{ github.sha }}",
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
        self.assertIn("BuildArtifacts/ScreenshotTests.xcresult", text)
        self.assertIn("Scripts/screenshots/run-screenshot-tests.sh update", text)

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
