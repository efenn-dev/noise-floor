#!/usr/bin/env bash
# Headless test loop: refresh the class cache, run every test/test_*.gd, fail on any failed check or script error.
set -uo pipefail
cd "$(dirname "$0")/.."
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
log="$(mktemp)"
bash tools/godot.sh --headless --path . --script res://test/run_tests.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "test.sh: script errors above - counting as a failure" >&2
  status=1
fi
rm -f "$log"
exit "$status"
