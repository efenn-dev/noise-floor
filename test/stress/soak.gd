extends SceneTree
## Q1 integration soak: plays scripted game days through the REAL game scene (scenes/main.tscn), so every
## system (sim, physics, navmesh, zombie bodies, cars, screens, save/load scene reload) runs together.
## Not a test_*.gd, so tools/test.sh never runs it. Run it with tools/soak.sh [--days=N] (--fixed-fps 60,
## faster than real time). Default one game-day; --days=3 also runs the day-2 wave and the day-3 death.
##
## A bot does the next thing on its list once each game-hour, using the sim's verbs and by moving the
## player node a couple of metres at a time while physics runs (the brief's "set the position, let
## physics run"; walls are stepped through at doors only). Every game-hour it prints one line and checks
## the invariants; at the end it prints "SOAK OK" or "SOAK FAILED: <why>" and exits non-zero on failure.

const MAIN := "res://scenes/main.tscn"
const SAVE := "user://soak_save.json"
const STEP_M := 2.0          # metres per walking step
const STEP_FRAMES := 8       # physics frames per step
const ABSURD := 1000.0
const WALL_LIMIT_S := 1500.0  # give up (and fail) after 25 minutes of wall time
const HOUSE := 1             # town["houses"][1] = house_0_e (east of the road, front door facing west)

var days := 1
var main: Node3D
var sim: SimWorld
var failures: PackedStringArray = []
var notes: PackedStringArray = []   # what the bot did or could not do (one line each, printed at the end)
var extra_zombies := 0               # zombies the bot spawned on purpose (the day-3 death)
var street_and_house := 0
var _mem_hour1 := -1.0
var _worst_phys_ms := 0.0
var _last_hour := -1
var _hours_seen := 0
var _t0 := 0
var _end_abs := 0.0
var _start_abs := 0.0
var _bag_taken := false
var _slept := false
var _saved_snapshot := {}
var _dying := false                  # the day-3 step: stand still, don't fight back
var _swings := 0
var _removed := 0
var _waves_before := -1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = maxi(1, int(arg.get_slice("=", 1)))
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	GameSession.save_path = SAVE
	_t0 = Time.get_ticks_msec()
	change_scene_to_file(MAIN)
	_run()


func _run() -> void:
	while current_scene == null or not current_scene.get("sim"):
		await process_frame
	_grab()
	await _frames(10)
	street_and_house = sim.horde.alive_count()
	_start_abs = _abs_hours()
	_end_abs = _start_abs + 24.0 * days
	print("soak: %d game-day(s) from day %d %s, %d min per game-day, %d zombies at start, %d town pieces" % [
			days, sim.clock.day, sim.clock.clock_text(), Settings.day_minutes, street_and_house, sim.build.pieces.size()])
	var plan := _plan()
	var i := 0
	while _abs_hours() < _end_abs and failures.is_empty():
		if i < plan.size() and _abs_hours() >= _start_abs + float(plan[i][0]):
			var label: String = plan[i][1]
			var step: Callable = plan[i][2]
			i += 1
			if plan[i - 1][0] >= 24.0 * days:
				continue
			if not _dying and not sim.bags.is_empty() and not sim.player.dead:
				print("soak:   %s %s" % [sim.when_text(), await _recover_bags()])
			var why: String = await step.call()
			notes.append("%s %s: %s" % [sim.when_text(), label, why if why != "" else "ok"])
			print("soak:   %s %s -> %s" % [sim.when_text(), label, why if why != "" else "ok"])
		else:
			await _frames(30)
		if (Time.get_ticks_msec() - _t0) / 1000.0 > WALL_LIMIT_S:
			failures.append("ran longer than %.0f s of wall time" % WALL_LIMIT_S)
	_hour_line()  # the last partial hour
	_check_end()
	_finish()


## [hours after the start, label, step]. The start is day 1 08:00.
func _plan() -> Array:
	return [
		[0.0, "walk up the street", _walk_street],
		[1.0, "open house 1's door and go in", _enter_house],
		[2.0, "search its fridge and cabinets", _search_house],
		[3.0, "go out and close the door", _leave_house],
		[4.0, "siphon car_0 and search its trunk", _car_loot],
		[5.0, "build smelter, belts, press (+ power) and hand-feed scrap", _build_factory],
		[6.0, "fit a muffler", _muffler],
		[7.0, "build a workbench and a wall", _bench_and_wall],
		[9.0, "eat and drink", _eat_drink],
		[12.0, "draw the pistol and fire at the nearest zombie", _shoot],
		[13.0, "drive car_0", _drive],
		[14.0, "sleep in house 1's bed", _sleep],
		[19.5, "eat and drink", _eat_drink],
		[20.0, "save (F5), load (F9), continue", _save_load],
		[31.0, "eat and drink", _eat_drink],
		[37.0, "stand in the base at dusk: machines running, heat 100", _wave],
		[50.0, "die among zombies", _die],
		[51.0, "pick up the bag", _take_bag],
	]


