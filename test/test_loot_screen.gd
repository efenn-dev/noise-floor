extends "res://test/base_test.gd"
## V18 loot screen wiring, hotkeys and Godot Control drag/drop decisions. Item and gear changes are asserted
## against SimWorld so the screen cannot quietly bypass carry weight or equipment rules.

const MAIN := "res://scenes/main.tscn"


func _screen(sim: SimWorld) -> InventoryScreen:
	var screen := InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	return screen


func _box(sim: SimWorld, id: String = "fridge") -> void:
	sim.loot.add(id, "fridge", Vector3.ZERO)
	sim.loot.containers[id]["searched"] = true
	sim.player_pos = Vector3.ZERO


func _action(name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func test_finished_search_opens_that_container() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	main._setup_loot_flag("")
	var flag_id: String = main.inventory_screen.container_id()
	check(flag_id != "" and sim.loot.containers[flag_id]["table"] == "fridge", "--loot defaults to a fridge")
	check(sim.loot.containers[flag_id]["searched"], "the screenshot container is already searched")
	main.inventory_screen.close()
	var id := "screen_test_fridge"
	sim.loot.add(id, "fridge", sim.player_pos)
	eq(sim.search(id), "", "E's sim path starts the search")
	for i in roundi(sim.loot.search_time() / SimWorld.TICK) + 2:
		sim.step()
	check(main.inventory_screen.is_open(), "finishing opens the inventory screen")
	eq(main.inventory_screen.container_id(), id, "on the container that finished")
	eq(sim.container_name(id), "Fridge", "the right panel uses its name")
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_e_and_r_work_only_while_open() -> void:
	InputSetup.register()
	var sim := SimWorld.new()
	_box(sim)
	sim.loot.inventory("fridge").give_all({"chips": 3, "clean_water": 2})
	var screen := _screen(sim)
	sim.inventory.add("bandage", 1)
	screen.select("bandage", InventoryScreen.POCKETS)
	var old_key := sim.hotbar.entry(3)
	screen._input(_action("hotbar_4"))
	eq(sim.hotbar.entry(3), old_key, "number keys do nothing while the screen is closed")
	screen.select("chips", InventoryScreen.CRATE)
	screen._input(_action("interact"))
	eq(sim.inventory.count("chips"), 0, "E does nothing while the screen is closed")
	screen._input(_action("refuel"))
	eq(sim.inventory.count("clean_water"), 0, "R does nothing while it is closed")
	screen.open_container("fridge")
	screen.select("chips", InventoryScreen.CRATE)
	screen._input(_action("interact"))
	eq(sim.inventory.count("chips"), 3, "E takes the selected stack")
	screen._input(_action("refuel"))
	eq(sim.inventory.count("clean_water"), 2, "R takes everything else that fits")
	screen.free()


func test_drag_items_gear_slots_and_hotbar() -> void:
	var sim := SimWorld.new()
	_box(sim)
	sim.loot.inventory("fridge").add("chips", 3)
	var hat := sim.gear.make("hard_hat", "civilian", "yellow")
	sim.loot.add_gear("fridge", [hat])
	var screen := _screen(sim)
	var messages := PackedStringArray()
	screen.message.connect(func(text: String) -> void: messages.append(text))
	screen.open_container("fridge")
	check(screen.find_child("Gear%d" % hat["uid"], true, false) != null, "container gear is drawn as an icon tile")
	var whole := screen.drag_data("chips", InventoryScreen.CRATE)
	var one := screen.drag_data("chips", InventoryScreen.CRATE, true)
	eq(whole["amount"], 3, "plain drag carries the whole stack")
	eq(one["amount"], 1, "Ctrl-drag carries one")
	var preview := screen.drag_preview(whole)
	eq((preview.get_child(1) as Label).text, "3", "the drag preview shows the stack count")
	preview.free()
	check(screen.can_drop(one, InventoryScreen.POCKETS), "container item can drop on pockets")
	eq(screen.drop_data(one, InventoryScreen.POCKETS), "", "item drop succeeds")
	eq([sim.inventory.count("chips"), sim.loot.inventory("fridge").count("chips")], [1, 2], "one moved")
	var back := screen.drag_data("chips", InventoryScreen.POCKETS)
	check(screen.can_drop(back, InventoryScreen.CRATE), "pocket item can drop back on the container")
	check(not screen.can_drop(back, InventoryScreen.POCKETS), "a pocket item cannot drop back on pockets")
	screen.drop_data(back, InventoryScreen.CRATE)
	eq(sim.inventory.count("chips"), 0, "the pocket stack moved back")

	var gear_data := screen.drag_data(InventoryScreen.GEAR + str(hat["uid"]), InventoryScreen.CRATE)
	check(screen.can_drop(gear_data, InventoryScreen.POCKETS), "container gear can drop on pockets")
	check(not screen.can_drop(gear_data, InventoryScreen.CRATE), "a container tile cannot drop back on itself")
	screen.drop_data(gear_data, InventoryScreen.POCKETS)
	var pocket_gear := screen.drag_data(InventoryScreen.GEAR + str(hat["uid"]), InventoryScreen.POCKETS)
	check(screen.can_drop(pocket_gear, "slot:head"), "a hat fits Head")
	check(not screen.can_drop(pocket_gear, "slot:body"), "a hat does not fit Body")
	eq(screen.drop_reason(pocket_gear, "slot:body"), "Doesn't fit that slot", "the invalid drop says why")
	screen.begin_drag()
	check(not screen.check_drop(pocket_gear, "slot:body"), "Godot's drop check refuses the invalid target")
	eq(messages[messages.size() - 1], "Doesn't fit that slot", "the refused drag shows the short message")
	screen.drop_data(pocket_gear, "slot:head")
	eq(sim.gear.equipped["head"]["uid"], hat["uid"], "dropping on Head equips it")
	var worn := screen.drag_data(InventoryScreen.GEAR + str(hat["uid"]), InventoryScreen.WORN)
	check(screen.can_drop(worn, InventoryScreen.POCKETS), "a worn slot can drop back on pockets")
	screen.drop_data(worn, InventoryScreen.POCKETS)
	check(not sim.gear.equipped.has("head"), "dropping back unequips")

	sim.inventory.add("chips", 1)
	var hotbar := screen.drag_data("chips", InventoryScreen.POCKETS)
	check(screen.can_drop(hotbar, "hotbar:3"), "a usable item can drop on a hotbar key")
	screen.drop_data(hotbar, "hotbar:3")
	eq(sim.hotbar.id(3), "chips", "the sim assigned key 4")
	sim.inventory.add("plank", 1)
	var plank := screen.drag_data("plank", InventoryScreen.POCKETS)
	check(not screen.can_drop(plank, "hotbar:3"), "building material is invalid on the item hotbar")
	screen.free()


func test_too_heavy_and_leaving_or_damage_close_loot() -> void:
	var sim := SimWorld.new()
	_box(sim)
	sim.inventory.add("plank", 20)
	sim.loot.inventory("fridge").add("plank", 1)
	var screen := _screen(sim)
	var messages := PackedStringArray()
	screen.message.connect(func(text: String) -> void: messages.append(text))
	screen.open_container("fridge")
	var drag := screen.drag_data("plank", InventoryScreen.CRATE)
	check(not screen.can_drop(drag, InventoryScreen.POCKETS), "an overweight drop is refused")
	eq(screen.drop_reason(drag, InventoryScreen.POCKETS), "Too heavy", "with the short message")
	screen.take_everything()
	check(messages[messages.size() - 1].begins_with("Too heavy:") and "Plank" in messages[messages.size() - 1],
			"take all reports what did not fit (%s)" % messages[messages.size() - 1])
	sim.player_pos = Vector3(10, 0, 0)
	screen._process(0.0)
	check(not screen.is_open(), "walking beyond reach closes it")
	check(messages.has("Loot closed: too far away"), "and explains why")
	sim.player_pos = Vector3.ZERO
	screen.open_container("fridge")
	sim.player.health -= 1.0
	screen._process(0.0)
	check(not screen.is_open(), "taking damage closes it")
	check(messages.has("Loot closed: you were hurt"), "damage explains why too")
	screen.free()


func test_corpses_and_trunks_use_the_same_screen() -> void:
	var sim := SimWorld.new()
	sim.loot.add("car_0", "car_trunk", Vector3.ZERO)
	sim.loot.containers["car_0"]["searched"] = true
	sim.loot.add("corpse_7", "zombie", Vector3.ZERO)
	sim.loot.containers["corpse_7"]["searched"] = true
	eq(sim.container_name("car_0"), "Trunk", "car loot is titled Trunk")
	eq(sim.container_name("corpse_7"), "Corpse", "zombie loot is titled Corpse")
	var screen := _screen(sim)
	screen.open_container("car_0")
	eq(screen.container_id(), "car_0", "trunk opens")
	eq(screen._crate_title.text, "Trunk", "its right panel is titled Trunk")
	screen.open_container("corpse_7")
	eq(screen.container_id(), "corpse_7", "corpse opens through the same path")
	eq(screen._crate_title.text, "Corpse", "its right panel is titled Corpse")
	screen.free()


func test_layout_fits_the_small_supported_window() -> void:
	var sim := SimWorld.new()
	_box(sim)
	var screen := _screen(sim)
	screen.open_container("fridge")
	await tree.process_frame
	var panel: Control = screen._root.get_child(0).get_child(0)
	var minimum := panel.get_combined_minimum_size()
	check(minimum.x <= 1280.0 and minimum.y <= 720.0,
			"the loot panel fits 1280x720 (minimum is %s)" % minimum)
	screen.free()
