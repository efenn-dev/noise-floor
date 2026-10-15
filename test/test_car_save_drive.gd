extends "res://test/base_test.gd"
## Fix (2026-10-13): Emmitt's car went NaN in the engine's vehicle maths right after he got in (his save, the
## V3 build). Every car with gas: get in from where a player stands (beside the door, the walker left
## there), then drive hard with steering for a few seconds through the real town, and check the car and
## every zombie stay finite. Uses a committed save fixture and never reads or copies a player's save.

const MAIN := "res://scenes/main.tscn"
const COPY := "user://test_car_save_drive.json"


func test_drive_every_car_from_a_save_fixture() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path("res://test/fixtures/save_v17.json"),
			ProjectSettings.globalize_path(COPY))
	eq(copy_error, OK, "staged the committed save fixture")
	GameSession.pending_load = COPY
	var keep_path := GameSession.save_path
	GameSession.save_path = COPY  # anything saved goes to the copy, never the player's file
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var drove := 0
	var bad := ""
	for id: String in sim.vehicles.cars.keys():
		var c: Dictionary = sim.vehicles.cars[id]
		if String(c["wreck"]) != "":
			continue
		c["fuel"] = maxf(float(c["fuel"]), 3.0)
		sim.inventory.add(Vehicles.key_item(id), 1)
		var car: CarBody = main.cars[id]
		car.use_device_input = false
		# Stand beside the driver's door like a player who just pressed E.
		main.player.global_position = car.global_position + car.global_basis.x * 1.6 + Vector3.UP * 0.1
		await tree.physics_frame
		if sim.enter_car(id) != "":
			continue
		main._enter_car(id)
		drove += 1
		for i in 420:
			car.wish_throttle = 1.0 if i < 300 else -1.0
			car.wish_steer = [0.0, 1.0, -1.0, 0.5][(i / 60) % 4]
			await tree.physics_frame
			if bad == "" and not (car.global_transform.is_finite() and car.linear_velocity.is_finite()):
				bad = "%s frame %d: %s %s" % [id, i, car.global_transform.origin, car.linear_velocity]
		main._exit_car()
		for i in 30:
			await tree.physics_frame
	check(drove > 0, "drove at least one car (%d)" % drove)
	eq(bad, "", "every car stays finite")
	var zombie_bad := 0
	for body: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
		zombie_bad += body.nan_recoveries
		if not body.global_position.is_finite():
			zombie_bad += 1
	eq(zombie_bad, 0, "no zombie went NaN")
	main.free()
	GameSession.pending_load = ""
	GameSession.save_path = keep_path
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
