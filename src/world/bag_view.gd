class_name BagView
extends Node3D
## Draws what lies on the ground: the bags you dropped when you died (walk back and pick them up, E), and since
## V34 (Emmitt: "skins for the items dropped, also allow placing items") everything you dropped or placed, as
## itself: a can as a can, a rifle on its side, a jacket folded flat, turned the way it was put down, with a
## small stack shown as up to three. Models come from the weapon, gun and part models, the two throwables and
## the item props (tools/art/item_props.py -> assets/models/item_<id>.glb); anything without one shows its
## picture on a card.

## The item props' materials, textured by name (object-space triplanar, like the guns); a material that isn't
## listed keeps the colour it was made with.
const ITEM_LOOKS := {
	"Item Metal": {"texture": "gun_metal", "tile_m": 0.12, "metallic": 0.5, "roughness": 0.55},
	"Item Dark Metal": {"texture": "gun_metal", "tile_m": 0.12, "metallic": 0.4, "roughness": 0.6},
	"Item Brass": {"texture": "gun_metal", "tile_m": 0.06, "metallic": 0.8, "roughness": 0.35},
	"Item Wood": {"texture": "gun_wood", "tile_m": 0.3},
	"Item Cloth": {"texture": "cloth_cotton", "tile_m": 0.12, "metallic": 0.0, "roughness": 0.95},
	"Item Hi-Vis": {"texture": "cloth_workshirt", "tile_m": 0.15, "metallic": 0.0, "roughness": 0.9},
	"Item Denim": {"texture": "denim", "tile_m": 0.15, "metallic": 0.0, "roughness": 0.95},
	"Item Leather": {"texture": "leather_boot", "tile_m": 0.1, "metallic": 0.0, "roughness": 0.8},
	"Item Rubber": {"texture": "gun_polymer", "tile_m": 0.08, "metallic": 0.0, "roughness": 0.9},
	"Item Plastic": {"texture": "gun_polymer", "tile_m": 0.1, "metallic": 0.0, "roughness": 0.6},
	"Item Red Paint": {"texture": "car_paint", "tile_m": 0.3, "metallic": 0.2, "roughness": 0.5},
}
const BAG_LOOK := "military_rucksack"  # a death bag looks like a dropped rucksack
const MAX_SHOWN := 3
const MIN_BOX := 0.14  # the look ray's box is at least this big, so a box of nails is easy to point at

var sim: SimWorld
var _bodies: Dictionary = {}  # id -> StaticBody3D
var _shown: Dictionary = {}   # id -> what it was drawn as (look and count), to redraw a stack that changed


func setup(p_sim: SimWorld) -> void:
	sim = p_sim


func _process(_delta: float) -> void:
	var live := {}
	for bag: Dictionary in sim.bags:
		var id: int = bag["id"]
		live[id] = true
		var shown := "%s:%d" % [SimWorld.lying_look(bag), _count(bag)]
		if _bodies.has(id) and _shown.get(id, "") != shown:
			_bodies[id].queue_free()
			_bodies.erase(id)
		if not _bodies.has(id):
			_bodies[id] = _make(bag)
			_shown[id] = shown
	for id: int in _bodies.keys():
		if not live.has(id):
			_bodies[id].queue_free()
			_bodies.erase(id)
			_shown.erase(id)


static func _count(bag: Dictionary) -> int:
	var n := (bag["gear"] as Array).size()
	for item: String in bag["items"]:
		n += int(bag["items"][item])
	return n


## The model file for `look` (an item id or a gear base), or "" when there is none.
static func model_path(look: String) -> String:
	var paths: Array[String] = []
	if Shooter.MODELS.has(look):
		paths.append(Shooter.MODELS[look])
	if Shooter.PART_MODELS.has(look):
		paths.append(Shooter.PART_MODELS[look])
	if Melee.MODELS.has(look):
		paths.append(Melee.MODELS[look])
	paths.append("res://assets/models/item_%s.glb" % look)
	paths.append("res://assets/models/%s.glb" % look)  # the bottle and the pipe bomb
	for path: String in paths:
		if ResourceLoader.exists(path):
			return path
	return ""


## `look` as it lies on a floor: textured, resting on y = 0 and centred over the origin. Melee weapons lie
## flat, guns on their side; the item props were built lying already. Without a model: its picture on a card.
static func make_model(look: String) -> Node3D:
	var path := model_path(look)
	var inner: Node3D
	if path == "":
		inner = _card(look)
	else:
		inner = (load(path) as PackedScene).instantiate() as Node3D
		if Shooter.MODELS.has(look) or Shooter.PART_MODELS.has(look):
			Shooter.apply_textured_materials(inner)
		elif Melee.MODELS.has(look):
			Melee.apply_weapon_materials(inner)
		else:
			_apply_item_materials(inner)
		if Melee.MODELS.has(look):
			# It points up its +Y with its striking side to -Z: lay it along the floor on its flat side (V38: on its
			# striking side, an axe or a blade balanced on its edge), so the side of an axe head faces up.
			inner.basis = Basis(Vector3.UP, Vector3.FORWARD, Vector3.LEFT)
		elif Shooter.MODELS.has(look):
			inner.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))  # on its side
	var root := Node3D.new()
	root.name = "Look"
	root.add_child(inner)
	var box := bounds(root)
	inner.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## The box around every mesh under `root`, in root's space.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != null and node != root:
			if node is Node3D:
				xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _apply_item_materials(node: Node3D) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null or not ITEM_LOOKS.has(source.resource_name):
				continue
			var m: Dictionary = ITEM_LOOKS[source.resource_name]
			mi.set_surface_override_material(i, Shooter._gun_material(source, String(m["texture"]), float(m["tile_m"]),
					source.albedo_color, m))


## A picture card lying flat, for anything without a model yet.
static func _card(look: String) -> Node3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	quad.orientation = PlaneMesh.FACE_Y
	mesh.mesh = quad
	mesh.position.y = 0.005
	var mat := StandardMaterial3D.new()
	var icon := "res://assets/icons/%s.png" % look
	if ResourceLoader.exists(icon):
		mat.albedo_texture = load(icon)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	else:
		mat.albedo_color = Color(0.5, 0.32, 0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	return mesh


func _make(bag: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.BAG
	body.collision_mask = 0
	body.set_meta("bag_id", bag["id"])
	var item: bool = bag.get("kind", SimWorld.BAG) == SimWorld.ITEM
	var look := SimWorld.lying_look(bag)
	var model := make_model(look if item else BAG_LOOK)
	if not item:
		model.scale = Vector3.ONE * 1.4  # a stuffed death bag
	body.add_child(model)
	var box := bounds(model)
	var count := mini(_count(bag), MAX_SHOWN) if item and (bag["gear"] as Array).is_empty() else 1
	for i in range(1, count):  # a small stack: side by side
		var copy := make_model(look)
		copy.position.x = (box.size.x + 0.02) * i
		body.add_child(copy)
		var cb := bounds(copy)
		box = box.merge(AABB(copy.position + cb.position, cb.size))
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size.max(Vector3.ONE * MIN_BOX)
	shape.shape = box_shape
	shape.position = box.get_center()
	body.add_child(shape)
	body.position = bag["pos"]
	body.rotation.y = float(bag.get("yaw", 0.0))
	add_child(body)
	return body
