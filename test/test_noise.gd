extends "res://test/base_test.gd"

const TICK := SimWorld.TICK
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST
const S := BuildGrid.Side.SOUTH
const W := BuildGrid.Side.WEST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## A sim with a smelter at cell (0, 0) (centre 1, 1) that keeps working.
func _smelter_sim(hour := 10.0) -> SimWorld:
	var sim := SimWorld.new(hour)
	if hour >= 21.0:  # these tests isolate ordinary heat/hearing waves from V29's scripted first night
		sim.director.first_night_warning_sent = true
		sim.director.first_night_wave_sent = true
		sim.director.first_morning_sent = true
	sim.power.free = true  # these tests are about noise, not power
	sim.give_debug_kit()
	sim.inventory.add("plank", 200)
	sim.inventory.add("nails", 200)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
	sim.player_pos = Vector3(0, 0, 500)  # far away and out of sight
	return sim


func _wall_in(sim: SimWorld, cell: Vector2i) -> void:
	for side in [N, E, S, W]:
		eq(sim.build.place("wall", cell, side, sim.inventory), "", "wall on %s" % BuildGrid.SIDE_NAMES[side])


func test_heard_level_formula() -> void:
	near(NoiseField.heard_level(80, 1000, 0), 20.0, "generator (80) at 1 km = 20: just heard by day")
	near(NoiseField.heard_level(60, 100, 0), 20.0, "muffled to 60: 100 m")
	near(NoiseField.heard_level(80, 0.3, 0), 80.0, "closer than 1 m counts as 1 m")
	near(NoiseField.heard_level(60, 10, 2), 20.0, "two walls take 20 off")


func test_walls_between() -> void:
	var sim := _smelter_sim()
	var nf := sim.noise
	eq(nf.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -20)), 0, "no walls yet")
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	eq(nf.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -20)), 1, "north wall is crossed going north")
	eq(nf.walls_between(Vector3(1, 1, -20), Vector3(1, 1, 1)), 1, "and coming back south")
	eq(nf.walls_between(Vector3(1, 1, 1), Vector3(20, 1, 1)), 0, "not going east")
	eq(nf.walls_between(Vector3(1, 1, 1), Vector3(1.5, 1, 1.5)), 0, "inside the same cell")
	for side in [E, S, W]:
		sim.build.place("wall", Vector2i(0, 0), side, sim.inventory)
	eq(nf.walls_between(Vector3(1, 1, 1), Vector3(30, 1, 17)), 1, "diagonal out of a closed room: one wall")
	eq(nf.walls_between(Vector3(-5, 1, 1), Vector3(7, 1, 1)), 2, "straight through the room: two walls")


func test_working_machines_make_noise() -> void:
	var sim := _smelter_sim()
	_run(sim, 0.2)
	eq(sim.noise.continuous.size(), 1, "a working smelter is a noise source")
	near(sim.noise.continuous[0]["loudness"], 60.0, "smelter loudness 60")
	eq(sim.noise.continuous[0]["key"], "o:0:0", "tagged with its piece")
	sim.factory.machines[Vector2i(0, 0)].input.clear()
	_run(sim, 3.0)
	eq(sim.noise.continuous.size(), 0, "silent once it runs out of scrap")


func test_muffler_cuts_noise_and_slows() -> void:
	var sim := _smelter_sim()
	var nails := sim.inventory.count("nails")
	eq(sim.fit_muffler(Vector2i(0, 0)), "", "fit a muffler")
	eq(sim.fit_muffler(Vector2i(0, 0)), "Not enough materials", "F5: U again wants a sound box (wall panels)")
	eq(sim.inventory.count("nails"), nails - 8, "costs 8 nails")
	_run(sim, 0.2)
	near(sim.noise.continuous[0]["loudness"], 45.0, "60 - 15 = 45")
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 0)]
	_run(sim, 1.85)
	eq(m.crafted, 0, "not done at 2.05 s (10% slower than 2 s)")
	_run(sim, 0.2)
	eq(m.crafted, 1, "done by 2.25 s")
	sim.build.remove("o:0:0", sim.inventory)
	eq(sim.inventory.count("nails"), nails, "removing the machine refunds the muffler")


func test_zombie_hears_and_walks_to_the_machine() -> void:
	var sim := _smelter_sim()
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -40))  # 41 m away: 60 - 32 = 28 >= 20
	_run(sim, 1.0)
	eq(z.state_name(), "investigate", "hears the smelter 41 m away and goes to look")
	check(z.target_pos.distance_to(Vector3(1, 1, 1)) < 0.01, "heading for the smelter")
	eq(z.move_speed(), float(z.stats["investigate_speed"]), "at investigate speed")
	z.pos = Vector3(1, 0, -0.5)  # the body got there
	_run(sim, 0.1)
	eq(z.state_name(), "break", "reaches the noisy machine and starts wrecking it")
	_run(sim, 20.0)
	check(not sim.build.pieces.has("o:0:0"), "smelter wrecked (150 hp)")


func test_walls_and_night_change_who_hears() -> void:
	var sim := _smelter_sim()
	var far := sim.horde.spawn("shambler", Vector3(1, 0, -70))  # 71 m: 60 - 37 = 23 by day: heard
	_wall_in(sim, Vector2i(0, 0))
	_run(sim, 1.0)
	eq(far.state_name(), "idle", "with walls (13) the zombie at 71 m hears nothing by day")
	var night := _smelter_sim(23.0)
	_wall_in(night, Vector2i(0, 0))
	var z := night.horde.spawn("shambler", Vector3(1, 0, -40))  # 28 - 10 = 18: under 20, over 14
	_run(night, 1.0)
	eq(z.state_name(), "investigate", "at night it hears the walled smelter at 41 m")
	var day := _smelter_sim(10.0)
	_wall_in(day, Vector2i(0, 0))
	var z2 := day.horde.spawn("shambler", Vector3(1, 0, -40))
	_run(day, 1.0)
	eq(z2.state_name(), "idle", "by day it doesn't")


