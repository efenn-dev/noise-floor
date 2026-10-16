extends SceneTree
## Q1 integration soak: plays scripted game days through the REAL game scene (scenes/main.tscn), so every
## system (sim, physics, navmesh, zombie bodies, cars, screens, save/load scene reload) runs together.
## Not a test_*.gd, so tools/test.sh never runs it. Run it with tools/soak.sh [--days=N] [--start-day=D]
## (--fixed-fps 60, faster than real time). Default one game-day; --days=3 also runs the day-2 wave and the
## day-3 death. Q3: --start-day=D starts on day D (like the game's --day) and turns on the winter steps:
## --days=7 --start-day=12 starts in autumn, crosses into winter on day 15 and walks into the park once.
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
const WALL_LIMIT_S := 1440.0  # give up (and fail) after 24 minutes of wall time (tools: timeout 1500)
const HOUSE := 1             # town["houses"][1] = house_0_e (east of the road, front door facing west)

var days := 1
var start_day := 1                   # Q3: --start-day=D; above 1 also turns on the winter steps
var winter := false
const WARM_AT := 50.0                # Q3: under this warmth (in a cold season) the bot goes indoors
const TOWER := "water_tower"
var _stove_key := ""
var _park_ids: Dictionary = {}       # Q3: park zombie id -> drawn yet (chased, investigated, attacked, broke)
## Q4: every live zombie at the save, as {pos, park, drawn}, so _grab() can carry the park watch across the load
## (zombie ids are new after a load; a saved zombie comes back at the same spot).
var _zombies_at_save: Array = []
var _deaths_by_day: Dictionary = {}  # Q3: day -> ["cause@where", ...], from the death tally
var _last_deaths := 0
var _rain_by_season: Dictionary = {}  # Q3: season -> a rain collector's season speed seen there
var _ground_tints: Dictionary = {}   # Q3: ground tints seen (the material's albedo, as html)
var _frozen_seen := false
var _tint_due := -1
var _cold_trips := 0
var _warmth_min := 100.0
var _in_park := false
var _park_note := ""
var _stove_rebuilds := 0
var _start_season := ""
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
var _bandaged := 0                   # Q5: bandages used (H) when a hit made the bot bleed
var _bleeds_unbandaged := 0          # Q5: times it bled with no bandage to use
var _was_bleeding := false
var _removed := 0
var _waves_before := -1
var _waves_carried := 0              # Q3: RunStats is new after a load (headless has no session log to carry it)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = maxi(1, int(arg.get_slice("=", 1)))
		if arg.begins_with("--start-day="):
			start_day = maxi(1, int(arg.get_slice("=", 1)))
	winter = start_day > 1
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
	if winter:
		sim.clock.day = start_day  # what the game's --day does (the season's look follows on the next frame)
		_kit_crate().add("plank", 60)  # Q3: a week of stove fuel on top of the day-1 builds
		await _frames(2)
	_last_deaths = int(sim.tally["deaths"])
	_start_season = sim.clock.season()
	_start_abs = _abs_hours()
	_end_abs = _start_abs + 24.0 * days
	print("soak: %d game-day(s) from day %d %s (%s), %d min per game-day, %d zombies at start (%d in the park), %d town pieces" % [
			days, sim.clock.day, sim.clock.clock_text(), sim.clock.season_name(), Settings.day_minutes, street_and_house,
			_park_ids.size(), sim.build.pieces.size()])
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
		elif winter and _too_cold():
			await _warm_up()
		else:
			await _frames(30)
		if (Time.get_ticks_msec() - _t0) / 1000.0 > WALL_LIMIT_S:
			failures.append("ran longer than %.0f s of wall time" % WALL_LIMIT_S)
	_hour_line()  # the last partial hour
	_check_end()
	_finish()


## [hours after the start, label, step]. The start is day 1 08:00 (Q3: day --start-day 08:00).
func _plan() -> Array:
	var plan := _day1_plan()
	if winter:
		plan.append_array(_winter_plan())
		plan.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return plan


