extends "res://test/base_test.gd"
## RunStats: what a play session leaves in the session log (deaths and their causes, builds, heat,
## loudest sounds, the first-five-minutes timeline), recorded by SimWorld where things happen.

const TICK := SimWorld.TICK


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _run_until_dead(sim: SimWorld, max_seconds: float) -> void:
	for i in roundi(max_seconds / TICK):
		sim.step()
		if sim.player.dead:
			return


func test_death_by_a_zombie() -> void:
	var sim := SimWorld.new(10.0)
	sim.player_pos = Vector3(0, 0, -1)
	sim.player.health = 5.0
	var z := sim.horde.spawn("shambler", Vector3.ZERO)
	z.los_clear = true
	_run_until_dead(sim, 3.0)
	check(sim.player.dead, "the zombie killed the player")
	eq(sim.stats.deaths.size(), 1, "one death recorded")
	eq(sim.stats.deaths[0]["cause"], "shambler", "cause: the zombie's type")
	check(String(sim.stats.deaths[0]["when"]).begins_with("day 1 10:"), "with the game time (%s)" % sim.stats.deaths[0]["when"])
	check("  1. at 0:00 real (day 1 10:0" in "\n".join(sim.stats.summary_lines()), "listed in the summary")
	check("killed by a shambler" in "\n".join(sim.stats.summary_lines()), "in plain words")


func test_death_by_starving_thirst_and_bleeding() -> void:
	for cause: String in ["starvation", "dehydration", "bleeding"]:
		var sim := SimWorld.new(10.0)
		sim.player.health = 0.3
		match cause:
			"starvation":
				sim.player.food = 0.0
			"dehydration":
				sim.player.water = 0.0
			"bleeding":
				sim.player.bleeding = true
		_run_until_dead(sim, 5.0)
		check(sim.player.dead, "%s kills" % cause)
		eq(sim.stats.deaths.size(), 1, "%s: one death" % cause)
		eq(sim.stats.deaths[0]["cause"] if not sim.stats.deaths.is_empty() else "", cause, "cause recorded")
	var sim := SimWorld.new(10.0)
	sim.player.damage(500.0)
	eq(sim.stats.deaths[0]["cause"], "unknown", "damage with no source is 'unknown'")
	eq(RunStats.cause_text("starvation"), "starvation", "plain causes stay as they are")


func test_built_by_kind_not_counting_the_start_stash() -> void:
	var sim := SimWorld.new(10.0)
	check(sim.place_start_stash(Vector2i(1, 3)) != "", "start stash placed")
	eq(sim.stats.built, {}, "the game's own stash isn't counted")
	sim.give_debug_kit()
	var S := BuildGrid.Side
	eq(sim.build.place("foundation", Vector2i(0, 0), S.NORTH, sim.inventory), "", "a floor")
	eq(sim.build.place("wall", Vector2i(0, 0), S.NORTH, sim.inventory), "", "a wall")
	eq(sim.build.place("wall", Vector2i(0, 0), S.WEST, sim.inventory), "", "another wall")
	eq(sim.build.place("smelter", Vector2i(0, 0), S.EAST, sim.inventory), "", "a smelter")
	eq(sim.stats.built, {"foundation": 1, "wall": 2, "smelter": 1}, "counted by kind")
	check("Built 4 pieces: 1 foundation, 2 wall, 1 smelter." in sim.stats.summary_lines(), "summary line")
	eq(sim.stats.timeline[0][1], "built a foundation", "the timeline has the first build")
	sim.stats.muted = true
	eq(sim.build.place("foundation", Vector2i(3, 0), S.NORTH, sim.inventory), "", "a floor while muted")
	eq(sim.stats.built.get("foundation", 0), 1, "isn't counted (loading a save, demo bases)")


