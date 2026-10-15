extends "res://test/base_test.gd"
## A1: the street plan (lamp posts, mailboxes, fences, trash cans, trees, road markings). Pure checks on the
## plan for a few seeds, the trash cans as containers, the Director's road route kept clear, and with real
## physics: you walk from the spawn to house 0's front door with the scenery in place; in the real game every
## street item has a collider, none sits on a car, and the lamps light at night.

const MAIN := "res://scenes/main.tscn"
const MAIN_SCRIPT := preload("res://src/world/main.gd")
const SEEDS := [1, 5, 77]


func _street(seed_value: int) -> Dictionary:
	return StreetPlan.generate(seed_value, TownPlan.generate(seed_value))


func _kind(street: Dictionary, kind: String) -> Array:
	return street["items"].filter(func(it: Dictionary) -> bool: return it["kind"] == kind)


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * BuildGrid.GRID, c.y * BuildGrid.GRID, BuildGrid.GRID, BuildGrid.GRID)


func test_same_seed_same_street() -> void:
	eq(var_to_str(_street(1)), var_to_str(_street(1)), "seed 1 twice gives the same street")
	eq(var_to_str(_street(5)), var_to_str(_street(5)), "seed 5 twice gives the same street")
	check(var_to_str(_street(1)) != var_to_str(_street(5)), "seeds 1 and 5 give different streets")


func test_every_piece_is_there() -> void:
	for s: int in SEEDS:
		var town := TownPlan.generate(s)
		var street := StreetPlan.generate(s, town)
		eq(_kind(street, "lamp_post").size(), 6, "seed %d: six lamp posts, three a side" % s)
		var mailboxes := _kind(street, "mailbox")
		eq(mailboxes.size(), 12, "seed %d: a mailbox for every house" % s)
		var colors := {}
		var near_ok := true
		var faces_road := true
		for m: Dictionary in mailboxes:
			colors[m["color"]] = true
			var h: Dictionary = town["houses"][m["house"]]
			var door := Vector2((h["door_cell"].x + 0.5) * BuildGrid.GRID, (h["door_cell"].y + 0.5) * BuildGrid.GRID)
			near_ok = near_ok and door.distance_to(Vector2(m["pos"].x, m["pos"].z)) < 5.0
			var front := Basis(Vector3.UP, deg_to_rad(m["yaw"])) * Vector3(0, 0, -1)
			faces_road = faces_road and signf(front.x) == -signf(m["pos"].x)
		eq(colors.size(), 12, "seed %d: every mailbox is its own colour" % s)
		check(near_ok, "seed %d: each mailbox is within 5 m of its front door" % s)
		check(faces_road, "seed %d: each mailbox's door faces the road" % s)
		eq(_kind(street, "fence").size(), 10 * StreetPlan.FENCE_SECTIONS, "seed %d: five fence lines a side" % s)
		var cans := _kind(street, "trash_can")
		var per_house := {}
		for c: Dictionary in cans:
			per_house[c["house"]] = per_house.get(c["house"], 0) + 1
		check(per_house.size() == 12 and per_house.values().max() <= 2,
				"seed %d: one or two trash cans at every house (%d cans)" % [s, cans.size()])
		var trees := _kind(street, "tree")
		var behind := trees.filter(func(t: Dictionary) -> bool: return t.has("house"))
		check(behind.size() >= 9, "seed %d: a tree behind most houses (%d)" % [s, behind.size()])
		check(trees.size() - behind.size() >= 5, "seed %d: trees at the ends of the road (%d)" % [s, trees.size() - behind.size()])
		var scales := {}
		for t: Dictionary in trees:
			scales[t["scale"]] = true
		check(scales.size() >= 2, "seed %d: trees come in more than one size" % s)
		check(street["markings"]["dashes"].size() >= 15 and street["markings"]["kerbs"].size() == 2,
				"seed %d: a dashed centre line and two kerbs" % s)


func test_nothing_on_the_road_houses_doors_or_start() -> void:
	var start := _cell_rect(MAIN_SCRIPT.STASH_CELL)
	var spawn: Vector3 = MAIN_SCRIPT.SPAWN
	for s: int in SEEDS:
		var town := TownPlan.generate(s)
		var street := StreetPlan.generate(s, town)
		var houses := StreetPlan.house_rects(town)
		var front := []  # each front door's cell and the cell in front of it
		var steps := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for h: Dictionary in town["houses"]:
			front.append(_cell_rect(h["door_cell"]))
			front.append(_cell_rect(h["door_cell"] + steps[h["door_side"]]))
		var paths := StreetPlan.door_paths(town)
		var bad: Array = []
		for it: Dictionary in street["items"]:
			var r := StreetPlan.footprint(it)
			var why := ""
			if r.intersects(StreetPlan.road_rect()):
				why = "on the road"
			elif r.intersects(TownPlan.factory_rect()):
				why = "in the factory"
			elif r.intersects(start) or r.grow(0.5).has_point(Vector2(spawn.x, spawn.z)):
				why = "on the start"
			for hr: Rect2 in houses:
				if r.intersects(hr):
					why = "on a house"
			for fr: Rect2 in front:
				if StreetPlan.gap(r, fr) < 1.5:
					why = "within 1.5 m of a front door"
			for pr: Rect2 in paths:
				if r.intersects(pr):
					why = "on the path to a front door"
			for other: Dictionary in street["items"]:
				if other != it and r.intersects(StreetPlan.footprint(other)):
					why = "on another item"
			if why != "":
				bad.append("%s at %s %s" % [it["kind"], it["pos"], why])
		check(bad.is_empty(), "seed %d: nothing on the road, a house, a door, its path or the start %s" % [s, bad.slice(0, 3)])


