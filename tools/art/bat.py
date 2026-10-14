"""Plain, worn 0.85 m wooden baseball bat with a taped grip."""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, material, reset  # noqa: E402
from melee_common import grip_anchor, held_finish, lathe  # noqa: E402

reset()
wood = material("Weapon Wood", (0.14, 0.040, 0.010), 0.0, 0.67)
grip = material("Weapon Grip", (0.014, 0.012, 0.010), 0.0, 0.95)

profile = [(-0.100, 0.028), (-0.092, 0.034), (-0.078, 0.034), (-0.066, 0.022),
           (0.000, 0.019), (0.150, 0.021), (0.320, 0.027), (0.470, 0.034),
           (0.610, 0.0365), (0.715, 0.0365), (0.742, 0.034), (0.750, 0.025)]
lathe("Bat", profile, wood, sides=20,
      dents=((0.575, -math.pi / 2, 0.0035, 0.038), (0.665, math.pi - 0.4, 0.0028, 0.030)))

for i in range(11):
    z = -0.055 + i * 0.016
    cylinder(f"Tape_{i}", 0.0220 + (0.0005 if i % 4 == 0 else 0), 0.018,
             (0, 0, z), grip, vertices=16, bevel=0.0007)

grip_anchor()
held_finish("bat", (0.12, 1.05, 0.12), 0.85,
            ["Weapon Wood", "Weapon Grip"])
