#!/usr/bin/env bash
# F4 part 2: the factory-against-loot budget (numbers only): loads the real game headless, adds up the world's
# expected loot for the parts the defense burns, and works out one night's draw of a reference defended base
# from the data. Prints a markdown report; non-zero on any SCRIPT ERROR. Not part of tools/test.sh.
# On Emmitt's PC: one heavy job at a time.
set -uo pipefail
cd "$(dirname "$0")/.."
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
log="$(mktemp)"
bash tools/godot.sh --headless --path . --script res://test/stress/balance.gd 2>&1 | grep -v "^Godot Engine" | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "balance.sh: script errors above - counting as a failure" >&2
  status=1
fi
rm -f "$log"
exit "$status"
