"""Water tap (M17a): a standpipe off the water tower's mains with a valve wheel and a spout over a drip tray.
It only runs while the tower is running. Written by Claude, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/water_tap.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, lamp, mat, material, reset  # noqa: E402

reset()
bare, bare_edge, body_dark = mat("bare"), mat("bare_edge"), mat("body_dark")
pipe_blue = material("Mains Blue", (0.10, 0.22, 0.42), 0.45, 0.55)

box("Base_Plate", (0.7, 0.7, 0.08), (0.0, 0.0, 0.04), body_dark, 0.02)
cylinder("Standpipe", 0.09, 1.0, (0.0, 0.12, 0.55), pipe_blue, 12, bevel=0.01)
cylinder("Collar", 0.13, 0.08, (0.0, 0.12, 0.2), bare_edge, 12)
cylinder("Elbow", 0.1, 0.32, (0.0, -0.02, 0.98), pipe_blue, 12, rotation=(deg(90), 0.0, 0.0))
cylinder("Spout", 0.06, 0.22, (0.0, -0.18, 0.88), mat("output_orange"), 10)
cylinder("Valve_Stem", 0.03, 0.14, (0.0, 0.12, 1.1), bare, 8)
cylinder("Valve_Wheel", 0.13, 0.04, (0.0, 0.12, 1.16), mat("red"), 12)
box("Drip_Tray", (0.42, 0.3, 0.06), (0.0, -0.18, 0.22), bare, 0.01)
box("Tray_Lip", (0.42, 0.04, 0.08), (0.0, -0.32, 0.26), bare_edge)
lamp((0.22, 0.25, 1.05), radius=0.05)

finish("water_tap", (0.8, 1.2, 0.8))
