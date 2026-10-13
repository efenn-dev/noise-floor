extends "res://test/base_test.gd"
## Zombies are solid bodies a car can't move: three standing against the bumper used to pin a running car
## in place (the soak bot's drive moved 0.1 m). On the gas, the car now nudges them aside and creeps out.

const MAIN := "res://scenes/main.tscn"


func test_car_creeps_out_through_zombies_at_the_bumper() -> void:
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
	var ahead := Vector3.ZERO
	eq(sim.enter_car("car_0"), "", "get in")
	main._enter_car("car_0")
	# Find the way it drives first, with nobody in the way.
	var p0 := car.global_position
	car.wish_throttle = 1.0
	for i in 20:
		await tree.physics_frame
	ahead = car.global_position - p0
	ahead.y = 0.0
	ahead = ahead.normalized()
	car.wish_throttle = 0.0
	car.wish_handbrake = true
	for i in 60:
		await tree.physics_frame
	car.wish_handbrake = false
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	var front := car.global_position + ahead * (car.size.z / 2.0 + 0.5)
	for off: Vector3 in [Vector3.ZERO, side * 0.8, -side * 0.8]:
		sim.horde.spawn("shambler", Vector3(front.x + off.x, 0.0, front.z + off.z)).los_clear = true
	for i in 30:
		await tree.physics_frame
	var start := car.global_position
	car.wish_throttle = 1.0
	for i in 180:
		await tree.physics_frame
	var moved := Vector2(start.x, start.z).distance_to(Vector2(car.global_position.x, car.global_position.z))
	check(moved > 1.5, "the car creeps out through three zombies at the bumper (moved %.1f m in 3 s)" % moved)
	car.wish_throttle = 0.0
	main._exit_car()
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
