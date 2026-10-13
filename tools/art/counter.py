"""Kitchen counter with a sink, back against a wall (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/counter.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()

W, D = 1.76, 0.65  # width along the wall, depth into the room (front = -Y)
carcass = material("Counter Carcass", (0.42, 0.40, 0.34), 0.0, 0.85)
doors = material("Cupboard Doors", (0.30, 0.38, 0.30), 0.0, 0.8)  # the front: test_art_models checks it is at -Z
top = material("Worktop", (0.55, 0.52, 0.46), 0.0, 0.6)
steel = material("Sink Steel", (0.45, 0.47, 0.48), 0.85, 0.35)
dark = mat("black")

# Toe kick, cupboard body and worktop (the worktop overhangs the doors a little at the front).
box("Toe_Kick", (W - 0.04, D - 0.12, 0.10), (0.0, 0.05, 0.05), dark)
box("Carcass", (W, D - 0.05, 0.78), (0.0, 0.025, 0.49), carcass, 0.01)
box("Worktop", (W, D, 0.045), (0.0, 0.0, 0.9025), top, 0.008)
box("Backsplash", (W, 0.025, 0.10), (0.0, D / 2 - 0.0125, 0.975), top, 0.004)

# Three cupboard doors and a drawer row across the front, with dark handles.
door_w = (W - 0.08) / 3
for i in range(3):
    x = -W / 2 + 0.04 + door_w * (i + 0.5)
    box(f"Door_{i}", (door_w - 0.03, 0.025, 0.52), (x, -D / 2 + 0.03, 0.40), doors, 0.006)
    box(f"Drawer_{i}", (door_w - 0.03, 0.025, 0.14), (x, -D / 2 + 0.03, 0.78), doors, 0.006)
    box(f"Door_Handle_{i}", (0.10, 0.02, 0.02), (x, -D / 2 + 0.02, 0.60), dark)
    box(f"Drawer_Handle_{i}", (0.14, 0.02, 0.02), (x, -D / 2 + 0.02, 0.78), dark)

# The sink: a steel rim with a dark basin inside it, and a tap at the back.
box("Sink_Rim", (0.62, 0.44, 0.012), (0.30, -0.02, 0.931), steel)
box("Sink_Basin", (0.52, 0.34, 0.006), (0.30, -0.02, 0.938), dark)
box("Drain", (0.05, 0.05, 0.004), (0.30, -0.02, 0.942), steel)
cylinder("Tap_Post", 0.02, 0.20, (0.30, 0.24, 1.025), steel, 10)
box("Tap_Spout", (0.035, 0.16, 0.03), (0.30, 0.17, 1.11), steel, 0.008)
for x in (0.22, 0.38):
    cylinder(f"Tap_Knob_{x}", 0.022, 0.04, (x, 0.25, 0.945), steel, 10)

# A chopping board and a mug so it reads as a kitchen from across the room.
box("Chopping_Board", (0.36, 0.24, 0.02), (-0.45, -0.04, 0.935),
    material("Board Wood", (0.40, 0.28, 0.16), 0.0, 0.85), 0.006, rotation=(0.0, 0.0, deg(-6)))
cylinder("Mug", 0.04, 0.09, (-0.15, 0.14, 0.97), mat("red"), 10)

finish("counter", (1.76, 1.15, 0.65), max_triangles=2000)
