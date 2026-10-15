class_name BuildView
extends Node3D
## Draws the pieces in a BuildGrid: one solid box per piece, added and freed as the grid changes.
## Each body carries meta "piece_key" so a raycast can tell which piece it hit.

var grid: BuildGrid
var _bodies: Dictionary = {}  # key -> StaticBody3D
## Town pieces (W1a): piece key -> "brick", "siding", "plaster" (inside walls), "factory" or "floor", from the
## town plan. Set by main.gd before setup(). Town pieces without an entry get siding / floor.
var styles: Dictionary = {}

const COLORS := {
	"foundation": Color(0.55, 0.45, 0.32),
	"wall": Color(0.62, 0.52, 0.38),
	"belt": Color(0.16, 0.16, 0.18),
	"machine": Color(0.42, 0.44, 0.4),
	"bed": Color(0.35, 0.4, 0.6),
	"storage": Color(0.5, 0.38, 0.22),
	"generator": Color(0.6, 0.5, 0.15),
	"solar": Color(0.12, 0.16, 0.3),
	"pole": Color(0.4, 0.3, 0.2),
	"door": Color(0.45, 0.3, 0.18),
	"window": Color(0.6, 0.58, 0.55),
	"barricade": Color(0.5, 0.4, 0.28),
	"trap": Color(0.3, 0.3, 0.32),
	"turret": Color(0.35, 0.38, 0.35),
	"prop": Color(0.45, 0.36, 0.26),
	"workbench": Color(0.5, 0.36, 0.2),
	# M15
	"hopper": Color(0.42, 0.34, 0.2),
	"sensor": Color(0.25, 0.27, 0.3),
	"floodlight": Color(0.4, 0.3, 0.2),
	"noisemaker": Color(0.55, 0.2, 0.15),
	"bear_trap": Color(0.32, 0.3, 0.28),
	"tripwire": Color(0.55, 0.5, 0.35),
	"fence": Color(0.5, 0.52, 0.5),
	"repair_station": Color(0.45, 0.45, 0.3),
	# M16
	"stove": Color(0.2, 0.2, 0.2),
	"heater": Color(0.85, 0.85, 0.8),
}
## M15: walk-over pieces (only rays see them): spike strips, bear traps, tripwires.
const WALK_OVER := ["trap", "bear_trap", "tripwire"]
const INPUT_COLOR := Color(0.25, 0.45, 0.9)
const OUTPUT_COLOR := Color(0.95, 0.55, 0.15)
## Art made with Codex: models built by tools/art/<id>.py (checked by test_art_models.gd) replace the box mesh,
## collider unchanged. Pieces not listed stay plain coloured boxes.
const MODELS := {
	"press": "res://assets/models/press.glb",
	"hub": "res://assets/models/hub.glb",  # F2 (tools/art/f2_models.py)
	"radio_mast": "res://assets/models/radio_mast.glb",
	"salvager": "res://assets/models/salvager.glb",  # F1: extractors (tools/art/f1_models.py)
	"water_pump": "res://assets/models/water_pump.glb",
	"fuel_pump": "res://assets/models/fuel_pump.glb",
	"sawmill": "res://assets/models/sawmill.glb",
	"smelter": "res://assets/models/smelter.glb",
	"rain_collector": "res://assets/models/rain_collector.glb",
	"purifier": "res://assets/models/purifier.glb",
	"canner": "res://assets/models/canner.glb",
	"planter": "res://assets/models/planter.glb",
	"generator": "res://assets/models/generator.glb",
	"solar_panel": "res://assets/models/solar_panel.glb",
	"power_pole": "res://assets/models/power_pole.glb",
	"belt": "res://assets/models/belt.glb",
	"bed": "res://assets/models/bed.glb",
	"storage": "res://assets/models/storage.glb",
	"door": "res://assets/models/door.glb",
	"barricade": "res://assets/models/barricade.glb",
	"spikes": "res://assets/models/spikes.glb",
	"nail_turret": "res://assets/models/nail_turret.glb",
	# M15: the new turrets reuse the nail turret's body, with their own head parts added in code; the floodlight
	# is a power pole with a lamp, the repair station a purifier body with panels on top.
	"crossbow_turret": "res://assets/models/nail_turret.glb",
	"rifle_turret": "res://assets/models/nail_turret.glb",
	"floodlight": "res://assets/models/power_pole.glb",
	"repair_station": "res://assets/models/purifier.glb",
	# M16: the stove is the generator's body painted cast-iron black (its Lamp is the fire, lit by DefenseView),
	# the electric heater the purifier's body painted cream.
	"stove": "res://assets/models/generator.glb",
	"electric_heater": "res://assets/models/purifier.glb",
	"water_tap": "res://assets/models/water_tap.glb",  # M17a
	# W1c: house furniture, laid by the town plan (kind "prop").
	"counter": "res://assets/models/counter.glb",
	"table": "res://assets/models/table.glb",
	"couch": "res://assets/models/couch.glb",
	"shelf": "res://assets/models/shelf.glb",
	"bathtub": "res://assets/models/bathtub.glb",
	"toilet": "res://assets/models/toilet.glb",
}
const SURFACES := {"foundation": "concrete_floor", "wall": "scrap_wall"}  # piece id -> texture name (see Surfaces)



func setup(p_grid: BuildGrid) -> void:
	grid = p_grid
	grid.piece_added.connect(_on_added)
	grid.piece_removed.connect(_on_removed)
	grid.piece_changed.connect(_on_changed)
	for key: String in grid.pieces:
		_on_added(key)


func body_for(key: String) -> StaticBody3D:
	return _bodies.get(key)


func _on_added(key: String) -> void:
	var piece: Dictionary = grid.pieces[key]
	var id: String = piece["id"]
	var info: Dictionary = grid.data.buildables[id]
	var size: Vector3 = info["size"]
	var body := StaticBody3D.new()
	body.collision_layer = Layers.TRAP if info["kind"] in WALK_OVER else Layers.BUILT
	body.collision_mask = 0
	body.set_meta("piece_key", key)
	body.position = grid.piece_center(key)
	body.rotation_degrees.y = grid.yaw_for(id, piece["cell"], piece.get("side", 0))
	if MODELS.has(id):
		_add_model(body, id)
	elif id == "window":
		_add_window(body, key, size)
	elif id in ["town_wall", "town_floor"]:
		var town_mesh := MeshInstance3D.new()
		var town_box := BoxMesh.new()
		town_box.size = size
		town_mesh.mesh = town_box
		town_mesh.material_override = town_material(styles.get(key, "floor" if id == "town_floor" else "siding"))
		body.add_child(town_mesh)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		if SURFACES.has(id):
			mesh.material_override = _surface(id)
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = COLORS.get(info["kind"], Color.GRAY)
			mat.roughness = 0.95
			mesh.material_override = mat
		body.add_child(mesh)
	# Models carry their own details (lamp, in/out paint), so they skip these placeholder parts.
	match info["kind"] if not MODELS.has(id) else "":
		"belt":
			# Two pale chevron bars toward the front (-Z) show which way it runs.
			for z in [-0.55, 0.25]:
				_add_part(body, Vector3(0.7, 0.02, 0.12), Vector3(0, size.y / 2.0 + 0.01, z), Color(0.8, 0.75, 0.3))
		"machine":
			_add_part(body, Vector3(0.7, 0.5, 0.12), Vector3(0, -size.y / 2.0 + 0.4, -size.z / 2.0 - 0.06), OUTPUT_COLOR)
			_add_part(body, Vector3(0.7, 0.5, 0.12), Vector3(0, -size.y / 2.0 + 0.4, size.z / 2.0 + 0.06), INPUT_COLOR)
			var lamp := _add_part(body, Vector3(0.25, 0.25, 0.25), Vector3(0, size.y / 2.0 + 0.125, 0), Color(0.2, 0.2, 0.2))
			lamp.name = "Lamp"
		"bed":
			_add_part(body, Vector3(0.7, 0.12, 0.35), Vector3(0, size.y / 2.0 + 0.06, -size.z / 2.0 + 0.25), Color(0.92, 0.92, 0.9))
		"generator":
			_add_part(body, Vector3(0.15, 0.6, 0.15), Vector3(size.x / 2.0 - 0.2, size.y / 2.0 + 0.3, 0.3), Color(0.25, 0.25, 0.25))  # exhaust
			var glamp := _add_part(body, Vector3(0.2, 0.2, 0.2), Vector3(-size.x / 2.0 + 0.25, size.y / 2.0 + 0.1, 0), Color(0.2, 0.2, 0.2))
			glamp.name = "Lamp"
		"solar":
			_add_part(body, Vector3(0.12, 0.5, 0.12), Vector3(0, -0.3, 0), Color(0.5, 0.5, 0.5))  # stand
		"pole":
			_add_part(body, Vector3(1.0, 0.1, 0.1), Vector3(0, size.y / 2.0 - 0.2, 0), Color(0.35, 0.25, 0.15))  # crossbar
		"door":
			_add_part(body, Vector3(0.1, 0.1, 0.25), Vector3(0.75, 0, 0), Color(0.75, 0.7, 0.3))  # handle
		"barricade":
			for y in [-0.35, 0.3]:  # boards nailed across
				_add_part(body, Vector3(size.x + 0.1, 0.18, 0.06), Vector3(0, y, size.z / 2.0 + 0.03), Color(0.62, 0.5, 0.34))
		"trap":
			for x in [-0.6, -0.2, 0.2, 0.6]:
				for z in [-0.6, -0.2, 0.2, 0.6]:
					_add_part(body, Vector3(0.08, 0.35, 0.08), Vector3(x, 0.15, z), Color(0.7, 0.7, 0.72))
		"turret":
			var head := _add_part(body, Vector3(0.5, 0.35, 0.8), Vector3(0, size.y / 2.0 + 0.15, 0), Color(0.3, 0.32, 0.3))
			head.name = "Head"
			var barrel := MeshInstance3D.new()
			var tube := BoxMesh.new()
			tube.size = Vector3(0.1, 0.1, 0.6)
			barrel.mesh = tube
			barrel.position = Vector3(0, 0, -0.6)
			head.add_child(barrel)
		"storage":
			_add_part(body, Vector3(size.x + 0.04, 0.08, size.z + 0.04), Vector3(0, size.y / 2.0 - 0.1, 0), Color(0.3, 0.22, 0.12))
		"hopper":  # a funnel lip on top and a chute at the front, toward the turret it feeds
			_add_part(body, Vector3(size.x + 0.1, 0.12, size.z + 0.1), Vector3(0, size.y / 2.0, 0), Color(0.3, 0.24, 0.14))
			_add_part(body, Vector3(0.3, 0.3, 0.3), Vector3(0, size.y / 2.0 - 0.25, -size.z / 2.0 - 0.15), Color(0.35, 0.35, 0.35))
		"sensor":  # a small box on a pole; its Lamp goes red while it's on
			var eye := _add_part(body, Vector3(0.36, 0.26, 0.3), Vector3(0, size.y / 2.0 + 0.1, 0), Color(0.15, 0.15, 0.16))
			var slamp := _add_part(body, Vector3(0.1, 0.1, 0.04), Vector3(0, size.y / 2.0 + 0.1, -0.17), Color(0.2, 0.2, 0.2))
			slamp.name = "Lamp"
			eye.name = "Eye"
			if id == "noise_sensor":
				_add_part(body, Vector3(0.12, 0.12, 0.2), Vector3(0, size.y / 2.0 + 0.3, 0), Color(0.3, 0.3, 0.3))  # a mic
		"noisemaker":  # a box with a horn on top
			var horn := _add_part(body, Vector3(0.36, 0.36, 0.6), Vector3(0, size.y / 2.0 + 0.2, -0.1), Color(0.75, 0.7, 0.3))
			horn.name = "Horn"
			var nlamp := _add_part(body, Vector3(0.15, 0.15, 0.15), Vector3(0.25, size.y / 2.0 + 0.08, 0.25), Color(0.2, 0.2, 0.2))
			nlamp.name = "Lamp"
		"bear_trap":
			for x in [-0.25, 0.25]:
				_add_part(body, Vector3(0.06, 0.16, 0.7), Vector3(x, 0.08, 0), Color(0.6, 0.6, 0.62))  # jaws
		"tripwire":
			_add_part(body, Vector3(0.06, 0.5, 0.06), Vector3(-size.x / 2.0, 0.05, 0), Color(0.4, 0.3, 0.2))  # stakes
			_add_part(body, Vector3(0.06, 0.5, 0.06), Vector3(size.x / 2.0, 0.05, 0), Color(0.4, 0.3, 0.2))
			_add_part(body, Vector3(0.14, 0.16, 0.14), Vector3(size.x / 2.0, 0.35, 0), Color(0.85, 0.7, 0.25))  # the bell
		"fence":
			for x in [-size.x / 2.0, 0.0, size.x / 2.0]:
				_add_part(body, Vector3(0.1, size.y + 0.1, 0.12), Vector3(x, 0.05, 0), Color(0.35, 0.33, 0.3))  # posts
			for y in [-0.45, 0.0, 0.45]:
				_add_part(body, Vector3(size.x, 0.03, 0.14), Vector3(0, y, 0), Color(0.85, 0.75, 0.3))  # live wires
	_add_m15_parts(body, id, size)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	body.add_to_group("build_pieces")  # ZombieBody finds the one window collider to ignore while climbing
	_bodies[key] = body
	if grid.is_broken(key):
		_on_changed(key, false)  # a broken window from a save: no shatter, just the jagged edge


## The surface a town piece is drawn with (shared materials; world-space, so pieces join up).
static func town_material(style: String) -> StandardMaterial3D:
	match style:
		"brick":
			return Surfaces.material("brick", 2.5, Color(0.78, 0.7, 0.66))
		"siding":
			return Surfaces.material("siding", 2.5, Color(0.72, 0.74, 0.78))
		"factory":
			return Surfaces.material("brick", 3.0, Color(0.6, 0.6, 0.62))  # the old factory block's grey brick
		"plaster":
			return Surfaces.material("concrete_floor", 3.0, Color(0.86, 0.84, 0.78))  # pale inside walls
		"park_brick":  # M17a: the industrial park's warehouses, a darker red-brown brick
			return Surfaces.material("brick", 3.0, Color(0.62, 0.48, 0.42))
		"corrugated":  # M17a: corrugated-metal warehouses (the scrap-wall texture in steel grey)
			return Surfaces.material("scrap_wall", 2.0, Color(0.62, 0.66, 0.7))
	return Surfaces.material("concrete_floor", 2.0, Color(0.62, 0.5, 0.4))  # a warm, worn floor


## A window: wall below and above, posts each side, and a pane of glass ("Glass") in the middle.
## The collider is the whole edge even after the glass breaks: ordinary walking and navmesh paths remain
## blocked by the sill/frame. Intact windows are see-through for zombie sight rays (meta "see_through");
## a scripted player/zombie climb temporarily ignores this specific body.
func _add_window(body: StaticBody3D, key: String, size: Vector3) -> void:
	var mat := town_material(styles.get(key, "siding"))
	var h := size.y / 2.0
	var sill := 0.9
	var top := 0.5
	for part: Array in [[Vector3(size.x, sill, size.z), Vector3(0, -h + sill / 2.0, 0)],
			[Vector3(size.x, top, size.z), Vector3(0, h - top / 2.0, 0)],
			[Vector3(0.3, size.y - sill - top, size.z), Vector3(-size.x / 2.0 + 0.15, -h + sill + (size.y - sill - top) / 2.0, 0)],
			[Vector3(0.3, size.y - sill - top, size.z), Vector3(size.x / 2.0 - 0.15, -h + sill + (size.y - sill - top) / 2.0, 0)]]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		m.mesh = b
		m.position = part[1]
		m.material_override = mat
		body.add_child(m)
	var glass := _add_part(body, Vector3(size.x - 0.6, size.y - sill - top, 0.03),
			Vector3(0, -h + sill + (size.y - sill - top) / 2.0, 0), Color(0.6, 0.75, 0.85, 0.25))
	glass.name = "Glass"
	var glass_mat: StandardMaterial3D = glass.material_override
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 0.9
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # daylight comes in
	body.set_meta("see_through", true)


## A door opened or closed: swing it round its hinge (BuildGrid.door_pose). S3: an open door stays a solid
## body in its swung pose, so the look ray still finds it (to close it) and nobody walks through the panel;
## the doorway itself is clear, and the navmesh rebake routes zombies through it round the open panel.
## (It used to go on no layer at all when open: you could not close it again, and walked through it.)
func _on_changed(key: String, fx: bool = true) -> void:
	var body: StaticBody3D = _bodies.get(key)
	if body == null or not grid.pieces.has(key):
		return
	if grid.pieces[key]["id"] == "window":
		var broken := grid.is_broken(key)
		# The sim rule drives both CharacterBody collision and NavBaker's static-collider geometry.
		body.collision_layer = Layers.BUILT if grid.edge_blocks_walk(key) else 0
		var glass := body.get_node_or_null("Glass") as MeshInstance3D
		if glass != null:
			var shards := body.get_node_or_null("GlassShards")
			if broken and grid.has_shards(key) and shards == null:
				body.add_child(shard_ring(glass, key))  # W2: jagged glass left in the frame
				if fx:  # W2: and a burst of glass, both ways (zombie or you, inside or out)
					var n := body.global_basis.z
					ImpactFx.spawn(get_parent() if get_parent() != null else self, glass.global_position, n, "glass")
					ImpactFx.spawn(get_parent() if get_parent() != null else self, glass.global_position, -n, "glass")
			elif shards != null and not grid.has_shards(key):
				shards.queue_free()  # clearing glass keeps the frame and its collider, but removes the hazard
			glass.visible = not broken
		return
	body.collision_layer = Layers.BUILT
	body.transform = grid.door_pose(key)


## M15: pieces that reuse another model get their own touches: a crossbow's bow and a rifle's long barrel on the
## nail turret's head, a lamp on the floodlight's pole, wall panels stacked on the repair station.
func _add_m15_parts(body: StaticBody3D, id: String, size: Vector3) -> void:
	var head := body.get_node_or_null("Head") as Node3D
	match id:
		"crossbow_turret":
			if head != null:
				var bow := _add_part(head, Vector3(1.1, 0.06, 0.08), Vector3(0, 0.05, -0.35), Color(0.45, 0.32, 0.18))
				bow.name = "Bow"
		"rifle_turret":
			if head != null:
				var barrel := _add_part(head, Vector3(0.08, 0.08, 1.0), Vector3(0, 0.05, -0.75), Color(0.12, 0.12, 0.12))
				barrel.name = "Barrel"
		"floodlight":
			var lamp := _add_part(body, Vector3(0.45, 0.3, 0.25), Vector3(0, size.y / 2.0 - 0.1, -0.2), Color(0.25, 0.25, 0.22))
			lamp.name = "Lamp"
		"repair_station":
			_add_part(body, Vector3(1.0, 0.16, 0.7), Vector3(0, size.y / 2.0 + 0.08, 0), Color(0.62, 0.62, 0.55))
		# M16: the stove's fire is a glowing window low on its front, with a stovepipe on top; the heater's is a
		# grille across its front. Either becomes the body's "Lamp" (DefenseView lights it).
		"stove", "electric_heater":
			var old := body.get_node_or_null("Lamp")
			if old != null:
				old.name = "ModelLamp"
			var fire := _add_part(body, Vector3(0.7, 0.32, 0.04) if id == "stove" else Vector3(0.9, 0.5, 0.04),
					Vector3(0, -size.y / 2.0 + (0.42 if id == "stove" else 0.7), -size.z / 2.0 - 0.01), Color(0.12, 0.1, 0.1))
			fire.name = "Lamp"
			if id == "stove":
				_add_part(body, Vector3(0.16, 0.9, 0.16), Vector3(size.x / 2.0 - 0.3, size.y / 2.0 + 0.45, 0.2), Color(0.12, 0.12, 0.12))


func _add_part(body: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	part.material_override = mat
	body.add_child(part)
	return part


## A model's separate parts (tools/art/kit.py) become the body's own children, where FactoryView
## looks for them: "Lamp" (recoloured, so it gets an unshared material) and a turret's "Head" (aimed).
func _add_model(body: StaticBody3D, id: String) -> void:
	var model := (load(MODELS[id]) as PackedScene).instantiate() as Node3D
	body.add_child(model)
	if MODEL_TINTS.has(id):
		tint_model(model, MODEL_TINTS[id])
	for part_name in ["Lamp", "Head"]:
		var part := model.get_node_or_null(part_name) as MeshInstance3D
		if part == null:
			continue
		model.remove_child(part)  # the model root sits at the body origin, so the part's transform still holds
		part.owner = null
		body.add_child(part)
		if part_name == "Lamp":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.2, 0.2)
			part.material_override = mat


## M16: model ids drawn with every material's colour multiplied by a tint (a reused body made to look different).
const MODEL_TINTS := {"stove": Color(0.3, 0.28, 0.27), "electric_heater": Color(1.25, 1.2, 1.05)}


static func tint_model(model: Node3D, tint: Color) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null:
				mat = mat.duplicate()
				mat.albedo_color = Color(minf(1.0, mat.albedo_color.r * tint.r), minf(1.0, mat.albedo_color.g * tint.g),
						minf(1.0, mat.albedo_color.b * tint.b), mat.albedo_color.a)
				mesh.set_surface_override_material(s, mat)


func _surface(id: String) -> StandardMaterial3D:
	return Surfaces.material(SURFACES[id])  # shared, so world-space tiling lines up across pieces


func _on_removed(key: String, piece: Dictionary) -> void:
	if piece.get("destroyed", false) and _bodies.has(key) and kind_has_wood(String(piece.get("id", ""))):
		ImpactFx.spawn(get_parent() if get_parent() != null else self, _bodies[key].global_position, Vector3.UP, "wood")  # W2
	if _bodies.has(key):
		_bodies[key].queue_free()
		_bodies.erase(key)


## W2: doors, barricades, fences and furniture splinter when they're wrecked.
static func kind_has_wood(id: String) -> bool:
	return id in ["door", "town_door", "barricade", "fence"] or id.begins_with("town_door")


## W2: the jagged glass a broken window leaves in its frame: thin triangles along each edge of the pane,
## pointing in, laid out from the piece key so the same window always breaks the same way.
static func shard_ring(glass: MeshInstance3D, key: String) -> MeshInstance3D:
	var size := (glass.mesh as BoxMesh).size if glass.mesh is BoxMesh else Vector3(1.4, 1.3, 0.03)
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each edge: a start and end corner and the inward direction.
	for edge: Array in [[Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(0, 1)], [Vector2(hx, hy), Vector2(-hx, hy), Vector2(0, -1)],
			[Vector2(-hx, hy), Vector2(-hx, -hy), Vector2(1, 0)], [Vector2(hx, -hy), Vector2(hx, hy), Vector2(-1, 0)]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var inward: Vector2 = edge[2]
		var count := rng.randi_range(2, 4)
		for i in count:
			var t0 := float(i) / count + rng.randf_range(0.0, 0.05)
			var t1 := float(i + 1) / count - rng.randf_range(0.0, 0.05)
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var depth := rng.randf_range(0.06, 0.32) * minf(size.x, size.y)
			var tip := a.lerp(b, rng.randf_range(t0, t1)) + inward * depth
			for p: Vector2 in [p0, p1, tip]:  # both faces, so it shows from inside and out
				st.add_vertex(Vector3(p.x, p.y, 0.0))
			for p: Vector2 in [p1, p0, tip]:
				st.add_vertex(Vector3(p.x, p.y, 0.0))
	st.generate_normals()
	var shards := MeshInstance3D.new()
	shards.name = "GlassShards"
	shards.mesh = st.commit()
	shards.material_override = glass.material_override
	shards.transform = glass.transform
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shards
