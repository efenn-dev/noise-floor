extends "res://test/base_test.gd"
## Scripted physics run of building: ghost aim, blocked placement, solid pieces, removal.

var _scene: Node3D
var sim: SimWorld
var view: BuildView
var builder: BuildController
var player: Player


func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	_scene.add_child(floor_body)
	sim = SimWorld.new(10.0)
	sim.give_debug_kit()
	view = BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	player = Player.new()
	player.use_device_input = false
	player.position = Vector3(1, 0, 7)  # facing north, in cell (0, 3)
	_scene.add_child(player)
	builder = BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	builder.set_active(true)


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _add_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_scene.add_child(body)


func test_main_scene_script_loads() -> void:
	var script: GDScript = load("res://src/world/main.gd")
	check(script != null and script.can_instantiate(), "src/world/main.gd compiles")


func test_aim_place_and_remove() -> void:
	await _setup()
	await _frames(5)
	player.set_look(0, -30)  # eye 1.65 m, 30 deg down -> ground ~2.9 m ahead, z ~ 4.1 -> cell (0, 2)
	await _frames(2)
	builder.update_aim()
	check(builder.aim_valid, "aims at the ground")
	eq(builder.aim_cell, Vector2i(0, 2), "snaps to the cell ahead")
	eq(builder.try_place(), "", "builds a foundation")
	await _frames(2)
	var body := view.body_for("f:0:2")
	check(body != null, "foundation has a body")
	builder.update_aim()
	eq(builder.aim_remove_key, "f:0:2", "ray now hits the new foundation")
	builder.select(1)
	builder.update_aim()
	eq(builder.aim_side, BuildGrid.Side.NORTH, "wall goes on the edge ahead")
	eq(builder.try_place(), "", "builds a wall on it")
	builder.turns = 1
	builder.update_aim()
	eq(builder.aim_side, BuildGrid.Side.EAST, "R turns the wall to the next edge clockwise")
	builder.turns = 0
	var planks := sim.inventory.count("plank")
	builder.select(0)
	eq(builder.try_remove(), "Remove the walls on it first", "foundation under a wall stays")
	eq(sim.build.remove(sim.build.key_for("wall", Vector2i(0, 2), BuildGrid.Side.NORTH), sim.inventory), "", "remove wall")
	await _frames(2)
	builder.update_aim()
	eq(builder.try_remove(), "", "now the foundation comes up")
	eq(sim.inventory.count("plank"), planks + 3 + 4, "both refunded")
	await _frames(2)
	check(view.body_for("f:0:2") == null, "body gone")
	await _teardown()


func test_obstacles_block_but_own_pieces_dont() -> void:
	await _setup()
	_add_box(Vector3(5, 1, 1), Vector3(2, 2, 2))  # a crate filling cell (2, 0)
	await _frames(3)
	check(builder.placement_blocked("foundation", Vector2i(2, 0), 0), "crate blocks a foundation")
	check(not builder.placement_blocked("foundation", Vector2i(0, 0), 0), "open ground is clear")
	check(builder.placement_blocked("foundation", Vector2i(0, 3), 0), "can't build under the player")
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("foundation", Vector2i(1, 0), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory)
	await _frames(3)
	check(not builder.placement_blocked("wall", Vector2i(0, 0), BuildGrid.Side.EAST), "neighbouring pieces don't block")
	check(not builder.placement_blocked("wall", Vector2i(1, 0), BuildGrid.Side.NORTH), "wall next to a wall is fine")
	await _teardown()


func test_player_walks_onto_foundation_and_wall_blocks() -> void:
	await _setup()
	for z in range(0, 3):
		sim.build.place("foundation", Vector2i(0, z), 0, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory)  # wall line at z = 0
	await _frames(10)
	player.wish_move = Vector2(0, 1)
	await _frames(150)
	check(player.position.y > 0.05, "stepped up onto the foundations (y = %.2f)" % player.position.y)
	check(player.position.z > 0.1 + Player.RADIUS - 0.05, "stopped by the wall (z = %.2f)" % player.position.z)
	check(player.position.z < 1.5, "walked across the floor to it (z = %.2f)" % player.position.z)
	await _teardown()
