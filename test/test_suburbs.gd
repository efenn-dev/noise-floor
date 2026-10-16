extends "res://test/base_test.gd"
## W3c: West and East Street's houses (SuburbPlan): seeded; inside their areas and off every road, the town,
## the park, downtown, the junkyard and each other; every house closed with a front door on its road; the
## scenery off roads and houses; laid round an older save's own building (and the skip remembered); zombies.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]
var _scene: Node3D
var sim: SimWorld
var player: Player


func test_same_seed_same_streets() -> void:
	eq(str(SuburbPlan.generate(4)), str(SuburbPlan.generate(4)), "the same seed gives the same streets")
	for seed_value: int in SEEDS:
		var p := SuburbPlan.generate(seed_value)
		var n: int = p["houses"].size()
		check(n >= 16 and n <= 30, "seed %d: a street's worth of houses (%d)" % [seed_value, n])
		var west := (p["houses"] as Array).filter(func(h: Dictionary) -> bool: return str(h["name"]).begins_with("west_")).size()
		check(west >= 8 and n - west >= 6, "seed %d: on both streets (%d west, %d east)" % [seed_value, west, n - west])


func test_houses_stay_in_their_areas_and_off_everything() -> void:
	for seed_value: int in SEEDS:
		var p := SuburbPlan.generate(seed_value)
		var town := TownPlan.generate(seed_value)
		var park := ParkPlan.generate(seed_value)
		var downtown := DowntownPlan.generate(seed_value)
		var taken := {}
		for piece: Dictionary in town["pieces"] + town["factory"]["pieces"] + park["pieces"] + downtown["pieces"]:
			if piece["id"] == "town_floor":
				taken[piece["cell"]] = true
		var mine := {}
		for h: Dictionary in p["houses"]:
			var area: Rect2 = WorldMap.AREAS["residential_west" if str(h["name"]).begins_with("west_") else "residential_east"]
			var r := SuburbPlan.house_rect(h)
			check(area.encloses(r), "seed %d: %s is in its area" % [seed_value, h["name"]])
			check(not WorldMap.AREAS["junkyard"].intersects(r.grow(4.0)), "seed %d: %s keeps off the junkyard" % [seed_value, h["name"]])
			for c: Vector2i in h["cells"]:
				var mid := Vector2((c.x + 0.5) * BuildGrid.GRID, (c.y + 0.5) * BuildGrid.GRID)
				if WorldMap.on_road(mid, 1.5) or taken.has(c) or mine.has(c):
					check(false, "seed %d: %s cell %s is on a road or another building" % [seed_value, h["name"], c])
				mine[c] = true
		for it: Dictionary in p["items"]:
			var at := Vector2(it["pos"].x, it["pos"].z)
			check(not WorldMap.on_road(at, 0.4), "seed %d: a %s is off the road" % [seed_value, it["kind"]])
			for c: Vector2i in mine:  # every house cell (an L-shaped house's notch is open ground)
				var cr := Rect2(c.x * BuildGrid.GRID, c.y * BuildGrid.GRID, BuildGrid.GRID, BuildGrid.GRID)
				if cr.grow(0.3).intersects(StreetPlan.footprint(it)):
					check(false, "seed %d: a %s stands on a house at %s" % [seed_value, it["kind"], c])
	var data := GameData.load_default()
	var p := SuburbPlan.generate(1)
	for n: Dictionary in data.resources["nodes"]:
		var at := Vector2(n["pos"][0], n["pos"][1])
		for h: Dictionary in p["houses"]:
			check(not SuburbPlan.house_rect(h).grow(3.0).has_point(at), "node %s keeps clear of %s" % [n["id"], h["name"]])


