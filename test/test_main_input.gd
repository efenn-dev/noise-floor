extends "res://test/base_test.gd"
## Loads the real game scene and feeds it mouse input the way Windows would, so a HUD element
## swallowing the mouse (as the crosshair dot once did) fails here instead of on Emmitt's PC.

const MAIN := "res://scenes/main.tscn"


func _mouse_motion(vp: Viewport, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = vp.get_visible_rect().size / 2.0  # a locked mouse sits in the middle of the screen
	ev.relative = relative
	vp.push_input(ev)


func _click(vp: Viewport, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = vp.get_visible_rect().size / 2.0
		ev.button_index = button
		ev.pressed = pressed
		vp.push_input(ev)


func test_mouse_turns_the_view_and_swings() -> void:
	InputSetup.assume_captured = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	var vp := main.get_viewport()
	var player: Player = main.player
	var yaw := player.rotation.y
	var pitch := player.head.rotation.x
	_mouse_motion(vp, Vector2(100, 0))
	check(absf(player.rotation.y - yaw) > 0.1, "moving the mouse sideways turns the player (%.3f -> %.3f)" % [yaw, player.rotation.y])
	_mouse_motion(vp, Vector2(0, -80))
	check(player.head.rotation.x > pitch + 0.1, "moving it up looks up")
	_click(vp, MOUSE_BUTTON_LEFT)
	check(main.sim.player.swing_cooldown > 0.0, "left click swings the pipe")
	var kb := InputEventKey.new()
	kb.physical_keycode = KEY_B
	kb.pressed = true
	vp.push_input(kb)
	check(main.builder.active, "B opens build mode")
	await tree.process_frame
	var planks: int = main.sim.inventory.count("plank")
	player.set_look(0, -20)  # about 4.5 m ahead: clear of the player's own feet
	await tree.physics_frame
	await tree.physics_frame
	_click(vp, MOUSE_BUTTON_LEFT)
	check(main.sim.inventory.count("plank") < planks, "left click in build mode builds (%s)" % main.builder.last_message)
	main.queue_free()
	InputSetup.assume_captured = false
	await tree.process_frame
