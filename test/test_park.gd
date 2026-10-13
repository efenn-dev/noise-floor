extends "res://test/base_test.gd"
## M17a: the industrial park (ParkPlan): seeded and deterministic, never on the town, the factory hall, the
## road or itself; warehouses you can walk into; the "industrial" loot table and the park's raised Police
## chance; its zombies spawn and are saved; the Director's road routes reach the new north end through the park.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
var _scene: Node3D
var sim: SimWorld
var player: Player


func _house_rects(town: Dictionary) -> Array:
	var out: Array = []
	for h: Dictionary in town["houses"]:
		for c: Vector2i in h["cells"]:
			out.append(ParkPlan.cell_rect(c))
	return out


func test_same_seed_same_park() -> void:
	var a := ParkPlan.generate(3)
	var b := ParkPlan.generate(3)
	eq(var_to_str(a), var_to_str(b), "the same seed gives the same park")
	var c := ParkPlan.generate(4)
	check(var_to_str(a) != var_to_str(c), "another seed gives another park")
	eq(a["warehouses"].size(), 4, "four warehouses")
	var styles := {}
	for s: int in SEEDS:
		for wh: Dictionary in ParkPlan.generate(s)["warehouses"]:
			styles[wh["style"]] = true
	eq(styles.size(), 2, "brick and corrugated warehouses both turn up")


func test_park_never_overlaps_anything() -> void:
	var town := TownPlan.generate(1)
	var houses := _house_rects(town)
	var factory := TownPlan.factory_rect()
	var bad := 0
	for s: int in SEEDS:
		var p := ParkPlan.generate(s)
		var rects: Array = []
		for wh: Dictionary in p["warehouses"]:
			var r: Rect2 = wh["rect"]
			eq(wh["cells"].size(), ParkPlan.SIZE.x * ParkPlan.SIZE.y, "seed %d: a 6 x 10 cell floor" % s)
			check(ParkPlan.area().encloses(r), "seed %d: %s inside the park's fence" % [s, wh["name"]])
			check(not r.intersects(factory), "seed %d: not on the factory hall" % s)
			check(not r.intersects(ParkPlan.road_rect()) and not r.intersects(StreetPlan.road_rect()), "seed %d: off the road" % s)
			check(not r.intersects(ParkPlan.tower_rect()), "seed %d: not on the water tower" % s)
			for h: Rect2 in houses:
				if r.intersects(h):
					bad += 1
			for o: Rect2 in rects:
				check(not r.grow(2.0).intersects(o), "seed %d: warehouses at least 4 m apart" % s)
			rects.append(r)
			# Closed all round less the big doorway (two empty edges facing the road) and the back doorway.
			eq(wh["doorway"].size(), ParkPlan.DOOR_WIDTH, "seed %d: a two-cell doorway" % s)
		check(not ParkPlan.tower_rect().intersects(factory) and not ParkPlan.tower_rect().intersects(ParkPlan.road_rect()),
				"seed %d: the tower is off the road and the hall" % s)
		check(ParkPlan.area().position.y + ParkPlan.area().size.y <= factory.position.y - 3.0, "the park is north of the hall")
	eq(bad, 0, "no warehouse on any house")