func test_sprinting_is_heard_walking_is_not() -> void:
	var sim := SimWorld.new(10.0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -8))
	z.facing = Vector3.FORWARD  # facing away from the player, so it can't see
	sim.player_pos = Vector3(0, 0, 0)
	for i in 4:
		sim.make_noise(sim.player_pos, "footstep_walk")  # 22 at 8 m = 4: inaudible
		_run(sim, 0.5)
	eq(z.state_name() in ["idle", "wander"], true, "walking 8 m behind it: unheard")
	sim.make_noise(sim.player_pos, "footstep_sprint")  # 40 at 8 m = 22: heard
	_run(sim, 0.6)
	eq(z.state_name(), "investigate", "sprinting: it turns to look")


func test_one_off_sounds_reach_every_zombie_once() -> void:
	var sim := SimWorld.new(10.0)
	var zs := []
	for i in 7:
		zs.append(sim.horde.spawn("shambler", Vector3(i * 2.0, 0, -5)))
	sim.make_noise(Vector3(5, 0, 0), "melee_hit")
	_run(sim, 0.6)
	var all_heard := true
	for z: ZombieBrain in zs:
		all_heard = all_heard and z.state_name() == "investigate"
	check(all_heard, "every zombie got to hear the one-off sound despite staggered listening")
	_run(sim, 2.0)
	eq(sim.noise.recent.size(), 0, "and it fades out of the list")


func test_bashing_draws_more_zombies() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	var basher := sim.horde.spawn("shambler", Vector3(1, 0, -0.6))
	basher.take_hit(0, Vector3(1, 0, 3), 0)  # chasing someone behind the wall
	basher.blocked_by = wall
	var listener := sim.horde.spawn("shambler", Vector3(1, 0, -25))  # bash 50 at 25 m = 22
	sim.player_pos = Vector3(1, 0, 3)
	_run(sim, 1.5)
	eq(basher.state_name(), "break", "one zombie is bashing")
	eq(listener.state_name(), "investigate", "another 25 m off hears the bashing and comes")


func test_director_heat_rises_with_noise_and_cools_when_quiet() -> void:
	var sim := _smelter_sim()
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
	_run(sim, 20.0)
	check(sim.director.heat > 10.0, "a bare smelter heats things up (heat %.1f)" % sim.director.heat)
	near(sim.director.gain, 1.1, "gain = (26 - 15) x 0.1 per second", 0.05)
	var was := sim.director.heat
	sim.factory.machines[Vector2i(0, 0)].input.clear()
	_run(sim, 30.0)  # finishes the plate it's on, then silence
	check(sim.director.heat < was - 4.0, "cools when quiet (%.1f -> %.1f)" % [was, sim.director.heat])


func test_walls_or_muffler_keep_the_director_calm() -> void:
	var walled := _smelter_sim()
	_wall_in(walled, Vector2i(0, 0))
	var muffled := _smelter_sim()
	muffled.fit_muffler(Vector2i(0, 0))
	for sim: SimWorld in [walled, muffled]:
		sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
		sim.director.heat = 5.0
		_run(sim, 10.0)
	check(walled.director.heat < 5.0, "walled-in smelter: heat falls (%.1f)" % walled.director.heat)
	check(muffled.director.heat < 5.0, "muffled smelter: heat falls (%.1f)" % muffled.director.heat)
	var leaky := _smelter_sim()
	for side in [N, E, S]:  # west side left open
		leaky.build.place("wall", Vector2i(0, 0), side, leaky.inventory)
	leaky.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 20
	_run(leaky, 2.0)
	check(leaky.director.gain > 0.5, "a gap in the walls lets the noise out (gain %.2f)" % leaky.director.gain)


func test_director_sends_waves_by_heat_and_time_of_day() -> void:
	var day := _smelter_sim(10.0)
	day.director.heat = 120.0
	var before := day.horde.zombies.size()
	_run(day, 30.1)
	eq(day.horde.zombies.size() - before, 2, "by day even huge heat only sends wanderers (2)")
	check(not day.messages.is_empty(), "with a HUD message")
	var lured: ZombieBrain = day.horde.zombies.values().back()
	eq(lured.state_name(), "investigate", "sent zombies head for the noise")
	check(lured.target_pos.distance_to(Vector3(1, 1, 1)) < 0.01, "toward the smelter")
	# A bare smelter adds about 1.4 heat/s at night, so heat climbs ~42 before the 30 s check.
	var night := _smelter_sim(23.0)
	night.director.heat = 20.0
	_run(night, 30.1)
	eq(night.horde.zombies.size(), roundi(4 * night.director.loud_multiplier()), "night, heat ~62 at the check: a group of 4 (F4: times how loud the smelter is)")
	var horde := _smelter_sim(23.0)
	horde.director.heat = 60.0
	_run(horde, 30.1)
	eq(horde.horde.zombies.size(), roundi(8 * horde.director.loud_multiplier()), "night, heat ~102 at the check: a horde of 8 (F4: times how loud the smelter is)")
	check(horde.director.heat < 70.0, "sending 8 spent 40 heat (%.1f)" % horde.director.heat)
	var quiet := SimWorld.new(23.0)
	quiet.director.first_night_warning_sent = true
	quiet.director.first_night_wave_sent = true
	quiet.director.first_morning_sent = true
	quiet.director.heat = 100.0
	_run(quiet, 30.1)
	eq(quiet.horde.zombies.size(), 0, "no machines running: nothing to lure them to")
