extends "res://test/base_test.gd"
## P3: doors, beds, walls and furniture the town laid give salvage when pulled down, not their full cost;
## the pieces you build give everything back. The "town" flag rides in saves, and older saves get it.


func _town_door_key(plan: Dictionary) -> String:
	for p: Dictionary in plan["pieces"]:
		if p["id"] == "door":
			return TownPlan.piece_key(p)
	return ""


func _town_sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	return sim


func test_town_pieces_are_flagged() -> void:
	var sim := _town_sim()
	var plan := TownPlan.generate(1)
	var doors := 0
	var beds := 0
	var unflagged := 0
	for key: String in sim.build.pieces:
		var p: Dictionary = sim.build.pieces[key]
		if not p.get("town", false):
			unflagged += 1
		doors += 1 if p["id"] == "door" else 0
		beds += 1 if p["id"] == "bed" else 0
	eq(unflagged, 0, "every piece the town laid carries the town flag")
	eq(doors, 24, "24 town doors")
	eq(beds, 12, "12 town beds")
	eq(sim.build.refund_for(sim.build.pieces[_town_door_key(plan)]), {"plank": 2}, "a town door salvages for 2 planks")


func test_town_door_salvages_player_door_refunds() -> void:
	var sim := _town_sim()
	var key := _town_door_key(TownPlan.generate(1))
	var inv := Inventory.new()
	eq(sim.build.remove(key, inv), "", "pull down a town door")
	eq(inv.count("plank"), 2, "2 planks of salvage")
	eq(inv.count("nails"), 0, "and no nails")
	var bed_key := ""
	for k: String in sim.build.pieces:
		if sim.build.pieces[k]["id"] == "bed":
			bed_key = k
			break
	inv = Inventory.new()
	eq(sim.build.remove(bed_key, inv), "", "pull apart a town bed")
	eq(inv.count("plank"), 3, "3 planks")
	eq(inv.count("scrap_metal"), 1, "and 1 scrap")
	eq(inv.count("nails"), 0, "no nails")
	var wall_key := ""
	for k: String in sim.build.pieces:
		if sim.build.pieces[k]["id"] == "town_wall" and sim.build.can_remove(k) == "":
			wall_key = k
			break
	inv = Inventory.new()
	sim.build.remove(wall_key, inv)
	eq(inv.count("plank") + inv.count("scrap_metal"), 2, "a town wall still gives its W1a salvage (1 plank, 1 scrap)")
	# Your own door and bed: the full cost back.
	sim.inventory.give_all({"plank": 40, "nails": 40})
	eq(sim.build.place("foundation", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory), "", "a foundation")
	eq(sim.build.place("door", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory), "", "your own door")
	var mine := sim.build.key_for("door", Vector2i(0, 0), BuildGrid.Side.NORTH)
	check(not sim.build.pieces[mine].get("town", false), "isn't a town piece")
	inv = Inventory.new()
	sim.build.remove(mine, inv)
	eq(inv.count("plank"), 6, "your door gives back 6 planks")
	eq(inv.count("nails"), 8, "and 8 nails")
	eq(sim.build.place("bed", Vector2i(0, 0), BuildGrid.Side.NORTH, sim.inventory), "", "your own bed")
	inv = Inventory.new()
	sim.build.remove(sim.build.key_for("bed", Vector2i(0, 0)), inv)
	eq(inv.count("plank"), 6, "your bed gives back 6 planks")
	eq(inv.count("nails"), 10, "and 10 nails")


func test_flag_survives_save_and_load() -> void:
	var a := _town_sim()
	a.inventory.give_all({"plank": 40, "nails": 40})
	a.build.place("foundation", Vector2i(0, 0), BuildGrid.Side.NORTH, a.inventory)
	a.build.place("door", Vector2i(0, 0), BuildGrid.Side.NORTH, a.inventory)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(d["version"]), 10, "saves are version 10 (P3)")
	var b := SimWorld.new(10.0, null, int(d["seed"]))
	eq(SaveGame.apply(b, d), "", "loads")
	var town_key := _town_door_key(TownPlan.generate(1))
	check(b.build.pieces[town_key].get("town", false), "the town door is still the town's")
	var mine := b.build.key_for("door", Vector2i(0, 0), BuildGrid.Side.NORTH)
	check(not b.build.pieces[mine].get("town", false), "your door is still yours")
	var inv := Inventory.new()
	b.build.remove(town_key, inv)
	eq(inv.count("plank"), 2, "after loading, the town door still salvages for 2 planks")


func test_version_9_save_gets_the_flag() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v9.json")
	eq(int(d.get("version", 0)), 9, "the fixture is a version-9 save (written by the P2 code)")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.build.pieces.size(), d["pieces"].size(), "every piece, once")
	var flagged := 0
	for key: String in sim.build.pieces:
		if sim.build.pieces[key]["id"] == "door" and sim.build.pieces[key].get("town", false):
			flagged += 1
	eq(flagged, 24, "its 24 town doors are marked as the town's")
	var mine := sim.build.key_for("door", Vector2i(0, 0), BuildGrid.Side.NORTH)
	check(sim.build.pieces.has(mine) and not sim.build.pieces[mine].get("town", false), "the door the player built is not")
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(again["version"]), SaveGame.VERSION, "saved again as the current version")
	for v in [2, 3, 4, 5, 6, 7, 8]:
		var old := SaveGame.read("res://test/fixtures/save_v%d.json" % v)
		var s := SimWorld.new(8.0, null, int(old.get("seed", 1)))
		eq(SaveGame.apply(s, old), "", "the version-%d fixture still loads" % v)
