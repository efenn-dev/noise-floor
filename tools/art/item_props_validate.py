"""Validate the dropped-item GLB batch and print a compact model report.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/item_props_validate.py
"""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
ITEM_IDS = (
    "plank", "nails", "scrap_metal", "metal_plate", "dirty_water", "clean_water",
    "soda", "chips", "canned_food", "seeds", "vegetable", "rotten_food", "bandage",
    "school_bag", "hiking_pack", "military_rucksack", "gas_can", "repair_kit",
    "ammo_casing", "ammo_standard", "ammo_subsonic", "ammo_ap", "bolt", "shells",
    "gunpowder", "wall_panel", "radio", "hard_hat", "cap", "hi_vis_vest", "jacket",
    "work_gloves", "work_pants", "cargo_pants", "work_boots", "sneakers", "headlamp",
)
ALLOWED_MATERIALS = {
    "Item Metal", "Item Dark Metal", "Item Wood", "Item Cardboard", "Item Cloth",
    "Item Denim", "Item Leather", "Item Rubber", "Item Plastic", "Item Paper",
    "Item Glass", "Item Food", "Item Hi-Vis", "Item Red Paint", "Item Brass",
    "Item Label",
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)


def validate_one(item_id):
    path = MODEL_DIR / f"item_{item_id}.glb"
    assert path.exists(), f"missing {path.relative_to(ROOT)}"
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, f"{item_id}: no mesh"
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    dims = hi - lo
    triangles = 0
    materials = set()
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        materials.update(mat.name for mat in obj.data.materials if mat)
    invalid = sorted(name for name in materials
                     if name not in ALLOWED_MATERIALS and not name.startswith("Item Label "))
    assert not invalid, f"{item_id}: invalid materials {invalid}"
    assert 300 <= triangles <= 3000, f"{item_id}: {triangles} triangles"
    assert min(dims) > 0.005, f"{item_id}: degenerate bounds {tuple(dims)}"
    print("ITEM_REPORT", item_id,
          f"size={dims.x:.3f}x{dims.z:.3f}x{dims.y:.3f}",
          f"triangles={triangles}", f"materials={','.join(sorted(materials))}")


failures = []
for prop_id in ITEM_IDS:
    try:
        validate_one(prop_id)
    except Exception as exc:  # report the whole batch, not only the first missing file
        failures.append(str(exc))
for failure in failures:
    print("ITEM_FAILURE", failure)
assert not failures, f"{len(failures)} item prop validation failures"
print(f"ITEM_VALIDATION_OK count={len(ITEM_IDS)}")
