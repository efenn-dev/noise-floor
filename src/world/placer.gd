class_name Placer
extends Node3D
## V34 (Emmitt: "allow placing items"): Place in the inventory hands a thing to this. It shows the thing
## see-through where you aim (any floor, table, counter or shelf, up to REACH away), the mouse wheel turns it,
## left click puts it down (one at a time; it stays ready while you have more), right click or Esc stops.
## The sim checks the reach and moves the thing out of your pockets (SimWorld.place_item / place_gear).

const REACH := 3.2
const TURN_STEP := PI / 12.0  # 15 degrees a wheel notch
const FLAT_ENOUGH := 0.7      # a surface whose normal points at least this much up can hold things
const GHOST_SEE_THROUGH := 0.45

var sim: SimWorld
var camera: Camera3D
var exclude: Array[RID] = []
var item := ""  # the item being placed, or "" while placing a gear piece (uid)
var uid := -1
var turn := 0.0
var last_message := ""
var _ghost: Node3D
var _valid := false
var _at := Vector3.INF


func setup(p_sim: SimWorld, p_camera: Camera3D, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	exclude = p_exclude


func active() -> bool:
	return item != "" or uid >= 0


## Starts placing `p_item` (or the gear piece `p_uid` when p_item is "").
func start(p_item: String, p_uid: int = -1) -> void:
	stop()
	var look := p_item
	if p_item == "":
		var piece := sim.gear.find(p_uid)
		if piece.is_empty():
			return
		look = str(piece.get("base", ""))
	elif sim.inventory.count(p_item) <= 0:
		return
	item = p_item
	uid = p_uid if p_item == "" else -1
	turn = 0.0
	_ghost = BagView.make_model(look)
	_ghost.top_level = true
	_ghost.visible = false
	for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.transparency = GHOST_SEE_THROUGH
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	last_message = "Placing %s: LMB put down, wheel turn, RMB stop" % _name()


func stop() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	item = ""
	uid = -1
	_valid = false


func _name() -> String:
	if item != "":
		return sim.data.item_name(item).to_lower()
	return str(sim.gear.find(uid).get("name", "it"))


## The yaw it goes down at: its front toward you, plus what the wheel added.
func yaw() -> float:
	return camera.global_rotation.y + PI + turn


func _process(_delta: float) -> void:
	if not active() or camera == null:
		return
	if (item != "" and sim.inventory.count(item) <= 0) or (item == "" and sim.gear.find(uid).is_empty()):
		stop()
		return
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REACH,
			Layers.WORLD | Layers.BUILT, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_valid = not hit.is_empty() and (hit["normal"] as Vector3).y >= FLAT_ENOUGH
	_at = hit["position"] if _valid else Vector3.INF
	_ghost.visible = _valid
	if _valid:
		_ghost.global_position = _at
		_ghost.global_rotation = Vector3(0.0, yaw(), 0.0)


## Puts one down where the ghost is. Returns the message to show.
func place() -> String:
	if not _valid:
		return "Aim at a floor, table or shelf"
	var why := sim.place_item(item, _at, yaw()) if item != "" else sim.place_gear(uid, _at, yaw())
	if why != "":
		return why
	var what := _name()
	if item == "" or sim.inventory.count(item) <= 0:
		stop()
		return "Placed " + what
	return "Placed %s (%d left)" % [what, sim.inventory.count(item)]


func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
	if event.is_action_pressed("free_mouse") or event.is_action_pressed("aim"):
		stop()
		sim.add_message("Stopped placing", 1.5)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") and InputSetup.captured():
		sim.add_message(place(), 2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_next"):
		turn += TURN_STEP
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_prev"):
		turn -= TURN_STEP
		get_viewport().set_input_as_handled()