func test_every_house_is_closed_with_a_front_door_on_its_road() -> void:
	var p := SuburbPlan.generate(2)
	var edges := {}
	for piece: Dictionary in p["pieces"]:
		if piece["id"] != "town_floor":
			edges[TownPlan.piece_key(piece)] = piece["id"]
	for h: Dictionary in p["houses"]:
		var cells := {}
		for c: Vector2i in h["cells"]:
			cells[c] = true
		for c: Vector2i in cells:
			for side in 4:
				if not cells.has(c + Factory.DIRS[side]):
					check(edges.has(BuildGrid.key_for_wall_edge(c, side)), "%s: outside edge %s of %s closed" % [h["name"], side, c])
		eq(edges.get(BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"]), ""), "door", "%s: a front door" % h["name"])
		var toward_road: int = BuildGrid.Side.WEST if h["east"] else BuildGrid.Side.EAST
		eq(h["door_side"], toward_road, "%s: the door faces its road" % h["name"])
		var front_x: float = (h["door_cell"].x + (0 if h["east"] else 1)) * BuildGrid.GRID
		near(absf(front_x - float(h["road_x"])), 8.0, "%s: 8 m back from the road's middle, like Main Street's" % h["name"], 0.01)


func test_place_suburbs_lays_houses_furniture_and_trash() -> void:
	var w := SimWorld.new(12.0)
	var p := SuburbPlan.generate(1)
	var shown := w.place_suburbs(p, true)
	eq(w.suburbs_skipped, [], "a new game skips nothing")
	eq(shown["houses"].size(), p["houses"].size(), "every house is there")
	for piece: Dictionary in p["pieces"]:
		if not w.build.pieces.has(TownPlan.piece_key(piece)):
			check(false, "%s piece %s laid" % [piece["house"], TownPlan.piece_key(piece)])
	check(w.build.pieces[TownPlan.piece_key(p["pieces"][0])].get("town", false), "laid as the town's")
	var beds := 0
	var furniture := 0
	for key: String in w.build.pieces:
		var kind := w.build.kind_of(w.build.pieces[key]["id"])
		beds += 1 if kind == "bed" else 0
		furniture += 1 if kind == "prop" else 0
	eq(beds, p["houses"].size(), "a bed in every house")
	check(furniture >= p["houses"].size() * 4, "furnished (%d pieces of furniture)" % furniture)
	var trash := (p["items"] as Array).filter(func(it: Dictionary) -> bool: return it["kind"] == "trash_can")
	check(trash.size() >= p["houses"].size() - 2, "a trash can behind nearly every house")
	for it: Dictionary in trash:
		eq(w.loot.containers.get(it["id"], {}).get("table", ""), "trash", "%s is searchable" % it["id"])
	var h: Dictionary = p["houses"][0]
	var mid := SuburbPlan.house_rect(h).get_center()
	check(w.is_indoors(Vector3(mid.x, 0.1, mid.y)), "inside a house is indoors")
	var ids := w.spawn_house_zombies(shown)
	eq(ids.size(), p["houses"].size() / SuburbPlan.ZOMBIE_SHARE, "a zombie in one house in three")
	for id: int in ids:
		var z: ZombieBrain = w.horde.zombies[id]
		check(w.is_indoors(z.pos), "each stands inside (%s)" % z.pos)


func test_houses_steer_round_what_an_older_save_built() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v23.json")
	eq(int(d.get("version", 0)), 23, "the fixture is a version-23 save (written by the W3b code)")
	check(not SaveGame.holds_suburbs(d), "it doesn't hold the new streets")
	var p := SuburbPlan.generate(int(d["seed"]))
	var hit := ""
	for h: Dictionary in p["houses"]:
		if "f:-36:-26" in SuburbPlan.house_keys(p, h["name"]):
			hit = h["name"]
	check(hit != "", "a house would stand on the save's foundation on West Street")
	var w := SimWorld.new(8.0, null, int(d["seed"]))
	var taken := {}
	for piece: Dictionary in d["pieces"]:
		taken[str(piece["key"])] = true
	var shown := w.place_suburbs(p, true, taken)  # what main.gd does: lay round the save's pieces, apply, zombies
	eq(w.suburbs_skipped, [hit], "that house is left out")
	eq(shown["houses"].size(), p["houses"].size() - 1, "the rest are there")
	eq(SaveGame.apply(w, d), "", "loads cleanly")
	eq(w.build.pieces.get("f:-36:-26", {}).get("id", ""), "foundation", "the player's foundation is still there")
	eq(w.build.pieces.get("w:-36:-26:n", {}).get("id", ""), "wall", "and their wall")
	check(not w.build.pieces["f:-36:-26"].get("town", false), "and still theirs")
	eq(w.suburbs_skipped, [hit], "loading an older save doesn't forget the skip")
	var again := SaveGame.to_dict(w)
	eq(int(again["version"]), 24, "saved as version 24")
	eq(again["suburbs_skipped"], [hit], "with the skip")
	var b := SimWorld.new(8.0, null, int(d["seed"]))
	b.suburbs_skipped = Array(again["suburbs_skipped"])
	var shown_b := b.place_suburbs(p, false)
	eq(SaveGame.apply(b, JSON.parse_string(JSON.stringify(again))), "", "the version-24 save loads")
	eq(shown_b["houses"].size(), p["houses"].size() - 1, "and the skipped house stays away")
	eq(b.build.pieces.size(), w.build.pieces.size(), "every piece comes back from the save")


func test_the_session_log_names_street_houses() -> void:
	var w := SimWorld.new(12.0)
	var p := SuburbPlan.generate(1)
	w.know_houses({"houses": p["houses"]})
	var h: Dictionary = p["houses"][0]
	var label: String = w.house_cells[h["cells"][0]]
	check(label.ends_with("side)") and label.contains("Street house"), "a street house has its own name (%s)" % label)


# --- Physics -------------------------------------------------------------------------

func _setup(p: Dictionary) -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(80, 2, 200)
	shape.shape = slab
	shape.position = Vector3(-60, -1.0, -20)
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	sim.place_suburbs(p, true)
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	var roofs := TownView.new()
	_scene.add_child(roofs)
	roofs.setup(p, sim.build)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_walk_into_a_west_street_house() -> void:
	var p := SuburbPlan.generate(1)
	_setup(p)
	var h: Dictionary = (p["houses"] as Array).filter(func(x: Dictionary) -> bool: return str(x["name"]).begins_with("west_"))[0]
	var door_key := BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"])
	sim.toggle_door(door_key, Vector3(float(h["road_x"]), 0, 0))
	var out := -1.0 if h["east"] else 1.0  # toward the road, from the front
	var front_x: float = (h["door_cell"].x + (0 if h["east"] else 1)) * BuildGrid.GRID
	var dz: float = (int(h["door_cell"].y) + 0.5) * BuildGrid.GRID
	player.position = Vector3(front_x + out * 3.0, 0.1, dz)
	player.set_look(90.0 if out > 0.0 else -90.0, 0)  # facing the house
	player.wish_move = Vector2(0, 1)
	await _run(1.4)
	player.wish_move = Vector2.ZERO
	var at := Vector2(player.global_position.x, player.global_position.z)
	check(SuburbPlan.house_rect(h).has_point(at), "%s: walked in through the front door (at %s)" % [h["name"], at])
	_scene.queue_free()
	await tree.process_frame
