extends "res://test/base_test.gd"
## Fix (2026-10-13, Emmitt: "when I got into the car the game bugged out"). His log: the car's physics went
## NaN inside the engine (a NaN axis in the vehicle's wheel maths, no script on the stack), then every
## zombie touching it logged NaN warnings each frame (28,000 in a minute), which stalled the game.
## Since S4 a dead zombie stays where it fell as a searchable body; the car collided with those bodies.
## Here: zombies dead against and under the parked car, a live one at the bumper, then drive.

const MAIN := "res://scenes/main.tscn"


func _bad(car: CarBody) -> String:
	if not car.global_transform.is_finite():
		return "transform %s" % car.global_transform
	if not car.linear_velocity.is_finite() or not car.angular_velocity.is_finite():
		return "velocity %s / %s" % [car.linear_velocity, car.angular_velocity]
	return ""


func test_driving_over_bodies_stays_finite() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	sim.vehicles.cars["car_0"]["fuel"] = 5.0
	var car: CarBody = main.cars["car_0"]
	car.use_device_input = false
	var at: Vector3 = car.global_position
	var fwd := car.global_basis.z  # the body drives toward +Z
	var side := car.global_basis.x
	# Bodies: one right under the car, one against each side, one just ahead; a live one at the bumper.
	for off: Vector3 in [Vector3.ZERO, side * 1.1, -side * 1.1, fwd * 2.6]:
		var z := sim.horde.spawn("shambler", Vector3(at.x + off.x, 0.0, at.z + off.z))
		z.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.horde.spawn("shambler", Vector3(at.x + fwd.x * 3.2, 0.0, at.z + fwd.z * 3.2))
	for i in 30:
		await tree.physics_frame  # bodies made, dead ones lying down
	eq(sim.enter_car("car_0"), "", "get in")
	main._enter_car("car_0")
	var bad := ""
	var zombie_nan := 0
	for i in 240:
		car.wish_throttle = 1.0 if i < 150 else -1.0
		car.wish_steer = 0.4 if i % 80 < 40 else -0.4
		await tree.physics_frame
		if bad == "":
			var b := _bad(car)
			if b != "":
				bad = "frame %d: %s" % [i, b]
		for body: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
			if not body.global_position.is_finite():
				zombie_nan += 1
	eq(bad, "", "the car's physics stay finite while driving over and through bodies")
	eq(zombie_nan, 0, "no zombie body goes NaN")
	var recoveries := 0
	for body: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
		recoveries += body.nan_recoveries
	eq(recoveries, 0, "no zombie needed a NaN recovery")
	main.free()
