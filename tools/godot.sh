#!/usr/bin/env bash
# Runs the pinned Godot 4.7 binary: Linux in cloud sessions, the _console build on Emmitt's Windows PC.
# Override with GODOT_BIN=/path/to/godot.
set -euo pipefail
if [ -n "${GODOT_BIN:-}" ]; then exec "$GODOT_BIN" "$@"; fi
for candidate in \
  "$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64" \
  "/c/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"; do
  if [ -x "$candidate" ]; then exec "$candidate" "$@"; fi
done
echo "godot.sh: Godot 4.7 not found. Cloud: bash tools/cloud-setup.sh (FORCE_CLOUD_SETUP=1). Windows: set GODOT_BIN." >&2
exit 127
