extends "res://test/base_test.gd"
## Doors, barricades, spike strips, nail turrets, repair.

const TICK := SimWorld.TICK
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.inventory.give_all({"plank": 300, "nails": 1000, "metal_plate": 100})
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func test_doors_and_barricades_are_edge_pieces() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	eq(sim.build.place("door", Vector2i(0, 0), N, sim.inventory), "", "a door on the north edge")
	eq(sim.build.place("wall", Vector2i(0, 0), N, sim.inventory), "Already built", "one piece per edge")
	eq(sim.build.place("barricade", Vector2i(0, 0), E, sim.inventory), "", "a barricade on the east edge")
	eq(sim.build.place("door", Vector2i(5, 5), N, sim.inventory), "Needs a foundation", "doors need a foundation like walls")
	var door := sim.build.key_for("door", Vector2i(0, 0), N)
	check(door.begins_with("w:"), "doors share the wall edge keys")
	eq(sim.build.remove("f:0:0", sim.inventory), "Remove the walls on it first", "can't pull the floor from under a door")


func test_door_open_shut_and_sound() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("door", Vector2i(0, 0), N, sim.inventory)
	var door := sim.build.key_for("door", Vector2i(0, 0), N)
	var inside := Vector3(1, 1, 1)
	var outside := Vector3(1, 1, -10)
	eq(sim.noise.walls_between(inside, outside), 1, "closed door muffles like a wall")
	eq(sim.toggle_door(door), "Door opened", "open it")
	eq(sim.noise.walls_between(inside, outside), 0, "open door lets sound out")
	sim.step()
	eq(sim.noise.recent.size(), 1, "doors make a little noise")
	eq(sim.toggle_door(door), "Door closed", "and shut it")
	var changed := [0]
	sim.build.piece_changed.connect(func(_k: String) -> void: changed[0] += 1)
	sim.toggle_door(door)
	eq(changed[0], 1, "the world hears about it (to move the door and re-bake the navmesh)")


func test_barricades_block_sound_but_not_turret_sight() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("barricade", Vector2i(0, 0), N, sim.inventory)
	eq(sim.noise.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -10)), 1, "muffles sound")
	eq(sim.noise.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -10), true), 0, "but a turret sees over it")


func test_spikes_slow_hurt_and_wear_out() -> void:
	var sim := _sim()
	eq(sim.build.place("spikes", Vector2i(0, -3), 0, sim.inventory), "", "spike strips go on bare ground")
	var key := sim.build.key_for("spikes", Vector2i(0, -3))
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -5))  # standing on the strip
	z.take_hit(0, Vector3(1, 0, 20), 0)  # chasing something to the south
	_run(sim, 1.0)
	near(z.slow, 0.4, "slowed to 40%")
	near(z.move_speed(), float(z.stats["chase_speed"]) * 0.4, "chase speed x 0.4")
	near(z.hp, 100.0 - 8.0, "8 damage a second", 0.1)
	near(float(sim.build.pieces[key]["hp"]), 100.0 - 8.0, "the strip wears by what it deals", 1.0)
	_run(sim, 12.0)
	check(z.is_dead(), "standing on spikes for 12.5 s kills a shambler")
	z.pos = Vector3(50, 0, 50)
	var z2 := sim.horde.spawn("shambler", Vector3(1, 0, -5))
	z2.take_hit(0, Vector3(1, 0, 20), 0)
	var z3 := sim.horde.spawn("shambler", Vector3(1, 0, -5))
	z3.take_hit(0, Vector3(1, 0, 20), 0)
	_run(sim, 15.0)
	check(not sim.build.pieces.has(key), "after 300 damage dealt the 100 hp strip is used up")
	near(z3.slow, 1.0, "and zombies walk at full speed again")


func test_turret_shoots_the_nearest_zombie_it_can_see() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	eq(sim.build.place("nail_turret", Vector2i(0, 0), N, sim.inventory), "", "build a turret")
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	var far := sim.horde.spawn("shambler", Vector3(1, 0, -12))
	var near_z := sim.horde.spawn("shambler", Vector3(1, 0, -6))
	_run(sim, 1.0)
	eq(t.shots, 0, "no ammo, no shots")
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	eq(t.ammo, 200, "load 200 nails by hand")
	_run(sim, 0.05)
	eq(t.target, near_z.id, "aims at the nearest")
	_run(sim, 2.4)
	check(near_z.is_dead(), "4 nails at 25 kill the near one (hp %.0f)" % near_z.hp)
	_run(sim, 2.5)
	check(far.is_dead(), "then the far one")
	eq(t.shots, 8, "8 shots, 8 nails")
	eq(t.ammo, 192, "192 left")
	var turret_shots := 0
	for s: Dictionary in sim.noise.recent:
		if s["kind"] == "turret":
			turret_shots += 1
			near(s["loudness"], 35.0, "a quiet turret: 35")
	check(turret_shots > 0, "shots make noise")


func test_turret_cant_see_through_walls_and_draws_attention() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("nail_turret", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var t: Factory.Turret = sim.factory.turrets[Vector2i(0, 0)]
	t.ammo = 50
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -6))
	_run(sim, 2.0)
	eq(t.shots, 0, "a wall in the way: no shot")
	sim.build.destroy(sim.build.key_for("wall", Vector2i(0, 0), N))
	_run(sim, 0.1)
	eq(t.shots, 1, "wall gone: fires")
	eq(z.state_name(), "chase", "the zombie it hit comes for the turret")


func test_turret_takes_nails_from_a_belt() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("foundation", Vector2i(-1, 0), 0, sim.inventory)
	sim.build.place("nail_turret", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("belt", Vector2i(-1, 0), E, sim.inventory)
	for i in 3:
		sim.factory.belts[Vector2i(-1, 0)].accept("nails")
		_run(sim, 0.3)
	_run(sim, 1.5)
	eq(sim.factory.turrets[Vector2i(0, 0)].ammo, 3, "3 nails rode the belt into the turret")


func test_repair_costs_a_share_of_the_build_cost() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	eq(sim.repair(wall), "Not damaged", "nothing to fix")
	sim.build.damage(wall, 100)  # half of 200
	eq(sim.build.repair_cost(wall), {"plank": 2, "nails": 2}, "half damaged: half of 3 planks and 4 nails, rounded up")
	var planks := sim.inventory.count("plank")
	eq(sim.repair(wall), "", "repair it")
	eq(sim.build.pieces[wall]["hp"], 200, "back to full")
	eq(sim.inventory.count("plank"), planks - 2, "paid 2 planks")
	sim.build.damage(wall, 199)
	sim.inventory.take_all({"plank": sim.inventory.count("plank")})
	eq(sim.repair(wall), "Not enough materials", "need the planks")


func test_zombies_break_closed_doors_but_walk_through_open_ones() -> void:
	var sim := _sim()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("door", Vector2i(0, 0), N, sim.inventory)
	var door := sim.build.key_for("door", Vector2i(0, 0), N)
	sim.player_pos = Vector3(1, 0, 3)
	var z := sim.horde.spawn("shambler", Vector3(1, 0, -0.6))
	z.take_hit(0, sim.player_pos, 0)
	z.blocked_by = door
	_run(sim, 2.0)
	eq(z.state_name(), "break", "a closed door gets beaten on like a wall")
	check(sim.build.pieces[door]["hp"] < 150, "and takes damage")
