#!/usr/bin/env bash
# Headless stress test (numbers only): one game-day of the sim with the town, 50 machines and 200 zombies,
# plus an empty-map run and a 20-zombie run. Prints a markdown table; non-zero on any SCRIPT ERROR.
# Not part of tools/test.sh. On Emmitt's PC: one heavy job at a time.
set -uo pipefail
cd "$(dirname "$0")/.."
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
log="$(mktemp)"
bash tools/godot.sh --headless --path . --script res://test/stress/stress_sim.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|ERROR: stress" "$log"; then
  echo "stress.sh: errors above - counting as a failure" >&2
  status=1
fi
rm -f "$log"
exit "$status"
