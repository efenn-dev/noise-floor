class_name BuildController
extends Node3D
## Build mode: B toggles it. Aim at the ground or a foundation to see a ghost of the piece,
## snapped to the 2 m grid: green = can build, red = can't (the HUD says why).
## 1-9, 0 and the mouse wheel pick the piece (see PIECES). R turns the piece: walls move to the next edge,
## belts and machines turn to face the next way (default: facing away from you).
## Left-click builds, right-click removes the piece you're looking at (full refund).

const REACH := 8.0
const PIECES := ["foundation", "wall", "door", "barricade", "belt", "smelter", "press", "rain_collector",
		"purifier", "planter", "canner", "bed", "storage", "generator", "solar_panel", "power_pole", "spikes",
		"nail_turret"]
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


func piece() -> String:
	return PIECES[piece_index]


func set_active(on: bool) -> void:
	active = on
	last_message = ""
	if not on:
		_ghost.visible = false


func select(index: int) -> void:
	piece_index = clampi(index, 0, PIECES.size() - 1)
	last_message = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		set_active(not active)
	if not active:
		return
	for i in mini(PIECES.size(), 10):  # keys 1-9 and 0; the rest via the wheel
		if event.is_action_pressed("build_pick_%d" % (i + 1)):
			select(i)
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
			try_place()
		elif event.is_action_pressed("build_remove"):
			try_remove()


func _physics_process(_delta: float) -> void:
	if active:
		update_aim()


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


## The cell edge straight ahead of where the player looks (north is -Z).
static func _facing_side(forward: Vector3) -> int:
	if absf(forward.x) > absf(forward.z):
		return BuildGrid.Side.EAST if forward.x > 0.0 else BuildGrid.Side.WEST
	return BuildGrid.Side.SOUTH if forward.z > 0.0 else BuildGrid.Side.NORTH


## Two lines for the HUD.
func status_text() -> String:
	if not active:
		return "B: build mode"
	var info: Dictionary = sim.data.buildables[piece()]
	var lines := PackedStringArray()
	lines.append("BUILD  %s  (%s)" % [info["name"], _cost_text(info["cost"])])
	var hint := "1-9, 0 or wheel: pick · R rotate · LMB build · RMB remove · B exit · uses crates within %dm" % int(sim.data.survival["storage_range"])
	if aim_remove_key != "":
		hint += "   [RMB removes this %s]" % sim.data.buildables[sim.build.pieces[aim_remove_key]["id"]]["name"]
	lines.append(hint)
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
	var kg := "%.1f / %d kg" % [sim.inventory.weight(sim.data), roundi(sim.carry_limit())]
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
