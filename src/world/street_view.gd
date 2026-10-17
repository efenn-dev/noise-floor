class_name StreetView
extends Node3D
## A1: draws the street plan (StreetPlan): lamp posts, mailboxes, picket fences, trash cans and trees from
## their kit models, each in a StaticBody3D on the WORLD layer with a box collider (a tree's is its trunk),
## so the player bumps into them and the navmesh (NavBaker reads WORLD colliders) goes round them. Trash
## cans carry "container_id", so the Interactor searches them like a fridge (SimWorld.place_street registers
## them). At night every lamp post's lantern glows and lights a small warm omni light. Road markings (centre
## dashes and kerbs) are plain meshes with no collider. No rules live here.
## P11: a tree's body carries "tree" ([id, kind, foot], read by CountryView.tree_at), and a tree the sim fells
## (Salvage) tips over away from you and is gone.

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
var _trees: Dictionary = {}  # P11: tree id -> its body
var _falling: Array = []  # P11: [body, seconds so far, tip axis, standing transform, foot]
var _seen_changes := -1


func setup(p_sim: SimWorld, street: Dictionary) -> void:
	sim = p_sim
	for item: Dictionary in street["items"]:
		bodies.append(_add_item(item))
	_add_markings(street["markings"])
	_set_lit(sim.clock.is_night())


func _process(delta: float) -> void:
	if sim != null and sim.clock.is_night() != lit:
		_set_lit(not lit)
	if sim != null and sim.salvage.changes != _seen_changes:
		_seen_changes = sim.salvage.changes
		for id: String in sim.salvage.felled:
			if not _trees.has(id):
				continue
			var body: StaticBody3D = _trees[id]
			_trees.erase(id)
			for cs: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
				cs.set_deferred("disabled", true)
			if id == sim.salvage.last_felled and is_inside_tree():
				var foot: Vector3 = body.get_meta("tree")[2]
				var cam := get_viewport().get_camera_3d()
				var away := (foot - cam.global_position) if cam != null else Vector3.FORWARD
				away.y = 0.0
				var axis := Vector3.UP.cross(away.normalized() if away.length_squared() > 1e-4 else Vector3.FORWARD).normalized()
				_falling.append([body, maxf(CountryView.hold_fall, 0.0) * CountryView.FALL_TIME, axis, body.global_transform, foot])
			else:
				body.visible = false
	for f: Array in _falling:
		f[1] = float(f[1]) + delta
		var t := CountryView.fall_fraction(float(f[1]))
		(f[0] as Node3D).global_transform = CountryView.tipped(f[3], f[4], f[2], t)
		if t >= 1.0:
			(f[0] as Node3D).visible = false
	_falling = _falling.filter(func(f: Array) -> bool: return CountryView.fall_fraction(float(f[1])) < 1.0)


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
		"tree":  # P11: the axe's target
			var id := Salvage.tree_id(item["pos"])
			body.set_meta("tree", [id, "tree", item["pos"]])
			if not sim.salvage.felled.has(id):
				_trees[id] = body
			else:
				body.visible = false
				shape.disabled = true
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
