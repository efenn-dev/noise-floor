extends "res://test/base_test.gd"
## M15: belt- and hopper-fed turrets, crossbow and rifle turrets, turret parts, sensors and their actions,
## floodlights, noisemakers, locked doors, the base log and the radio, bear traps, tripwires, electric fences,
## the repair station and the Director's cached wall counts.

const TICK := SimWorld.TICK
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST
const S := BuildGrid.Side.SOUTH
const W := BuildGrid.Side.WEST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _sim(hour := 10.0) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.inventory.give_all({"plank": 400, "nails": 1000, "metal_plate": 200, "scrap_metal": 100, "gas_can": 10,
			"bolt": 60, "ammo_standard": 80})
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func _put(sim: SimWorld, id: String, cell: Vector2i, side := N, floor := true) -> String:
	if floor and not sim.build.pieces.has("f:%d:%d" % [cell.x, cell.y]):
		sim.build.place("foundation", cell, 0, sim.inventory)
	eq(sim.build.place(id, cell, side, sim.inventory), "", "place %s at %s" % [id, cell])
	return sim.build.key_for(id, cell, side)


func _generator(sim: SimWorld, cell: Vector2i) -> String:
	var gen := _put(sim, "generator", cell)
	sim.power.load_fuel(gen, sim.inventory)
	return gen


func _shots_heard(sim: SimWorld) -> Array:
	var out := []
	for s: Dictionary in sim.noise.recent:
		if s["kind"] == "turret" and s["age"] == 0.0:
			out.append(s["loudness"])
	return out


# --- 1. Turrets fed by belts and hoppers ---------------------------------------------------

func test_a_belt_feeds_a_nail_turret_and_it_shoots() -> void:
	var sim := _sim()
	_put(sim, "nail_turret", Vector2i(0, 0))
	_put(sim, "belt", Vector2i(0, 1), N)  # runs north into the turret's back
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	for i in 4:
		sim.factory.belts[Vector2i(0, 1)].accept("nails")
		_run(sim, 0.3)
	_run(sim, 2.0)
	eq(t.ammo, 4, "4 nails rode the belt in")
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -6))
	_run(sim, 2.5)
	check(z.is_dead(), "and it shot the zombie with them")
	eq(t.ammo, 0, "using all four")


func test_the_hopper_feeds_the_turret_in_front_of_it() -> void:
	var sim := _sim()
	_put(sim, "nail_turret", Vector2i(0, 0))
	var hop := _put(sim, "hopper", Vector2i(0, 1), N)  # facing north: the turret is in front
	var bin: Factory.Bin = sim.factory.bins[Vector2i(0, 1)]
	sim.inventory.remove("nails", sim.inventory.count("nails") - 150)
	var moved := sim.machine_interact(Vector2i(0, 1), sim.build.piece_center(hop))
	eq(moved["fed"].get("nails", 0), 100, "E loads 100 nails, its cap")
	eq(bin.item, "nails", "it holds nails now")
	_run(sim, 0.5)
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	eq(t.ammo, 10, "one a tick into the turret")
	eq(bin.count, 90, "out of the hopper")
	check(not bin.accepts("bolt"), "a hopper holds one kind at a time")
	_put(sim, "belt", Vector2i(0, 2), N)
	sim.factory.belts[Vector2i(0, 2)].accept("nails")
	_run(sim, 1.5)
	check(bin.count + t.ammo >= 101, "a belt tops the hopper up too")


