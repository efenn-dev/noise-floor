#!/usr/bin/env bash
# Q1 integration soak: a bot plays scripted game days through the real game scene (main.tscn), headless,
# with --fixed-fps 60 so it runs faster than real time. One line per game-hour, invariants checked every
# hour, then "SOAK OK" or "SOAK FAILED: <why>". Usage: tools/soak.sh [--days=N]   (default 1; 3 = all steps)
# Not part of tools/test.sh. On Emmitt's PC: one heavy job at a time.
set -uo pipefail
cd "$(dirname "$0")/.."
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
log="$(mktemp)"
start=$(date +%s)
bash tools/godot.sh --headless --fixed-fps 60 --path . --script res://test/stress/soak.gd -- "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "soak.sh: script errors above - counting as a failure" >&2
  status=1
fi
if ! grep -q "^SOAK OK" "$log"; then
  status=1
fi
echo "soak.sh: $(( $(date +%s) - start )) s wall time, exit $status"
rm -f "$log"
exit "$status"
