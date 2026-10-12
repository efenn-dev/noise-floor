extends "res://test/base_test.gd"
## Player health, death, the death bag, respawn, and zombies wrecking buildings, through SimWorld.

const TICK := SimWorld.TICK


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func test_zombie_kills_player_who_drops_bag_and_respawns() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	var planks := sim.inventory.count("plank")
	sim.player_pos = Vector3(0, 0, -1)
	sim.spawn_point = Vector3(0, 0, 50)
	var z := sim.horde.spawn("shambler", Vector3.ZERO)
	z.los_clear = true
	var respawns := [0]
	sim.player.respawned.connect(func() -> void: respawns[0] += 1)
	_run(sim, 1.0)
	near(sim.player.health, 90.0, "first hit: -10 (plus a little bleeding if it drew blood)", 0.6)
	_run(sim, 11.0)  # 10 hits at 1.2 s
	check(sim.player.dead, "dead after 10 hits")
	eq(sim.player.deaths, 1, "one death")
	eq(sim.inventory.items(), [], "pockets emptied")
	eq(sim.bags.size(), 1, "a bag dropped")
	eq(sim.bags[0]["items"].get("plank", 0), planks, "bag holds the planks")
	check(sim.bags[0]["pos"].is_equal_approx(Vector3(0, 0, -1)), "where the player fell")
	_run(sim, PlayerStats.RESPAWN_TIME + 0.1)
	check(not sim.player.dead, "respawned")
	near(sim.player.health, 100.0, "at full health")
	check(sim.player_pos.is_equal_approx(sim.spawn_point), "back at the spawn point")
	eq(respawns[0], 1, "respawned signal once")
	var got := sim.take_bag(sim.bags[0]["id"])
	eq(got.get("plank", 0), planks, "bag picked up")
	eq(sim.inventory.count("plank"), planks, "planks back in pockets")
	eq(sim.bags.size(), 0, "bag gone")


func test_swing_cooldown_and_kill() -> void:
	var sim := SimWorld.new(10.0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	var cd: float = sim.weapon_stats()["cooldown"]
	check(sim.player.try_swing(cd), "first swing")
	check(not sim.player.try_swing(cd), "can't swing again at once")
	_run(sim, cd + 0.05)
	check(sim.player.try_swing(cd), "ready after the cooldown")
	sim.hit_zombie(z.id, false)
	near(z.hp, 66.0, "body hit: 34")
	eq(sim.hit_zombie(z.id, true), true, "head hit: 68 more, dead")


func test_zombies_wreck_walls_without_refund() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	for x in 2:
		sim.build.place("foundation", Vector2i(x, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory)
	sim.build.place("smelter", Vector2i(1, 0), BuildGrid.Side.EAST, sim.inventory)
	sim.factory.machines[Vector2i(1, 0)].input["scrap_metal"] = 5
	var planks := sim.inventory.count("plank")
	var wall := sim.build.key_for("wall", Vector2i(0, 0), BuildGrid.Side.NORTH)
	eq(sim.build.damage(wall, 150), false, "200 hp wall survives 150")
	eq(sim.build.damage(wall, 50), true, "and falls at 200")
	check(not sim.build.pieces.has(wall), "wall gone")
	sim.build.destroy("f:1:0")
	check(not sim.build.pieces.has("o:1:0"), "smelter on a wrecked foundation goes with it")
	check(not sim.factory.machines.has(Vector2i(1, 0)), "and leaves the factory")
	eq(sim.inventory.count("plank"), planks, "no refund for wreckage")
	eq(sim.inventory.count("scrap_metal"), sim.data.debug_kit["scrap_metal"] - 10, "its contents are lost")


func test_horde_breaks_through_via_sim() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), BuildGrid.Side.NORTH)
	sim.player_pos = Vector3(1, 0, 1)
	for i in 2:
		var z := sim.horde.spawn("shambler", Vector3(1, 0, -0.5))
		z.facing = Vector3.BACK
		z.los_clear = true
	_run(sim, TICK)
	for id: int in sim.horde.zombies:
		sim.horde.zombies[id].los_clear = false  # the wall hides you now
		sim.horde.zombies[id].blocked_by = wall
	_run(sim, 12.0)
	check(not sim.build.pieces.has(wall), "two zombies take a 200 hp wall down within 12 s")
