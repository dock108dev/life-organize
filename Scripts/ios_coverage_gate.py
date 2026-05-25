#!/usr/bin/env python3
"""Gate LifeOrganize app-target line coverage from an xccov JSON report."""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_XCRESULT_PATH = "BuildArtifacts/LifeOrganizeTests.xcresult"
DEFAULT_PROJECT_PATH = "LifeOrganize.xcodeproj"
DEFAULT_THRESHOLD = 0.80
APP_PRODUCT_TYPE = "com.apple.product-type.application"
TEST_PRODUCT_TYPES = {
    "com.apple.product-type.bundle.unit-test": "unit test bundle product",
    "com.apple.product-type.bundle.ui-testing": "UI test bundle product",
}

EXCLUSION_RULES = [
    ("LifeOrganize/Persistence/LifeOrganizeSchemas.swift", "historical schema snapshot"),
    ("LifeOrganize/Persistence/LifeOrganizeSchemaV1.swift", "historical schema snapshot"),
    ("LifeOrganize/Persistence/LifeOrganizeSchemaV2.swift", "historical schema snapshot"),
    ("LifeOrganize/Persistence/HeavyHistorySeedScenarioGenerator.swift", "generated-heavy fixture code"),
    ("LifeOrganize/Resources/SeedScenarios/*.json", "static fixture data"),
    ("DerivedData/**", "generated build output"),
    ("*.generated.swift", "generated Swift source"),
    ("**/*Generated*.swift", "generated Swift source"),
    ("**/*+Generated.swift", "generated Swift source"),
    ("LifeOrganize/Features/Debug/*View.swift", "UI-only diagnostics shell"),
    ("LifeOrganize/Features/Debug/*Views.swift", "UI-only diagnostics shell"),
    ("LifeOrganize/Features/Debug/DebugTextViewer.swift", "UI-only diagnostics shell"),
    ("LifeOrganize/Features/Debug/ExtractionDebugComponents.swift", "UI-only diagnostics shell"),
    ("LifeOrganize/Features/Debug/ManualExtractionRetryButton.swift", "UI-only diagnostics shell"),
    ("LifeOrganize/Features/Things/*EditView.swift", "UI-only manual edit shell"),
    ("LifeOrganize/Features/Things/ThingDeleteReassignmentView.swift", "UI-only manual edit shell"),
    ("LifeOrganize/Features/Things/ThingSelectionPicker.swift", "UI-only manual edit shell"),
]


@dataclass(frozen=True)
class ProjectTarget:
    uuid: str
    name: str
    product_name: str
    product_reference_name: str
    product_type: str
    source_roots: tuple[str, ...]


@dataclass(frozen=True)
class CoverageFile:
    path: str
    covered_lines: int
    executable_lines: int


@dataclass(frozen=True)
class FileDecision:
    path: str
    reason: str
    covered_lines: int
    executable_lines: int


