"""0.30 m full-tang kitchen/hunting knife with riveted wooden scales."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, material, reset  # noqa: E402
from melee_common import grip_anchor, held_finish, profile_prism  # noqa: E402

reset()
metal = material("Weapon Metal", (0.060, 0.070, 0.074), 0.88, 0.32)
edge = material("Weapon Edge", (0.42, 0.46, 0.48), 0.95, 0.13)
wood = material("Weapon Wood", (0.12, 0.026, 0.006), 0.0, 0.68)

# 0.18 m blade from z=.06 to .24; the belly/edge is on Blender +Y = Godot -Z.
profile_prism("Blade", [(0.006, 0.055), (0.008, 0.205), (0.000, 0.232),
                        (-0.010, 0.240), (-0.032, 0.185), (-0.034, 0.060)],
              0.0045, metal, 0.0012)
profile_prism("Sharpened_Edge", [(-0.034, 0.060), (-0.032, 0.185), (-0.010, 0.240),
                                 (-0.019, 0.184), (-0.023, 0.063)],
              0.0053, edge, 0.00055)
box("Tang", (0.012, 0.022, 0.120), (0, 0.006, 0.000), metal, 0.001)
box("Left_Wood_Scale", (0.010, 0.033, 0.118), (-0.009, 0.006, -0.001), wood, 0.004)
box("Right_Wood_Scale", (0.010, 0.033, 0.118), (0.009, 0.006, -0.001), wood, 0.004)
box("Bolster", (0.026, 0.038, 0.013), (0, 0.008, 0.058), metal, 0.002)
for z in (-0.035, 0.018):
    cylinder(f"Rivet_{z}", 0.0032, 0.030, (0, 0.006, z), metal, vertices=12,
             rotation=(0, deg(90), 0), bevel=0.0004)

grip_anchor()
held_finish("knife", (0.12, 0.45, 0.12), 0.30,
            ["Weapon Metal", "Weapon Wood", "Weapon Edge"])