func test_crossbow_and_rifle_turrets() -> void:
	var sim := _sim()
	var cb := _put(sim, "crossbow_turret", Vector2i(0, 0))
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	eq(sim.turret_interact(Vector2i(0, 0), sim.build.piece_center(cb)), "Loaded 30 Crossbow bolts", "E loads 30 bolts")
	var st := sim.defense.turret_stats(t)
	near(st["damage"], 60.0, "crossbow: 60 a bolt")
	near(st["interval"], 2.0, "one every 2 s")
	near(st["range"], 20.0, "20 m")
	near(st["loudness"], 20.0, "near silent: 20")
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -18))
	z.hp = 40.0
	_run(sim, 0.1)
	eq(_shots_heard(sim), [20.0], "one quiet shot")
	check(z.is_dead(), "one bolt kills a hurt shambler (40 hp)")
	var brute := sim.horde.spawn("shambler", Vector3(1, 0, -10))
	brute.hp = 200.0
	_run(sim, 1.9)
	near(brute.hp, 200.0, "nothing more inside 2 s")
	_run(sim, 0.2)
	near(brute.hp, 140.0, "the next bolt after 2 s")

	var sim2 := _sim()
	var rk := _put(sim2, "rifle_turret", Vector2i(0, 0))
	var r: Factory.Turret = sim2.factory.turrets[Vector2i(0, 0)]
	sim2.turret_interact(Vector2i(0, 0), sim2.build.piece_center(rk))
	eq(r.ammo, 40, "40 standard rounds")
	var rs := sim2.defense.turret_stats(r)
	near(rs["damage"], 50.0, "rifle: 50 a round")
	near(rs["interval"], 1.5, "one every 1.5 s")
	near(rs["range"], 35.0, "35 m")
	near(rs["loudness"], 85.0, "loud: 85")
	var far := sim2.horde.spawn("shambler", Vector3(1, 0, -33))
	far.hp = 40.0
	_run(sim2, 1.0)
	eq(r.shots, 0, "no power, no shots")
	_generator(sim2, Vector2i(1, 0))
	_run(sim2, 0.2)
	check(far.is_dead(), "powered: it reaches 33 m")
	near(sim2.power.network_of(rk)["demand"], 20.0, "and draws 20 W")


func test_a_suppressor_on_a_rifle_turret_cuts_loudness_and_wears() -> void:
	var sim := _sim()
	sim.power.free = true
	var rk := _put(sim, "rifle_turret", Vector2i(0, 0))
	var supp := sim.gear.make("oil_filter_suppressor", "civilian", "white")
	var scope := sim.gear.make("scope", "civilian", "white")
	sim.gear.pieces.append(supp)
	sim.gear.pieces.append(scope)
	var msg := sim.turret_interact(Vector2i(0, 0), sim.build.piece_center(rk))
	check(msg.contains("Fitted the Oil-filter suppressor") and msg.contains("Fitted the Scope"), "E fits both (%s)" % msg)
	eq(sim.gear.pieces.size(), 0, "out of your pockets")
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	var st := sim.defense.turret_stats(t)
	near(st["loudness"], 65.0, "85 - 20 = 65 with the oil-filter suppressor")
	near(st["range"], 56.0, "the scope: 35 x 1.6 = 56 m")
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -10))
	z.hp = 1000.0
	_run(sim, 0.1)
	eq(_shots_heard(sim), [65.0], "the shot is 65 loud")
	_run(sim, 4.9)
	eq(t.shots, 4, "four shots")
	near(float(t.parts["muzzle"]["condition"]), 1.0 - 4 * 0.005, "wears 0.5% a shot, as on a gun")
	sim.build.remove(rk, sim.inventory)
	eq(sim.gear.pieces.size(), 2, "pulling the turret down gives the parts back")


# --- 2. Sensors and actions ----------------------------------------------------------------

func test_motion_sensor_quiet_mode_stops_the_network_then_resumes() -> void:
	var sim := _sim()
	_put(sim, "smelter", Vector2i(0, 0), E)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
	var gen := _generator(sim, Vector2i(1, 0))
	var sensor := _put(sim, "motion_sensor", Vector2i(2, 0), N, false)
	eq(sim.automation.sensors[sensor]["action"], "quiet", "quiet mode is the default action")
	_run(sim, 1.0)
	check(sim.power.generators[gen]["running"], "the generator runs")
	check(sim.factory.machines[Vector2i(0, 0)].crafting, "the smelter works")
	var z := sim.horde.spawn("shambler", Vector3(5, 0, -8))
	_run(sim, 0.6)
	check(sim.automation.sensors[sensor]["on"], "it sees the zombie 9 m away")
	check(not sim.power.generators[gen]["running"], "quiet mode: the generator stops")
	check(not sim.factory.machines[Vector2i(0, 0)].powered, "and the smelter")
	var loud := 0
	for s: Dictionary in sim.noise.continuous:
		loud += 1
	eq(loud, 0, "nothing on the network makes a sound")
	check(sim.base_log.lines()[0].contains("Motion sensor") and sim.base_log.lines()[0].contains("quiet mode on"),
			"the log says so (%s)" % sim.base_log.lines()[0])
	z.hurt(1000.0)
	_run(sim, 20.0)
	check(not sim.power.generators[gen]["running"], "still quiet 20 s after it clears")
	_run(sim, 11.0)
	check(sim.power.generators[gen]["running"], "30 s after: the generator is back")
	check(sim.factory.machines[Vector2i(0, 0)].powered, "and the smelter")


