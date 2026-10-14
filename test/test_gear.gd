extends "res://test/base_test.gd"
## M13 loot: gear pieces with rarity, rolled stats, tiers, slots, condition and repair kits; the unique
## (Old Pete's axe) and the Night Shift set; where gear comes from; carrying, dying and saving it.

const TICK := SimWorld.TICK


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## A piece straight into your pockets, then worn.
func _wear(sim: SimWorld, base: String, stats: Dictionary = {}, rarity := "blue", set_id := "", tier := "civilian") -> Dictionary:
	var p := sim.gear.make(base, tier, rarity, stats, 1.0, "", set_id)
	sim.gear.pieces.append(p)
	eq(sim.gear.equip(p["uid"]), "", "equip %s" % base)
	return p


func test_gear_data_is_valid() -> void:
	var data := GameData.load_default()
	var gear_errors := Array(data.validate()).filter(func(e: String) -> bool: return "gear" in e or "unique" in e or "set " in e)
	eq(gear_errors, [], "gear.json validates")
	eq(data.gear["slots"], ["head", "body", "hands", "legs", "feet", "back", "light", "weapon", "primary", "sidearm"],
			"all clothing, bag and weapon slots")
	for r: String in ["white", "blue", "yellow", "gold", "set", "orange"]:
		check(data.gear["rarities"].has(r), "rarity " + r)
	var bad := GameData.load_default()
	bad.gear["bases"]["axe"]["slot"] = "tail"
	bad.gear["stats"]["strength"]["max"] = 0
	bad.gear["sets"]["night_shift"]["pieces"]["boots"] = "Night Shift Boots"
	var errors := " ".join(bad.validate())
	check("gear base 'axe'" in errors and "gear stat 'strength'" in errors and "unknown base 'boots'" in errors,
			"a broken gear.json is caught")


func test_start_pipe_is_a_white_piece_in_the_weapon_slot() -> void:
	var sim := SimWorld.new()
	var pipe: Dictionary = sim.gear.equipped.get("weapon", {})
	eq(pipe.get("base"), "pipe", "you start holding the pipe")
	eq(pipe.get("rarity"), "white", "white")
	eq(pipe.get("stats"), {}, "base stats only")
	near(pipe.get("condition", 0.0), 1.0, "mint")
	eq(sim.gear.pieces, [], "nothing in your pockets")
	near(sim.weapon_stats()["damage"], 34.0, "pipe damage as before")
	eq(sim.gear.unequip("weapon"), "", "you can put it away")
	eq(sim.weapon_stats()["name"], "Fists", "then you punch")
	near(sim.carried_kg(), 1.5, "and carry it (1.5 kg)")


func test_rolled_stats_stay_in_their_ranges() -> void:
	var sim := SimWorld.new()
	var table: Dictionary = sim.data.gear["stats"]
	var rng := _rng(5)
	var bad := 0
	var seen := {}
	for i in 600:
		var p := sim.gear.roll_piece(rng, "factory_crate")
		for s: String in p["stats"]:
			seen[s] = true
			var v := float(p["stats"][s])
			if v < float(table[s]["min"]) - 1e-6 or v > float(table[s]["max"]) + 1e-6:
				bad += 1
		if p["condition"] < 0.4 or p["condition"] > 1.0:
			bad += 1
	eq(bad, 0, "every rolled stat and condition inside gear.json's ranges")
	eq(seen.size(), table.keys().filter(func(s: String) -> bool: return not table[s].has("slots")).size(),
			"every stat turns up (but no gun-only stats on ordinary gear, M14)")
	var u: Dictionary = sim.data.gear["uniques"]["petes_fire_axe"]
	for i in 50:
		var axe := sim.gear.roll_unique(rng, "petes_fire_axe")
		for s: String in u["stats"]:
			if axe["stats"][s] < float(u["stats"][s][0]) or axe["stats"][s] > float(u["stats"][s][1]):
				bad += 1
		if i == 0:
			eq(axe["stats"].keys().size(), 3, "the unique has its fixed three stats")
	eq(bad, 0, "the unique's stats inside their ranges")


