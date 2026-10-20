extends "res://test/base_test.gd"
## R1b (Emmitt: "should we make loot respawn?" and "more places like where we got Pete's old rifle"): loot that comes
## back the right way. Supply trucks go off the road every few days (a big container, a stuck horn the dead hear, the
## radio saying where); Rust-style forage piles turn up round town and run out; four named guardians stand at their
## posts with a gold piece each, like Old Pete. Saved; a save from before loads and gets its guardians.

const TICK := SimWorld.TICK
const S := ZombieBrain.State


func _sim(seed_value: int = 5) -> SimWorld:
	var sim := SimWorld.new(12.0, null, seed_value, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	return sim


## Day by day to `day`: the clock wraps through each midnight (a day set by hand runs no schedule).
func _to_day(sim: SimWorld, day: int) -> void:
	while sim.clock.day < day:
		sim.clock.time_of_day = 23.9999
		sim.step()


func _horns(sim: SimWorld) -> Array:
	return sim.noise.continuous.filter(func(s: Dictionary) -> bool: return s["kind"] == "horn_truck")


func test_the_data() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "supplies.json, the pile kinds, the uniques and the named types check out")
	check(not data.supplies.is_empty(), "supplies.json loads")
	var spots: Array = data.supplies["truck"]["spots"]
	check(spots.size() >= 4, "several truck spots (%d)" % spots.size())
	for sp: Dictionary in spots:
		var p := Vector2(float(sp["pos"][0]), float(sp["pos"][1]))
		check(not WorldMap.on_road(p, 2.0), "truck spot '%s' is beside the road, not on it" % sp["name"])
		var d := float(WorldMap.nearest(p)["dist"])
		check(d < 14.0, "and near one (%s: %.0f m off the road's middle)" % [sp["name"], d])
		check(WorldMap.area_at(Vector3(p.x, 0, p.y)) not in ["town", "park", "downtown"], "%s is out of town" % sp["name"])
	for kind: String in data.supplies["piles"]["kinds"]:
		var k: Dictionary = data.resources["kinds"][kind]
		check(int(k["holds"]) > 0 and str(k["extractor"]) == "" and not (k["hand"] as Dictionary).is_empty(), "%s is a hand-only pile" % kind)
	for type: String in data.supplies["guardians"]:
		check(bool(data.zombies[type].get("named", false)), "%s is a named type" % type)
		check(data.gear["zombie_uniques"].has(type), "%s has a gold piece" % type)
		check(str(data.supplies["guardians"][type]["post"]) in SimWorld.GUARDIAN_POSTS, "%s has a post" % type)
	check(data.loot.has("supply_truck") and data.gear["containers"].has("supply_truck") and data.guns["finds"].has("supply_truck"),
			"the truck's loot table has gear and gun odds")
	# a pile kind with an extractor, or an extractor kind with holds, is a data error
	var bad := GameData.load_default()
	bad.resources["kinds"]["scrap_pile"]["extractor"] = "salvager"
	check(not bad.validate().is_empty(), "a pile with an extractor is refused")


