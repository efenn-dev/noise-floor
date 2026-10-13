class_name Interactor
extends Node3D
## Looking at a machine or belt (outside build mode) shows what's in it. E takes a machine's output
## and loads it with any recipe inputs you carry, or picks up everything on a belt.
## Cars: E at the back searches the trunk, E anywhere else gets in (main does the switch when
## entered_car fires), G siphons, R pours in gas cans, T repairs.

signal entered_car(id: String)

const REACH := 4.0

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []

var target_cell := Vector2i.ZERO
var has_target := false
var target_bag := -1  # id of the death bag being looked at, -1 if none
var target_container := ""  # id of the loot container being looked at, "" if none
var target_key := ""  # piece key of the machine/belt/bed/crate being looked at
var target_car := ""  # id of the car being looked at, "" if none
var target_trunk := false  # looking at the car's back (or it's a wreck): E searches instead of getting in
var last_message := ""


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude


func _physics_process(_delta: float) -> void:
	update_target()


func _unhandled_input(event: InputEvent) -> void:
	if not InputSetup.captured():
		return
	if event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("upgrade"):
		upgrade()
	elif event.is_action_pressed("siphon"):
		siphon()
	elif event.is_action_pressed("repair"):
		repair()
	elif event.is_action_pressed("refuel"):
		refuel()


## T on anything you built: repair it (pays part of its cost from pockets and nearby crates).
func repair() -> String:
	update_target()
	if target_car != "":
		var car_why := sim.repair_car(target_car)
		last_message = car_why if car_why != "" else "Repaired"
		return last_message
	if target_key == "":
		return ""
	var why := sim.repair(target_key)
	last_message = why if why != "" else "Repaired"
	return last_message


## G on a car: siphon its gas.
func siphon() -> String:
	update_target()
	if target_car == "":
		return ""
	last_message = sim.siphon(target_car)
	return last_message


## R on a car: pour the gas cans you carry into its tank.
func refuel() -> String:
	update_target()
	if target_car == "":
		return ""
	last_message = sim.refuel_car(target_car)
	return last_message


## U on a machine: fit a muffler.
func upgrade() -> String:
	update_target()
	if not has_target or not (sim.factory.machines.has(target_cell) or sim.power.generators.has(target_key)):
		return ""
	var reason := sim.fit_muffler(target_cell)
	last_message = "Muffler fitted: 15 quieter, 10% slower" if reason == "" else reason
	return last_message


