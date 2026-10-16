#!/usr/bin/env bash
# Puts a fresh portable copy on the family drive, where the other PC's launcher picks it up next time it starts:
# runs tools/make_portable.sh (main by default), then copies NoiseFloor.zip and the README into FAMILY_DIR
# (default R:/Reserve/Noise Floor) and version.txt LAST, so a launcher never sees a new version with an old zip.
# Usage: tools/publish_family.sh [git-ref]
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${FAMILY_DIR:-/r/Reserve/Noise Floor}"
bash tools/make_portable.sh "${1:-origin/main}"
mkdir -p "$dest"
cp build/NoiseFloor.zip "$dest/NoiseFloor.zip.part"
mv -f "$dest/NoiseFloor.zip.part" "$dest/NoiseFloor.zip"
sed 's/\r$//; s/$/\r/' tools/portable/README.txt > "$dest/README.txt"
cp build/version.txt "$dest/version.txt"
echo "publish_family: $dest now has $(cat "$dest/version.txt")"
