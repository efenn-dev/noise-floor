class_name CountryView
extends Node3D
## W3a: draws the countryside (CountryPlan): every tree from one MultiMesh (a thousand trees in one draw per
## leaf colour) with its trunk as a collider (so you, zombies and the navmesh go round them), the highway's
## wrecked cars as solid props, and an invisible wall round the map's edge behind the tree belt. Leaves take the
## season's colours like the town's trees (apply_season). No rules live here.

const TRUNK := Vector2(0.28, 2.6)  # radius and height of a scale-1 trunk collider (StreetPlan.COLLIDERS "tree")
const WRECK_MODELS := {"sedan": "res://assets/models/sedan.glb", "pickup": "res://assets/models/pickup.glb"}
const WRECK_BOXES := {"sedan": Vector3(1.9, 1.5, 4.4), "pickup": Vector3(2.0, 1.85, 5.2)}  # data/vehicles.json sizes
const WALL_HEIGHT := 6.0
## How each kind is solid: "trunk" (a thin cylinder), "box" (its model's box), or not at all (bushes).
const COLLIDE := {"tree": "trunk", "pine_tree": "trunk", "pine_tree_small": "trunk", "rock": "box",
		"guardrail": "box", "concrete_barrier": "box", "road_sign": "box", "farm_fence": "box",
		"hay_bale_round": "box", "hay_bale_square": "box", "water_trough": "box"}  # W3d: the farmyards (corn you walk through)
## The props' materials (Codex's tools/art/world_props.py), textured by name like the guns; others keep their colour.
const PROP_LOOKS := {
	"Prop Metal": {"texture": "gun_metal", "tile_m": 0.3, "metallic": 0.5, "roughness": 0.55},
	"Prop Painted Metal": {"texture": "car_paint", "tile_m": 0.5, "metallic": 0.3, "roughness": 0.5},
	"Prop Rust": {"texture": "car_paint", "tile_m": 0.4, "metallic": 0.1, "roughness": 0.85},
	"Prop Wood": {"texture": "gun_wood", "tile_m": 0.5},
	"Prop Bark": {"texture": "gun_wood", "tile_m": 0.4, "metallic": 0.0, "roughness": 0.95},
	"Prop Concrete": {"texture": "concrete_floor", "tile_m": 1.0, "metallic": 0.0, "roughness": 0.9},
	"Prop Rock": {"texture": "concrete_floor", "tile_m": 0.8, "metallic": 0.0, "roughness": 0.95},
	"Prop Fabric": {"texture": "cloth_cotton", "tile_m": 0.3, "metallic": 0.0, "roughness": 0.95},
}

var plan: Dictionary
var trees: MultiMeshInstance3D
var _tree_mesh: Mesh  # our own copy, so the season can recolour its leaves
var _leaf_materials: Dictionary = {}  # surface index -> original material


## W3d: `edge_wall` false for a second CountryView that only scatters (the farms' corn, fences and hay).
func setup(p_plan: Dictionary, edge_wall: bool = true) -> void:
	plan = p_plan
	var by_kind := {}
	for t: Dictionary in plan.get("trees", []):
		var kind := str(t.get("kind", "tree"))
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(t)
	for p: Dictionary in plan.get("props", []):
		if not by_kind.has(p["kind"]):
			by_kind[p["kind"]] = []
		(by_kind[p["kind"]] as Array).append(p)
	for kind: String in by_kind:
		_scatter(kind, by_kind[kind])
	_add_wrecks(plan.get("wrecks", []))
	if edge_wall:
		_add_edge_wall()


## The box round every mesh under `root`, in root's space.
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


