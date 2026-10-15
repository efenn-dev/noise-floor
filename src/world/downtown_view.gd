class_name DowntownView
extends Node3D
## W3b: what downtown (DowntownPlan) has that isn't a build piece: each shop's flat roof and the wall band from
## the top of its wall pieces up to the roof, a sign over its front (the shop's name on a coloured board), the
## props (world_props models with box colliders; one with a loot table carries "container_id", so E searches
## it), and the gas station's canopy on four posts. The shops' walls, doors, windows and floors are BuildGrid
## pieces drawn by BuildView; the wrecks are CarBodies made by main.gd. No rules live here.

const WALL_TOP := 2.8
const TOP := 4.0          # the shops' roofs (a 1.2 m band over the wall pieces, where the signs go)
const ROOF := 0.25
const OVERHANG := 0.3
const CANOPY_THICK := 0.45
## Sign boards: [board colour, text colour] by shop.
const SIGN_COLORS := {
	"grocery": [Color(0.16, 0.42, 0.2), Color(0.95, 0.93, 0.85)],
	"pharmacy": [Color(0.92, 0.92, 0.9), Color(0.75, 0.12, 0.12)],
	"hardware": [Color(0.78, 0.4, 0.1), Color(0.1, 0.1, 0.1)],
	"police": [Color(0.12, 0.2, 0.42), Color(0.95, 0.95, 0.95)],
	"gas_station": [Color(0.72, 0.12, 0.1), Color(0.98, 0.95, 0.85)],
}

var sim: SimWorld
var plan: Dictionary
var roof_meshes: Array = []  # retinted by apply_season (snow in winter)
var props: Dictionary = {}   # prop id -> StaticBody3D (tests)
var signs: Array = []        # Label3D per shop (tests, screenshots)
var _models: Dictionary = {} # model id -> PackedScene, loaded once


func setup(p_sim: SimWorld, p_plan: Dictionary) -> void:
	sim = p_sim
	plan = p_plan
	var roof_mat := Surfaces.material("asphalt", 3.0, Color(0.42, 0.42, 0.44))
	var ceiling_mat := Surfaces.material("concrete_floor", 3.0, Color(0.78, 0.78, 0.75))
	for s: Dictionary in plan["shops"]:
		_shop(s, roof_mat, ceiling_mat)
	for p: Dictionary in plan["props"]:
		props[p["id"]] = _prop(p)
	if not (plan.get("canopy", {}) as Dictionary).is_empty():
		_canopy(plan["canopy"], roof_mat)
	_sidewalks()


## Is `pos` under a shop's roof (main.gd thins the fog there)?
func is_under_roof(pos: Vector3) -> bool:
	if pos.y >= TOP:
		return false
	for s: Dictionary in plan.get("shops", []):
		if (s["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


func apply_season(season: String) -> void:
	var mat := SeasonLook.roof_material(season)
	for m: MeshInstance3D in roof_meshes:
		m.material_override = mat


func _shop(s: Dictionary, roof_mat: Material, ceiling_mat: Material) -> void:
	var r: Rect2 = s["rect"]
	var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
	roof_meshes.append(_box(Vector3(r.size.x + 2 * OVERHANG, ROOF, r.size.y + 2 * OVERHANG), mid + Vector3(0, TOP + ROOF / 2.0, 0), roof_mat))
	_box(Vector3(r.size.x, 0.04, r.size.y), mid + Vector3(0, TOP - 0.02, 0), ceiling_mat, false)
	var wall := BuildView.town_material(s["style"])
	var h := TOP - WALL_TOP
	var y := WALL_TOP + h / 2.0
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.position.y), wall)
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.end.y), wall)
	_box(Vector3(0.2, h, r.size.y), Vector3(r.position.x, y, mid.z), wall)
	_box(Vector3(0.2, h, r.size.y), Vector3(r.end.x, y, mid.z), wall)
	# The sign: a board on the front band over the door, the name on it, facing the street.
	var out := 1.0 if s["north"] else -1.0  # the street is +Z of a north-side shop
	var colors: Array = SIGN_COLORS.get(s["name"], [Color(0.3, 0.3, 0.3), Color.WHITE])
	var door: Vector2i = s["door_cell"]
	var sx := clampf((door.x + 0.5) * BuildGrid.GRID, r.position.x + 3.0, r.end.x - 3.0)
	var board_w := minf(r.size.x - 1.0, 1.0 + 0.62 * String(s["sign"]).length())
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = colors[0]
	board_mat.roughness = 0.6
	_box(Vector3(board_w, h - 0.3, 0.08), Vector3(sx, y, float(s["front_z"]) + out * 0.15), board_mat, false)
	var label := Label3D.new()
	label.text = s["sign"]
	label.font_size = 128
	label.pixel_size = 0.0055
	label.modulate = colors[1]
	label.outline_size = 0
	label.double_sided = false
	label.shaded = true  # no power downtown: the letters are only as bright as the light on them
	label.position = Vector3(sx, y, float(s["front_z"]) + out * 0.2)
	label.rotation.y = 0.0 if s["north"] else PI
	add_child(label)
	signs.append(label)


