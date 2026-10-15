"""Deterministic low-poly dropped-item props for Noise Floor (Blender 5.1).

Examples:
    blender.exe -b --factory-startup --python tools/art/item_props.py -- all
    blender.exe -b --factory-startup --python tools/art/item_props.py -- gas_can
    blender.exe -b --factory-startup --python tools/art/item_props.py -- contact

Every build starts from an empty scene, uses only the approved Item material names, and ends in
kit.finish(..., max_triangles=3000).  The contact mode imports the finished GLBs, normalises only
their preview copies to a common cell size, and renders tools/art/item_props_contact.png.
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
ITEM_IDS = (
    "plank", "nails", "scrap_metal", "metal_plate", "dirty_water", "clean_water",
    "soda", "chips", "canned_food", "seeds", "vegetable", "rotten_food", "bandage",
    "school_bag", "hiking_pack", "military_rucksack", "gas_can", "repair_kit",
    "ammo_casing", "ammo_standard", "ammo_subsonic", "ammo_ap", "bolt", "shells",
    "gunpowder", "wall_panel", "radio", "hard_hat", "cap", "hi_vis_vest", "jacket",
    "work_gloves", "work_pants", "cargo_pants", "work_boots", "sneakers", "headlamp",
)

# finish() boxes are Godot order: width X, height Y, depth Z.
BOXES = {
    "plank": (1.04, .05, .18), "nails": (.30, .11, .24),
    "scrap_metal": (.48, .19, .40), "metal_plate": (.48, .06, .38),
    "dirty_water": (.28, .40, .25), "clean_water": (.13, .33, .13),
    "soda": (.08, .14, .08), "chips": (.23, .08, .11),
    "canned_food": (.12, .16, .12), "seeds": (.27, .11, .24),
    "vegetable": (.48, .16, .28), "rotten_food": (.34, .19, .27),
    "bandage": (.31, .12, .18), "school_bag": (.43, .50, .24),
    "hiking_pack": (.51, .68, .36), "military_rucksack": (.57, .74, .38),
    "gas_can": (.39, .51, .20), "repair_kit": (.45, .28, .28),
    "ammo_casing": (.29, .08, .22), "ammo_standard": (.29, .17, .30),
    "ammo_subsonic": (.29, .17, .30), "ammo_ap": (.29, .17, .30),
    "bolt": (.43, .11, .18), "shells": (.29, .17, .28),
    "gunpowder": (.19, .13, .19), "wall_panel": (.66, .07, .56),
    "radio": (.17, .09, .41), "hard_hat": (.38, .23, .34),
    "cap": (.36, .23, .38), "hi_vis_vest": (.44, .08, .50),
    "jacket": (.50, .10, .54), "work_gloves": (.46, .09, .32),
    "work_pants": (.44, .10, .56), "cargo_pants": (.44, .10, .56),
    "work_boots": (.48, .28, .40), "sneakers": (.52, .20, .40),
    "headlamp": (.36, .12, .30),
}

DEFAULTS = {
    "Item Metal": ((.34, .37, .38), .78, .48),
    "Item Dark Metal": ((.075, .085, .085), .70, .56),
    "Item Wood": ((.38, .20, .085), .02, .86),
    "Item Cardboard": ((.48, .32, .16), .0, .90),
    "Item Cloth": ((.20, .24, .22), .0, .94),
    "Item Denim": ((.08, .14, .20), .0, .92),
    "Item Leather": ((.24, .105, .045), .0, .84),
    "Item Rubber": ((.018, .022, .022), .0, .96),
    "Item Plastic": ((.18, .28, .38), .0, .52),
    "Item Paper": ((.72, .67, .54), .0, .94),
    "Item Glass": ((.35, .62, .72), .03, .18),
    "Item Food": ((.38, .44, .12), .0, .96),
    "Item Hi-Vis": ((1.0, .26, .015), .0, .70),
    "Item Red Paint": ((.58, .025, .018), .28, .64),
    "Item Brass": ((.62, .36, .07), .72, .42),
    "Item Label": ((.80, .72, .26), .0, .78),
}


def mat(name, color=None, metallic=None, roughness=None):
    base_color, base_metallic, base_roughness = DEFAULTS[name]
    return material(name, color or base_color,
                    base_metallic if metallic is None else metallic,
                    base_roughness if roughness is None else roughness)


def sphere(name, location, scale, material_, segments=12, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material_)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def cone(name, radius1, radius2, depth, location, material_, vertices=12, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2,
                                    depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


def torus(name, major_radius, minor_radius, location, material_, major_segments=20,
          minor_segments=6, rotation=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius,
                                     major_segments=major_segments, minor_segments=minor_segments,
                                     location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material_)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def tube_between(name, start, end, radius, material_, vertices=10):
    a, b = Vector(start), Vector(end)
    direction = b - a
    obj = cylinder(name, radius, direction.length, tuple((a + b) / 2), material_, vertices)
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def flat_prism(name, points, z0, z1, material_):
    count = len(points)
    vertices = [(x, y, z0) for x, y in points] + [(x, y, z1) for x, y in points]
    faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Soft edges", "BEVEL")
    bevel.width = min(.006, (z1 - z0) * .28)
    bevel.segments = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def lathe(name, profile, material_, sides=18):
    verts = []
    for z, radius in profile:
        for i in range(sides):
            angle = math.tau * i / sides
            verts.append((radius * math.cos(angle), radius * math.sin(angle), z))
    faces = [tuple(range(sides - 1, -1, -1)),
             tuple((len(profile) - 1) * sides + i for i in range(sides))]
    for ring in range(len(profile) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b = ring * sides + i, ring * sides + j
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def seam_boxes(prefix, positions, sizes, material_, rotation=(0, 0, 0)):
    for i, position in enumerate(positions):
        box(f"{prefix}_{i}", sizes, position, material_, min(sizes) * .20, rotation)


def build_plank():
    wood = mat("Item Wood", (.34, .16, .055))
    dark = mat("Item Dark Metal", (.13, .075, .035), .35, .86)
    box("Weathered_Plank", (1.0, .14, .03), (0, 0, .015), wood, .006)
    for i, x in enumerate((-.38, -.22, -.04, .17, .34)):
        cylinder(f"Knot_{i}", .013 + .003 * (i % 2), .005, (x, -.022 + .025*(i%3), .033),
                 dark, 12, bevel=.001)
    for x in (-.45, .44):
        cylinder("Old_Nail", .005, .006, (x, .035, .034), dark, 10, bevel=.001)


def build_nails():
    card = mat("Item Cardboard")
    metal = mat("Item Metal", (.22, .20, .17), .65, .62)
    label = mat("Item Label", (.78, .60, .19))
    box("Nail_Box", (.18, .14, .055), (0, .015, .0275), card, .008)
    box("Nail_Label", (.11, .0015, .030), (0, -.056, .059), label, .002)
    for i in range(8):
        x = -.085 + (i % 4) * .055
        y = -.095 + (i // 4) * .035
        angle = deg(-34 + i * 11)
        cylinder(f"Nail_Shaft_{i}", .003, .105, (x, y, .018), metal, 8,
                 rotation=(0, deg(90), angle))
        cylinder(f"Nail_Head_{i}", .009, .004, (x - .052*math.cos(angle),
                 y - .052*math.sin(angle), .019), metal, 8, bevel=.001)


def build_scrap_metal():
    metal = mat("Item Metal", (.31, .16, .075), .62, .82)
    dark = mat("Item Dark Metal", (.10, .065, .045), .64, .84)
    flat_prism("Bent_Sheet", [(-.21,-.14),(.04,-.17),(.10,-.04),(-.03,.03),(-.16,.01)],
               .015, .045, metal)
    box("Angle_Iron", (.30, .055, .045), (.06, .09, .065), dark, .006,
        (0, deg(11), deg(-18)))
    cylinder("Rusty_Pipe", .045, .28, (.10, -.04, .085), metal, 12,
             rotation=(deg(90), deg(12), deg(38)), bevel=.005)
    for i, p in enumerate(((-.16,.08,.062),(.16,.11,.084),(.02,-.12,.055))):
        cylinder(f"Scrap_Bolt_{i}", .015, .018, p, dark, 10, bevel=.002)


def build_metal_plate():
    metal = mat("Item Metal", (.32, .34, .33), .78, .58)
    dark = mat("Item Dark Metal")
    box("Plate", (.44, .34, .025), (0, 0, .0125), metal, .008)
    for i, (x, y) in enumerate(((-.19,-.14),(.19,-.14),(-.19,.14),(.19,.14),
                                (0,-.14),(0,.14),(-.19,0),(.19,0))):
        cylinder(f"Plate_Bolt_{i}", .010, .008, (x,y,.029), dark, 10, bevel=.002)


def build_dirty_water():
    plastic = mat("Item Plastic", (.33, .27, .15), .0, .42)
    glass = mat("Item Glass", (.30, .24, .12), .02, .25)
    dark = mat("Item Dark Metal", (.12, .08, .035), .20, .75)
    box("Jug_Body", (.22, .18, .25), (0, 0, .125), glass, .035)
    cone("Jug_Shoulder", .105, .060, .070, (0,0,.285), glass, 16)
    cylinder("Jug_Neck", .040, .045, (0,0,.342), plastic, 16, bevel=.004)
    cylinder("Dirty_Cap", .046, .022, (0,0,.375), dark, 16, bevel=.003)
    torus("Jug_Handle", .055, .014, (.090,0,.285), plastic, 18, 6,
          rotation=(deg(90),0,0), scale=(.70,1,1))
    for z in (.07,.12,.17,.22):
        torus("Jug_Rib", .094, .004, (0,0,z), plastic, 18, 4)


def build_clean_water():
    glass = mat("Item Glass", (.48, .72, .85), .01, .13)
    plastic = mat("Item Plastic", (.10, .35, .64), .0, .40)
    lathe("Bottle", [(0,.043),(.018,.050),(.055,.052),(.19,.047),(.23,.035),
                      (.255,.018),(.29,.018)], glass, 20)
    cylinder("Water_Cap", .021, .024, (0,0,.302), plastic, 18, bevel=.002)
    for z in (.065,.10,.14,.18):
        torus("Grip_Rib", .048, .0025, (0,0,z), glass, 20, 4)


def build_soda():
    red = mat("Item Red Paint", (.74, .025, .018), .32, .46)
    metal = mat("Item Metal", (.52, .54, .52), .80, .32)
    label = mat("Item Label", (.92, .78, .58), .0, .62)
    cylinder("Crushed_Can", .033, .112, (0,0,.056), red, 24, bevel=.004)
    cylinder("Top_Rim", .035, .008, (0,0,.116), metal, 24, bevel=.0015)
    cylinder("Bottom_Rim", .035, .007, (0,0,.0035), metal, 24, bevel=.0015)
    box("Soda_Stripe", (.004,.067,.045), (-.034,0,.063), label, .001)
    torus("Pull_Tab", .009, .002, (0,-.004,.121), metal, 12, 4, scale=(.55,1,1))


def build_chips():
    plastic = mat("Item Plastic", (.78, .55, .035), .0, .58)
    label = mat("Item Label", (.67, .075, .025))
    points = [(-.10,-.045),(.09,-.050),(.105,-.020),(.095,.045),(-.085,.050),(-.11,.018)]
    flat_prism("Crinkled_Bag", points, .008, .055, plastic)
    box("Chip_Label", (.135,.065,.007), (0,-.005,.060), label, .004)
    seam_boxes("Bag_Crinkle", [(-.075,y,.063) for y in (-.035,-.010,.025)] +
               [(.075,y,.063) for y in (-.025,.010,.035)], (.045,.008,.008), plastic)


def build_canned_food():
    metal = mat("Item Metal", (.31,.30,.26), .76, .52)
    paper = mat("Item Paper", (.62,.55,.41))
    label = mat("Item Label", (.46,.30,.12))
    cylinder("Food_Can", .050, .125, (0,0,.0625), metal, 24, bevel=.003)
    cylinder("Paper_Label", .051, .072, (0,0,.066), paper, 24)
    box("Can_Label_Band", (.004,.104,.025), (-.052,0,.066), label, .002)
    for z in (.005,.122):
        torus("Can_Rim", .049, .003, (0,0,z), metal, 24, 4)


def build_seeds():
    paper = mat("Item Paper", (.58,.39,.20))
    label = mat("Item Label", (.26,.42,.12))
    food = mat("Item Food", (.44,.33,.16))
    flat_prism("Seed_Packet", [(-.11,-.075),(.10,-.07),(.115,.06),(-.09,.075)],
               .008, .032, paper)
    box("Seed_Label", (.10,.075,.005), (-.01,-.005,.035), label, .004)
    for i in range(10):
        sphere(f"Seed_{i}", (-.12 + .025*i, -.105 + .014*(i%3), .012),
               (.010,.005,.004), food, 10, 5)


def build_vegetable():
    food = mat("Item Food", (.76,.22,.025))
    leaf = mat("Item Label", (.12,.38,.035))
    for i, (x,y,a) in enumerate(((-.10,-.02,-18),(0,.035,7),(.105,-.025,22))):
        cone(f"Carrot_{i}", .032, .006, .22, (x,y,.075), food, 14,
             rotation=(0,deg(78),deg(a)))
        for j in range(3):
            tube_between(f"Leaf_{i}_{j}", (x-.09*math.cos(deg(a)), y, .105),
                         (x-.15*math.cos(deg(a))+j*.02, y+.035*(j-1), .145+j*.006),
                         .007, leaf, 8)


def build_rotten_food():
    food = mat("Item Food", (.24,.20,.075))
    mould = mat("Item Label", (.22,.34,.11))
    for i, (p,s) in enumerate((((-.07,0,.055),(.10,.08,.055)),
                               ((.055,.015,.06),(.11,.09,.06)),
                               ((0,-.06,.09),(.09,.07,.075)))):
        sphere(f"Rotten_Lump_{i}", p, s, food, 14, 7)
    for i, p in enumerate(((-.08,-.045,.105),(-.01,.03,.14),(.07,-.02,.115),(.10,.04,.08))):
        sphere(f"Mould_{i}", p, (.025,.018,.010), mould, 10, 5)


def build_bandage():
    cloth = mat("Item Cloth", (.78,.74,.65))
    paper = mat("Item Paper", (.43,.29,.16))
    cylinder("Bandage_Roll", .052, .14, (-.045,0,.055), cloth, 24,
             rotation=(0,deg(90),0), bevel=.003)
    cylinder("Roll_Core", .017, .143, (-.045,0,.055), paper, 16,
             rotation=(0,deg(90),0))
    box("Loose_Bandage", (.145,.11,.018), (.092,.015,.014), cloth, .007,
        (0,deg(-4),deg(6)))
    for x in (-.10,-.055,-.01):
        torus("Bandage_Ridge", .052, .0025, (x,0,.055), cloth, 20, 4,
              rotation=(0,deg(90),0))


def backpack_body(kind, size, color):
    cloth = mat("Item Cloth", color)
    leather = mat("Item Leather", (.19,.11,.055))
    dark = mat("Item Dark Metal")
    w, d, h = size
    box("Pack_Body", (w,d,h), (0,0,h/2), cloth, min(w,d)*.16)
    box("Front_Pocket", (w*.58,d*.18,h*.30), (0,-d*.55,h*.32), cloth, .018)
    for x in (-w*.31,w*.31):
        box("Shoulder_Strap", (w*.13,.025,h*.72), (x,d*.54,h*.50), leather, .009)
        cylinder("Buckle", .014, .012, (x,-d*.61,h*.31), dark, 10,
                 rotation=(deg(90),0,0), bevel=.002)
    torus("Carry_Handle", w*.16, .012, (0,0,h+.015), leather, 16, 6,
          rotation=(deg(90),0,0), scale=(1,.55,1))
    if kind in ("hiking", "military"):
        for x in (-w*.51,w*.51):
            box("Side_Pouch", (w*.22,d*.75,h*.34), (x,0,h*.35), cloth, .015)
        cylinder("Bed_Roll", d*.32, w*.78, (0,.02,h+.035), cloth, 16,
                 rotation=(0,deg(90),0), bevel=.006)
    if kind == "military":
        for z in (h*.25,h*.48,h*.70):
            box("Webbing", (w*.86,.012,.025), (0,-d*.53,z), leather, .005)


def build_school_bag(): backpack_body("school", (.36,.18,.44), (.06,.16,.38))
def build_hiking_pack(): backpack_body("hiking", (.39,.28,.54), (.55,.20,.045))
def build_military_rucksack(): backpack_body("military", (.43,.31,.59), (.17,.23,.11))


def build_gas_can():
    red = mat("Item Red Paint", (.63,.025,.018), .32, .66)
    dark = mat("Item Dark Metal")
    box("Jerry_Can", (.34,.16,.41), (0,0,.205), red, .028)
    box("Handle_Cutout", (.17,.18,.075), (0,0,.405), dark, .018)
    box("Handle_Top", (.20,.075,.035), (0,0,.463), red, .012)
    cylinder("Spout", .035, .095, (.125,0,.445), dark, 16,
             rotation=(0,deg(20),0), bevel=.004)
    for angle in (35,-35):
        box("Stamped_X", (.25,.015,.027), (0,-.085,.22), red, .004,
            (0,deg(angle),0))


def build_repair_kit():
    red = mat("Item Red Paint", (.52,.028,.018), .45, .61)
    dark = mat("Item Dark Metal")
    rubber = mat("Item Rubber")
    box("Toolbox_Base", (.40,.23,.13), (0,0,.065), red, .018)
    box("Toolbox_Lid", (.40,.23,.055), (0,0,.157), red, .018)
    box("Toolbox_Seam", (.405,.012,.015), (0,-.121,.13), dark, .003)
    torus("Toolbox_Handle", .075,.012,(0,0,.215),dark,18,6,
          rotation=(deg(90),0,0),scale=(1,.55,1))
    for x in (-.13,.13):
        box("Latch", (.045,.018,.055), (x,-.125,.13), dark, .006)
    box("Rubber_Grip", (.11,.024,.025), (0,-.13,.16), rubber, .006)


def build_ammo_casing():
    brass = mat("Item Brass")
    for i in range(10):
        angle = deg(-55 + i*23)
        x = -.10 + (i%5)*.05
        y = -.045 + (i//5)*.075
        cylinder(f"Casing_{i}", .011, .065, (x,y,.018), brass, 10,
                 rotation=(0,deg(78),angle), bevel=.0015)
        torus(f"Casing_Rim_{i}", .011,.002,(x-.030*math.cos(angle),
              y-.030*math.sin(angle),.019),brass,10,4,rotation=(0,deg(78),angle))


def ammo_box(kind, box_material, box_color, label_color):
    case = mat(box_material, box_color)
    label = mat("Item Label", label_color)
    brass = mat("Item Brass")
    dark = mat("Item Dark Metal")
    box("Ammo_Box", (.25,.19,.115), (0,0,.0575), case, .012)
    box("Ammo_Label", (.14,.006,.065), (0,-.098,.064), label, .004)
    box("Ammo_Lid_Seam", (.255,.012,.012), (0,-.098,.108), dark, .002)
    for i in range(4):
        x = -.09 + i*.06
        cylinder(f"Round_{i}", .009,.072,(x,-.122,.035),brass,10,
                 rotation=(deg(90),0,0),bevel=.001)
        cone(f"Round_Tip_{i}",.009,.002,.023,(x,-.169,.035),brass,10,
             rotation=(deg(90),0,0))
    # Kind-specific top mark makes the silhouettes readable even under neutral game tinting.
    if kind == "subsonic":
        box("Subsonic_Band", (.19,.008,.018), (0,-.101,.089), label, .003)
    elif kind == "ap":
        for x in (-.065,0,.065):
            cone("AP_Mark",.014,0,.024,(x,-.105,.092),label,10,
                 rotation=(deg(90),0,0))


def build_ammo_standard(): ammo_box("standard", "Item Cardboard", (.50,.34,.17), (.82,.64,.16))
def build_ammo_subsonic(): ammo_box("subsonic", "Item Dark Metal", (.13,.19,.12), (.12,.38,.62))
def build_ammo_ap(): ammo_box("ap", "Item Dark Metal", (.10,.10,.095), (.65,.035,.025))


def build_bolt():
    wood = mat("Item Wood", (.26,.18,.095))
    metal = mat("Item Metal", (.32,.35,.35), .78, .40)
    paper = mat("Item Paper", (.45,.16,.07))
    rubber = mat("Item Rubber")
    for i in range(5):
        y = -.05 + i*.025
        tube_between(f"Bolt_Shaft_{i}", (-.17,y,.026), (.15,y,.026), .0045, wood, 8)
        cone(f"Bolt_Head_{i}", .012, 0, .035, (.17,y,.026), metal, 10,
             rotation=(0,deg(90),0))
        flat_prism(f"Fletching_{i}", [(-.17,y-.012),(-.12,y-.012),(-.135,y),(-.17,y)],
                   .021,.036,paper)
    for x in (-.07,.07):
        cylinder("Bundle_Tie", .052,.014,(x,0,.027),rubber,16,
                 rotation=(0,deg(90),0),bevel=.002)


def build_shells():
    card = mat("Item Cardboard", (.43,.28,.13))
    plastic = mat("Item Plastic", (.63,.025,.018))
    brass = mat("Item Brass")
    label = mat("Item Label", (.78,.68,.42))
    box("Shell_Box",(.25,.18,.105),(0,.015,.0525),card,.012)
    box("Shell_Label",(.13,.006,.060),(0,-.078,.058),label,.004)
    for i in range(5):
        x=-.10+i*.05
        cylinder(f"Shell_{i}",.013,.080,(x,-.105,.028),plastic,12,
                 rotation=(deg(90),0,0),bevel=.002)
        cylinder(f"Shell_Brass_{i}",.014,.018,(x,-.145,.028),brass,12,
                 rotation=(deg(90),0,0),bevel=.001)


def build_gunpowder():
    metal=mat("Item Metal",(.25,.24,.21),.70,.58)
    dark=mat("Item Dark Metal")
    label=mat("Item Label",(.68,.46,.14))
    cylinder("Powder_Tin",.080,.095,(0,0,.0475),metal,24,bevel=.004)
    cylinder("Tin_Lid",.083,.018,(0,0,.104),dark,24,bevel=.003)
    cylinder("Powder_Label",.081,.050,(0,0,.055),label,24)
    for i in range(5):
        sphere(f"Powder_Grain_{i}",(-.04+i*.02,-.085,.008),(.007,.004,.004),dark,8,4)


def build_wall_panel():
    metal=mat("Item Metal",(.39,.40,.37),.72,.64)
    dark=mat("Item Dark Metal")
    box("Wall_Panel",(.62,.52,.030),(0,0,.015),metal,.008)
    for angle in (36,-36):
        box("Panel_Brace",(.52,.030,.025),(0,0,.045),dark,.004,(0,0,deg(angle)))
    for i,(x,y) in enumerate(((-.27,-.22),(.27,-.22),(-.27,.22),(.27,.22),(0,-.22),(0,.22))):
        cylinder(f"Panel_Bolt_{i}",.012,.010,(x,y,.050),dark,10,bevel=.002)


def build_radio():
    plastic=mat("Item Plastic",(.075,.095,.075),.0,.78)
    rubber=mat("Item Rubber")
    dark=mat("Item Dark Metal")
    glass=mat("Item Glass",(.10,.30,.24),.03,.20)
    box("Radio_Body",(.14,.245,.055),(0,0,.0275),plastic,.018)
    box("Radio_Screen",(.065,.042,.007),(-.015,.060,.058),glass,.004)
    for y in (-.085,-.065,-.045,-.025,-.005):
        box("Speaker_Slot",(.075,.008,.007),(.015,y,.058),dark,.002)
    tube_between("Antenna",(-.045,.105,.055),(-.045,.270,.065),.010,rubber,12)
    cylinder("Channel_Knob",.014,.024,(.040,.112,.062),dark,12,bevel=.002)
    box("Push_To_Talk",(.016,.060,.014),(-.078,.015,.038),rubber,.004)


def build_hard_hat():
    plastic=mat("Item Plastic",(.92,.56,.015),.0,.54)
    rubber=mat("Item Rubber")
    lathe("Helmet_Dome",[(.025,.14),(.055,.165),(.105,.155),(.155,.125),(.19,.06),(.205,.01)],
          plastic,24)
    flat_prism("Helmet_Brim",[(-.18,-.13),(.18,-.13),(.17,.12),(-.17,.12)],.018,.045,plastic)
    for x in (-.09,0,.09):
        box("Helmet_Rib",(.022,.21,.022),(x,0,.195),plastic,.006)
    box("Suspension",(.24,.12,.018),(0,.02,.025),rubber,.006)


def build_cap():
    cloth=mat("Item Cloth",(.055,.075,.105))
    sphere("Cap_Crown",(0,.025,.105),(.145,.125,.105),cloth,20,10)
    flat_prism("Cap_Brim",[(-.13,-.22),(.13,-.22),(.16,-.08),(-.16,-.08)],.018,.040,cloth)
    cylinder("Cap_Button",.012,.010,(0,.025,.215),cloth,12,bevel=.002)
    for angle in (-55,-25,0,25,55):
        box("Cap_Seam",(.006,.14,.007),(0,.025,.196),cloth,.002,(0,deg(angle),0))


def folded_top(name, width, depth, cloth, collar=False):
    flat_prism(name,[(-width*.46,-depth*.48),(width*.46,-depth*.48),(width*.50,depth*.18),
                     (width*.34,depth*.48),(-width*.34,depth*.48),(-width*.50,depth*.18)],
               .008,.052,cloth)
    box("Folded_Sleeve_L",(width*.22,depth*.62,.030),(-width*.36,.02,.065),cloth,.010,
        (0,0,deg(-8)))
    box("Folded_Sleeve_R",(width*.22,depth*.62,.030),(width*.36,.02,.065),cloth,.010,
        (0,0,deg(8)))
    if collar:
        flat_prism("Collar",[(-.12,.16),(0,.06),(.12,.16),(.08,.22),(-.08,.22)],.055,.080,cloth)


def build_hi_vis_vest():
    hi=mat("Item Hi-Vis")
    label=mat("Item Label",(.72,.74,.70),.05,.48)
    folded_top("Folded_Vest",.40,.44,hi,True)
    for y in (-.08,.04):
        box("Reflective_Band",(.38,.035,.012),(0,y,.068),label,.004)
    box("Vest_Centre",(.025,.36,.012),(0,0,.070),label,.004)


def build_jacket():
    cloth=mat("Item Cloth",(.14,.095,.060))
    dark=mat("Item Dark Metal")
    leather=mat("Item Leather",(.24,.13,.065))
    folded_top("Folded_Jacket",.45,.48,cloth,True)
    box("Jacket_Zip",(.018,.34,.015),(0,-.04,.070),dark,.003)
    for x in (-.12,.12):
        box("Jacket_Pocket",(.12,.12,.020),(x,-.08,.069),leather,.007)
        cylinder("Jacket_Snap",.006,.006,(x,-.145,.083),dark,8,bevel=.001)


def glove(prefix, x, y, angle, leather):
    sphere(f"{prefix}_Palm",(x,y,.035),(.085,.070,.032),leather,14,7)
    box(f"{prefix}_Cuff",(.13,.075,.045),(x,y+.105,.030),leather,.012,(0,0,angle))
    for i in range(4):
        xx=x-.050+i*.033
        tube_between(f"{prefix}_Finger_{i}",(xx,y-.045,.034),(xx+(i-1.5)*.008,y-.135+.012*abs(i-1.5),.030),
                     .014,leather,10)
    tube_between(f"{prefix}_Thumb",(x-.066,y-.015,.035),(x-.105,y-.080,.028),.018,leather,10)


def build_work_gloves():
    leather=mat("Item Leather",(.34,.19,.09))
    glove("Left",-.105,.035,deg(-8),leather)
    glove("Right",.105,.015,deg(8),leather)


def folded_pants(cargo=False):
    cloth=mat("Item Cloth",(.25,.16,.085) if not cargo else (.18,.24,.12))
    dark=mat("Item Dark Metal")
    box("Folded_Waist",(.39,.20,.055),(0,.14,.0275),cloth,.014)
    box("Folded_Legs",(.37,.31,.060),(0,-.105,.032),cloth,.014)
    box("Hem",(.38,.040,.020),(0,-.265,.067),cloth,.006)
    for x in (-.15,-.075,0,.075,.15):
        box("Belt_Loop",(.022,.020,.018),(x,.235,.065),dark,.003)
    for x in (-.12,.12):
        box("Pocket",(.12,.12,.022),(x,-.08,.072),cloth,.008)
        cylinder("Pocket_Snap",.006,.006,(x,-.14,.085),dark,8,bevel=.001)
    if cargo:
        for x in (-.15,.15):
            box("Cargo_Pocket",(.13,.14,.035),(x,-.04,.079),cloth,.009)


def build_work_pants(): folded_pants(False)
def build_cargo_pants(): folded_pants(True)


def boot(prefix,x,leather):
    rubber=mat("Item Rubber")
    dark=mat("Item Dark Metal")
    box(f"{prefix}_Sole",(.18,.31,.035),(x,-.035,.018),rubber,.012)
    sphere(f"{prefix}_Toe",(x,-.14,.085),(.088,.11,.070),leather,14,7)
    box(f"{prefix}_Upper",(.17,.17,.20),(x,.055,.12),leather,.025)
    box(f"{prefix}_Tongue",(.075,.14,.025),(x,-.005,.215),dark,.008,(0,deg(-12),0))
    for i in range(4):
        box(f"{prefix}_Lace_{i}",(.12,.010,.007),(x,-.065+i*.030,.226-i*.010),dark,.002)
    for y in (-.14,-.07,0,.07):
        box(f"{prefix}_Tread",(.16,.025,.010),(x,y,.001),rubber,.002)


def build_work_boots():
    leather=mat("Item Leather",(.28,.13,.045))
    boot("Left",-.115,leather); boot("Right",.115,leather)


def sneaker(prefix,x,cloth):
    rubber=mat("Item Rubber",(.18,.18,.17))
    label=mat("Item Label",(.62,.64,.62))
    box(f"{prefix}_Sole",(.20,.31,.030),(x,-.03,.015),rubber,.012)
    sphere(f"{prefix}_Toe",(x,-.14,.065),(.096,.115,.050),cloth,14,7)
    box(f"{prefix}_Heel",(.18,.13,.115),(x,.07,.070),cloth,.025)
    box(f"{prefix}_Side_Stripe",(.012,.20,.040),(x-.097,-.02,.075),label,.004)
    for i in range(4):
        box(f"{prefix}_Lace_{i}",(.13,.010,.006),(x,-.075+i*.030,.125-i*.005),label,.002)


def build_sneakers():
    cloth=mat("Item Cloth",(.075,.115,.16))
    sneaker("Left",-.125,cloth); sneaker("Right",.125,cloth)


def build_headlamp():
    rubber=mat("Item Rubber",(.035,.035,.032))
    plastic=mat("Item Plastic",(.16,.17,.17))
    glass=mat("Item Glass",(.70,.72,.58),.05,.12)
    label=mat("Item Label",(.85,.22,.035))
    torus("Head_Strap",.125,.014,(0,.015,.026),rubber,28,8,scale=(1,.75,1))
    box("Lamp_Housing",(.105,.065,.070),(0,-.105,.060),plastic,.015)
    cylinder("Lamp_Lens",.032,.012,(0,-.142,.063),glass,20,
             rotation=(deg(90),0,0),bevel=.002)
    for x in (-.045,.045):
        box("Orange_Clip",(.018,.020,.045),(x,-.135,.060),label,.004)


BUILDERS = {item_id: globals()[f"build_{item_id}"] for item_id in ITEM_IDS}


def build_one(item_id):
    assert item_id in BUILDERS, f"unknown item {item_id}"
    reset()
    BUILDERS[item_id]()
    finish(f"item_{item_id}", BOXES[item_id], max_triangles=3000)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_contact():
    reset()
    cols = 7
    cell_x, cell_y = 1.18, 1.08
    for index, item_id in enumerate(ITEM_IDS):
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets" / "models" / f"item_{item_id}.glb"))
        objects = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
        points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
        lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        dims = hi - lo
        scale = min(.72 / max(dims.x, dims.y), .55 / dims.z)
        col, row = index % cols, index // cols
        x = (col - (cols - 1) / 2) * cell_x
        y = ((len(ITEM_IDS) - 1) // cols / 2 - row) * cell_y
        centre = (lo + hi) / 2
        for obj in objects:
            obj.scale *= scale
            obj.location = (obj.location - centre) * scale + Vector((x, y+.06, dims.z*scale/2+.035))
        bpy.ops.object.text_add(location=(x, y-.39, .018))
        text_obj = bpy.context.object
        text_obj.name = f"Caption_{item_id}"
        text_obj.data.body = item_id.replace("_", " ")
        text_obj.data.align_x = "CENTER"
        text_obj.data.align_y = "CENTER"
        text_obj.data.size = .105
        text_obj.data.extrude = .001
        text_obj.data.materials.append(material(f"Preview Text {index}", (.78,.81,.82), 0, .8))

    bpy.ops.mesh.primitive_plane_add(size=20, location=(0,0,0))
    board = bpy.context.object
    board.name = "Preview_Backdrop"
    board.data.materials.append(material("Preview Backdrop", (.025,.032,.037), 0, .88))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 3000
    scene.render.resolution_y = 2200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (.012,.016,.020)
    camera_data = bpy.data.cameras.new("Contact_Camera")
    camera = bpy.data.objects.new("Contact_Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 11.5
    camera.location = (0.0,-7.0,24.0)
    look_at(camera,(0,0,0))
    for name, loc, energy, size in (("Key",(-4,-5,10),1800,6.0),
                                    ("Fill",(6,-1,7),1100,5.0),
                                    ("Rim",(0,7,9),1400,4.0)):
        data=bpy.data.lights.new(name,"AREA")
        data.energy=energy; data.shape="DISK"; data.size=size
        light=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(light)
        light.location=loc; look_at(light,(0,0,0))
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.filepath = str(Path(__file__).resolve().parent / "item_props_contact.png")
    bpy.ops.render.render(write_still=True)
    print("CONTACT", scene.render.filepath)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
target = args[0] if args else "all"
if target == "all":
    for requested_id in ITEM_IDS:
        build_one(requested_id)
elif target == "contact":
    render_contact()
else:
    build_one(target)