func test_motion_sensor_needs_a_clear_line() -> void:
	var sim := _sim()
	var sensor := _put(sim, "motion_sensor", Vector2i(0, 0), N, false)
	sim.build.place("foundation", Vector2i(0, -1), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, -1), S, sim.inventory)
	sim.horde.spawn("shambler", Vector3(1, 0, -6))
	_run(sim, 0.6)
	check(not sim.automation.sensors[sensor]["on"], "a wall between: it doesn't see")
	sim.horde.spawn("shambler", Vector3(1, 0, -13))
	sim.horde.spawn("shambler", Vector3(-10, 0, 1))
	_run(sim, 0.6)
	check(sim.automation.sensors[sensor]["on"], "one in the open 11 m away: it does")


func test_noise_sensor_hears_one_offs_over_its_threshold() -> void:
	var sim := _sim()
	var sensor := _put(sim, "noise_sensor", Vector2i(0, 0), N, false)
	eq(sim.set_sensor_action(sensor, "floodlights"), "", "pick floodlights")
	sim.noise.emit(Vector3(1, 0, -25), 80.0, "horn")
	_run(sim, 0.6)
	check(not sim.automation.sensors[sensor]["on"], "25 m away is out of its 20 m range")
	sim.noise.emit(Vector3(1, 0, -15), 40.0, "footstep_sprint")
	_run(sim, 0.6)
	check(not sim.automation.sensors[sensor]["on"], "a sprint 15 m off is under 30")
	sim.noise.emit(Vector3(1, 0, -15), 60.0, "zombie_bash")
	_run(sim, 0.6)
	check(sim.automation.sensors[sensor]["on"], "banging 15 m off sets it off")


func test_the_decoy_pulls_an_investigating_zombie_away_from_a_wall() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -8))
	z.hear(sim.build.piece_center(wall))
	eq(z.state_name(), "investigate", "a zombie on its way to the wall")
	var nm := _put(sim, "noisemaker", Vector2i(15, 0), N, false)
	_generator(sim, Vector2i(16, 0))
	var sensor := _put(sim, "motion_sensor", Vector2i(2, 0), N, false)
	sim.set_sensor_action(sensor, "decoy")
	_run(sim, 1.2)
	check(sim.automation.noisemakers[nm]["blare"] > 0.0, "the sensor set the noisemaker off")
	eq(z.sound_key, nm, "the zombie goes for the noisemaker instead")
	near(z.sound_pos.x, sim.build.piece_center(nm).x, "30 m away from the wall")
	var heard := false
	for s: Dictionary in sim.noise.recent:
		if s["kind"] == "noisemaker":
			heard = true
			near(s["loudness"], 90.0, "it blares at 90")
	check(heard, "a blare")
	_run(sim, 20.0)
	near(sim.automation.noisemakers[nm]["blare"], 0.0, "20 s of it")
	check(sim.automation.noisemakers[nm]["recharge"] > 58.0, "then 60 s to recharge")
	check(sim.fire_noisemaker(nm).begins_with("Recharging"), "it can't go again yet")
	_run(sim, 60.0)
	eq(sim.fire_noisemaker(nm), "Noisemaker going off", "charged again")


