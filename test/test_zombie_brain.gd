extends "res://test/base_test.gd"

const TICK := SimWorld.TICK
const S := ZombieBrain.State

var data := GameData.load_default()
var stats: Dictionary = data.zombies["shambler"]


func _z(pos := Vector3.ZERO) -> ZombieBrain:
	var z := ZombieBrain.new(1, "shambler", stats, pos, 42)
	z.facing = Vector3.FORWARD  # looking north (-Z)
	return z


## Runs `seconds` of thinking; returns all attack events.
func _think(z: ZombieBrain, seconds: float, player: Vector3, sees: bool, pieces := {}, dead := false) -> Array:
	var events := []
	for i in roundi(seconds / TICK):
		events.append_array(z.think(TICK, player, sees, dead, pieces))
	return events


func test_sight_rules() -> void:
	var eye := Vector3(0, 1.6, 0)
	var f := Vector3.FORWARD
	check(ZombieBrain.can_see(eye, f, Vector3(0, 1.6, -20), true, false, false, stats), "sees 20 m ahead by day")
	check(not ZombieBrain.can_see(eye, f, Vector3(0, 1.6, -20), false, false, false, stats), "not through a wall")
	check(not ZombieBrain.can_see(eye, f, Vector3(0, 1.6, -30), true, false, false, stats), "not 30 m away")
	check(not ZombieBrain.can_see(eye, f, Vector3(0, 1.6, -20), true, true, false, stats), "night cuts sight to 12 m")
	check(ZombieBrain.can_see(eye, f, Vector3(0, 1.6, -20), true, true, true, stats), "a flashlight gives you away at night")
	check(not ZombieBrain.can_see(eye, f, Vector3(0, 1.6, 10), true, false, false, stats), "not behind it")
	check(ZombieBrain.can_see(eye, f, Vector3(0, 1.6, 2), true, false, false, stats), "but senses you right behind it")
	check(ZombieBrain.can_see(eye, f, Vector3(10, 1.6, -10), true, false, false, stats), "45 deg off is inside a 120 deg view")
	check(not ZombieBrain.can_see(eye, f, Vector3(10, 1.6, -2), true, false, false, stats), "80 deg off is outside it")


func test_idle_then_wanders_near_home_then_idles() -> void:
	var z := _z(Vector3(5, 0, 5))
	_think(z, 4.1, Vector3(100, 0, 100), false)
	eq(z.state, S.WANDER, "starts a stroll within 4 s")
	var d := Vector2(z.target_pos.x - 5, z.target_pos.z - 5).length()
	check(d >= 2.0 and d <= ZombieBrain.WANDER_RADIUS, "stroll target near home (%.1f m)" % d)
	check(z.move_speed() == float(stats["wander_speed"]), "walks slowly")
	z.pos = z.target_pos  # the body got there
	_think(z, TICK, Vector3(100, 0, 100), false)
	eq(z.state, S.IDLE, "arrived: back to idle")


func test_same_seed_same_strolls() -> void:
	var a := _z()
	var b := _z()
	_think(a, 5.0, Vector3(100, 0, 100), false)
	_think(b, 5.0, Vector3(100, 0, 100), false)
	check(a.target_pos.is_equal_approx(b.target_pos), "deterministic wandering")


func test_sees_chases_attacks_on_interval() -> void:
	var z := _z()
	var player := Vector3(0, 0, -10)
	_think(z, TICK, player, true)
	eq(z.state, S.CHASE, "sees you: chase")
	check(z.target_pos.is_equal_approx(player), "heads for you")
	check(z.move_speed() == float(stats["chase_speed"]), "at chase speed")
	z.pos = Vector3(0, 0, -9)  # body closed in
	var events := _think(z, 3.0, player, true)
	eq(z.state, S.ATTACK, "in reach: attack")
	eq(z.move_speed(), 0.0, "stands still to hit")
	eq(events.size(), 3, "3 hits in 3 s at 1.2 s intervals (0, 1.2, 2.4)")
	eq(events[0], {"target": "player"}, "hits the player")
	_think(z, TICK, Vector3(0, 0, -5), true)
	eq(z.state, S.CHASE, "you back off: chase again")


