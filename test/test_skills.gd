extends "res://test/base_test.gd"
## M12: the ten skills level by doing, each with an effect you feel; perk points every 3 levels;
## three perk trees spent through Skills.spend and read by the rules through Skills.bonus.

const TICK := SimWorld.TICK
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _xp(sim: SimWorld, skill: String, action: String) -> float:
	return float(sim.data.skills["skills"][skill]["xp"][action])


## Sets a skill straight to a level (the xp that level needs).
func _set_level(sim: SimWorld, skill: String, lv: int) -> void:
	sim.skills.xp[skill] = float(sim.data.skills["levels"][lv])


func _said(sim: SimWorld, text: String) -> bool:
	return sim.messages.any(func(m: Dictionary) -> bool: return m["text"] == text)


# --- Data and levels -----------------------------------------------------------

func test_all_skills_in_data() -> void:
	var sim := SimWorld.new(10.0)
	# V10: Melee became Blunt, Blades and Axe, plus Maintenance.
	eq(sim.skills.ids(), ["strength", "fitness", "building", "mechanics", "scavenging", "sneaking", "blunt", "blades",
			"axe", "maintenance", "firearms", "first_aid", "farming"], "the thirteen skills, in the screen's order")
	eq(sim.data.validate(), PackedStringArray(), "skills.json passes validation")
	check(not sim.skills.is_disabled("firearms"), "Firearms works since M14")
	check(not sim.data.skills["skills"]["firearms"]["xp"].is_empty(), "and shots give Firearms xp")
	for t: String in sim.data.skills["trees"]:
		eq(sim.data.skills["trees"][t]["perks"].size(), 6 if t == "fighter" else 3,
				"three perks in %s (Fighter has three gun perks since M14)" % t)


func test_level_thresholds() -> void:
	var sim := SimWorld.new(10.0)
	var levels: Array = sim.data.skills["levels"]
	eq(sim.skills.level("strength"), 0, "everything starts at 0")
	sim.skills.xp["strength"] = float(levels[1]) - 0.5
	eq(sim.skills.level("strength"), 0, "just short of level 1")
	sim.skills.xp["strength"] = float(levels[1])
	eq(sim.skills.level("strength"), 1, "level 1 at its threshold")
	sim.skills.xp["strength"] = float(levels[5]) + 1.0
	eq(sim.skills.level("strength"), 5, "level 5")
	eq(sim.skills.progress("strength"), [1.0, float(levels[6]) - float(levels[5])], "1 xp into level 5")
	sim.skills.xp["strength"] = 99999.0
	eq(sim.skills.level("strength"), 10, "tops out at 10")
	eq(sim.skills.progress("strength"), [0, 0], "no bar past the top")


# --- XP per action ---------------------------------------------------------------

