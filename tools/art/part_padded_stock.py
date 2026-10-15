"""Slip-on padded recoil pad for a rifle stock; front (-Y) face meets the wooden butt."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, finish, material, reset  # noqa: E402

reset()
rubber = material("Gun Rubber", (0.012, 0.014, 0.015), 0.0, 0.94)
polymer = material("Gun Polymer", (0.055, 0.050, 0.042), 0.03, 0.82)

box("Recoil_Pad", (0.052, 0.035, 0.112), (0.0, 0.004, 0.0), rubber, 0.006)
box("Pad_Back", (0.047, 0.012, 0.102), (0.0, 0.025, 0.0), polymer, 0.004)
box("Upper_Strap", (0.060, 0.048, 0.014), (0.0, -0.002, 0.035), polymer, 0.003)
box("Lower_Strap", (0.060, 0.048, 0.014), (0.0, -0.002, -0.035), polymer, 0.003)

finish("part_padded_stock", (0.065, 0.12, 0.06), max_triangles=3000)