func test_warehouse_pieces_crates_and_doorways() -> void:
	var p := ParkPlan.generate(1)
	var keys := {}
	for piece: Dictionary in p["pieces"]:
		var k := TownPlan.piece_key(piece)
		check(not keys.has(k), "no piece laid twice (%s)" % k)
		keys[k] = true
	var town := TownPlan.generate(1)
	for piece: Dictionary in town["pieces"] + town["factory"]["pieces"]:
		check(not keys.has(TownPlan.piece_key(piece)), "no park piece on a town piece")
	for wh: Dictionary in p["warehouses"]:
		var walls := 0
		var windows := 0
		var ids := {}
		for piece: Dictionary in p["pieces"]:
			ids[TownPlan.piece_key(piece)] = piece["id"]
		var cells := {}
		for c: Vector2i in wh["cells"]:
			cells[c] = true
		for c: Vector2i in wh["cells"]:
			for side in 4:
				if cells.has(c + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]):
					continue
				var id: String = ids.get(BuildGrid.key_for_wall_edge(c, side), "")
				walls += 1 if id == "town_wall" else 0
				windows += 1 if id == "window" else 0
		eq(walls + windows, 2 * (ParkPlan.SIZE.x + ParkPlan.SIZE.y) - ParkPlan.DOOR_WIDTH - 1,
				"%s: walls and windows all round less the doorway and the back door" % wh["name"])
		eq(windows, 4, "%s: two windows in each end wall" % wh["name"])
		for k: String in wh["doorway"] + [wh["back_door"]]:
			check(not keys.has(k), "%s: doorway edge %s is open" % [wh["name"], k])
		var n: int = p["crates"].filter(func(c: Dictionary) -> bool: return c["warehouse"] == wh["name"]).size()
		check(n >= ParkPlan.CRATES_MIN and n <= ParkPlan.CRATES_MAX, "%s: 3 to 5 crates (%d)" % [wh["name"], n])
	var cells := {}
	for c: Dictionary in p["crates"]:
		eq(c["table"], "industrial", "crates roll the industrial table")
		check(ParkPlan.warehouse_at(p, c["cell"]) >= 0, "crate %s inside a warehouse" % c["id"])
		check(not cells.has(c["cell"]), "one crate per cell")
		cells[c["cell"]] = true
		var wall := BuildGrid.key_for_wall_edge(c["cell"], c["side"])
		check(keys.has(wall), "crate %s stands against a wall" % c["id"])


func test_zombies_wrecks_and_fence() -> void:
	for s: int in SEEDS:
		var p := ParkPlan.generate(s)
		var shamblers := 0
		var runners := 0
		var inside := 0
		for z: Dictionary in p["zombies"]:
			shamblers += 1 if z["type"] == "shambler" else 0
			runners += 1 if z["type"] == "runner" else 0
			var cell := BuildGrid.world_to_cell(z["pos"])
			if z["warehouse"] >= 0:
				inside += 1
				eq(ParkPlan.warehouse_at(p, cell), z["warehouse"], "seed %d: an inside zombie stands in its warehouse" % s)
			else:
				check(ParkPlan.is_open_ground(p, Vector2(z["pos"].x, z["pos"].z), 1.0), "seed %d: an outside one on open ground" % s)
		eq(shamblers, 10, "seed %d: ten shamblers" % s)
		eq(runners, 2, "seed %d: two runners" % s)
		eq(inside, 8, "seed %d: two in each warehouse, four between them" % s)
		check(p["wrecks"].size() >= 2 and p["wrecks"].size() <= 3, "seed %d: two or three wrecks" % s)
		for w: Dictionary in p["wrecks"]:
			check(ParkPlan.road_rect().has_point(Vector2(w["pos"].x, w["pos"].z)), "seed %d: a wreck on the park road" % s)
		check(p["fences"].size() > 80, "seed %d: a fence round the park (%d sections)" % [s, p["fences"].size()])
		var west: Array = p["fences"].filter(func(f: Dictionary) -> bool: return is_equal_approx(f["pos"].x, -ParkPlan.FENCE_X))
		var full := roundi((ParkPlan.FENCE_SOUTH_Z - ParkPlan.FENCE_NORTH_Z) / ParkPlan.FENCE_LENGTH)
		check(west.size() < full and west.size() > full / 2, "seed %d: the west fence has gaps (%d of %d)" % [s, west.size(), full])


## A point is in a wreck if it's inside the car's box, turned by its yaw.
func _in_wreck(p: Vector2, w: Dictionary, data: GameData) -> bool:
	var size: Array = data.vehicles[w["type"]]["size"]
	var local := (p - Vector2(w["pos"].x, w["pos"].z)).rotated(float(w["yaw"]))
	return absf(local.x) < float(size[0]) / 2.0 + 0.3 and absf(local.y) < float(size[2]) / 2.0 + 0.3