# --- Bot steps (each returns "" or a short note) ------------------------------------------------------

func _walk_street() -> String:
	await _walk_to(Vector3(0, 0, -30))
	await _walk_to(_house_door_outside())
	return ""


func _enter_house() -> String:
	var key := _door_key()
	if not sim.build.pieces.get(key, {}).get("open", false):
		sim.toggle_door(key)
	await _frames(10)
	await _walk_to(_door_mid())
	await _walk_to(_door_mid() + _into_house() * 2.0)
	return "" if _in_house() else "not inside (at %s)" % _fmt(main.player.global_position)


func _search_house() -> String:
	var found := 0
	var prefix: String = main.town["houses"][HOUSE]["name"] + "_"
	for c: Dictionary in main.town["containers"]:
		if not String(c["id"]).begins_with(prefix):
			continue
		var at := SimWorld.town_container_pos(c)
		var out := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][c["side"]] as Vector3
		await _walk_to(Vector3(at.x, 0, at.z) - out * 1.2)
		var why := sim.search(c["id"])
		if why != "":
			notes.append("search %s: %s" % [c["id"], why])
			continue
		await _frames(roundi(sim.loot.search_time() * 60.0) + 30)
		found += 1
	return "" if found > 0 else "searched nothing"


func _leave_house() -> String:
	await _walk_to(_door_mid() + _into_house() * 2.0)
	await _walk_to(_door_mid())
	await _walk_to(_house_door_outside())
	var key := _door_key()
	if sim.build.pieces.get(key, {}).get("open", false):
		sim.toggle_door(key)
	return "" if not sim.build.pieces.get(key, {}).get("open", true) else "door still open"


func _car_loot() -> String:
	var car: Vector3 = sim.vehicles.cars["car_0"]["pos"]
	await _walk_to(Vector3(car.x + 2.0, 0, car.z + 3.0))
	var why := sim.siphon("car_0")
	var s := sim.search("car_0")
	if s == "":
		await _frames(roundi(sim.loot.search_time() * 60.0) + 30)
	return "siphon: %s; trunk: %s" % [why, s if s != "" else "searched"]


func _build_factory() -> String:
	await _walk_to(Vector3(0, 0, 6))
	var stock := sim.stock_at(main.player.global_position)
	var E := BuildGrid.Side.EAST
	var errs := PackedStringArray()
	for x in range(-2, 3):
		_try(errs, sim.build.place("foundation", Vector2i(x, 0), 0, stock))
	_try(errs, sim.build.place("smelter", Vector2i(-2, 0), E, stock))
	for x in range(-1, 2):
		if x != 0:
			_try(errs, sim.build.place("belt", Vector2i(x, 0), E, stock))  # two belts, then a gap of floor
	_try(errs, sim.build.place("belt", Vector2i(0, 0), E, stock))  # (the third joins them: smelter -> press)
	_try(errs, sim.build.place("press", Vector2i(2, 0), E, stock))
	_try(errs, sim.build.place("foundation", Vector2i(-2, 1), 0, stock))
	_try(errs, sim.build.place("generator", Vector2i(-2, 1), E, stock))
	_try(errs, sim.build.place("power_pole", Vector2i(0, 1), E, stock))
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(-2, 1)), stock)
	var fed := sim.machine_interact(Vector2i(-2, 0), main.player.global_position)
	if fed.get("fed", {}).is_empty():
		errs.append("hand-feed fed nothing (%s)" % fed)
	return "; ".join(errs)


func _muffler() -> String:
	_take_from_crate({"metal_plate": 4, "nails": 8})
	return sim.fit_muffler(Vector2i(-2, 0))


