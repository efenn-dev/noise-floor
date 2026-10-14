extends "res://test/base_test.gd"
## Fix (2026-10-13): the guards against a NaN car (Emmitt's "the game bugged out" after getting in).
## The engine-side cause couldn't be reproduced headless (test_car_corpse.gd, test_car_save_drive.gd
## drive hard and stay finite), so these check that a NaN, wherever it comes from, can't spread or stall.

const MAIN := "res://scenes/main.tscn"


func test_state_ok() -> void:
	check(CarBody.state_ok(Transform3D(), Vector3.ZERO, Vector3.ZERO), "a still car is fine")
	check(not CarBody.state_ok(Transform3D(Basis(), Vector3(NAN, 0, 0)), Vector3.ZERO, Vector3.ZERO), "NaN place")
	check(not CarBody.state_ok(Transform3D(), Vector3(0, INF, 0), Vector3.ZERO), "infinite speed")
	check(not CarBody.state_ok(Transform3D(), Vector3.ZERO, Vector3(NAN, NAN, NAN)), "NaN spin")


func test_guards_in_the_real_scene() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	sim.vehicles.cars["car_0"]["fuel"] = 3.0
	var car: CarBody = main.cars["car_0"]
	car.use_device_input = false

	# The hidden walker doesn't collide while you drive, and does again when you get out.
	eq(sim.enter_car("car_0"), "", "get in")
	main._enter_car("car_0")
	eq(main.player.collision_mask, 0, "the walker left at the door collides with nothing while you drive")
	car.wish_throttle = 1.0
	for i in 40:
		await tree.physics_frame
	var good := car.global_transform
	check(good.is_finite(), "driving normally")

	# A NaN car is put back where it last was, stopped.
	car.global_position = car.global_position + Vector3(3, 0, 0)
	await tree.physics_frame
	var before := car.nan_recoveries
	car.recover_from_nan()
	eq(car.nan_recoveries, before + 1, "counted")
	check(car.global_transform.is_finite(), "finite again")
	eq(car.linear_velocity, Vector3.ZERO, "and stopped")
	main._exit_car()
	eq(main.player.collision_mask, Player.MASK, "the walker collides again once you're out")

	# A zombie handed a NaN knock or step stays put instead of feeding it to the physics engine.
	var z := sim.horde.spawn("shambler", main.player.global_position + Vector3(0, 0, -6))
	for i in 5:
		await tree.physics_frame
	var body: ZombieBody = null
	for b: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
		if b.brain == z:
			body = b
	check(body != null, "the zombie has a body")
	if body != null:
		z.knockback = Vector3(NAN, 0, NAN)
		await tree.physics_frame
		body._push = Vector3(INF, 0, 0)
		await tree.physics_frame
		await tree.physics_frame
		check(body.global_position.is_finite(), "the zombie stays finite")
		eq(body.nan_recoveries, 0, "the guard caught it before the engine (no recovery needed)")
		check(body.bad_moves >= 1, "the bad step was dropped (%d)" % body.bad_moves)
	main.free()
