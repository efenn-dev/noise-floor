extends "res://test/base_test.gd"
## M14 guns, sim side: gun numbers from base plus parts, loudness (suppressors, subsonic, Gunsmith),
## hit chance, recoil spread, magazine and reloads, wear, the workbench's recipes and the Gunsmith gate,
## shots heard by zombies, Firearms xp, guns in loot, Old Pete's rifle, and saving.

const TICK := SimWorld.TICK


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A sim holding a white civilian `base` gun, `rounds` standard rounds in pockets, gun in hand and raised.
func _armed(base: String = "pistol", rounds: int = 30) -> SimWorld:
	var sim := SimWorld.new(12.0)
	var gun := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(gun["uid"])
	sim.inventory.add("ammo_standard", rounds)
	sim.swap_hands()
	_run(sim, 1.0)  # raise it
	return sim


func _part(sim: SimWorld, base: String) -> Dictionary:
	var p := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(p)
	return p


func _load_full(sim: SimWorld) -> void:
	sim.reload()
	_run(sim, 3.0)


func test_guns_json_is_valid() -> void:
	var sim := SimWorld.new()
	eq(sim.data.validate(), PackedStringArray(), "every data file still passes validation")
	var d := sim.data
	near(float(d.guns["guns"]["pistol"]["loudness"]), 85.0, "a pistol is 85 loud")
	near(float(d.guns["guns"]["hunting_rifle"]["loudness"]), 95.0, "a rifle is 95 loud")
	check(float(d.guns["guns"]["pistol"]["loudness"]) > float(d.buildables["generator"]["loudness"]),
			"a shot is louder than a generator")
	eq(d.gear["bases"]["pistol"]["slot"], "sidearm", "pistols are sidearms")
	eq(d.gear["bases"]["hunting_rifle"]["slot"], "primary", "rifles are primary weapons")
	eq(d.gear["bases"]["scope"]["slot"], "part", "parts are gear in the part slot")
	check(d.guns["ammo"]["ammo_ap"].get("reserved", false), "armour-piercing is reserved")
	var broken := GameData.load_default()
	broken.gear["bases"]["pistol"]["gun"] = "bazooka"
	check(broken.validate().size() > 0, "a gun base naming an unknown gun is caught")


func test_gun_numbers_are_base_plus_parts() -> void:
	var sim := _armed()
	var gun := sim.gear.gun()
	var base: Dictionary = sim.data.guns["guns"]["pistol"]
	var st := sim.gear.gun_stats(gun)
	near(st["damage"], float(base["damage"]), "bare pistol: base damage")
	eq(st["magazine"], 8, "8 rounds")
	check(not st["suppressed"], "not suppressed")
	for p: String in ["extended_mag", "scope", "padded_stock", "oil_filter_suppressor"]:
		eq(sim.attach_part(_part(sim, p)["uid"]).begins_with("Attached"), true, "attach " + p)
	st = sim.gear.gun_stats(gun)
	eq(st["magazine"], 12, "extended magazine: +50% rounds")
	near(st["range"], float(base["range"]) * 1.6, "scope: +60% accuracy at range")
	near(st["recoil"], float(base["recoil"]) * 0.65, "padded stock: 35% less recoil")
	near(st["loudness"], 65.0, "crude suppressor: 20 quieter")
	check(st["suppressed"], "suppressed")
	var police := sim.gear.make("pistol", "police", "white")
	near(sim.gear.gun_stats(police)["damage"], float(base["damage"]) * 1.25, "a Police pistol hits 25% harder")
	var machined := _part(sim, "machined_suppressor")
	eq(sim.attach_part(machined["uid"]), "Attached Machined suppressor to Pistol", "swap in the machined suppressor")
	near(sim.gear.gun_stats(gun)["loudness"], 55.0, "machined suppressor: 30 quieter")
	check(sim.gear.pieces.any(func(p: Dictionary) -> bool: return p["base"] == "oil_filter_suppressor"),
			"the crude one came back to your pockets")
	eq(sim.detach_part("sight"), "Took off Scope", "take the scope off")
	near(sim.gear.gun_stats(gun)["range"], float(base["range"]), "range back to base")
	var crude: Dictionary = sim.gear.pieces.filter(func(p: Dictionary) -> bool: return p["base"] == "oil_filter_suppressor")[0]
	eq(sim.equip_gear(crude["uid"]), "Attach it to a firearm at a workbench", "a part can't be worn")
	var rolled := sim.gear.make("pistol", "civilian", "blue", {"gun_damage": 0.2, "gun_quiet": 4.0})
	near(sim.gear.gun_stats(rolled)["damage"], float(base["damage"]) * 1.2, "a rolled +20% gun damage counts")
	near(sim.gear.gun_stats(rolled)["loudness"], 81.0, "a rolled 4 quieter shots counts")
	near(sim.skills.bonus("gun_damage"), 0.0, "gun stats on the gun count once (gun_stats), not again in bonus()")