func test_fences_run_back_from_the_fronts_and_leave_a_gap() -> void:
	for s: int in SEEDS:
		var street := _street(s)
		var lines := {}
		var ok := true
		for f: Dictionary in _kind(street, "fence"):
			var r := StreetPlan.footprint(f)
			ok = ok and is_zero_approx(f["yaw"]) and absf(f["pos"].x) > StreetPlan.FRONT_X
			var key := "%d:%.2f" % [signi(int(f["pos"].x)), f["pos"].z]
			lines[key] = maxf(lines.get(key, 0.0), maxf(absf(r.position.x), absf(r.end.x)))
		check(ok, "seed %d: every fence section runs away from the road, behind the house fronts" % s)
		eq(lines.size(), 10, "seed %d: ten fence lines" % s)
		var gaps_open := true
		for key: String in lines:
			near(lines[key], StreetPlan.FENCE_END, "seed %d: fence %s ends at the back" % [s, key], 0.01)
			var sx := float(key.split(":")[0])
			var z := float(key.split(":")[1])
			var gap := Rect2(minf(sx * StreetPlan.FENCE_END, sx * StreetPlan.LOT_BACK), z - 1.0, StreetPlan.FENCE_GAP, 2.0)
			for it: Dictionary in street["items"]:
				gaps_open = gaps_open and not StreetPlan.footprint(it).intersects(gap)
		check(StreetPlan.FENCE_GAP >= 2.0 and gaps_open, "seed %d: a clear 2 m gap at the back of every fence line" % s)
		var lamps_ok := true
		for l: Dictionary in _kind(street, "lamp_post"):
			var x := absf(l["pos"].x)
			lamps_ok = lamps_ok and x > StreetPlan.ROAD_HALF and x < StreetPlan.FRONT_X
		check(lamps_ok, "seed %d: lamp posts stand on the strip beside the road" % s)


func test_trash_cans_are_searchable_containers() -> void:
	var sim := SimWorld.new(12.0)
	var street := _street(1)
	var cans := _kind(street, "trash_can")
	eq(sim.place_street(street), cans.size(), "every trash can registered")
	var ok := true
	for c: Dictionary in cans:
		var box: Dictionary = sim.loot.containers.get(c["id"], {})
		ok = ok and box.get("table", "") == "trash" and Vector2(box["pos"].x, box["pos"].z).distance_to(Vector2(c["pos"].x, c["pos"].z)) < 0.01
	check(ok, "each is a 'trash' container where its can stands")
	eq(sim.loot.display_name(cans[0]["id"]), "Trash can", "it is called a trash can")
	sim.player_pos = cans[0]["pos"] + Vector3(0.8, 0, 0)
	eq(sim.search(cans[0]["id"]), "", "you can search one")
	for i in roundi(10.0 / SimWorld.TICK):
		sim.step()
	check(sim.loot.containers[cans[0]["id"]]["searched"], "and it is searched once done")
	eq(sim.search(cans[0]["id"]), "Already searched", "and stays searched")


func test_trash_is_mostly_nothing() -> void:
	var data := GameData.load_default()
	var t: Dictionary = data.loot["trash"]
	eq(int(t["rolls"][1]), 1, "trash rolls once")
	var empty := 0
	var allowed := true
	for s in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var got := Loot.roll(t, rng)
		if got.is_empty():
			empty += 1
		for item: String in got:
			allowed = allowed and item in ["scrap_metal", "nails", "bandage", "canned_food", "bottle"]  # V30: empty bottles to throw
		allowed = allowed and got.size() <= 1
	check(allowed, "only scrap, nails, a bandage, canned food or a bottle, one thing at most")
	check(empty > 200 and empty < 340, "mostly nothing (%d of 400 empty)" % empty)


