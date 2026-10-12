"""Ground-mounted scavenged solar panel. Written by Codex for Noise Floor.

    blender.exe -b --factory-startup --python tools/art/solar_panel.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()
body_dark, bare, bare_edge = mat("body_dark"), mat("bare"), mat("bare_edge")
rubber, rust = mat("rubber"), mat("rust")
solar = material("Solar Cell", (0.012, 0.018, 0.026), 0.3, 0.2)
aluminium = material("Aluminium", (0.62, 0.66, 0.67), 0.9, 0.35)

# The entire array has to live inside a 15 cm-high collision box.  A two-degree
# pitch still makes the front (-Y) visibly lower without turning the panel into
# an implausibly paper-thin prop.
tilt = deg(2.0)
panel_z = 0.052


def on_panel(y: float, lift: float = 0.0) -> tuple[float, float]:
    """Return world Y/Z for a point on the tilted panel's top surface."""
    return (y - lift * 0.0348995, panel_z + y * 0.0348995 + lift * 0.9993908)


# Low masonry pads and steel foot plates give the silhouette some weight.
for xi, x in enumerate((-0.72, 0.72)):
    for yi, y in enumerate((-0.68, 0.68)):
        box(f"Cinder_Block_{xi}_{yi}", (0.24, 0.18, 0.040), (x, y, 0.020), body_dark, 0.012)
        box(f"Foot_Plate_{xi}_{yi}", (0.30, 0.23, 0.018), (x, y, 0.049), bare, 0.006)

# Dark backing plate, aluminium perimeter rails, and a central strengthening bar.
box("Panel_Backing", (1.72, 1.62, 0.026), (0.0, 0.0, panel_z), body_dark, 0.012,
    rotation=(tilt, 0.0, 0.0))
for x in (-0.825, 0.825):
    y, z = on_panel(0.0, 0.025)
    box(f"Side_Frame_{x}", (0.070, 1.62, 0.048), (x, y, z), aluminium, 0.009,
        rotation=(tilt, 0.0, 0.0))
for y0 in (-0.775, 0.775):
    y, z = on_panel(y0, 0.025)
    box(f"End_Frame_{y0}", (1.72, 0.070, 0.048), (0.0, y, z), aluminium, 0.009,
        rotation=(tilt, 0.0, 0.0))
y, z = on_panel(0.0, 0.022)
box("Centre_Frame_Bar", (0.045, 1.49, 0.040), (0.0, y, z), aluminium, 0.006,
    rotation=(tilt, 0.0, 0.0))

# Six by six individually inset photovoltaic cells.  The broad gaps expose the
# backing at distance, so the grid reads cleanly instead of becoming a texture.
cell_w, cell_d = 0.238, 0.218
cell_xs = (-0.678, -0.426, -0.174, 0.174, 0.426, 0.678)
cell_ys = (-0.640, -0.384, -0.128, 0.128, 0.384, 0.640)
for row, cell_y in enumerate(cell_ys):
    for col, cell_x in enumerate(cell_xs):
        y, z = on_panel(cell_y, 0.023)
        box(f"Solar_Cell_{row}_{col}", (cell_w, cell_d, 0.020), (cell_x, y, z), solar, 0.006,
            rotation=(tilt, 0.0, 0.0))

# A cracked front-left cell: three short metal-bright fracture lines branching
# from one point.  They are raised just enough to survive the GLB merge.
crack_y = -0.384
for i, (cx, cy, sx, sy, angle) in enumerate((
        (-0.426, crack_y, 0.010, 0.120, -22.0),
        (-0.447, crack_y - 0.042, 0.009, 0.075, 28.0),
        (-0.397, crack_y + 0.036, 0.009, 0.070, -42.0))):
    y, z = on_panel(cy, 0.036)
    box(f"Cell_Crack_{i}", (sx, sy, 0.006), (cx, y, z), bare_edge, 0.002,
        rotation=(tilt, 0.0, deg(angle)))

# Dirt/rust caught along the lower frame and one cell corner.
y, z = on_panel(-0.727, 0.052)
box("Lower_Frame_Dirt", (0.38, 0.026, 0.009), (0.36, y, z), rust, 0.004,
    rotation=(tilt, 0.0, deg(-3)))
y, z = on_panel(-0.640, 0.038)
box("Cell_Dirt", (0.085, 0.050, 0.007), (0.675, y, z), rust, 0.005,
    rotation=(tilt, 0.0, deg(18)))

# Scavenged repair strap across the right rail, complete with visible fasteners.
y, z = on_panel(0.195, 0.054)
box("Frame_Repair_Strap", (0.112, 0.30, 0.018), (0.825, y, z), bare_edge, 0.006,
    rotation=(tilt, 0.0, deg(4)))
for i, by in enumerate((0.095, 0.295)):
    y, z = on_panel(by, 0.067)
    cylinder(f"Repair_Bolt_{i}", 0.020, 0.012, (0.825, y, z), bare, 10,
             rotation=(tilt, 0.0, 0.0), bevel=0.003)

# Compact weatherproof junction box at the back (+Y) with a short rubber cable
# loop and a steel retaining clip.  Everything remains inside the frame edge.
y, z = on_panel(0.665, 0.042)
box("Junction_Box", (0.31, 0.16, 0.055), (-0.40, y, z), rubber, 0.012,
    rotation=(tilt, 0.0, 0.0))
y, z = on_panel(0.570, 0.035)
cylinder("Cable_Gland", 0.026, 0.075, (-0.40, y, z), bare, 12,
         rotation=(deg(90) + tilt, 0.0, 0.0), bevel=0.004)
cylinder("Back_Cable_A", 0.014, 0.25, (-0.40, 0.505, 0.126), rubber, 10,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Back_Cable_B", 0.014, 0.28, (-0.27, 0.390, 0.126), rubber, 10,
         rotation=(0.0, deg(90), 0.0))
cylinder("Cable_Clip", 0.025, 0.012, (-0.13, 0.390, 0.126), bare_edge, 10, bevel=0.003)

# Frame corner bolts reinforce the low-poly, bolted-together construction.
for xi, x in enumerate((-0.825, 0.825)):
    for yi, bolt_y in enumerate((-0.700, 0.700)):
        y, z = on_panel(bolt_y, 0.058)
        cylinder(f"Frame_Bolt_{xi}_{yi}", 0.022, 0.014, (x, y, z), bare, 10,
                 rotation=(tilt, 0.0, 0.0), bevel=0.003)

finish("solar_panel", (1.8, 0.15, 1.8))