func _bench_and_wall() -> String:
	var stock := sim.stock_at(main.player.global_position)
	var errs := PackedStringArray()
	_try(errs, sim.build.place("foundation", Vector2i(-3, 0), 0, stock))
	_try(errs, sim.build.place("foundation", Vector2i(-3, 1), 0, stock))
	_try(errs, sim.build.place("workbench", Vector2i(-3, 1), BuildGrid.Side.EAST, stock))
	_try(errs, sim.build.place("wall", Vector2i(-3, 0), BuildGrid.Side.WEST, stock))
	return "; ".join(errs)


func _eat_drink() -> String:
	_take_from_crate({})
	return "%s, %s (food %.0f water %.0f)" % [sim.eat_best(), sim.drink_best(), sim.player.food, sim.player.water]


func _shoot() -> String:
	var had := sim.gear.equipped.has("gun") or _gun_in_pockets()
	if not sim.gear.equipped.has("gun"):
		var uid := _gun_in_pockets()
		if uid > 0:
			sim.equip_gear(uid)
	if not sim.gear.equipped.has("gun"):
		main._give_gun("pistol", false)  # the path --gun uses
	elif sim.guns.hands != "gun":
		sim.swap_hands()
	if sim.inventory.count("ammo_standard") < 10:
		sim.inventory.add("ammo_standard", 30)
	await _frames(60)  # raising the gun
	var shots := 0
	var hits := 0
	for n in 4:
		var z := _nearest_zombie(main.player.global_position)
		if z == null:
			return "no zombie alive"
		var d := Vector2(z.pos.x, z.pos.z).distance_to(Vector2(main.player.global_position.x, main.player.global_position.z))
		if d > 18.0:  # walk closer, keeping some distance
			var to: Vector3 = main.player.global_position.lerp(Vector3(z.pos.x, 0, z.pos.z), 1.0 - 12.0 / d)
			await _walk_to(to)
		_aim_at(z)
		await _frames(2)
		if sim.guns.can_fire() != "" and sim.guns.reloading <= 0.0:
			sim.reload()
			await _frames(150)
		var id: int = main.shooter.fire()
		if id != -2:
			shots += 1
		if id >= 0:
			hits += 1
		await _frames(45)
	return "gun %s; %d shots, %d met a zombie" % ["found" if had else "given (--gun path)", shots, hits]


func _drive() -> String:
	if sim.inventory.count("gas_can") == 0:  # the generator burned the siphoned can: fetch one from the crate
		await _walk_to(Vector3(0, 0, 6))
		_take_from_crate({"gas_can": 1})
	var keyed := sim.vehicles.can_start("car_0", sim.inventory)
	var car: Vector3 = sim.vehicles.cars["car_0"]["pos"]
	await _walk_to(Vector3(car.x + 2.0, 0, car.z))
	var fuel := sim.refuel_car("car_0")  # the bot siphoned it at noon
	var why := sim.enter_car("car_0")
	if why != "":
		return "enter: " + why
	main._enter_car("car_0")
	var body: CarBody = main.cars["car_0"]
	body.use_device_input = false
	body.wish_throttle = 1.0
	await _frames(180)
	body.wish_throttle = 0.0
	body.wish_handbrake = true
	await _frames(120)
	body.wish_handbrake = false
	var moved: float = Vector2(car.x, car.z).distance_to(Vector2(body.global_position.x, body.global_position.z))
	main._exit_car()
	body.use_device_input = true
	await _frames(10)
	return "%s; refuel: %s; moved %.1f m" % ["key found" if keyed else "no key (sat in it)", fuel, moved]


func _sleep() -> String:
	var key := _bed_key()
	if key == "":
		return "no bed in house 1"
	await _walk_to(_house_door_outside())
	var door := _door_key()
	if not sim.build.pieces.get(door, {}).get("open", false):
		sim.toggle_door(door)
	await _walk_to(_door_mid())
	await _walk_to(_door_mid() + _into_house() * 2.0)
	var bed := sim.build.piece_center(key)
	await _walk_to(Vector3(bed.x, 0, bed.z) + Vector3(1.2, 0, 0))
	sim.player.energy = minf(sim.player.energy, float(sim.data.survival["sleep_below_energy"]) - 1.0)
	var why := sim.sleep_in(key)
	if why != "":
		return why
	_slept = true
	var guard := 0
	while sim.player.asleep and guard < 60 * 60 * 6:  # at most 6 real minutes asleep
		await _frames(30)
		guard += 30
	return "slept until %s (energy %.0f)" % [sim.clock.clock_text(), sim.player.energy]