## Every `kind` in `list` from one MultiMesh, standing on the ground, each with its collider (COLLIDE).
func _scatter(kind: String, list: Array) -> void:
	var path := "res://assets/models/%s.glb" % kind
	if list.is_empty() or not ResourceLoader.exists(path):
		return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var box := bounds(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var source := meshes[0] as MeshInstance3D
	var local := source.transform
	var mesh: Mesh = source.mesh.duplicate()
	model.free()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as StandardMaterial3D
		if mat == null:
			continue
		if mat.resource_name in ["Leaves", "Leaves Dark"] and kind == "tree":
			_leaf_materials[s] = mat
		elif PROP_LOOKS.has(mat.resource_name):
			var m: Dictionary = PROP_LOOKS[mat.resource_name]
			mesh.surface_set_material(s, Shooter._gun_material(mat, String(m["texture"]), float(m["tile_m"]), mat.albedo_color, m))
	if kind == "tree":
		_tree_mesh = mesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	var body := StaticBody3D.new()
	body.name = "Solid_" + kind
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var collide: String = COLLIDE.get(kind, "")
	for i in list.size():
		var it: Dictionary = list[i]
		var sc := float(it.get("scale", 1.0))
		var basis := Basis(Vector3.UP, float(it["yaw"])).scaled(Vector3.ONE * sc)
		var at: Vector3 = (it["pos"] as Vector3) + Vector3(0, -box.position.y * sc, 0)  # kit models are centred on their box
		mm.set_instance_transform(i, Transform3D(basis, at) * local)
		if collide == "":
			continue
		var cs := CollisionShape3D.new()
		if collide == "trunk":
			var cyl := CylinderShape3D.new()
			cyl.radius = TRUNK.x * sc
			cyl.height = TRUNK.y * sc
			cs.shape = cyl
			cs.position = (it["pos"] as Vector3) + Vector3(0, cyl.height / 2.0, 0)
		else:
			var shape := BoxShape3D.new()
			shape.size = box.size * sc
			cs.shape = shape
			cs.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), (it["pos"] as Vector3) + Vector3(0, box.size.y * sc / 2.0, 0))
		body.add_child(cs)
	var multi := MultiMeshInstance3D.new()
	multi.name = "Country_" + kind
	multi.multimesh = mm
	add_child(multi)
	if kind == "tree":
		trees = multi
	if body.get_child_count() > 0:
		add_child(body)
	else:
		body.free()


func _add_wrecks(list: Array) -> void:
	for w: Dictionary in list:
		var type := str(w["type"])
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = w["pos"]
		body.rotation.y = float(w["yaw"])
		if w.has("id"):
			body.set_meta("container_id", w["id"])  # W3d: E searches its trunk
		if ResourceLoader.exists(WRECK_MODELS.get(type, "")):
			var model := (load(WRECK_MODELS[type]) as PackedScene).instantiate() as Node3D
			model.rotation.y = PI  # the car models face -Z like everything else; a wreck's way doesn't matter
			model.position.y = (WRECK_BOXES.get(type, Vector3(2, 1.6, 4.5)) as Vector3).y / 2.0  # kit models are centred on their box
			_rust(model)
			body.add_child(model)
		var box: Vector3 = WRECK_BOXES.get(type, Vector3(2, 1.6, 4.5))
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box
		cs.shape = shape
		cs.position.y = box.y / 2.0
		body.add_child(cs)
		add_child(body)


## A wreck's paint goes to rust and its glass dark.
static func _rust(model: Node3D) -> void:
	var rust := Surfaces.material("car_paint", 2.0, Color(0.42, 0.26, 0.17))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.09, 0.1, 0.85)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null:
				continue
			if mat.resource_name == "Car Paint":
				mi.set_surface_override_material(s, rust)
			elif mat.resource_name == "Car Glass":
				mi.set_surface_override_material(s, glass)


## Four thin walls along the map's edge (WorldMap.EXTENT), behind the tree belt: nobody walks off the world.
func _add_edge_wall() -> void:
	var e := WorldMap.EXTENT
	var body := StaticBody3D.new()
	body.name = "MapEdge"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var sides := [
		[Vector3(e.get_center().x, WALL_HEIGHT / 2.0, e.position.y), Vector3(e.size.x, WALL_HEIGHT, 1.0)],
		[Vector3(e.get_center().x, WALL_HEIGHT / 2.0, e.end.y), Vector3(e.size.x, WALL_HEIGHT, 1.0)],
		[Vector3(e.position.x, WALL_HEIGHT / 2.0, e.get_center().y), Vector3(1.0, WALL_HEIGHT, e.size.y)],
		[Vector3(e.end.x, WALL_HEIGHT / 2.0, e.get_center().y), Vector3(1.0, WALL_HEIGHT, e.size.y)],
	]
	for side: Array in sides:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		cs.shape = box
		cs.position = side[0]
		body.add_child(cs)
	add_child(body)


## F1: the "Prop ..." materials on one model instance (NodeView's resource nodes), textured like the props here.
static func texture_props(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and PROP_LOOKS.has(mat.resource_name):
				var m: Dictionary = PROP_LOOKS[mat.resource_name]
				mi.set_surface_override_material(s, Shooter._gun_material(mat, String(m["texture"]), float(m["tile_m"]),
						mat.albedo_color, m))


## M16-style: the season's leaf colours on every countryside tree at once.
func apply_season(season: String) -> void:
	if _tree_mesh == null:
		return
	var colors := SeasonLook.leaves(season)
	for s: int in _leaf_materials:
		var original: StandardMaterial3D = _leaf_materials[s]
		if not colors.has(original.resource_name):
			_tree_mesh.surface_set_material(s, original)
			continue
		var mat := original.duplicate() as StandardMaterial3D
		mat.albedo_color = colors[original.resource_name]
		_tree_mesh.surface_set_material(s, mat)
