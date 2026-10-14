extends "res://test/base_test.gd"
## Carry weight, bags, storage crates, building from the stash.

const TICK := SimWorld.TICK


func test_weight_and_limit() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.give_all({"plank": 10, "nails": 100})
	near(sim.inventory.weight(sim.data), 11.0, "10 planks (1 kg) + 100 nails (0.01 kg) = 11 kg")
	near(sim.carry_limit(), 20.0, "20 kg limit with no bag")
	sim.inventory.give_all({"school_bag": 1, "hiking_pack": 1})
	near(sim.carry_limit(), 20.0, "bags in pockets add no capacity")
	eq(sim.equip_bag("hiking_pack"), "Equipped Hiking pack", "wear the hiking pack")
	near(sim.carry_limit(), 38.0, "only the worn bag counts: 20 + 18")


func test_overloaded_is_slow_loud_and_cant_sprint() -> void:
	var sim := SimWorld.new(10.0)
	sim.player_pos = Vector3(0, 0, 500)
	sim.inventory.add("plank", 25)  # 25 / 20 kg
	sim.step()
	near(sim.player.carry_ratio, 1.25, "125% loaded")
	near(sim.player.speed_multiplier(), 0.875, "1 - 0.25 x 0.5 = 87.5% speed")
	check(sim.player.can_sprint(), "can still sprint under 150%")
	sim.player.sprinting = true
	for i in 20:
		sim.step()
	near(sim.player.stamina, 100.0 - 15.0 * 1.25, "sprinting costs 25% more", 0.2)
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	sim.step()
	near(sim.noise.recent.back()["loudness"], 22.0 + 10.0, "footsteps 10 louder when overloaded")
	sim.inventory.add("plank", 10)  # 35 / 20 = 175%
	sim.step()
	check(not sim.player.can_sprint(), "no sprinting over 150%")
	near(sim.player.speed_multiplier(), 0.625, "slower still")


func test_build_and_feed_from_a_nearby_crate() -> void:
	var sim := SimWorld.new(10.0)
	var stash := sim.place_start_stash(Vector2i(0, 0))
	check(stash != "", "start stash placed")
	eq(sim.storages[stash].count("plank"), sim.data.debug_kit["plank"], "the kit is in the crate, not your pockets")
	eq(sim.inventory.count("plank"), 0, "pockets empty")
	var near_stock := sim.stock_at(Vector3(10, 0, 10))
	eq(sim.build.place("foundation", Vector2i(5, 5), 0, near_stock), "", "build 14 m away using the crate's planks")
	eq(sim.storages[stash].count("plank"), sim.data.debug_kit["plank"] - 4, "4 planks came out of the crate")
	var far_stock := sim.stock_at(Vector3(100, 0, 100))
	eq(sim.build.place("foundation", Vector2i(50, 50), 0, far_stock), "Not enough materials", "too far from the crate")
	near_stock.refund_to_storage = true
	sim.build.remove("f:5:5", near_stock)
	eq(sim.storages[stash].count("plank"), sim.data.debug_kit["plank"], "the refund goes back in the crate")
	sim.inventory.give_all({"plank": 2, "chips": 1})
	var pocket_first := sim.stock_at(Vector3.ZERO)
	pocket_first.take_all({"plank": 3})
	eq(sim.inventory.count("plank"), 0, "takes from your pockets first")
	eq(sim.storages[stash].count("plank"), sim.data.debug_kit["plank"] - 1, "then the crate")


func test_deposit_keeps_supplies() -> void:
	var sim := SimWorld.new(10.0)
	var stash := sim.place_start_stash(Vector2i(0, 0))
	sim.inventory.give_all({"scrap_metal": 6, "canned_food": 2, "bandage": 1, "school_bag": 1})
	var moved := sim.deposit(stash)
	eq(moved, {"scrap_metal": 6}, "puts away materials")
	eq(sim.inventory.count("canned_food"), 2, "keeps food")
	eq(sim.inventory.count("bandage"), 1, "keeps bandages")
	eq(sim.inventory.count("school_bag"), 1, "keeps bags")


func test_removing_a_crate_drops_its_contents() -> void:
	var sim := SimWorld.new(10.0)
	var stash := sim.place_start_stash(Vector2i(0, 0))
	sim.build.destroy(stash)
	eq(sim.bags.size(), 1, "a wrecked crate spills a bag")
	eq(sim.bags[0]["items"].get("plank", 0), sim.data.debug_kit["plank"], "with everything that was in it")