func _save_load() -> String:
	var before := _snapshot()
	_saved_snapshot = before
	var why: String = main.save_game()
	if why != "":
		return "save: " + why
	main.load_game()
	await process_frame
	while current_scene == null or current_scene == main or not current_scene.get("sim"):
		await process_frame
	_grab()
	await _frames(10)
	var after := _snapshot()
	for k: String in before:
		if str(before[k]) != str(after[k]):
			failures.append("save round-trip changed %s: %s -> %s" % [k, before[k], after[k]])
	return "round-trip %s" % ("ok" if failures.is_empty() else "MISMATCH")


## Day 2 dusk: waves need a running machine to home in on, so refuel the generator and feed the smelter,
## then heat 100 (like --heat=100) and stand in the base until the next step.
func _wave() -> String:
	await _walk_to(Vector3(0, 0, 6))
	var stock := sim.stock_at(main.player.global_position)
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(-2, 1)), stock)
	sim.machine_interact(Vector2i(-2, 0), main.player.global_position)
	sim.director.heat = 100.0
	_waves_before = sim.stats.waves
	return "heat %.0f, %d machine noise source(s), waves so far %d" % [sim.director.heat, sim.noise.continuous.size(), sim.stats.waves]


func _die() -> String:
	_dying = true
	await _walk_to(Vector3(0, 0, 4))
	var at: Vector3 = main.player.global_position
	for a in 6:
		var p: Vector3 = at + Vector3(cos(a * TAU / 6.0), 0, sin(a * TAU / 6.0)) * 1.6
		var z := sim.horde.spawn("shambler", Vector3(p.x, 0, p.z))
		z.facing = (at - z.pos).normalized()
		extra_zombies += 1
	var guard := 0
	while not sim.player.dead and guard < 60 * 120:
		await _frames(30)
		guard += 30
	if not sim.player.dead:
		return "still alive after 2 game-minutes among 6 zombies (health %.0f)" % sim.player.health
	return "died (%s), %d bag(s) on the ground" % [sim.player.last_cause, sim.bags.size()]


## After a death the bot walks back for its bag, like a player would.
func _recover_bags() -> String:
	var took := 0
	for bag: Dictionary in sim.bags.duplicate():
		await _walk_to(Vector3(bag["pos"].x + 0.8, 0, bag["pos"].z))
		if not sim.take_bag(bag["id"]).is_empty():
			took += 1
	return "picked up %d bag(s) after dying" % took


func _take_bag() -> String:
	var guard := 0
	while sim.player.dead and guard < 60 * 120:
		await _frames(30)
		guard += 30
	_dying = false
	if sim.bags.is_empty():
		return "no bag"
	var bag: Dictionary = sim.bags[0]
	for id: int in sim.horde.zombies:  # clear the killers off the bag so the walk back is not a second death
		var z: ZombieBrain = sim.horde.zombies[id]
		if not z.is_dead() and z.pos.distance_to(bag["pos"]) < 12.0:
			z.take_hit(10000.0, bag["pos"], 0.0)
	await _walk_to(Vector3(bag["pos"].x + 1.0, 0, bag["pos"].z))
	var took := sim.take_bag(bag["id"])
	_bag_taken = not took.is_empty()
	return "took %d kinds of thing" % took.size()


# --- Helpers ---------------------------------------------------------------------------------------

func _grab() -> void:
	main = current_scene as Node3D
	sim = main.sim
	sim.build.piece_removed.connect(func(key: String, piece: Dictionary) -> void:
		_removed += 1
		if _removed <= 8:
			print("soak:   %s piece gone: %s %s (%s)" % [sim.when_text(), piece.get("id", "?"), key,
					"the player's" if not piece.get("town", false) else "the town's"]))


func _abs_hours() -> float:
	return (sim.clock.day - 1) * 24.0 + sim.clock.time_of_day