func test_swinging_and_hitting_train_strength_and_blunt() -> void:
	var sim := SimWorld.new(10.0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	check(sim.swing(), "a swing")
	near(sim.skills.xp["strength"], _xp(sim, "strength", "swing"), "a swing trains Strength")
	check(not sim.swing(), "not ready again at once")
	near(sim.skills.xp["strength"], _xp(sim, "strength", "swing"), "and a swing that didn't happen doesn't")
	sim.hit_zombie(z.id, false)
	near(sim.skills.xp["blunt"], _xp(sim, "blunt", "hit"), "a hit with the pipe trains Blunt")
	check(sim.hit_zombie(z.id, true), "the head hit kills it")
	near(sim.skills.xp["blunt"], 2.0 * _xp(sim, "blunt", "hit") + _xp(sim, "blunt", "kill"), "a kill is worth more")


func test_heavy_loads_train_strength() -> void:
	var sim := SimWorld.new(10.0)
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	eq(sim.skills.xp.get("strength", 0.0), 0.0, "walking light teaches nothing")
	sim.inventory.add("plank", 100)  # well over half the 20 kg limit
	check(sim.carry_ratio() > 0.5, "carrying over half the limit")
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	sim.make_noise(Vector3.ZERO, "footstep_sprint")
	near(sim.skills.xp["strength"], 2.0 * _xp(sim, "strength", "heavy_step"), "each heavy step trains Strength")


func test_sprinting_trains_fitness() -> void:
	var sim := SimWorld.new(10.0)
	sim.player.sprinting = true
	_run(sim, 2.0)
	near(sim.skills.xp["fitness"], 2.0 * _xp(sim, "fitness", "sprint_second"), "xp per second of sprinting", 0.01)
	sim.player.sprinting = false
	_run(sim, 2.0)
	near(sim.skills.xp["fitness"], 2.0 * _xp(sim, "fitness", "sprint_second"), "none while walking", 0.01)


func test_building_and_repairing_train_building() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.give_all({"plank": 100, "nails": 100})
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	near(sim.skills.xp["building"], 2.0 * _xp(sim, "building", "place"), "each piece placed")
	sim.stats.muted = true
	sim.build.place("foundation", Vector2i(1, 0), N, sim.inventory)
	near(sim.skills.xp["building"], 2.0 * _xp(sim, "building", "place"), "not pieces the game lays itself")
	sim.stats.muted = false
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	sim.build.damage(wall, 100)
	sim.player_pos = sim.build.piece_center(wall)
	eq(sim.repair(wall), "", "repaired")
	near(sim.skills.xp["building"], 2.0 * _xp(sim, "building", "place") + _xp(sim, "building", "repair"), "repairs train Building")
	near(sim.skills.xp["mechanics"], _xp(sim, "mechanics", "repair"), "and still Mechanics")


func test_searching_trains_scavenging() -> void:
	var sim := SimWorld.new(10.0)
	sim.loot.add("house_0_e", "kitchen", Vector3(2, 0.8, 0))
	eq(sim.search("house_0_e"), "", "search started")
	_run(sim, 1.0)
	eq(sim.skills.xp.get("scavenging", 0.0), 0.0, "nothing until it's done")
	_run(sim, float(sim.data.survival["search_time"]))
	near(sim.skills.xp["scavenging"], _xp(sim, "scavenging", "search"), "xp per search")


func test_sneaking_near_unaware_zombies_trains_sneaking() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_sneaking = true
	_run(sim, 1.0)
	eq(sim.skills.xp.get("sneaking", 0.0), 0.0, "no zombie near: nothing to sneak past")
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -10))
	z.los_clear = false
	_run(sim, 1.0)
	near(sim.skills.xp["sneaking"], _xp(sim, "sneaking", "sneak_second"), "a second crouched within 15 m", 0.01)
	sim.player_sneaking = false
	_run(sim, 1.0)
	near(sim.skills.xp["sneaking"], _xp(sim, "sneaking", "sneak_second"), "not while standing up", 0.01)
	sim.player_sneaking = true
	z.state = ZombieBrain.State.CHASE
	var before: float = sim.skills.xp["sneaking"]
	sim.step()
	near(sim.skills.xp["sneaking"], before, "nothing once it has noticed you")


func test_bandages_train_first_aid() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.add("bandage", 2)
	sim.player.bleeding = true
	eq(sim.use_bandage(), "Bandaged", "bandaged")
	near(sim.skills.xp["first_aid"], _xp(sim, "first_aid", "bandage"), "xp per bandage")
	sim.use_bandage()
	near(sim.skills.xp["first_aid"], _xp(sim, "first_aid", "bandage"), "not for a bandage you didn't need")


func _farm(sim: SimWorld) -> Factory.Machine:
	sim.inventory.give_all({"plank": 100, "nails": 100})
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("planter", Vector2i(0, 0), E, sim.inventory)
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 0)]
	m.input = {"seeds": 1, "dirty_water": 1}
	return m


func test_harvesting_trains_farming() -> void:
	var sim := SimWorld.new(10.0)
	var m := _farm(sim)
	sim.machine_interact(Vector2i(0, 0), sim.player_pos)
	eq(sim.skills.xp.get("farming", 0.0), 0.0, "nothing to take yet")
	_run(sim, float(sim.data.recipes["grow_vegetables"]["time"]) + 0.1)
	eq(m.crafted, 1, "it grew")
	var moved := sim.machine_interact(Vector2i(0, 0), sim.player_pos)
	eq(moved["took"], {"vegetable": 3}, "took the vegetables")
	near(sim.skills.xp["farming"], _xp(sim, "farming", "harvest"), "a harvest trains Farming")


