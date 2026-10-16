extends "res://test/base_test.gd"
## W3d: the farms and the hunting cabin (RuralPlan) and the countryside's searchable wrecks: seeded; inside their
## areas and off every road, building, resource node and each other; closed buildings with their ways in; the
## cornfields fenced round, clear of the wells; laid round an older save's own building; loot, zombies, saves;
## walking into a barn and the cabin.

const SEEDS := [1, 2, 3, 4, 5, 6]
var _scene: Node3D
var sim: SimWorld
var player: Player


func _rects(plan: Dictionary, building: String) -> Array:
	var out: Array = []
	for p: Dictionary in plan["pieces"]:
		if p["building"] == building and p["id"] == "town_floor":
			out.append(RuralPlan.cell_rect(p["cell"]))
	return out


func test_same_seed_same_countryside() -> void:
	eq(str(RuralPlan.generate(5)), str(RuralPlan.generate(5)), "the same seed gives the same farms")
	var p := RuralPlan.generate(1)
	eq(RuralPlan.buildings(p), ["farmhouse_west", "barn_west", "farmhouse_south", "barn_south", "hunting_cabin"],
			"two farmhouses, two barns and the cabin")
	eq(p["houses"].size(), 3, "the farmhouses and the cabin are houses (roofs, the session log)")
	eq(p["barns"].size(), 2, "and two barns")


func test_buildings_stay_in_their_areas_and_off_everything() -> void:
	var data := GameData.load_default()
	for seed_value: int in SEEDS:
		var p := RuralPlan.generate(seed_value)
		var town := TownPlan.generate(seed_value)
		var others := {}
		for piece: Dictionary in town["pieces"] + town["factory"]["pieces"] + ParkPlan.generate(seed_value)["pieces"] \
				+ DowntownPlan.generate(seed_value)["pieces"] + SuburbPlan.generate(seed_value)["pieces"]:
			if piece["id"] == "town_floor":
				others[piece["cell"]] = true
		var mine := {}
		for piece: Dictionary in p["pieces"]:
			if piece["id"] != "town_floor":
				continue
			var c: Vector2i = piece["cell"]
			var b: String = piece["building"]
			var area: Rect2 = WorldMap.AREAS["cabin" if b == "hunting_cabin" else ("farm_west" if b.ends_with("west") else "farm_south")]
			if not area.encloses(RuralPlan.cell_rect(c)):
				check(false, "seed %d: %s cell %s is outside its area" % [seed_value, b, c])
			var mid := RuralPlan.cell_rect(c).get_center()
			if WorldMap.on_road(mid, 1.5) or others.has(c) or mine.has(c):
				check(false, "seed %d: %s cell %s is on a road or another building" % [seed_value, b, c])
			mine[c] = true
			for n: Dictionary in data.resources["nodes"]:
				if Vector2(n["pos"][0], n["pos"][1]).distance_to(mid) < 9.0:
					check(false, "seed %d: %s stands on the %s node" % [seed_value, b, n["id"]])
		for o: Dictionary in p["outdoor"]:
			var at := Vector2(o["pos"].x, o["pos"].z)
			if WorldMap.on_road(at, 0.5):
				check(false, "seed %d: a %s is on a road at %s" % [seed_value, o["kind"], at])
			for c: Vector2i in mine:
				if RuralPlan.cell_rect(c).grow(0.2).has_point(at):
					check(false, "seed %d: a %s is inside a building at %s" % [seed_value, o["kind"], at])
	var p := RuralPlan.generate(1)
	for farm: Dictionary in RuralPlan.FARMS:
		var f: Rect2 = farm["field"]
		var well: Dictionary = data.resources["nodes"].filter(func(n: Dictionary) -> bool: return n["id"] == "farm_%s_well" % farm["name"])[0]
		var w := Vector2(well["pos"][0], well["pos"][1])
		check(not f.grow(8.0).has_point(w), "the %s field keeps 8 m clear of its well" % farm["name"])
		var corn := (p["outdoor"] as Array).filter(func(o: Dictionary) -> bool:
			return o["kind"] == "corn_row" and f.has_point(Vector2(o["pos"].x, o["pos"].z))).size()
		check(corn > 300, "the %s field is full of corn (%d)" % [farm["name"], corn])
		var fence := (p["outdoor"] as Array).filter(func(o: Dictionary) -> bool:
			return o["kind"] == "farm_fence" and f.grow(1.0).has_point(Vector2(o["pos"].x, o["pos"].z))).size()
		var round_trip := roundi((f.size.x + f.size.y) * 2.0 / RuralPlan.FENCE)
		check(fence >= round_trip - 4 and fence < round_trip, "fenced round with a gate (%d of %d)" % [fence, round_trip])