## Q3: the week into winter, on top of the day-1 script: a stove in house 1 on the first evening, planks
## every morning, the bed every night, food and water twice a day, one trip into the park (a warehouse crate,
## the tower's phase-1 plates) and a second save/load mid-week (projects and stoves).
func _winter_plan() -> Array:
	var out := [[13.5, "build a planter and a rain collector in the base, and a stove in house 1", _winter_build]]
	for d in range(1, days):
		out.append([24.0 * d, "fetch planks and load the stove", _load_stove])
		if d >= 1:
			out.append([24.0 * d + 14.0, "sleep in house 1's bed", _sleep])
	for h in range(43, 24 * days, 12):
		out.append([float(h), "eat and drink", _eat_drink])
	out.append([76.0, "walk into the park: a warehouse crate, the tower's plates, and back", _park_visit])
	out.append([78.5, "save (F5), load (F9) mid-week: projects and stoves", _save_load])
	return out


func _day1_plan() -> Array:
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
	var had := sim.gear.gun_slot() != "" or _gun_in_pockets()
	if sim.gear.gun_slot() == "":
		var uid := _gun_in_pockets()
		if uid > 0:
			sim.equip_gear(uid)
	if sim.gear.gun_slot() == "":
		main._give_gun("pistol", false)  # the path --gun uses
	while not sim.guns.in_hand():
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
	var given := sim.inventory.count("gas_can") == 0
	if given:  # nothing left to siphon or fetch: hand the bot a can so the drive step really drives
		sim.inventory.add("gas_can", 1)
	var keyed := sim.vehicles.can_start("car_0", sim.inventory)
	var car: Vector3 = sim.vehicles.cars["car_0"]["pos"]
	await _walk_to(Vector3(car.x + 2.0, 0, car.z))
	var fuel := sim.refuel_car("car_0")  # the bot siphoned it at noon
	var why := sim.enter_car("car_0")
	if why != "":
		return "enter: " + why
	main._enter_car("car_0")
	var state: Dictionary = sim.vehicles.cars["car_0"]
	var engine := "engine %s (fuel %.1f, hp %d)" % ["on" if state["running"] else "off", state["fuel"], state["hp"]]
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
	return "%s; refuel: %s%s; %s; moved %.1f m" % ["key found" if keyed else "no key (sat in it)",
			fuel if fuel != "" else "ok", " (can given)" if given else "", engine, moved]


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
	_zombies_at_save = []
	for zid: int in sim.horde.zombies:
		var sz: ZombieBrain = sim.horde.zombies[zid]
		if not sz.is_dead():
			_zombies_at_save.append({"pos": sz.pos, "park": _park_ids.has(zid), "drawn": _park_ids.get(zid, false)})
	var why: String = main.save_game()
	if why != "":
		return "save: " + why
	_waves_carried += sim.stats.waves
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
	# A chasing zombie may have wrecked a machine since day 1 (allowed); rebuild it, as a player would.
	var rebuilt := PackedStringArray()
	for m: Array in [["smelter", Vector2i(-2, 0)], ["generator", Vector2i(-2, 1)]]:
		if not sim.build.pieces.has(sim.build.key_for(m[0], m[1])):
			var err: String = sim.build.place(m[0], m[1], BuildGrid.Side.EAST, stock)
			rebuilt.append(m[0] + ("" if err == "" else " (failed: %s)" % err))
	var cans := sim.power.load_fuel(sim.build.key_for("generator", Vector2i(-2, 1)), stock)
	sim.machine_interact(Vector2i(-2, 0), main.player.global_position)
	sim.director.heat = 100.0
	_waves_before = _waves()
	await _frames(30)
	return "heat %.0f, %d machine noise source(s), %d gas can(s) loaded, rebuilt [%s], waves so far %d" % [
			sim.director.heat, sim.noise.continuous.size(), cans, ", ".join(rebuilt), _waves()]


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


# --- Q3 winter steps ------------------------------------------------------------------------------