func test_a_truck_goes_off_the_road_every_few_days_and_its_horn_draws_the_dead() -> void:
	var sim := _sim()
	var tc: Dictionary = sim.data.supplies["truck"]
	var first := int(tc["first_day"])
	_to_day(sim, first - 1)
	eq(sim.supplies.trucks.size(), 0, "no truck before day %d" % first)
	_to_day(sim, first)
	eq(sim.supplies.trucks.size(), 1, "a truck on day %d" % first)
	if sim.supplies.trucks.is_empty():
		return
	sim.step()  # the horn joins the noise field on the tick after it lands
	var t: Dictionary = sim.supplies.trucks[0]
	var id := str(t["id"])
	check(sim.loot.containers.has(id) and sim.loot.containers[id]["table"] == tc["table"], "its back is a '%s' container" % tc["table"])
	eq(sim.container_name(id), "Supply truck", "named for what it is")
	eq(sim.wreck_type(id), str(tc["model"]), "and a wreck to strip for scrap")
	var horns := _horns(sim)
	eq(horns.size(), 1, "its horn is a continuous noise")
	if horns.size() == 1:
		near(float(horns[0]["loudness"]), float(tc["horn_loudness"]), "at horn_loudness")
		eq(horns[0]["key"], "truck:" + id, "keyed to the truck")
	check(bool(horns[0].get("world", false)) if horns.size() == 1 else false, "marked the world's own sound")
	near(sim.director.gain_now(sim.noise, true), 0.0, "the Director doesn't count it as your noise (no heat)")
	sim.director.heat = 150.0
	sim.director._check = 0.0
	check(sim.director.tick(TICK, sim.noise, true, sim.horde).is_empty(), "and sends no wave at it")
	var day_set := _sim(9)
	day_set.clock.day = 2
	day_set.step()
	eq(day_set.supplies.trucks.size(), 0, "a day set by hand (a test, --day) lands no truck: only a midnight does")
	var crowd: Array = sim.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return SimWorld._flat_dist(z.pos, t["pos"]) < 14.0)
	eq(crowd.size(), int(tc["zombies"]), "%d zombies are already round it" % int(tc["zombies"]))
	check(crowd.all(func(z: ZombieBrain) -> bool: return z.state == S.INVESTIGATE), "shuffling toward the horn")
	var logged := Array(sim.base_log.lines()).filter(func(l: String) -> bool: return "truck" in l and str(t["where"]) in l)
	check(not logged.is_empty(), "the base log says a truck went off the road on %s" % t["where"])
	check(sim.messages.any(func(m: Dictionary) -> bool: return "horn" in str(m["text"])), "and you're told a horn started blaring")
	eq(sim.reveal_container(id), "", "searched")
	check(not sim.loot.inventory(id).items().is_empty(), "there's a load in the back")
	eq(sim.stats.trucks_searched, 1, "the session log counts it")
	sim.step()
	eq(_horns(sim).size(), 0, "the horn stops once it's searched")
	var every := int(tc["every_days"])
	_to_day(sim, first + every - 1)
	eq(sim.supplies.trucks.size(), 1, "no second truck before %d days have passed" % every)
	_to_day(sim, first + every)
	eq(sim.supplies.trucks.size(), 2, "the second truck on day %d" % (first + every))
	if sim.supplies.trucks.size() < 2:
		return
	var t2: Dictionary = sim.supplies.trucks[1]
	check(t2["spot"] != t["spot"], "at a different spot")
	check(sim.supplies.horn_on(t2, sim.clock_hours(), sim.truck_searched), "the new one's horn is on")
	sim.clock.time_of_day += float(tc["horn_hours"]) + 0.1
	sim.step()
	check(not sim.supplies.horn_on(t2, sim.clock_hours(), sim.truck_searched), "and dies after %d hours unsearched" % int(tc["horn_hours"]))
	eq(_horns(sim).size(), 0, "quiet")


func test_forage_piles_turn_up_round_town_and_run_out() -> void:
	var sim := _sim(3)
	var plan := TownPlan.generate(3, sim.data)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	sim.know_houses(plan)
	var pc: Dictionary = sim.data.supplies["piles"]
	var raw: Array = pc["area"]
	var area := Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	var most := int(pc["max"])
	_to_day(sim, most + 2)
	eq(sim.supplies.piles.size(), most, "a pile a day, up to %d" % most)
	for p: Dictionary in sim.supplies.piles:
		var at: Vector3 = p["pos"]
		check(area.has_point(Vector2(at.x, at.z)), "%s is in the area" % p["id"])
		check(not WorldMap.on_road(Vector2(at.x, at.z), 2.0), "%s is off the road" % p["id"])
		var cell := BuildGrid.world_to_cell(at)
		check(not sim.house_cells.has(cell) and not sim.build.pieces.has("f:%d:%d" % [cell.x, cell.y]), "%s is not in a house" % p["id"])
		check(str(p["kind"]) in pc["kinds"], "%s is of a listed kind" % p["id"])
	for i in sim.supplies.piles.size():
		for j in range(i + 1, sim.supplies.piles.size()):
			check(SimWorld._flat_dist(sim.supplies.piles[i]["pos"], sim.supplies.piles[j]["pos"]) >= float(pc["apart"]), "piles keep apart")
	var p0: Dictionary = sim.supplies.piles[0]
	var pid := str(p0["id"])
	var node := sim.resource_node(pid)
	check(bool(node.get("pile", false)) and node["extractor"] == "", "a pile is a resource node with no extractor")
	eq(sim.node_at(node["cell"]), {}, "but not a spot an extractor goes on")
	sim.player_pos = p0["pos"] + Vector3(1.5, 0, 0)
	var hand := sim.hand_gather(node)
	check(sim.gather_start(pid).begins_with("You "), "E gathers from it by hand")
	var before := sim.inventory.count(hand["item"])
	var holds := int(p0["left"])
	for i in roundi((sim.gather_seconds(node) * holds + 5.0) / TICK):
		sim.step()
		if sim.gathering == "":
			break
	eq(sim.inventory.count(hand["item"]) - before, holds, "it gives everything it held (%d %s)" % [holds, hand["item"]])
	eq(sim.gathering, "", "then the gathering stops")
	check(sim.supplies.pile(pid).is_empty() and sim.resource_node(pid).is_empty(), "and the pile is gone")
	eq(sim.supplies.piles.size(), most - 1, "one fewer pile")
	eq(sim.stats.pile_items, holds, "the session log counts it")
	check(sim.messages.any(func(m: Dictionary) -> bool: return "picked clean" in str(m["text"])), "you're told it's picked clean")
	_to_day(sim, sim.clock.day + 1)
	eq(sim.supplies.piles.size(), most, "a new one comes the next day")