func test_every_building_is_closed_with_a_way_in() -> void:
	var p := RuralPlan.generate(2)
	var edges := {}
	for piece: Dictionary in p["pieces"]:
		if piece["id"] != "town_floor":
			edges[TownPlan.piece_key(piece)] = piece["id"]
	for b: String in RuralPlan.buildings(p):
		var cells := {}
		for piece: Dictionary in p["pieces"]:
			if piece["building"] == b and piece["id"] == "town_floor":
				cells[piece["cell"]] = true
		var open := 0
		var doors := 0
		for c: Vector2i in cells:
			for side in 4:
				if cells.has(c + Factory.DIRS[side]):
					continue
				var id: String = edges.get(BuildGrid.key_for_wall_edge(c, side), "")
				open += 1 if id == "" else 0
				doors += 1 if id == "door" else 0
		if b.begins_with("barn"):
			eq(open, 2, "%s: a two-cell open doorway" % b)
			eq(doors, 1, "%s: and a back door" % b)
		else:
			eq(open, 0, "%s: closed all round" % b)
			check(doors >= 1, "%s: a door (%d)" % [b, doors])
	var cabin: Dictionary = (p["houses"] as Array).filter(func(h: Dictionary) -> bool: return h["name"] == "hunting_cabin")[0]
	eq(edges.get(BuildGrid.key_for_wall_edge(cabin["door_cell"], BuildGrid.Side.EAST), ""), "door", "the cabin's door faces the woods track")


func test_place_rural_lays_buildings_and_registers_fixtures() -> void:
	var w := SimWorld.new(12.0)
	var p := RuralPlan.generate(1)
	var shown := w.place_rural(p, true)
	eq(w.rural_skipped, [], "a new game skips nothing")
	for piece: Dictionary in p["pieces"]:
		if not w.build.pieces.has(TownPlan.piece_key(piece)):
			check(false, "%s piece %s laid" % [piece["building"], TownPlan.piece_key(piece)])
	var tables := {}
	for f: Dictionary in shown["fixtures"]:
		if str(f["table"]) != "":
			eq(w.loot.containers.get(f["id"], {}).get("table", ""), f["table"], "%s is searchable" % f["id"])
			tables[f["table"]] = true
	for t in ["barn", "tractor", "hunting_cabin"]:
		check(tables.has(t), "something holds '%s' loot" % t)
	for b: Dictionary in p["barns"]:
		var mid: Vector2 = (b["rect"] as Rect2).get_center()
		check(w.is_indoors(Vector3(mid.x, 0.1, mid.y)), "inside %s is indoors" % b["name"])
	var cabin_mid: Vector2 = (_rects(p, "hunting_cabin")[4] as Rect2).get_center()
	check(w.is_indoors(Vector3(cabin_mid.x, 0.1, cabin_mid.y)), "inside the cabin is indoors")
	var house_z := w.spawn_house_zombies(shown)
	eq(house_z.size(), 2, "a zombie in two of the three houses")
	var yard := w.spawn_park_zombies({"zombies": shown["yard_zombies"]})
	eq(yard.size(), shown["yard_zombies"].size(), "the barns', fields' and cabin's zombies")
	for id: int in yard:
		var z: ZombieBrain = w.horde.zombies[id]
		check(DowntownPlan.is_clear({"props": shown["fixtures"]}, Vector2(z.pos.x, z.pos.z), 0.3), "not inside a fixture")


func test_the_cabin_locker_holds_rifles_and_wrecks_can_be_searched() -> void:
	var guns := 0
	for seed_value: int in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
		var w := SimWorld.new(12.0, null, seed_value)
		w.place_rural(RuralPlan.generate(seed_value), true)
		eq(w.reveal_container("hunting_cabin_gun_locker"), "", "the gun locker opens")
		for piece: Dictionary in w.container_gear("hunting_cabin_gun_locker"):
			guns += 1 if w.gear.is_gun(piece) else 0
	check(guns >= 3, "the cabin's gun locker often has a gun (%d in 12 games)" % guns)
	var country := CountryPlan.generate(1)
	var w2 := SimWorld.new(12.0)
	w2.place_country(country)
	var ids := {}
	var highway := 0
	for wreck: Dictionary in country["wrecks"]:
		check(not ids.has(wreck["id"]), "%s is one of a kind" % wreck["id"])
		ids[wreck["id"]] = true
		eq(w2.loot.containers.get(wreck["id"], {}).get("table", ""), wreck["table"], "%s can be searched" % wreck["id"])
		highway += 1 if wreck["table"] == "highway_wreck" else 0
	eq(highway, CountryPlan.JAMS.size() * CountryPlan.WRECKS_PER_JAM, "every highway wreck has highway loot")