func test_lock_doors_keeps_a_door_shut() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("door", Vector2i(0, 0), S, sim.inventory)
	var door := sim.build.key_for("door", Vector2i(0, 0), S)
	sim.toggle_door(door)
	check(sim.build.pieces[door]["open"], "the door is open")
	var sensor := _put(sim, "motion_sensor", Vector2i(2, 0), N, false)
	sim.set_sensor_action(sensor, "lock_doors")
	var z := sim.horde.spawn("shambler", Vector3(5, 0, -6))
	_run(sim, 0.6)
	check(not sim.build.pieces[door]["open"], "the sensor shut it")
	eq(sim.toggle_door(door), "Locked by a sensor until it clears", "E can't open it")
	z.hurt(1000.0)
	_run(sim, 5.0)
	check(sim.automation.is_locked(door), "still locked 5 s after it clears")
	_run(sim, 6.0)
	eq(sim.toggle_door(door), "Door opened", "10 s after: it opens again")


func test_floodlights_draw_power_only_at_night() -> void:
	var sim := _sim(12.0)
	_generator(sim, Vector2i(0, 0))
	var light := _put(sim, "floodlight", Vector2i(1, 0), N, false)
	var sensor := _put(sim, "motion_sensor", Vector2i(2, 0), N, false)
	sim.set_sensor_action(sensor, "floodlights")
	sim.horde.spawn("shambler", Vector3(5, 0, -6))
	_run(sim, 1.0)
	check(sim.automation.sensors[sensor]["on"], "the sensor is on")
	check(not sim.automation.floodlights[light]["lit"], "by day the floodlight stays dark")
	near(sim.power.network_of(light)["demand"], 0.0, "and draws nothing")
	var night := _sim(22.0)
	_generator(night, Vector2i(0, 0))
	var l2 := _put(night, "floodlight", Vector2i(1, 0), N, false)
	var s2 := _put(night, "motion_sensor", Vector2i(2, 0), N, false)
	night.set_sensor_action(s2, "floodlights")
	_run(night, 1.0)
	check(not night.automation.floodlights[l2]["lit"], "at night, nothing seen: dark")
	night.horde.spawn("shambler", Vector3(5, 0, -6))
	_run(night, 1.0)
	check(night.automation.floodlights[l2]["lit"], "a zombie seen at night: lit")
	near(night.power.network_of(l2)["demand"], 10.0, "drawing 10 W")
	check(night.automation.in_light(Vector3(3, 0, 4)), "you stand in its light 5 m away (zombies see you further)")
	check(not night.automation.in_light(Vector3(3, 0, 20)), "but not 20 m away")
	eq(night.toggle_floodlight(l2), "Floodlight: on every night", "E sets it to light every night")


# --- 3. Base log and radio ---------------------------------------------------------------

func test_the_base_log_records_a_wall_hit_and_a_turret_kill_with_game_time() -> void:
	var sim := _sim(21.5)
	for x in 3:
		sim.build.place("foundation", Vector2i(x, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), W, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), W)
	var z := sim.horde.spawn("shambler", Vector3(-0.6, 0, 1))
	z.state = ZombieBrain.State.CHASE  # Q2: only a chasing or investigating zombie breaks things
	z._start_break(wall)
	_run(sim, 3.0)
	check(sim.build.pieces[wall]["hp"] < 200, "the zombie is hitting the wall")
	var hits := 0
	for e: Dictionary in sim.base_log.entries:
		if e["text"].contains("under attack"):
			hits += 1
			eq(e["text"], "West wall under attack: 1 zombie", "names the wall by where it is")
			check(String(e["when"]).begins_with("day 1 21:"), "with the game time (%s)" % e["when"])
	eq(hits, 1, "once, not every hit")
	sim.build.place("foundation", Vector2i(-2, 0), 0, sim.inventory)  # outside the wall, with the zombie
	sim.build.place("nail_turret", Vector2i(-2, 0), N, sim.inventory)
	sim.factory.turrets[Vector2i(-2, 0)].ammo = 5
	_run(sim, 3.0)
	check(z.is_dead(), "the turret killed it")
	check(sim.base_log.lines()[0].contains("Nail turret") and sim.base_log.lines()[0].contains("killed a shambler"),
			"logged (%s)" % sim.base_log.lines()[0])
	check(sim.base_log.entries.size() <= 50, "keeps at most 50")
	for i in 60:
		sim.base_log.add("filler %d" % i, Vector3.ZERO)
	eq(sim.base_log.entries.size(), 50, "the last 50")


