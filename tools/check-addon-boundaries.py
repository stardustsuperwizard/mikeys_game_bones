#!/usr/bin/env python3
"""Enforce the addon boundaries in docs/ARCHITECTURE_BOUNDARIES.md.

An addon is reusable only while the dependency arrow points one way: games
depend on addons, never the reverse. That rule is easy to state and easy to
break by accident -- the drift between this repo, mikeys_game_world and
mikeys_game_bones-rules-moba happened one reasonable-looking edit at a time.
Prose does not catch that. This does.

Runs without Godot, so it works in CI and in a fresh checkout.

    tools/check-addon-boundaries.py            errors fail, warnings inform
    tools/check-addon-boundaries.py --strict   warnings fail too

Exit 0 = clean, 1 = violations, 2 = could not run.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

# Files whose contents are code or data. Markdown is deliberately excluded:
# an addon README quoting a forbidden path while explaining the rule is not a
# violation, and treating it as one trains people to ignore this script.
SCANNED_SUFFIXES = {".gd", ".tres", ".tscn", ".json", ".cfg"}

# An addon may reference res://addons/ (a sibling addon it declares a
# dependency on) and nothing else. res://scripts/, res://scenes/,
# res://resources/, res://demo/ and friends are all the game reaching back in.
ALLOWED_RES_PREFIX = "res://addons/"

RES_REF = re.compile(r"res://[A-Za-z0-9_./-]*")
CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)")

# Input actions named as string literals rather than taken from an export.
# Godot raises "Request for nonexistent InputMap action" on every event for an
# action the host project never defined, so a hardcoded name is a hard failure
# in any project that doesn't happen to share this one's input map.
INPUT_ACTION = re.compile(
    r"\b(?:is_action_pressed|is_action_released|is_action_just_pressed"
    r"|is_action_just_released|get_action_strength|get_axis|get_vector)\(\s*\""
)


class Finding:
    def __init__(self, path: Path, line_no: int, message: str) -> None:
        self.path = path
        self.line_no = line_no
        self.message = message

    def __str__(self) -> str:
        return f"{self.path}:{self.line_no}: {self.message}"


def strip_comment(line: str, suffix: str) -> str:
    """Drop a GDScript comment so a path named in prose isn't a violation.

    Naive on purpose: a '#' inside a string literal truncates the line early.
    That can only ever hide a violation, never invent one, and a res:// path
    sitting after a '#' inside a string is not a case worth the parser.
    """
    if suffix != ".gd":
        return line
    return line.split("#", 1)[0]


def scan_addon(addon_dir: Path, repo_root: Path) -> tuple[list[Finding], list[Finding], dict]:
    errors: list[Finding] = []
    warnings: list[Finding] = []
    declared: dict[str, tuple[Path, int]] = {}

    for path in sorted(addon_dir.rglob("*")):
        if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
            continue
        rel = path.relative_to(repo_root)
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            errors.append(Finding(rel, 0, f"could not read: {exc}"))
            continue

        for line_no, raw in enumerate(text.splitlines(), start=1):
            line = strip_comment(raw, path.suffix)

            for ref in RES_REF.findall(line):
                if not ref.startswith(ALLOWED_RES_PREFIX):
                    errors.append(
                        Finding(rel, line_no, f"outward reference to {ref} -- addons may only reference {ALLOWED_RES_PREFIX}")
                    )

            match = CLASS_NAME.match(line)
            if match:
                declared[match.group(1)] = (rel, line_no)

            if INPUT_ACTION.search(line):
                warnings.append(
                    Finding(rel, line_no, "input action named as a string literal -- export the action name and guard it with InputMap.has_action()")
                )

    return errors, warnings, declared


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="treat warnings as failures")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    addons_root = repo_root / "addons"
    if not addons_root.is_dir():
        print(f"no addons/ directory at {addons_root}", file=sys.stderr)
        return 2

    addon_dirs = sorted(d for d in addons_root.iterdir() if d.is_dir() and not d.name.startswith("."))
    if not addon_dirs:
        print(f"no addons found under {addons_root}", file=sys.stderr)
        return 2

    errors: list[Finding] = []
    warnings: list[Finding] = []
    # class_name -> [(addon, path, line)], to name both sides of a collision.
    owners: dict[str, list[tuple[str, Path, int]]] = defaultdict(list)

    for addon_dir in addon_dirs:
        addon_errors, addon_warnings, declared = scan_addon(addon_dir, repo_root)
        errors.extend(addon_errors)
        warnings.extend(addon_warnings)
        for name, (path, line_no) in declared.items():
            owners[name].append((addon_dir.name, path, line_no))

    # Godot's class_name registry is one flat namespace shared with every
    # installed addon. Two declarations of the same name is a project-load
    # error, not a warning -- and the ones that bite are collisions with
    # third-party addons, which is why generic names are the risk.
    for name, sites in sorted(owners.items()):
        if len(sites) > 1:
            where = ", ".join(f"{p}:{ln}" for _, p, ln in sites)
            errors.append(Finding(Path("addons"), 0, f"class_name {name} declared {len(sites)} times ({where})"))

    print(f"Checked {len(addon_dirs)} addon(s): {', '.join(d.name for d in addon_dirs)}")

    if warnings:
        print(f"\n{len(warnings)} warning(s):")
        for finding in warnings:
            print(f"  WARN {finding}")

    if errors:
        print(f"\n{len(errors)} error(s):")
        for finding in errors:
            print(f"  FAIL {finding}")
        print("\nSee docs/ARCHITECTURE_BOUNDARIES.md")
        return 1

    if warnings and args.strict:
        print("\nFAILED (--strict: warnings are errors)")
        print("See docs/ARCHITECTURE_BOUNDARIES.md")
        return 1

    print("\nAll addon boundaries hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
