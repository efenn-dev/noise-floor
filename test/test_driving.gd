extends "res://test/base_test.gd"
## Real physics: a car drives the way it faces, steers, burns gas, brakes, and stays put when parked.

var _scene: Node3D
var sim: SimWorld
var car: CarBody


func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	_scene.add_child(floor_body)
	sim = SimWorld.new(10.0)
	sim.loot.add("car_0", "car_trunk", Vector3(0, 0.75, 0))
	sim.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	sim.vehicles.cars["car_0"]["fuel"] = 3.0
	sim.inventory.add(Vehicles.key_item("car_0"), 1)  # these tests are about driving, not keys
	car = CarBody.new()
	_scene.add_child(car)
	car.setup(sim, "car_0", Color(0.8, 0.3, 0.2))
	car.use_device_input = false


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _drive() -> void:
	eq(sim.enter_car("car_0"), "", "get in")
	car.drive(true)
	await _frames(30)  # settle on the suspension


func test_drives_where_it_faces() -> void:
	_setup()
	await _drive()
	var start := car.global_position
	car.wish_throttle = 1.0
	await _frames(120)
	var moved := car.global_position - start
	check(moved.z < -5.0, "forward is the way the car faces, -Z (moved %s)" % moved)
	check(absf(moved.x) < 1.0, "in a straight line (%.2f sideways)" % moved.x)
	check(car.forward_speed() > 3.0, "going forward (%.1f m/s)" % car.forward_speed())
	check(sim.vehicles.cars["car_0"]["fuel"] < 3.0, "burning gas")
	check(sim.player_pos.distance_to(car.global_position) < 1.0, "you're where the car is (give or take a frame)")
	car.wish_throttle = -1.0  # hold S: brake, then back up
	var slowest := INF
	for i in 240:
		await tree.physics_frame
		slowest = minf(slowest, absf(car.forward_speed()))
	check(slowest < 1.5, "S brakes it to a stop (down to %.1f m/s)" % slowest)
	check(car.forward_speed() < -0.5, "then backs up (%.1f m/s)" % car.forward_speed())
	check(car.forward_speed() > -float(sim.data.vehicles["sedan"]["max_speed"]) * 0.35, "slowly")
	await _teardown()


func test_steering_turns_it() -> void:
	_setup()
	await _drive()
	car.wish_throttle = 0.7
	car.wish_steer = 1.0
	await _frames(150)
	check(car.sim_yaw() > 0.3, "A turns it left (yaw %.2f)" % car.sim_yaw())
	await _teardown()


func test_no_gas_no_go() -> void:
	_setup()
	sim.vehicles.cars["car_0"]["fuel"] = 0.0
	await _drive()
	var start := car.global_position
	car.wish_throttle = 1.0
	await _frames(90)
	check(car.global_position.distance_to(start) < 0.5, "an empty tank goes nowhere")
	await _teardown()


func test_parked_cars_stay_put() -> void:
	_setup()
	var start := car.global_position
	await _frames(60)
	check(car.freeze, "parked cars are frozen")
	check(car.global_position.distance_to(start) < 0.01, "and don't drift")
	await _drive()
	await _frames(10)
	sim.exit_car()
	car.drive(false)
	check(car.freeze, "frozen again once you get out")
	await _teardown()