func test_the_radio_only_calls_out_far_events() -> void:
	var sim := _sim()
	sim.inventory.add("radio", 1)
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("nail_turret", Vector2i(0, 0), N, sim.inventory)
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	t.ammo = 1
	sim.player_pos = Vector3(1, 0, 10)  # 10 m away
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -6))
	z.hp = 500.0
	_run(sim, 0.2)
	check(sim.base_log.lines()[0].contains("out of nails"), "the log has it (%s)" % sim.base_log.lines()[0])
	eq(sim.radio_lines.size(), 0, "you're 10 m away: no radio call")
	sim.player_pos = Vector3(1, 0, 200)
	t.ammo = 1
	_run(sim, 1.0)
	eq(sim.radio_lines, ["Nail turret out of nails"], "200 m away: the radio says it")
	var said := false
	for m: Dictionary in sim.messages:
		said = said or m["text"] == "Radio: Nail turret out of nails"
	check(said, "as a HUD line")
	sim.inventory.remove("radio", 1)
	t.ammo = 1
	_run(sim, 1.0)
	eq(sim.radio_lines.size(), 1, "no radio in your pockets: no call")
	var start := SimWorld.new(8.0)
	start.place_start_stash(Vector2i(1, 3))
	eq(start.storages[start.build.key_for("storage", Vector2i(1, 3))].count("radio"), 1, "a new game's crate has a radio")


# --- 4. Traps ------------------------------------------------------------------------------

func test_bear_trap_pins_one_zombie_and_needs_resetting() -> void:
	var sim := _sim()
	var trap := _put(sim, "bear_trap", Vector2i(3, 3), N, false)
	var z := sim.horde.spawn("shambler", Vector3(7, 0, 7))
	z.state = ZombieBrain.State.CHASE
	_run(sim, 0.1)
	check(z.pinned > 14.0, "pinned for 15 s")
	near(z.hp, 90.0, "and bitten for 10")
	near(z.move_speed(), 0.0, "it can't walk")
	check(sim.defense.sprung.has(trap), "the trap is sprung")
	_run(sim, 15.0)
	near(z.pinned, 0.0, "free after 15 s")
	check(z.move_speed() > 0.0, "walking again")
	z.pos = Vector3(30, 0, 30)
	var z2 := sim.horde.spawn("shambler", Vector3(7, 0, 7))
	_run(sim, 0.2)
	near(z2.pinned, 0.0, "a sprung trap catches nothing")
	eq(sim.reset_trap(trap), "Bear trap set", "E resets it")
	_run(sim, 0.1)
	check(z2.pinned > 14.0, "and it catches the next one")
	eq(sim.reset_trap(trap), "Bear trap set", "")


func test_tripwire_rings_and_triggers_sensors() -> void:
	var sim := _sim()
	var wire := _put(sim, "tripwire", Vector2i(0, 0), N, false)
	check(not sim.build.edge_blocks(wire) and not sim.build.edge_blocks(wire, true), "it blocks neither sound nor sight")
	var sensor := _put(sim, "motion_sensor", Vector2i(0, 8), N, false)  # 16 m away: too far to see
	sim.set_sensor_action(sensor, "floodlights")
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -1))  # cell (0, -1), north of the wire
	_run(sim, 0.6)
	check(not sim.automation.sensors[sensor]["on"], "the sensor can't see that far")
	z.pos = Vector3(1, 0, 0.5)  # across into cell (0, 0)
	_run(sim, 0.1)
	var rang := false
	for s: Dictionary in sim.noise.recent:
		if s["kind"] == "bell":
			rang = true
			near(s["loudness"], 60.0, "it rings at 60")
	check(rang, "crossing it rings the bell")
	check(sim.automation.sensors[sensor]["on"], "and sets off the sensor's action")
	check(sim.base_log.lines().size() >= 2, "both in the log")