func _winter_build() -> String:
	await _walk_to(Vector3(0, 0, 6))
	var stock := sim.stock_at(main.player.global_position)
	var errs := PackedStringArray()
	for x in [3, 4]:
		_try(errs, sim.build.place("foundation", Vector2i(x, 3), 0, stock))
	_try(errs, sim.build.place("planter", Vector2i(3, 3), BuildGrid.Side.EAST, stock))
	_try(errs, sim.build.place("rain_collector", Vector2i(4, 3), BuildGrid.Side.EAST, stock))
	errs.append(await _build_stove())
	return "; ".join(errs)


## From the base crate's scrap, nails and planks: a stove in house 1 near the bed, loaded.
func _build_stove() -> String:
	_take_from_crate({"scrap_metal": 6, "nails": 6, "plank": 10})
	await _go_into_house()
	var cell := _stove_cell()
	var bed: Vector3 = sim.build.piece_center(_bed_key()) if _bed_key() != "" else main.player.global_position
	var why := sim.build.place("stove", cell, BuildGrid.Side.NORTH, sim.inventory)
	if why != "":
		return "stove at %s: %s" % [cell, why]
	_stove_key = sim.build.key_for("stove", cell)
	var at := sim.build.piece_center(_stove_key)
	return "stove %s %.1f m from the bed; %s" % [_stove_key, Vector2(at.x - bed.x, at.z - bed.z).length(), sim.stove_interact(_stove_key)]


## Each morning: planks from the base crate into the stove (rebuilding the stove first if zombies broke it).
func _load_stove() -> String:
	await _walk_to(Vector3(0, 0, 6))
	if _stove_key == "" or not sim.climate.stoves.has(_stove_key):
		_stove_rebuilds += 1
		return "the stove was gone: " + await _build_stove()
	var before := sim.climate.hours_left(_stove_key)
	_take_from_crate({"plank": 10})
	await _go_into_house()
	var at := sim.build.piece_center(_stove_key)
	await _walk_to(_beside(at))
	return "%s (%.1f h of fuel left before, %.1f after; %d planks in pockets)" % [sim.stove_interact(_stove_key),
			before, sim.climate.hours_left(_stove_key), sim.inventory.count("plank")]


## Once in the park: up the road and through the factory hall's two doorways, into the nearest warehouse
## for one crate, past the water tower (its phase-1 metal plates), then back the same way.
func _park_visit() -> String:
	var first := await _park_trip()
	if not sim.player.dead:
		return first
	await _wait_respawn()
	return first + " | again after respawning: " + await _park_trip()


func _wait_respawn() -> void:
	var guard := 0
	while sim.player.dead and guard < 60 * 120:
		await _frames(30)
		guard += 30


func _park_trip() -> String:
	await _wait_respawn()
	await _walk_to(Vector3(0, 0, 6))
	_take_from_crate({"metal_plate": 10})
	for at: Vector3 in [Vector3(0, 0, -30), Vector3(0, 0, -100), Vector3(0, 0, -126), ParkPlan.ENTRANCE]:
		await _walk_to(at)
	var notes_here := PackedStringArray()
	var wh := _nearest_warehouse(main.player.global_position)
	var door: Vector2i = wh["door_cells"][0]
	var door_mid := Vector3((door.x + 0.5) * BuildGrid.GRID, 0.1, (door.y + 0.5) * BuildGrid.GRID)
	var to_road := -1.0 if wh["east"] else 1.0
	await _walk_to(Vector3(0, 0, door_mid.z))
	await _walk_to(door_mid + Vector3(to_road * 3.0, 0, 0))
	await _walk_to(door_mid)
	await _walk_to(door_mid - Vector3(to_road * 2.0, 0, 0))
	var crate := _nearest_park_crate(wh["name"], main.player.global_position)
	if crate.is_empty():
		notes_here.append("no crate in %s" % wh["name"])
	else:
		var c_at := SimWorld.town_container_pos(crate)
		var out := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][crate["side"]] as Vector3
		await _walk_to(Vector3(c_at.x, 0, c_at.z) - out * 1.2)
		var why := sim.search(crate["id"])
		if why == "":
			await _frames(roundi(sim.loot.search_time() * 60.0) + 30)
		notes_here.append("%s %s: %s" % [wh["name"], crate["id"], why if why != "" else "searched"])
	_in_park = _in_park or ParkPlan.area().has_point(Vector2(main.player.global_position.x, main.player.global_position.z))
	await _walk_to(door_mid)
	await _walk_to(door_mid + Vector3(to_road * 3.0, 0, 0))
	await _walk_to(ParkPlan.TOWER_POS + Vector3(-6.0, 0.0, 1.5))
	notes_here.append("tower: " + sim.project_deliver(TOWER))
	for at: Vector3 in [Vector3(0, 0, ParkPlan.TOWER_POS.z), ParkPlan.ENTRANCE, Vector3(0, 0, -126), Vector3(0, 0, -100),
			Vector3(0, 0, -30), Vector3(0, 0, 6)]:
		await _walk_to(at)
	_park_note = "; ".join(notes_here)
	return _park_note + ("" if not sim.player.dead else "; DIED on the way")


