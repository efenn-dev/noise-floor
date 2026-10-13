#!/usr/bin/env bash
# Q1 screenshot tour: twelve fixed shots with existing game flags into .shots/tour/, one Godot run at a
# time (never two at once), then one 4x3 contact sheet .shots/tour/contact.png (tools/contact_sheet.py,
# needs Python with Pillow). Look at the sheet (and any tile) afterwards. Usage: tools/tour.sh
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p .shots/tour
bash tools/godot.sh --headless --path . --import >/dev/null 2>&1 || true
# name | label | flags
shots=(
  "01_street_0800|Street 08:00 from spawn|--time=8"
  "02_street_2200|Street 22:00, flashlight|--time=22 --flashlight"
  "03_kitchen|House 0 kitchen|--inside=0,counter --time=12"
  "04_bathroom|House 0 bathroom|--inside=0,toilet --time=12"
  "05_factory_hall|Factory hall, Old Pete|--time=15 --cam=0,0,-116,0,-5"
  "06_demo_factory|--demo-factory|--demo-factory --advance=7.5 --time=12 --cam=0,0,6,0,-25"
  "07_demo_farm|--demo-farm|--demo-farm --advance=7.5 --time=12 --cam=0,0,6,0,-25"
  "08_demo_defense|--demo-defense 22:00|--demo-defense --time=22 --advance=1 --cam=7,0,-13,148,-14"
  "09_title|Title screen|--title"
  "10_inventory_gear|Inventory, --gear=yellow|--gear=yellow --time=12"
  "11_skills|Skills screen|--skills --time=12"
  "12_help|Help screen (F1)|--help --time=12"
)
failed=0
labels=()
for s in "${shots[@]}"; do
  IFS='|' read -r name label flags <<< "$s"
  # shellcheck disable=SC2086
  if bash tools/shot.sh "tour/$name" $flags >/dev/null 2>&1 && [ -f ".shots/tour/$name.png" ]; then
    echo "tour.sh: $name ok"
  else
    echo "tour.sh: $name FAILED" >&2
    failed=1
  fi
  labels+=("$name|$label")
done
py=python
command -v python >/dev/null 2>&1 || py=python3
"$py" tools/contact_sheet.py .shots/tour "${labels[@]}" || failed=1
exit "$failed"