func test_suppressor_subsonic_and_gunsmith_loudness() -> void:
	var sim := _armed()
	near(sim.guns.shot_loudness(), 85.0, "pistol, standard rounds: 85")
	sim.attach_part(_part(sim, "oil_filter_suppressor")["uid"])
	near(sim.guns.shot_loudness(), 65.0, "crude suppressor: 65")
	sim.gear.gun()["ammo"] = "ammo_subsonic"
	near(sim.guns.shot_loudness(), 50.0, "and subsonic rounds: 50")
	near(sim.guns.damage(), float(sim.data.guns["guns"]["pistol"]["damage"]) * 0.75, "subsonic hits 25% softer")
	sim.skills.perks["gunsmith"] = 2
	near(sim.guns.shot_loudness(), 46.0, "Gunsmith 2: 4 quieter on a suppressed shot")
	sim.detach_part("muzzle")
	near(sim.guns.shot_loudness(), 70.0, "but nothing off an unsuppressed one")
	var rifle := _armed("hunting_rifle")
	near(rifle.guns.shot_loudness(), 95.0, "a rifle: 95")
	eq(rifle.guns.shot_kind(), "gunshot_rifle", "its sound")
	rifle.attach_part(_part(rifle, "machined_suppressor")["uid"])
	eq(rifle.guns.shot_kind(), "gunshot_rifle_suppressed", "suppressed sound")


func test_the_ray_is_the_only_roll() -> void:
	# P2: no hit-chance roll after the ray. A shot the world's ray put on a zombie hits, near or far;
	# distance acts through the cone, which covers more ground further out.
	var sim := _armed("pistol", 30)
	_load_full(sim)
	var hits := 0
	for i in 200:
		var t := sim.horde.spawn("shambler", Vector3(0, 0, -40))
		t.hp = 10000.0
		if sim.shoot_zombie(t.id, false)["hit"]:
			hits += 1
	eq(hits, 200, "every shot the ray lands at 40 m hits")
	near(sim.guns.cone_radius(40.0), 4.0 * sim.guns.cone_radius(10.0), "the same cone is 4x as wide at 40 m as at 10 m")
	near(sim.guns.cone_radius(18.0), tan(deg_to_rad(sim.guns.spread_deg())) * 18.0, "the cone's radius at 18 m (about 0.3-0.4 m for a pistol)")
	var dead := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	dead.hp = 0.0
	dead.take_hit(1.0, Vector3.ZERO, 0.0)
	check(not sim.shoot_zombie(dead.id, false)["hit"], "a dead zombie can't be hit")
	check(not sim.shoot_zombie(99999, false)["hit"], "nor one that isn't there")


