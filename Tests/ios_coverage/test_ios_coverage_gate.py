import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "ios_coverage_gate.py"


def file(path, covered, executable):
    return {"name": str(ROOT / path), "coveredLines": covered, "executableLines": executable}


class IOSCoverageGateTests(unittest.TestCase):
    def run_gate(self, payload=None, raw=None):
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "xccov.json"
            if raw is None:
                report_path.write_text(json.dumps(payload), encoding="utf-8")
            else:
                report_path.write_text(raw, encoding="utf-8")
            return subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "Fixture.xcresult",
                    "--report-json",
                    str(report_path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

    def test_passes_when_app_target_meets_threshold(self):
        result = self.run_gate(
            {
                "targets": [
                    {
                        "name": "LifeOrganize.app",
                        "files": [
                            file("LifeOrganize/AppRootView.swift", 80, 100),
                            file("LifeOrganize/Persistence/LifeOrganizeSchemaV2.swift", 0, 50),
                        ],
                    },
                    {
                        "name": "LifeOrganizeTests.xctest",
                        "files": [file("LifeOrganizeTests/LifeOrganizeTests.swift", 20, 20)],
                    },
                ]
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("app coverage: 80.00%", result.stdout)
        self.assertIn("LifeOrganize.app", result.stdout)
        self.assertIn("LifeOrganizeTests.xctest: unit test bundle product", result.stdout)
        self.assertIn("LifeOrganize/Persistence/LifeOrganizeSchemaV2.swift: historical schema snapshot", result.stdout)

    def test_fails_when_app_target_is_below_threshold(self):
        result = self.run_gate(
            {
                "targets": [
                    {
                        "name": "LifeOrganize.app",
                        "files": [file("LifeOrganize/AppRootView.swift", 79, 100)],
                    }
                ]
            }
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("app coverage: 79.00%", result.stdout)
        self.assertIn("below 80.00%", result.stderr)

    def test_errors_when_app_target_is_missing(self):
        result = self.run_gate(
            {
                "targets": [
                    {
                        "name": "LifeOrganizeTests.xctest",
                        "files": [file("LifeOrganizeTests/LifeOrganizeTests.swift", 20, 20)],
                    }
                ]
            }
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("no app coverage target matched", result.stderr)

    def test_errors_on_malformed_json(self):
        result = self.run_gate(raw="{not json")

        self.assertEqual(result.returncode, 2)
        self.assertIn("Malformed xccov JSON", result.stderr)

    def test_sums_multiple_app_target_entries_and_excludes_test_targets(self):
        result = self.run_gate(
            {
                "targets": [
                    {
                        "name": "LifeOrganize",
                        "files": [file("LifeOrganize/Services/SearchService.swift", 40, 50)],
                    },
                    {
                        "name": "MergedCoverage",
                        "files": [file("LifeOrganize/Services/RecallService.swift", 40, 50)],
                    },
                    {
                        "name": "LifeOrganizeUITests.xctest",
                        "files": [file("LifeOrganizeUITests/LifeOrganizeUITests.swift", 100, 100)],
                    },
                ]
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("app coverage: 80.00% (80/100 lines)", result.stdout)
        self.assertIn("LifeOrganizeUITests.xctest: UI test bundle product", result.stdout)


if __name__ == "__main__":
    unittest.main()
