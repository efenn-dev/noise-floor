extends "res://test/base_test.gd"
## V25: first-hour guidance stays sim-owned, survives saves, and its keys go through the real viewport.

const MAIN := "res://scenes/main.tscn"
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST
const S := BuildGrid.Side.SOUTH
const W := BuildGrid.Side.WEST


func _key(vp: Viewport, key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		vp.push_input(event)


func _said(sim: SimWorld, text: String) -> bool:
	return sim.messages.any(func(message: Dictionary) -> bool: return message["text"] == text)


func _build_shelter(sim: SimWorld) -> void:
	sim.inventory.give_all({"plank": 100, "nails": 100})
	eq(sim.build.place("foundation", Vector2i.ZERO, N, sim.inventory), "", "shelter foundation")
	eq(sim.build.place("bed", Vector2i.ZERO, N, sim.inventory), "", "bed on it")
	for side: int in [N, E, S]:
		eq(sim.build.place("wall", Vector2i.ZERO, side, sim.inventory), "", "shelter wall %d" % side)
	eq(sim.build.place("door", Vector2i.ZERO, W, sim.inventory), "", "shelter door")


func test_perk_toast_badge_and_obvious_skills_points() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var level_one := float(sim.data.skills["levels"][1])
	sim.skills.xp["strength"] = level_one
	sim.skills.xp["fitness"] = level_one
	sim.skills.xp["building"] = level_one - float(sim.data.skills["skills"]["building"]["xp"]["place"]) * 0.5
	sim._practice("building", "place")
	check(_said(sim, "Perk point! Press K to spend it"), "earning a point gives the clear K toast")
	main._update_hud(0.0)
	check(main._perk_badge.visible, "unspent points show a HUD badge")
	eq(main._perk_badge_label.text, "K: 1 perk point", "badge gives the key and count")
	main.skills_screen.open()
	main.skills_screen.refresh()
	check("UNSPENT PERK POINT" in main.skills_screen._points_label.text, "the skills screen makes the point obvious")
	main.skills_screen.spend("soft_step")
	main._update_hud(0.0)
	check(not main._perk_badge.visible, "the badge clears when the point is spent")
	eq(sim.stats.perks_spent.get("soft_step", 0), 1, "the session records the spent point")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_better_gear_compares_rarity_tier_condition_and_main_stat() -> void:
	var sim := SimWorld.new()
	var common := sim.gear.make("work_boots", "civilian", "white", {}, 0.7)
	var rare := sim.gear.make("work_boots", "civilian", "yellow", {}, 0.7)
	check(sim.gear.is_better(common, {}), "an empty slot accepts a wearable piece")
	check(sim.gear.is_better(rare, common), "rarity can make the same base better")
	check(not sim.gear.is_better(common, rare), "lower rarity does not replace it")
	var civilian := sim.gear.make("work_boots", "civilian", "blue", {}, 0.7)
	var police := sim.gear.make("work_boots", "police", "blue", {}, 0.7)
	check(sim.gear.is_better(police, civilian), "a higher base tier wins otherwise equal pieces")
	var worn := sim.gear.make("work_boots", "civilian", "blue", {}, 0.4)
	var mint := sim.gear.make("work_boots", "civilian", "blue", {}, 1.0)
	check(sim.gear.is_better(mint, worn), "condition breaks an otherwise equal comparison")
	var boots := sim.gear.make("work_boots", "civilian", "white", {}, 1.0)
	var shoes := sim.gear.make("sneakers", "civilian", "white", {}, 1.0)
	check(sim.gear.is_better(shoes, boots), "the feet slot values its main quietness stat")
	var part := sim.gear.make("scope", "civilian", "yellow")
	check(not sim.gear.is_better(part, {}), "a firearm part is not wearable gear")


func test_looted_upgrade_toast_quick_equips_and_rechecks_before_wearing() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var id := "guidance_test_crate"
	sim.loot.add(id, "industrial", sim.player_pos)
	sim.loot.containers[id]["searched"] = true
	var boots := sim.gear.make("work_boots", "civilian", "yellow", {}, 0.9)
	sim.loot.add_gear(id, [boots])
	check(sim.move_container_gear(id, int(boots["uid"]), true)["moved"], "loot the boots into pockets")
	main._update_hud(0.0)
	check(main._gear_toast_label.visible, "an upgrade gets its own toast")
	eq(main._gear_toast_label.text, "Rare work boots: better than your feet slot. Press Y to wear", "toast names the rarity, slot and key")
	eq(main._gear_toast_label.get_theme_color("font_color"), sim.gear.color(boots), "toast uses the rarity colour")
	_key(main.get_viewport(), KEY_Y)
	eq(int(sim.gear.equipped["feet"]["uid"]), int(boots["uid"]), "Y wears the suggested piece")
	eq(sim.stats.gear_equipped.get("%s (%s)" % [boots["name"], boots["rarity"]], 0), 1,
			"the session records the equipped piece and rarity")
	main._update_hud(0.0)
	check(not main._gear_toast_label.visible, "wearing it clears the toast")

	var worse := sim.gear.make("work_boots", "civilian", "white", {}, 0.4)
	sim.gear.pieces.append(worse)
	sim.guidance.note_better_gear(int(worse["uid"]))  # it was suggested before the rare boots went on
	_key(main.get_viewport(), KEY_Y)
	eq(int(sim.gear.equipped["feet"]["uid"]), int(boots["uid"]), "Y refuses a piece that is now worse")
	check(_said(sim, "That piece is no longer better"), "and explains the refusal")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_each_first_night_objective_ticks_from_sim_state() -> void:
	var sim := SimWorld.new(8.0)
	sim.guidance.start(sim.clock.day)
	eq(sim.guidance.step(sim.build), 0, "starts with food and water")
	sim.inventory.add("canned_food", 1)
	sim.inventory.add("clean_water", 1)
	sim.eat_best()
	eq(sim.guidance.step(sim.build), 0, "food alone is not both supplies")
	sim.drink_best()
	eq(sim.guidance.step(sim.build), 1, "eating and drinking tick the first goal")
	_build_shelter(sim)  # building early is remembered from the build state
	var bed := sim.build.key_for("bed", Vector2i.ZERO)
	check(sim.sleep_in(bed) != "No bed", "interacting with the bed finds it even when not tired")
	eq(sim.guidance.step(sim.build), 3, "the already-built complete shelter also ticks")
	var progress := sim.guidance.shelter_progress(sim.build)
	eq(progress, [true, true, 3, true, true], "foundation, bed, three walls and door are all seen as enclosed")
	sim.clock.time_of_day = 21.01
	sim.step()
	check(sim.guidance.saw_night, "the sim sees night begin")
	sim.clock.day = 2
	sim.clock.time_of_day = sim.clock.sunrise_hour + 0.01
	sim.step()
	check(sim.guidance.survived_night and sim.guidance.completed, "reaching morning alive completes the loop")
	eq(sim.guidance.step(sim.build), Guidance.COMPLETE, "all four objectives are complete")


func test_shelter_subchecks_tick_when_the_shell_is_built_before_the_bed() -> void:
	var sim := SimWorld.new()
	sim.inventory.give_all({"plank": 100, "nails": 100})
	eq(sim.build.place("foundation", Vector2i.ZERO, N, sim.inventory), "", "foundation first")
	for side: int in [N, E, S]:
		eq(sim.build.place("wall", Vector2i.ZERO, side, sim.inventory), "", "wall before bed")
	eq(sim.build.place("door", Vector2i.ZERO, W, sim.inventory), "", "door before bed")
	eq(sim.guidance.shelter_progress(sim.build), [true, false, 3, true, false],
			"the shell's subchecks advance without prematurely completing")
	eq(sim.build.place("bed", Vector2i.ZERO, N, sim.inventory), "", "bed goes inside last")
	eq(sim.guidance.shelter_progress(sim.build), [true, true, 3, true, true],
			"placing the bed completes that same enclosed room")


func test_dying_at_night_requires_surviving_a_later_full_night() -> void:
	var sim := SimWorld.new(8.0)
	sim.guidance.start(1)
	sim.clock.time_of_day = 21.01
	sim.step()
	sim.tally["deaths"] = 1
	sim.step()
	sim.clock.day = 2
	sim.clock.time_of_day = sim.clock.sunrise_hour + 0.01
	sim.step()
	check(not sim.guidance.survived_night, "dying during the night does not count its remaining hours")
	sim.clock.time_of_day = sim.clock.sunset_hour + 0.01
	sim.step()
	sim.clock.day = 3
	sim.clock.time_of_day = sim.clock.sunrise_hour + 0.01
	sim.step()
	check(sim.guidance.survived_night, "a later full night completes the survival check")


func test_objectives_hide_from_setting_non_new_games_and_no_hints() -> void:
	var old_setting := Settings.show_objectives
	Settings.show_objectives = true
	var sim := SimWorld.new()
	sim.guidance.start(1)
	var panel := ObjectivesPanel.new()
	tree.root.add_child(panel)
	panel.setup(sim)
	panel.refresh()
	check(panel.visible and "Find food and water" in panel.text(), "an active new-game checklist is visible")
	Settings.show_objectives = false
	panel.refresh()
	check(not panel.visible, "the Show objectives setting hides it")
	Settings.show_objectives = true
	panel.suppressed = true
	panel.refresh()
	check(not panel.visible, "--no-hints suppression wins over the setting")
	panel.queue_free()
	await tree.process_frame

	var legacy := SaveGame.read("res://test/fixtures/save_v18.json")
	var established := SimWorld.new(8.0, null, int(legacy["seed"]))
	eq(SaveGame.apply(established, legacy), "", "the version-18 fixture migrates")
	check(not established.guidance.active, "an established pre-guidance game does not start objectives")
	var old_panel := ObjectivesPanel.new()
	tree.root.add_child(old_panel)
	old_panel.setup(established)
	old_panel.refresh()
	check(not old_panel.visible, "so its panel shows nothing")
	old_panel.queue_free()
	Settings.show_objectives = old_setting
	await tree.process_frame

	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	check(not main.sim.guidance.active and not main.objectives_panel.visible, "the test equivalent of --no-hints starts no objectives")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_guidance_save_round_trip() -> void:
	var a := SimWorld.new(8.0, null, 25)
	a.guidance.start(1)
	a.guidance.note_consumed(30.0, 0.0)
	a.guidance.note_bed()
	var boots := a.gear.make("work_boots", "civilian", "yellow")
	a.gear.pieces.append(boots)
	a.guidance.note_better_gear(int(boots["uid"]))
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(data["version"]), 19, "guidance bumps the save to version 19")
	var b := SimWorld.new(8.0, null, 25)
	eq(SaveGame.apply(b, data), "", "the current save loads")
	check(b.guidance.active and b.guidance.ate and b.guidance.bed_found, "objective progress survives")
	check(not b.guidance.drank, "an unfinished half-step stays unfinished")
	eq(b.guidance.better_gear_uid, int(boots["uid"]), "the quick-equip suggestion survives")