func test_road_routes_reach_the_north_end_through_the_park() -> void:
	var lure := Vector3(21, 1, -49)
	var north := Director.road_route("north", lure)
	eq(north[0], Vector3(0, 0, ParkPlan.ROAD_NORTH_Z), "from the north: the park road's north end first")
	check(Director.EDGES[0].z < ParkPlan.FENCE_NORTH_Z, "the north wave spawns past the park's north fence")
	var in_park := north.filter(func(p: Vector3) -> bool: return p.z < -150.0 and p.x == 0.0).size()
	check(in_park >= 2, "it walks the park road (%d points)" % in_park)
	check(north.has(Vector3(-25, 0, -142)) and north.has(Vector3(-25, 0, -106)), "round the hall's west side")
	eq(north.back(), Vector3(0, 0, -49), "then down the town road to the noise")
	var tower := ParkPlan.TOWER_POS
	var from_south := Director.road_route("south", tower)
	eq(from_south.back(), Vector3(0, 0, tower.z), "from the south, a noise at the tower: up into the park")
	check(from_south.has(Vector3(-25, 0, -106)) and from_south.has(Vector3(0, 0, -142)), "round the hall and onto the park road")
	var from_north := Director.road_route("north", tower)
	eq(from_north.back(), Vector3(0, 0, tower.z), "from the north: down the park road to the tower")
	check(not from_north.has(Vector3(-25, 0, -142)), "without going round the hall")
	for route: Array in [north, from_south, from_north]:
		for i in range(1, route.size()):
			check(route[i].distance_to(route[i - 1]) <= Director.ROAD_LEG + 0.01, "legs no longer than %d m" % Director.ROAD_LEG)
	# Nothing in the park stands on the routes.
	var data := GameData.load_default()
	var bad: Array = []
	for s: int in SEEDS:
		var p := ParkPlan.generate(s)
		for e: int in [0, 1]:
			for l: Vector3 in [tower, Vector3(-20, 0, -240), Vector3(12, 0, -40)]:
				var route: Array = [Director.EDGES[e]] + Director.road_route(Director.EDGE_NAMES[e], l)
				for i in route.size() - 1:
					for k in 41:
						var q: Vector3 = (route[i] as Vector3).lerp(route[i + 1], k / 40.0)
						var q2 := Vector2(q.x, q.z)
						for w: Dictionary in p["wrecks"]:
							if _in_wreck(q2, w, data):
								bad.append(q2)
						for f: Dictionary in p["fences"]:
							if Vector2(f["pos"].x, f["pos"].z).distance_to(q2) < 1.5:
								bad.append(q2)
						for wh: Dictionary in p["warehouses"]:
							if (wh["rect"] as Rect2).has_point(q2):
								bad.append(q2)
	check(bad.is_empty(), "no route runs into a wreck, a fence or a warehouse %s" % [bad.slice(0, 3)])


func test_waves_from_the_north_spawn_past_the_park() -> void:
	var seen_north := false
	for s: int in [1, 2, 3, 4, 5, 6]:
		var w := SimWorld.new(23.0, null, s)
		w.power.free = true
		w.give_debug_kit()
		w.build.place("foundation", Vector2i(10, -25), BuildGrid.Side.NORTH, w.inventory)
		w.build.place("smelter", Vector2i(10, -25), BuildGrid.Side.EAST, w.inventory)
		w.factory.machines[Vector2i(10, -25)].input["scrap_metal"] = 20
		w.player_pos = Vector3(0, 0, 500)
		w.director.heat = 100.0
		for i in roundi(30.1 / SimWorld.TICK):
			w.step()
		for z: ZombieBrain in w.horde.zombies.values():
			if z.home.z < -200.0:
				seen_north = true
				check(z.home.z < ParkPlan.FENCE_NORTH_Z, "seed %d: spawned past the park's north fence (z %.0f)" % [s, z.home.z])
				eq(z.route[0], Vector3(0, 0, ParkPlan.ROAD_NORTH_Z), "seed %d: walks the park road first" % s)
	check(seen_north, "a wave came from the north")


