class_name Interactor
extends Node3D
## Looking at a machine or belt (outside build mode) shows what's in it. E takes a machine's output
## and loads it with any recipe inputs you carry, or picks up everything on a belt.

const REACH := 4.0

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []

var target_cell := Vector2i.ZERO
var has_target := false
var target_bag := -1  # id of the death bag being looked at, -1 if none
var last_message := ""


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude


func _physics_process(_delta: float) -> void:
	update_target()


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("upgrade"):
		upgrade()


## U on a machine: fit a muffler.
func upgrade() -> String:
	update_target()
	if not has_target or not sim.factory.machines.has(target_cell):
		return ""
	var reason := sim.fit_muffler(target_cell)
	last_message = "Muffler fitted: 15 quieter, 10% slower" if reason == "" else reason
	return last_message


func update_target() -> void:
	var was := target_cell
	var was_bag := target_bag
	has_target = false
	target_bag = -1
	if builder.active:
		return
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REACH,
			Layers.WORLD | Layers.BUILT | Layers.BAG, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] != null and hit["collider"].has_meta("bag_id"):
		target_bag = hit["collider"].get_meta("bag_id")
		if target_bag != was_bag:
			last_message = ""
		return
	if hit.is_empty() or hit["collider"] == null or not hit["collider"].has_meta("piece_key"):
		return
	var key: String = hit["collider"].get_meta("piece_key")
	if not key.begins_with("o:") or not sim.build.pieces.has(key):
		return
	target_cell = sim.build.pieces[key]["cell"]
	has_target = true
	if target_cell != was:
		last_message = ""


func interact() -> String:
	update_target()
	if target_bag != -1:
		var items := sim.take_bag(target_bag)
		last_message = "Took " + _list(items) if not items.is_empty() else ""
		return last_message
	if not has_target:
		return ""
	var moved: Dictionary = sim.factory.hand_interact(target_cell, sim.inventory)
	var parts := PackedStringArray()
	if not moved["took"].is_empty():
		parts.append("Took " + _list(moved["took"]))
	if not moved["fed"].is_empty():
		parts.append("Loaded " + _list(moved["fed"]))
	last_message = " · ".join(parts) if not parts.is_empty() else "Nothing to take or load"
	return last_message


func status_text() -> String:
	if target_bag != -1:
		return "Your bag\n[E] pick it up"
	if not has_target:
		return ""
	var f := sim.factory
	var lines := PackedStringArray()
	if f.machines.has(target_cell):
		var m: Factory.Machine = f.machines[target_cell]
		lines.append("%s · makes %s · %s · loudness %d%s" % [sim.data.buildables[m.id]["name"], m.recipe["name"],
				m.status(), roundi(sim.noise.machine_loudness(m)), " (muffled)" if m.muffled else ""])
		lines.append("in: %s   out: %s" % [_list(m.input, "empty"), _list(m.output, "empty")])
		var names := PackedStringArray()
		for item: String in m.recipe["in"]:
			names.append(sim.data.item_name(item))
		var hint := "[E] take output, load %s" % ", ".join(names)
		if not m.muffled:
			hint += "   [U] fit muffler (%s)" % _list(sim.data.noise["muffler"]["cost"])
		lines.append(hint)
	elif f.belts.has(target_cell):
		lines.append("Belt · %d items" % f.belts[target_cell].items.size())
		lines.append("[E] pick up the items")
	if last_message != "":
		lines.append(last_message)
	return "\n".join(lines)


func _list(counts: Dictionary, empty: String = "nothing") -> String:
	var parts := PackedStringArray()
	for item: String in counts:
		parts.append("%d %s" % [counts[item], sim.data.item_name(item)])
	return ", ".join(parts) if not parts.is_empty() else empty
