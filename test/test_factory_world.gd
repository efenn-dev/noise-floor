extends "res://test/base_test.gd"
## Scripted run of the world side of factories: look at a machine, press E, see items drawn on belts.

var _scene: Node3D


func test_interact_and_items_drawn() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.give_debug_kit()
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	var player := Player.new()
	player.use_device_input = false
	player.position = Vector3(1, 0, 5)  # cell (0, 2), facing north
	_scene.add_child(player)
	var builder := BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	var interactor := Interactor.new()
	_scene.add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])
	var fview := FactoryView.new()
	_scene.add_child(fview)
	fview.setup(sim, view)

	for z in range(0, 2):
		sim.build.place("foundation", Vector2i(0, z), 0, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), BuildGrid.Side.SOUTH, sim.inventory)  # output toward the player
	sim.build.place("belt", Vector2i(0, 1), BuildGrid.Side.SOUTH, sim.inventory)
	for i in 5:
		await tree.physics_frame
	player.set_look(0, -10)
	interactor.update_target()
	check(interactor.has_target, "looking at the smelter")
	eq(interactor.target_cell, Vector2i(0, 0), "smelter cell")
	var scrap := sim.inventory.count("scrap_metal")
	var msg := interactor.interact()
	check(msg.begins_with("Loaded 20 Scrap metal"), "E loads scrap (%s)" % msg)
	eq(sim.inventory.count("scrap_metal"), scrap - 20, "scrap left the inventory")
	check("working" in interactor.status_text() or "needs" in interactor.status_text(), "HUD describes the machine")
	check("loudness 60" in interactor.status_text(), "HUD shows how loud it is")
	eq(interactor.upgrade(), "Muffler fitted: 15 quieter, 10% slower", "U fits a muffler")
	check("loudness 45 (muffled)" in interactor.status_text(), "now 45")

	builder.set_active(true)
	interactor.update_target()
	check(not interactor.has_target, "no interacting in build mode")
	builder.set_active(false)

	for i in 50:  # 2.5 s: one plate made and pushed onto the belt
		sim.step()
	await tree.process_frame  # process_frame fires before nodes' _process, so wait for the next one
	await tree.process_frame
	eq(fview.items_shown, 1, "one plate drawn on the belt")
	var drawn := func() -> MeshInstance3D: return fview._pool[0]  # the first pooled item mesh
	var belt_top: float = sim.build.center_for("belt", Vector2i(0, 1), BuildGrid.Side.SOUTH).y + sim.data.buildables["belt"]["size"].y / 2.0
	check(is_equal_approx((drawn.call() as MeshInstance3D).position.y, belt_top + FactoryView.ITEM_SIZE / 2.0), "it sits on the belt")
	sim.build.place("belt", Vector2i(5, 1), BuildGrid.Side.SOUTH, sim.inventory)  # F3: out on the bare ground
	sim.factory.belts[Vector2i(5, 1)].accept("nails")
	sim.factory.belts[Vector2i(0, 1)].items.clear()
	await tree.process_frame
	await tree.process_frame
	var ground_top: float = sim.data.buildables["belt"]["size"].y
	check(is_equal_approx((drawn.call() as MeshInstance3D).position.y, ground_top + FactoryView.ITEM_SIZE / 2.0),
			"on a belt out on the ground it sits on that belt, not up at floor height")
	_scene.queue_free()
	await tree.process_frame
