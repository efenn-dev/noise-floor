"""0.75 m wooden-handled felling/fire axe with bright bit and flat poll."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, material, reset  # noqa: E402
from melee_common import apply_bevel, grip_anchor, held_finish, profile_prism, swept_oval  # noqa: E402

reset()
wood = material("Weapon Wood", (0.18, 0.052, 0.012), 0.0, 0.64)
metal = material("Weapon Metal", (0.045, 0.052, 0.055), 0.82, 0.39)
edge = material("Weapon Edge", (0.32, 0.36, 0.38), 0.92, 0.20)

stations = [(0.000, -0.110), (-0.004, 0.020), (-0.012, 0.200),
            (-0.006, 0.400), (0.006, 0.555), (0.004, 0.600)]
radii = [(0.021, 0.027), (0.021, 0.027), (0.020, 0.026),
         (0.019, 0.024), (0.021, 0.026), (0.024, 0.029)]
handle = swept_oval("Handle", stations, radii, wood, sides=14)
apply_bevel(handle, 0.0015, 2)

# kit.finish() half-turns source -Y onto exported Godot -Z.
profile_prism("Axe_Head", [(0.092, 0.540), (0.070, 0.620), (-0.020, 0.640),
                           (-0.105, 0.620), (-0.118, 0.557), (-0.040, 0.530)],
              0.052, metal, 0.003)
profile_prism("Sharpened_Bit", [(-0.105, 0.620), (-0.128, 0.615),
                                (-0.137, 0.555), (-0.118, 0.557)],
              0.047, edge, 0.0012)
box("Flat_Poll", (0.050, 0.050, 0.060), (0, 0.102, 0.575), metal, 0.002)

grip_anchor()
held_finish("axe", (0.30, 0.95, 0.32), 0.75,
            ["Weapon Metal", "Weapon Wood", "Weapon Edge"], preview_scale=1.05)
