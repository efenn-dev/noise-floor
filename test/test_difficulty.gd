extends "res://test/base_test.gd"
## V29: data-driven difficulty, first-night pressure, shelter response and save migration.

const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST
const S := BuildGrid.Side.SOUTH
const W := BuildGrid.Side.WEST


func _said(sim: SimWorld, text: String) -> int:
	return sim.messages.filter(func(m: Dictionary) -> bool: return m["text"] == text).size()


func _build_shelter(sim: SimWorld) -> void:
	sim.inventory.give_all({"plank": 100, "nails": 100})
	sim.build.place("foundation", Vector2i.ZERO, N, sim.inventory)
	sim.build.place("bed", Vector2i.ZERO, N, sim.inventory)
	for side: int in [N, E, S]:
		sim.build.place("wall", Vector2i.ZERO, side, sim.inventory)
	sim.build.place("door", Vector2i.ZERO, W, sim.inventory)
	sim.player_pos = Vector3(1.0, 0.0, 1.0)


func _at_first_night(id: String, sheltered: bool = false) -> SimWorld:
	var sim := SimWorld.new(20.99, null, 29, id)
	if sheltered:
		_build_shelter(sim)
	sim.clock.time_of_day = 21.0
	sim.step()
	return sim


func test_new_game_choice_defaults_normal_and_reaches_the_slot() -> void:
	var menus := Menus.new()
	tree.root.add_child(menus)
	menus.show_title([
		{"slot": 1, "used": false, "name": "", "summary": "Empty"},
		{"slot": 2, "used": false, "name": "", "summary": "Empty"},
		{"slot": 3, "used": false, "name": "", "summary": "Empty"},
	])
	var chosen := []
	menus.new_game.connect(func(slot: int, profile_name: String, difficulty: String) -> void:
		chosen.append([slot, profile_name, difficulty]))
	menus.open_slots(true)
	menus.choose_slot(2)
	(menus.find_child("ProfileName", true, false) as LineEdit).text = "Kaleb"
	menus.start_new_profile()
	eq(chosen, [[2, "Kaleb", "normal"]], "New game defaults to Normal after the slot name")

	menus.open_slots(true)
	menus.choose_slot(3)
	(menus.find_child("ProfileName", true, false) as LineEdit).text = "Dad"
	var picker := menus.find_child("Difficulty", true, false) as OptionButton
	picker.select(Difficulty.ORDER.find("hard"))
	menus.start_new_profile()
	eq(chosen[1], [3, "Dad", "hard"], "Hard is carried with the named slot choice")
	var chosen_sim := SimWorld.new(8.0, null, 29, str(chosen[1][2]))
	eq(SaveGame.to_dict(chosen_sim)["difficulty"], "hard", "the New game choice reaches the save payload")
	menus.queue_free()
	await tree.process_frame


func test_every_multiplier_reaches_its_rule() -> void:
	var data := GameData.load_default()
	for id: String in Difficulty.ORDER:
		var cfg: Dictionary = data.difficulty[id]
		var sim := SimWorld.new(12.0, data, 7, id)
		var z := sim.horde.spawn("shambler", Vector3.ZERO)
		near(z.max_hp(), float(data.zombies["shambler"]["hp"]) * float(cfg["zombie_health"]),
				id + " zombie health")
		near(z.attack_damage(), float(data.zombies["shambler"]["damage"]) * float(cfg["zombie_damage"]),
				id + " zombie damage")
		near(z.structure_damage(), float(data.zombies["shambler"]["structure_damage"]) * float(cfg["zombie_damage"]),
				id + " wall damage")
		eq(sim.difficulty.count("zombie_count", 10), roundi(10.0 * float(cfg["zombie_count"])),
				id + " starting count")
		eq(sim.difficulty.count("night_wave_size", 10), roundi(10.0 * float(cfg["night_wave_size"])),
				id + " heat-wave count")

		var before_food := sim.player.food
		var before_water := sim.player.water
		var before_energy := sim.player.energy
		sim.player.tick(10.0)
		near(before_food - sim.player.food,
				float(data.survival["food_drain"]) * float(cfg["needs_drain"]) * 10.0,
				id + " needs drain")
		near(before_water - sim.player.water,
				float(data.survival["water_drain"]) * float(cfg["needs_drain"]) * 10.0,
				id + " thirst drain")
		near(before_energy - sim.player.energy,
				float(data.survival["energy_drain"]) * float(cfg["needs_drain"]) * 10.0,
				id + " energy drain")

		var table := {"rolls": [10, 10], "items": [{"item": "nails", "weight": 1, "min": 1, "max": 1}]}
		sim.data.loot["difficulty_fixed"] = table
		sim.loot.add("fixed", "difficulty_fixed", Vector3.ZERO)
		var found := sim.loot.reveal("fixed")
		eq(int(found["items"]["nails"]), roundi(10.0 * float(cfg["loot_abundance"])), id + " loot rolls")

		var source := {"pos": Vector3.ZERO, "loudness": 80.0, "key": "machine", "kind": "smelter"}
		sim.noise.continuous = [source]
		var raw := maxf(0.0, sim.noise.level(80.0, float(sim.director.cfg["listen_distance"]), 0)
				- float(sim.director.cfg["gain_floor"])) * float(sim.director.cfg["gain_rate"])
		near(sim.director.gain_now(sim.noise, false), raw * float(cfg["director_heat_gain"]),
				id + " Director heat gain")
		sim.director.heat = float(sim.director.cfg["group_at"])
		sim.director._check = 0.0
		var wave := sim.director.tick(0.0, sim.noise, true, sim.horde)
		eq(int(wave["size"]), sim.difficulty.count("night_wave_size", int(sim.director.cfg["group"]), 1),
				id + " actual night heat wave")

		sim.skills.xp["strength"] = 50.0
		sim.player.damage(1000.0, "test")
		near(float(sim.skills.xp["strength"]), 50.0, id + " keeps skills on death")