## Runs n frames, watching the clock: prints and checks once per game-hour.
func _frames(n: int) -> void:
	for i in n:
		await process_frame
		if main == null or not is_instance_valid(main) or main.is_queued_for_deletion():
			continue
		_worst_phys_ms = maxf(_worst_phys_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		if i % 15 == 0:
			_fight_back()
		var hour := int(floor(_abs_hours()))
		if _last_hour < 0:
			_last_hour = hour
		elif hour != _last_hour:
			_last_hour = hour
			_hour_line()
			_check_hour()


## The bot defends itself like a player would: a swing (sim.swing + sim.hit_zombie) at any zombie within
## arm's reach, except while it is dying on purpose, asleep or in a car.
func _fight_back() -> void:
	if _dying or sim.player.dead or sim.player.asleep or main.driving != null:
		return
	var at: Vector3 = main.player.global_position
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		if z.is_dead() or Vector2(z.pos.x, z.pos.z).distance_to(Vector2(at.x, at.z)) > 2.2:
			continue
		if sim.swing():
			_swings += 1
			sim.hit_zombie(id, false)
		return


func _walk_to(target: Vector3) -> void:
	var p: Player = main.player
	var guard := 0
	while guard < 200 and not sim.player.dead and main.driving == null:
		var here := p.global_position
		var flat := Vector3(target.x - here.x, 0, target.z - here.z)
		if flat.length() < 0.3:
			break
		var step := flat.limit_length(STEP_M)
		p.global_position = Vector3(here.x + step.x, maxf(here.y, 0.1), here.z + step.z)
		p.velocity = Vector3.ZERO
		if flat.length() > 0.5:
			p.set_look(rad_to_deg(atan2(-flat.x, -flat.z)), 0)
		await _frames(STEP_FRAMES)
		guard += 1


func _aim_at(z: ZombieBrain) -> void:
	var eye: Vector3 = main.player.camera.global_position
	var body = main.zombie_view.get("_bodies")
	var target := z.pos + Vector3(0, 1.2, 0)
	if body is Dictionary and (body as Dictionary).has(z.id):
		target = (body as Dictionary)[z.id].global_position + Vector3(0, 1.2, 0)
	var d := target - eye
	main.player.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _nearest_zombie(at: Vector3) -> ZombieBrain:
	var best: ZombieBrain = null
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		if z.is_dead():
			continue
		if best == null or z.pos.distance_to(at) < best.pos.distance_to(at):
			best = z
	return best


func _gun_in_pockets() -> int:
	for piece: Dictionary in sim.gear.pieces:
		if sim.gear.slot_of(piece) == "gun":
			return int(piece["uid"])
	return 0


func _take_from_crate(items: Dictionary) -> void:
	var stock := sim.stock_at(main.player.global_position)
	for crate: Inventory in stock.crates:
		for item: String in items:
			var n := mini(crate.count(item), int(items[item]) - sim.inventory.count(item))
			if n > 0 and crate.remove(item, n):
				sim.inventory.add(item, n)
		for item: String in crate.items():  # food and water too, for eat_best / drink_best
			if sim._is_supply(item):
				var n := crate.count(item)
				crate.remove(item, n)
				sim.inventory.add(item, n)


func _try(errs: PackedStringArray, why: String) -> void:
	if why != "":
		errs.append(why)


func _house() -> Dictionary:
	return main.town["houses"][HOUSE]


func _door_key() -> String:
	return BuildGrid.key_for_wall_edge(_house()["door_cell"], _house()["door_side"])


func _door_mid() -> Vector3:
	var c: Vector2i = _house()["door_cell"]
	return Vector3((c.x + 0.5) * BuildGrid.GRID, 0.1, (c.y + 0.5) * BuildGrid.GRID)


func _into_house() -> Vector3:
	return [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)][_house()["door_side"]]


func _house_door_outside() -> Vector3:
	return _door_mid() - _into_house() * (BuildGrid.GRID / 2.0 + 2.0)


func _in_house() -> bool:
	return BuildGrid.world_to_cell(main.player.global_position) in _house()["cells"]


func _bed_key() -> String:
	for key: String in sim.build.pieces:
		var piece: Dictionary = sim.build.pieces[key]
		if sim.build.kind_of(piece["id"]) == "bed" and BuildGrid.world_to_cell(sim.build.piece_center(key)) in _house()["cells"]:
			return key
	return ""


func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _gear_count() -> int:
	return sim.gear.pieces.size() + sim.gear.equipped.size()


func _xp_total() -> float:
	var t := 0.0
	for k: String in sim.skills.xp:
		t += float(sim.skills.xp[k])
	return t


func _snapshot() -> Dictionary:
	return {"day": sim.clock.day, "clock": sim.clock.clock_text(), "pieces": sim.build.pieces.size(),
			"zombies": sim.horde.alive_count(), "gear": _gear_count(), "skills_xp": snappedf(_xp_total(), 0.01),
			"infamy": snappedf(sim.director.infamy, 0.01), "base_log": sim.base_log.entries.size()}


# --- Watching --------------------------------------------------------------------------------------