func test_loses_you_searches_then_gives_up() -> void:
	var z := _z()
	_think(z, TICK, Vector3(0, 0, -10), true)
	_think(z, 10.0, Vector3(0, 0, -50), false)
	eq(z.state, S.CHASE, "still heading for where it last saw you")
	check(z.target_pos.is_equal_approx(Vector3(0, 0, -10)), "target is the last-seen spot")
	z.pos = Vector3(0, 0, -9.5)  # got there; you're gone
	_think(z, ZombieBrain.LOSE_TIME - 0.5, Vector3(0, 0, -50), false)
	eq(z.state, S.CHASE, "looks around for a bit")
	_think(z, 1.0, Vector3(0, 0, -50), false)
	eq(z.state, S.IDLE, "gives up %.0f s after reaching the spot" % ZombieBrain.LOSE_TIME)
	check(Vector2(z.home.x, z.home.z).distance_to(Vector2(0, -9.5)) < 0.01, "and hangs around there now")


func test_unreachable_chase_times_out() -> void:
	var z := _z()
	_think(z, TICK, Vector3(0, 0, -10), true)
	_think(z, ZombieBrain.CHASE_MEMORY + 0.1, Vector3(0, 0, -50), false)
	eq(z.state, S.IDLE, "gives up after %.0f s if it never gets there" % ZombieBrain.CHASE_MEMORY)


func test_breaks_a_wall_in_the_way() -> void:
	var z := _z()
	var pieces := {"w:0:-1:n": {}}
	_think(z, TICK, Vector3(0, 0, -10), true, pieces)
	z.blocked_by = "w:0:-1:n"
	var events := _think(z, 2.5, Vector3(0, 0, -10), false, pieces)
	eq(z.state, S.BREAK, "stuck on a wall while chasing: break it")
	eq(events.size(), 3, "hits it every 1.2 s")
	eq(events[0], {"target": "w:0:-1:n"}, "hits the wall")
	pieces.erase("w:0:-1:n")
	z.blocked_by = ""
	_think(z, TICK, Vector3(0, 0, -10), false, pieces)
	eq(z.state, S.CHASE, "wall gone: chase on")


func test_wandering_into_a_wall_is_not_breaking() -> void:
	var z := _z()
	_think(z, 4.1, Vector3(100, 0, 100), false)
	eq(z.state, S.WANDER, "out for a stroll")
	var was := z.target_pos - z.pos
	z.blocked_by = "w:0:0:n"
	var events := _think(z, TICK, Vector3(100, 0, 100), false, {"w:0:0:n": {}})
	eq(z.state, S.WANDER, "Q2: a wandering zombie turns away and strolls on")
	check((z.target_pos - z.pos).dot(was) < 0.0, "Q2: toward a new spot away from the wall")
	eq(z.blocked_by, "", "and forgets the bump")
	for i in 600:  # a minute of pressing on it
		z.blocked_by = "w:0:0:n"
		events.append_array(z.think(TICK, Vector3(100, 0, 100), false, false, {"w:0:0:n": {}}))
	eq(events.size(), 0, "never hits it")


## Q2 (the soak broke a town door and house 1's counter on day 1 with nobody chasing anyone): a town with
## its house zombies, run through the real sim step that turns hits into piece damage.
func _town_sim() -> Array:
	var sim := SimWorld.new(12.0, null, 1)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	sim.place_props(plan)
	sim.player_pos = Vector3(0, 0, 500)
	var ids := sim.spawn_house_zombies(plan)
	return [sim, plan, ids]


