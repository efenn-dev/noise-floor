extends "res://test/base_test.gd"
## S3: the hotbar (ten slots under 1-9 and 0): defaults, what may go on a key, moving a thing between keys,
## saving and loading (and the version-12 fixture from before it), and doors that swing away from whoever
## opens them (BuildGrid.swing_away_from / door_pose).

const N := BuildGrid.Side.NORTH


func test_defaults_and_slots() -> void:
	var sim := SimWorld.new()
	var h := sim.hotbar
	eq(h.slots.size(), Hotbar.SLOTS, "ten slots")
	eq(h.entry(0), "build:foundation", "1 is the foundation")
	eq(h.entry(9), "item:bandage", "0 is a bandage")
	eq(h.kind(0), "build", "a piece")
	eq(h.id(0), "foundation", "its id")
	eq(h.kind(9), "item", "an item")
	eq(h.id(9), "bandage", "its id")
	eq(h.label(0), "Foundation", "named from the data")
	eq(h.label(9), "Bandage", "items too")
	eq(Hotbar.key_name(0), "1", "slot 0 is key 1")
	eq(Hotbar.key_name(9), "0", "slot 9 is key 0")
	eq(h.entry(10), "", "no eleventh slot")
	eq(h.find("build:wall"), 1, "find")
	eq(h.find(""), -1, "an empty entry is nowhere")


func test_assigning_and_what_is_allowed() -> void:
	var sim := SimWorld.new()
	var h := sim.hotbar
	eq(h.assign(3, "build:wall"), "", "a piece goes on key 4")
	eq(h.entry(3), "build:wall", "it's there")
	eq(h.entry(1), "", "and gone from key 2: a thing is on one key only")
	eq(h.assign(2, "item:canned_food"), "", "food goes on a key")
	eq(h.assign(2, "item:plank"), "Only food, drink and bandages go on the hotbar", "planks don't")
	eq(h.entry(2), "item:canned_food", "the refusal changed nothing")
	eq(h.assign(2, "build:town_wall"), "Only found in town", "town pieces don't")
	eq(h.assign(2, "build:no_such_piece"), "Unknown piece", "unknown pieces don't")
	eq(h.assign(2, "item:no_such_item"), "Unknown item", "unknown items don't")
	eq(h.assign(2, "garbage"), "Not a piece or an item", "nor anything else")
	eq(h.assign(10, "build:wall"), "No such slot", "keys are 1-9 and 0")
	eq(h.assign(-1, "build:wall"), "No such slot", "no negative slots")
	h.clear(3)
	eq(h.entry(3), "", "cleared")
	check(h.usable("clean_water") and h.usable("bandage") and not h.usable("nails"), "usable = food, drink, bandage")
	eq(h.validate(""), "", "an empty entry is fine")


func test_save_and_load() -> void:
	var sim := SimWorld.new()
	sim.hotbar.assign(0, "item:chips")
	sim.hotbar.assign(4, "build:nail_turret")
	sim.hotbar.clear(7)
	var arr := sim.hotbar.to_array()
	var again := Hotbar.new(sim.data)
	again.load_array(arr)
	eq(again.to_array(), arr, "round trip")
	again.load_array([])
	eq(again.to_array(), Hotbar.DEFAULT, "an empty list means the defaults (a save from before the hotbar)")
	again.load_array(["build:wall", "item:no_such_item", "nonsense"])
	eq(again.entry(0), "build:wall", "a short list fills the first slots")
	eq(again.entry(1), "", "an entry the data doesn't know is dropped")
	eq(again.entry(2), "", "so is nonsense")
	eq(again.entry(3), "", "the rest are empty")
	# Through SaveGame.
	var d := SaveGame.to_dict(sim)
	eq(d["hotbar"], arr, "saved")
	var b := SimWorld.new()
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.hotbar.to_array(), arr, "and the hotbar came back")
	d.erase("hotbar")
	var c := SimWorld.new()
	eq(SaveGame.apply(c, d), "", "a save without one loads")
	eq(c.hotbar.to_array(), Hotbar.DEFAULT, "with the defaults")


