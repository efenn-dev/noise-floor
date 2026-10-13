extends "res://test/base_test.gd"
## S3, real physics in the game scene: an open door is a solid panel swung away from you, beside the
## doorway. You can still look at it to close it (Playtest #1: "we are not able to close doors after
## opening"), you can't walk through the panel ("you can clip through the door after open"), the doorway
## itself is clear, and a door won't shut on someone standing in it.

const MAIN := "res://scenes/main.tscn"

var main: Node3D
var sim: SimWorld
var player: Player
var interactor: Interactor
var house: Dictionary


func _setup() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	main = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	sim = main.sim
	player = main.player
	interactor = main.interactor
	house = main.town["houses"][1]  # house_0_e: east of the road, front door facing west (test_town_world)
	eq(house["door_side"], BuildGrid.Side.WEST, "house_0_e's door faces west")


func _teardown() -> void:
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func _key() -> String:
	return BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"])


func _look_at(target: Vector3) -> void:
	var d := target - (player.global_position + Vector3(0, 1.65, 0))
	player.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _settle() -> void:
	for i in 3:
		await tree.physics_frame
	interactor.update_target()


func test_open_door_is_solid_beside_the_doorway_and_closes_again() -> void:
	await _setup()
	var key := _key()
	var center := sim.build.piece_center(key)
	var body: StaticBody3D = main.build_view.body_for(key)
	# On the lawn, 2.5 m west of the door, looking at it.
	player.global_position = Vector3(center.x - 2.5, 0.0, center.z)
	_look_at(center)
	await _settle()
	eq(interactor.target_key, key, "looking at the front door")
	check("[E] open" in interactor.status_text(), "it offers to open")
	eq(interactor.interact(), "Door opened", "E opens it")
	await _settle()
	eq(int(sim.build.pieces[key]["swing"]), -1, "it swings away from you: into the house (east)")
	eq(body.collision_layer, Layers.BUILT, "the open door is still a solid piece")
	var panel := body.global_position
	check(panel.x > center.x + 0.5, "the panel stands inside, east of the doorway (x %.2f vs %.2f)" % [panel.x, center.x])
	near(absf(body.global_basis.x.x), 1.0, "turned a quarter: it runs east-west now", 0.01)
	# The doorway is clear: a step through its middle meets nothing (feet just above the 10 cm house floor,
	# or the sweep hits the floor's edge).
	player.global_position = Vector3(center.x - 0.6, 0.15, center.z)
	await tree.physics_frame
	check(not player.test_move(player.global_transform, Vector3(1.2, 0, 0)), "you can walk through the open doorway")
	# The panel is not: standing inside beside it, a step into it is stopped.
	var side := signf(panel.z - center.z)  # the panel sits on the hinge side of the doorway
	player.global_position = Vector3(panel.x, 0.15, panel.z + side * 0.7)
	await tree.physics_frame
	check(player.test_move(player.global_transform, Vector3(0, 0, -side * 0.6)), "you can't walk through the open panel")
	# Look at the panel: you can close it from here.
	_look_at(panel)
	await _settle()
	eq(interactor.target_key, key, "looking at the open panel finds the door")
	check("[E] close" in interactor.status_text(), "it offers to close (%s)" % interactor.status_text().replace("\n", " | "))
	# Not while someone stands in the doorway, though.
	player.global_position = Vector3(center.x, 0.0, center.z)
	_look_at(panel)
	await _settle()
	eq(interactor.target_key, key, "still looking at the door from the doorway")
	eq(interactor.interact(), "Something's in the way of the door", "it won't shut on you")
	check(sim.build.pieces[key]["open"], "so it stays open")
	# Step clear and close it.
	player.global_position = Vector3(center.x + 1.3, 0.0, center.z - side * 0.6)
	_look_at(panel)
	await _settle()
	eq(interactor.target_key, key, "looking at it from inside")
	eq(interactor.interact(), "Door closed", "E closes it")
	await _settle()
	check(not sim.build.pieces[key]["open"], "shut")
	eq(body.global_position, center, "back on its edge")
	eq(body.collision_layer, Layers.BUILT, "solid")
	player.global_position = Vector3(center.x - 0.6, 0.15, center.z)
	await tree.physics_frame
	check(player.test_move(player.global_transform, Vector3(1.2, 0, 0)), "and the doorway is blocked again")
	await _teardown()


func test_opening_from_inside_swings_it_out() -> void:
	await _setup()
	var key := _key()
	var center := sim.build.piece_center(key)
	player.global_position = Vector3(center.x + 1.5, 0.0, center.z)  # inside the house
	_look_at(center)
	await _settle()
	eq(interactor.target_key, key, "looking at the door from inside")
	eq(interactor.interact(), "Door opened", "opens")
	await _settle()
	eq(int(sim.build.pieces[key]["swing"]), 1, "it swings out, away from you")
	check(main.build_view.body_for(key).global_position.x < center.x - 0.5, "the panel stands outside, on the lawn")
	await _teardown()