## The first town piece with id `id` in house `h`'s cells (or on its edges).
func _piece_in(sim: SimWorld, plan: Dictionary, h: int, id: String) -> String:
	for key: String in sim.build.pieces:
		var p: Dictionary = sim.build.pieces[key]
		if p["id"] == id and TownPlan.house_at(plan, p["cell"]) == h:
			return key
	return ""


func test_q2_idle_house_zombie_leaves_the_counter_alone() -> void:
	var t := _town_sim()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var ids: Array = t[2]
	var z: ZombieBrain = null
	var counter := ""
	for i in ids.size():
		counter = _piece_in(sim, plan, plan["zombies"][i]["house"], "counter")
		if counter != "":
			z = sim.horde.zombies[ids[i]]
			break
	check(z != null, "a house zombie with a counter in its house")
	if z == null:
		return
	var hp: int = sim.build.pieces[counter]["hp"]
	z.pos = sim.build.piece_center(counter) + Vector3(0.9, -sim.build.piece_center(counter).y, 0)
	var broke := 0
	for i in roundi(600.0 / TICK):  # ten minutes, no noise, nobody near, leaning on the counter all along
		z.blocked_by = counter
		if i == roundi(300.0 / TICK):  # halfway, it goes for a stroll and walks into it too
			z.state = S.WANDER
			z.target_pos = sim.build.piece_center(counter)
		sim.step()
		if z.state == S.BREAK:
			broke += 1
	eq(broke, 0, "never starts breaking it")
	check(sim.build.pieces.has(counter), "the counter is still there")
	if sim.build.pieces.has(counter):
		eq(sim.build.pieces[counter]["hp"], hp, "not a scratch on it")
	check(z.state == S.IDLE or z.state == S.WANDER, "still idle or strolling (%s)" % z.state_name())


## M16 (reverses W1c's "bashed by zombies like a crate"): furniture is never broken. The house zombie
## investigating a noise with its counter in the way leaves the counter at full hp; so does one chasing you.
func test_m16_zombies_never_break_furniture() -> void:
	var t := _town_sim()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var ids: Array = t[2]
	var z: ZombieBrain = null
	var counter := ""
	for i in ids.size():
		counter = _piece_in(sim, plan, plan["zombies"][i]["house"], "counter")
		if counter != "":
			z = sim.horde.zombies[ids[i]]
			break
	check(z != null, "a house zombie with a counter in its house")
	if z == null:
		return
	var hp: int = sim.build.pieces[counter]["hp"]
	var at := sim.build.piece_center(counter)
	z.pos = Vector3(at.x + 0.9, 0, at.z)
	z.hear(Vector3(at.x - 6.0, 0, at.z))  # a noise on the far side of the counter
	eq(z.state, S.INVESTIGATE, "investigating a noise")
	var broke := 0
	for i in roundi(30.0 / TICK):
		z.blocked_by = counter  # walking into the counter the whole time
		sim.step()
		if z.state == S.BREAK:
			broke += 1
	eq(broke, 0, "an investigator never starts breaking the counter")
	eq(sim.build.pieces[counter]["hp"], hp, "the counter keeps every hit point")
	z.pos = Vector3(at.x + 0.9, 0, at.z)
	z.think(TICK, Vector3(at.x - 3.0, 0, at.z), true, false, sim.build.pieces)  # it sees you behind the counter
	eq(z.state, S.CHASE, "chasing you")
	for i in roundi(30.0 / TICK):
		z.blocked_by = counter
		sim.step()
		if z.state == S.BREAK:
			broke += 1
	eq(broke, 0, "a chaser never breaks it either")
	eq(sim.build.pieces[counter]["hp"], hp, "still full hp")
	z.state = S.BREAK  # one caught mid-break (as before M16) stops
	z.break_key = counter
	sim.step()
	check(z.state != S.BREAK, "a zombie breaking furniture stops (%s)" % z.state_name())


