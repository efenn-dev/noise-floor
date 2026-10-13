"""Rural mailbox on a wooden post (A1 street dressing). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/mailbox.py

The box uses a material named "Mailbox Paint" that StreetView tints per house. Its door ("Mailbox Door")
is at the front (-Y here, -Z in the game), which faces the road.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402

reset()
wood = material("Mailbox Post", (0.22, 0.16, 0.10), 0.0, 0.9)
paint = material("Mailbox Paint", (0.55, 0.55, 0.55), 0.3, 0.55)
door = material("Mailbox Door", (0.16, 0.16, 0.17), 0.6, 0.5)
flag = material("Mailbox Flag", (0.70, 0.06, 0.04), 0.2, 0.6)

L, W = 0.48, 0.22
TOP = 1.0  # post height; the box sits on it
box("Post", (0.09, 0.09, TOP), (0.0, 0.06, TOP / 2), wood, 0.01)
box("Shelf", (0.16, 0.36, 0.04), (0.0, 0.0, TOP + 0.02), wood, 0.005)
# A flat-sided box with a rounded top, like the classic tin mailbox.
box("Body", (W, L, 0.12), (0.0, 0.0, TOP + 0.04 + 0.06), paint, 0.005)
cylinder("Roof", W / 2, L, (0.0, 0.0, TOP + 0.16), paint, 12, rotation=(deg(90), 0.0, 0.0))
box("Door", (W + 0.01, 0.02, 0.12), (0.0, -L / 2 - 0.005, TOP + 0.10), door, 0.004)
cylinder("Door_Top", W / 2 + 0.005, 0.02, (0.0, -L / 2 - 0.005, TOP + 0.16), door, 12, rotation=(deg(90), 0.0, 0.0))
box("Latch", (0.04, 0.02, 0.02), (0.0, -L / 2 - 0.02, TOP + 0.20), door, 0.0)
# The red flag on the +X side, raised.
box("Flag_Arm", (0.015, 0.03, 0.24), (W / 2 + 0.01, 0.08, TOP + 0.20), flag, 0.0)
box("Flag", (0.015, 0.10, 0.07), (W / 2 + 0.01, 0.04, TOP + 0.29), flag, 0.0)

finish("mailbox", (0.3, 1.35, 0.55), max_triangles=800)