func test_firearms_and_a_scope_shrink_the_cone_and_recoil_grows_it() -> void:
	var sim := _armed()
	_load_full(sim)
	var rest := sim.guns.spread_deg()
	sim.skills.xp["firearms"] = float(sim.data.skills["levels"][5])
	var trained := sim.guns.spread_deg()
	check(trained < rest, "Firearms 5: a smaller cone than Firearms 0 (%.3f < %.3f)" % [trained, rest])
	near(trained, rest * 0.85, "15% smaller (3% a level)")
	sim.skills.xp["firearms"] = 0.0
	check(not sim.guns.scoped(), "no scope yet")
	sim.attach_part(_part(sim, "scope")["uid"])
	check(sim.guns.scoped(), "scoped")
	near(sim.guns.spread_deg(), rest, "a scope gives no cone bonus from the hip")
	sim.guns.aiming = true
	var scoped := sim.guns.spread_deg()
	near(scoped, rest * 0.5 / 1.6, "ADS halves spread and a scope adds its 1/1.6 range bonus")
	eq(sim.fire(), "", "fires")
	check(sim.guns.spread_deg() > scoped * 1.5, "a shot's recoil grows the aimed scoped cone (%.3f)" % sim.guns.spread_deg())
	_run(sim, 2.0)
	near(sim.guns.spread_deg(), scoped, "and it settles back")
	sim.guns.aiming = false
	var rifle := _armed("hunting_rifle")
	check(rifle.guns.spread_deg() < sim.guns.spread_deg() * 0.6, "a rifle's cone is far tighter than a pistol's")
	rifle.swap_hands()
	near(rifle.guns.spread_deg(), 0.35, "the cone is the gun's, whichever hand")
	check(not rifle.guns.scoped(), "a holstered gun is never scoped")


func test_recoil_spread_grows_and_settles() -> void:
	var sim := _armed()
	_load_full(sim)
	var rest := sim.guns.spread_deg()
	near(rest, float(sim.data.guns["guns"]["pistol"]["spread"]), "at rest: the gun's spread")
	eq(sim.fire(), "", "fires")
	var one := sim.guns.spread_deg()
	check(one > rest, "a shot kicks the spread up (%.2f)" % one)
	_run(sim, 0.3)
	eq(sim.fire(), "", "fires again")
	check(sim.guns.spread_deg() > rest + 1.0, "two quick shots spread more (%.2f)" % sim.guns.spread_deg())
	_run(sim, 2.0)
	near(sim.guns.spread_deg(), rest, "and it settles back")
	sim.attach_part(_part(sim, "padded_stock")["uid"])
	sim.skills.perks["steady_hands"] = 2
	_run(sim, 0.3)
	sim.fire()
	check(sim.guns.spread_deg() - rest < one - rest, "a padded stock and Steady Hands kick less")
	sim.skills.xp["firearms"] = float(sim.data.skills["levels"][10])
	_run(sim, 2.0)
	near(sim.guns.spread_deg(), rest * 0.7, "Firearms 10: 30% tighter")