func test_buildings_steer_round_what_an_older_save_built() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v24.json")
	eq(int(d.get("version", 0)), 24, "the fixture is a version-24 save (written by the W3c code)")
	check(not SaveGame.holds_rural(d), "it doesn't hold the farms")
	var p := RuralPlan.generate(int(d["seed"]))
	check("f:-134:50" in RuralPlan.building_keys(p, "farmhouse_west"), "the west farmhouse would stand on the save's foundation")
	var w := SimWorld.new(8.0, null, int(d["seed"]))
	var taken := {}
	for piece: Dictionary in d["pieces"]:
		taken[str(piece["key"])] = true
	var shown := w.place_rural(p, true, taken)  # what main.gd does: lay round the save's pieces, apply, zombies
	eq(w.rural_skipped, ["farmhouse_west"], "that farmhouse is left out")
	eq(shown["houses"].size(), 2, "the other farmhouse and the cabin are there")
	eq(shown["barns"].size(), 2, "and both barns")
	eq(SaveGame.apply(w, d), "", "loads cleanly")
	eq(w.build.pieces.get("f:-134:50", {}).get("id", ""), "foundation", "the player's foundation is still there")
	eq(w.build.pieces.get("w:-134:50:n", {}).get("id", ""), "wall", "and their wall")
	eq(w.rural_skipped, ["farmhouse_west"], "loading an older save doesn't forget the skip")
	var again := SaveGame.to_dict(w)
	eq(int(again["version"]), SaveGame.VERSION, "saved as the current version")
	eq(again["rural_skipped"], ["farmhouse_west"], "with the skip")
	var b := SimWorld.new(8.0, null, int(d["seed"]))
	b.rural_skipped = Array(again["rural_skipped"])
	var shown_b := b.place_rural(p, false)
	eq(SaveGame.apply(b, JSON.parse_string(JSON.stringify(again))), "", "the new save loads")
	eq(shown_b["houses"].size(), 2, "and the skipped farmhouse stays away")
	eq(b.build.pieces.size(), w.build.pieces.size(), "every piece comes back from the save")


func test_the_session_log_names_them() -> void:
	var w := SimWorld.new(12.0)
	var p := RuralPlan.generate(1)
	w.know_houses({"houses": p["houses"]})
	var cabin: Dictionary = (p["houses"] as Array).filter(func(h: Dictionary) -> bool: return h["name"] == "hunting_cabin")[0]
	eq(w.house_cells[cabin["cells"][0]], "hunting cabin", "the cabin by name")


# --- Physics -------------------------------------------------------------------------

func _setup(p: Dictionary, centre: Vector3) -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(80, 2, 80)
	shape.shape = slab
	shape.position = centre + Vector3(0, -1.0, 0)
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	var shown := sim.place_rural(p, true)
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	var rv := RuralView.new()
	_scene.add_child(rv)
	rv.setup(sim, shown)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_walk_into_a_barn_and_search_the_tractor() -> void:
	var p := RuralPlan.generate(1)
	var barn: Dictionary = p["barns"][0]
	var r: Rect2 = barn["rect"]
	_setup(p, Vector3(r.get_center().x, 0, r.get_center().y))
	var door_z := r.position.y + (RuralPlan.BARN_DOOR_ROW + 1) * BuildGrid.GRID  # between the doorway's two cells
	player.position = Vector3(r.position.x - 3.0, 0.1, door_z)
	player.set_look(-90.0, 0)  # facing east, into the barn
	player.wish_move = Vector2(0, 1)
	await _run(1.2)
	player.wish_move = Vector2.ZERO
	var at := Vector2(player.global_position.x, player.global_position.z)
	check(r.has_point(at), "walked in through the open doorway (at %s)" % at)
	var rv: RuralView = _scene.get_children().filter(func(n: Node) -> bool: return n is RuralView)[0]
	eq(rv.barns, 2, "both barns are roofed")
	check(rv.is_under_roof(player.global_position + Vector3(0, 1.6, 0)), "under the barn's roof")
	var tractor: StaticBody3D = rv.fixtures["barn_west_tractor_wreck_0"]
	eq(tractor.get_meta("container_id", ""), "barn_west_tractor_wreck_0", "the tractor can be searched")
	_scene.queue_free()
	await tree.process_frame


func test_walk_into_the_hunting_cabin() -> void:
	var p := RuralPlan.generate(1)
	var cabin: Dictionary = (p["houses"] as Array).filter(func(h: Dictionary) -> bool: return h["name"] == "hunting_cabin")[0]
	var door: Vector2i = cabin["door_cell"]
	var front_x := (door.x + 1) * BuildGrid.GRID
	var dz := (door.y + 0.5) * BuildGrid.GRID
	_setup(p, Vector3(front_x, 0, dz))
	eq(sim.toggle_door(BuildGrid.key_for_wall_edge(door, BuildGrid.Side.EAST), Vector3(front_x + 5.0, 0, dz)), "Door opened", "the door opens")
	player.position = Vector3(front_x + 3.0, 0.1, dz)
	player.set_look(90.0, 0)  # facing west, at the door
	player.wish_move = Vector2(0, 1)
	await _run(1.2)
	player.wish_move = Vector2.ZERO
	var at := Vector2(player.global_position.x, player.global_position.z)
	var inside := false
	for r: Rect2 in _rects(p, "hunting_cabin"):
		inside = inside or r.has_point(at)
	check(inside, "walked into the cabin (at %s)" % at)
	_scene.queue_free()
	await tree.process_frame
