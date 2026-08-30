#!/usr/bin/env bash
# Smoke-tests the project: everything parses, and the default scene boots
# without script/runtime errors. Not a behavior test — nothing here asserts
# in-game outcomes (e.g. that an attack actually deals damage).
set -euo pipefail
cd "$(dirname "$0")/.."

# Addon boundaries first: it needs no Godot, so it still runs (and still
# fails) in an environment where the checks below cannot. find_godot exits
# outright when Godot is missing, so anything after it is Godot-gated.
echo "=== Addon boundaries ==="
"$(dirname "$0")/check-addon-boundaries.py"
echo

find_godot() {
	for candidate in godot4 godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			echo "$candidate"
			return
		fi
	done
	if [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
		echo "/Applications/Godot.app/Contents/MacOS/Godot"
		return
	fi
	echo "Godot 4 executable not found. Set GODOT_BIN or install Godot." >&2
	exit 1
}

GODOT_BIN="${GODOT_BIN:-$(find_godot)}"

# Godot logs these on every abrupt --quit-after shutdown (an in-flight
# resource/ObjectDB not yet freed); they aren't project bugs.
BENIGN_PATTERN='ObjectDB instances were leaked at exit|at: cleanup \(core/object/object\.cpp|resources still in use at exit|at: clear \(core/io/resource\.cpp'

fail=0

run_check() {
	local label="$1"
	shift
	echo "=== $label ==="
	local output
	output=$("$@" 2>&1) || true
	local errors
	errors=$(printf '%s\n' "$output" | grep -iE "error" | grep -vE "$BENIGN_PATTERN" || true)
	if [ -n "$errors" ]; then
		printf '%s\n' "$errors"
		fail=1
	else
		echo "ok"
	fi
}

# Force a fresh rescan so global class_name resolution isn't hidden by a
# stale cache from before a file move/rename.
rm -f .godot/global_script_class_cache.cfg

run_check "Project rescan (script parse + global classes)" \
	"$GODOT_BIN" --headless --editor --quit --path .

run_check "Main scene boot (demo/demo_room.tscn)" \
	"$GODOT_BIN" --headless --path . --quit-after 20

run_check "demo_room_2d.tscn (2D presentation proof, booted directly)" \
	"$GODOT_BIN" --headless --path . res://demo/scenes/world/demo_room_2d.tscn --quit-after 10

echo
if [ "$fail" -ne 0 ]; then
	echo "FAILED"
	exit 1
fi
echo "All checks passed."
