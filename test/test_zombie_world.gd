extends "res://test/base_test.gd"
## Scripted physics runs of zombies: chase and bite, break a wall, get hit by the pipe, path around a building.

var _scene: Node3D
var sim: SimWorld
var player: Player
var zview: ZombieView


func _setup(player_pos: Vector3) -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	_add_box(Vector3(0, -1, 0), Vector3(100, 2, 100))  # ground
	sim = SimWorld.new(10.0)
	sim.give_debug_kit()
	player = Player.new()
	player.use_device_input = false
	player.position = player_pos
	_scene.add_child(player)
	zview = ZombieView.new()
	_scene.add_child(zview)


func _start_zombies() -> void:
	zview.setup(sim, player)


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _add_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_scene.add_child(body)


## Physics at 60 Hz with a sim tick every 3rd frame (20 Hz), like the game.
func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func _zombie(pos: Vector3, look: Vector3) -> ZombieBrain:
	var z := sim.horde.spawn("shambler", pos)
	z.facing = look
	return z


func test_zombie_chases_and_bites() -> void:
	_setup(Vector3.ZERO)
	var z := _zombie(Vector3(0, 0, -8), Vector3.BACK)
	_start_zombies()
	await _run(1.0)
	eq(z.state, ZombieBrain.State.CHASE, "sees the player 8 m away and chases")
	await _run(7.0)
	var d := Vector2(z.pos.x, z.pos.z).length()
	check(d < 2.0, "closed in (%.1f m)" % d)
	check(sim.player.health < 100.0, "and bit (health %d)" % sim.player.health)
	await _teardown()


func test_zombie_breaks_a_wall_between_you() -> void:
	_setup(Vector3(1, 0, 5))
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	sim.build.place("foundation", Vector2i(0, 1), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 1), BuildGrid.Side.NORTH, sim.inventory)  # wall line z = 2, x 0..2
	var wall := sim.build.key_for("wall", Vector2i(0, 1), BuildGrid.Side.NORTH)
	var z := _zombie(Vector3(1, 0, -1), Vector3.BACK)
	z.take_hit(0, player.position, 0)  # it knows where you are
	_start_zombies()
	await _run(4.0)
	eq(z.state_name(), "break", "stuck on the wall: breaking it")
	check(sim.build.pieces.has(wall) and sim.build.pieces[wall]["hp"] < 200, "wall is taking damage")
	await _teardown()


func test_pipe_hits_head_and_body() -> void:
	_setup(Vector3.ZERO)
	var builder := BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	var melee := Melee.new()
	_scene.add_child(melee)
	melee.setup(sim, player.camera, builder, [player.get_rid()])
	var z := _zombie(Vector3(0, 0, -1.6), Vector3.BACK)
	_start_zombies()
	await _run(0.2)
	player.set_look(0, 0)  # eye height 1.65: level swing meets the head
	await tree.physics_frame
	eq(melee.swing(), z.id, "level swing hits the zombie")
	near(z.hp, 100.0 - 68.0, "head hit: double damage", 0.01)
	eq(melee.swing(), -2, "can't swing again straight away")
	await _run(0.8)
	player.set_look(0, -30)
	await tree.physics_frame
	z.pos = Vector3(0, 0, -1.6)
	eq(melee.swing(), z.id, "low swing hits too")
	check(z.is_dead(), "body hit finishes it (32 hp left, 34 damage)")
	await _run(1.0)
	var anim := zview.body_for(z.id).find_child("AnimationPlayer", true, false) as AnimationPlayer
	eq(anim.assigned_animation if anim != null else "", "Death", "the body plays its fall")
	await _teardown()


func test_navmesh_leads_around_a_building() -> void:
	_setup(Vector3(0, 0, 5))
	_add_box(Vector3(0, 1.5, 0), Vector3(12, 3, 0.6))  # a long building between zombie and player
	var nav := NavBaker.new()
	_scene.add_child(nav)
	nav.setup(_scene, AABB(Vector3(-20, -1, -20), Vector3(40, 6, 40)))
	nav.bake_now()
	await nav.wait_synced()  # W3a: the map syncs on a worker thread
	await _run(0.2)
	var map := _scene.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, -5), Vector3(0, 0, 5), true)
	var widest := 0.0
	for p in path:
		widest = maxf(widest, absf(p.x))
	check(path.size() > 2 and widest > 6.0, "path goes round the end of the building (%d points, |x| up to %.1f)" % [path.size(), widest])
	var z := _zombie(Vector3(0, 0, -5), Vector3.BACK)
	z.take_hit(0, player.position, 0)
	_start_zombies()
	await _run(18.0)
	var d := Vector2(z.pos.x - player.position.x, z.pos.z - player.position.z).length()
	check(d < 2.5, "zombie walked round and reached the player (%.1f m away, %s)" % [d, z.state_name()])
	await _teardown()


## Q1: the soak found move_and_slide handing back a NaN position next to a parked car; a NaN body never
## recovered (its brain went NaN too and the log filled with warnings). Now the body steps back.
func test_a_nan_move_is_undone() -> void:
	_setup(Vector3.ZERO)
	var z := _zombie(Vector3(0, 0, -8), Vector3.BACK)
	_start_zombies()
	await _run(1.0)
	var body: ZombieBody = zview.body_for(z.id)
	var was := body.global_position
	body.global_position = Vector3(NAN, NAN, NAN)  # what the bad slide left behind
	await _run(0.1)
	check(body.global_position.is_finite(), "the body is back on a real position (%s)" % body.global_position)
	check(z.pos.is_finite(), "and so is its brain (%s)" % z.pos)
	check(body.nan_recoveries >= 1, "the guard counted it (%d)" % body.nan_recoveries)
	check(Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(was.x, was.z)) < 1.0,
			"where it was, not at the origin (%s, was %s)" % [body.global_position, was])
	eq(body.platform_floor_layers, 0, "zombies take no velocity from what they stand on (the NaN's source)")
	eq(player.platform_floor_layers, 0, "nor does the player")
	await _run(3.0)
	check(Vector2(z.pos.x, z.pos.z).length() < Vector2(was.x, was.z).length() - 1.0,
			"and it keeps chasing (%.1f m, was %.1f m)" % [Vector2(z.pos.x, z.pos.z).length(), Vector2(was.x, was.z).length()])
	await _teardown()