func test_q2_chasing_zombie_breaks_a_closed_door() -> void:
	var t := _town_sim()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var door := _piece_in(sim, plan, 1, "door")
	check(door != "", "house 1 has a door")
	if door == "":
		return
	var z := sim.horde.spawn("shambler", sim.build.piece_center(door) + Vector3(0, 0, 0))
	z.pos.y = 0.0
	z.think(TICK, z.pos + Vector3(3, 0, 0), true, false, sim.build.pieces)  # it saw you go in
	eq(z.state, S.CHASE, "chasing")
	z.blocked_by = door
	var hit := false
	for i in roundi(120.0 / TICK):
		if not sim.build.pieces.has(door):
			break
		z.blocked_by = door
		sim.step()
		hit = hit or z.state == S.BREAK
	check(hit, "a chaser blocked by the closed door breaks it")
	check(not sim.build.pieces.has(door), "the door is gone")


func test_q2_investigating_zombie_breaks_a_wall_in_its_way() -> void:
	var t := _town_sim()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var wall := _piece_in(sim, plan, 1, "town_wall")
	check(wall != "", "house 1 has a wall")
	if wall == "":
		return
	var at := sim.build.piece_center(wall)
	var z := sim.horde.spawn("shambler", Vector3(at.x + 1.0, 0, at.z + 1.0))
	z.hear(Vector3(at.x - 4.0, 0, at.z - 4.0))
	eq(z.state, S.INVESTIGATE, "investigating a sound")
	var hp: int = sim.build.pieces[wall]["hp"]
	var hit := false
	for i in roundi(20.0 / TICK):
		z.blocked_by = wall
		sim.step()
		hit = hit or z.state == S.BREAK
	check(hit, "an investigator blocked by a wall breaks it")
	check(not sim.build.pieces.has(wall) or sim.build.pieces[wall]["hp"] < hp, "the wall is hit")


func test_q2_after_breaking_an_investigator_walks_on_to_the_sound() -> void:
	var z := _z()
	var pieces := {"w:0:-1:n": {}}
	z.hear(Vector3(0, 0, -10))
	z.blocked_by = "w:0:-1:n"
	_think(z, TICK, Vector3(100, 0, 100), false, pieces)
	eq(z.state, S.BREAK, "breaking the wall in its way")
	pieces.erase("w:0:-1:n")
	z.blocked_by = ""
	_think(z, TICK, Vector3(100, 0, 100), false, pieces)
	eq(z.state, S.INVESTIGATE, "wall gone: back to the sound, not a chase after nobody")
	check(z.target_pos.distance_to(Vector3(0, 0, -10)) < 0.01, "still heading for the sound")
	var m := _z()
	var mp := {"o:0:-3": {}}
	m.hear(Vector3(0, 0, -6), "o:0:-3")
	m.blocked_by = "o:0:-3"
	_think(m, TICK, Vector3(100, 0, 100), false, mp)
	mp.erase("o:0:-3")
	m.blocked_by = ""
	_think(m, TICK, Vector3(100, 0, 100), false, mp)
	eq(m.state, S.IDLE, "the noisy machine itself wrecked: it's done")


func test_hits_head_shots_and_death() -> void:
	var z := _z()
	eq(z.take_hit(34, Vector3(0, 0, 2), 3.0), false, "one pipe hit doesn't kill")
	eq(z.state, S.CHASE, "being hit makes it chase you")
	check(z.knockback.z < 0.0, "shoved away from you")
	z.take_hit(34, Vector3(0, 0, 2), 3.0)
	eq(z.take_hit(68, Vector3(0, 0, 2), 3.0), true, "head shot finishes it")
	eq(z.state, S.DEAD, "dead")
	eq(_think(z, 5.0, Vector3(0, 0, -1), true).size(), 0, "dead zombies don't attack")
	eq(z.move_speed(), 0.0, "or move")