def parse_args() -> argparse.Namespace:
    """Parse command-line options for local and CI coverage gates."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "xcresult",
        nargs="?",
        default=DEFAULT_XCRESULT_PATH,
        help=f"Path to an .xcresult bundle. Defaults to {DEFAULT_XCRESULT_PATH}.",
    )
    parser.add_argument(
        "--report-json",
        help="Read an existing xccov JSON report instead of invoking xcrun.",
    )
    parser.add_argument(
        "--project",
        default=DEFAULT_PROJECT_PATH,
        help=f"Path to the Xcode project. Defaults to {DEFAULT_PROJECT_PATH}.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=DEFAULT_THRESHOLD,
        help=f"Required app line coverage as a fraction. Defaults to {DEFAULT_THRESHOLD:.2f}.",
    )
    parser.add_argument(
        "--app-target",
        default=None,
        help="Expected app target name when more than one app target exists.",
    )
    return parser.parse_args()


def parse_project_targets(project_path: Path) -> list[ProjectTarget]:
    """Extract native target identity from the checked-in Xcode project."""
    pbxproj_path = project_path / "project.pbxproj"
    text = pbxproj_path.read_text(encoding="utf-8")
    file_references = {
        match.group("uuid"): match.group("name")
        for match in __import__("re").finditer(
            r"(?P<uuid>[A-Z0-9]+) /\* (?P<name>[^*]+) \*/ = \{isa = PBXFileReference;[^\n]*\};",
            text,
        )
    }
    targets: list[ProjectTarget] = []
    target_pattern = __import__("re").compile(
        r"(?P<uuid>[A-Z0-9]+) /\* (?P<comment>[^*]+) \*/ = \{\n"
        r"(?P<body>.*?)\n\t\t\};",
        __import__("re").S,
    )
    for match in target_pattern.finditer(text):
        body = match.group("body")
        if "isa = PBXNativeTarget;" not in body:
            continue
        name = scalar_value(body, "name") or match.group("comment")
        product_name = scalar_value(body, "productName") or name
        product_type = scalar_value(body, "productType") or ""
        product_reference_uuid = scalar_value(body, "productReference") or ""
        source_roots = tuple(
            root.strip()
            for root in __import__("re").findall(
                r"fileSystemSynchronizedGroups = \((.*?)\);", body, __import__("re").S
            )[0].split(",")
            if root.strip()
        )
        source_root_names = tuple(
            root.split("/*", 1)[1].split("*/", 1)[0].strip()
            for root in source_roots
            if "/*" in root
        )
        targets.append(
            ProjectTarget(
                uuid=match.group("uuid"),
                name=name,
                product_name=product_name,
                product_reference_name=file_references.get(product_reference_uuid, product_name),
                product_type=product_type.strip('"'),
                source_roots=source_root_names,
            )
        )
    return targets


def scalar_value(body: str, key: str) -> str | None:
    """Read a simple scalar assignment from an Xcode project block."""
    import re

    match = re.search(rf"\b{key} = (?P<value>[^;]+);", body)
    if not match:
        return None
    value = match.group("value").strip()
    if "/*" in value:
        value = value.split("/*", 1)[0].strip()
    return value.strip('"')


def selected_app_target(targets: list[ProjectTarget], app_target_name: str | None) -> ProjectTarget:
    """Return the single app target that defines the coverage denominator."""
    app_targets = [target for target in targets if target.product_type == APP_PRODUCT_TYPE]
    if app_target_name:
        app_targets = [target for target in app_targets if target.name == app_target_name]
    if len(app_targets) != 1:
        names = ", ".join(target.name for target in app_targets) or "none"
        raise ValueError(f"Expected exactly one app target, found: {names}")
    return app_targets[0]


def load_report(args: argparse.Namespace) -> dict[str, Any]:
    """Load xccov JSON from disk or by invoking xcrun for an xcresult bundle."""
    if args.report_json:
        raw = Path(args.report_json).read_text(encoding="utf-8")
    else:
        raw = subprocess.check_output(
            ["xcrun", "xccov", "view", "--report", "--json", args.xcresult],
            text=True,
        )
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"Malformed xccov JSON: {error}") from error
    if not isinstance(payload, dict) or not isinstance(payload.get("targets"), list):
        raise ValueError("Malformed xccov JSON: expected a top-level targets array")
    return payload


def classify_target(
    target: dict[str, Any],
    app_target: ProjectTarget,
    known_tests: dict[str, str],
    repo_root: Path,
) -> tuple[str, str]:
    """Classify an xccov target as app, excluded, or unknown."""
    name = str(target.get("name") or "")
    product_path = str(target.get("buildProductPath") or "")
    if name in {app_target.name, app_target.product_reference_name}:
        return "app", "matched app target/product"
    if name in known_tests:
        return "excluded", known_tests[name]
    if name.endswith(".xctest"):
        return "excluded", "test bundle product"
    if product_path.endswith(f"/{app_target.product_reference_name}"):
        return "app", "matched app product path"

    files = [coverage_file(file_payload, repo_root) for file_payload in target.get("files") or []]
    nonempty_paths = [file.path for file in files if file.path]
    if nonempty_paths and all(path.startswith(("LifeOrganizeTests/", "LifeOrganizeUITests/")) for path in nonempty_paths):
        return "excluded", "all files under test source roots"
    if nonempty_paths and all(path.startswith("LifeOrganize/") for path in nonempty_paths):
        return "app", "all files under app source root"
    return "unknown", "target does not match app or test target identity"


def coverage_file(file_payload: dict[str, Any], repo_root: Path) -> CoverageFile:
    """Normalize a single xccov file entry into relative coverage data."""
    raw_path = str(file_payload.get("path") or file_payload.get("name") or "")
    normalized = normalize_path(raw_path, repo_root)
    return CoverageFile(
        path=normalized,
        covered_lines=int(file_payload.get("coveredLines") or 0),
        executable_lines=int(file_payload.get("executableLines") or 0),
    )


def normalize_path(raw_path: str, repo_root: Path) -> str:
    """Return a repo-relative POSIX path when possible."""
    if not raw_path:
        return ""
    path = Path(raw_path)
    if path.is_absolute():
        try:
            return path.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            return path.as_posix()
    return Path(raw_path).as_posix().removeprefix("./")


def decide_file(file: CoverageFile, target_class: str) -> tuple[bool, str]:
    """Decide whether a coverage file contributes to the app denominator."""
    if target_class == "excluded":
        return False, "excluded coverage target"
    if not file.path:
        return False, "unresolved path"
    if file.path.startswith("LifeOrganizeTests/"):
        return False, "unit test source root"
    if file.path.startswith("LifeOrganizeUITests/"):
        return False, "UI test source root"
    if ".xctest/" in file.path:
        return False, "test bundle path"
    if not file.path.startswith("LifeOrganize/"):
        return False, "outside app source root"
    for pattern, reason in EXCLUSION_RULES:
        if fnmatch.fnmatch(file.path, pattern):
            return False, reason
    if not file.path.endswith(".swift"):
        return False, "non-Swift app file"
    if file.executable_lines == 0:
        return False, "zero executable lines"
    return True, "included app Swift source"


def percent(value: float) -> str:
    """Format a coverage ratio as a percentage."""
    return f"{value * 100:.2f}%"


def print_report(
    xcresult_path: str,
    threshold: float,
    included_targets: list[str],
    excluded_targets: list[tuple[str, str]],
    included_files: list[FileDecision],
    excluded_files: list[FileDecision],
    coverage: float,
) -> None:
    """Emit a visible coverage scope and exclusion report."""
    covered = sum(file.covered_lines for file in included_files)
    executable = sum(file.executable_lines for file in included_files)
    print("iOS Coverage Gate")
    print(f"xcresult: {xcresult_path}")
    print(f"threshold: {percent(threshold)}")
    print(f"app coverage: {percent(coverage)} ({covered}/{executable} lines)")
    print("")
    print("Included targets:")
    if included_targets:
        for name in included_targets:
            print(f"- {name}")
    else:
        print("- None")
    print("")
    print("Excluded targets:")
    if excluded_targets:
        for name, reason in excluded_targets:
            print(f"- {name}: {reason}")
    else:
        print("- None")
    print("")
    print("Excluded files:")
    if excluded_files:
        for file in excluded_files:
            print(f"- {file.path}: {file.reason} ({file.covered_lines}/{file.executable_lines})")
    else:
        print("- None")
    print("")
    print("Configured deliberate exclusions:")
    for pattern, reason in EXCLUSION_RULES:
        print(f"- {pattern}: {reason}")
    print("")
    print("Included files:")
    if included_files:
        for file in included_files:
            file_coverage = file.covered_lines / file.executable_lines
            print(f"- {file.path}: {file.covered_lines}/{file.executable_lines} ({percent(file_coverage)})")
    else:
        print("- None")


def main() -> int:
    """Run the coverage gate and return a process exit code."""
    args = parse_args()
    repo_root = Path.cwd().resolve()
    try:
        targets = parse_project_targets(repo_root / args.project)
        app_target = selected_app_target(targets, args.app_target)
        test_targets = {
            target.name: TEST_PRODUCT_TYPES.get(target.product_type, "test target")
            for target in targets
            if target.product_type in TEST_PRODUCT_TYPES
        }
        test_targets.update(
            {
                target.product_reference_name: TEST_PRODUCT_TYPES.get(target.product_type, "test target")
                for target in targets
                if target.product_type in TEST_PRODUCT_TYPES
            }
        )
        report = load_report(args)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Coverage gate error: {error}", file=sys.stderr)
        return 2

    included_targets: list[str] = []
    excluded_targets: list[tuple[str, str]] = []
    included_files: list[FileDecision] = []
    excluded_files: list[FileDecision] = []
    unknown_targets: list[tuple[str, str]] = []

    for target in report["targets"]:
        if not isinstance(target, dict):
            unknown_targets.append(("<non-object target>", "target entry is not an object"))
            continue
        target_class, target_reason = classify_target(target, app_target, test_targets, repo_root)
        target_name = str(target.get("name") or "<unnamed target>")
        if target_class == "unknown":
            unknown_targets.append((target_name, target_reason))
            continue
        if target_class == "app":
            included_targets.append(target_name)
        else:
            excluded_targets.append((target_name, target_reason))
        for file_payload in target.get("files") or []:
            if not isinstance(file_payload, dict):
                excluded_files.append(FileDecision("<non-object file>", "file entry is not an object", 0, 0))
                continue
            file = coverage_file(file_payload, repo_root)
            include, reason = decide_file(file, target_class)
            decision = FileDecision(file.path, reason, file.covered_lines, file.executable_lines)
            if include:
                included_files.append(decision)
            else:
                excluded_files.append(decision)

    if unknown_targets:
        for name, reason in unknown_targets:
            print(f"Unable to classify xccov target {name!r}: {reason}", file=sys.stderr)
        return 2
    if not included_targets:
        print("Coverage gate error: no app coverage target matched LifeOrganize", file=sys.stderr)
        return 2

    executable = sum(file.executable_lines for file in included_files)
    if executable == 0:
        print("Coverage gate error: no executable app lines found", file=sys.stderr)
        return 2
    coverage = sum(file.covered_lines for file in included_files) / executable
    print_report(
        args.xcresult,
        args.threshold,
        included_targets,
        excluded_targets,
        included_files,
        excluded_files,
        coverage,
    )
    if coverage < args.threshold:
        print(f"Coverage gate failed: {percent(coverage)} is below {percent(args.threshold)}", file=sys.stderr)
        return 1
    print(f"Coverage gate passed: {percent(coverage)} meets {percent(args.threshold)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
