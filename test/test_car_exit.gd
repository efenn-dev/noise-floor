extends "res://test/base_test.gd"
## Q2: after you get out of a car its reported speed used to read NaN once (Q1 made zombies and the
## player immune to the NaN it handed them as "platform velocity"). The real game scene: get in, drive a
## few physics frames, get out; the car's speed and velocity stay finite every frame for two seconds.

const MAIN := "res://scenes/main.tscn"


func _finite_state(car: CarBody) -> String:
	if not is_finite(car.forward_speed()):
		return "forward_speed %s" % car.forward_speed()
	if not car.linear_velocity.is_finite():
		return "linear_velocity %s" % car.linear_velocity
	if not car.angular_velocity.is_finite():
		return "angular_velocity %s" % car.angular_velocity
	var st := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if st != null:
		if not st.linear_velocity.is_finite():
			return "server linear_velocity %s" % st.linear_velocity
		var v := st.get_velocity_at_local_position(Vector3(1.0, 0.0, 1.0))
		if not v.is_finite():
			return "velocity at a point (what a body standing on it gets) %s" % v
	if not car.global_transform.is_finite():
		return "transform %s" % car.global_transform
	return ""


func test_speed_stays_finite_after_getting_out() -> void:
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
	# A body standing against the car's side, like the zombie in the soak: what the engine hands it as
	# the car's velocity where they touch is the "platform velocity" that went NaN.
	var probe := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position.y = 0.9
	probe.add_child(shape)
	probe.collision_layer = 0
	probe.collision_mask = Layers.WORLD
	main.add_child(probe)
	for drive in 2:  # once like the soak (drive, handbrake to a stop, get out), once still rolling
		eq(sim.enter_car("car_0"), "", "get in (%d)" % drive)
		main._enter_car("car_0")
		car.wish_throttle = 1.0
		var bad_in := ""
		for i in (180 if drive == 0 else 60):
			await tree.physics_frame
			var st0 := PhysicsServer3D.body_get_direct_state(car.get_rid())
			if bad_in == "" and _finite_state(car) != "":
				bad_in = "frame %d after getting in: %s" % [i, _finite_state(car)]
		eq(bad_in, "", "finite while driving (%d)" % drive)
		check(absf(car.forward_speed()) > 0.5, "moving (%.2f m/s)" % car.forward_speed())
		car.wish_throttle = 0.0
		if drive == 0:
			car.wish_handbrake = true
			for i in 120:
				await tree.physics_frame
			car.wish_handbrake = false
		main._exit_car()
		var side := car.global_basis.x * (car.size.x / 2.0 + 0.4)
		var bad := ""
		var touched := 0
		for i in 120:  # two seconds at 60 physics frames a second
			var why := _finite_state(car)
			probe.global_position = Vector3(car.global_position.x + side.x, 0.05, car.global_position.z + side.z)
			probe.velocity = -side.normalized() * 2.0
			probe.move_and_slide()
			for k in probe.get_slide_collision_count():
				var hit := probe.get_slide_collision(k)
				if hit.get_collider() == car:
					touched += 1
					if why == "" and not hit.get_collider_velocity().is_finite():
						why = "the velocity it hands a body touching it %s" % hit.get_collider_velocity()
			if why == "" and not probe.get_platform_velocity().is_finite():
				why = "platform velocity %s" % probe.get_platform_velocity()
			if why != "" and bad == "":
				bad = "frame %d after getting out: %s" % [i, why]
			await tree.physics_frame
		eq(bad, "", "the car's speed is finite on every frame for two seconds after getting out (%d)" % drive)
		check(touched > 0, "the probe leaned on the car (%d)" % drive)
		check(car.freeze, "parked again (%d)" % drive)
		eq(car.forward_speed(), 0.0, "a parked car reports 0 m/s, not the speed it had when you got out (%d)" % drive)
		check(car.linear_velocity.is_zero_approx() and PhysicsServer3D.body_get_direct_state(car.get_rid()).linear_velocity.is_zero_approx(),
				"and its velocity is zero in the node and the physics server (%d)" % drive)
	probe.queue_free()
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
