#!/usr/bin/env bash
set -euo pipefail

RESULT_BUNDLE="${1:-BuildArtifacts/ScreenshotTests.xcresult}"
OUTPUT_DIR="${2:-BuildArtifacts/screenshots/actual/iPhone_16/light}"
RAW_DIR="$OUTPUT_DIR/raw"

if [[ ! -d "$RESULT_BUNDLE" ]]; then
  echo "Result bundle not found: $RESULT_BUNDLE" >&2
  exit 2
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$RAW_DIR"

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$RAW_DIR"

python3 - "$RAW_DIR" "$OUTPUT_DIR" <<'PY'
import json
import os
import re
import shutil
import sys
from pathlib import Path

raw_dir = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
manifest_path = raw_dir / "manifest.json"
prefix = "screenshot__"


def normalize(name):
    if not name.startswith(prefix):
        return None
    normalized = name[len(prefix):]
    normalized = re.sub(r"_[0-9]+_[0-9A-Fa-f-]{36}(?=\.png$)", "", normalized)
    if normalized.lower().endswith(".png"):
        return normalized
    return f"{normalized}.png"


def candidate_files():
    for path in raw_dir.rglob("*.png"):
        name = normalize(path.name)
        if name:
            yield path, name


def manifest_entries(value):
    if isinstance(value, dict):
        strings = {key: val for key, val in value.items() if isinstance(val, str)}
        names = [
            strings.get("name"),
            strings.get("displayName"),
            strings.get("attachmentName"),
            strings.get("filename"),
            strings.get("fileName"),
            strings.get("suggestedHumanReadableName"),
        ]
        paths = [
            strings.get("filename"),
            strings.get("fileName"),
            strings.get("path"),
            strings.get("relativePath"),
            strings.get("exportedFilePath"),
            strings.get("exportedFileName"),
        ]
        for display_name in names:
            if not display_name:
                continue
            normalized = normalize(Path(display_name).name)
            if not normalized:
                continue
            for raw_path in paths:
                if not raw_path:
                    continue
                path = raw_dir / raw_path
                if path.is_file():
                    yield path, normalized
                    return
                matches = list(raw_dir.rglob(Path(raw_path).name))
                if matches:
                    yield matches[0], normalized
                    return
        for item in value.values():
            yield from manifest_entries(item)
    elif isinstance(value, list):
        for item in value:
            yield from manifest_entries(item)


copied = {}
for source, name in candidate_files():
    destination = output_dir / name
    shutil.copyfile(source, destination)
    copied[name] = source

if manifest_path.is_file():
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    for source, name in manifest_entries(manifest):
        destination = output_dir / name
        shutil.copyfile(source, destination)
        copied[name] = source

if not copied:
    print("No screenshot__ PNG attachments were exported.", file=sys.stderr)
    if manifest_path.is_file():
        print(f"Attachment manifest: {manifest_path}", file=sys.stderr)
    sys.exit(1)

for name in sorted(copied):
    print(name)
PY

rm -rf "$RAW_DIR"