func test_trucks_and_piles_are_saved() -> void:
	var sim := _sim()
	_to_day(sim, 3)
	check(not sim.supplies.trucks.is_empty() and not sim.supplies.piles.is_empty(), "a truck and a pile by day 3")
	if sim.supplies.trucks.is_empty() or sim.supplies.piles.is_empty():
		return
	var t: Dictionary = sim.supplies.trucks[0]
	eq(sim.reveal_container(t["id"]), "", "the truck is searched")
	var had := {}
	for item: String in sim.loot.inventory(t["id"]).items():
		had[item] = sim.loot.inventory(t["id"]).count(item)
	var pid := str(sim.supplies.piles[0]["id"])
	var left := sim.supplies.take_from_pile(pid, 2)
	check(left > 0, "two taken from the pile, %d left" % left)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(d["version"]), 27, "save version 27")
	check(SaveGame.holds_supplies(d), "holds the supplies")
	var b := _sim()
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.supplies.trucks.size(), sim.supplies.trucks.size(), "the trucks are back")
	check(b.loot.containers.has(t["id"]) and bool(b.loot.containers[t["id"]]["searched"]), "the searched truck is still searched")
	var again := {}
	for item: String in b.loot.inventory(t["id"]).items():
		again[item] = b.loot.inventory(t["id"]).count(item)
	eq(again, had, "with what was left in it")
	eq(b.wreck_type(t["id"]), str(t["model"]), "still a wreck to strip")
	eq(_horns(b).size(), 0, "its horn stays quiet")
	eq(int(b.supplies.pile(pid).get("left", -1)), left, "the pile's count is kept")
	eq(b.supplies.last_truck_day, sim.supplies.last_truck_day, "and the schedule")
	eq(b.supplies.next_id, sim.supplies.next_id, "and the ids")
	b.step()
	eq(b.supplies.trucks.size(), sim.supplies.trucks.size(), "no truck doubles up on load")


func test_a_save_from_before_loads_and_gets_its_guardians_once() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v26.json")
	eq(int(d["version"]), 26, "the fixture is a version-26 save")
	check(not SaveGame.holds_supplies(d), "from before the trucks")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	var plan := TownPlan.generate(sim.seed_value, sim.data)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	eq(SaveGame.apply(sim, d), "", "it loads")
	eq(sim.supplies.trucks.size(), 0, "no trucks yet")
	check(sim.named_alive().all(func(g: Dictionary) -> bool: return g["type"] == "old_pete"), "only Old Pete so far")
	var spawned := sim.spawn_guardians()  # what main.gd does for a save without supplies
	eq(spawned.size(), 4, "the four guardians are put out")
	eq(sim.spawn_guardians().size(), 0, "once")
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	check(SaveGame.holds_supplies(again), "saved again, it holds them")
	var c := SimWorld.new(8.0, null, int(d["seed"]))
	c.place_town(plan)
	c.place_factory(plan)
	c.place_props(plan)
	eq(SaveGame.apply(c, again), "", "and loads")
	eq(c.named_alive().size(), 5, "five named dead standing (through the horde's save)")
	eq(c.spawn_guardians().size(), 0, "and they aren't put out twice")


