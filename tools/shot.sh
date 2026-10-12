#!/usr/bin/env bash
# Captures one frame of the game to .shots/<name>.png so Claude can look at it (Read the PNG).
# Usage: tools/shot.sh [name] [game flags...]     e.g.  tools/shot.sh night --time=22
# Cloud (no GPU): runs under Xvfb with the Compatibility renderer on Mesa software GL - flatter
# lighting than Forward+ on Emmitt's GPU, so judge layout and legibility, not final looks.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-shot}"
shift || true
mkdir -p .shots
out="$PWD/.shots/$name.png"
if command -v cygpath >/dev/null 2>&1; then out="$(cygpath -m "$out")"; fi
if [ "$(uname -s)" = "Linux" ]; then
  command -v xvfb-run >/dev/null 2>&1 || { echo "shot.sh: xvfb-run missing - run tools/cloud-setup.sh" >&2; exit 1; }
  xvfb-run -a -s "-screen 0 1600x900x24" bash tools/godot.sh --path . \
    --rendering-method gl_compatibility --rendering-driver opengl3 \
    --quit-after 900 -- --screenshot="$out" "$@"
else
  bash tools/godot.sh --path . --quit-after 900 -- --screenshot="$out" "$@"
fi
[ -f "$out" ] && echo "shot.sh: saved $out" || { echo "shot.sh: no image produced" >&2; exit 1; }
