extends "res://test/base_test.gd"
## Q4: Old Pete guards the factory hall. TownPlan flags him a guardian of the hall when it places him; he
## never leaves it: a loud machine outside doesn't draw him (an ordinary zombie at his spot goes to it), he
## chases a player who walks into the hall, gives up at the doorway when they walk out and goes back to his
## spot. The flag survives a save and load, and an Old Pete from a save before Q4 becomes a guardian.

const TICK := SimWorld.TICK
const S := ZombieBrain.State
const FAR := Vector3(0, 0, 500)


func _pete_sim() -> Array:
	var sim := SimWorld.new(12.0, null, 1)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	sim.player_pos = FAR
	var pete := sim.spawn_old_pete()
	return [sim, pete]


func _inside(at: Vector3) -> bool:
	return TownPlan.factory_rect().has_point(Vector2(at.x, at.z))


## One tick of the horde with each zombie's body walked straight at its target (the world body's job).
func _tick(sim: SimWorld, player: Vector3, night: bool, see: bool) -> void:
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		z.los_clear = see
		z.blocked_by = ""
	sim.horde.tick(TICK, {"player_pos": player, "player_dead": false, "night": night, "player_lit": false,
			"pieces": sim.build.pieces, "noise": sim.noise})
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		var to := Vector3(z.target_pos.x - z.pos.x, 0, z.target_pos.z - z.pos.z)
		if to.length() > 0.05:
			z.pos += to.normalized() * minf(to.length(), z.move_speed() * TICK)
		if to.length() > 0.3:
			z.facing = to.normalized()


func test_townplan_makes_old_pete_a_guardian_of_the_hall() -> void:
	var t := _pete_sim()
	var pete: ZombieBrain = t[1]
	check(pete.is_guardian(), "Old Pete is a guardian")
	eq(pete.guard_area, TownPlan.factory_rect(), "of the factory hall's footprint")
	check(_inside(pete.guard_spot) and pete.guard_spot == pete.pos, "his spot is where he stands, in the hall")
	eq(pete.hp, 200.0, "his stats are unchanged (200 hp)")
	check(not ZombieBrain.new(9, "shambler", GameData.load_default().zombies["shambler"], Vector3.ZERO, 1).is_guardian(),
			"an ordinary zombie is not")


func test_a_loud_machine_outside_never_draws_old_pete_out_over_a_game_day() -> void:
	var t := _pete_sim()
	var sim: SimWorld = t[0]
	var pete: ZombieBrain = t[1]
	sim.power.free = true
	sim.inventory.give_all({"plank": 20, "scrap_metal": 40})
	var cell := Vector2i(0, -50)  # on the road 14 m south of the hall's doorway
	eq(sim.build.place("foundation", cell, 0, sim.inventory), "", "a foundation outside the hall")
	eq(sim.build.place("smelter", cell, BuildGrid.Side.NORTH, sim.inventory), "", "a smelter on it")
	sim.factory.machines[cell].input["scrap_metal"] = 20
	for i in 10:
		sim.step()
	eq(sim.noise.continuous.size(), 1, "the smelter is running")
	check(not sim.noise.loudest_heard(pete.pos, pete.hearing(true)).is_empty(), "it's loud enough to hear at his spot")
	var control := sim.horde.spawn("shambler", pete.pos + Vector3(2, 0, 0))  # an ordinary zombie beside him
	var left := 0
	var away := 0
	var control_left := false
	var day := roundi(24.0 * sim.clock.seconds_per_hour() / TICK)
	for i in day:
		var hour := fmod(12.0 + i * TICK / sim.clock.seconds_per_hour(), 24.0)
		_tick(sim, FAR, hour >= 21.0 or hour < 5.0, false)
		if not _inside(pete.pos) or not _inside(pete.target_pos):
			left += 1
		if pete.state == S.INVESTIGATE or pete.state == S.BREAK:
			away += 1
		control_left = control_left or not _inside(control.pos)
	check(control_left, "the ordinary zombie beside him leaves the hall for the noise")
	eq(left, 0, "Old Pete never steps (or heads) out of the hall in a game-day")
	eq(away, 0, "and never goes after the sound")
	check(pete.state == S.IDLE and pete.pos.distance_to(pete.guard_spot) < 0.1, "he's idle on his spot (%s)" % pete.state_name())
	eq(pete.hp, 200.0, "unhurt")


