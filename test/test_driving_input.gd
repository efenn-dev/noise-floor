extends "res://test/base_test.gd"
## S3, Playtest #1: "the driving feature does not work". Pressing E at a car got you in and, with the same
## key press, straight back out: the Interactor entered the car and then main.gd (a parent gets the event
## after its children) read "E while driving" as get out. The driving-keys message piled up once per press.
## This feeds a real E key through the viewport, as Windows would, and checks you stay in the car.

const MAIN := "res://scenes/main.tscn"


func _key(vp: Viewport, key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = pressed
		vp.push_input(ev)


func test_e_gets_you_in_and_you_stay_in() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var player: Player = main.player
	var vp := main.get_viewport()
	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	sim.vehicles.cars["car_0"]["fuel"] = 3.0
	var c: Dictionary = sim.vehicles.cars["car_0"]
	player.global_position = Vector3(c["pos"].x - 3.0, 0.0, c["pos"].z)  # beside it, west of the driver's door
	player.set_look(-90.0, -10.0)  # facing east, at the car's side
	for i in 3:
		await tree.physics_frame
	main.interactor.update_target()
	eq(main.interactor.target_car, "car_0", "looking at the first car")
	_key(vp, KEY_E)
	check(main.driving != null, "E gets you in")
	eq(sim.vehicles.driving, "car_0", "the sim agrees")
	for i in 10:
		await tree.physics_frame
	check(main.driving != null and sim.vehicles.driving == "car_0", "and you stay in")
	check(c["running"], "the engine is running (key in your pockets, gas in the tank)")
	var hints := 0
	for m: Dictionary in sim.messages:
		if String(m["text"]).begins_with("W/S gas"):
			hints += 1
	eq(hints, 1, "the driving keys are shown once, not once per bounce")
	_key(vp, KEY_E)
	check(main.driving == null and sim.vehicles.driving == "", "E again gets you out")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