func test_director_road_route_stays_clear() -> void:
	var street := _street(1)
	var rects: Array = street["items"].map(func(it: Dictionary) -> Rect2: return StreetPlan.footprint(it).grow(0.5))
	var lures := [Vector3(0, 0, 0), Vector3(12, 0, -40), Vector3(-12, 0, -80), Vector3(20, 0, -100), Vector3(-30, 0, -20)]
	var bad: Array = []
	var points := 0
	for start: Vector3 in [Vector3(0, 0, -300), Vector3(0, 0, 200), Vector3(262, 0, 0)]:  # W3a: north road, south road, highway
		for lure: Vector3 in lures:
			var route: Array = WorldMap.route(start, lure)
			for i in route.size():
				points += 1
				var a: Vector3 = route[i]
				var b: Vector3 = route[mini(i + 1, route.size() - 1)]
				var steps := maxi(1, ceili(a.distance_to(b) / 0.5))
				for k in steps + 1:
					var p := a.lerp(b, float(k) / steps)
					for r: Rect2 in rects:
						if r.has_point(Vector2(p.x, p.z)):
							bad.append(Vector2(p.x, p.z))
	check(points > 20, "routes from both ends checked (%d points)" % points)
	check(bad.is_empty(), "no road route point or leg runs into street scenery %s" % [bad.slice(0, 3)])


## Physics: from the spawn to house 0's front door, steering straight at it, with every street collider in place.
func test_walk_from_spawn_to_house_0_door() -> void:
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(200, 2, 200)
	shape.shape = slab
	shape.position.y = -1.0
	ground.add_child(shape)
	scene.add_child(ground)
	var sim := SimWorld.new(12.0)
	var town := TownPlan.generate(1)
	sim.place_town(town)
	var view := BuildView.new()
	scene.add_child(view)
	view.setup(sim.build)
	var street := StreetPlan.generate(1, town)
	var street_view := StreetView.new()
	scene.add_child(street_view)
	street_view.setup(sim, street)
	eq(street_view.bodies.size(), street["items"].size(), "every street item has a body")
	var player := Player.new()
	player.use_device_input = false
	player.position = MAIN_SCRIPT.SPAWN
	scene.add_child(player)
	var h: Dictionary = town["houses"][0]
	var c: Vector2i = h["door_cell"]
	var steps := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var outside: Vector2i = c + steps[h["door_side"]]
	var goal := Vector3((outside.x + 0.5) * BuildGrid.GRID, 0, (outside.y + 0.5) * BuildGrid.GRID)
	var reached := false
	for i in 60 * 12:
		await tree.physics_frame
		var d := goal - player.global_position
		d.y = 0.0
		if d.length() < 0.6:
			reached = true
			break
		player.set_look(rad_to_deg(atan2(-d.x, -d.z)), 0.0)
		player.wish_move = Vector2(0, 1)
	player.wish_move = Vector2.ZERO
	check(reached, "walked from the spawn to house 0's front door (ended %.1f m away)" % (goal - player.global_position).length())
	scene.queue_free()
	await tree.process_frame


func test_real_game_street() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sv: StreetView = main.street_view
	check(sv != null and sv.bodies.size() == main.street["items"].size(), "the game draws every street item")
	var on_car: Array = []
	for car_id: String in main.cars:
		var car: CarBody = main.cars[car_id]
		var p := car.global_position
		var car_rect := Rect2(p.x - 1.5, p.z - 3.0, 3.0, 6.0)  # generous: any car, either way round
		for it: Dictionary in main.street["items"]:
			if StreetPlan.footprint(it).intersects(car_rect):
				on_car.append("%s by %s" % [it["kind"], car_id])
	check(main.cars.size() == 4 + main.park["wrecks"].size() + main.downtown["wrecks"].size() and on_car.is_empty(), "nothing stands on a car %s" % [on_car])
	var trash := 0
	for id: String in main.sim.loot.containers:
		trash += 1 if main.sim.loot.containers[id]["table"] == "trash" else 0
	var dumpsters := (main.downtown["props"] as Array).filter(func(pr: Dictionary) -> bool: return pr["table"] == "trash").size()  # W3b
	eq(trash, StreetPlan.generate(main.sim.seed_value, main.town)["items"].filter(
			func(it: Dictionary) -> bool: return it["kind"] == "trash_can").size() + dumpsters, "the game registers the trash cans (and downtown's dumpsters)")
	var can_body: StaticBody3D = sv.bodies[main.street["items"].find(
			main.street["items"].filter(func(it: Dictionary) -> bool: return it["kind"] == "trash_can")[0])]
	check(can_body.has_meta("container_id") and can_body.collision_layer == Layers.WORLD,
			"a trash can's body is searchable and on the world layer")
	eq(sv.lights.size(), 6, "a light for each lamp post")
	check(not sv.lit and not sv.lights[0].visible, "lamps are off by day (08:00)")
	main.sim.clock.time_of_day = 22.0
	await tree.process_frame
	check(sv.lit and sv.lights.all(func(l: OmniLight3D) -> bool: return l.visible and l.omni_range == 10.0),
			"at 22:00 every lamp is lit, 10 m")
	main.queue_free()
	await tree.process_frame
	GameSession.skip_menu = false
	GameSession.skip_hints = false
