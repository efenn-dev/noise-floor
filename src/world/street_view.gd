class_name StreetView
extends Node3D
## A1: draws the street plan (StreetPlan): lamp posts, mailboxes, picket fences, trash cans and trees from
## their kit models, each in a StaticBody3D on the WORLD layer with a box collider (a tree's is its trunk),
## so the player bumps into them and the navmesh (NavBaker reads WORLD colliders) goes round them. Trash
## cans carry "container_id", so the Interactor searches them like a fridge (SimWorld.place_street registers
## them). At night every lamp post's lantern glows and lights a small warm omni light. Road markings (centre
## dashes and kerbs) are plain meshes with no collider. No rules live here.

const MODELS := {
	"lamp_post": "res://assets/models/lamp_post.glb",
	"mailbox": "res://assets/models/mailbox.glb",
	"picket_fence": "res://assets/models/picket_fence.glb",
	"trash_can": "res://assets/models/trash_can.glb",
	"tree": "res://assets/models/tree.glb",
}
const LIGHT_RANGE := 10.0
const LIGHT_COLOR := Color(1.0, 0.78, 0.5)
const LIGHT_ENERGY := 1.8

var sim: SimWorld
var bodies: Array = []   # one StaticBody3D per street item, in plan order (tests)
var lights: Array = []   # OmniLight3D per lamp post
var lit := false
var _lamp_mats: Array = []


func setup(p_sim: SimWorld, street: Dictionary) -> void:
	sim = p_sim
	for item: Dictionary in street["items"]:
		bodies.append(_add_item(item))
	_add_markings(street["markings"])
	_set_lit(sim.clock.is_night())


func _process(_delta: float) -> void:
	if sim != null and sim.clock.is_night() != lit:
		_set_lit(not lit)


func _set_lit(on: bool) -> void:
	lit = on
	for l: OmniLight3D in lights:
		l.visible = on
	for m: StandardMaterial3D in _lamp_mats:
		m.emission_enabled = on
		m.albedo_color = Color(1.0, 0.86, 0.6) if on else Color(0.35, 0.33, 0.28)


func _add_item(item: Dictionary) -> StaticBody3D:
	var kind: String = item["kind"]
	var scale := float(item.get("scale", 1.0))
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = item["pos"]
	body.rotation_degrees.y = float(item["yaw"])
	body.set_meta("street_kind", kind)
	var size: Vector3 = StreetPlan.COLLIDERS[kind] * scale
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	var model := (load(MODELS[StreetPlan.MODELS[kind]]) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * scale
	model.position.y = StreetPlan.SIZES[kind].y / 2.0 * scale  # kit models stand on the floor of their centred box
	body.add_child(model)
	match kind:
		"trash_can":
			body.set_meta("container_id", item["id"])
		"mailbox":
			_paint(model, "Mailbox Paint", item["color"])
		"lamp_post":
			_add_lamp(body, model)
	add_child(body)
	return body


func _add_lamp(body: StaticBody3D, model: Node3D) -> void:
	var glass := model.get_node_or_null("Lamp") as MeshInstance3D
	if glass != null:
		var mat := StandardMaterial3D.new()
		mat.emission = LIGHT_COLOR
		mat.emission_energy_multiplier = 3.0
		glass.material_override = mat
		_lamp_mats.append(mat)
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.position.y = StreetPlan.LAMP_HEIGHT - 0.25  # just under the glass, so the lantern doesn't hide it
	body.add_child(light)
	lights.append(light)


## M16: the trees' leaves in this season's colours (brown in autumn, grey and bare-looking in winter, bright
## in spring, the model's own green in summer).
func apply_season(season: String) -> void:
	var colors := SeasonLook.leaves(season)
	for body: StaticBody3D in bodies:
		if body.get_meta("street_kind", "") != "tree":
			continue
		for model: Node3D in body.get_children().filter(func(n: Node) -> bool: return n is Node3D and not n is CollisionShape3D):
			for mat_name: String in ["Leaves", "Leaves Dark"]:
				_paint(model, mat_name, colors.get(mat_name, Color()), not colors.has(mat_name))


func _paint(model: Node3D, material_name: String, color: Color, original := false) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name == material_name:
				if original:
					mesh.set_surface_override_material(s, null)  # M16: back to the model's own colour
					continue
				mat = mat.duplicate()
				mat.albedo_color = color
				mesh.set_surface_override_material(s, mat)


func _add_markings(m: Dictionary) -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.83, 0.72)
	white.roughness = 0.8
	var dash := BoxMesh.new()
	dash.size = m["dash_size"]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = dash
	multi.instance_count = m["dashes"].size()
	for i in m["dashes"].size():
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, m["dashes"][i] + Vector3(0, 0.025, 0)))
	var dashes := MultiMeshInstance3D.new()
	dashes.name = "CentreLine"
	dashes.multimesh = multi
	dashes.material_override = white
	add_child(dashes)
	var kerb_mat := Surfaces.material("concrete_floor", 2.0, Color(0.72, 0.71, 0.68))
	var h: float = m["kerb_height"]
	for r: Rect2 in m["kerbs"]:
		var mesh := MeshInstance3D.new()
		mesh.name = "Kerb"
		var box := BoxMesh.new()
		box.size = Vector3(r.size.x, h, r.size.y)
		mesh.mesh = box
		mesh.position = Vector3(r.get_center().x, h / 2.0, r.get_center().y)
		mesh.material_override = kerb_mat
		add_child(mesh)
