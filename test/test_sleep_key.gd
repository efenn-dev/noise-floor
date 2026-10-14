extends "res://test/base_test.gd"
## V24 (Emmitt: "I was not able to sleep or regain energy"): E on a bed through the real input path. The E
## press used to reach main.gd after the interactor had put you to sleep, and "any key wakes you" woke you in
## the same press, so you could never sleep.

const MAIN := "res://scenes/main.tscn"


func test_e_on_a_bed_puts_you_to_sleep_and_you_stay_asleep() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var player: Player = main.player
	# A bed right in front of you, by the start crate.
	player.global_position = Vector3(1.0, 0.1, 4.6)
	player.set_look(0.0, -30.0)
	sim.player_pos = player.global_position
	sim.give_debug_kit()
	var cell := Vector2i(0, 1)  # the 2 m cell just north of you (as in test_survival_world)
	eq(sim.build.place("foundation", cell, 0, sim.inventory), "", "a floor")
	eq(sim.build.place("bed", cell, 0, sim.inventory), "", "a bed in front of you")
	for i in 4:
		await tree.physics_frame
	main.interactor.update_target()
	check("[E] sleep" in main.interactor.status_text(), "the HUD offers sleep (%s)" % main.interactor.status_text())
	sim.player.energy = 30.0
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		ev.pressed = pressed
		main.get_viewport().push_input(ev)
	await tree.process_frame
	await tree.process_frame
	check(sim.player.asleep, "E on the bed: asleep, and the same press didn't wake you")
	var energy := sim.player.energy
	for i in 30:
		await tree.physics_frame
	check(sim.player.energy > energy, "sleeping restores energy (%.1f -> %.1f)" % [energy, sim.player.energy])
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_W
	ev2.pressed = true
	main.get_viewport().push_input(ev2)
	await tree.process_frame
	check(not sim.player.asleep, "a later key press still wakes you")
	Engine.time_scale = 1.0
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