## Q3: in a cold season with warmth under WARM_AT and not under a roof, go into house 1 (by its stove).
func _too_cold() -> bool:
	return not _dying and not sim.player.dead and not sim.player.asleep and main.driving == null \
			and sim.player.warmth < WARM_AT and not sim.is_indoors(main.player.global_position)


func _warm_up() -> void:
	_cold_trips += 1
	var w := sim.player.warmth
	await _go_into_house()
	if _stove_key != "" and sim.climate.stoves.has(_stove_key):
		await _walk_to(_beside(sim.build.piece_center(_stove_key)))
	if _cold_trips <= 12:
		print("soak:   %s cold (warmth %.0f): into house 1 -> %s" % [sim.when_text(), w,
				"inside" if sim.is_indoors(main.player.global_position) else "NOT inside"])
	await _frames(30)


func _go_into_house() -> void:
	if _in_house():
		return
	await _walk_to(_house_door_outside())
	var door := _door_key()
	if not sim.build.pieces.get(door, {}).get("open", false):
		sim.toggle_door(door)
	await _frames(10)
	await _walk_to(_door_mid())
	await _walk_to(_door_mid() + _into_house() * 2.0)


## A free floor cell of house 1 for the stove: no furniture or container, not the door cell or the one inside
## it, no wall between it and the bed; the nearest to the bed that isn't right against it.
func _stove_cell() -> Vector2i:
	var taken := {}
	for c: Dictionary in main.town["containers"]:
		taken[c["cell"]] = true
	var door: Vector2i = _house()["door_cell"]
	taken[door] = true
	taken[BuildGrid.world_to_cell(_door_mid() + _into_house() * 2.0)] = true
	var bed: Vector3 = sim.build.piece_center(_bed_key()) if _bed_key() != "" else _door_mid() + _into_house() * 3.0
	var best := door
	var best_d := INF
	for c: Vector2i in _house()["cells"]:
		var mid := Vector3((c.x + 0.5) * BuildGrid.GRID, 0.0, (c.y + 0.5) * BuildGrid.GRID)
		if taken.has(c) or sim.build.pieces.has("o:%d:%d" % [c.x, c.y]) or sim.noise.walls_between(bed, mid, true) > 0:
			continue
		var d := Vector2(mid.x - bed.x, mid.z - bed.z).length()
		if d > 1.5 and d < best_d:
			best_d = d
			best = c
	return best


## A spot 1.3 m from a piece's middle, on the side toward the player.
func _beside(at: Vector3) -> Vector3:
	var from := Vector3(main.player.global_position.x - at.x, 0, main.player.global_position.z - at.z)
	if from.length() < 0.1:
		from = Vector3(1, 0, 0)
	return Vector3(at.x, 0, at.z) + from.normalized() * 1.3