## A prop: its model standing on the floor and turned to its facing, a box collider round it, and
## "container_id" if it has a loot table.
func _prop(p: Dictionary) -> StaticBody3D:
	var size: Vector3 = p["size"]
	var f: Vector2 = p["facing"]
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = p["pos"]
	body.rotation.y = atan2(-f.x, -f.y)  # models face -Z: turn the front to look along `facing`
	if str(p["table"]) != "":
		body.set_meta("container_id", p["id"])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	var model := _model(p["model"])
	if model != null:
		body.add_child(model)
	else:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		mesh.position.y = size.y / 2.0
		body.add_child(mesh)
	add_child(body)
	return body


## The model for `id` (assets/models/<id>.glb from tools/art/world_props.py) standing on its feet, its "Prop"
## materials textured like the countryside's; null if it hasn't been made.
func _model(id: String) -> Node3D:
	var path := "res://assets/models/%s.glb" % id
	if not _models.has(id):
		_models[id] = load(path) if ResourceLoader.exists(path) else null
	if _models[id] == null:
		return null
	var model := (_models[id] as PackedScene).instantiate() as Node3D
	model.position.y = -CountryView.bounds(model).position.y  # kit models are centred on their box
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and CountryView.PROP_LOOKS.has(mat.resource_name):
				var look: Dictionary = CountryView.PROP_LOOKS[mat.resource_name]
				mi.set_surface_override_material(i, Shooter._gun_material(mat, String(look["texture"]), float(look["tile_m"]),
						mat.albedo_color, look))
	return model


## A concrete sidewalk along each side of Market Street, from the first shop's front to the last (the gas
## station's forecourt too), a hand's height up so it reads as a kerb.
func _sidewalks() -> void:
	var mat := Surfaces.material("concrete_floor", 2.0, Color(0.72, 0.72, 0.7))
	for north in [true, false]:
		var x0 := INF
		var x1 := -INF
		var front := 0.0
		for s: Dictionary in plan["shops"]:
			if s["north"] == north:
				x0 = minf(x0, (s["rect"] as Rect2).position.x)
				x1 = maxf(x1, (s["rect"] as Rect2).end.x)
				front = s["front_z"] if north else minf(front if front != 0.0 else INF, s["front_z"])
		if x0 == INF:
			continue
		var edge := DowntownPlan.STREET_Z + (-5.0 if north else 5.0)
		var z0 := minf(front, edge)
		var z1 := maxf(front, edge)
		_box(Vector3(x1 - x0 + 2.0, 0.08, z1 - z0), Vector3((x0 + x1) / 2.0, 0.04, (z0 + z1) / 2.0), mat, false)


## The gas station's canopy: a flat roof over the pumps on four posts (the posts are solid).
func _canopy(c: Dictionary, roof_mat: Material) -> void:
	var r: Rect2 = c["rect"]
	var top: float = c["top"]
	var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
	roof_meshes.append(_box(Vector3(r.size.x, 0.12, r.size.y), mid + Vector3(0, top + 0.06, 0), roof_mat))
	var fascia := StandardMaterial3D.new()
	fascia.albedo_color = SIGN_COLORS["gas_station"][0]
	fascia.roughness = 0.55
	_box(Vector3(r.size.x + 0.1, CANOPY_THICK, r.size.y + 0.1), mid + Vector3(0, top - CANOPY_THICK / 2.0, 0), fascia, false)
	var under := StandardMaterial3D.new()
	under.albedo_color = Color(0.85, 0.85, 0.82)
	_box(Vector3(r.size.x - 0.05, 0.02, r.size.y - 0.05), mid + Vector3(0, top - CANOPY_THICK - 0.01, 0), under, false)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.82, 0.82, 0.8)
	post_mat.roughness = 0.5
	var height := top - CANOPY_THICK
	for p: Vector3 in c["posts"]:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = p + Vector3(0, height / 2.0, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, height, 0.3)
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		mesh.mesh = bm
		mesh.material_override = post_mat
		body.add_child(mesh)
		add_child(body)


func _box(size: Vector3, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = pos
	mesh.material_override = mat
	if not shadow:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh
