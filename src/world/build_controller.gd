class_name BuildController
extends Node3D
## Build mode. Aim at the ground or a foundation to see a ghost of the piece, snapped to the 2 m grid:
## green = can build, red = can't (the HUD says why). S3: main.gd turns it on with a piece from the build
## menu (B) or a hotbar key (1-9, 0), and Esc turns it off; the mouse wheel steps through PIECES (the order
## the build menu lists them in). R turns the piece: walls move to the next edge, belts and machines turn to
## face the next way (default: facing away from you). Left-click builds, right-click removes the piece you're
## looking at (full refund). F3: hold left-click and drag to build a straight row. F5: for anything that makes noise,
## rings on the ground round the ghost show how far zombies will hear it: blue at night, orange by day, dented by
## the walls around it (SimWorld.heard_preview), and the HUD says it in metres.

const REACH := 8.0
const PIECES := ["foundation", "wall", "door", "barricade", "belt", "smelter", "press", "rain_collector",
		"purifier", "planter", "canner", "bed", "storage", "generator", "solar_panel", "power_pole", "spikes",
		"nail_turret", "workbench",
		# F2: the Hub and the rescue
		"hub", "radio_mast",
		# F1: extractors (built on resource nodes)
		"salvager", "water_pump", "fuel_pump", "sawmill",
		# M15: automated defense (mouse wheel)
		"crossbow_turret", "rifle_turret", "hopper", "motion_sensor", "noise_sensor", "floodlight", "noisemaker",
		"bear_trap", "tripwire", "electric_fence", "repair_station",
		# M16: heat
		"stove", "electric_heater",
		# M17a: unlocked by the water tower
		"water_tap",
		# F3: belt routing
		"splitter", "merger",
		# F5: quieting a base
		"soundproof_wall", "dusk_timer"]
## Shrink the "is anything in the way" box so touching neighbours and the ground don't count.
const CLEARANCE := Vector3(0.1, 0.06, 0.1)

var sim: SimWorld
var camera: Camera3D
var exclude: Array[RID] = []

var active := false
var piece_index := 0
var turns := 0  # R presses; walls go on the edge `turns` quarter-turns clockwise from the one ahead

## What the player is aiming at, refreshed every physics frame.
var aim_valid := false
var aim_cell := Vector2i.ZERO
var aim_side := 0
var aim_reason := ""
var aim_remove_key := ""
var last_message := ""

var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_nose: MeshInstance3D  # marks the front of belts and machines
var _rings: MeshInstance3D  # F5: the heard-radius rings
var _rings_mesh: ImmediateMesh
var _rings_shown: Dictionary = {}  # the preview the rings were last drawn from
## F5: the heard-radius preview for the piece being placed ({} for a quiet piece): see SimWorld.heard_preview.
var heard: Dictionary = {}
const NIGHT_RING := Color(0.45, 0.6, 1.0, 0.9)
const DAY_RING := Color(1.0, 0.6, 0.2, 0.9)
## F3 (building like Satisfactory): hold the place button and drag to lay a straight run ("zoop") of up to
## ZOOP_MAX pieces: foundations, walls along their edge, belts facing the way you drag. Release to build.
const ZOOP_MAX := 32
var dragging := false
var drag_from := Vector2i.ZERO
var drag_side := 0
var _run_ghosts: Array[MeshInstance3D] = []


func setup(p_sim: SimWorld, p_camera: Camera3D, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	exclude = p_exclude
	_ghost = MeshInstance3D.new()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)
	_ghost_nose = MeshInstance3D.new()
	var nose := BoxMesh.new()
	nose.size = Vector3(0.5, 0.3, 0.3)
	_ghost_nose.mesh = nose
	_ghost_nose.material_override = _ghost_mat
	_ghost.add_child(_ghost_nose)
	_rings_mesh = ImmediateMesh.new()
	_rings = MeshInstance3D.new()
	_rings.mesh = _rings_mesh
	_rings.top_level = true
	var rings_mat := StandardMaterial3D.new()
	rings_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rings_mat.vertex_color_use_as_albedo = true
	rings_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rings.material_override = rings_mat
	_rings.visible = false
	add_child(_rings)


func piece() -> String:
	return PIECES[piece_index]


func set_active(on: bool) -> void:
	dragging = false
	active = on
	last_message = ""
	if not on:
		_ghost.visible = false
		_rings.visible = false


func select(index: int) -> void:
	piece_index = clampi(index, 0, PIECES.size() - 1)
	last_message = ""
	heard = {}  # F5: worked out again for the new piece when the ghost shows


## S3: picks a piece by id (the hotbar and the build menu). Unknown ids are ignored.
func select_id(id: String) -> void:
	var i := PIECES.find(id)
	if i != -1:
		select(i)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("build_next"):
		select((piece_index + 1) % PIECES.size())
		return
	if event.is_action_pressed("build_prev"):
		select((piece_index + PIECES.size() - 1) % PIECES.size())
		return
	if event.is_action_pressed("build_rotate"):
		turns = (turns + 1) % 4
	elif InputSetup.captured():
		if event.is_action_pressed("build_place"):
			start_drag()
		elif event.is_action_released("build_place") and dragging:
			finish_drag()
		elif event.is_action_pressed("build_remove"):
			try_remove()


func _physics_process(_delta: float) -> void:
	if active:
		update_aim()
		_rings.visible = _ghost.visible and not heard.is_empty()  # F5


func try_place() -> String:
	update_aim()
	if not aim_valid:
		last_message = "Aim at the ground"
	elif aim_reason != "":
		last_message = aim_reason
	else:
		last_message = sim.build.place(piece(), aim_cell, aim_side, _stock())
		if last_message == "":
			SoundView.play_at(self, "build_place", sim.build.center_for(piece(), aim_cell, aim_side), -4.0, randf_range(0.9, 1.1))
		update_aim()
	return last_message


## F3: the place button went down: a run starts here (released at once, it's a single piece).
func start_drag() -> void:
	update_aim()
	if not aim_valid:
		last_message = "Aim at the ground"
		return
	dragging = true
	drag_from = aim_cell
	drag_side = aim_side


## F3: the place button came up: builds the run from where it went down to where you aim now.
func finish_drag() -> String:
	dragging = false
	_hide_run()
	update_aim()
	var to := aim_cell if aim_valid else drag_from
	var cells := run_cells(sim.build.is_edge(piece()), drag_from, to, drag_side)
	var side := run_side(piece(), drag_from, to, drag_side)
	var placed := 0
	var why := ""
	for c: Vector2i in cells:
		var reason := sim.build.can_place(piece(), c, side, _stock())
		if reason == "" and placement_blocked(piece(), c, side):
			reason = "Something's in the way"
		if reason == "":
			reason = sim.build.place(piece(), c, side, _stock())
		if reason == "":
			placed += 1
		elif why == "":
			why = reason
	if placed > 0:
		SoundView.play_at(self, "build_place", sim.build.center_for(piece(), cells[0], side), -4.0, randf_range(0.9, 1.1))
	var piece_name: String = sim.data.buildables[piece()]["name"]
	if cells.size() == 1:
		last_message = why
	elif placed == cells.size():
		last_message = "Built %d %s" % [placed, piece_name.to_lower()]
	else:
		last_message = "Built %d of %d %s (%s)" % [placed, cells.size(), piece_name.to_lower(), why.to_lower()]
	update_aim()
	return last_message


## F3: the cells of a straight run from `from` toward `to`: along the edge for walls (a wall on a north or south
## edge runs east-west), else along whichever way you dragged further. At most ZOOP_MAX, `from` first.
static func run_cells(edge: bool, from: Vector2i, to: Vector2i, side: int) -> Array[Vector2i]:
	var d := to - from
	var along_x := (side == BuildGrid.Side.NORTH or side == BuildGrid.Side.SOUTH) if edge else absi(d.x) >= absi(d.y)
	var n := absi(d.x) if along_x else absi(d.y)
	var step := Vector2i(signi(d.x), 0) if along_x else Vector2i(0, signi(d.y))
	var out: Array[Vector2i] = []
	for i in mini(n, ZOOP_MAX - 1) + 1:
		out.append(from + step * i)
	return out


## F3: the side a run's pieces face: belts, splitters and mergers face the way you dragged; anything else
## keeps the side it had where the run began.
static func run_side(id: String, from: Vector2i, to: Vector2i, side: int) -> int:
	if not id in ["belt", "splitter", "merger"] or from == to:
		return side
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return BuildGrid.Side.EAST if d.x > 0 else BuildGrid.Side.WEST
	return BuildGrid.Side.SOUTH if d.y > 0 else BuildGrid.Side.NORTH


func _show_run() -> void:
	var cells := run_cells(sim.build.is_edge(piece()), drag_from, aim_cell, drag_side)
	var side := run_side(piece(), drag_from, aim_cell, drag_side)
	if cells.size() < 2:
		_hide_run()
		return
	while _run_ghosts.size() < cells.size():
		var g := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.top_level = true
		add_child(g)
		_run_ghosts.append(g)
	var box := BoxMesh.new()
	var size: Vector3 = sim.data.buildables[piece()]["size"]
	box.size = Vector3(maxf(size.x - 0.2, 0.05), size.y + 0.02, maxf(size.z - 0.2, 0.05))  # a gap between, so you can count them
	for i in _run_ghosts.size():
		var g: MeshInstance3D = _run_ghosts[i]
		g.visible = i < cells.size()
		if not g.visible:
			continue
		g.mesh = box
		g.global_position = sim.build.center_for(piece(), cells[i], side)
		g.rotation_degrees = Vector3(0, sim.build.yaw_for(piece(), cells[i], side), 0)
		var ok := sim.build.can_place(piece(), cells[i], side, _stock()) == ""
		(g.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.4, 0.35) if ok else Color(1.0, 0.25, 0.2, 0.35)
	_ghost.visible = false


func _hide_run() -> void:
	for g: MeshInstance3D in _run_ghosts:
		g.visible = false


func try_remove() -> String:
	update_aim()
	if aim_remove_key == "":
		last_message = "Look at something you built"
	else:
		var refund := sim.stock_at(sim.build.piece_center(aim_remove_key))
		refund.refund_to_storage = true  # refunds go back in the crate, not your back
		last_message = sim.build.remove(aim_remove_key, refund)
		update_aim()
	return last_message


## Raycasts from the camera and works out the snapped cell/edge, whether it's buildable, and the ghost.
func update_aim() -> void:
	aim_valid = false
	aim_remove_key = ""
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * REACH, Layers.WORLD | Layers.BUILT | Layers.TRAP, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ghost.visible = false
		return
	var collider: Object = hit["collider"]
	if collider != null and collider.has_meta("piece_key"):
		aim_remove_key = collider.get_meta("piece_key")
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if normal.y < 0.7:
		point += normal * 0.05  # hit a side: build on the near side of it
	var id := piece()
	var cell := BuildGrid.world_to_cell(point)
	var side := (_facing_side(forward) + turns) % 4
	if cell != aim_cell or side != aim_side:
		last_message = ""  # moved on: drop the old "can't build" message
	aim_cell = cell
	aim_side = side
	aim_valid = true
	aim_reason = sim.build.can_place(id, aim_cell, aim_side, _stock())
	if aim_reason == "" and placement_blocked(id, aim_cell, aim_side):
		aim_reason = "Something's in the way"
	_show_ghost(id)
	if dragging:
		_show_run()  # F3


## True if a town building, car, the player, a zombie or anything else on the WORLD layer overlaps the piece.
func placement_blocked(id: String, cell: Vector2i, side: int) -> bool:
	var size: Vector3 = sim.data.buildables[id]["size"]
	var box := BoxShape3D.new()
	box.size = (size - CLEARANCE * 2.0).max(Vector3.ONE * 0.01)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.collision_mask = Layers.WORLD | Layers.ZOMBIE
	params.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(sim.build.yaw_for(id, cell, side))),
			sim.build.center_for(id, cell, side))
	return not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _show_ghost(id: String) -> void:
	var box := BoxMesh.new()
	box.size = sim.data.buildables[id]["size"] + Vector3.ONE * 0.02
	_ghost.mesh = box
	_ghost.global_position = sim.build.center_for(id, aim_cell, aim_side)
	_ghost.rotation_degrees = Vector3(0, sim.build.yaw_for(id, aim_cell, aim_side), 0)
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4) if aim_reason == "" else Color(1.0, 0.25, 0.2, 0.4)
	var size: Vector3 = sim.data.buildables[id]["size"]
	_ghost_nose.visible = sim.build.is_object(id)
	_ghost_nose.position = Vector3(0, size.y / 2.0, -size.z / 2.0)
	_ghost.visible = true
	_show_heard(id)


