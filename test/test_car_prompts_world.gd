extends "res://test/base_test.gd"
## Loads the real game scene, stands beside the first car and reads what the look-at prompt says:
## a car with no key says where to find one, a startable car just offers to get in, a wreck says
## what's wrong and what you can still do (P1: Emmitt pressed E on cars and couldn't tell why).

const MAIN := "res://scenes/main.tscn"


func test_car_prompts_explain_keys_and_wrecks() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var player: Player = main.player
	var interactor: Interactor = main.interactor
	var c: Dictionary = sim.vehicles.cars["car_0"]
	player.global_position = Vector3(c["pos"].x - 3.0, 0.0, c["pos"].z)  # beside it, west of the driver's door
	player.set_look(-90.0, -10.0)  # facing east, at the car's side
	for i in 3:
		await tree.physics_frame
	interactor.update_target()
	eq(interactor.target_car, "car_0", "looking at the first car")
	check(not interactor.target_trunk, "at its side, not the trunk")
	var text := interactor.status_text()
	check("[E] get in   " + Vehicles.NO_KEY_HINT in text, "no key: the prompt says where to look (%s)" % text.replace("\n", " | "))

	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	text = interactor.status_text()
	check("[E] get in" in text and not "No key" in text, "with the key it just offers to get in (%s)" % text.replace("\n", " | "))

	c["wreck"] = "Flat tyres"
	interactor.update_target()
	check(interactor.target_trunk, "E on a wreck searches it")
	text = interactor.status_text()
	check("Flat tyres.   [E] search the trunk   [G] siphon gas" in text or c["fuel"] < 1.0 and "Flat tyres.   [E] search the trunk" in text,
			"a wreck says what's wrong and what you can still do (%s)" % text.replace("\n", " | "))
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
