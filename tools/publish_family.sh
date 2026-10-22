#!/usr/bin/env bash
# Puts a fresh portable copy on the family drive, where the other PC's launcher picks it up next time it starts:
# runs tools/make_portable.sh (main by default), then copies NoiseFloor.zip and the README into FAMILY_DIR
# (default R:/Reserve/Noise Floor) and version.txt LAST, so a launcher never sees a new version with an old zip.
# P9: then the same copy goes to the family's private CDN folder (https://cdn.agencyedge.io/noisefloor/, password in
# ~/.noisefloor/family_cdn.txt), so the other PC updates even when this one is off. Both version.txt files carry the
# zip's SHA-256 on a second line ("sha256 <hex>"); the launcher checks a download against it. Uploads go through the
# restricted cdnpublish account; NO_CDN=1 skips them, CDN_HOST / CDN_KEY / CDN_DIR override.
# Usage: tools/publish_family.sh [git-ref]
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${FAMILY_DIR:-/r/Reserve/Noise Floor}"
bash tools/make_portable.sh "${1:-origin/main}"
mkdir -p "$dest"
cp build/NoiseFloor.zip "$dest/NoiseFloor.zip.part"
mv -f "$dest/NoiseFloor.zip.part" "$dest/NoiseFloor.zip"
sed 's/\r$//; s/$/\r/' tools/portable/README.txt > "$dest/README.txt"
{ head -n 1 build/version.txt; echo "sha256 $(sha256sum build/NoiseFloor.zip | cut -d' ' -f1)"; } > build/version_published.txt
cp build/version_published.txt "$dest/version.txt"
echo "publish_family: $dest now has $(head -n 1 "$dest/version.txt")"
if [ "${NO_CDN:-}" != "1" ]; then
  host="${CDN_HOST:?set CDN_HOST=user@host (the family CDN box)}"
  key="${CDN_KEY:-$HOME/.ssh/cliplabpro-cdn-publish.ed25519}"
  dir="${CDN_DIR:-/var/www/noisefloor}"
  ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15 -i "$key")
  sed 's/\r$//; s/$/\r/' tools/portable/README.txt > build/README_published.txt
  scp -q "${ssh_opts[@]}" build/NoiseFloor.zip "$host:$dir/NoiseFloor.zip.part"
  scp -q "${ssh_opts[@]}" build/version_published.txt "$host:$dir/version.txt.part"
  scp -q "${ssh_opts[@]}" build/README_published.txt "$host:$dir/README.txt"
  # The zip first, version.txt last, each renamed into place, so a launcher never sees a new version with an old zip.
  ssh "${ssh_opts[@]}" "$host" "mv -f '$dir/NoiseFloor.zip.part' '$dir/NoiseFloor.zip' && mv -f '$dir/version.txt.part' '$dir/version.txt'"
  echo "publish_family: https://cdn.agencyedge.io/noisefloor/ now has $(head -n 1 build/version_published.txt)"
fi
