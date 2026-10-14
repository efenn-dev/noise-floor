extends "res://test/base_test.gd"
## V26: three named save slots, their title UI, safe overwrite/delete confirmations, migration,
## and the real main-scene F5/F9 path. Every path here is test-only.

const MAIN := "res://scenes/main.tscn"
const FOLDER := "user://test_save_slots"
const LEGACY := "user://test_save_slots_legacy.json"


func _reset_slots() -> void:
	tree.paused = false
	InputSetup.assume_captured = false
	GameSession.pending_load = ""
	GameSession.started = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	GameSession.slots_folder = FOLDER
	GameSession.legacy_save_path = LEGACY
	GameSession.current_slot = 1
	GameSession.current_slot_name = "Slot 1"
	GameSession.slot_real_seconds = 0.0
	GameSession.save_path = GameSession.slot_path(1)
	for slot in range(1, GameSession.SLOT_COUNT + 1):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.slot_path(slot)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))


func _restore_slots() -> void:
	for slot in range(1, GameSession.SLOT_COUNT + 1):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.slot_path(slot)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))
	GameSession.slots_folder = GameSession.SAVE_FOLDER
	GameSession.legacy_save_path = GameSession.LEGACY_SAVE_PATH
	GameSession.current_slot = 1
	GameSession.current_slot_name = "Slot 1"
	GameSession.slot_real_seconds = 0.0
	GameSession.save_path = GameSession.SAVE_PATH
	GameSession.pending_load = ""
	GameSession.started = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	InputSetup.assume_captured = false
	tree.paused = false


func _write_slot(slot: int, profile_name: String, day: int, hour: float, played: float,
		kills: int, water: float = 100.0) -> String:
	GameSession.current_slot = slot
	GameSession.current_slot_name = profile_name
	GameSession.slot_real_seconds = played
	GameSession.save_path = GameSession.slot_path(slot)
	var sim := SimWorld.new(hour)
	sim.clock.day = day
	sim.player.water = water
	sim.tally["kills"] = kills
	return SaveGame.write(sim, GameSession.save_path, {"meta": GameSession.make_meta(sim)})


func _key(viewport: Viewport, key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		viewport.push_input(event)


func test_three_slots_and_meta_block() -> void:
	_reset_slots()
	eq(GameSession.SLOT_COUNT, 3, "the slot count is data-driven from one constant")
	eq(_write_slot(1, "Dad", 3, 14.5, 3723.0, 17), "", "slot 1 saves")
	eq(_write_slot(2, "Kaleb", 8, 21.25, 95.0, 4), "", "slot 2 saves")
	eq(_write_slot(3, "Guest", 1, 8.0, 0.0, 0), "", "slot 3 saves")
	for slot in range(1, GameSession.SLOT_COUNT + 1):
		check(FileAccess.file_exists(GameSession.slot_path(slot)), "slot %d has its own file" % slot)
	var data := SaveGame.read(GameSession.slot_path(1))
	var meta: Dictionary = data.get("meta", {})
	eq(meta.get("name"), "Dad", "meta has the typed profile name")
	eq(int(meta.get("day", 0)), 3, "meta has the game day")
	near(float(meta.get("time", 0.0)), 14.5, "meta has the game time")
	near(float(meta.get("real_seconds", 0.0)), 3723.0, "meta has real time played")
	check(str(meta.get("last_played", "")) != "", "meta has the last-played date")
	eq(int(meta.get("zombies_killed", -1)), 17, "meta has zombies killed")
	eq(Settings.PATH, "user://settings.cfg", "settings remain one shared file")
	_restore_slots()


func test_title_lists_names_summaries_and_empty_slot() -> void:
	_reset_slots()
	_write_slot(1, "Dad", 3, 14.5, 3723.0, 17)
	_write_slot(2, "Kaleb", 8, 21.25, 95.0, 4)
	var menus := Menus.new()
	tree.root.add_child(menus)
	menus.show_title(GameSession.slot_summaries())
	menus.open_slots(false)
	eq(menus._slot_rows.get_child_count(), GameSession.SLOT_COUNT, "the picker draws all three slots")
	check("Dad" in menus.slot_text(1) and "Day 3, 14:30" in menus.slot_text(1), "Dad's day and time are listed")
	check("1 h 02 min played" in menus.slot_text(1) and "17 zombies killed" in menus.slot_text(1),
			"Dad's play time and kills are summarized")
	check("Kaleb" in menus.slot_text(2) and "Last played" in menus.slot_text(2), "Kaleb and the date are listed")
	check("Empty" in menus.slot_text(3), "an unused slot says Empty")
	menus.queue_free()
	await tree.process_frame
	_restore_slots()


func test_used_new_game_and_delete_need_confirmation() -> void:
	_reset_slots()
	_write_slot(1, "Dad", 3, 14.5, 300.0, 2)
	_write_slot(2, "Kaleb", 2, 9.0, 100.0, 1)
	var old_dad := FileAccess.get_file_as_string(GameSession.slot_path(1))
	var menus := Menus.new()
	tree.root.add_child(menus)
	menus.show_title(GameSession.slot_summaries())
	var new_calls := []
	menus.new_game.connect(func(slot: int, profile_name: String) -> void:
		new_calls.append([slot, profile_name])
		GameSession.start_new_slot(slot, profile_name))
	menus.open_slots(true)
	menus.choose_slot(1)
	eq(new_calls.size(), 0, "choosing a used slot does not start or replace it")
	eq(FileAccess.get_file_as_string(GameSession.slot_path(1)), old_dad, "the used save is intact before confirmation")
	menus.confirm_pending()
	check(menus.new_profile_open(), "overwrite confirmation leads to the name field")
	check(FileAccess.file_exists(GameSession.slot_path(1)), "confirming the warning alone still keeps the save")
	(menus.find_child("ProfileName", true, false) as LineEdit).text = "Dad's new run"
	menus.start_new_profile()
	eq(new_calls, [[1, "Dad's new run"]], "the confirmed named game starts in slot 1")
	check(not FileAccess.file_exists(GameSession.slot_path(1)), "the confirmed new game replaces the old slot")
	var delete_calls := []
	menus.update_slots(GameSession.slot_summaries())
	menus.delete_slot_requested.connect(func(slot: int) -> void:
		delete_calls.append(slot)
		GameSession.delete_slot(slot))
	menus.request_delete(2)
	eq(delete_calls.size(), 0, "Delete does nothing before confirmation")
	check(FileAccess.file_exists(GameSession.slot_path(2)), "Kaleb's save is intact before delete confirmation")
	menus.confirm_pending()
	eq(delete_calls, [2], "Delete emits only after confirmation")
	check(not FileAccess.file_exists(GameSession.slot_path(2)), "the confirmed slot is deleted")
	menus.queue_free()
	await tree.process_frame
	_restore_slots()


func test_old_single_save_migrates_once() -> void:
	_reset_slots()
	var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path("res://test/fixtures/save_v17.json"),
			ProjectSettings.globalize_path(LEGACY))
	eq(copy_error, OK, "an old single-save fixture is staged at a test-only legacy path")
	var before := SaveGame.read(LEGACY)
	eq(GameSession.migrate_legacy_save(), "", "the legacy save migrates")
	check(FileAccess.file_exists(LEGACY), "the old save is copied, never deleted (older builds can still read it)")
	eq(SaveGame.read(LEGACY).get("seed"), before.get("seed"), "and left untouched")
	check(FileAccess.file_exists(GameSession.slot_path(1)), "the old game is now slot 1")
	var migrated := SaveGame.read(GameSession.slot_path(1))
	eq(int(migrated.get("version", 0)), int(before.get("version", -1)), "its SaveGame version is unchanged")
	eq(migrated.get("seed"), before.get("seed"), "its world data is preserved")
	var migrated_meta: Dictionary = migrated.get("meta", {})
	eq(migrated_meta.get("name"), "Slot 1", "migration names it Slot 1")
	var once := FileAccess.get_file_as_string(GameSession.slot_path(1))
	eq(GameSession.migrate_legacy_save(), "", "the next start is a no-op")
	eq(FileAccess.get_file_as_string(GameSession.slot_path(1)), once, "slot 1 is not rewritten or duplicated")
	check(not FileAccess.file_exists(GameSession.slot_path(2)) and not FileAccess.file_exists(GameSession.slot_path(3)),
			"migration creates no extra slots")
	_restore_slots()