func test_rarity_odds_and_stat_counts() -> void:
	var sim := SimWorld.new()
	var rng := _rng(11)
	var n := 6000
	var count := {"white": 0, "blue": 0, "yellow": 0, "set": 0}
	var bad_counts := 0
	var police := 0
	for i in n:
		var p := sim.gear.roll_piece(rng, "factory_crate")
		count[p["rarity"]] += 1
		var k: int = p["stats"].size()
		var extra := 1 if p["tier"] == "police" else 0
		police += extra
		match p["rarity"]:
			"white": bad_counts += 0 if k == 0 else 1
			"blue": bad_counts += 0 if k >= 1 + extra and k <= 2 + extra else 1
			"yellow": bad_counts += 0 if k >= 3 + extra and k <= 5 + extra else 1
	near(count["white"] / float(n), 0.70, "white about 70%", 0.03)
	near(count["blue"] / float(n), 0.20, "blue about 20%", 0.025)
	near(count["yellow"] / float(n), 0.08, "yellow about 8%", 0.015)
	near(count["set"] / float(n), 0.02, "set about 2% in a factory crate", 0.008)
	near(police / float(n), 0.15, "Police tier about 15%", 0.02)
	eq(bad_counts, 0, "white 0 stats, blue 1-2, yellow 3-5 (Police +1)")
	var civ := sim.gear.make("bat", "civilian", "yellow", sim.gear.roll_stats(rng, 4))
	eq(civ["stats"].size(), 4, "roll_stats gives different stats")
	var kitchen_sets := 0
	for i in 3000:
		var p := sim.gear.roll_piece(rng, "kitchen")
		if p["rarity"] == "set":
			kitchen_sets += 1
			check(p["tier"] == "police", "a set piece outside the factory is Police tier")
	check(kitchen_sets < 30, "set pieces are rare outside the factory (%d of 3000)" % kitchen_sets)


func test_police_tier_hits_harder() -> void:
	var sim := SimWorld.new()
	_wear(sim, "axe", {}, "white", "", "police")
	near(sim.weapon_stats()["damage"], 48.0 * 1.25, "a Police axe: base damage x1.25")
	check(sim.gear.equipped["weapon"]["name"].begins_with("Police"), "and says so")
	eq(sim.gear.pieces.size(), 1, "the pipe went back in your pockets")


func test_skills_bonus_includes_equipped_gear() -> void:
	var sim := SimWorld.new()
	var limit := sim.carry_limit()
	var dmg := sim.melee_damage()
	var search := sim.loot.search_time()
	var p := sim.gear.make("cap", "civilian", "yellow", {"carry_kg": 10.0, "melee_damage": 0.2, "search_speed": 0.2})
	sim.gear.pieces.append(p)
	near(sim.skills.bonus("carry_kg"), 0.0, "in your pockets it does nothing")
	sim.gear.equip(p["uid"])
	near(sim.carry_limit(), limit + 10.0, "+10 kg carry when worn")
	near(sim.melee_damage(), dmg * 1.2, "+20% melee damage", 0.01)
	near(sim.loot.search_time(), search * 0.8, "searches 20% quicker", 0.01)
	near(sim.noise_loudness("footstep_walk"), float(sim.data.noise["sounds"]["footstep_walk"]) - 1.0,
			"the cap's base stat: footsteps 1 quieter")
	var s := SimWorld.new()
	s.skills.xp["strength"] = 0.0
	var before := s.carry_limit()
	_wear(s, "hard_hat", {"strength": 2.0})
	near(s.carry_limit(), before + 6.0, "+2 Strength counts as two Strength levels (3 kg each)")
	eq(s.skills.level("strength"), 0, "but doesn't change the level you earned")
	near(s.skills.bonus("damage_cut"), 0.05, "a hard hat's base stat: zombies hurt 5% less")


