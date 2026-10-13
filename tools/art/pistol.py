"""A plain semi-automatic pistol (M14), held in view in first person. Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/pistol.py

Not a build piece: the "box" passed to finish() is just its size (0.04 wide, 0.16 tall, 0.24 long). The muzzle
points to the front (-Y in Blender, -Z in the game), so the game can hang it under the camera as it is.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, reset  # noqa: E402

reset()

steel = mat("bare")
edge = mat("bare_edge")
grip = mat("rubber")

box("Slide", (0.03, 0.2, 0.034), (0.0, -0.01, 0.112), steel, 0.003)
box("Slide_Serrations", (0.031, 0.035, 0.026), (0.0, 0.07, 0.112), edge)
box("Frame", (0.027, 0.15, 0.024), (0.0, 0.0, 0.083), steel, 0.002)
box("Grip", (0.029, 0.045, 0.105), (0.0, 0.058, 0.035), grip, 0.004, rotation=(deg(-14), 0.0, 0.0))
box("Trigger_Guard", (0.006, 0.042, 0.006), (0.0, 0.006, 0.052), steel)
box("Trigger_Guard_Front", (0.006, 0.006, 0.026), (0.0, -0.016, 0.066), steel)
box("Trigger", (0.005, 0.006, 0.02), (0.0, 0.01, 0.064), edge)
cylinder("Muzzle", 0.0065, 0.012, (0.0, -0.112, 0.112), edge, vertices=10, rotation=(deg(90), 0.0, 0.0))
box("Front_Sight", (0.005, 0.006, 0.008), (0.0, -0.1, 0.132), edge)
box("Rear_Sight", (0.022, 0.006, 0.008), (0.0, 0.082, 0.132), edge)

finish("pistol", (0.04, 0.16, 0.24), max_triangles=800)
