extends "res://test/base_test.gd"
## W3b: downtown (DowntownPlan): seeded, inside its area and off every road, the town, the park and the resource
## nodes; five closed shops with a front door; props inside their shop, apart, with a way to every container;
## the new loot tables (the police station's gun lockers find guns); its zombies and its saves; walking in.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]
const RADIUS := 0.32  # about the player's (Player.RADIUS), for the walking-room checks
var _scene: Node3D
var sim: SimWorld
var player: Player


func test_same_seed_same_downtown() -> void:
	eq(str(DowntownPlan.generate(3)), str(DowntownPlan.generate(3)), "the same seed gives the same downtown")
	var p := DowntownPlan.generate(1)
	eq(p["shops"].size(), 5, "five shops")
	var names := (p["shops"] as Array).map(func(s: Dictionary) -> String: return s["name"])
	eq(names, ["grocery", "pharmacy", "hardware", "police", "gas_station"], "grocery, pharmacy, hardware, police, gas")


func test_downtown_stays_in_its_area_and_off_everything() -> void:
	var area: Rect2 = WorldMap.AREAS["downtown"]
	var data := GameData.load_default()
	for seed_value: int in SEEDS:
		var p := DowntownPlan.generate(seed_value)
		var town := TownPlan.generate(seed_value)
		var park := ParkPlan.generate(seed_value)
		var taken := {}
		for piece: Dictionary in town["pieces"] + town["factory"]["pieces"] + park["pieces"]:
			if piece["id"] == "town_floor":
				taken[piece["cell"]] = true
		for s: Dictionary in p["shops"]:
			check(area.encloses(s["rect"]), "seed %d: %s is downtown" % [seed_value, s["name"]])
			for c: Vector2i in s["cells"]:
				var mid := Vector2((c.x + 0.5) * BuildGrid.GRID, (c.y + 0.5) * BuildGrid.GRID)
				if WorldMap.on_road(mid, 1.0) or taken.has(c):
					check(false, "seed %d: %s cell %s is on a road or another building" % [seed_value, s["name"], c])
		for pr: Dictionary in p["props"]:
			var r := DowntownPlan.prop_rect(pr)
			check(area.grow(1.0).encloses(r), "seed %d: %s is downtown" % [seed_value, pr["id"]])
			if pr["shop"] == "" or DowntownPlan.shop(p, pr["shop"])["rect"].encloses(r):
				continue
			check(not WorldMap.on_road(r.get_center(), 0.5), "seed %d: %s is off the road" % [seed_value, pr["id"]])
		for w: Dictionary in p["wrecks"]:
			check(WorldMap.on_road(Vector2(w["pos"].x, w["pos"].z)), "seed %d: %s is on Market Street" % [seed_value, w["id"]])
			for s: Dictionary in p["shops"]:
				check(not (s["rect"] as Rect2).grow(3.0).has_point(Vector2(w["pos"].x, w["pos"].z)), "and clear of the shops")
	var p := DowntownPlan.generate(1)
	for n: Dictionary in data.resources["nodes"]:
		var spots := [Vector2(n["pos"][0], n["pos"][1]), Vector2(n["pos"][0] + n["prop"][0], n["pos"][1] + n["prop"][1])]
		for at: Vector2 in spots:
			check(DowntownPlan.is_open_ground(p, at, 2.0) or not area.grow(4.0).has_point(at), "node %s keeps clear of the shops" % n["id"])
	check(WorldMap.area_at(Vector3(79, 0, 77)) == "downtown", "the gas station's tanker node is downtown")


