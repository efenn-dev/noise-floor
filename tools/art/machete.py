"""0.60 m machete with a curved 0.45 m blade and riveted two-piece grip."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, material, reset  # noqa: E402
from melee_common import grip_anchor, held_finish, profile_prism  # noqa: E402

reset()
metal = material("Weapon Metal", (0.055, 0.064, 0.068), 0.86, 0.36)
edge = material("Weapon Edge", (0.38, 0.42, 0.44), 0.94, 0.16)
grip = material("Weapon Grip", (0.012, 0.009, 0.006), 0.02, 0.86)

# Tang and broad blade: 0.45 m from guard (z=.05) to the raised tip (z=.50).
profile_prism("Blade", [(0.010, 0.045), (0.014, 0.380), (0.010, 0.455),
                        (-0.005, 0.500), (-0.040, 0.465), (-0.052, 0.380),
                        (-0.050, 0.100), (-0.032, 0.045)],
              0.0055, metal, 0.0015)
profile_prism("Sharpened_Edge", [(-0.050, 0.100), (-0.052, 0.380),
                                 (-0.040, 0.465), (-0.005, 0.500),
                                 (-0.016, 0.462), (-0.038, 0.375), (-0.036, 0.105)],
              0.0065, edge, 0.0007)
box("Tang", (0.014, 0.024, 0.150), (0, 0.006, -0.025), metal, 0.0015)
box("Left_Handle_Scale", (0.011, 0.036, 0.150), (-0.010, 0.006, -0.025), grip, 0.004)
box("Right_Handle_Scale", (0.011, 0.036, 0.150), (0.010, 0.006, -0.025), grip, 0.004)
box("Guard", (0.034, 0.052, 0.011), (0, 0.012, 0.050), metal, 0.002)
for z in (-0.065, -0.005, 0.035):
    cylinder(f"Rivet_{z}", 0.004, 0.034, (0, 0.006, z), metal, vertices=12,
             rotation=(0, deg(90), 0), bevel=0.0005)

grip_anchor()
held_finish("machete", (0.16, 0.80, 0.16), 0.60,
            ["Weapon Metal", "Weapon Grip", "Weapon Edge"])