func test_night_hearing_and_speed_scale_with_difficulty() -> void:
	var hearing := []
	var speeds := []
	for id: String in Difficulty.ORDER:
		var sim := SimWorld.new(22.0, null, 3, id)
		var z := sim.horde.spawn("shambler", Vector3.ZERO)
		z.state = ZombieBrain.State.CHASE
		z.night = true
		hearing.append(z.hearing(true))
		speeds.append(z.move_speed())
	near(float(hearing[1]), 14.0, "Normal keeps the authored night hearing")
	check(hearing[0] > hearing[1] and hearing[1] > hearing[2], "Hard hears best at night; Easy hears least")
	check(speeds[0] < speeds[1] and speeds[1] < speeds[2], "night movement bonus rises with difficulty")


func test_warning_and_first_wave_happen_once_and_hunt_outside() -> void:
	var sim := SimWorld.new(18.99, null, 11, "normal")
	sim.clock.time_of_day = 19.0
	sim.step()
	eq(_said(sim, "It'll be dark at 21:00. Find shelter: a bed inside walls with a door"), 1,
			"the 19:00 warning appears")
	sim.step()
	eq(_said(sim, "It'll be dark at 21:00. Find shelter: a bed inside walls with a door"), 1,
			"the warning does not repeat")
	sim.clock.time_of_day = 21.0
	sim.step()
	eq(sim.director.first_night_ids.size(), 5, "Normal sends a handful at 21:00")
	eq(_said(sim, "Night falls"), 1, "nightfall gets its short message")
	eq(sim.scares.count("night"), 1, "nightfall requests one sting")
	for id: int in sim.director.first_night_ids:
		eq((sim.horde.zombies[id] as ZombieBrain).state, ZombieBrain.State.CHASE, "outside: the wave hunts you")
	var count := sim.horde.alive_count()
	sim.step()
	eq(sim.horde.alive_count(), count, "the first wave does not repeat")
	eq(_said(sim, "Night falls"), 1, "the nightfall message does not repeat")


func test_a_game_started_after_dark_gets_no_dusk_warning() -> void:
	var sim := SimWorld.new(22.0, null, 11, "normal")
	sim.step()
	eq(_said(sim, "It'll be dark at 21:00. Find shelter: a bed inside walls with a door"), 0,
			"Q6: starting at 22:00, no warning that it'll be dark at 21:00")
	eq(_said(sim, "Night falls"), 1, "the night still falls, with its wave")
	check(sim.director.first_night_warning_sent, "and the warning is marked done")


func test_shelter_holds_the_wave_until_the_player_makes_noise() -> void:
	var sim := SimWorld.new(20.99, null, 29, "normal")
	_build_shelter(sim)
	var door := BuildGrid.key_for_wall_edge(Vector2i.ZERO, W)
	check(sim.guidance.is_sheltered(sim.build, sim.player_pos), "the closed player-built bedroom is shelter")
	sim.build.pieces[door]["open"] = true
	check(not sim.guidance.is_sheltered(sim.build, sim.player_pos), "its open door is not shelter")
	sim.build.pieces[door]["open"] = false
	sim.clock.time_of_day = 21.0
	sim.step()
	check(sim.director.first_night_sheltered, "a closed player-built bedroom is sheltered")
	for id: int in sim.director.first_night_ids:
		eq((sim.horde.zombies[id] as ZombieBrain).state, ZombieBrain.State.INVESTIGATE,
				"the sheltered wave mills outside instead of hunting")
	sim.noise.emit(sim.player_pos, 80.0, "footstep_sprint")
	sim.step()
	check(not sim.director.first_night_sheltered, "making noise gives the shelter away")
	for id: int in sim.director.first_night_ids:
		eq((sim.horde.zombies[id] as ZombieBrain).state, ZombieBrain.State.CHASE,
				"the noisy sheltered player is hunted")


