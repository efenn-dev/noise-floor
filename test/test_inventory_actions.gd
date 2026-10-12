extends "res://test/base_test.gd"
## The rules behind the inventory screen: moving stacks between pockets and crates, using one
## particular item, dropping items in a bag at your feet, and which crates are within reach.

const N := BuildGrid.Side.NORTH


func _sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.inventory.add("plank", 200)
	sim.inventory.add("nails", 200)
	return sim


func _crate(sim: SimWorld, cell: Vector2i) -> String:
	sim.build.place("foundation", cell, N, sim.inventory)
	eq(sim.build.place("storage", cell, BuildGrid.Side.WEST, sim.inventory), "", "crate placed at %s" % cell)
	return sim.build.key_for("storage", cell)


func test_move_between_containers() -> void:
	var a := Inventory.new()
	var b := Inventory.new()
	a.add("chips", 3)
	eq(a.move_to(b, "chips", 2), 2, "moves two")
	eq([a.count("chips"), b.count("chips")], [1, 2], "one left, two moved")
	eq(a.move_to(b, "chips", 5), 1, "only what's there")
	eq(a.count("chips"), 0, "pockets empty")
	eq(b.move_to(b, "chips", 1), 0, "not into itself")
	eq(a.move_to(b, "soda", 1), 0, "nothing to move")


func test_use_a_particular_item() -> void:
	var sim := _sim()
	sim.inventory.give_all({"chips": 2, "clean_water": 1, "bandage": 1})
	sim.player.food = 50.0
	sim.player.water = 50.0
	eq(sim.use_item("chips"), "Ate Chips", "eat chips")
	eq(sim.inventory.count("chips"), 1, "one bag left")
	near(sim.player.food, 50.0 + sim.data.item_value("chips", "food"), "food went up")
	eq(sim.use_item("clean_water"), "Drank Clean water", "drink water")
	near(sim.player.water, 50.0 + sim.data.item_value("clean_water", "water"), "water went up")
	eq(sim.use_item("bandage"), "Not bleeding", "a bandage needs a wound")
	check(sim.can_use("chips") and sim.can_use("bandage") and not sim.can_use("plank"), "what can be used")
	eq(sim.use_item("plank"), "Can't use Plank", "planks aren't food")
	eq(sim.use_item("soda"), "You don't have that", "nothing to use")


func test_drop_into_a_bag_at_your_feet() -> void:
	var sim := _sim()
	sim.player_pos = Vector3(5, 0, 5)
	var before := sim.bags.size()
	eq(sim.drop_items("plank", 3), "Dropped 3 Plank", "drop planks")
	eq(sim.bags.size(), before + 1, "a bag appears")
	eq(sim.inventory.count("plank"), 197, "they left your pockets")
	sim.drop_items("nails", 5)
	eq(sim.bags.size(), before + 1, "dropping again joins the same bag")
	var bag: Dictionary = sim.bags[-1]
	eq(bag["items"], {"plank": 3, "nails": 5}, "with both stacks in it")
	sim.drop_items("plank", 1000)
	eq(sim.inventory.count("plank"), 0, "can't drop more than you have")
	eq(int(bag["items"]["plank"]), 200, "all the planks are in the bag")
	sim.player_pos = Vector3(30, 0, 30)
	sim.inventory.add("chips", 1)
	sim.drop_items("chips", 1)
	eq(sim.bags.size(), before + 2, "somewhere else, a new bag")
	var got := sim.take_bag(bag["id"])
	eq(int(got.get("nails", 0)), 5, "and E picks the first one back up")


func test_crates_within_reach() -> void:
	var sim := _sim()
	var near_key := _crate(sim, Vector2i(0, 0))
	var far_key := _crate(sim, Vector2i(5, 0))
	var close := sim.crates_near(sim.build.piece_center(near_key) + Vector3(1.5, 0, 0))
	eq(close, [near_key], "only the crate within reach")
	var mid := _crate(sim, Vector2i(1, 0))
	var both := sim.crates_near(sim.build.piece_center(near_key) + Vector3(0.5, 0, 0))
	eq(both, [near_key, mid], "nearest first")
	check(not sim.crates_near(Vector3(100, 0, 100)).has(far_key), "none out in the street")