func test_continue_and_f5_f9_use_the_current_slot() -> void:
	_reset_slots()
	_write_slot(1, "Dad", 2, 10.0, 600.0, 3, 71.0)
	var dad_before := FileAccess.get_file_as_string(GameSession.slot_path(1))
	GameSession.start_new_slot(2, "Kaleb")
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	InputSetup.assume_captured = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	tree.current_scene = main
	for i in 5:
		await tree.process_frame
	main.sim.clock.day = 5
	main.sim.clock.time_of_day = 18.75
	main.sim.player.water = 42.0
	main.sim.tally["kills"] = 9
	GameSession.slot_real_seconds = 3661.0
	_key(main.get_viewport(), KEY_F5)
	check(FileAccess.file_exists(GameSession.slot_path(2)), "F5 writes the current slot")
	eq(FileAccess.get_file_as_string(GameSession.slot_path(1)), dad_before, "F5 does not touch Dad's slot")
	check(not FileAccess.file_exists(GameSession.slot_path(3)), "F5 does not create another slot")
	var saved := SaveGame.read(GameSession.slot_path(2))
	var saved_meta: Dictionary = saved.get("meta", {})
	eq(saved_meta.get("name"), "Kaleb", "F5 writes current-slot metadata")
	eq(int(saved_meta.get("day", 0)), 5, "F5 metadata uses the live day")
	main.sim.player.water = 3.0
	_key(main.get_viewport(), KEY_F9)
	for i in 8:
		await tree.process_frame
	var again := tree.current_scene
	check(is_instance_valid(again), "F9 leaves a loaded main scene")
	if is_instance_valid(again):
		near(again.sim.player.water, 42.0, "F9 loads the current slot, not another profile", 0.5)
		eq(GameSession.current_slot, 2, "the selected slot survives the reload")
		again.queue_free()
		tree.current_scene = null
	await tree.process_frame

	# Continue selects the clicked profile before reloading it through the real main-scene route.
	GameSession.pending_load = ""
	GameSession.started = false
	var selector: Node3D = load(MAIN).instantiate()
	tree.root.add_child(selector)
	tree.current_scene = selector
	for i in 5:
		await tree.process_frame
	selector.continue_game(1)
	for i in 8:
		await tree.process_frame
	var continued := tree.current_scene
	check(is_instance_valid(continued), "Continue leaves a loaded main scene")
	if is_instance_valid(continued):
		near(continued.sim.player.water, 71.0, "Continue loads the selected slot's world", 0.5)
		eq(GameSession.current_slot_name, "Dad", "Continue carries the selected profile name")
		continued.queue_free()
	tree.current_scene = null
	await tree.process_frame
	_restore_slots()