func _nearest_warehouse(at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for wh: Dictionary in main.park["warehouses"]:
		var r: Rect2 = wh["rect"]
		var d := r.get_center().distance_to(Vector2(at.x, at.z))
		if d < best_d:
			best_d = d
			best = wh
	return best


func _nearest_park_crate(wh_name: String, at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for c: Dictionary in main.park["crates"]:
		if c["warehouse"] != wh_name:
			continue
		var p := SimWorld.town_container_pos(c)
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func _kit_crate() -> Inventory:
	return sim.stock_at(Vector3(2, 0, 6)).crates[0]


# --- Helpers ---------------------------------------------------------------------------------------

func _grab() -> void:
	main = current_scene as Node3D
	sim = main.sim
	# Q3: the park's zombies are the ones standing in it at the start. Q4: after a load (ids are new) each zombie
	# is matched to the one saved at its spot and keeps its watch: a park zombie stays one, drawn or not, wherever
	# it is now, and a zombie that wasn't one (a wave or town zombie standing in the park) isn't made one. Only a
	# zombie that matches nothing falls back to "standing in the park".
	_park_ids.clear()
	for zid: int in sim.horde.zombies:
		var pz: ZombieBrain = sim.horde.zombies[zid]
		if pz.is_dead():
			continue
		var hit: Dictionary = {}
		var best := 0.5
		for saved: Dictionary in _zombies_at_save:
			var d := Vector2(saved["pos"].x - pz.pos.x, saved["pos"].z - pz.pos.z).length()
			if d < best:
				best = d
				hit = saved
		if not hit.is_empty():
			if hit["park"]:
				_park_ids[zid] = hit["drawn"]
		elif ParkPlan.area().has_point(Vector2(pz.pos.x, pz.pos.z)):
			_park_ids[zid] = false
	_last_deaths = int(sim.tally["deaths"])
	sim.build.piece_removed.connect(func(key: String, piece: Dictionary) -> void:
		_removed += 1
		if _removed <= 8:
			var by := ""  # Q2: which zombie broke it, and what it was doing when it started
			for zid: int in sim.horde.zombies:
				var z: ZombieBrain = sim.horde.zombies[zid]
				if z.break_key == key:
					by = "; zombie %d, %s" % [zid, ZombieBrain.STATE_NAMES[z.break_from]]
			print("soak:   %s piece gone: %s %s (%s%s)" % [sim.when_text(), piece.get("id", "?"), key,
					"the player's" if not piece.get("town", false) else "the town's", by]))


## Waves the Director sent since the start, across loads.
func _waves() -> int:
	return _waves_carried + sim.stats.waves


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
			_watch()
		if _tint_due > 0:
			_tint_due -= 1
			if _tint_due == 0:
				_check_tint()
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
	# Q5: H when bleeding, as the HUD tells a player to; count the bleeds it had nothing for.
	if sim.player.bleeding and not _was_bleeding:
		if sim.use_bandage().begins_with("Bandaged"):
			_bandaged += 1
		else:
			_bleeds_unbandaged += 1
	_was_bleeding = sim.player.bleeding
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
		if sim.gear.slot_of(piece) in Gear.FIREARM_SLOTS:
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
	var stoves := {}
	for key: String in sim.climate.stoves:
		stoves[key] = sim.climate.stoves[key]["planks"]
	return {"day": sim.clock.day, "clock": sim.clock.clock_text(), "pieces": sim.build.pieces.size(),
			"zombies": sim.horde.alive_count(), "gear": _gear_count(), "skills_xp": snappedf(_xp_total(), 0.01),
			"infamy": snappedf(sim.director.infamy, 0.01), "base_log": sim.base_log.entries.size(),
			"projects": JSON.stringify(sim.projects.to_dict(), "", true), "projects_done": str(sim.projects.done),
			"stoves": str(stoves), "season": sim.clock.season()}


# --- Watching --------------------------------------------------------------------------------------

func _hour_line() -> void:
	var p := sim.player
	var mem := OS.get_static_memory_usage() / 1048576.0
	if _hours_seen == 1:
		_mem_hour1 = mem
	_hours_seen += 1
	var resting := 0  # W3b/W3c: zombie bodies resting (idle, far from you: see ZombieBody.REST_BEYOND)
	for zb: ZombieBody in main.zombie_view.get("_bodies").values():
		resting += 1 if zb.resting else 0
	print("soak: day %d %s %s  hp %.0f food %.0f water %.0f energy %.0f warmth %.0f  zombies %d (%d resting)  heat %.0f infamy %.1f  pieces %d  deaths %d  mem %.1f MB  worst physics %.1f ms  nav bakes %d (first %.0f ms)%s%s" % [
			sim.clock.day, sim.clock.season_name(), sim.clock.clock_text(), p.health, p.food, p.water, p.energy, p.warmth, sim.horde.alive_count(), resting,
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
	if winter:
		_check_winter_hour()
	for key: String in sim.build.pieces:
		if main.build_view.body_for(key) == null:
			failures.append("piece %s (%s) has no drawn node" % [key, sim.build.pieces[key]["id"]])
			break


## Q3, every 15 frames: which park zombies have been drawn (chase, attack, break, investigate), and each death
## (its day, cause, and where: in house 1 by a stove with planks, or not).
func _watch() -> void:
	for zid: int in _park_ids:
		var z: ZombieBrain = sim.horde.zombies.get(zid)
		if z != null and not z.is_dead() and z.state in [ZombieBrain.State.CHASE, ZombieBrain.State.ATTACK,
				ZombieBrain.State.BREAK, ZombieBrain.State.INVESTIGATE]:
			_park_ids[zid] = true
	_warmth_min = minf(_warmth_min, sim.player.warmth)
	var deaths := int(sim.tally["deaths"])
	if deaths > _last_deaths:
		var inside := _in_house()
		var planks: int = sim.climate.stoves[_stove_key]["planks"] if sim.climate.stoves.has(_stove_key) else -1
		var lit: bool = sim.climate.stoves[_stove_key]["lit"] if sim.climate.stoves.has(_stove_key) else false
		var cause := sim.player.last_cause
		var where := "house 1" if inside else ("park" if ParkPlan.area().has_point(Vector2(main.player.global_position.x,
				main.player.global_position.z)) else "out")
		if not _deaths_by_day.has(sim.clock.day):
			_deaths_by_day[sim.clock.day] = []
		_deaths_by_day[sim.clock.day].append("%s@%s" % [cause, where])
		print("soak:   %s DIED: %s (%s, warmth %.0f, stove planks %d%s)" % [sim.when_text(), cause, where, sim.player.warmth,
				planks, ", lit" if lit else ""])
		if cause == "cold" and inside and (planks > 0 or lit):
			failures.append("died of cold in house 1 with the stove holding %d plank(s) (lit %s) at %s" % [planks, lit, sim.when_text()])
	_last_deaths = deaths


## Q3: the season's tints are on the materials (ground, town and park roofs), a few frames after the hour.
func _check_tint() -> void:
	var season := sim.clock.season()
	var ground: Material = main._ground_mesh.material_override if main._ground_mesh != null else null
	if ground != SeasonLook.ground_material(season):
		failures.append("ground material is not %s's at %s" % [season, sim.when_text()])
	elif ground is StandardMaterial3D:
		_ground_tints[(ground as StandardMaterial3D).albedo_color.to_html()] = season
	var roof := SeasonLook.roof_material(season)
	for view: Variant in [main.town_view, main.park_view]:
		if view != null and not view.roof_meshes.is_empty() and view.roof_meshes[0].material_override != roof:
			failures.append("%s roofs are not %s's at %s" % [view.name, season, sim.when_text()])


## Q3's hourly invariants: warmth in range; planters frozen exactly in winter; the collector's season speed;
## park zombies stay in the park until drawn; the tint check a few frames later.
func _check_winter_hour() -> void:
	_range("warmth", sim.player.warmth, 0.0, 100.0)
	var season := sim.clock.season()
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		if m.id == "planter":
			if m.frozen != (season == "winter"):
				failures.append("planter frozen %s in %s at %s" % [m.frozen, season, sim.when_text()])
			_frozen_seen = _frozen_seen or m.frozen
		elif m.id == "rain_collector":
			_rain_by_season[season] = sim.factory.season_speed(m)
	var park := ParkPlan.area().grow(4.0)
	for zid: int in _park_ids:
		var z: ZombieBrain = sim.horde.zombies.get(zid)
		if z != null and not z.is_dead() and not _park_ids[zid] and not park.has_point(Vector2(z.pos.x, z.pos.z)):
			failures.append("park zombie %d (%s, %s) left the park undrawn, at %s, %s" % [zid, z.type, z.state_name(),
					_fmt(z.pos), sim.when_text()])
			_park_ids[zid] = true  # once
	_tint_due = 5


func _check_end() -> void:
	_check_hour()
	if _waves_before >= 0 and _waves() <= _waves_before:
		failures.append("heat 100 at dusk with machines running sent no wave by the end")
	var mem := OS.get_static_memory_usage() / 1048576.0
	if _mem_hour1 > 0.0 and mem > _mem_hour1 * 1.6:
		failures.append("static memory %.1f MB at the end, %.1f MB after hour 1 (more than 1.6x)" % [mem, _mem_hour1])
	if _saved_snapshot.is_empty() and 24.0 * days > 20.0:
		failures.append("the save/load step never ran")
	if winter:
		_check_winter_end()


## Q3: what the week should have shown by its end.
func _check_winter_end() -> void:
	var seasons := {}
	for t: String in _ground_tints:
		seasons[_ground_tints[t]] = true
	if seasons.size() < 2 and _start_season != sim.clock.season():
		failures.append("the ground tint never changed (%s)" % [_ground_tints])
	if _stove_key == "":
		failures.append("no stove was built")
	if _rain_by_season.has("autumn") and _rain_by_season.has("winter") and is_equal_approx(_rain_by_season["autumn"], _rain_by_season["winter"]):
		failures.append("the rain collector ran at the same speed in autumn and winter (%s)" % [_rain_by_season])
	if sim.clock.season() == "winter" and not _frozen_seen:
		failures.append("winter came but no planter was ever frozen")
	if 24.0 * days > 76.0 and not _in_park:
		failures.append("the bot never got into the park (%s)" % _park_note)


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
	if winter:
		var per_day := PackedStringArray()
		for d in range(start_day, start_day + days + 1):
			var list: Array = _deaths_by_day.get(d, [])
			per_day.append("day %d: %d%s" % [d, list.size(), (" (" + ", ".join(list) + ")") if not list.is_empty() else ""])
		print("soak: deaths by day: " + "; ".join(per_day))
		print("soak: winter: %d cold trip(s) indoors, warmth low %.0f, stove rebuilt %d time(s), stove %s, collector speed by season %s, ground tints %s, park zombies drawn %d of %d" % [
				_cold_trips, _warmth_min, _stove_rebuilds, ("%.1f h of fuel left" % sim.climate.hours_left(_stove_key)) if sim.climate.stoves.has(_stove_key) else "gone",
				_rain_by_season, _ground_tints.values(), _park_ids.values().count(true), _park_ids.size()])
	var recovered := 0
	for zb: ZombieBody in main.zombie_view.get("_bodies").values():
		recovered += zb.nan_recoveries
	var summary := "NaN moves undone %d; %d game-day(s) in %.0f s wall (%.0f s per game-day); deaths %d, kills %d, waves %d, swings %d, bandaged %d, bled with no bandage %d, gear %d, pieces %d, bag %s" % [
			recovered, days, wall, wall / maxf(0.01, (_abs_hours() - _start_abs) / 24.0), sim.tally["deaths"], sim.tally["kills"], _waves(), _swings,
			_bandaged, _bleeds_unbandaged, _gear_count(), sim.build.pieces.size(),
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
