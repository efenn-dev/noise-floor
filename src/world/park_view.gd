class_name ParkView
extends Node3D
## M17a: what the industrial park (ParkPlan) has that isn't a build piece: the warehouses' roofs and the wall
## band from the top of their wall pieces up to the roof (like the factory hall's), the supply crates (searchable
## like the factory's, "container_id"), the grey wire fence sections (the picket fence model in grey), and the
## water tower (its model, leg and pump-house colliders with "project_id" so E opens the project screen, and a
## glow in the pump house's window while the pump runs). The warehouse walls, windows and floors are BuildGrid
## pieces drawn by BuildView; the wrecks are CarBodies made by main.gd. No rules live here.

const WALL_TOP := 2.8
const TOP := 5.0          # the warehouses' roof
const ROOF := 0.25
const OVERHANG := 0.35
const TOWER_MODEL := "res://assets/models/water_tower.glb"
const TOWER_SIZE := Vector3(6.0, 12.8, 6.0)
const TOWER_YAW := 90.0   # the ladder and pump face the road (west)
const FENCE_MODEL := "res://assets/models/picket_fence.glb"
const FENCE_COLOR := Color(0.3, 0.31, 0.33)
const CRATE_SIZE := Vector3(1.2, 1.0, 1.0)

var sim: SimWorld
var plan: Dictionary
var roof_meshes: Array = []  # retinted by apply_season (snow in winter)
var crates: Array = []       # StaticBody3D per crate (tests)
var fences: Array = []       # StaticBody3D per fence section (tests)
var tower: Node3D            # the tower's root (tests, screenshots)
var _pump_light: OmniLight3D


func setup(p_sim: SimWorld, p_plan: Dictionary) -> void:
	sim = p_sim
	plan = p_plan
	var roof_mat := Surfaces.material("asphalt", 3.0, Color(0.42, 0.42, 0.44))
	var ceiling_mat := Surfaces.material("concrete_floor", 3.0, Color(0.7, 0.7, 0.68))
	for wh: Dictionary in plan["warehouses"]:
		_warehouse(wh, roof_mat, ceiling_mat)
	for c: Dictionary in plan["crates"]:
		crates.append(_crate(c))
	var fence_mat := StandardMaterial3D.new()
	fence_mat.albedo_color = FENCE_COLOR
	fence_mat.metallic = 0.3
	fence_mat.roughness = 0.7
	for f: Dictionary in plan["fences"]:
		fences.append(_fence(f, fence_mat))
	_tower(plan["tower"]["pos"])


func _process(_delta: float) -> void:
	if _pump_light != null and sim != null:
		_pump_light.visible = sim.projects.is_running("water_tower") or sim.projects.is_done("water_tower")


## Is `pos` under a warehouse roof (main.gd thins the fog there)?
func is_under_roof(pos: Vector3) -> bool:
	if pos.y >= TOP:
		return false
	for wh: Dictionary in plan.get("warehouses", []):
		if (wh["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


func apply_season(season: String) -> void:
	var mat := SeasonLook.roof_material(season)
	for m: MeshInstance3D in roof_meshes:
		m.material_override = mat


func _warehouse(wh: Dictionary, roof_mat: Material, ceiling_mat: Material) -> void:
	var r: Rect2 = wh["rect"]
	var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
	roof_meshes.append(_box(Vector3(r.size.x + 2 * OVERHANG, ROOF, r.size.y + 2 * OVERHANG), mid + Vector3(0, TOP + ROOF / 2.0, 0), roof_mat))
	_box(Vector3(r.size.x, 0.04, r.size.y), mid + Vector3(0, TOP - 0.02, 0), ceiling_mat, false)
	var wall := BuildView.town_material(wh["style"])
	var h := TOP - WALL_TOP
	var y := WALL_TOP + h / 2.0
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.position.y), wall)
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.end.y), wall)
	_box(Vector3(0.2, h, r.size.y), Vector3(r.position.x, y, mid.z), wall)  # over the doorways too, as lintels
	_box(Vector3(0.2, h, r.size.y), Vector3(r.end.x, y, mid.z), wall)


func _crate(c: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = SimWorld.park_crate_pos(c)
	body.set_meta("container_id", c["id"])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CRATE_SIZE
	shape.shape = box
	body.add_child(shape)
	var path := "res://assets/models/storage.glb"
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.scale = Vector3(CRATE_SIZE.x / 1.4, 1.0, 1.0)
		var out := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][c["side"]] as Vector2
		model.rotation.y = atan2(out.x, out.y)
		body.add_child(model)
	add_child(body)
	return body


func _fence(f: Dictionary, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = f["pos"]
	body.rotation_degrees.y = float(f["yaw"])
	var size: Vector3 = StreetPlan.COLLIDERS["fence"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	if ResourceLoader.exists(FENCE_MODEL):
		var model := (load(FENCE_MODEL) as PackedScene).instantiate() as Node3D
		model.position.y = StreetPlan.SIZES["fence"].y / 2.0
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			m.material_override = mat
		body.add_child(model)
	add_child(body)
	return body


## The tower: the model, a collider per leg and one round the pump house, all carrying "project_id".
func _tower(pos: Vector3) -> void:
	tower = Node3D.new()
	tower.position = pos
	tower.rotation_degrees.y = TOWER_YAW
	add_child(tower)
	if ResourceLoader.exists(TOWER_MODEL):
		var model := (load(TOWER_MODEL) as PackedScene).instantiate() as Node3D
		model.position.y = TOWER_SIZE.y / 2.0
		tower.add_child(model)
	else:
		_box(Vector3(5.0, 3.2, 5.0), Vector3(0, 9.8, 0), BuildView.town_material("corrugated")).reparent(tower, false)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("project_id", "water_tower")
	tower.add_child(body)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_shape(body, Vector3(0.5, 8.0, 0.5), Vector3(sx * 2.35, 4.0, sz * 2.35))
	_shape(body, Vector3(1.7, 1.4, 1.6), Vector3(0, 0.7, 0))  # the pump house, under the middle
	_pump_light = OmniLight3D.new()
	_pump_light.light_color = Color(0.6, 0.85, 1.0)
	_pump_light.light_energy = 1.5
	_pump_light.omni_range = 6.0
	_pump_light.position = Vector3(0, 1.8, 0)
	_pump_light.visible = false
	tower.add_child(_pump_light)


func _shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


func _box(size: Vector3, pos: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m
