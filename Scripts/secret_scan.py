#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str


RULES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("private_key", re.compile(r"BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY")),
    ("openai_key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}")),
    (
        "nonempty_secret_assignment",
        re.compile(
            r"^\s*(?:OPENAI_API_KEY|LIFE_ORGANIZE_ADMIN_API_KEY|DEVICE_TOKEN_SIGNING_SECRET)"
            r"\s*=\s*(?!\s*$)(?!<[^>]+>\s*$)(?!sk-\.\.\.\s*$)(?!dev-secret\s*$)"
            r"(?!dev-admin\s*$)(?!test-[A-Za-z0-9_-]+\s*$).+"
        ),
    ),
)

SKIPPED_PATH_PARTS = {
    ".git",
    ".venv",
    ".build",
    ".derivedData",
    ".deriveddata",
    "BuildArtifacts",
    "ScreenshotBaselines",
}

SKIPPED_SUFFIXES = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".pdf",
    ".xcresult",
}

ALLOWLIST: set[tuple[str, str]] = {
    ("LifeOrganizeTests/LocalJSONExportSecretGuardrailTests.swift", "openai_key"),
    ("Backend/tests/test_admin_routes.py", "openai_key"),
    ("docs/backend.md", "openai_key"),
    ("Backend/tests/test_auth_config.py", "nonempty_secret_assignment"),
    ("docs/backend.md", "nonempty_secret_assignment"),
}


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        text=True,
        capture_output=True,
        check=True,
    )
    return [Path(line) for line in result.stdout.splitlines() if line]


def should_skip(path: Path) -> bool:
    return bool(SKIPPED_PATH_PARTS.intersection(path.parts)) or path.suffix in SKIPPED_SUFFIXES


def scan_file(path: Path) -> list[Finding]:
    if not path.exists():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return [Finding(path.as_posix(), 0, "unreadable_tracked_file")]

    findings: list[Finding] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for rule_name, pattern in RULES:
            if (path.as_posix(), rule_name) in ALLOWLIST:
                continue
            if pattern.search(line):
                findings.append(Finding(path.as_posix(), line_number, rule_name))
    return findings


def main() -> int:
    findings = [
        finding
        for path in tracked_files()
        if not should_skip(path)
        for finding in scan_file(path)
    ]
    if not findings:
        print("Secret scan passed.")
        return 0

    print("Potential committed secrets found:", file=sys.stderr)
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