func test_every_shop_is_a_closed_room_with_a_door() -> void:
	var p := DowntownPlan.generate(1)
	var edges := {}  # edge key -> piece id
	var floors := {}
	for piece: Dictionary in p["pieces"]:
		if piece["id"] == "town_floor":
			floors[piece["cell"]] = true
		else:
			check(not edges.has(TownPlan.piece_key(piece)), "one piece per edge (%s)" % TownPlan.piece_key(piece))
			edges[TownPlan.piece_key(piece)] = piece["id"]
	for s: Dictionary in p["shops"]:
		var cells := {}
		for c: Vector2i in s["cells"]:
			cells[c] = true
			check(floors.has(c), "%s: a floor on %s" % [s["name"], c])
		var doors := 0
		var windows := 0
		for c: Vector2i in cells:
			for side in 4:
				if cells.has(c + Factory.DIRS[side]):
					continue
				var key := BuildGrid.key_for_wall_edge(c, side)
				check(edges.has(key), "%s: the outside edge %s is closed" % [s["name"], key])
				doors += 1 if edges.get(key, "") == "door" else 0
				windows += 1 if edges.get(key, "") == "window" else 0
		eq(edges.get(BuildGrid.key_for_wall_edge(s["door_cell"], s["door_side"]), ""), "door", "%s: a front door" % s["name"])
		eq(doors, 1 if s["name"] == "police" else 2, "%s: front and back doors (the police station only a front one)" % s["name"])
		check(windows >= 4, "%s: shop windows (%d)" % [s["name"], windows])
	var police := DowntownPlan.shop(p, "police")
	var inside := 0
	for piece: Dictionary in p["pieces"]:
		if piece["style"] == "plaster" and piece["id"] == "town_wall" and DowntownPlan.shop_at(p, piece["cell"]) == 3:
			inside += 1
	eq(inside, (police["rect"] as Rect2).size.x / BuildGrid.GRID - 1, "the armory wall has one open doorway")


func test_props_fit_and_leave_a_way_to_every_container() -> void:
	var p := DowntownPlan.generate(1)
	var props: Array = p["props"]
	for i in props.size():
		var a := DowntownPlan.prop_rect(props[i])
		var s := DowntownPlan.shop(p, props[i]["shop"])
		var outside: bool = props[i]["model"] in ["dumpster", "bench", "gas_pump"]
		if not outside:
			check((s["rect"] as Rect2).grow(-0.1).encloses(a), "%s stands inside its shop" % props[i]["id"])
		for j in range(i + 1, props.size()):
			check(not a.intersects(DowntownPlan.prop_rect(props[j])), "%s and %s don't overlap" % [props[i]["id"], props[j]["id"]])
	for s: Dictionary in p["shops"]:
		var reach := _reachable(p, s)
		for pr: Dictionary in props:
			if pr["shop"] != s["name"] or str(pr["table"]) == "" or pr["model"] in ["dumpster", "gas_pump"]:
				continue
			var f: Vector2 = pr["facing"]
			var front := Vector2(pr["pos"].x, pr["pos"].z) + f * ((pr["size"] as Vector3).z / 2.0 + RADIUS + 0.15)
			check(reach.has(_snap(front)), "%s: you can walk up to the front of %s" % [s["name"], pr["id"]])


