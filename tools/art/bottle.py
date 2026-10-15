"""V30 empty glass bottle throwable."""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, finish, material, reset  # noqa: E402

reset()
glass = material("Gun Glass", (0.42, 0.62, 0.58), 0.05, 0.18)
cylinder("Bottle_Base", 0.039, 0.018, (0.0, 0.0, 0.009), glass, vertices=24, bevel=0.003)
bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.037, radius2=0.030, depth=0.135,
                                location=(0.0, 0.0, 0.085))
bpy.context.object.name = "Bottle_Body"
bpy.context.object.data.materials.append(glass)
bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.030, radius2=0.012, depth=0.065,
                                location=(0.0, 0.0, 0.185))
bpy.context.object.name = "Bottle_Shoulder"
bpy.context.object.data.materials.append(glass)
cylinder("Bottle_Neck", 0.012, 0.065, (0.0, 0.0, 0.250), glass, vertices=24)
cylinder("Bottle_Lip", 0.016, 0.014, (0.0, 0.0, 0.289), glass, vertices=24, bevel=0.002)
finish("bottle", (0.09, 0.31, 0.09), max_triangles=5000)