## F5: works out how far zombies would hear piece `id` where the ghost stands and draws the rings: one line round
## for the night and one for the day, each point as far out as the walls that way let the sound go.
func _show_heard(id: String) -> void:
	if float(sim.data.buildables[id]["loudness"]) <= 0.0:
		heard = {}
		_rings.visible = false
		return
	var center := sim.build.center_for(id, aim_cell, aim_side)
	heard = sim.heard_preview(center, sim.loudness_of(id))
	if is_same(heard, _rings_shown):
		return
	_rings_shown = heard
	var y := center.y - float(sim.data.buildables[id]["size"].y) / 2.0 + 0.08
	_rings_mesh.clear_surfaces()
	_rings_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for ring: Array in [[heard["night"], NIGHT_RING], [heard["day"], DAY_RING]]:
		var radii: PackedFloat32Array = ring[0]
		var n := radii.size()
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var r0 := maxf(radii[i], 0.5)
			var r1 := maxf(radii[(i + 1) % n], 0.5)
			_rings_mesh.surface_set_color(ring[1])
			_rings_mesh.surface_add_vertex(Vector3(center.x + cos(a0) * r0, y, center.z + sin(a0) * r0))
			_rings_mesh.surface_set_color(ring[1])
			_rings_mesh.surface_add_vertex(Vector3(center.x + cos(a1) * r1, y, center.z + sin(a1) * r1))
	_rings_mesh.surface_end()


## The cell edge straight ahead of where the player looks (north is -Z).
static func _facing_side(forward: Vector3) -> int:
	if absf(forward.x) > absf(forward.z):
		return BuildGrid.Side.EAST if forward.x > 0.0 else BuildGrid.Side.WEST
	return BuildGrid.Side.SOUTH if forward.z > 0.0 else BuildGrid.Side.NORTH


## Two lines for the HUD.
func status_text() -> String:
	if not active:
		return "B: build menu"
	var info: Dictionary = sim.data.buildables[piece()]
	var lines := PackedStringArray()
	lines.append("BUILD  %s  (%s)" % [info["name"], _cost_text(info["cost"])])
	var hint := "1-0 hotbar · wheel: next piece · B menu · R rotate · LMB build (drag: a row) · RMB remove · Esc stop · uses crates within %dm" % int(sim.data.survival["storage_range"])
	if aim_remove_key != "":
		hint += "   [RMB removes this %s]" % sim.data.buildables[sim.build.pieces[aim_remove_key]["id"]]["name"]
	lines.append(hint)
	if not heard.is_empty():  # F5
		lines.append("Loudness %d: %s (blue ring: night, orange: day)" % [roundi(float(heard["loudness"])),
				Interactor.heard_words(SimWorld.heard_far(heard["night"]), SimWorld.heard_far(heard["day"]))])
	var msg := last_message if last_message != "" else aim_reason
	if msg != "":
		lines.append(msg)
	return "\n".join(lines)


## Your pockets and carried weight; in build mode, what nearby crates add.
func materials_text() -> String:
	var parts := PackedStringArray()
	var stock: Inventory = _stock() if active else sim.inventory
	for item: String in stock.items():
		parts.append("%s %d" % [sim.data.item_name(item), stock.count(item)])
	var kg := "%.1f / %d kg" % [sim.carried_kg(), roundi(sim.carry_limit())]
	var label := "Pockets + nearby crates: " if active else ""
	return label + ("  ·  ".join(parts) if not parts.is_empty() else "Nothing carried") + "\n" + kg


func _stock() -> Stock:
	var at := sim.build.center_for(piece(), aim_cell, aim_side) if aim_valid else camera.global_position
	return sim.stock_at(at)


func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in cost:
		parts.append("%d %s" % [cost[item], sim.data.item_name(item)])
	return ", ".join(parts)