func test_magazine_reload_and_ammo() -> void:
	var sim := _armed("pistol", 10)
	eq(sim.gear.gun()["loaded"], 0, "a new gun is empty")
	eq(sim.fire(), "Click. Empty (R to reload)", "an empty gun clicks")
	check(sim.reload().begins_with("Reloading"), "R reloads")
	check(sim.fire() != "", "can't fire mid-reload")
	_run(sim, 1.0)
	eq(sim.gear.gun()["loaded"], 0, "still reloading after 1 s")
	_run(sim, 1.0)
	eq(sim.gear.gun()["loaded"], 8, "8 in the magazine")
	eq(sim.inventory.count("ammo_standard"), 2, "taken from your pockets")
	for i in 3:
		eq(sim.fire(), "", "shot %d" % (i + 1))
		_run(sim, 0.3)
	eq(sim.gear.gun()["loaded"], 5, "each shot uses a round")
	sim.reload()
	_run(sim, 2.0)
	eq(sim.gear.gun()["loaded"], 7, "a reload tops up with what you have")
	eq(sim.inventory.count("ammo_standard"), 0, "none left")
	eq(sim.reload(), "No standard rounds (the workbench makes them)", "nothing to reload")
	sim.inventory.add("ammo_subsonic", 5)
	eq(sim.reload(), "Switching to subsonic rounds...", "R switches to the type you have")
	eq(sim.inventory.count("ammo_standard"), 7, "the standard rounds come back")
	_run(sim, 2.0)
	eq(sim.gear.gun()["loaded"], 5, "loaded subsonic")
	eq(sim.gear.gun()["ammo"], "ammo_subsonic", "and it says so")
	sim.skills.perks["quick_hands"] = 3
	near(sim.guns.reload_time(), 1.6 * 0.7, "Quick Hands 3: reloads 30% faster")
	sim.attach_part(_part(sim, "extended_mag")["uid"])
	sim.gear.gun()["loaded"] = 12
	sim.detach_part("magazine")
	eq(sim.gear.gun()["loaded"], 8, "taking the extended magazine off leaves 8")
	eq(sim.inventory.count("ammo_subsonic"), 4, "the other 4 go in your pockets")
	eq(sim.swap_hands(), "Pipe in hand", "Q: back to the pipe")
	eq(sim.fire(), "No firearm in hand (Q)", "no shooting with the pipe out")
	eq(sim.swap_hands(), "Pistol in hand", "Q: the gun again")
	eq(sim.fire(), "Not ready", "it takes a moment to raise")
	_run(sim, 0.4)
	eq(sim.fire(), "", "then it fires")


func test_wear_per_shot() -> void:
	var sim := _armed("pistol", 100)
	var crude := _part(sim, "oil_filter_suppressor")
	sim.attach_part(crude["uid"])
	_load_full(sim)
	for i in 8:
		sim.fire()
		_run(sim, 0.25)
	near(sim.gear.gun()["condition"], 1.0 - 8 * 0.002, "the pistol wears 0.2% a shot")
	near(crude["condition"], 1.0 - 8 * 0.005, "the crude suppressor 0.5% a shot")
	crude["condition"] = 0.252
	sim.reload()
	_run(sim, 2.0)
	sim.fire()
	check(not sim.gear.working(crude), "a worn-out suppressor")
	near(sim.gear.gun_stats(sim.gear.gun())["loudness"], 85.0, "stops working: full loudness again")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].begins_with("Your Oil-filter suppressor is worn out")),
			"the HUD says so")
	var pete := sim.gear.roll_unique(_rng(3), "petes_deer_rifle")
	var m := sim.gear.make("machined_suppressor", "civilian", "white")
	pete["parts"]["muzzle"] = m
	near(sim.gear.gun_stats(pete)["muzzle_wear"], 0.0008 * 0.5, "a threaded barrel halves suppressor wear")


func test_shots_are_heard_at_the_right_distance() -> void:
	var sim := _armed("pistol", 30)
	_load_full(sim)
	sim.player_pos = Vector3.ZERO
	var far := sim.horde.spawn("shambler", Vector3(0, 0, 400))
	far.facing = Vector3(0, 0, 1)  # looking away
	sim.fire()
	sim.step()  # one-offs join the noise field on the next tick
	var shot: Dictionary = sim.noise.recent.back()
	eq(shot["kind"], "gunshot_pistol", "a pistol shot")
	near(shot["loudness"], 85.0, "at 85")
	check(shot["pos"].is_equal_approx(Vector3.ZERO), "where you stand")
	_run(sim, 1.0)
	eq(far.state, ZombieBrain.State.INVESTIGATE, "a zombie 400 m away hears it and comes")
	check(sim.director.infamy > 0.0, "a shot adds to infamy")
	var q := _armed("pistol", 30)
	q.attach_part(_part(q, "oil_filter_suppressor")["uid"])
	q.inventory.add("ammo_subsonic", 10)
	q.gear.gun()["ammo"] = "ammo_subsonic"
	_load_full(q)
	q.player_pos = Vector3.ZERO
	var near_z := q.horde.spawn("shambler", Vector3(0, 0, 25))
	near_z.facing = Vector3(0, 0, 1)
	var out_z := q.horde.spawn("shambler", Vector3(60, 0, 0))
	out_z.facing = Vector3(1, 0, 0)
	q.fire()
	q.step()
	near(q.noise.recent.back()["loudness"], 50.0, "suppressed subsonic: 50")
	_run(q, 1.0)
	eq(near_z.state, ZombieBrain.State.INVESTIGATE, "heard 25 m away (50 - 28 = 22 >= 20)")
	check(out_z.state != ZombieBrain.State.INVESTIGATE, "not 60 m away (50 - 36 = 14 < 20)")