func test_level_up_and_perk_point_messages() -> void:
	var sim := SimWorld.new(10.0)
	_set_level(sim, "strength", 2)
	_set_level(sim, "blunt", 0)
	sim.skills.xp["blunt"] = float(sim.data.skills["levels"][1]) - 0.5
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	sim.hit_zombie(z.id, false)
	check(_said(sim, "Blunt 1"), "says the new level")
	check(_said(sim, "Perk point earned: K to spend"), "3 levels in all: says so")
	eq(sim.skills.perk_points, 1, "and the point is there")


# --- Perk points -------------------------------------------------------------------

func test_a_perk_point_every_three_levels() -> void:
	var sim := SimWorld.new(10.0)
	var lv1 := float(sim.data.skills["levels"][1])
	eq(sim.skills.perk_points, 0, "none to start")
	for s: String in ["strength", "fitness"]:
		sim.skills.xp[s] = lv1 - 0.001
		sim.skills.practice(s, "swing" if s == "strength" else "sprint_second")
	eq(sim.skills.total_levels(), 2, "two levels")
	eq(sim.skills.perk_points, 0, "no point yet")
	sim.skills.xp["building"] = lv1 - 0.001
	sim.skills.practice("building", "place")
	eq(sim.skills.perk_points, 1, "the third level earns one")
	sim.skills.xp["building"] = float(sim.data.skills["levels"][4]) - 0.001
	sim.skills.practice("building", "place")
	eq(sim.skills.total_levels(), 6, "six levels")
	eq(sim.skills.perk_points, 2, "two points at six (a jump of three levels at once still counts)")


func test_spending_ranks_cap_and_no_points() -> void:
	var sim := SimWorld.new(10.0)
	check(sim.skills.spend("soft_step") != "", "no points, no spend")
	eq(sim.skills.rank("soft_step"), 0, "still rank 0")
	sim.skills.perk_points = 7
	for i in 5:
		eq(sim.skills.spend("soft_step"), "", "rank %d" % (i + 1))
	eq(sim.skills.rank("soft_step"), 5, "rank 5")
	check(sim.skills.spend("soft_step") != "", "can't go past rank 5")
	eq(sim.skills.perk_points, 2, "the refused point is kept")
	check(sim.skills.spend("nonsense") != "", "no such perk")
	eq(sim.skills.spend("heavy_swing"), "", "another tree")
	eq(sim.skills.tree_points("ghost"), 5, "5 points in Ghost")
	eq(sim.skills.tree_points("fighter"), 1, "1 in Fighter")


# --- Each skill's effect at level 0 and level 5 -----------------------------------

func test_strength_carry_limit() -> void:
	var sim := SimWorld.new(10.0)
	near(sim.carry_limit(), 20.0, "20 kg at Strength 0")
	_set_level(sim, "strength", 5)
	near(sim.carry_limit(), 35.0, "35 kg at Strength 5")
	_set_level(sim, "strength", 10)
	near(sim.carry_limit(), 50.0, "50 kg at Strength 10")
	sim.inventory.add("hiking_pack", 1)
	sim.equip_bag("hiking_pack")
	near(sim.carry_limit(), 50.0 + sim.data.item_value("hiking_pack", "bag"), "a worn bag still adds on top")


func test_melee_damage_and_knockback() -> void:
	var sim := SimWorld.new(10.0)
	var base: float = sim.weapon_stats()["damage"]
	near(sim.melee_damage(), base, "the pipe's damage at 0")
	_set_level(sim, "strength", 5)
	near(sim.melee_damage(), base * 1.25, "Strength 5: +25%")
	_set_level(sim, "blunt", 5)
	near(sim.melee_damage(), base * 1.55, "and Blunt 5 with the pipe: +30% more (they stack)")
	sim.skills.perks["heavy_swing"] = 2
	near(sim.melee_damage(), base * 1.75, "Heavy Swing 2: +20% more")
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	sim.hit_zombie(z.id, false)
	near(z.hp, float(z.stats["hp"]) - base * 1.75, "the zombie takes it")
	near(z.knockback.length(), float(sim.weapon_stats()["knockback"]) * 1.25, "Strength 5 knocks back 25% further", 0.01)