func test_old_pete_hears_a_sound_inside_the_hall() -> void:
	var t := _pete_sim()
	var pete: ZombieBrain = t[1]
	pete.hear(pete.pos + Vector3(5, 0, 4))
	eq(pete.state, S.INVESTIGATE, "a sound in the hall: he goes to look")
	var p2: ZombieBrain = _pete_sim()[1]
	p2.hear(Vector3(0, 0, -100))
	eq(p2.state, S.IDLE, "a sound outside: he stays put")
	p2.hear_via([Vector3(0, 0, -90)], Vector3(0, 0, -100))
	eq(p2.state, S.IDLE, "a wave's lure outside: he stays put too")


func test_old_pete_chases_into_the_hall_and_gives_up_at_the_doorway() -> void:
	var t := _pete_sim()
	var sim: SimWorld = t[0]
	var pete: ZombieBrain = t[1]
	var spot := pete.guard_spot
	var door_z := TownPlan.factory_rect().end.y  # the south wall's line (the doorway)
	var outside := Vector3(spot.x, 0, door_z + 8.0)  # 8 m out of the doorway, in his view
	for i in roundi(5.0 / TICK):
		_tick(sim, outside, false, true)
	eq(pete.state, S.IDLE, "a player in plain sight outside the doorway: he stays idle")
	var inside := Vector3(spot.x + 1.0, 0, door_z - 3.0)
	_tick(sim, inside, false, true)
	eq(pete.state, S.CHASE, "the player walks in: he chases")
	var hit := false
	for i in roundi(10.0 / TICK):
		_tick(sim, inside, false, true)
		hit = hit or pete.state == S.ATTACK
	check(hit, "he reaches the player and attacks")
	var path := [Vector3(spot.x, 0, door_z - 1.0), Vector3(spot.x, 0, door_z + 1.0), outside]
	var at_door := Vector3.ZERO
	var given_up := false
	for p: Vector3 in path:
		for i in roundi(1.0 / TICK):
			_tick(sim, p, false, true)
			if not given_up and pete.state == S.WANDER:
				given_up = true
				at_door = pete.pos
	check(given_up, "the player walks out: he gives up")
	check(_inside(at_door) and at_door.z > door_z - 4.0, "at the doorway, still inside (z %.1f, doorway %.1f)" % [at_door.z, door_z])
	eq(pete.target_pos, spot, "heading back to his spot")
	var left := false
	for i in roundi(60.0 / TICK):
		_tick(sim, outside, false, true)
		left = left or not _inside(pete.pos)
	check(not left, "he never stepped outside")
	check(pete.state == S.IDLE and pete.pos.distance_to(spot) < 1.0, "back on his spot, idle (%s, %.1f m)" % [
			pete.state_name(), pete.pos.distance_to(spot)])
	pete.take_hit(10.0, outside, 0.0)  # shot from outside: he doesn't come out for it
	_tick(sim, outside, false, true)
	check(pete.state != S.CHASE and pete.state != S.ATTACK, "shot at from outside, he doesn't chase (%s)" % pete.state_name())


func test_the_guard_is_saved_with_him() -> void:
	var t := _pete_sim()
	var sim: SimWorld = t[0]
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	var b := SimWorld.new(12.0, null, 1)
	eq(SaveGame.apply(b, d), "", "loads")
	var petes := b.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return z.type == "old_pete")
	eq(petes.size(), 1, "Old Pete is back")
	if petes.size() == 1:
		var p: ZombieBrain = petes[0]
		check(p.is_guardian(), "still a guardian")
		eq(p.guard_area, TownPlan.factory_rect(), "of the hall")
		check(p.guard_spot.distance_to(TownPlan.factory()["pete"]["pos"]) < 0.01, "same spot")
	for zd: Dictionary in d["zombies"]:  # a save from before Q4 has no guard field
		zd.erase("guard")
	var c := SimWorld.new(12.0, null, 1)
	eq(SaveGame.apply(c, d), "", "a save without the field loads")
	var old := c.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return z.type == "old_pete")
	check(old.size() == 1 and old[0].is_guardian(), "and his Old Pete guards the hall from now on")
	var plain := c.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return z.type != "old_pete" and z.is_guardian())
	eq(plain.size(), 0, "no other zombie is a guardian")