func test_player_death_ends_the_chase() -> void:
	var z := _z()
	_think(z, TICK, Vector3(0, 0, -1), true)
	_think(z, TICK, Vector3(0, 0, -1), true, {}, true)
	eq(z.state, S.IDLE, "player died: zombie loses interest")


func test_horde_removes_corpses_and_is_deterministic() -> void:
	var h := Horde.new(data, 7)
	h.spawn_town(6)
	var h2 := Horde.new(data, 7)
	h2.spawn_town(6)
	var same := true
	for id: int in h.zombies:
		same = same and h.zombies[id].pos.is_equal_approx(h2.zombies[id].pos)
		check(absf(h.zombies[id].pos.x) >= 4.5 and h.zombies[id].pos.z < -20.0, "spawns on a sidewalk, away from spawn")
	check(same, "same seed, same spawn spots")
	h.zombies[1].take_hit(1000, Vector3.ZERO, 0)
	eq(h.alive_count(), 5, "one down")
	var ctx := {"player_pos": Vector3(0, 0, 500), "player_dead": false, "night": false, "player_lit": false, "pieces": {}}
	# W3e: a corpse this far away thinks every Horde.THINK_EVERY ticks, so it may go up to that many ticks later
	for i in roundi((ZombieBrain.CORPSE_TIME + 0.1) / TICK) + Horde.THINK_EVERY:
		h.tick(TICK, ctx)
	check(not h.zombies.has(1), "corpse cleared after %.0f s" % ZombieBrain.CORPSE_TIME)


func test_q2_a_bump_from_a_stroll_is_not_in_the_way_to_a_sound() -> void:
	var z := _z()
	var pieces := {"o:0:-1": {}}
	_think(z, 4.1, Vector3(100, 0, 100), false)
	z.blocked_by = "o:0:-1"  # it strolled into the counter on this frame...
	z.hear(Vector3(0, 0, 20))  # ...and hears something behind it
	var events := _think(z, 0.5, Vector3(100, 0, 100), false, pieces)
	eq(z.state, S.INVESTIGATE, "it goes to the sound")
	eq(events.size(), 0, "without breaking the counter it bumped while strolling")
	var c := _z()
	_think(c, 4.1, Vector3(100, 0, 100), false)
	c.blocked_by = "o:0:-1"
	_think(c, TICK, Vector3(0, 0, 10), true, pieces)  # it spots you behind it
	eq(c.state, S.CHASE, "spotted you: chasing, not breaking the counter it strolled into")


## Q4: the one list of what zombies may break. Structure and noise-makers yes; furniture, beds, crates,
## stoves, heaters, workbenches, poles, the water tap, hoppers and the repair station never.
func test_q4_what_zombies_may_break() -> void:
	var horde := Horde.new(data, 1)
	var yes := ["wall", "town_wall", "door", "window", "barricade", "smelter", "press", "generator", "nail_turret",
			"motion_sensor", "noise_sensor", "noisemaker", "floodlight"]
	var no := ["bed", "storage", "stove", "electric_heater", "workbench", "power_pole", "water_tap", "hopper",
			"repair_station", "counter", "table", "couch", "shelf", "bathtub", "toilet"]
	for id: String in yes:
		check(horde.breakable({"k": {"id": id}}, "k"), "zombies may break a %s" % id)
	for id: String in no:
		check(not horde.breakable({"k": {"id": id}}, "k"), "zombies never break a %s" % id)
	check(not horde.breakable({}, "gone"), "nor something that isn't there")


func _first(sim: SimWorld, id: String) -> String:
	var keys := sim.build.pieces.keys()
	keys.sort()
	for key: String in keys:
		if sim.build.pieces[key]["id"] == id:
			return key
	return ""


