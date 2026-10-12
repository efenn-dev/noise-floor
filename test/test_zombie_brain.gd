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
	z.blocked_by = "w:0:0:n"
	_think(z, TICK, Vector3(100, 0, 100), false, {"w:0:0:n": {}})
	eq(z.state, S.IDLE, "a wandering zombie just turns away")


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
	for i in roundi((ZombieBrain.CORPSE_TIME + 0.1) / TICK):
		h.tick(TICK, ctx)
	check(not h.zombies.has(1), "corpse cleared after %.0f s" % ZombieBrain.CORPSE_TIME)
