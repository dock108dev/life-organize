#!/usr/bin/env python3
"""Static guardrails for adaptive iOS layout contracts."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


SOURCE_ROOTS = ("LifeOrganize", "LifeOrganizeTests", "LifeOrganizeUITests")
SKIP_PATH_PARTS = {".build", "BuildArtifacts", "DerivedData", ".swiftpm"}
SKIP_FILE_SUFFIXES = (".generated.swift",)

SUSPICIOUS_WIDTH_MIN = 300
SUSPICIOUS_WIDTH_MAX = 1400
SUSPICIOUS_HEIGHT_MIN = 500
SUSPICIOUS_HEIGHT_MAX = 1600

REQUIRED_SCREENSHOT_BASELINES = (
    ("iPhone_17_Pro", "portrait", "light"),
    ("iPhone_17_Pro", "landscape", "light"),
    ("iPad_Pro_13-inch_M5", "portrait", "light"),
    ("iPad_Pro_13-inch_M5", "landscape", "light"),
)
REQUIRED_SCREENSHOT_SCENARIOS = (
    "first_launch",
    "timeline_empty",
    "timeline",
    "things",
    "thing_detail",
    "carry_forward",
    "search",
    "review_queue",
    "heavy_timeline",
)

ALLOW_PATTERN = re.compile(
    r'layout-guard:\s*allow\s+(UIScreen|UIDevice|fixed-size)\s+reason="[^"]{12,}"'
)
BROAD_ALLOW_PATTERN = re.compile(r"layout-guard:\s*allow\b")

DEVICE_PATTERNS = (
    (
        "UIScreen",
        re.compile(
            r"UIScreen\s*\.\s*(main|screens)\b|UIScreen\s*\([^)]*\)|"
            r"\.nativeBounds\b|\.nativeScale\b|"
            r"UIScreen\s*\.\s*main\s*\.\s*(bounds|frame)\b|"
            r"UIScreen\s*\.\s*main\s*\.\s*(bounds|frame)\s*\.\s*(width|height)\b"
        ),
        "avoid UIScreen-driven layout; use container geometry, size classes, or adaptive SwiftUI layout instead",
    ),
    (
        "UIDevice",
        re.compile(
            r"UIDevice\s*\.\s*current\b|UIDeviceOrientation\b|UIUserInterfaceIdiom\b|"
            r"\.userInterfaceIdiom\b|XCUIDevice\s*\.\s*shared\s*\.\s*orientation\b"
        ),
        "avoid UIDevice layout branching; prefer responsive layout from available container space",
    ),
)

WIDTH_PATTERNS = (
    re.compile(r"\.frame\s*\([^)]*\b(?:width|maxWidth|minWidth)\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
    re.compile(r"CGRect\s*\([^)]*\bwidth\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
    re.compile(r"CGSize\s*\([^)]*\bwidth\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
)
HEIGHT_PATTERNS = (
    re.compile(r"\.frame\s*\([^)]*\b(?:height|maxHeight)\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
    re.compile(r"CGRect\s*\([^)]*\bheight\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
    re.compile(r"CGSize\s*\([^)]*\bheight\s*:\s*([0-9]+(?:\.[0-9]+)?)\b"),
)


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    message: str

    def format(self, root: Path) -> str:
        return f"{self.path.relative_to(root)}:{self.line}: {self.message}"


def swift_files(root: Path) -> list[Path]:
    """Return Swift files in the configured source roots."""
    files: list[Path] = []
    for source_root in SOURCE_ROOTS:
        directory = root / source_root
        if not directory.exists():
            continue
        for path in directory.rglob("*.swift"):
            relative_parts = set(path.relative_to(root).parts)
            if relative_parts & SKIP_PATH_PARTS:
                continue
            if path.name.endswith(SKIP_FILE_SUFFIXES):
                continue
            files.append(path)
    return sorted(files)


def has_allow(lines: list[str], index: int, kind: str) -> bool:
    """Check for a narrow allow reason on the same line or nearby previous lines."""
    start = max(0, index - 2)
    for candidate in lines[start : index + 1]:
        match = ALLOW_PATTERN.search(candidate)
        if match and match.group(1) == kind:
            return True
    return False


def invalid_allow_finding(path: Path, line_number: int, line: str) -> Finding | None:
    """Return a finding for broad or malformed layout guard allow comments."""
    if BROAD_ALLOW_PATTERN.search(line) and not ALLOW_PATTERN.search(line):
        return Finding(
            path,
            line_number,
            'layout guard allow comments must be narrow and include reason="..." with at least 12 characters',
        )
    return None


def scan_file(path: Path) -> list[Finding]:
    """Scan one Swift file for layout guardrail violations."""
    lines = path.read_text(encoding="utf-8").splitlines()
    findings: list[Finding] = []

    for index, line in enumerate(lines):
        line_number = index + 1
        invalid_allow = invalid_allow_finding(path, line_number, line)
        if invalid_allow is not None:
            findings.append(invalid_allow)

        for kind, pattern, message in DEVICE_PATTERNS:
            if pattern.search(line) and not has_allow(lines, index, kind):
                findings.append(Finding(path, line_number, message))

        if not has_allow(lines, index, "fixed-size"):
            findings.extend(scan_fixed_sizes(path, line_number, line))

    return findings


def scan_fixed_sizes(path: Path, line_number: int, line: str) -> list[Finding]:
    """Return findings for screen-like fixed dimensions."""
    findings: list[Finding] = []
    for pattern in WIDTH_PATTERNS:
        for match in pattern.finditer(line):
            width = float(match.group(1))
            if SUSPICIOUS_WIDTH_MIN <= width <= SUSPICIOUS_WIDTH_MAX:
                findings.append(
                    Finding(
                        path,
                        line_number,
                        f"avoid screen-like fixed width {width:g}; use adaptive container constraints or add a narrow layout-guard reason",
                    )
                )
    for pattern in HEIGHT_PATTERNS:
        for match in pattern.finditer(line):
            height = float(match.group(1))
            if SUSPICIOUS_HEIGHT_MIN <= height <= SUSPICIOUS_HEIGHT_MAX:
                findings.append(
                    Finding(
                        path,
                        line_number,
                        f"avoid screen-like fixed height {height:g}; use adaptive container constraints or add a narrow layout-guard reason",
                    )
                )
    return findings


def verify_screenshot_baselines(root: Path) -> list[Finding]:
    """Verify every required screenshot matrix cell contains stable scenario PNGs."""
    findings: list[Finding] = []
    base = root / "Tests" / "ScreenshotBaselines"
    for device, orientation, appearance in REQUIRED_SCREENSHOT_BASELINES:
        directory = base / device / orientation / appearance
        for scenario in REQUIRED_SCREENSHOT_SCENARIOS:
            path = directory / f"{scenario}.png"
            if not path.is_file():
                findings.append(
                    Finding(
                        path,
                        1,
                        f"missing screenshot baseline: device={device} orientation={orientation} appearance={appearance} scenario={scenario}",
                    )
                )
    return findings


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    findings: list[Finding] = []

    for path in swift_files(root):
        findings.extend(scan_file(path))
    findings.extend(verify_screenshot_baselines(root))

    if findings:
        print("iOS static layout guard failed:", file=sys.stderr)
        for finding in findings:
            print(finding.format(root), file=sys.stderr)
        return 1

    print("iOS static layout guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