func test_fitness_stamina_regen() -> void:
	var regen := []
	for lv in [0, 5]:
		var sim := SimWorld.new(10.0)
		_set_level(sim, "fitness", lv)
		sim.player.stamina = 20.0
		_run(sim, 2.0)  # 1 s delay, then 1 s of regen
		regen.append(sim.player.stamina - 20.0)
	near(regen[1] / regen[0], 1.25, "Fitness 5: stamina comes back 25% faster", 0.03)
	var sim := SimWorld.new(10.0)
	sim.skills.perks["second_wind"] = 1
	sim.player.stamina = 20.0
	_run(sim, 2.0)
	near((sim.player.stamina - 20.0) / regen[0], 1.1, "Second Wind 1: 10% faster", 0.03)


func _damaged_wall(sim: SimWorld) -> String:
	sim.inventory.give_all({"plank": 200, "nails": 200})
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("wall", Vector2i(0, 0), N, sim.inventory)
	var wall := sim.build.key_for("wall", Vector2i(0, 0), N)
	sim.build.pieces[wall]["hp"] = 1  # almost wrecked: nearly the full cost to repair
	return wall


func test_building_cheaper_repairs() -> void:
	var sim := SimWorld.new(10.0)
	var wall := _damaged_wall(sim)
	var full := sim.repair_cost(wall)
	var cost: Dictionary = sim.data.buildables["wall"]["cost"]
	eq(full, cost, "Building 0: the full cost for a nearly wrecked wall")
	_set_level(sim, "building", 5)
	var cheap := sim.repair_cost(wall)
	for item: String in cost:
		eq(cheap[item], maxi(1, roundi(cost[item] * 0.75)), "Building 5: 25%% off %s" % item)
	_set_level(sim, "building", 10)
	for item: String in cost:
		eq(sim.repair_cost(wall)[item], maxi(1, roundi(cost[item] * 0.5)), "never below half (%s)" % item)
	_set_level(sim, "building", 5)
	var before := sim.inventory.count("plank")
	sim.player_pos = sim.build.piece_center(wall)
	eq(sim.repair(wall), "", "repaired")
	eq(before - sim.inventory.count("plank"), int(cheap["plank"]), "and it charged the cheaper price")


func test_scavenging_search_time_and_quick_fingers() -> void:
	var sim := SimWorld.new(10.0)
	var base := float(sim.data.survival["search_time"])
	near(sim.loot.search_time(), base, "Scavenging 0: the full time")
	_set_level(sim, "scavenging", 5)
	near(sim.loot.search_time(), base * 0.75, "Scavenging 5: 25% quicker")
	sim.skills.perks["quick_fingers"] = 2
	near(sim.loot.search_time(), base * 0.55, "plus Quick Fingers 2: 20% more")
	_set_level(sim, "scavenging", 10)
	sim.skills.perks["quick_fingers"] = 5
	near(sim.loot.search_time(), base * float(sim.data.skills["search_time_min"]), "never under the floor")
	_set_level(sim, "scavenging", 5)
	sim.skills.perks.erase("quick_fingers")
	sim.loot.add("house_0_e", "kitchen", Vector3(2, 0.8, 0))
	sim.search("house_0_e")
	_run(sim, base * 0.75 + 0.1)
	check(sim.loot.containers["house_0_e"]["searched"], "the search really finishes sooner")


func test_sneaking_and_soft_step_footsteps() -> void:
	var sim := SimWorld.new(10.0)
	var walk := float(sim.data.noise["sounds"]["footstep_walk"])
	var sprint := float(sim.data.noise["sounds"]["footstep_sprint"])
	near(sim.noise_loudness("footstep_walk"), walk, "Sneaking 0: the usual walking step")
	_set_level(sim, "sneaking", 5)
	near(sim.noise_loudness("footstep_walk"), walk - 5.0, "Sneaking 5: 5 quieter")
	near(sim.noise_loudness("footstep_sprint"), sprint, "sprinting isn't helped by Sneaking")
	sim.skills.perks["soft_step"] = 2
	near(sim.noise_loudness("footstep_walk"), walk - 11.0, "Soft Step 2: 6 more")
	near(sim.noise_loudness("footstep_sprint"), sprint - 6.0, "and sprinting 6 quieter")
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	sim.step()
	near(sim.noise.recent[-1]["loudness"], walk - 11.0, "what zombies hear is the quieter step")


