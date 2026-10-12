#!/usr/bin/env bash
# Cloud-session bootstrap, run by the SessionStart hook in .claude/settings.json.
# Installs the pinned Godot 4.7 (sha512-verified) plus Xvfb/Mesa for screenshots.
# Does nothing on Emmitt's PC. Safe to run every session (skips what is already installed).
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || [ "${FORCE_CLOUD_SETUP:-}" = "1" ] || exit 0

GODOT_VERSION="4.7-stable"
ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
# From https://github.com/godotengine/godot/releases/download/4.7-stable/SHA512-SUMS.txt
SHA512="b639ca9c1ddea39bb3df89bd5283a51ca6047467abe6b25e9436566f2b2082ede633025073989ecf39c7d5d3c2493d80ea13e3af6dd5e261bbf89e462d6d2214"
DEST="$HOME/.local/godot"
BIN="$DEST/Godot_v${GODOT_VERSION}_linux.x86_64"
godot_status="ok"
shot_status="ok"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  tmp="$(mktemp -d)"
  if curl -fsSL --retry 3 -o "$tmp/$ZIP" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP}" \
    && echo "$SHA512  $tmp/$ZIP" | sha512sum -c --quiet - \
    && python3 -m zipfile -e "$tmp/$ZIP" "$tmp/x"; then
    mv "$tmp/x/Godot_v${GODOT_VERSION}_linux.x86_64" "$BIN"
    chmod +x "$BIN"
  else
    godot_status="FAILED (download or checksum; check the environment's network access allows github.com)"
  fi
  rm -rf "$tmp"
fi

if ! command -v xvfb-run >/dev/null 2>&1; then
  SUDO=""
  [ "$(id -u)" -eq 0 ] || SUDO="sudo -n"
  if ! { command -v apt-get >/dev/null 2>&1 \
    && $SUDO apt-get update -qq >/dev/null 2>&1 \
    && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libx11-6 libxcursor1 libxinerama1 \
      libxext6 libxrandr2 libxrender1 libxi6 libfontconfig1 >/dev/null 2>&1; }; then
    shot_status="unavailable (could not install xvfb/mesa; tests still work)"
  fi
fi

echo "cloud-setup: godot $GODOT_VERSION $godot_status | screenshots $shot_status | run tools/test.sh and tools/shot.sh"