func test_perk_bonus_raises_ranked_perks_past_five() -> void:
	var sim := SimWorld.new()
	sim.skills.perks = {"heavy_swing": 5, "thick_skin": 1}
	near(sim.skills.bonus("melee_damage"), 0.5, "Heavy Swing 5")
	_wear(sim, "work_gloves", {"fighter_perks": 1.0})
	eq(sim.skills.effective_rank("heavy_swing"), 6, "+1 to Fighter perks: Heavy Swing 6, past the cap")
	eq(sim.skills.effective_rank("thick_skin"), 2, "Thick Skin 2")
	eq(sim.skills.effective_rank("second_wind"), 0, "no rank bought in Second Wind: still 0")
	eq(sim.skills.rank("heavy_swing"), 5, "the ranks you bought don't change")
	near(sim.skills.bonus("melee_damage"), 0.6 + 0.05, "melee damage from rank 6 (+ the gloves' base 5%)")
	near(sim.skills.bonus("damage_cut"), 0.10, "Thick Skin 2")
	sim.skills.perks["soft_step"] = 1
	eq(sim.skills.effective_rank("soft_step"), 1, "a Fighter bonus doesn't touch Ghost perks")


func test_night_shift_set_bonuses() -> void:
	var sim := SimWorld.new()
	var base_search := sim.skills.bonus("search_speed")
	var base_carry := sim.carry_limit()
	var walk := sim.noise_loudness("footstep_walk")
	var hit := sim.noise_loudness("melee_hit")
	_wear(sim, "hard_hat", {}, "set", "night_shift")
	eq(sim.gear.set_count("night_shift"), 1, "one piece")
	near(sim.skills.bonus("search_speed"), base_search, "1 piece: no set bonus")
	_wear(sim, "hi_vis_vest", {}, "set", "night_shift")
	near(sim.skills.bonus("search_speed"), base_search + 0.15, "2 pieces: +15% search speed")
	near(sim.carry_limit(), base_carry + 3.0, "(the vest's own +3 kg, no set carry yet)")
	_wear(sim, "work_gloves", {}, "set", "night_shift")
	near(sim.carry_limit(), base_carry + 3.0 + 10.0, "3 pieces: +10 kg carry")
	near(sim.noise_loudness("melee_hit"), hit, "3 pieces: noises not quieter yet")
	_wear(sim, "headlamp", {}, "set", "night_shift")
	near(sim.noise_loudness("melee_hit"), hit - 3.0, "all 4: your noises count as 3 quieter")
	near(sim.noise_loudness("footstep_walk"), walk - 3.0, "footsteps too")
	near(sim.skills.bonus("search_speed"), base_search + 0.15 + 0.05, "and the headlamp's own +5% search")


func test_gear_quiet_on_footsteps_and_swings() -> void:
	var sim := SimWorld.new()
	var walk := sim.noise_loudness("footstep_walk")
	var hit := sim.noise_loudness("melee_hit")
	var door := sim.noise_loudness("door")
	_wear(sim, "jacket", {"gear_quiet": 8.0})
	near(sim.noise_loudness("footstep_walk"), walk - 8.0, "footsteps 8 quieter")
	near(sim.noise_loudness("melee_hit"), hit - 8.0, "hits 8 quieter")
	near(sim.noise_loudness("door"), door, "a door isn't a footstep or a swing")