func test_closed_town_house_with_bed_and_intact_window_is_shelter() -> void:
	var sim := SimWorld.new()
	var cell := Vector2i.ZERO
	sim.build.restore("f:0:0", {"id": "town_floor", "cell": cell, "side": N, "hp": 400, "town": true})
	sim.build.restore(sim.build.key_for("bed", cell), {"id": "bed", "cell": cell, "side": N, "hp": 60, "town": true})
	for side: int in [E, S]:
		var key := BuildGrid.key_for_wall_edge(cell, side)
		sim.build.restore(key, {"id": "town_wall", "cell": cell, "side": side, "hp": 600, "town": true})
	var window := BuildGrid.key_for_wall_edge(cell, N)
	sim.build.restore(window, {"id": "window", "cell": cell, "side": N, "hp": 40, "town": true})
	var door := BuildGrid.key_for_wall_edge(cell, W)
	sim.build.restore(door, {"id": "door", "cell": cell, "side": W, "hp": 200, "open": false, "town": true})
	var at := Vector3(1.0, 0.0, 1.0)
	check(sim.guidance.is_sheltered(sim.build, at), "closed town house with a bed and whole window protects you")
	sim.build.pieces[door]["open"] = true
	check(not sim.guidance.is_sheltered(sim.build, at), "an open town door exposes you")
	sim.build.pieces[door]["open"] = false
	sim.build.pieces[window]["hp"] = 0
	check(not sim.guidance.is_sheltered(sim.build, at), "a broken town window exposes you")


func test_easy_first_wave_is_small_slow_and_weak_hard_adds_a_runner() -> void:
	var easy := _at_first_night("easy")
	eq(easy.director.first_night_ids.size(), 3, "Easy sends only three")
	for id: int in easy.director.first_night_ids:
		var z: ZombieBrain = easy.horde.zombies[id]
		eq(z.type, "shambler", "Easy first night has only slow zombies")
		near(z.hp, 60.0, "Easy shambler health")
		near(z.attack_damage(), 5.0, "Easy shambler damage")
		near(z.structure_damage(), 5.0, "Easy shambler cannot break walls quickly")
	var hard := _at_first_night("hard")
	eq(hard.director.first_night_ids.size(), 8, "Hard sends eight")
	var types := hard.director.first_night_ids.map(
			func(id: int) -> String: return (hard.horde.zombies[id] as ZombieBrain).type)
	eq(types.count("runner"), 1, "Hard adds a runner")


func test_morning_message_save_round_trip_and_v19_migration() -> void:
	var died := _at_first_night("normal")
	died.player.damage(1000.0, "shambler")
	died.clock.day = 2
	died.clock.time_of_day = 6.0
	died.step()
	eq(_said(died, "You made it to morning"), 0, "dying during the first night does not claim survival")

	var a := _at_first_night("hard", true)
	a.clock.day = 2
	a.clock.time_of_day = 6.0
	a.step()
	eq(_said(a, "You made it to morning"), 1, "06:00 after the first night gets the morning message")
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	check(int(d["version"]) >= 20, "difficulty is saved from version 20 on")
	eq(d["difficulty"], "hard", "difficulty is in the sim payload")
	var b := SimWorld.new(8.0, null, 29)
	eq(SaveGame.apply(b, d), "", "current difficulty save loads")
	eq(b.difficulty.id, "hard", "difficulty survives the round trip")
	check(b.director.first_night_wave_sent and b.director.first_morning_sent,
			"one-shot night state survives too")

	var old := SaveGame.read("res://test/fixtures/save_v19.json")
	eq(int(old["version"]), 19, "the fixture was written by V25")
	old["difficulty"] = "hard"  # Version, not an accidental field, owns the migration.
	var migrated := SimWorld.new(8.0, null, int(old["seed"]), "hard")
	eq(SaveGame.apply(migrated, old), "", "the v19 fixture loads")
	eq(migrated.difficulty.id, "normal", "an older save migrates to Normal")
	eq(GameSession._meta_from_data(old, 1)["difficulty"], "normal", "its slot summary migrates too")
	check(not migrated.director.first_night_warning_sent and not migrated.director.first_night_wave_sent,
			"its 18:30 first night still has both beats ahead")

	GameSession.current_slot_name = "Dad"
	GameSession.current_slot = 1
	GameSession.slot_real_seconds = 90.0
	var meta := GameSession.make_meta(a)
	check("Hard" in GameSession.summary_text(meta), "slot summary shows difficulty")
	var menus := Menus.new()
	tree.root.add_child(menus)
	menus.set_difficulty(a.difficulty.display_name())
	menus.show_pause(false)
	eq(menus._difficulty_label.text, "Difficulty: Hard", "pause menu shows difficulty")
	menus.queue_free()
	await tree.process_frame