func test_the_named_dead_stand_at_their_posts_with_a_gold_piece_each() -> void:
	var sim := _sim(1)
	var downtown := DowntownPlan.generate(1)
	sim.place_downtown(downtown)
	var rural := RuralPlan.generate(1)
	sim.place_rural(rural, true)
	sim.player_pos = Vector3(0, 0, 500)
	var spawned := sim.spawn_guardians()
	eq(spawned.size(), 4, "four guardians")
	var posts := sim.guardian_posts()
	var by_type := {}
	for z: ZombieBrain in spawned:
		by_type[z.type] = z
		check(z.is_guardian(), "%s is a guardian" % z.type)
		check(z.guard_area.has_point(Vector2(z.pos.x, z.pos.z)), "%s stands inside their area" % z.type)
		var post := str(sim.data.supplies["guardians"][z.type]["post"])
		eq(z.guard_area, posts[post]["guard"], "%s guards the %s" % [z.type, post])
		var cell := BuildGrid.world_to_cell(z.pos)
		check(not sim.build.pieces.has("o:%d:%d" % [cell.x, cell.y]), "%s isn't standing in a prop" % z.type)
	var police := DowntownPlan.shop(downtown, "police")
	var sheriff: ZombieBrain = by_type["sheriff"]
	check((police["rect"] as Rect2).has_point(Vector2(sheriff.pos.x, sheriff.pos.z)), "the sheriff is in the police station")
	var armory_z := (float(police["door_cell"].y) + float(police["inside_wall"])) * BuildGrid.GRID
	check(sheriff.pos.z > armory_z, "behind the inside wall, in the armory (z %.1f > %.1f)" % [sheriff.pos.z, armory_z])
	check(DowntownPlan.is_clear(downtown, Vector2(sheriff.pos.x, sheriff.pos.z), 0.5), "not in a desk or a locker")
	var pharmacy := DowntownPlan.shop(downtown, "pharmacy")
	var doc: ZombieBrain = by_type["pharmacist"]
	check((pharmacy["rect"] as Rect2).has_point(Vector2(doc.pos.x, doc.pos.z)), "the pharmacist is in the pharmacy")
	check(DowntownPlan.is_clear(downtown, Vector2(doc.pos.x, doc.pos.z), 0.5), "clear of the counters and shelves")
	var barn: Dictionary = rural["barns"].filter(func(b: Dictionary) -> bool: return b["farm"] == "west")[0]
	var farmer: ZombieBrain = by_type["farmer"]
	check((barn["rect"] as Rect2).has_point(Vector2(farmer.pos.x, farmer.pos.z)), "the farmer is in the west barn")
	var lineman: ZombieBrain = by_type["lineman"]
	check(ParkPlan.tower_rect().grow(8.0).has_point(Vector2(lineman.pos.x, lineman.pos.z)), "the lineman is at the water tower")
	check(not ParkPlan.tower_rect().has_point(Vector2(lineman.pos.x, lineman.pos.z)), "beside it, not inside its legs")
	# the base log notes a named one on the move
	sheriff.hear(sheriff.pos + Vector3(2, 0, 2))  # a sound inside the station: he goes to look
	eq(sheriff.state, S.INVESTIGATE, "the sheriff goes to look at a sound in the station")
	sim.ticks = SimWorld.TICK_RATE - 1
	sim.step()
	check(Array(sim.base_log.lines()).any(func(l: String) -> bool: return "Sheriff Dale is on the move" in l), "the base log says the sheriff is on the move")
	# each carries its own gold piece and its pockets
	for type: String in by_type:
		var z: ZombieBrain = by_type[type]
		z.take_hit(99999.0, z.pos + Vector3(1, 0, 0), 0.0)
		check(z.is_dead(), "%s goes down" % type)
	sim.step()
	for type: String in by_type:
		var z: ZombieBrain = by_type[type]
		var cid := SimWorld.CORPSE + str(z.id)
		eq(sim.reveal_container(cid), "", "%s's body can be searched" % type)
		var golds: Array = sim.loot.containers[cid]["gear"].filter(func(p: Dictionary) -> bool: return p["rarity"] == "gold")
		eq(golds.size(), 1, "%s carried one gold piece" % type)
		if golds.size() == 1:
			var want: String = sim.data.gear["uniques"][sim.data.gear["zombie_uniques"][type]]["name"]
			eq(golds[0]["name"], want, "their own: %s" % want)
		var pockets: Dictionary = sim.data.guns["zombie_extra_uniques"][type]["ammo"]
		for item: String in pockets:
			check(sim.loot.inventory(cid).count(item) >= int(pockets[item]), "%s's pockets hold %s" % [type, item])
		var said := sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).begins_with(str(sim.data.zombies[type]["name"]) + " is carrying"))
		check(said, "you were told %s carried something" % sim.data.zombies[type]["name"])
	# Old Pete's own extras still work the old way (his rifle and rounds)
	var pete := sim.spawn_old_pete()
	pete.take_hit(99999.0, pete.pos + Vector3(1, 0, 0), 0.0)
	sim.step()
	var pcid := SimWorld.CORPSE + str(pete.id)
	eq(sim.reveal_container(pcid), "", "Old Pete's body")
	eq(sim.loot.containers[pcid]["gear"].size(), 2, "his axe and his rifle")
	check(sim.loot.inventory(pcid).count("ammo_standard") >= 10, "and his rounds")