func test_timeline_is_the_first_five_minutes() -> void:
	var sim := SimWorld.new(10.0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	sim.stats.add_real_time(12.0)
	sim.hit_zombie(z.id, false)
	sim.hit_zombie(z.id, false)
	eq(sim.stats.timeline.size(), 1, "the same action twice in a row is one line")
	eq(sim.stats.timeline[0], [12.0, "hit a zombie", 2], "stamped with real time, counted")
	check("  0:12 hit a zombie x2" in sim.stats.summary_lines(), "shown as '0:12 hit a zombie x2'")
	sim.hit_zombie(z.id, true)
	eq(sim.stats.kills, 1, "a kill")
	eq(sim.stats.timeline[-1][1], "killed a shambler", "and a line for it")
	sim.stats.add_real_time(RunStats.TIMELINE_SECONDS)
	var lines := sim.stats.timeline.size()
	var z2 := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	sim.hit_zombie(z2.id, true)
	sim.hit_zombie(z2.id, true)
	eq(sim.stats.timeline.size(), lines, "nothing added after five real minutes")
	eq(sim.stats.kills, 2, "but kills still count")
	var stats := RunStats.new()
	for i in RunStats.TIMELINE_MAX + 5:
		stats.note("thing %d" % i)
	eq(stats.timeline.size(), RunStats.TIMELINE_MAX, "the timeline stays short")
	check(stats.summary_lines().size() < 37, "summary fits under 40 lines with a header (%d)" % stats.summary_lines().size())


func test_peak_heat_and_when() -> void:
	var sim := SimWorld.new(10.0)
	sim.director.heat = 50.0
	_run(sim, 0.1)
	near(sim.stats.peak_heat, 50.0, "peak heat recorded", 1.0)
	eq(sim.stats.peak_heat_when, "day 1 10:00", "and the game time it peaked")
	sim.director.heat = 20.0
	_run(sim, 0.1)
	near(sim.stats.peak_heat, 50.0, "a lower heat doesn't replace it", 1.0)
	check("Director heat peaked at 50 (day 1 10:00). Waves sent: 0." in sim.stats.summary_lines(), "summary line")


func test_loudest_sounds() -> void:
	var sim := SimWorld.new(10.0)
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	_run(sim, 0.1)
	eq(sim.stats.loudest_sound.get("kind", ""), "footstep_walk", "the first sound is the loudest so far")
	sim.noise.emit(Vector3.ZERO, 99.0, "test_bang")
	sim.make_noise(Vector3.ZERO, "footstep_walk")
	_run(sim, 0.1)
	eq(sim.stats.loudest_sound.get("kind", ""), "test_bang", "a louder one replaces it")
	near(float(sim.stats.loudest_sound.get("loudness", 0.0)), 99.0, "with its loudness")
	sim.power.free = true
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), BuildGrid.Side.EAST, sim.inventory)
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	_run(sim, 1.0)
	eq(sim.stats.loudest_continuous.get("kind", ""), "smelter", "a working smelter is the loudest machine")
	var line := ""
	for l: String in sim.stats.summary_lines():
		if l.begins_with("Loudest machine"):
			line = l
	check(line.begins_with("Loudest machine or engine: smelter, "), "summary line (%s)" % line)


# --- P3: gear, skills, perks, guns, the base while you were away, houses -----------------------------

func test_p3_gear_skills_and_perks() -> void:
	var sim := SimWorld.new(10.0)
	sim.stats.note_gear("white")
	sim.stats.note_gear("white")
	sim.stats.note_gear("gold")
	var text := "\n".join(sim.stats.summary_lines())
	check("Gear found: 2 white, 1 gold." in text, "gear found by rarity")
	check("Wearing at the end: nothing." in text, "nothing worn listed until the log fills it in")
	# Levels and perk points come from practice; three levels earn a point.
	for i in 400:
		sim._practice("building", "place")
	var levels: int = sim.skills.level("building")
	check(levels >= 3, "practice raised Building (level %d)" % levels)
	eq(int(sim.stats.levels_gained.get("building", 0)), levels, "every level gained is counted")
	eq(sim.stats.perk_points_earned, sim.skills.perk_points, "and the perk points it earned")
	var perk := ""
	for p: String in sim.data.skills["perks"]:
		if perk == "" and sim.skills.can_spend(p) == "":
			perk = p
	eq(sim.spend_perk(perk), "", "spend one (%s)" % perk)
	eq(int(sim.stats.perks_spent.get(perk, 0)), 1, "spending is counted")
	text = "\n".join(sim.stats.summary_lines())
	check(("Skill levels gained: building +%d." % levels) in text, "skills line")
	check(("Perk points earned: %d, spent: 1 (%s)." % [sim.stats.perk_points_earned, perk.replace("_", " ")]) in text, "perks line")
	sim.stats.muted = true
	sim.stats.note_gear("set")
	check(not sim.stats.gear_found.has("set"), "muted: the game's own setup isn't counted")


