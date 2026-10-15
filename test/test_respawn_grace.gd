extends "res://test/base_test.gd"
## Q6: the soak bot died three times in 50 game-minutes on the first night, because the zombies that killed
## it stood at its spawn point when it came back. A few seconds' grace after a respawn fixes the spiral.


func _sim_with_zombie_at_spawn() -> Array:
	var sim := SimWorld.new(12.0, null, 7, "normal")
	for id: int in sim.horde.zombies.keys():
		sim.horde.zombies.erase(id)
	sim.spawn_point = Vector3(0, 0, 0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -2.5))
	z.facing = Vector3(0, 0, 1)
	z.los_clear = true  # the world's sight rays set this; nothing stands between them here
	return [sim, z]


func _die_and_respawn(sim: SimWorld) -> void:
	sim.player.damage(1000.0, "test")
	for i in int(PlayerStats.RESPAWN_TIME / SimWorld.TICK) + 2:
		sim.step()


func test_zombies_ignore_you_for_a_moment_after_respawn() -> void:
	var pair := _sim_with_zombie_at_spawn()
	var sim: SimWorld = pair[0]
	var z: ZombieBrain = pair[1]
	_die_and_respawn(sim)
	check(not sim.player.dead, "back on your feet")
	check(sim.respawn_grace > 0.0, "with a head start (%.1f s)" % sim.respawn_grace)
	var hp: float = sim.player.health
	for i in int(5.0 / SimWorld.TICK):
		sim.step()
	check(z.state != ZombieBrain.State.CHASE and z.state != ZombieBrain.State.ATTACK,
			"the zombie at your spawn takes no notice for the first seconds")
	near(sim.player.health, hp, "and doesn't hurt you", 0.5)
	for i in int(float(sim.data.survival["respawn_grace"]) / SimWorld.TICK):
		sim.step()
	eq(sim.respawn_grace, 0.0, "the head start runs out")
	z.facing = (sim.player_pos - z.pos).normalized()  # idle zombies turn about; face it at you again
	for i in int(1.0 / SimWorld.TICK):
		sim.step()
	check(z.state == ZombieBrain.State.CHASE or z.state == ZombieBrain.State.ATTACK,
			"once the head start is over, standing in its face gets you noticed")


func test_attacking_ends_the_head_start() -> void:
	var pair := _sim_with_zombie_at_spawn()
	var sim: SimWorld = pair[0]
	_die_and_respawn(sim)
	check(sim.respawn_grace > 0.0, "the head start begins")
	sim.swing()
	eq(sim.respawn_grace, 0.0, "a swing ends it")
