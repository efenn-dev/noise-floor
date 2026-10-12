extends "res://test/base_test.gd"
## Scripted physics run: doors block when shut and let you through when open; spikes don't block.

var _scene: Node3D


func test_doors_and_spikes_in_the_world() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	_scene.add_child(ground)
	var sim := SimWorld.new(10.0)
	sim.inventory.give_all({"plank": 100, "nails": 200, "metal_plate": 20})
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	for z in [0, 1]:
		sim.build.place("foundation", Vector2i(0, z), 0, sim.inventory)
	sim.build.place("door", Vector2i(0, 1), BuildGrid.Side.NORTH, sim.inventory)  # door line at z = 2
	var door := sim.build.key_for("door", Vector2i(0, 1), BuildGrid.Side.NORTH)
	var player := Player.new()
	player.use_device_input = false
	player.position = Vector3(1, 0, 3.5)
	_scene.add_child(player)
	var builder := BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	var interactor := Interactor.new()
	_scene.add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])
	for i in 5:
		await tree.physics_frame
	interactor.update_target()
	eq(interactor.target_key, door, "looking at the door")
	check("closed   [E] open" in interactor.status_text(), "HUD: closed, E opens")
	player.wish_move = Vector2(0, 1)
	for i in 90:
		await tree.physics_frame
	check(player.position.z > 2.2, "a closed door stops you (z = %.2f)" % player.position.z)
	player.wish_move = Vector2.ZERO
	eq(interactor.interact(), "Door opened", "E opens it")
	await tree.physics_frame
	player.wish_move = Vector2(0, 1)
	for i in 90:
		await tree.physics_frame
	check(player.position.z < 1.0, "walked through the open door (z = %.2f)" % player.position.z)
	sim.build.place("spikes", Vector2i(0, -2), 0, sim.inventory)  # cell z -4..-2, straight ahead
	for i in 120:
		await tree.physics_frame
	check(player.position.z < -3.0, "spike strips don't block your feet (z = %.2f)" % player.position.z)
	_scene.queue_free()
	await tree.process_frame