func test_industrial_loot_and_police_chance() -> void:
	var data := GameData.load_default()
	var table: Dictionary = data.loot["industrial"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {}
	for i in 400:
		var got := Loot.roll(table, rng)
		check(not got.is_empty(), "a warehouse crate is never empty")
		for item: String in got:
			counts[item] = int(counts.get(item, 0)) + 1
	for item: String in ["metal_plate", "wall_panel", "nails", "gas_can", "ammo_standard"]:
		check(counts.has(item), "warehouse crates hold %s" % item)
	check(int(counts.get("metal_plate", 0)) > 150, "metal plates are common (%d of 400)" % int(counts.get("metal_plate", 0)))
	var finds: Dictionary = data.guns["finds"]
	for kind: String in ["gun", "part", "ammo"]:
		for other: String in finds:
			if other != "industrial":
				check(float(finds["industrial"][kind]) > float(finds[other][kind]),
						"more %s in warehouse crates than in %s" % [kind, other])
	check(float(data.gear["containers"]["industrial"]) >= float(data.gear["containers"]["factory_crate"]), "gear as often as the factory's crates")
	var gear := Gear.new(data)
	near(gear.police_chance("industrial"), 3.0 * gear.police_chance("kitchen"), "Police tier three times as likely in the park")
	near(gear.police_chance("kitchen"), float(data.gear["tiers"]["police"]["chance"]), "the town's chance is unchanged")
	var park_police := 0
	var town_police := 0
	rng.seed = 9
	for i in 2000:
		park_police += 1 if gear.roll_piece(rng, "industrial")["tier"] == "police" else 0
		town_police += 1 if gear.roll_piece(rng, "factory_crate")["tier"] == "police" else 0
	check(park_police > 2.4 * town_police and park_police < 3.6 * town_police,
			"rolled: %d Police pieces in the park, %d in town, of 2000 each" % [park_police, town_police])
	var gun_police := 0
	for i in 1000:
		gun_police += 1 if gear.roll_gun_piece(rng, "part", false, "industrial")["tier"] == "police" else 0
	check(gun_police > 350, "gun parts found in the park are Police tier about 45%% of the time (%d of 1000)" % gun_police)


func test_place_park_registers_crates_wrecks_and_the_tower() -> void:
	var w := SimWorld.new(12.0)
	var p := ParkPlan.generate(1)
	var n := w.place_park(p)
	eq(n, p["pieces"].size(), "every warehouse piece laid")
	for piece: Dictionary in p["pieces"]:
		check(w.build.pieces[TownPlan.piece_key(piece)].get("town", false), "laid as the town's (salvage, not refunds)")
		if piece["id"] != "town_floor":
			break
	for c: Dictionary in p["crates"]:
		eq(w.loot.containers[c["id"]]["table"], "industrial", "crate %s is searchable" % c["id"])
	for wr: Dictionary in p["wrecks"]:
		check(w.vehicles.cars.has(wr["id"]), "%s is a car" % wr["id"])
		check(w.vehicles.why_not(wr["id"]) != "", "%s can't be driven (%s)" % [wr["id"], w.vehicles.why_not(wr["id"])])
		eq(w.loot.containers[wr["id"]]["table"], "car_trunk", "its trunk can be searched")
	check(w.projects.sites.has("water_tower"), "the water tower is a project site")
	# A crate search gives industrial loot.
	var c: Dictionary = p["crates"][0]
	w.player_pos = w.loot.containers[c["id"]]["pos"]
	eq(w.search(c["id"]), "", "searching a warehouse crate starts")
	var before := w.inventory.items().size()
	for i in roundi(w.loot.search_time() / SimWorld.TICK) + 2:
		w.step()
	check(w.loot.containers[c["id"]]["searched"], "searched")
	check(w.inventory.items().size() > before, "found something")


func test_park_zombies_spawn_and_are_saved() -> void:
	var w := SimWorld.new(12.0)
	var p := ParkPlan.generate(1)
	w.place_park(p)
	var ids := w.spawn_park_zombies(p)
	eq(ids.size(), 12, "twelve park zombies")
	var types := {}
	for id: int in ids:
		types[w.horde.zombies[id].type] = int(types.get(w.horde.zombies[id].type, 0)) + 1
	eq(types, {"shambler": 10, "runner": 2}, "ten shamblers and two runners")
	w.player_pos = Vector3(0, 0, 0)  # far away: nothing draws them
	for i in roundi(60.0 / SimWorld.TICK):
		w.step()
	for id: int in ids:
		var z: ZombieBrain = w.horde.zombies[id]
		var pz: Dictionary = p["zombies"][ids.find(id)]
		if pz["warehouse"] >= 0:
			eq(ParkPlan.warehouse_at(p, BuildGrid.world_to_cell(z.pos)), pz["warehouse"], "an inside zombie stays inside")
	var d := SaveGame.to_dict(w)
	var b := SimWorld.new(8.0)
	b.place_park(p, false)
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.horde.zombies.size(), w.horde.zombies.size(), "the park zombies come back, no more")
	for id: int in ids:
		eq(b.horde.zombies[id].type, w.horde.zombies[id].type, "same kind")
		check(b.horde.zombies[id].pos.distance_to(w.horde.zombies[id].pos) < 0.01, "same place")
	eq(b.build.pieces.size(), w.build.pieces.size(), "the warehouses come back from the save")