func test_shooting_hurts_and_trains_firearms() -> void:
	var sim := _armed("pistol", 30)
	_load_full(sim)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	var hp := z.hp
	sim.fire()
	near(sim.skills.xp.get("firearms", 0.0), 1.0, "a shot: 1 Firearms xp")
	var r := sim.shoot_zombie(z.id, false)
	check(r["hit"], "a shot the ray put on it hits")
	near(z.hp, hp - float(sim.data.guns["guns"]["pistol"]["damage"]), "for the pistol's damage")
	near(sim.skills.xp["firearms"], 4.0, "a hit: 3 more")
	_run(sim, 0.3)
	sim.fire()
	z.hp = 300.0
	var hp2 := z.hp
	sim.shoot_zombie(z.id, true)
	near(hp2 - z.hp, 2.0 * float(sim.data.guns["guns"]["pistol"]["damage"]), "a headshot doubles")
	z.hp = 50.0
	_run(sim, 0.3)
	sim.fire()
	check(sim.shoot_zombie(z.id, true)["killed"], "a headshot kills a hurt one")
	check(z.is_dead(), "dead")
	check(sim.skills.xp["firearms"] >= 14.0, "a kill: 6 more")


func test_workbench_recipes_and_the_gunsmith_gate() -> void:
	var sim := SimWorld.new(12.0)
	eq(sim.data.buildables["workbench"]["kind"], "workbench", "a workbench piece")
	eq(sim.data.buildables["workbench"]["cost"], {"plank": 6, "nails": 10}, "cheap: planks and nails")
	sim.inventory.give_all({"plank": 20, "nails": 40, "ammo_casing": 30, "scrap_metal": 10, "metal_plate": 10})
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	eq(sim.build.place("workbench", Vector2i(0, 0), 0, sim.inventory), "", "you can build one")
	var at := sim.build.piece_center(sim.build.key_for("workbench", Vector2i(0, 0)))
	check("bench_standard" in sim.bench_recipes() and "bench_subsonic" in sim.bench_recipes(), "ammo recipes at the bench")
	eq(sim.bench_craft("bench_standard", at), "Made 10 Standard rounds", "standard rounds by hand")
	eq(sim.inventory.count("ammo_casing"), 20, "10 casings used")
	eq(sim.bench_craft("bench_subsonic", at), "Needs the Gunsmith perk (Fighter tree, K)", "subsonic needs Gunsmith")
	eq(sim.bench_craft("bench_machined_suppressor", at), "Needs the Gunsmith perk (Fighter tree, K)",
			"so does the machined suppressor")
	eq(sim.bench_craft("bench_crude_suppressor", at), "Made Oil-filter suppressor", "the crude one doesn't")
	sim.skills.perks["gunsmith"] = 1
	eq(sim.bench_craft("bench_subsonic", at), "Made 10 Subsonic rounds", "Gunsmith 1: subsonic")
	eq(sim.bench_craft("bench_machined_suppressor", at), "Made Machined suppressor", "and the machined suppressor")
	sim.inventory.take_all({"ammo_casing": sim.inventory.count("ammo_casing")})
	check(sim.bench_craft("bench_standard", at).begins_with("Needs"), "no casings, no rounds")