func test_condition_wear_break_and_repair() -> void:
	var sim := SimWorld.new()
	var axe := _wear(sim, "axe", {"melee_damage": 0.2})
	var z := sim.horde.spawn("shambler", Vector3(1, 0, 0))
	z.hp = 10000.0
	sim.hit_zombie(z.id, false)
	near(axe["condition"], 1.0 - 0.010, "V9: an axe wears 0.010 a hit (each weapon has its own rate)")
	var tough := _wear(sim, "bat", {"durability": 0.25})
	sim.hit_zombie(z.id, false)
	near(tough["condition"], 1.0 - 0.012 * 0.75, "a bat wears 0.012; +25% durability takes a quarter off")
	var hat := _wear(sim, "hard_hat", {"carry_kg": 10.0})
	var pocket_hat := sim.gear.make("cap", "civilian", "blue", {"carry_kg": 5.0})
	sim.gear.pieces.append(pocket_hat)
	sim._new_day()
	near(hat["condition"], 0.97, "a day wears what you're wearing 0.03")
	near(pocket_hat["condition"], 1.0, "not what's in your pockets")
	near(tough["condition"], 1.0 - 0.012 * 0.75, "nor the weapon (hits wear that)")
	var limit := sim.carry_limit()
	hat["condition"] = 0.26
	sim.gear._wear(hat, 0.02)
	near(sim.carry_limit(), limit - 10.0, "under 25%: the rolled +10 kg stops")
	near(sim.skills.bonus("damage_cut"), 0.05, "the base stat stays")
	check("worn out" in " ".join(PackedStringArray(sim.gear.stat_lines(hat))), "the screen says it's worn out")
	eq(sim.repair_gear(hat["uid"]), "You need a repair kit (the Press makes them)", "no kit, no repair")
	sim.inventory.add("repair_kit", 1)
	eq(sim.repair_gear(hat["uid"]), "Repaired Hard hat", "a kit repairs it")
	near(hat["condition"], 1.0, "back to mint")
	eq(sim.inventory.count("repair_kit"), 0, "the kit is used up")
	near(sim.carry_limit(), limit, "and its stats work again")
	var w := _wear(sim, "machete", {"melee_damage": 0.1})
	w["condition"] = 0.252
	sim.hit_zombie(z.id, false)
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].begins_with("Your Machete")),
			"the HUD says when your weapon wears out")


func test_press_makes_repair_kits() -> void:
	var sim := SimWorld.new()
	sim.power.free = true
	sim.inventory.give_all({"plank": 40, "metal_plate": 40, "nails": 10})
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("press", Vector2i(0, 0), BuildGrid.Side.EAST, sim.inventory)
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 0)]
	eq(m.recipe_id, "press_nails", "a press makes nails")
	eq(sim.cycle_recipe(Vector2i(0, 0)), "Press now makes Repair kit", "R switches it")
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	eq(m.input.get("nails", 0), 10, "it takes nails now")
	_run(sim, 7.0)
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	check(sim.inventory.count("repair_kit") >= 1, "out comes a repair kit")
	sim.cycle_recipe(Vector2i(0, 0))
	eq(m.recipe_id, "press_casings", "on to ammo casings (M14)")
	eq(m.input.get("nails", 0), 0, "the nails it held came back to you")
	sim.cycle_recipe(Vector2i(0, 0))
	eq(m.recipe_id, "press_bolts", "on to crossbow bolts (M15)")
	sim.cycle_recipe(Vector2i(0, 0))
	eq(m.recipe_id, "press_wall_panel", "and wall panels (M15)")
	sim.cycle_recipe(Vector2i(0, 0))
	eq(m.recipe_id, "press_nails", "and back to nails")
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	sim.cycle_recipe(Vector2i(0, 0))
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	var b := SimWorld.new()
	b.power.free = true
	SaveGame.apply(b, again)
	eq(b.factory.machines[Vector2i(0, 0)].recipe_id, "repair_kit", "the press's recipe is saved")
	check(d["machines"][0]["recipe"] == "press_nails", "(and written in the save)")


func test_old_pete_drops_his_axe() -> void:
	var sim := SimWorld.new()
	var pete := sim.spawn_old_pete()
	eq(pete.type, "old_pete", "Old Pete")
	near(pete.hp, 200.0, "200 hp")
	check(TownPlan.factory_rect().has_point(Vector2(pete.pos.x, pete.pos.z)), "he stands in the factory hall")
	pete.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	eq(sim.bags.size(), 0, "S4: no bag; his body is what you search")
	var cid := SimWorld.CORPSE + str(pete.id)
	check(sim.loot.containers.has(cid), "his corpse is a container")
	var axe: Dictionary = sim.loot.containers[cid]["gear"][0]
	eq(axe["name"], "Pete's Fire Axe", "with his axe")
	eq(axe["rarity"], "gold", "gold")
	eq(axe["base"], "axe", "an axe")
	check(sim.loot.containers[cid]["pos"].distance_to(pete.pos) < 0.01, "where he fell")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"] == "Old Pete is carrying something gold: search the body"),
			"the HUD says Old Pete is carrying something gold")
	sim.player_pos = pete.pos
	eq(sim.search(cid), "", "search the body")
	for i in roundi(sim.loot.search_time() / SimWorld.TICK) + 2:
		sim.step()
	check(sim.loot.containers[cid]["searched"], "searched")
	eq(sim.container_gear(cid).size(), 2, "the axe and deer rifle wait on the body")
	sim.take_all(cid)
	eq(sim.gear.pieces.size(), 2, "the axe (and, since M14, his deer rifle) are in your pockets")
	eq(sim.equip_gear(axe["uid"]), "Equipped Pete's Fire Axe", "equip it")
	eq(sim.gear.weapon_name(), "Pete's Fire Axe", "it's your weapon now")
	check(sim.skills.bonus("melee_damage") >= 0.15, "its damage stat counts")


