#!/usr/bin/env python3
"""Enforce the addon boundaries in docs/ARCHITECTURE_BOUNDARIES.md.

An addon is reusable only while the dependency arrow points one way: games
depend on addons, never the reverse. That rule is easy to state and easy to
break by accident -- the drift between this repo, mikeys_game_world and
mikeys_game_bones-rules-moba happened one reasonable-looking edit at a time.
Prose does not catch that. This does.

Godot resolves global `class_name` declarations and autoload singletons by
name, with no path involved. A res://-only check therefore cannot see the
most damaging kind of outward reference: an addon that names a class the
consuming game happens to define. Those are found here too, via a
project-wide symbol table.

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


# GDScript keywords and built-ins that can never be a project class_name, so
# a same-named symbol is never worth resolving. Kept small on purpose: the
# symbol table is built from real declarations, so this only guards against a
# declaration that shadows something built-in.
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"

AUTOLOAD_LINE = re.compile(rf"^({IDENT})\s*=\s*\"\*?(res://[^\"]+)\"")


class Finding:
    def __init__(self, path: Path, line_no: int, message: str) -> None:
        self.path = path
        self.line_no = line_no
        self.message = message

    def __str__(self) -> str:
        return f"{self.path}:{self.line_no}: {self.message}"

    def baseline_key(self) -> str:
        """Stable identity for the baseline: file plus symbol, never the line.

        Keying on a line number would make the baseline go stale on any edit
        above the violation, turning an unrelated change red for no reason.
        """
        return f"{self.path}:{self.message.split(',')[0].replace('references ', '')}"


def strip_comment(line: str, suffix: str) -> str:
    """Drop a GDScript comment so a path named in prose isn't a violation.

    Naive on purpose: a '#' inside a string literal truncates the line early.
    That can only ever hide a violation, never invent one, and a res:// path
    sitting after a '#' inside a string is not a case worth the parser.
    """
    if suffix != ".gd":
        return line
    return line.split("#", 1)[0]


def collect_global_symbols(repo_root: Path) -> dict[str, Path]:
    """Every global `class_name` in the project, mapped to where it is declared.

    Project-wide, not addons-only: the point is to learn which names an addon
    can reference without any res:// path appearing in its source.
    """
    symbols: dict[str, Path] = {}
    for path in sorted(repo_root.rglob("*.gd")):
        if ".godot" in path.parts or ".git" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line in text.splitlines():
            match = CLASS_NAME.match(line)
            if match:
                symbols[match.group(1)] = path.relative_to(repo_root)
                break
    return symbols


def collect_autoloads(repo_root: Path) -> dict[str, str]:
    """Autoload singletons from project.godot, mapped to their script path.

    An autoload is a global name too, and an addon calling `Rules.attack()`
    depends on the consuming project having registered that autoload just as
    surely as if it had imported a file.
    """
    autoloads: dict[str, str] = {}
    project = repo_root / "project.godot"
    if not project.is_file():
        return autoloads
    in_section = False
    for line in project.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_section = stripped == "[autoload]"
            continue
        if not in_section:
            continue
        match = AUTOLOAD_LINE.match(stripped)
        if match:
            autoloads[match.group(1)] = match.group(2)
    return autoloads


def external_symbols(repo_root: Path) -> dict[str, str]:
    """Global names an addon must NOT reference, mapped to why.

    A name is external when the thing providing it lives outside addons/ --
    a class_name declared in the game, or an autoload whose script is not in
    an addon. Referencing one inverts the dependency arrow invisibly: the
    addon will not even parse in a project that does not happen to supply it.
    """
    external: dict[str, str] = {}

    for name, decl_path in collect_global_symbols(repo_root).items():
        if decl_path.parts and decl_path.parts[0] != "addons":
            external[name] = f"class_name declared in {decl_path}"

    for name, script_path in collect_autoloads(repo_root).items():
        if not script_path.startswith("res://addons/"):
            external[name] = f"autoload registered in project.godot -> {script_path}"

    return external


def load_baseline(repo_root: Path) -> set[str]:
    """Known, accepted violations, one `path:symbol` per line.

    A baseline rather than a suppression: everything in it is a real defect
    that is expected to be paid down, and anything NOT in it fails the build.
    That keeps the check green on a repository that already has debt without
    letting the debt grow. Shrinking this file to empty is the definition of
    done.
    """
    path = repo_root / "tools" / "addon-boundaries-baseline.txt"
    if not path.is_file():
        return set()
    entries = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            entries.add(line)
    return entries


def scan_addon(
    addon_dir: Path, repo_root: Path, external: dict[str, str]
) -> tuple[list[Finding], list[Finding], dict]:
    errors: list[Finding] = []
    warnings: list[Finding] = []
    declared: dict[str, tuple[Path, int]] = {}

    # Compiled once per addon rather than per line: this runs over every
    # line of every addon file, and the alternation is the whole game
    # vocabulary the project defines outside addons/.
    symbol_re = (
        re.compile(r"\b(" + "|".join(re.escape(n) for n in sorted(external)) + r")\b")
        if external
        else None
    )

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

            # A global name provided from outside addons/. No res:// path
            # appears in the source, which is exactly why this needs its own
            # check -- and why these are the violations that survive longest.
            if symbol_re is not None and path.suffix == ".gd":
                for name in symbol_re.findall(line):
                    errors.append(
                        Finding(rel, line_no, f"references {name}, {external[name]} -- outside addons/")
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

    external = external_symbols(repo_root)
    baseline = load_baseline(repo_root)

    errors: list[Finding] = []
    warnings: list[Finding] = []
    # class_name -> [(addon, path, line)], to name both sides of a collision.
    owners: dict[str, list[tuple[str, Path, int]]] = defaultdict(list)

    for addon_dir in addon_dirs:
        addon_errors, addon_warnings, declared = scan_addon(addon_dir, repo_root, external)
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
    if external:
        print(f"Global names provided from outside addons/: {', '.join(sorted(external))}")

    # Partition against the baseline. A baselined finding is still a real
    # defect -- it is reported every run so it stays visible -- it just does
    # not fail the build the way a newly introduced one does.
    known: list[Finding] = []
    new_errors: list[Finding] = []
    seen_keys: set[str] = set()
    for finding in errors:
        key = finding.baseline_key()
        if key in baseline:
            seen_keys.add(key)
            known.append(finding)
        else:
            new_errors.append(finding)
    errors = new_errors

    if known:
        print(f"\n{len(known)} known violation(s), baselined in tools/addon-boundaries-baseline.txt:")
        for finding in known:
            print(f"  DEBT {finding}")

    # A baseline entry that no longer matches anything is debt that has been
    # paid; leaving it behind would silently re-permit the violation later.
    stale = sorted(baseline - seen_keys)
    if stale:
        print(f"\n{len(stale)} stale baseline entr(y/ies) -- fixed, so remove from the baseline:")
        for entry in stale:
            print(f"  STALE {entry}")

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

    if stale:
        print("\nFAILED (baseline lists violations that no longer exist)")
        return 1

    if warnings and args.strict:
        print("\nFAILED (--strict: warnings are errors)")
        print("See docs/ARCHITECTURE_BOUNDARIES.md")
        return 1

    print("\nAll addon boundaries hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