func test_press_makes_casings() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	sim.inventory.give_all({"plank": 40, "metal_plate": 40})
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("press", Vector2i(0, 0), BuildGrid.Side.EAST, sim.inventory)
	sim.cycle_recipe(Vector2i(0, 0))
	eq(sim.cycle_recipe(Vector2i(0, 0)), "Press now makes Ammo casings", "R twice: ammo casings")
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	_run(sim, 3.5)
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	check(sim.inventory.count("ammo_casing") >= 10, "a metal plate makes 10 casings")


func test_loot_rolls_guns_parts_and_ammo() -> void:
	var sim := SimWorld.new(12.0)
	var guns := {"pistol": 0, "hunting_rifle": 0}
	var parts := 0
	var police := 0
	var ammo := 0
	var odd := 0
	for i in 2000:
		var out := sim._search_guns({"id": "car_%d" % i, "table": "car_trunk"})
		for p: Dictionary in out["pieces"]:
			if guns.has(p["base"]):
				guns[p["base"]] += 1
				if not p.has("parts") or int(p["loaded"]) > int(sim.gear.gun_stats(p)["magazine"]):
					odd += 1
			else:
				parts += 1
			if p["tier"] == "police":
				police += 1
		ammo += 1 if out["items"].has("ammo_standard") else 0
	eq(odd, 0, "every found gun has part slots and no more rounds than its magazine holds")
	check(guns["pistol"] > 50, "pistols turn up in car trunks (%d in 2000)" % guns["pistol"])
	check(guns["hunting_rifle"] > 5 and guns["hunting_rifle"] < guns["pistol"], "rifles rarer (%d)" % guns["hunting_rifle"])
	check(ammo > 400 and ammo < 600, "ammo in about a quarter of trunks (%d)" % ammo)
	check(police > 0, "some Police-tier finds (%d)" % police)
	var crate_parts := 0
	var crate_guns := 0
	for i in 1000:
		for p: Dictionary in sim._search_guns({"id": "crate_%d" % i, "table": "factory_crate"})["pieces"]:
			if sim.gear.slot_of(p) == "part":
				crate_parts += 1
			elif p["tier"] != "police":
				crate_guns += 1
	check(crate_parts > 100, "parts in factory crates (%d in 1000)" % crate_parts)
	eq(crate_guns, 0, "no civilian guns in factory crates")
	var kitchen := 0
	for i in 1000:
		kitchen += sim._search_guns({"id": "k_%d" % i, "table": "kitchen"})["pieces"].size()
	check(kitchen > 5 and kitchen < 50, "a rare Police find anywhere (%d in 1000 kitchens)" % kitchen)
	eq(sim._search_guns({"id": "car_3", "table": "car_trunk"}), sim._search_guns({"id": "car_3", "table": "car_trunk"}),
			"the same seed finds the same")
	var rng := _rng(9)
	var wrong := 0
	var rolled := 0
	for i in 300:
		var g := sim.gear.roll_gun_piece(rng, "gun")
		for s: String in g["stats"]:
			rolled += 1
			if not sim.data.gear["stats"][s].get("slots", []).has(sim.gear.slot_of(g)):
				wrong += 1
	check(rolled > 50, "guns roll stats (%d)" % rolled)
	eq(wrong, 0, "but only gun stats")
	var guns_in_gear := 0
	for i in 300:
		if sim.gear.slot_of(sim.gear.roll_piece(rng, "car_trunk")) in ["primary", "sidearm", "part"]:
			guns_in_gear += 1
	eq(guns_in_gear, 0, "ordinary gear finds never roll a gun or part")


