extends "res://test/base_test.gd"
## Scripted run: look at a cabinet and search it, put things in a crate, sleep in a bed.

var _scene: Node3D


func test_search_store_and_sleep_with_e() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	_scene.add_child(ground)
	var sim := SimWorld.new(10.0)
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	var player := Player.new()
	player.use_device_input = false
	player.position = Vector3(1, 0, 5)
	_scene.add_child(player)
	var builder := BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	var interactor := Interactor.new()
	_scene.add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])

	var cabinet := StaticBody3D.new()  # a kitchen cabinet 2 m ahead
	cabinet.position = Vector3(1, 0.8, 3)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.6, 0.7)
	cs.shape = box
	cabinet.add_child(cs)
	cabinet.set_meta("container_id", "test_cabinet")
	_scene.add_child(cabinet)
	sim.loot.add("test_cabinet", "kitchen", cabinet.position)
	for i in 5:
		await tree.physics_frame
	sim.player_pos = player.global_position
	player.set_look(0, -10)
	interactor.update_target()
	eq(interactor.target_container, "test_cabinet", "looking at the cabinet")
	check("[E] search" in interactor.status_text(), "HUD offers a search")
	eq(interactor.interact(), "", "E starts the search")
	for i in 60:  # 3 s of ticks
		sim.step()
	check(sim.inventory.items().size() > 0, "found something: %s" % str(sim.inventory.items()))
	check("searched" in interactor.status_text(), "HUD says it's been searched")
	cabinet.queue_free()

	var stash := sim.place_start_stash(Vector2i(0, 1))  # crate at x 0..2, z 2..4: ahead of the player
	await tree.physics_frame
	await tree.physics_frame
	sim.inventory.add("scrap_metal", 5)
	player.set_look(0, -25)  # the crate is only 1 m tall
	interactor.update_target()
	eq(interactor.target_key, stash, "looking at the crate")
	check(interactor.interact().begins_with("Stored"), "E puts materials in the crate")
	eq(sim.storages[stash].count("scrap_metal"), sim.data.debug_kit["scrap_metal"] + 5, "scrap is in the crate")
	sim.build.remove(stash, sim.stock_at(Vector3.ZERO))
	sim.bags.clear()
	sim.give_debug_kit()
	sim.build.place("bed", Vector2i(0, 1), 0, sim.inventory)
	await tree.physics_frame
	await tree.physics_frame
	interactor.update_target()
	check("[E] sleep" in interactor.status_text(), "HUD offers sleep at the bed")
	sim.player.energy = 30.0
	interactor.interact()
	check(sim.player.asleep, "E on the bed: asleep")
	_scene.queue_free()
	await tree.process_frame