func update_target() -> void:
	var was := target_cell
	var was_bag := target_bag
	var was_container := target_container
	var was_key := target_key
	var was_car := target_car
	has_target = false
	target_bag = -1
	target_container = ""
	target_key = ""
	target_car = ""
	target_trunk = false
	if builder.active:
		return
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REACH,
			Layers.WORLD | Layers.BUILT | Layers.BAG | Layers.TRAP, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] != null and hit["collider"].has_meta("bag_id"):
		target_bag = hit["collider"].get_meta("bag_id")
		if target_bag != was_bag:
			last_message = ""
		return
	if not hit.is_empty() and hit["collider"] is CarBody:
		var car := hit["collider"] as CarBody
		target_car = car.id
		var local: Vector3 = car.to_local(hit["position"])  # the body's front is +Z, so the trunk is -Z
		target_trunk = local.z < -car.size.z * 0.2 or sim.vehicles.why_not(car.id) != ""
		if target_trunk:
			target_container = car.id
		if target_car != was_car:
			last_message = ""
		return
	if not hit.is_empty() and hit["collider"] != null and hit["collider"].has_meta("container_id"):
		target_container = hit["collider"].get_meta("container_id")
		if target_container != was_container:
			last_message = ""
		return
	if hit.is_empty() or hit["collider"] == null or not hit["collider"].has_meta("piece_key"):
		return
	var key: String = hit["collider"].get_meta("piece_key")
	if not sim.build.pieces.has(key):
		return
	target_key = key  # any piece: walls, doors and floors can be repaired
	if key != was_key:
		last_message = ""
	if not key.begins_with("o:"):
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
	if target_car != "" and not target_trunk:
		var car_why := sim.enter_car(target_car)
		last_message = car_why
		if car_why == "":
			entered_car.emit(target_car)
		return car_why
	if target_container != "":
		var why := sim.search(target_container)
		last_message = why
		return why
	if target_key != "" and sim.build.kind_of(sim.build.pieces[target_key]["id"]) == "door":
		last_message = sim.toggle_door(target_key)
		return last_message
	if not has_target:
		return ""
	match sim.build.kind_of(sim.build.pieces[target_key]["id"]):
		"storage":
			var put := sim.deposit(target_key)
			last_message = ("Stored " + _list(put)) if not put.is_empty() else "Nothing to store (food, drink, bandages and bags stay with you)"
			return last_message
		"bed":
			var why := sim.sleep_in(target_key)
			last_message = why if why != "" else "Sleeping... (any key wakes you)"
			return last_message
		"generator":
			var n := sim.power.load_fuel(target_key, sim.stock_at(sim.build.piece_center(target_key)))
			last_message = ("Loaded %d gas can%s" % [n, "s" if n > 1 else ""]) if n > 0 else "No gas cans (G on a car siphons some)"
			return last_message
		"solar", "pole":
			return ""
	# Machines load from your pockets and nearby crates; what they made goes in your pockets.
	var moved: Dictionary = sim.machine_interact(target_cell, sim.build.piece_center(target_key))
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
	if target_car != "":
		return _car_status()
	if target_container != "":
		var c: Dictionary = sim.loot.containers.get(target_container, {})
		var name := sim.loot.display_name(target_container)
		if c.get("searched", false):
			return "%s · searched%s" % [name, ("\n" + last_message) if last_message != "" else ""]
		if sim.loot.active == target_container:
			return "%s · searching %d%%" % [name, roundi(100.0 * sim.loot.progress / sim.loot.search_time())]
		return "%s\n[E] search (stay close; it makes a little noise)%s" % [name, ("\n" + last_message) if last_message != "" else ""]
	if target_key == "" or not sim.build.pieces.has(target_key):
		return ""
	var f := sim.factory
	var lines := PackedStringArray()
	if not has_target:  # a wall, door, barricade or foundation
		var piece: Dictionary = sim.build.pieces[target_key]
		var b: Dictionary = sim.data.buildables[piece["id"]]
		var line := "%s · %d/%d hp" % [b["name"], piece["hp"], b["hp"]]
		if b["kind"] == "door":
			line += " · %s   [E] %s" % ["open" if piece.get("open", false) else "closed", "close" if piece.get("open", false) else "open"]
		lines.append(line)
		_append_repair(lines, piece, b)
		if last_message != "":
			lines.append(last_message)
		return "\n".join(lines)
	var kind := sim.build.kind_of(sim.build.pieces[target_key]["id"]) if sim.build.pieces.has(target_key) else ""
	if kind == "storage":
		var crate: Inventory = sim.storages.get(target_key, Inventory.new())
		var held := {}
		for item: String in crate.items():
			held[item] = crate.count(item)
		lines.append("Storage crate · %s" % _list(held, "empty"))
		lines.append("[E] put away building materials · building and machines use crates within %dm" % int(sim.data.survival["storage_range"]))
	elif kind == "turret":
		var t: Factory.Turret = f.turrets[target_cell]
		lines.append("Nail turret · %d/%d nails · %s · range %d m · loudness %d" % [t.ammo, t.cap,
				"shooting" if t.target != -1 and t.ammo > 0 else ("out of nails" if t.ammo == 0 else "watching"),
				int(sim.data.buildables["nail_turret"]["range"]), int(sim.data.buildables["nail_turret"]["loudness"])])
		lines.append("[E] load nails · or feed it with a belt from any side")
	elif kind == "trap":
		lines.append("Spike strip · slows and hurts zombies that cross it · wears out")
	elif kind == "generator":
		var g: Dictionary = sim.power.generators[target_key]
		var net := sim.power.network_of(target_key)
		var loud: float = sim.data.buildables["generator"]["loudness"] - (float(sim.data.noise["muffler"]["cut"]) if g["muffled"] else 0.0)
		lines.append("Generator · %s · %d gas cans + %ds in the tank · loudness %d%s" % [
				"running at %d%%" % roundi(g["load"] * 100.0) if g["running"] else "idle", g["cans"], roundi(g["fuel"]),
				roundi(loud), " (muffled)" if g["muffled"] else ""])
		lines.append(_network_line(net))
		lines.append("[E] load gas cans%s" % ("" if g["muffled"] else "   [U] fit muffler (%s)" % _list(sim.data.noise["muffler"]["cost"])))
	elif kind == "solar":
		lines.append("Solar panel · silent · %d W now (sunlight only)" % roundi(sim.data.buildables["solar_panel"]["watts_out"] * sim.clock_daylight()))
		lines.append(_network_line(sim.power.network_of(target_key)))
	elif kind == "pole":
		lines.append("Power pole · links anything within %d m" % int(sim.data.buildables["power_pole"]["reach"]))
		lines.append(_network_line(sim.power.network_of(target_key)))
	elif kind == "bed":
		lines.append("Bed · energy %d" % roundi(sim.player.energy))
		lines.append("[E] sleep here (you'll respawn here)")
	elif f.machines.has(target_cell):
		var m: Factory.Machine = f.machines[target_cell]
		lines.append("%s · makes %s · %s · loudness %d%s" % [sim.data.buildables[m.id]["name"], m.recipe["name"],
				m.status(), roundi(sim.noise.machine_loudness(m)), " (muffled)" if m.muffled else ""])
		lines.append("in: %s   out: %s" % [_list(m.input, "empty"), _list(m.output, "empty")])
		if m.watts > 0.0:
			lines.append("needs %d W · %s" % [roundi(m.watts), _network_line(sim.power.network_of(target_key))])
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
	var piece2: Dictionary = sim.build.pieces[target_key]
	var b2: Dictionary = sim.data.buildables[piece2["id"]]
	if piece2["hp"] < b2["hp"]:
		lines.append("%d/%d hp" % [piece2["hp"], b2["hp"]])
		_append_repair(lines, piece2, b2)
	if last_message != "":
		lines.append(last_message)
	return "\n".join(lines)


