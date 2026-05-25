#!/usr/bin/env python3
"""
Update or append one Caddy site block inside an existing Caddyfile.

Usage:
  python3 update_caddy_site_block.py <source_caddyfile> <target_caddyfile> <site_header>
"""

from __future__ import annotations

import pathlib
import re
import sys


def _site_header_pattern(header: str) -> re.Pattern[str]:
    return re.compile(rf"(?m)^[ \t]*{re.escape(header)}[ \t]*\{{[ \t]*(?:#.*)?$")


def _header_without_brace_pattern(header: str) -> re.Pattern[str]:
    return re.compile(rf"(?m)^[ \t]*{re.escape(header)}[ \t]*(?:#.*)?$")


def _matching_site_blocks(content: str, header: str) -> list[re.Match[str]]:
    return list(_site_header_pattern(header).finditer(content))


def _find_block_end(content: str, open_brace: int, malformed_message: str) -> int:
    depth = 0
    for index in range(open_brace, len(content)):
        char = content[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    raise RuntimeError(malformed_message)


def extract_site_block(content: str, header: str) -> str:
    """Extract a standalone Caddy site block for the exact header."""
    matches = _matching_site_blocks(content, header)
    if not matches:
        if _header_without_brace_pattern(header).search(content):
            raise RuntimeError("Could not find opening brace for source site block")
        raise RuntimeError(f"Could not find site header '{header}' in source Caddyfile")
    if len(matches) > 1:
        raise RuntimeError(f"Found multiple site blocks for '{header}' in source Caddyfile")

    match = matches[0]
    open_brace = match.start() + match.group(0).index("{")
    close_brace = _find_block_end(
        content,
        open_brace,
        "Could not find closing brace for source site block",
    )
    return content[match.start() : close_brace + 1].strip() + "\n"


def replace_or_append_site_block(content: str, header: str, new_block: str) -> str:
    """Replace a standalone Caddy site block, or append it when absent."""
    matches = _matching_site_blocks(content, header)
    if not matches:
        if _header_without_brace_pattern(header).search(content):
            raise RuntimeError("Malformed target Caddyfile: site header found without opening brace")
        return content.rstrip() + "\n\n" + new_block
    if len(matches) > 1:
        raise RuntimeError(f"Malformed target Caddyfile: multiple site blocks for '{header}'")

    match = matches[0]
    open_brace = match.start() + match.group(0).index("{")
    close_brace = _find_block_end(
        content,
        open_brace,
        "Malformed target Caddyfile: unmatched braces in site block",
    )
    return content[: match.start()] + new_block + content[close_brace + 1 :]


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "Usage: python3 update_caddy_site_block.py <source_caddyfile> "
            "<target_caddyfile> <site_header>",
            file=sys.stderr,
        )
        return 2

    source_path = pathlib.Path(sys.argv[1])
    target_path = pathlib.Path(sys.argv[2])
    site_header = sys.argv[3]

    new_block = extract_site_block(source_path.read_text(), site_header)
    updated = replace_or_append_site_block(target_path.read_text(), site_header, new_block)

    target_path.write_text(updated)
    print(f"Updated site block '{site_header}' in {target_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
