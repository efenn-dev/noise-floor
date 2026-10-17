#!/usr/bin/env bash
# Makes a standalone copy of Noise Floor for another Windows PC (one with no git or GitHub account, like the
# family's other computer): build/NoiseFloor/ gets the game files at a git ref (git archive: tracked files only,
# main by default), already imported so the first start is quick, the pinned Godot, "Play Noise Floor.bat"
# (tools/portable/play.bat) and a README, plus a copy of this PC's saved games (save.json and the save slots;
# the launcher brings them across only on a PC with none), plus update.ps1 and update_from.txt (the launcher
# updates itself from the family drive). Then zips it to build/NoiseFloor.zip and writes build/version.txt.
# Usage: tools/make_portable.sh [git-ref]   (e.g. origin/main after a merge; GODOT_DIR overrides Godot's folder)
set -euo pipefail
cd "$(dirname "$0")/.."
ref="${1:-origin/main}"
godot_dir="${GODOT_DIR:-/c/projects/Godot_v4.7-stable_win64.exe}"
out="build/NoiseFloor"
rm -rf "$out" build/NoiseFloor.zip
mkdir -p "$out/game" "$out/godot" "$out/saves"
git archive "$ref" | tar -x -C "$out/game"
printf '%s (portable copy)\n' "$(git log -1 --format='%h %s' "$ref")" > "$out/game/version.txt"
cp "$godot_dir/Godot_v4.7-stable_win64.exe" "$out/godot/"
echo "make_portable: importing (a minute or so)..."
"$godot_dir/Godot_v4.7-stable_win64_console.exe" --headless --path "$out/game" --import >/dev/null 2>&1 || true
user_dir="${APPDATA:-}/Godot/app_userdata/Noise Floor"
[ -f "$user_dir/save.json" ] && cp "$user_dir/save.json" "$out/saves/"
[ -d "$user_dir/saves" ] && cp -r "$user_dir/saves" "$out/saves/"
# Windows line endings for the launcher (cmd needs them) and the README (for Notepad).
sed 's/\r$//; s/$/\r/' tools/portable/play.bat > "$out/Play Noise Floor.bat"
sed 's/\r$//; s/$/\r/' tools/portable/README.txt > "$out/README.txt"
sed 's/\r$//; s/$/\r/' tools/portable/update_from.txt > "$out/update_from.txt"  # where the launcher looks for updates
sed 's/\r$//; s/$/\r/' tools/portable/update.ps1 > "$out/update.ps1"
# P9: the launcher's password for the family's private CDN folder; kept outside git (~/.noisefloor/family_cdn.txt).
cred="${FAMILY_CDN_CREDENTIALS:-$HOME/.noisefloor/family_cdn.txt}"
if [ -f "$cred" ]; then cp "$cred" "$out/family_cdn.txt"; else echo "make_portable: no $cred, so this copy can't update from the CDN" >&2; fi
python - "$out" build/NoiseFloor.zip <<'PY'
import sys, zipfile
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for f in sorted(src.rglob("*")):
        if f.is_file():
            z.write(f, Path("NoiseFloor") / f.relative_to(src))
PY
cp "$out/game/version.txt" build/version.txt  # published next to the zip: the launcher compares it with its own
echo "make_portable: $(du -sh build/NoiseFloor.zip | cut -f1) build/NoiseFloor.zip ($(cat "$out/game/version.txt"))"