## Half-quarter-metre spots inside shop `s` you can stand on (clear of the props and walls by RADIUS), reached
## from just inside the front door.
func _reachable(p: Dictionary, s: Dictionary) -> Dictionary:
	var r: Rect2 = s["rect"]
	var room := r.grow(-0.1 - RADIUS)
	var wall_z := -INF
	var gap := Rect2()
	if int(s["inside_wall"]) > 0:
		wall_z = s["front_z"] - s["inside_wall"] * BuildGrid.GRID if s["north"] else s["front_z"] + s["inside_wall"] * BuildGrid.GRID
		var gx := r.position.x + int(s["inside_doorway"]) * BuildGrid.GRID
		gap = Rect2(gx + RADIUS, wall_z - 1.0, BuildGrid.GRID - 2.0 * RADIUS, 2.0)
	var open := func(q: Vector2) -> bool:
		if not room.has_point(q) or not DowntownPlan.is_clear(p, q, RADIUS):
			return false
		return absf(q.y - wall_z) > 0.1 + RADIUS or gap.has_point(q)
	var door: Vector2i = s["door_cell"]
	var start := _snap(Vector2((door.x + 0.5) * BuildGrid.GRID, s["front_z"] + (-0.6 if s["north"] else 0.6)))
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var q: Vector2 = todo.pop_back()
		for d: Vector2 in [Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:
			var n := _snap(q + d)
			if not seen.has(n) and open.call(n):
				seen[n] = true
				todo.append(n)
	return seen


func _snap(q: Vector2) -> Vector2:
	return Vector2(snappedf(q.x, 0.25), snappedf(q.y, 0.25))


func test_place_downtown_registers_containers_and_wrecks() -> void:
	var w := SimWorld.new(12.0)
	var p := DowntownPlan.generate(1)
	eq(w.place_downtown(p), p["pieces"].size(), "every shop piece laid")
	check(w.build.pieces[TownPlan.piece_key(p["pieces"][0])].get("town", false), "laid as the town's")
	var tables := {}
	for pr: Dictionary in p["props"]:
		if str(pr["table"]) == "":
			check(not w.loot.containers.has(pr["id"]), "%s is just furniture" % pr["id"])
			continue
		check(w.data.loot.has(pr["table"]), "%s: loot table '%s' exists" % [pr["id"], pr["table"]])
		eq(w.loot.containers.get(pr["id"], {}).get("table", ""), pr["table"], "%s is searchable" % pr["id"])
		tables[pr["table"]] = true
	for t in ["grocery", "pharmacy", "hardware", "police_desk", "gun_locker", "gas_station", "gas_pump", "trash"]:
		check(tables.has(t), "something downtown holds '%s' loot" % t)
	for wr: Dictionary in p["wrecks"]:
		check(w.vehicles.why_not(wr["id"]) != "", "%s can't be driven" % wr["id"])
		eq(w.loot.containers[wr["id"]]["table"], "car_trunk", "its trunk can be searched")
	var grocery := DowntownPlan.shop(p, "grocery")
	var mid: Vector2 = (grocery["rect"] as Rect2).get_center()
	check(w.is_indoors(Vector3(mid.x, 0.1, mid.y)), "inside the grocery is indoors")
	check(not w.is_indoors(Vector3(mid.x, 0.0, DowntownPlan.STREET_Z)), "the street isn't")


func test_gun_lockers_hold_guns_and_ammo() -> void:
	var guns := 0
	var ammo := 0
	var searched := 0
	for seed_value: int in SEEDS:
		var w := SimWorld.new(12.0, null, seed_value)
		var p := DowntownPlan.generate(seed_value)
		w.place_downtown(p)
		for pr: Dictionary in p["props"]:
			if pr["table"] != "gun_locker":
				continue
			eq(w.reveal_container(pr["id"]), "", "a gun locker opens")
			searched += 1
			for piece: Dictionary in w.container_gear(pr["id"]):
				guns += 1 if w.gear.is_gun(piece) else 0
			var inv: Inventory = w.loot.inventory(pr["id"])
			for it: String in ["ammo_standard", "shells", "ammo_subsonic", "ammo_ap"]:
				ammo += inv.count(it)
	check(guns >= searched / 5, "gun lockers find guns (%d in %d lockers)" % [guns, searched])
	check(ammo > searched * 4, "and plenty of ammunition (%d rounds)" % ammo)


func test_downtown_zombies_spawn_inside_and_are_saved() -> void:
	var w := SimWorld.new(12.0)
	var p := DowntownPlan.generate(1)
	w.place_downtown(p)
	var ids := w.spawn_downtown_zombies(p)
	eq(ids.size(), p["zombies"].size(), "every planned zombie")
	var brutes := 0
	for i in ids.size():
		var z: ZombieBrain = w.horde.zombies[ids[i]]
		var pz: Dictionary = p["zombies"][i]
		brutes += 1 if z.type == "brute" else 0
		if pz["shop"] != "":
			eq(DowntownPlan.shop_at(p, BuildGrid.world_to_cell(z.pos)), (p["shops"] as Array).find(DowntownPlan.shop(p, pz["shop"])),
					"%s zombie stands in its shop" % pz["shop"])
		check(DowntownPlan.is_clear(p, Vector2(z.pos.x, z.pos.z), 0.3), "not inside a shelf")
	eq(brutes, 1, "a brute in the police station")
	var d := SaveGame.to_dict(w)
	check(int(d["version"]) >= 23, "saved as version 23 or later")
	check(SaveGame.holds_downtown(d), "which holds downtown")
	var b := SimWorld.new(8.0)
	b.place_downtown(p, false)
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.horde.zombies.size(), w.horde.zombies.size(), "downtown's zombies come back, no more")
	eq(b.build.pieces.size(), w.build.pieces.size(), "the shops come back from the save")


