extends "res://test/base_test.gd"
## W1a windows: 40 hp, block sound but not sight while the glass holds, become an opening when broken,
## and a barricade boards a broken one up (no refund). You can't build windows or other town pieces.

const N := BuildGrid.Side.NORTH


func _room() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.build.restore("f:0:0", {"id": "town_floor", "cell": Vector2i(0, 0), "side": N, "hp": 400})
	sim.build.restore("w:0:0:n", {"id": "window", "cell": Vector2i(0, 0), "side": N, "hp": 40})
	return sim


func test_window_blocks_sound_not_sight() -> void:
	var sim := _room()
	var key := "w:0:0:n"
	eq(sim.data.buildables["window"]["hp"], 40, "window hp")
	check(sim.build.is_edge("window"), "windows are edge pieces")
	check(sim.build.edge_blocks(key), "glass blocks sound")
	check(not sim.build.edge_blocks(key, true), "you can see through glass")
	var inside := Vector3(1, 1, 1)
	var outside := Vector3(1, 1, -3)
	eq(sim.noise.walls_between(inside, outside), 1, "sound counts the window as a wall")
	eq(sim.noise.walls_between(inside, outside, true), 0, "sight doesn't")


func test_window_breaks_into_an_opening() -> void:
	var sim := _room()
	var key := "w:0:0:n"
	var changed := []
	sim.build.piece_changed.connect(func(k: String) -> void: changed.append(k))
	check(not sim.build.damage(key, 30), "30 damage cracks it")
	check(sim.build.edge_blocks(key), "still whole")
	check(sim.build.damage(key, 30), "the next hit breaks it")
	check(sim.build.pieces.has(key), "a broken window stays as a piece")
	eq(sim.build.pieces[key]["hp"], 0, "at 0 hp")
	check(sim.build.is_broken(key), "broken")
	eq(changed, [key], "the view hears it break")
	check(not sim.build.edge_blocks(key), "sound passes")
	check(not sim.build.edge_blocks(key, true), "sight passes")
	eq(sim.noise.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -3)), 0, "no wall in the way any more")
	check(not sim.build.damage(key, 30), "can't break it twice")
	check(not ZombieBrain._standing(sim.build.pieces, key), "zombies stop bashing a broken window")
	check(ZombieBrain._standing(_room().build.pieces, key), "but a whole one is worth bashing")
	sim.inventory.give_all({"plank": 5})
	check(sim.build.repair(key, sim.inventory).contains("barricade"), "repair says to board it up")


func test_barricade_boards_up_a_broken_window() -> void:
	var sim := _room()
	var key := "w:0:0:n"
	sim.inventory.give_all({"plank": 20, "nails": 20})
	eq(sim.build.can_place("barricade", Vector2i(0, 0), N, sim.inventory), "Already built", "not over whole glass")
	sim.build.damage(key, 40)
	var removed := []
	sim.build.piece_removed.connect(func(k: String, p: Dictionary) -> void: removed.append([k, p["id"]]))
	eq(sim.build.place("barricade", Vector2i(0, 0), N, sim.inventory), "", "a barricade goes over the broken window")
	eq(sim.build.pieces[key]["id"], "barricade", "the edge is a barricade now")
	eq(removed, [[key, "window"]], "the window went")
	var cost: Dictionary = sim.data.buildables["barricade"]["cost"]
	eq(sim.inventory.count("plank"), 20 - int(cost.get("plank", 0)), "paid the planks, no window refund")
	eq(sim.inventory.count("nails"), 20 - int(cost.get("nails", 0)), "paid the nails")
	check(sim.build.edge_blocks(key), "sound is blocked again")
	eq(sim.noise.walls_between(Vector3(1, 1, 1), Vector3(1, 1, -3)), 1, "a wall again for sound")


func test_you_cannot_build_town_pieces() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	for id: String in ["window", "town_wall"]:
		eq(sim.build.can_place(id, Vector2i(0, 0), N, sim.inventory), "Only found in town", "can't place a %s" % id)
	eq(sim.build.can_place("town_floor", Vector2i(3, 3), N, sim.inventory), "Only found in town", "nor a town floor")
	eq(sim.build.can_place("wall", Vector2i(0, 0), N, sim.inventory), "", "your own wall is fine")


func test_removing_town_pieces_refunds_a_little() -> void:
	var sim := _room()
	sim.build.restore("w:0:0:w", {"id": "town_wall", "cell": Vector2i(0, 0), "side": BuildGrid.Side.WEST, "hp": 600})
	eq(sim.build.remove("w:0:0:n", sim.inventory), "", "take a window out")
	eq(sim.inventory.count("plank"), 1, "a plank back from the frame")
	eq(sim.build.remove("w:0:0:w", sim.inventory), "", "knock a house wall down")
	eq(sim.inventory.count("plank"), 2, "a plank")
	eq(sim.inventory.count("scrap_metal"), 1, "and some scrap")
	eq(sim.build.remove("f:0:0", sim.inventory), "", "then the floor")
	eq(sim.inventory.count("plank"), 3, "a floorboard")
	var s2 := _room()
	s2.build.damage("w:0:0:n", 40)
	eq(s2.build.remove("w:0:0:n", s2.inventory), "", "clear a broken window")
	eq(s2.inventory.count("plank"), 0, "a broken window is worth nothing")