func test_first_aid_bandage_heal_and_bleed_chance() -> void:
	var heal := []
	for lv in [0, 5]:
		var sim := SimWorld.new(10.0)
		_set_level(sim, "first_aid", lv)
		sim.player.health = 50.0
		sim.player.bleeding = true
		sim.inventory.add("bandage", 1)
		sim.use_bandage()
		heal.append(sim.player.health - 50.0)
		near(sim.bleed_chance(), float(sim.data.survival["bleed_chance"]) - 0.02 * lv, "bleed chance at First Aid %d" % lv)
	near(heal[0], 0.0, "First Aid 0: a bandage only stops the bleeding")
	near(heal[1], 25.0, "First Aid 5: and heals 25")


func test_farming_planter_yield() -> void:
	var got := []
	for lv in [0, 3, 5, 6]:
		var sim := SimWorld.new(10.0)
		_set_level(sim, "farming", lv)
		_farm(sim)
		_run(sim, float(sim.data.recipes["grow_vegetables"]["time"]) + 0.1)
		got.append(sim.machine_interact(Vector2i(0, 0), sim.player_pos)["took"].get("vegetable", 0))
	eq(got, [3, 4, 4, 5], "one extra vegetable per three Farming levels")


func test_mechanics_unchanged() -> void:
	var sim := SimWorld.new(10.0)
	eq(sim.data.skills["skills"]["mechanics"]["effects"], {}, "Mechanics has no bonus() effect: hotwiring reads its level")
	eq(int(sim.data.skills["hotwire_level"]), 2, "hotwiring still needs Mechanics 2")


# --- Perk effects through the same rules ---------------------------------------

func test_engineer_perks_belts_and_machines() -> void:
	var sim := SimWorld.new(10.0)
	near(sim.factory.belt_speed(), Factory.BELT_SPEED, "belts at their usual speed")
	sim.skills.perks["fast_lines"] = 3
	near(sim.factory.belt_speed(), Factory.BELT_SPEED * 1.3, "Fast Lines 3: +30%")
	var times := []
	for r in [0, 4]:
		var s := SimWorld.new(10.0)
		s.power.free = true
		s.skills.perks["tuned_machines"] = r
		s.inventory.give_all({"plank": 100, "nails": 100, "scrap_metal": 40})
		s.build.place("foundation", Vector2i(0, 0), N, s.inventory)
		s.build.place("smelter", Vector2i(0, 0), E, s.inventory)
		var m: Factory.Machine = s.factory.machines[Vector2i(0, 0)]
		m.input = {"scrap_metal": 20}
		var ticks := 0
		while m.crafted == 0 and ticks < 2000:
			s.step()
			ticks += 1
		times.append(ticks)
	near(float(times[0]) / float(times[1]), 1.2, "Tuned Machines 4: crafts 20% faster", 0.03)


func test_dampened_gears_and_its_ghost_synergy() -> void:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.inventory.give_all({"plank": 100, "nails": 100, "scrap_metal": 40, "gas_can": 2, "metal_plate": 20})
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory)
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 0)]
	var loud := float(sim.data.buildables["smelter"]["loudness"])
	near(sim.noise.machine_loudness(m), loud, "a smelter at its usual loudness")
	sim.skills.perks["dampened_gears"] = 2
	near(sim.noise.machine_loudness(m), loud - 4.0, "Dampened Gears 2: 4 quieter")
	sim.skills.perks["soft_step"] = 2
	near(sim.noise.machine_loudness(m), loud - 4.0, "2 points in Ghost: no synergy yet")
	sim.skills.perks["quick_fingers"] = 1
	near(sim.noise.machine_loudness(m), loud - 5.0, "3 points in Ghost: 1 more")
	sim.skills.perks["lucky_find"] = 3
	near(sim.noise.machine_loudness(m), loud - 6.0, "6 points in Ghost: 2 more")
	var s2 := SimWorld.new(10.0)
	s2.skills.perks["soft_step"] = 5
	eq(s2.skills.bonus("machine_quiet"), 0.0, "the synergy needs a rank in Dampened Gears itself")
	sim.build.place("foundation", Vector2i(2, 0), N, sim.inventory)
	sim.build.place("generator", Vector2i(2, 0), E, sim.inventory)
	var gen := sim.build.key_for("generator", Vector2i(2, 0))
	sim.power.load_fuel(gen, sim.inventory)
	sim.power.generators[gen]["running"] = true
	var src: Array = sim.power.noise_sources()
	near(src[0]["loudness"], float(sim.data.buildables["generator"]["loudness"]) - 6.0, "generators get quieter too")


