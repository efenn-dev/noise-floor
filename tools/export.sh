#!/usr/bin/env bash
# Builds the Windows download: build/NoiseFloor-windows.zip (NoiseFloor.exe plus a README; unzip and double-click).
# Needs the Godot 4.7 Windows export templates in ~/.local/share/godot/export_templates/4.7.stable/
# (on Windows: Godot's Editor > Manage Export Templates). Settings live in export_presets.cfg.
set -euo pipefail
cd "$(dirname "$0")/.."
git log -1 --format="%h %s" > version.txt  # shown on the title screen, so testers can say which build they played
rm -rf build/NoiseFloor build/NoiseFloor-windows.zip
mkdir -p build/NoiseFloor
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
bash tools/godot.sh --headless --path . --export-release "Windows" build/NoiseFloor/NoiseFloor.exe 2>&1 | grep -E "ERROR|error" || true
test -s build/NoiseFloor/NoiseFloor.exe || { echo "export.sh: no NoiseFloor.exe was made" >&2; exit 1; }
cp docs/PLAYING.txt build/NoiseFloor/README.txt
(cd build && python3 -c "import shutil; shutil.make_archive('NoiseFloor-windows', 'zip', '.', 'NoiseFloor')")
echo "export.sh: build/NoiseFloor-windows.zip ($(du -h build/NoiseFloor-windows.zip | cut -f1)), $(cat version.txt)"