func _hour_line() -> void:
	var p := sim.player
	var mem := OS.get_static_memory_usage() / 1048576.0
	if _hours_seen == 1:
		_mem_hour1 = mem
	_hours_seen += 1
	print("soak: day %d %s  hp %.0f food %.0f water %.0f energy %.0f  zombies %d  heat %.0f infamy %.1f  pieces %d  deaths %d  mem %.1f MB  worst physics %.1f ms  nav bakes %d (first %.0f ms)%s%s" % [
			sim.clock.day, sim.clock.clock_text(), p.health, p.food, p.water, p.energy, sim.horde.alive_count(),
			sim.director.heat, sim.director.infamy, sim.build.pieces.size(), sim.tally["deaths"], mem, _worst_phys_ms, main.nav.bakes,
			main.first_bake_ms, "  DEAD" if p.dead else "", "  asleep" if p.asleep else ""])
	_worst_phys_ms = 0.0


func _check_hour() -> void:
	var p := sim.player
	_range("health", p.health, 0.0, p.max_health)
	_range("food", p.food, 0.0, 100.0)
	_range("water", p.water, 0.0, 100.0)
	_range("energy", p.energy, 0.0, 100.0)
	_range("stamina", p.stamina, 0.0, 100.0)
	_range("heat", sim.director.heat, 0.0, float(sim.data.noise["director"]["max_heat"]))
	if sim.carried_kg() < 0.0:
		failures.append("carried weight %.2f < 0" % sim.carried_kg())
	_sane("player", main.player.global_position)
	_sane("sim player_pos", sim.player_pos)
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		if not z.is_dead():
			_sane("zombie %d (%s)" % [id, z.type], z.pos)
	for id: String in sim.vehicles.cars:
		_sane(id, sim.vehicles.cars[id]["pos"])
	var cap := int(sim.data.noise["director"]["max_alive"]) + street_and_house + extra_zombies
	if sim.horde.alive_count() > cap:
		failures.append("%d zombies alive, cap %d (Director %d + street/house %d + bot %d)" % [sim.horde.alive_count(), cap,
				int(sim.data.noise["director"]["max_alive"]), street_and_house, extra_zombies])
	for key: String in sim.build.pieces:
		if main.build_view.body_for(key) == null:
			failures.append("piece %s (%s) has no drawn node" % [key, sim.build.pieces[key]["id"]])
			break


func _check_end() -> void:
	_check_hour()
	if _waves_before >= 0 and sim.stats.waves <= _waves_before:
		failures.append("heat 100 at dusk with machines running sent no wave by the end")
	var mem := OS.get_static_memory_usage() / 1048576.0
	if _mem_hour1 > 0.0 and mem > _mem_hour1 * 1.6:
		failures.append("static memory %.1f MB at the end, %.1f MB after hour 1 (more than 1.6x)" % [mem, _mem_hour1])
	if _saved_snapshot.is_empty() and 24.0 * days > 20.0:
		failures.append("the save/load step never ran")


func _range(what: String, v: float, lo: float, hi: float) -> void:
	if is_nan(v) or v < lo - 0.001 or v > hi + 0.001:
		failures.append("%s %.3f outside [%.0f, %.0f] at %s" % [what, v, lo, hi, sim.when_text()])


func _sane(what: String, v: Vector3) -> void:
	if is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or absf(v.x) > ABSURD or absf(v.y) > ABSURD or absf(v.z) > ABSURD:
		failures.append("%s at an absurd position %s at %s" % [what, v, sim.when_text()])


func _finish() -> void:
	var wall := (Time.get_ticks_msec() - _t0) / 1000.0
	print("soak: bot steps:")
	for n: String in notes:
		print("soak:   " + n)
	var recovered := 0
	for zb: ZombieBody in main.zombie_view.get("_bodies").values():
		recovered += zb.nan_recoveries
	var summary := "NaN moves undone %d; %d game-day(s) in %.0f s wall; deaths %d, kills %d, waves %d, swings %d, gear %d, pieces %d, bag %s" % [
			recovered, days, wall, sim.tally["deaths"], sim.tally["kills"], sim.stats.waves, _swings, _gear_count(), sim.build.pieces.size(),
			"taken" if _bag_taken else "-"]
	if failures.is_empty():
		print("SOAK OK: " + summary)
	else:
		for f: String in failures.slice(0, 10):
			print("soak: FAIL " + f)
		print("SOAK FAILED: %s (%s)" % [failures[0], summary])
	if main != null and is_instance_valid(main):
		main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0 if failures.is_empty() else 1)