func test_old_pete_carries_his_deer_rifle() -> void:
	var sim := SimWorld.new()
	var pete := sim.spawn_old_pete()
	pete.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	var cid := SimWorld.CORPSE + str(pete.id)  # S4: he carries it; his body is searched, not a bag
	var rifle: Dictionary = sim.loot.containers[cid]["gear"][1]
	eq(rifle["name"], "Old Pete's Deer Rifle", "his deer rifle is on his body too")
	eq(rifle["rarity"], "gold", "gold")
	eq(sim.loot.containers[cid]["extra"].get("ammo_standard", 0), 10, "with 10 rounds")
	var st := sim.gear.gun_stats(rifle)
	var base := float(sim.data.guns["guns"]["hunting_rifle"]["damage"])
	check(st["damage"] >= base * 1.15 - 0.01 and st["damage"] <= base * 1.30 + 0.01, "+15-30% damage")
	check(st["loudness"] >= 85.0 and st["loudness"] <= 90.0, "5-10 quieter (%d)" % st["loudness"])
	sim.player_pos = pete.pos
	eq(sim.search(cid), "", "search the body")
	for i in roundi(sim.loot.search_time() / SimWorld.TICK) + 2:
		sim.step()
	sim.take_all(cid)
	eq(sim.inventory.count("ammo_standard"), 10, "the rounds are in your pockets")
	sim.equip_gear(rifle["uid"])
	sim.skills.perks["steady_hands"] = 1
	check(sim.skills.effective_rank("steady_hands") >= 2, "+1-2 to Fighter perks counts while it's equipped")


func test_save_keeps_guns_parts_and_ammo() -> void:
	var a := _armed("hunting_rifle", 13)
	a.attach_part(_part(a, "scope")["uid"])
	a.attach_part(_part(a, "oil_filter_suppressor")["uid"])
	_load_full(a)
	a.fire()
	_part(a, "extended_mag")
	var spare := a.gear.make("pistol", "police", "blue", {"gun_damage": 0.1})
	a.gear.pieces.append(spare)
	a.inventory.add("ammo_subsonic", 4)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(d["version"]), SaveGame.VERSION, "the current version (8 when guns came in)")
	var b := SimWorld.new()
	eq(SaveGame.apply(b, d), "", "loads")
	var gun := b.gear.gun()
	eq(gun["name"], "Hunting rifle", "the rifle is in the primary slot")
	eq(gun["loaded"], 4, "4 rounds still in it")
	eq(gun["ammo"], "ammo_standard", "standard")
	eq(gun["parts"].keys().size(), 2, "both parts attached")
	near(gun["parts"]["muzzle"]["condition"], a.gear.gun()["parts"]["muzzle"]["condition"], "suppressor wear kept")
	near(b.gear.gun_stats(gun)["loudness"], 75.0, "still suppressed")
	eq(b.guns.hands, "primary", "still in your hands")
	eq(b.inventory.count("ammo_standard"), 8, "standard rounds in pockets")
	eq(b.inventory.count("ammo_subsonic"), 4, "subsonic too")
	eq(b.gear.pieces.size(), 2, "the spare pistol and the magazine in your pockets")
	var p2: Dictionary = b.gear.find(spare["uid"])
	near(b.gear.gun_stats(p2)["damage"], float(b.data.guns["guns"]["pistol"]["damage"]) * 1.25 * 1.1, "its rolls kept")
	eq(p2["loaded"], 0, "an empty gun stays empty")


func test_version_7_save_loads_with_an_empty_gun_slot() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v7.json")
	eq(int(d.get("version", 0)), 7, "the fixture is a version-7 save")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	check(sim.gear.gun().is_empty(), "no gun")
	eq(sim.guns.hands, "melee", "the pipe in hand")
	eq(sim.gear.weapon_name(), "Pipe", "your pipe")
	eq(sim.swap_hands(), "No firearm equipped (Tab)", "Q with no firearm says so")
	eq(sim.build.pieces.size(), d["pieces"].size() - 2, "every piece, once (less the two walls of the hall's north doorway, opened by M17a)")
	var again: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(again["version"]), SaveGame.VERSION, "saved again as the current version")
