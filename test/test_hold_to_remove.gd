extends "res://test/base_test.gd"
## P12 (Emmitt's log: the Hub built four times in one sitting, so it came down three; Kaleb's door vanished): in
## build mode a tap of right-click no longer takes a piece down. You hold it for BuildController.HOLD_TO_REMOVE on
## the piece while the HUD's ring fills; letting go early or looking away cancels. Real mouse buttons through the
## Input singleton (so BuildController's _unhandled_input and Input.is_action_pressed both see them).

const MAIN := "res://scenes/main.tscn"

var main: Node3D
var sim: SimWorld
var player: Player
var builder: BuildController
var house: Dictionary


func _setup() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	main = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	sim = main.sim
	player = main.player
	builder = main.builder
	house = main.town["houses"][1]  # house_0_e: front door faces west
	sim.inventory.give_all({"plank": 40, "nails": 60})


func _teardown() -> void:
	_mouse(false)
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func _look_at(target: Vector3) -> void:
	var d := target - (player.global_position + Vector3(0, 1.65, 0))
	player.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _mouse(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func test_right_click_must_be_held_to_take_a_piece_down() -> void:
	await _setup()
	var key := BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"])
	var center := sim.build.piece_center(key)
	player.global_position = Vector3(center.x - 2.5, 0.0, center.z)  # on the lawn, facing the front door
	_look_at(center)
	builder.set_active(true)
	builder.select_id("door")
	await _frames(3)
	builder.update_aim()
	eq(builder.aim_remove_key, key, "build mode: looking at the front door")
	check("hold RMB to take down this Door" in builder.status_text(), "the build line says to hold (%s)" % builder.status_text())
	# A tap: nothing comes down, and the game says to hold.
	_mouse(true)
	await _frames(4)
	check(sim.build.pieces.has(key), "a short press: the door is still there")
	check(builder.remove_progress() > 0.0 and builder.remove_progress() < 0.3, "the ring has started (%.2f)" % builder.remove_progress())
	check(main._hold_ring.visible, "and shows on the HUD")
	_mouse(false)
	await _frames(1)
	check(sim.build.pieces.has(key), "let go early: still there")
	eq(builder.remove_progress(), 0.0, "the ring is gone")
	eq(builder.last_message, "Hold right-click to take it down", "and the build line says why nothing happened")
	eq(sim.stats.remove_taps, 1, "the log counts the tap")
	# A hold: it comes down at HOLD_TO_REMOVE, not before.
	_mouse(true)
	await _frames(int(BuildController.HOLD_TO_REMOVE * 60.0) - 6)
	check(sim.build.pieces.has(key), "most of the way through the hold: still there")
	await _frames(12)
	check(not sim.build.pieces.has(key), "held long enough: it comes down")
	eq(int(sim.stats.removed.get("door", 0)), 1, "the log counts what came down")
	eq(builder.remove_progress(), 0.0, "the ring resets")
	_mouse(false)
	await _frames(1)
	eq(sim.stats.remove_taps, 1, "letting go after it came down isn't a tap")
	# Holding on nothing says so and takes nothing down; looking away mid-hold starts over.
	builder.update_aim()
	eq(builder.try_place(), "", "a new door goes in the doorway")
	await _frames(3)
	_look_at(center + Vector3(0, 30, 0))  # the sky
	await _frames(2)
	_mouse(true)
	await _frames(2)
	eq(builder.last_message, "Look at something you built", "holding on nothing says so")
	eq(builder.remove_progress(), 0.0, "and nothing fills")
	_look_at(center)
	await _frames(int(BuildController.HOLD_TO_REMOVE * 60.0) - 6)
	check(sim.build.pieces.has(key), "the hold only started when the door came into view")
	await _frames(12)
	check(not sim.build.pieces.has(key), "and then it comes down")
	_mouse(false)
	await _frames(1)
	# Stopping build mode drops a hold.
	eq(builder.try_place(), "", "another door")
	await _frames(2)
	_mouse(true)
	await _frames(5)
	builder.set_active(false)
	await _frames(int(BuildController.HOLD_TO_REMOVE * 60.0) + 5)
	check(sim.build.pieces.has(key), "leaving build mode mid-hold takes nothing down")
	_mouse(false)
	await _teardown()
