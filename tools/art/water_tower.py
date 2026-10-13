"""Water tower (M17a): the industrial park's first big project. A riveted tank on four braced legs, about
12.6 m tall, with a ladder up the front leg to a catwalk round the tank, a riser pipe down the middle and a
small pump house at its foot (where you press E). Not a build piece: ParkView stands it at ParkPlan.TOWER_POS
and gives it leg and pump colliders. Written by Claude, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/water_tower.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()
bare, bare_edge, rust, body_dark = mat("bare"), mat("bare_edge"), mat("rust"), mat("body_dark")
tank_paint = material("Tower Paint", (0.36, 0.42, 0.44), 0.35, 0.70)
tank_band = material("Tower Band", (0.20, 0.24, 0.25), 0.40, 0.65)
roof_paint = material("Tower Roof", (0.24, 0.27, 0.28), 0.45, 0.60)

LEG_FOOT = 2.45   # leg feet at (+-2.45, +-2.45) on the ground
LEG_TOP = 2.05    # leg tops at (+-2.05, +-2.05) under the tank
DECK = 8.0        # the catwalk and the tank's floor
TANK_R = 2.55
TANK_H = 3.2


def leg(name: str, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, r: float, m) -> None:
    """A strut from (x0, y0, z0) to (x1, y1, z1)."""
    dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    obj = cylinder(name, r, length, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), m, 8)
    obj.rotation_mode = "QUATERNION"
    from mathutils import Vector
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((dx, dy, dz)).normalized())


# Four legs, splayed out at the feet, on concrete pads.
for sx in (-1, 1):
    for sy in (-1, 1):
        leg(f"Leg_{sx}_{sy}", sx * LEG_FOOT, sy * LEG_FOOT, 0.25, sx * LEG_TOP, sy * LEG_TOP, DECK, 0.16, bare)
        box(f"Pad_{sx}_{sy}", (0.8, 0.8, 0.25), (sx * LEG_FOOT, sy * LEG_FOOT, 0.125), body_dark, 0.03)

# X braces on each side at two heights, and ring girts between the legs.
def at(t: float) -> float:
    return LEG_FOOT + (LEG_TOP - LEG_FOOT) * t


for z0, z1 in ((0.6, 4.2), (4.2, 7.8)):
    t0, t1 = z0 / DECK, z1 / DECK
    for s in (-1, 1):
        # north / south faces (vary x), east / west faces (vary y)
        leg(f"BraceA_y{s}_{z0}", -at(t0), s * at(t0), z0, at(t1), s * at(t1), z1, 0.05, rust)
        leg(f"BraceB_y{s}_{z0}", at(t0), s * at(t0), z0, -at(t1), s * at(t1), z1, 0.05, rust)
        leg(f"BraceA_x{s}_{z0}", s * at(t0), -at(t0), z0, s * at(t1), at(t1), z1, 0.05, rust)
        leg(f"BraceB_x{s}_{z0}", s * at(t0), at(t0), z0, s * at(t1), -at(t1), z1, 0.05, rust)
for z in (4.2,):
    t = z / DECK
    for s in (-1, 1):
        leg(f"Girt_y{s}", -at(t), s * at(t), z, at(t), s * at(t), z, 0.07, bare_edge)
        leg(f"Girt_x{s}", s * at(t), -at(t), z, s * at(t), at(t), z, 0.07, bare_edge)

# Catwalk deck and railing round the tank's foot.
box("Deck", (5.6, 5.6, 0.12), (0.0, 0.0, DECK), bare, 0.02)
for s in (-1, 1):
    box(f"Rail_x{s}", (5.6, 0.06, 0.06), (0.0, s * 2.77, DECK + 1.0), bare_edge)
    box(f"Rail_y{s}", (0.06, 5.6, 0.06), (s * 2.77, 0.0, DECK + 1.0), bare_edge)
    for k in (-2.7, -0.9, 0.9, 2.7):
        box(f"Post_x{s}_{k}", (0.06, 0.06, 1.0), (k, s * 2.77, DECK + 0.5), bare_edge)
        box(f"Post_y{s}_{k}", (0.06, 0.06, 1.0), (s * 2.77, k, DECK + 0.5), bare_edge)

# The tank: a riveted drum with two dark bands, a cone roof and a vent cap.
cylinder("Tank", TANK_R, TANK_H, (0.0, 0.0, DECK + 0.06 + TANK_H / 2), tank_paint, 20)
for z in (DECK + 0.5, DECK + TANK_H - 0.4):
    cylinder(f"Band_{z}", TANK_R + 0.04, 0.16, (0.0, 0.0, z), tank_band, 20)
bpy_cone = __import__("bpy")
bpy_cone.ops.mesh.primitive_cone_add(vertices=20, radius1=TANK_R + 0.12, radius2=0.25, depth=1.1,
                                     location=(0.0, 0.0, DECK + 0.06 + TANK_H + 0.55))
cone = bpy_cone.context.object
cone.name = "Roof"
cone.data.materials.append(roof_paint)
cylinder("Vent", 0.22, 0.35, (0.0, 0.0, DECK + TANK_H + 1.25), bare_edge, 10)
# A rust streak and a patch plate on the front, where the tank leaked.
box("Rust_Streak", (0.35, 0.05, 1.6), (0.7, -TANK_R - 0.01, DECK + 1.5), rust)
box("Patch_Plate", (0.7, 0.05, 0.6), (0.7, -TANK_R - 0.03, DECK + 2.3), bare)

# Riser pipe down the middle to the pump house, and the pump house itself (front, -Y).
cylinder("Riser", 0.22, DECK - 1.2, (0.0, 0.0, 1.2 + (DECK - 1.2) / 2), bare_edge, 10)
box("Pump_House", (1.6, 1.2, 1.3), (0.0, 0.0, 0.65), body_dark, 0.04)
box("Pump_Lid", (1.7, 1.3, 0.08), (0.0, 0.0, 1.34), bare, 0.02)
cylinder("Pump_Motor", 0.32, 0.7, (0.0, -0.7, 0.75), bare_edge, 12, rotation=(deg(90), 0.0, 0.0))
cylinder("Valve_Wheel", 0.24, 0.05, (0.55, -0.62, 1.0), mat("red"), 12, rotation=(deg(90), 0.0, 0.0))

# Ladder up the front (-Y) face, from the ground to the catwalk, between the two front legs.
for x in (-0.25, 0.25):
    leg(f"Ladder_Rail_{x}", x, -LEG_FOOT + 0.05, 0.0, x, -LEG_TOP - 0.55, DECK + 1.0, 0.03, bare_edge)
rungs = 26
for i in range(1, rungs):
    t = i / rungs
    z = t * (DECK + 1.0)
    y = (-LEG_FOOT + 0.05) + ((-LEG_TOP - 0.55) - (-LEG_FOOT + 0.05)) * t
    box(f"Rung_{i}", (0.5, 0.04, 0.04), (0.0, y, z), bare)

finish("water_tower", (6.0, 12.8, 6.0), max_triangles=6000)
