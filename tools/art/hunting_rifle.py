"""A bolt-action hunting rifle (M14), held in view in first person. Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/hunting_rifle.py

Not a build piece: the "box" passed to finish() is just its size (0.09 wide, 0.2 tall, 1.1 long). The muzzle
points to the front (-Y in Blender, -Z in the game).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()

steel = mat("bare")
edge = mat("bare_edge")
wood = material("Rifle Walnut", (0.20, 0.09, 0.035), 0.0, 0.6)
pad = mat("rubber")

# Stock: a wooden butt that drops a little behind the grip, with a rubber pad at the back.
box("Stock_Butt", (0.042, 0.3, 0.085), (0.0, 0.36, 0.06), wood, 0.008, rotation=(deg(-6), 0.0, 0.0))
box("Butt_Pad", (0.044, 0.02, 0.1), (0.0, 0.515, 0.045), pad, 0.004, rotation=(deg(-6), 0.0, 0.0))
box("Wrist", (0.036, 0.1, 0.05), (0.0, 0.17, 0.085), wood, 0.006)
box("Forend", (0.04, 0.38, 0.042), (0.0, -0.17, 0.09), wood, 0.008)
# Receiver and bolt (the handle on the right: Blender -X ends up on the game's +X).
box("Receiver", (0.032, 0.2, 0.04), (0.0, 0.05, 0.125), steel, 0.004)
cylinder("Bolt_Handle", 0.005, 0.045, (-0.03, 0.1, 0.125), edge, vertices=8, rotation=(0.0, deg(90), 0.0))
cylinder("Bolt_Knob", 0.009, 0.014, (-0.055, 0.1, 0.125), edge, vertices=10, rotation=(0.0, deg(90), 0.0))
box("Trigger_Guard", (0.006, 0.06, 0.006), (0.0, 0.1, 0.05), steel)
box("Trigger", (0.005, 0.006, 0.022), (0.0, 0.1, 0.066), edge)
box("Magazine_Plate", (0.03, 0.07, 0.012), (0.0, 0.03, 0.066), steel)
# Barrel, past the forend to the muzzle.
cylinder("Barrel", 0.011, 0.62, (0.0, -0.24, 0.125), steel, vertices=14, rotation=(deg(90), 0.0, 0.0))
cylinder("Muzzle_Crown", 0.0125, 0.02, (0.0, -0.54, 0.125), edge, vertices=14, rotation=(deg(90), 0.0, 0.0))
box("Front_Sight", (0.005, 0.01, 0.014), (0.0, -0.52, 0.142), edge)

finish("hunting_rifle", (0.09, 0.2, 1.1), max_triangles=1200)