func test_zombie_drops_are_on_their_bodies() -> void:
	# S4: what a zombie carried is on its corpse (searched with E), no longer in a drop bag.
	var sim := SimWorld.new(8.0, null, 3)
	var drops := 0
	var kills := 400
	for i in kills:
		var z := sim.horde.spawn("shambler", Vector3(i, 0, 50))
		z.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	eq(sim.bags.size(), 0, "no bags on the ground")
	for cid: String in sim.loot.containers:
		if cid.begins_with(SimWorld.CORPSE):
			drops += sim.loot.containers[cid]["gear"].size()
			if drops == 1:
				check(sim.loot.containers[cid]["gear"].size() == 1, "one piece per corpse")
	near(drops / float(kills), 0.10, "about 10% of shamblers carry a piece", 0.04)
	var runs := 0
	for i in kills:
		sim.horde.spawn("runner", Vector3(i, 0, 80)).take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	for cid: String in sim.loot.containers:
		if cid.begins_with(SimWorld.CORPSE) and sim.loot.containers[cid]["pos"].z == 80.0 and not sim.loot.containers[cid]["gear"].is_empty():
			runs += 1
	near(runs / float(kills), 0.20, "about 20% of runners", 0.05)
	var same := SimWorld.new(8.0, null, 3)
	for i in 50:
		same.horde.spawn("shambler", Vector3(i, 0, 50)).take_hit(1000.0, Vector3.ZERO, 0.0)
	same.step()
	var first := 0
	var again := 0
	for cid: String in sim.loot.containers:
		var c: Dictionary = sim.loot.containers[cid]
		if cid.begins_with(SimWorld.CORPSE) and c["pos"].z == 50.0 and c["pos"].x < 50.0 and not c["gear"].is_empty():
			first += 1
	for cid: String in same.loot.containers:
		if cid.begins_with(SimWorld.CORPSE) and not same.loot.containers[cid]["gear"].is_empty():
			again += 1
	eq(again, first, "the same seed carries the same")


func test_searches_turn_up_gear() -> void:
	var sim := SimWorld.new()
	sim.data.gear["containers"]["kitchen"] = 1.0
	sim.loot.add("k", "kitchen", Vector3(1, 0, 0))
	eq(sim.search("k"), "", "search")
	_run(sim, 6.0)
	eq(sim.container_gear("k").size(), 1, "a kitchen with a 100% chance gives a piece")
	check(sim.messages.any(func(m: Dictionary) -> bool: return sim.container_gear("k")[0]["name"] in m["text"]),
			"the find message names it")
	sim.skills.perks["lucky_find"] = 5  # Lucky Find 100%: the gear roll happens twice
	sim.loot.add("k2", "kitchen", Vector3(1, 0, 0))
	sim.search("k2")
	_run(sim, 6.0)
	eq(sim.container_gear("k2").size(), 2, "Lucky Find rolls for gear again")
	var none := SimWorld.new()
	none.loot.add("f", "fridge", Vector3(1, 0, 0))
	none.search("f")
	_run(none, 6.0)
	eq(none.container_gear("f").size(), 0, "fridges hold no gear")