func test_version_22_save_gets_downtown_fresh() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v22.json")
	eq(int(d.get("version", 0)), 22, "the fixture is a version-22 save (written by the F3 code)")
	check(not SaveGame.holds_downtown(d), "it doesn't hold downtown")
	var w := SimWorld.new(8.0, null, int(d["seed"]))
	var p := DowntownPlan.generate(int(d["seed"]))
	w.place_downtown(p, not SaveGame.holds_downtown(d))  # what main.gd does: lay downtown, apply, then its zombies
	eq(SaveGame.apply(w, d), "", "loads cleanly")
	w.spawn_downtown_zombies(p)
	eq(w.horde.zombies.size(), d["zombies"].size() + p["zombies"].size(), "its own zombies plus downtown's")
	var door: Dictionary = p["shops"][0]
	check(w.build.pieces.has(BuildGrid.key_for_wall_edge(door["door_cell"], door["door_side"])), "the grocery's door is there")
	check(w.milestones.unlocked("salvager"), "and F2's grant still applies to it")


# --- Physics -------------------------------------------------------------------------

func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(120, 2, 60)
	shape.shape = slab
	shape.position = Vector3(60, -1.0, 60)
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	var p := DowntownPlan.generate(1)
	sim.place_downtown(p)
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	var dview := DowntownView.new()
	_scene.add_child(dview)
	dview.setup(sim, p)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_walk_into_the_grocery_and_search_a_shelf() -> void:
	_setup()
	var p := DowntownPlan.generate(1)
	var s := DowntownPlan.shop(p, "grocery")
	var door_key := BuildGrid.key_for_wall_edge(s["door_cell"], s["door_side"])
	eq(sim.toggle_door(door_key, Vector3(0, 0, DowntownPlan.STREET_Z)), "Door opened", "the front door opens")
	var dx := (int(s["door_cell"].x) + 0.5) * BuildGrid.GRID
	player.position = Vector3(dx, 0.1, float(s["front_z"]) + 3.0)  # on the sidewalk, facing the door (north)
	player.set_look(0, 0)
	player.wish_move = Vector2(0, 1)
	await _run(1.6)
	player.wish_move = Vector2.ZERO
	var at := Vector2(player.global_position.x, player.global_position.z)
	check((s["rect"] as Rect2).has_point(at), "walked in through the door (at %s)" % at)
	await _run(0.2)
	var dview: DowntownView = _scene.get_children().filter(func(n: Node) -> bool: return n is DowntownView)[0]
	eq(dview.signs.size(), 5, "a sign over every shop")
	check(dview.is_under_roof(player.global_position + Vector3(0, 1.6, 0)), "under the grocery's roof")
	var shelf: Dictionary = (p["props"] as Array).filter(func(pr: Dictionary) -> bool: return pr["table"] == "grocery")[0]
	var body: StaticBody3D = dview.props[shelf["id"]]
	eq(body.get_meta("container_id", ""), shelf["id"], "a grocery shelf can be searched with E")
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			SimWorld.downtown_prop_pos(shelf) + Vector3(0, 0, 2.0), SimWorld.downtown_prop_pos(shelf)))
	check(not hit.is_empty() and hit["collider"] == body, "and it's solid where it stands")
	_scene.queue_free()
	await tree.process_frame
