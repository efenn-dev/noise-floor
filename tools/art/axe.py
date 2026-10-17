"""0.75 m wooden-handled felling axe: a forged wedge head with a flared, bright-ground bit.

V38 (Emmitt: "it looks more like a sledgehammer"): the head was one flat-sided block 5 cm thick with a square
poll, so from any side it read as a hammer. It is now lofted through cross-sections from poll to bit: a slim
rounded poll, the eye a little fuller, cheeks tapering to a sharp edge while the bit flares to 11 cm tall, and
the edge curved (furthest forward in the middle) and ground bright, the head painted red. The handle is a slimmer oval with a swell
at the foot and its top showing through the eye.
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import material, reset  # noqa: E402
from melee_common import apply_bevel, grip_anchor, held_finish, swept_oval  # noqa: E402

reset()
wood = material("Weapon Wood", (0.18, 0.052, 0.012), 0.0, 0.64)
# A red-painted head with a wide, bright ground bevel reads as an axe at a glance (bare dark steel read as a
# black block in game: metal goes dark without reflections to show).
paint = material("Axe Paint", (0.45, 0.04, 0.03), 0.1, 0.45)
bevel = material("Axe Bevel", (0.62, 0.64, 0.66), 0.6, 0.22)

# Handle: a slim oval (X across the head, Y along it), a swell at the foot, narrowing into the eye.
stations = [(0.006, -0.118), (0.004, -0.100), (0.000, -0.075), (-0.004, 0.020),
            (-0.010, 0.200), (-0.006, 0.400), (0.002, 0.520), (0.004, 0.626)]
radii = [(0.020, 0.027), (0.021, 0.028), (0.016, 0.021), (0.016, 0.021),
         (0.016, 0.021), (0.015, 0.020), (0.0145, 0.022), (0.0145, 0.022)]
handle = swept_oval("Handle", stations, radii, wood, sides=14)
apply_bevel(handle, 0.0015, 2)

# Head cross-sections from the poll (+Y) to the bit (-Y; kit.finish() turns the striking side to Godot -Z):
# (Y, half thickness across X, bottom Z, top Z). Thickness tapers to the edge while the bit flares.
EDGE_Y = -0.137
EDGE_CURVE = 0.010  # how much further forward the middle of the edge is than its toe and heel
HEAD = [(0.058, 0.015, 0.549, 0.601), (0.044, 0.017, 0.545, 0.605), (0.024, 0.019, 0.540, 0.612),
        (-0.016, 0.019, 0.540, 0.612), (-0.036, 0.016, 0.539, 0.613), (-0.066, 0.011, 0.533, 0.620),
        (-0.084, 0.0080, 0.526, 0.628)]
BIT = [HEAD[-1], (-0.104, 0.0052, 0.518, 0.635), (-0.122, 0.0026, 0.510, 0.642), (EDGE_Y, 0.0006, 0.506, 0.645)]


def ring(y, t, z_lo, z_hi, curve):
    """One cross-section: a chamfered rectangle, its Y bent forward toward the middle by `curve`."""
    c = min(t, (z_hi - z_lo) / 4.0) * 0.6
    side = [z_lo + c + (z_hi - z_lo - 2.0 * c) * f for f in (0.0, 0.25, 0.5, 0.75, 1.0)]
    points = ([(t, z) for z in side] + [(t * 0.65, z_hi), (-t * 0.65, z_hi)]
              + [(-t, z) for z in reversed(side)] + [(-t * 0.65, z_lo), (t * 0.65, z_lo)])
    mid, half = (z_lo + z_hi) / 2.0, (z_hi - z_lo) / 2.0
    return [(x, y - curve * (1.0 - ((z - mid) / half) ** 2), z) for x, z in points]


def loft(name, sections, mat):
    """Join consecutive cross-sections into a closed solid (flat-shaded, like forged and ground steel)."""
    def curve_at(y):
        # The edge's curve fades in over the last 4 cm before the edge.
        return EDGE_CURVE * max(0.0, min(1.0, (-0.097 - y) / (-0.097 - EDGE_Y)))

    verts = []
    for y, t, z_lo, z_hi in sections:
        verts.extend(ring(y, t, z_lo, z_hi, curve_at(y)))
    n = len(verts) // len(sections)
    faces = [tuple(range(n - 1, -1, -1)), tuple((len(sections) - 1) * n + i for i in range(n))]
    for s in range(len(sections) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((s * n + i, s * n + j, (s + 1) * n + j, (s + 1) * n + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


loft("Axe_Head", HEAD, paint)
loft("Sharpened_Bit", BIT, bevel)

grip_anchor()
held_finish("axe", (0.30, 0.95, 0.32), 0.75,
            ["Axe Paint", "Weapon Wood", "Axe Bevel"], preview_scale=1.05)
