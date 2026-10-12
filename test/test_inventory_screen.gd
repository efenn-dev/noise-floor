extends "res://test/base_test.gd"
## The inventory screen: shows your pockets and the crate within reach, and its clicks move, use and
## drop through the sim's rules.

const N := BuildGrid.Side.NORTH

var sim: SimWorld
var screen: InventoryScreen
var crate_key := ""


func _setup() -> void:
	sim = SimWorld.new(10.0)
	sim.inventory.add("plank", 40)
	sim.inventory.add("nails", 40)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("storage", Vector2i(0, 0), BuildGrid.Side.WEST, sim.inventory)
	crate_key = sim.build.key_for("storage", Vector2i(0, 0))
	sim.inventory.give_all({"chips": 3, "clean_water": 2, "hiking_pack": 1})
	sim.player_pos = sim.build.piece_center(crate_key) + Vector3(1.0, 0, 0)
	screen = InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)


func _teardown() -> void:
	screen.free()


func _slots(grid_owner_side: String) -> int:
	var grids := screen.find_children("*", "GridContainer", true, false)
	var grid: GridContainer = grids[0] if grid_owner_side == InventoryScreen.POCKETS else grids[1]
	var live := 0
	for c in grid.get_children():
		if not c.is_queued_for_deletion():
			live += 1
	return live


func test_shows_pockets_and_the_crate() -> void:
	_setup()
	check(not screen.is_open(), "starts closed")
	screen.open()
	check(screen.is_open(), "Tab opens it")
	check(screen.crate() == sim.storages[crate_key], "the crate within reach is on the right")
	eq(_slots(InventoryScreen.POCKETS), sim.inventory.items().size(), "a slot per item in your pockets")
	eq(_slots(InventoryScreen.CRATE), 0, "the crate starts empty")
	screen.close()
	check(not screen.is_open(), "and closes")
	_teardown()


func test_shift_click_moves_the_stack_and_back() -> void:
	_setup()
	screen.open()
	screen.move("chips", InventoryScreen.POCKETS, true)
	eq([sim.inventory.count("chips"), screen.crate().count("chips")], [0, 3], "the whole stack went into the crate")
	screen.move("chips", InventoryScreen.CRATE, false)
	eq([sim.inventory.count("chips"), screen.crate().count("chips")], [1, 2], "ctrl-click brings one back")
	_teardown()


func test_use_and_drop_from_the_screen() -> void:
	_setup()
	screen.open()
	sim.player.water = 40.0
	screen.select("clean_water", InventoryScreen.POCKETS)
	screen.use_selected()
	eq(sim.inventory.count("clean_water"), 1, "drank one")
	check(sim.player.water > 40.0, "and you're less thirsty")
	var bags := sim.bags.size()
	screen.select("plank", InventoryScreen.POCKETS)
	screen.drop_selected(true)
	eq(sim.inventory.count("plank"), 0, "dropped all the planks")
	eq(sim.bags.size(), bags + 1, "into a bag at your feet")
	_teardown()


func test_no_crate_in_reach() -> void:
	_setup()
	sim.player_pos = Vector3(60, 0, 60)
	screen.open()
	check(screen.crate() == null, "nothing on the right")
	var messages := []
	screen.message.connect(func(t: String) -> void: messages.append(t))
	screen.move("chips", InventoryScreen.POCKETS, true)
	eq(sim.inventory.count("chips"), 3, "nothing moves")
	eq(messages, ["No crate within reach"], "and it says why")
	_teardown()


func test_bag_raises_the_limit_shown() -> void:
	_setup()
	screen.open()
	near(sim.carry_limit(), float(sim.data.survival["carry_base"]) + sim.data.item_value("hiking_pack", "bag"),
			"the hiking pack adds to what you can carry")
	_teardown()