func _append_repair(lines: PackedStringArray, piece: Dictionary, b: Dictionary) -> void:
	if piece["hp"] < b["hp"]:
		lines.append("[T] repair (%s)" % _list(sim.repair_cost(target_key)))


func _network_line(net: Dictionary) -> String:
	if net.is_empty():
		return "not connected to any power"
	return "network: %d W made / %d W wanted%s" % [roundi(net["supply"]), roundi(net["demand"]),
			"  BROWNOUT: everything stopped" if net["brownout"] else ""]


func _list(counts: Dictionary, empty: String = "nothing") -> String:
	var parts := PackedStringArray()
	for item: String in counts:
		parts.append("%d %s" % [counts[item], sim.data.item_name(item)])
	return ", ".join(parts) if not parts.is_empty() else empty


## What looking at a car shows: what it is, its gas and damage, and what the keys do here.
func _car_status() -> String:
	var c: Dictionary = sim.vehicles.cars[target_car]
	var s := sim.vehicles.stats(target_car)
	var head := "%s · gas %.1f / %d cans · damage %d%%" % [s["name"], c["fuel"], int(s["tank"]),
			roundi(100.0 * (1.0 - float(c["hp"]) / float(s["hp"])))]
	if c["wreck"] != "":
		head += " · wreck: " + String(c["wreck"]).to_lower()
	var keys := PackedStringArray()
	var why := sim.vehicles.why_not(target_car)
	if why != "":
		keys.append(why + ".")  # a wreck: say what's wrong, then what you can still do with it
	if target_trunk:
		var trunk: Dictionary = sim.loot.containers.get(target_car, {})
		if sim.loot.active == target_car:
			keys.append("searching the trunk %d%%" % roundi(100.0 * sim.loot.progress / sim.loot.search_time()))
		elif trunk.get("searched", false):
			keys.append("trunk searched")
		else:
			keys.append("[E] search the trunk")
	else:
		keys.append("[E] get in")
		var hint := sim.vehicles.start_hint(target_car, sim.inventory)
		if hint != "":
			keys.append(hint)  # no key: where to look for one
	if float(c["fuel"]) >= 1.0:
		keys.append("[G] siphon gas")
	if sim.inventory.count("gas_can") > 0 and float(c["fuel"]) <= float(s["tank"]) - 1.0:
		keys.append("[R] pour in gas cans")
	if c["wreck"] == "" and float(c["hp"]) < float(s["hp"]):
		keys.append("[T] repair (metal plate + 4 nails)")
	var lines := PackedStringArray([head, "   ".join(keys)])
	if last_message != "":
		lines.append(last_message)
	return "\n".join(lines)