func test_electric_fence_stuns_and_does_nothing_in_a_brownout() -> void:
	var sim := _sim()
	var fence := _put(sim, "electric_fence", Vector2i(0, 0), N, false)
	_generator(sim, Vector2i(0, 1))
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -0.3))
	z.state = ZombieBrain.State.CHASE
	_run(sim, 0.1)
	near(z.stunned, 3.0, "stunned for 3 s", 0.11)
	near(z.hp, 90.0, "and 10 damage")
	near(z.move_speed(), 0.0, "it stands there")
	eq(z.think(TICK, Vector3(1, 0, -1), true, false, sim.build.pieces), [], "and does nothing at all")
	near(sim.power.network_of(fence)["demand"], 15.0, "the fence draws 15 W")
	var dark := _sim()
	_put(dark, "electric_fence", Vector2i(0, 0), N, false)
	_put(dark, "generator", Vector2i(0, 1))  # no fuel: 15 W wanted, nothing made
	var z2 := dark.horde.spawn("shambler", Vector3(1, 0, -0.3))
	_run(dark, 0.5)
	check(dark.power.networks[0]["brownout"], "a brownout")
	near(z2.stunned, 0.0, "no shock")
	near(z2.hp, 100.0, "no damage")


# --- 5. Repair station ----------------------------------------------------------------------

func test_the_repair_station_spends_a_panel_to_restore_hp() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	sim.build.damage(wall, 120)
	var station := _put(sim, "repair_station", Vector2i(2, 0))
	_generator(sim, Vector2i(3, 0))
	sim.inventory.add("wall_panel", 2)
	var moved := sim.machine_interact(Vector2i(2, 0), sim.build.piece_center(station))
	eq(moved["fed"].get("wall_panel", 0), 2, "E loads 2 wall panels")
	_run(sim, 10.1)
	eq(sim.build.pieces[wall]["hp"], 130, "one panel: 80 -> 130 hp")
	eq(sim.factory.bins[Vector2i(2, 0)].count, 1, "one panel left")
	_run(sim, 10.0)
	eq(sim.build.pieces[wall]["hp"], 180, "the next 10 s: 180")
	_run(sim, 10.0)
	eq(sim.build.pieces[wall]["hp"], 180, "out of panels")
	_put(sim, "belt", Vector2i(1, 0), E)
	sim.factory.belts[Vector2i(1, 0)].accept("wall_panel")
	_run(sim, 1.5)
	eq(sim.build.pieces[wall]["hp"], 200, "a belt feeds it panels too (used at once: it was waiting)")
	check(sim.data.recipes.has("press_wall_panel") and sim.data.recipes["press_wall_panel"]["in"] == {"metal_plate": 2},
			"the Press makes a wall panel from 2 plates")
	check(sim.data.buildables["press"]["recipes"].has("press_bolts"), "and bolts")
	eq(sim.data.recipes["press_bolts"]["out"], {"bolt": 6}, "6 bolts a plate")


# --- 6. The Director's cache ----------------------------------------------------------------

func test_director_cache_gives_the_same_heat_and_recomputes_after_a_wall() -> void:
	var sim := _sim()
	sim.power.free = true
	_put(sim, "smelter", Vector2i(0, 0), E)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
	_run(sim, 0.5)
	var dist := float(sim.data.noise["director"]["listen_distance"])
	var floor_db := float(sim.data.noise["director"]["gain_floor"])
	var rate := float(sim.data.noise["director"]["gain_rate"])
	var expect := 0.0
	for s: Dictionary in sim.noise.continuous:
		expect += maxf(0.0, sim.noise.outdoor_level(s, dist) - floor_db) * rate
	var before := sim.director.recounts
	near(sim.director.gain_now(sim.noise, false), expect, "the same gain as counting walls every time")
	var counted := sim.director.recounts
	sim.director.gain_now(sim.noise, false)
	eq(sim.director.recounts, counted, "asked again: nothing recounted")
	check(counted > before or counted > 0, "it counted once")
	for side in [N, E, S, W]:
		sim.build.place("wall", Vector2i(0, 0), side, sim.inventory)
	var walled := sim.director.gain_now(sim.noise, false)
	check(sim.director.recounts > counted, "a wall placed: it recounts")
	near(walled, maxf(0.0, expect - 10.0 * rate), "walled in: 10 dB less heat (%.2f vs %.2f)" % [walled, expect])