func test_carry_weight_counts_gear_in_your_pockets() -> void:
	var sim := SimWorld.new()
	var kg := sim.carried_kg()
	var jacket := sim.gear.make("jacket", "civilian", "white")
	sim.gear.pieces.append(jacket)
	near(sim.carried_kg(), kg + 1.5, "a jacket in your pockets weighs 1.5 kg")
	sim.gear.equip(jacket["uid"])
	near(sim.carried_kg(), kg, "worn, it doesn't count")
	eq(sim.drop_gear(sim.gear.equipped["weapon"]["uid"]), "Nothing to drop", "you can't drop what you hold")
	sim.gear.unequip("weapon")
	eq(sim.drop_gear(sim.gear.pieces[0]["uid"]), "Dropped Pipe", "drop the pipe")
	eq(sim.bags[0]["gear"][0]["base"], "pipe", "into a bag at your feet")


func test_death_drops_pocket_gear_and_keeps_what_you_wear() -> void:
	var sim := SimWorld.new()
	var spare := sim.gear.make("bat", "civilian", "blue", {"strength": 1.0})
	sim.gear.pieces.append(spare)
	_wear(sim, "hard_hat", {"carry_kg": 5.0})
	sim.player.damage(1000.0)
	eq(sim.bags.size(), 1, "a death bag")
	eq(sim.bags[0]["gear"].size(), 1, "with the bat from your pockets")
	eq(sim.gear.pieces, [], "pockets empty")
	check(sim.gear.equipped.has("head") and sim.gear.equipped.has("weapon"), "the hat and the pipe stay on you")


func test_save_and_load_keep_gear() -> void:
	var sim := SimWorld.new(9.0, null, 4)
	var hat := _wear(sim, "hard_hat", {"carry_kg": 7.0, "fighter_perks": 2.0}, "yellow")
	hat["condition"] = 0.5
	var spare := sim.gear.make("machete", "police", "blue", {"durability": 0.12})
	sim.gear.pieces.append(spare)
	sim.drop_bag(Vector3(3, 0, 3), {"nails": 2}, [sim.gear.make("cap", "civilian", "set", {}, 0.8, "Cap", "night_shift")])
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	check(int(d["version"]) >= 6, "saved as version 6 or later (gear)")
	var b := SimWorld.new(9.0, null, 4)
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.gear.equipped["head"], hat, "the worn hat comes back, rolls and condition")
	eq(b.gear.equipped["weapon"]["base"], "pipe", "the pipe in your hand")
	eq(b.gear.pieces, [spare], "the machete in your pockets")
	eq(b.bags[0]["gear"][0]["set"], "night_shift", "gear in a bag")
	near(b.carry_limit(), sim.carry_limit(), "same carry limit")
	var fresh := b.gear.make("cap", "civilian", "white")
	check(fresh["uid"] > spare["uid"], "new pieces get new uids")


## A version-5 save (written by the M12 game, before gear) loads with the pipe as a white piece in the
## weapon slot and Old Pete in the hall.
func test_version_5_save_loads_with_the_pipe() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v5.json")
	eq(int(d.get("version", 0)), 5, "the fixture is a version-5 save")
	check(not d.has("gear"), "with no gear")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.gear.equipped["weapon"]["base"], "pipe", "the pipe is in the weapon slot")
	eq(sim.gear.equipped["weapon"]["rarity"], "white", "white")
	near(sim.gear.equipped["weapon"]["condition"], 1.0, "mint")
	eq(sim.skills.perks, {"heavy_swing": 1}, "its perk")
	eq(sim.inventory.count("plank"), 12, "its planks")
	eq(sim.bags.size(), 1, "its bag")
	eq(sim.bags[0]["gear"], [], "(with no gear)")
	var petes := sim.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return z.type == "old_pete")
	eq(petes.size(), 1, "Old Pete is in the hall")
	eq(sim.horde.zombies.size(), d["zombies"].size() + 1, "its zombies plus Old Pete")
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	var c := SimWorld.new(8.0, null, int(d["seed"]))
	SaveGame.apply(c, again)
	eq(c.horde.zombies.values().filter(func(z: ZombieBrain) -> bool: return z.type == "old_pete").size(), 1,
			"saved again, he isn't doubled")