func test_version_11_save_gets_the_park_fresh() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v11.json")
	eq(int(d.get("version", 0)), 11, "the fixture is a version-11 save (written by the A2 code)")
	check(not SaveGame.holds_park(d), "it doesn't hold the park")
	var w := SimWorld.new(8.0, null, int(d["seed"]))
	var p := ParkPlan.generate(int(d["seed"]))
	w.place_park(p, not SaveGame.holds_park(d))  # what main.gd does: lay the park, apply, then its zombies
	eq(SaveGame.apply(w, d), "", "loads cleanly")
	w.spawn_park_zombies(p)
	eq(w.horde.zombies.size(), d["zombies"].size() + 12, "its own zombie plus the park's twelve")
	eq(w.projects.phase("water_tower"), 0, "the tower at phase 0")
	check(w.projects.done.is_empty(), "nothing done")
	for key: String in TownPlan.factory()["north_doorway"]:
		check(not w.build.pieces.has(key), "the hall's north doorway is opened (%s)" % key)
	eq(w.climate.stoves.size(), 1, "its stove still")
	eq(w.clock.day, 17, "day 17")
	for v in range(2, 12):
		var old := SaveGame.read("res://test/fixtures/save_v%d.json" % v)
		var s := SimWorld.new(8.0, null, int(old.get("seed", 1)))
		s.place_park(ParkPlan.generate(int(old.get("seed", 1))))
		eq(SaveGame.apply(s, old), "", "the version-%d fixture still loads" % v)
		eq(s.projects.phase("water_tower"), 0, "v%d: the tower at phase 0" % v)


# --- Physics -------------------------------------------------------------------------

func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(90, 2, 140)
	shape.shape = slab
	shape.position = Vector3(0, -1.0, -200)
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	sim.place_park(ParkPlan.generate(1))
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_walk_into_a_warehouse() -> void:
	_setup()
	var p := ParkPlan.generate(1)
	for wh: Dictionary in [p["warehouses"][0], p["warehouses"][1]]:  # one west, one east of the road
		var r: Rect2 = wh["rect"]
		var door: Vector2i = wh["door_cells"][0]
		var mid_z := (door.y + 1) * BuildGrid.GRID  # between the doorway's two cells
		var face := r.end.x if not wh["east"] else r.position.x  # the road-side wall
		var out := 1.0 if not wh["east"] else -1.0  # toward the road
		player.position = Vector3(face + out * 5.0, 0.1, mid_z)
		player.set_look(90.0 if out > 0.0 else -90.0, 0)  # facing the warehouse
		player.wish_move = Vector2(0, 1)
		await _run(2.5)
		var at := Vector2(player.global_position.x, player.global_position.z)
		check(r.has_point(at), "%s: walked in through the doorway (at %s)" % [wh["name"], at])
		player.position = Vector3(face + out * 5.0, 0.1, r.position.y + 1.0)  # in front of the wall, off the doorway
		await _run(2.5)
		at = Vector2(player.global_position.x, player.global_position.z)
		check(not r.has_point(at), "%s: the wall beside it stops you (at %s)" % [wh["name"], at])
		player.wish_move = Vector2.ZERO
	_scene.queue_free()
	await tree.process_frame


func test_tower_and_tap_models() -> void:
	var scene := (load(ParkView.TOWER_MODEL) as PackedScene).instantiate() as Node3D
	tree.root.add_child(scene)
	var box := AABB()
	var first := true
	for m: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	check(not first, "the water tower model has a mesh")
	check(box.size.y > 11.5 and box.size.y <= ParkView.TOWER_SIZE.y + 0.01, "about 12 m tall (%.2f)" % box.size.y)
	check(box.size.x <= ParkView.TOWER_SIZE.x + 0.01 and box.size.z <= ParkView.TOWER_SIZE.z + 0.01, "fits its 6 x 6 m footprint")
	near(box.position.y, -ParkView.TOWER_SIZE.y / 2.0, "stands on the floor of its box", 0.02)
	scene.queue_free()
	check(BuildView.MODELS.has("water_tap") and ResourceLoader.exists(BuildView.MODELS["water_tap"]), "the water tap has a model")