# --- Saving (version 9) ---------------------------------------------------------------------

func test_save_and_load_keeps_sensors_hoppers_parts_traps_and_the_log() -> void:
	var a := _sim(22.0)
	_put(a, "nail_turret", Vector2i(0, 0))
	var hop := _put(a, "hopper", Vector2i(0, 1), N)
	a.machine_interact(Vector2i(0, 1), a.build.piece_center(hop))
	var rk := _put(a, "rifle_turret", Vector2i(3, 0))
	a.gear.pieces.append(a.gear.make("machined_suppressor", "civilian", "white"))
	a.turret_interact(Vector2i(3, 0), a.build.piece_center(rk))
	var ms := _put(a, "motion_sensor", Vector2i(5, 0), N, false)
	var ns := _put(a, "noise_sensor", Vector2i(6, 0), N, false)
	a.set_sensor_action(ms, "decoy")
	a.set_sensor_action(ns, "lock_doors")
	var light := _put(a, "floodlight", Vector2i(7, 0), N, false)
	a.toggle_floodlight(light)
	var trap := _put(a, "bear_trap", Vector2i(9, 9), N, false)
	a.horde.spawn("shambler", Vector3(19, 0, 19))
	a.base_log.add("West wall under attack: 3 zombies", Vector3(-5, 0, 0))
	_run(a, 0.2)
	var hopper_count: int = a.factory.bins[Vector2i(0, 1)].count
	check(hopper_count > 0, "the hopper holds nails")
	check(a.defense.sprung.has(trap), "the trap is sprung")
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(d["version"]), SaveGame.VERSION, "the current version (9 when M15 came in)")
	var b := SimWorld.new()
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.automation.sensors[ms]["action"], "decoy", "the motion sensor's action")
	eq(b.automation.sensors[ns]["action"], "lock_doors", "the noise sensor's action")
	check(b.automation.floodlights[light]["night"], "the floodlight's night setting")
	eq(b.factory.bins[Vector2i(0, 1)].item, "nails", "the hopper's nails")
	eq(b.factory.bins[Vector2i(0, 1)].count, hopper_count, "all of them")
	eq(b.factory.turrets[Vector2i(0, 0)].ammo, a.factory.turrets[Vector2i(0, 0)].ammo, "the turret's nails")
	eq(String(b.factory.turrets[Vector2i(3, 0)].parts["muzzle"]["base"]), "machined_suppressor", "the rifle turret's suppressor")
	near(b.defense.turret_stats(b.factory.turrets[Vector2i(3, 0)])["loudness"], 55.0, "still cutting 30")
	check(b.defense.sprung.has(trap), "the sprung trap")
	eq(b.base_log.lines(), a.base_log.lines(), "the base log, with its times")


func test_version_8_save_loads_with_no_m15_pieces() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v8.json")
	eq(int(d.get("version", 0)), 8, "the fixture is a version-8 save")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.build.pieces.size(), d["pieces"].size(), "every piece, once")
	eq(sim.automation.sensors.size(), 0, "no sensors")
	eq(sim.factory.bins.size(), 0, "no hoppers")
	eq(sim.base_log.entries.size(), 0, "an empty base log")
	eq(sim.factory.turrets[Vector2i(-5, -8)].ammo, 40, "its nail turret keeps its 40 nails")
	eq(sim.factory.turrets[Vector2i(-5, -8)].parts, {}, "with no parts")
	eq(sim.gear.gun_name(), "Pistol", "and its pistol")
	_run(sim, 1.0)
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(again["version"]), SaveGame.VERSION, "saved again as version 9")
	for v in [2, 3, 4, 5, 6, 7]:
		var old := SaveGame.read("res://test/fixtures/save_v%d.json" % v)
		var s := SimWorld.new(8.0, null, int(old.get("seed", 1)))
		eq(SaveGame.apply(s, old), "", "the version-%d fixture still loads" % v)
