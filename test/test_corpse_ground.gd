extends "res://test/base_test.gd"
## S5 (Emmitt: "when you walk over a slain zombie you push the dead bodies. Can you make them much more
## grounded"; and his pickup still went NaN). Bodies ignore you and the cars; walking over one nudges it a
## little; a NaN car's wheels are rebuilt.

const MAIN := "res://scenes/main.tscn"


func test_nudge_is_small_and_only_while_walking_over() -> void:
	var walker := CharacterBody3D.new()
	tree.root.add_child(walker)
	walker.global_position = Vector3.ZERO
	eq(ZombieBody.nudge_for(walker, Vector3(0.3, 0, 0)), Vector3.ZERO, "standing on it: nothing")
	walker.velocity = Vector3(4, 0, 0)
	var n := ZombieBody.nudge_for(walker, Vector3(0.3, 0, 0))
	check(n.x > 0.0 and n.length() <= 4.0 * ZombieBody.NUDGE_SHARE + 0.001, "walking over it: a small shuffle your way (%s)" % n)
	eq(ZombieBody.nudge_for(walker, Vector3(2.0, 0, 0)), Vector3.ZERO, "walking past it: nothing")
	walker.velocity = Vector3(7, -3, 0)
	check(ZombieBody.nudge_for(walker, Vector3(0.2, 0, 0)).y == 0.0, "never lifts it")
	walker.free()


func test_bodies_ignore_you_and_the_cars() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var z := sim.horde.spawn("shambler", main.player.global_position + Vector3(0, 0, -2))
	for i in 5:
		await tree.physics_frame
	var body: ZombieBody = null
	for b: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
		if b.brain == z:
			body = b
	check(body != null, "the zombie has a body")
	if body == null:
		main.free()
		return
	z.take_hit(1000.0, body.global_position + Vector3(0, 0, 2), 0.0)
	for i in 60:
		await tree.physics_frame
	var ex := body.get_collision_exceptions()
	check(main.player in ex, "the body doesn't push you or get pushed by you")
	check(main.cars["car_0"] in ex, "nor any car")
	# Walk straight across it: it moves a little, not metres.
	var start := body.global_position
	main.player.global_position = start + Vector3(0, 0.1, 1.5)
	main.player.use_device_input = false
	main.player.wish_move = Vector2(0, 1)  # forward is -Z: across the body
	for i in 60:
		await tree.physics_frame
	main.player.wish_move = Vector2.ZERO
	var moved := Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()
	check(moved < 0.5, "walking over it barely shifts it (%.2f m)" % moved)
	main.free()


func test_a_nan_car_gets_fresh_wheels() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var car: CarBody = main.cars["car_0"]
	var before := car.find_children("*", "VehicleWheel3D", false, false)
	var radius := (before[0] as VehicleWheel3D).wheel_radius
	var steer := before.filter(func(w: VehicleWheel3D) -> bool: return w.use_as_steering).size()
	car.recover_from_nan()
	await tree.process_frame
	var after := car.find_children("*", "VehicleWheel3D", false, false)
	eq(after.size(), before.size(), "the same number of wheels")
	check(not after.has(before[0]), "new wheel nodes")
	near((after[0] as VehicleWheel3D).wheel_radius, radius, "same size")
	eq(after.filter(func(w: VehicleWheel3D) -> bool: return w.use_as_steering).size(), steer, "the same wheels steer")
	check((after[0] as VehicleWheel3D).get_child_count() > 0, "with their tyres")
	check(car.nan_report != "", "and the tick before is written down for the log")
	main.free()