## Q4: a chaser blocked by a bed goes on round it and never breaks it (the soak lost a town bed every run);
## blocked by a wall, it breaks the wall.
func test_q4_a_chaser_leaves_a_bed_alone_but_breaks_a_wall() -> void:
	var t := _town_sim()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var bed := _first(sim, "bed")
	check(bed != "", "a town bed")
	if bed == "":
		return
	var hp: int = sim.build.pieces[bed]["hp"]
	var at := sim.build.piece_center(bed)
	var z := sim.horde.spawn("shambler", Vector3(at.x + 0.9, 0, at.z))
	z.think(TICK, Vector3(at.x - 3.0, 0, at.z), true, false, sim.build.pieces)  # it saw you behind the bed
	eq(z.state, S.CHASE, "chasing")
	var broke := 0
	var chasing := 0
	for i in roundi(15.0 / TICK):
		z.blocked_by = bed  # walking into the bed the whole time
		sim.step()
		if z.state == S.BREAK:
			broke += 1
		if z.state == S.CHASE:
			chasing += 1
	eq(broke, 0, "it never starts breaking the bed")
	eq(chasing, roundi(15.0 / TICK), "it keeps after you (its path goes round the bed)")
	eq(sim.build.pieces[bed]["hp"], hp, "the bed keeps every hit point")
	var wall := _piece_in(sim, plan, 1, "town_wall")
	var whp: int = sim.build.pieces[wall]["hp"]
	var w := sim.horde.spawn("shambler", sim.build.piece_center(wall) * Vector3(1, 0, 1))
	w.think(TICK, w.pos + Vector3(3, 0, 0), true, false, sim.build.pieces)
	eq(w.state, S.CHASE, "a second one chasing")
	var hit := false
	for i in roundi(10.0 / TICK):
		w.blocked_by = wall
		sim.step()
		hit = hit or w.state == S.BREAK
	check(hit, "blocked by a wall, it breaks it")
	check(not sim.build.pieces.has(wall) or sim.build.pieces[wall]["hp"] < whp, "the wall is hurt")


## Q4: a zombie beside a lit stove, investigating a sound past it (or the stove's own crackle), leaves the
## stove whole (the soak lost house 1's stove once).
func test_q4_an_investigator_leaves_a_stove_whole() -> void:
	var sim := SimWorld.new(22.5, null, 1)
	sim.clock.day = 16
	sim.player_pos = Vector3(0, 0, 500)
	sim.inventory.give_all({"plank": 20, "nails": 20, "scrap_metal": 20})
	var cell := Vector2i(2, 250)
	sim.build.place("foundation", cell, 0, sim.inventory)
	eq(sim.build.place("stove", cell, BuildGrid.Side.EAST, sim.inventory), "", "a stove")
	var key := sim.build.key_for("stove", cell)
	sim.stove_interact(key)
	var hp: int = sim.build.pieces[key]["hp"]
	var at := sim.build.piece_center(key)
	var z := sim.horde.spawn("shambler", Vector3(at.x + 1.0, 0, at.z))
	z.hear(Vector3(at.x - 8.0, 0, at.z))  # a noise on the far side of the stove
	eq(z.state, S.INVESTIGATE, "investigating")
	var broke := 0
	for i in roundi(30.0 / TICK):
		z.blocked_by = key
		sim.step()
		if z.state == S.BREAK:
			broke += 1
	eq(broke, 0, "walking into the stove, it never starts breaking it")
	var y := sim.horde.spawn("shambler", Vector3(at.x + 1.0, 0, at.z))
	y.hear(at, key)  # the stove's own crackle, as if it were a machine to wreck
	var hits := 0
	for i in roundi(30.0 / TICK):
		sim.step()
		if y.state == S.BREAK:
			broke += 1
		if y.break_key == key:
			hits += 1
	check(hits <= 1, "it doesn't stay on the stove (%d ticks)" % hits)
	check(y.state != S.BREAK, "it isn't breaking anything (%s)" % y.state_name())
	check(sim.build.pieces.has(key), "the stove is still there")
	eq(sim.build.pieces[key]["hp"], hp, "with every hit point")
	check(sim.climate.stoves[key]["lit"], "and still burning")
