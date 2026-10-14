extends "res://test/base_test.gd"
## V27 (Emmitt: "a loot all button might help, I also noticed that we can't immediately equip items, it has to
## go to inventory before being equipped"): a Take all button on the open container, and wearing gear straight
## out of a container (the Equip action, or dragging it onto a character slot).


func _box(sim: SimWorld, id: String = "fridge") -> void:
	sim.loot.add(id, "fridge", Vector3.ZERO)
	sim.loot.containers[id]["searched"] = true
	sim.player_pos = Vector3.ZERO


func _screen(sim: SimWorld) -> InventoryScreen:
	var screen := InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	return screen


func test_wear_gear_straight_out_of_a_container() -> void:
	var sim := SimWorld.new()
	_box(sim)
	var hat := sim.gear.make("hard_hat", "civilian", "yellow")
	sim.loot.add_gear("fridge", [hat])
	eq(sim.equip_from_container("fridge", int(hat["uid"])), "Equipped " + String(hat["name"]), "the hard hat goes straight on")
	eq(sim.gear.equipped["head"]["uid"], hat["uid"], "you're wearing it")
	check(sim.container_gear("fridge").is_empty(), "it left the fridge")
	check(not sim.gear.pieces.any(func(p: Dictionary) -> bool: return p["uid"] == hat["uid"]), "it never sat in your pockets")
	var cap := sim.gear.make("cap", "civilian", "white")
	sim.loot.add_gear("fridge", [cap])
	eq(sim.equip_from_container("fridge", int(cap["uid"])), "Equipped " + String(cap["name"]), "a cap swaps it")
	check(sim.gear.pieces.any(func(p: Dictionary) -> bool: return p["uid"] == hat["uid"]), "the hard hat went into your pockets")


func test_the_old_piece_stays_in_the_container_when_you_cant_carry_it() -> void:
	var sim := SimWorld.new()
	_box(sim)
	var old := sim.gear.make("jacket", "civilian", "white")
	sim.gear.pieces.append(old)
	sim.gear.equip(int(old["uid"]))
	sim.inventory.add("scrap_metal", 200)  # far over the carry limit
	var new := sim.gear.make("hi_vis_vest", "civilian", "blue")
	sim.loot.add_gear("fridge", [new])
	var msg := sim.equip_from_container("fridge", int(new["uid"]))
	check(msg.begins_with("Equipped") and "stayed in the fridge" in msg, "it says the old one stayed behind (%s)" % msg)
	eq(sim.gear.equipped["body"]["uid"], new["uid"], "the vest is on")
	check(sim.container_gear("fridge").any(func(p: Dictionary) -> bool: return p["uid"] == old["uid"]), "the jacket is in the fridge")


func test_what_cant_be_worn_from_a_container() -> void:
	var sim := SimWorld.new()
	_box(sim)
	var scope := sim.gear.make("scope", "civilian", "white")
	var boots := sim.gear.make("work_boots", "civilian", "white")
	sim.loot.add_gear("fridge", [scope, boots])
	eq(sim.can_equip_from_container("fridge", int(scope["uid"])), "Fit it on a gun", "a gun part isn't worn")
	eq(sim.can_equip_from_container("fridge", int(boots["uid"]), "head"), "Doesn't fit that slot", "boots don't go on your head")
	eq(sim.can_equip_from_container("fridge", 999999), "Nothing to take", "nothing by that id")
	sim.player_pos = Vector3(30, 0, 30)
	eq(sim.can_equip_from_container("fridge", int(boots["uid"])), "Too far away", "only within reach")


func test_the_screen_take_all_button_equip_action_and_drag_to_a_slot() -> void:
	var sim := SimWorld.new()
	_box(sim)
	sim.loot.inventory("fridge").add("chips", 2)
	var boots := sim.gear.make("work_boots", "civilian", "white")
	var cap := sim.gear.make("cap", "civilian", "white")
	sim.loot.add_gear("fridge", [boots, cap])
	var screen := _screen(sim)
	screen.open_container("fridge")
	var button := screen.find_child("TakeAll", true, false) as Button
	check(button != null and button.visible, "a Take all button shows on the open container")
	# drag the boots from the container onto the feet slot
	var data := screen.drag_data("gear:%d" % boots["uid"], InventoryScreen.CRATE)
	eq(screen.drop_reason(data, "slot:feet"), "", "boots can be dropped on the feet slot straight from the fridge")
	check(screen.drop_reason(data, "slot:head") != "", "but not on the head")
	screen.drop_data(data, "slot:feet")
	eq(sim.gear.equipped["feet"]["uid"], boots["uid"], "the drag put them on")
	# the Equip action on the cap
	screen.select_gear(int(cap["uid"]), InventoryScreen.CRATE)
	var labels := screen._actions.get_children().map(func(c: Node) -> String: return (c as Button).text)
	check("Equip" in labels, "a container gear piece offers Equip (%s)" % ", ".join(labels))
	screen.equip_from_container_selected()
	eq(sim.gear.equipped["head"]["uid"], cap["uid"], "Equip wore the cap")
	var before := sim.inventory.count("chips")
	button.pressed.emit()
	eq(sim.inventory.count("chips"), before + 2, "Take all took both chips")
	screen.queue_free()