func test_thick_skin_cuts_zombie_damage() -> void:
	var hurt := []
	for r in [0, 4]:
		var sim := SimWorld.new(10.0)
		sim.skills.perks["thick_skin"] = r
		sim.player_pos = Vector3(0, 0, -1)
		var z := sim.horde.spawn("shambler", Vector3.ZERO)
		z.los_clear = true
		var ticks := 0
		while sim.player.health >= 100.0 and ticks < 100:  # the first hit (any bleeding starts next tick)
			sim.step()
			ticks += 1
		hurt.append(100.0 - sim.player.health)
	near(hurt[1] / hurt[0], 0.8, "Thick Skin 4: zombies hurt 20% less", 0.01)


func test_lucky_find_uses_the_seeded_rng() -> void:
	var counts := []
	for r in [0, 5, 5]:
		var sim := SimWorld.new(10.0, null, 7)
		sim.skills.perks["lucky_find"] = r
		sim.loot.add("house_3_w", "kitchen", Vector3(2, 0.8, 0))
		sim.search("house_3_w")
		_run(sim, float(sim.data.survival["search_time"]) + 0.1)
		var n := 0
		for item: String in sim.loot.inventory("house_3_w").items():
			n += sim.loot.inventory("house_3_w").count(item)
		counts.append(n)
	eq(counts[0] + 1, counts[1], "Lucky Find 5 (100%): exactly one more item")
	eq(counts[1], counts[2], "the same world seed gives the same lucky find")
	var sim := SimWorld.new(10.0, null, 7)
	sim.loot.add("house_3_w", "kitchen", Vector3(2, 0.8, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, "house_3_w"])
	var base := Loot.roll(sim.data.loot["kitchen"], rng)
	sim.search("house_3_w")
	_run(sim, float(sim.data.survival["search_time"]) + 0.1)
	for item: String in base:
		check(sim.loot.inventory("house_3_w").count(item) >= base[item], "Lucky Find 0 finds the plain roll (%s)" % item)


# --- Kept through death and saves ---------------------------------------------------

func test_death_keeps_skills_and_perks() -> void:
	var sim := SimWorld.new(10.0)
	_set_level(sim, "strength", 4)
	sim.skills.perk_points = 2
	sim.skills.perks["thick_skin"] = 1
	var xp: Dictionary = sim.skills.xp.duplicate()
	sim.player.damage(1000.0, "shambler")
	check(sim.player.dead, "dead")
	_run(sim, PlayerStats.RESPAWN_TIME + 0.1)
	check(not sim.player.dead, "respawned")
	eq(sim.skills.xp, xp, "skills kept")
	eq(sim.skills.perks, {"thick_skin": 1}, "perks kept")
	eq(sim.skills.perk_points, 2, "unspent points kept")
	near(sim.carry_limit(), 32.0, "and Strength still carries")


func test_save_and_load_xp_perks_and_points() -> void:
	var a := SimWorld.new(10.0, null, 5)
	_set_level(a, "farming", 6)
	a.skills.xp["sneaking"] = 41.5
	a.skills.perks = {"soft_step": 2, "fast_lines": 1}
	a.skills.perk_points = 3
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(d["version"]), SaveGame.VERSION, "saved as the current version")
	var b := SimWorld.new(10.0, null, 5)
	eq(SaveGame.apply(b, d), "", "loads")
	near(b.skills.xp["sneaking"], 41.5, "xp back")
	eq(b.skills.level("farming"), 6, "levels back")
	eq(b.skills.perks, {"soft_step": 2, "fast_lines": 1}, "perks back")
	eq(b.skills.perk_points, 3, "points back")
	near(b.noise_loudness("footstep_sprint"), float(b.data.noise["sounds"]["footstep_sprint"]) - 6.0, "and they work")