func test_p3_shots_per_gun() -> void:
	var sim := SimWorld.new(12.0)
	var gun := sim.gear.make("pistol", "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(gun["uid"])
	sim.inventory.add("ammo_standard", 30)
	sim.swap_hands()
	_run(sim, 1.0)
	sim.reload()
	_run(sim, 4.0)
	eq(sim.fire(), "", "a shot")
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	sim.shoot_zombie(z.id, false)
	var name: String = sim.guns.gun()["name"]
	eq(sim.stats.guns[name]["shots"], 1, "one shot from the %s" % name)
	eq(sim.stats.guns[name]["hits"], 1, "one hit")
	sim.stats.note_shot("Rifle")
	check(("  %s: 1, 1, %d" % [name, sim.stats.guns[name]["kills"]]) in sim.stats.summary_lines(), "per gun in the summary")
	check("  Rifle: 1, 0, 0" in sim.stats.summary_lines(), "each gun its own line")


func test_p3_base_events_while_away() -> void:
	var sim := SimWorld.new(10.0)
	sim.player_pos = Vector3(0, 0, 0)
	sim.base_log.add("Nail turret killed a shambler", Vector3(5, 0, 0))  # close by: not "away"
	for i in 3:
		sim.base_log.add("Nail turret killed a shambler", Vector3(100, 0, 0))
	sim.base_log.add("West wall under attack: 6 zombies", Vector3(100, 0, 0))
	sim.base_log.add("North wall destroyed", Vector3(100, 0, 0))
	sim.base_log.add("Nail turret out of nails", Vector3(100, 0, 0))
	sim.base_log.add("Tripwire rang", Vector3(100, 0, 0))
	sim.step()
	eq(sim.stats.away_total, 7, "seven events more than 40 m away, the near one not counted")
	eq(sim.stats.away.size(), 5, "the five that matter most are kept")
	eq(sim.stats.away[0]["text"], "North wall destroyed", "destroyed first")
	eq(sim.stats.away[1]["text"], "West wall under attack: 6 zombies", "then under attack")
	eq(sim.stats.away[2]["text"], "Nail turret out of nails", "then out of ammo")
	eq(sim.stats.away[3]["text"], "Tripwire rang", "then a tripwire")
	eq(sim.stats.away[4]["text"], "Nail turret killed a shambler", "and one kill")
	check("At your base while you were away (7 events, the 5 that mattered most):" in sim.stats.summary_lines(), "in the summary")


func test_p3_houses_entered() -> void:
	var sim := SimWorld.new(10.0)
	var plan := TownPlan.generate(1)
	sim.know_houses(plan)
	var cell: Vector2i = plan["houses"][0]["cells"][0]
	sim.player_pos = Vector3(cell.x * 2.0 + 1.0, 0, cell.y * 2.0 + 1.0)
	_run(sim, 2.0)
	sim.player_pos = Vector3(0, 0, 6)
	_run(sim, 1.0)
	sim.player_pos = Vector3(cell.x * 2.0 + 1.0, 0, cell.y * 2.0 + 1.0)
	_run(sim, 1.0)
	eq(sim.stats.houses.size(), 1, "one house, counted once")
	check(String(sim.stats.houses[0]).begins_with("house 0 ("), "by a plain name (%s)" % sim.stats.houses[0])
	check(("Houses entered: 1 (%s)." % sim.stats.houses[0]) in sim.stats.summary_lines(), "in the summary")