## test/fixtures/save_v12.json was written by the M17a-era code before the hotbar and door swings (the
## seed-1 town and park, a foundation with a door and a crate on it, day 5 09:00).
func test_version_12_save_still_loads() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v12.json")
	eq(int(d.get("version", 0)), 12, "the fixture is a version-12 save")
	check(not d.has("hotbar"), "it predates the hotbar")
	check(not d["pieces"][0].has("swing"), "and door swings")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.hotbar.to_array(), Hotbar.DEFAULT, "with the default hotbar")
	var door := sim.build.key_for("door", Vector2i(0, 0), BuildGrid.Side.SOUTH)
	check(sim.build.pieces.has(door), "the door you built is there")
	check(not sim.build.pieces[door].get("open", false), "shut, as saved")
	eq(sim.build.door_pose(door).origin, sim.build.piece_center(door), "a shut door stands on its edge")
	eq(sim.clock.day, 5, "day 5")
	var again := SaveGame.to_dict(sim)
	eq(int(again["version"]), SaveGame.VERSION, "saved again as the current version")
	check(again.has("hotbar"), "with a hotbar")


func test_doors_swing_away_from_whoever_opens_them() -> void:
	var sim := SimWorld.new()
	sim.give_debug_kit()
	eq(sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory), "", "a floor")
	eq(sim.build.place("door", Vector2i(0, 0), N, sim.inventory), "", "a door on its north edge")
	var key := sim.build.key_for("door", Vector2i(0, 0), N)
	var center := sim.build.piece_center(key)
	near(center.x, 1.0, "the door's middle, x")
	near(center.z, 0.0, "the door's middle, z (the edge between z<0 and z>0)")
	var closed := sim.build.door_pose(key)
	eq(closed.origin, center, "shut: on its edge")
	near(closed.basis.x.x, 1.0, "shut: it runs east-west")
	eq(sim.build.swing_away_from(key, Vector3(1, 0, 1.5)), 1, "someone south of it: it swings north")
	eq(sim.build.swing_away_from(key, Vector3(1, 0, -1.5)), -1, "someone north of it: it swings south")
	# Opened from the south (the cell it's on): the panel ends up along the north side, hinged at its west end.
	check(sim.build.toggle_door(key, Vector3(1.0, 0.0, 1.5)), "opens")
	eq(int(sim.build.pieces[key]["swing"]), 1, "swinging north")
	var open := sim.build.door_pose(key)
	near(open.origin.x, 0.0, "hinged at its west end (x)")
	near(open.origin.z, -1.0, "the panel's middle is 1 m north of the edge")
	near(open.basis.x.z, -1.0, "the panel runs north-south")
	near(open.origin.y, center.y, "same height")
	check(not sim.build.toggle_door(key, Vector3(1.0, 0.0, -1.5)), "closes (from whichever side)")
	eq(sim.build.door_pose(key).origin, center, "shut again, back on its edge")
	eq(int(sim.build.pieces[key]["swing"]), 1, "closing keeps the last swing")
	check(sim.build.toggle_door(key, Vector3(1.0, 0.0, -1.5)), "opened from the north")
	eq(int(sim.build.pieces[key]["swing"]), -1, "it swings south, away again")
	near(sim.build.door_pose(key).origin.z, 1.0, "the panel is now on the south side")
	sim.build.toggle_door(key)
	check(sim.build.toggle_door(key), "opened with no one given (tests, the soak)")
	eq(int(sim.build.pieces[key]["swing"]), -1, "keeps the swing it had")
	# Through the sim, and the swing survives a save.
	sim.build.toggle_door(key)
	eq(sim.toggle_door(key, Vector3(1.0, 0.0, 1.5)), "Door opened", "SimWorld.toggle_door takes the opener's place")
	eq(int(sim.build.pieces[key]["swing"]), 1, "and swings away from it")
	var b := SimWorld.new()
	eq(SaveGame.apply(b, SaveGame.to_dict(sim)), "", "saved and loaded")
	check(b.build.pieces[key]["open"], "still open")
	eq(int(b.build.pieces[key]["swing"]), 1, "swinging the same way")
	eq(b.build.door_pose(key).origin, sim.build.door_pose(key).origin, "same pose")
