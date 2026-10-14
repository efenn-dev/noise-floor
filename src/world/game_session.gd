class_name GameSession
extends RefCounted
## Things that must survive restarting the game scene (loading a save reloads the scene).

## V26: three named profiles. save_path stays public because main-scene tests point it at a test file.
const SLOT_COUNT := 3
const SAVE_FOLDER := "user://saves"
const LEGACY_SAVE_PATH := "user://save.json"
const SAVE_PATH := SAVE_FOLDER + "/slot_1.json"
const AUTOSAVE_SECONDS := 300.0

## Path of a save to load as soon as the scene has rebuilt the town ("" = start fresh).
static var pending_load := ""
## True once the title screen has been passed this run, so reloads go straight into the game.
static var started := false
## Tests and command-line flags skip the title screen.
static var skip_menu := false
## Tests that load the main scene skip the first-game hints (like --no-hints).
static var skip_hints := false
## Where saves go (tests point this somewhere else).
static var save_path := SAVE_PATH
## These two are the migration test hook: tests point both at user://test_* paths.
static var slots_folder := SAVE_FOLDER
static var legacy_save_path := LEGACY_SAVE_PATH
## The selected profile. Every save/load route, including F5/F9 and autosave, uses save_path.
static var current_slot := 1
static var current_slot_name := "Slot 1"
static var slot_real_seconds := 0.0

## Where play.bat writes the build being played: one line, "<short commit> <commit title>".
const VERSION_PATH := "res://version.txt"
## Tests point this at a file of their own, so they never read the real one.
static var version_path := VERSION_PATH
## True once the build line has been printed to the console (main.gd, once per run).
static var build_printed := false


static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [slots_folder, clampi(slot, 1, SLOT_COUNT)]


## Selects an existing slot and makes it the path used by saves, loads and scene reloads.
static func select_slot(slot: int) -> void:
	current_slot = clampi(slot, 1, SLOT_COUNT)
	save_path = slot_path(current_slot)
	var meta := meta_for_path(save_path, current_slot)
	current_slot_name = clean_name(str(meta.get("name", "")), current_slot)
	slot_real_seconds = float(meta.get("real_seconds", 0.0))


## Starts a confirmed new game in this slot. The caller owns the overwrite confirmation.
static func start_new_slot(slot: int, profile_name: String) -> String:
	var chosen := clampi(slot, 1, SLOT_COUNT)
	var path := slot_path(chosen)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			return "Couldn't replace slot %d (%s)" % [chosen, error_string(err)]
	current_slot = chosen
	save_path = path
	current_slot_name = clean_name(profile_name, current_slot)
	slot_real_seconds = 0.0
	return ""


## Deletes a slot after the menu's confirmation.
static func delete_slot(slot: int) -> String:
	var chosen := clampi(slot, 1, SLOT_COUNT)
	var path := slot_path(chosen)
	if not FileAccess.file_exists(path):
		return ""
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		return "Couldn't delete slot %d (%s)" % [chosen, error_string(err)]
	if chosen == current_slot:
		current_slot_name = "Slot %d" % chosen
		slot_real_seconds = 0.0
	return ""


## The meta block written beside SaveGame's versioned sim payload.
static func make_meta(sim: SimWorld) -> Dictionary:
	return {
		"name": clean_name(current_slot_name, current_slot),
		"day": sim.clock.day,
		"time": sim.clock.time_of_day,
		"real_seconds": slot_real_seconds,
		"last_played": Time.get_datetime_string_from_system(false, true),
		"zombies_killed": int(sim.tally.get("kills", 0)),
	}


## Data for the title picker. A broken file is still "used", so New game cannot erase it without warning.
static func slot_summaries() -> Array:
	var out := []
	for slot in range(1, SLOT_COUNT + 1):
		var path := slot_path(slot)
		var used := FileAccess.file_exists(path)
		var meta := meta_for_path(path, slot) if used else {}
		out.append({
			"slot": slot,
			"used": used,
			"name": str(meta.get("name", "Slot %d" % slot)) if used else "",
			"summary": summary_text(meta) if used else "Empty",
		})
	return out


## Reads metadata, filling it from an older save payload when it predates V26's meta block.
static func meta_for_path(path: String, slot: int = 1) -> Dictionary:
	var data := SaveGame.read(path)
	if data.is_empty():
		return {"name": "Slot %d" % slot, "unreadable": FileAccess.file_exists(path)}
	return _meta_from_data(data, slot)


static func _meta_from_data(data: Dictionary, slot: int) -> Dictionary:
	var raw: Variant = data.get("meta", {})
	var meta: Dictionary = raw if raw is Dictionary else {}
	var clock: Dictionary = data.get("clock", {})
	var tally: Dictionary = data.get("stats", {})
	return {
		"name": clean_name(str(meta.get("name", "Slot %d" % slot)), slot),
		"day": int(meta.get("day", clock.get("day", 1))),
		"time": float(meta.get("time", clock.get("time", 8.0))),
		"real_seconds": maxf(0.0, float(meta.get("real_seconds", 0.0))),
		"last_played": str(meta.get("last_played", "Unknown")),
		"zombies_killed": int(meta.get("zombies_killed", tally.get("kills", 0))),
	}


static func summary_text(meta: Dictionary) -> String:
	if bool(meta.get("unreadable", false)):
		return "Unreadable save"
	return "Day %d, %s  ·  %s played\n%d zombies killed  ·  Last played %s" % [
			int(meta.get("day", 1)), clock_text(float(meta.get("time", 8.0))),
			played_text(float(meta.get("real_seconds", 0.0))), int(meta.get("zombies_killed", 0)),
			str(meta.get("last_played", "Unknown"))]


static func clock_text(hour: float) -> String:
	var wrapped := fposmod(hour, 24.0)
	return "%02d:%02d" % [int(wrapped), int((wrapped - int(wrapped)) * 60.0)]


static func played_text(seconds: float) -> String:
	var minutes := maxi(0, floori(seconds / 60.0))
	if minutes < 60:
		return "%d min" % minutes
	return "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]


static func clean_name(profile_name: String, slot: int) -> String:
	var cleaned := profile_name.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if cleaned.length() > 24:
		cleaned = cleaned.left(24).strip_edges()
	return cleaned if cleaned != "" else "Slot %d" % clampi(slot, 1, SLOT_COUNT)


## First V26 start: copy the old single save into slot 1 and add metadata. The old file is never removed: an
## older build (or a screenshot/test run of this one) can still read it, and nothing is lost if anything goes
## wrong. Once slot 1 exists this does nothing, so it runs once.
static func migrate_legacy_save() -> String:
	if not FileAccess.file_exists(legacy_save_path) or FileAccess.file_exists(slot_path(1)):
		return ""
	var modified := FileAccess.get_modified_time(legacy_save_path)
	var folder_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slots_folder))
	if folder_error != OK:
		return "Couldn't make the save-slots folder (%s)" % error_string(folder_error)
	var target := slot_path(1)
	var data := SaveGame.read(legacy_save_path)
	if data.is_empty():
		var copy_error := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(legacy_save_path), ProjectSettings.globalize_path(target))
		return "" if copy_error == OK else "Couldn't copy the old save into slot 1 (%s)" % error_string(copy_error)
	data["meta"] = _meta_from_data(data, 1)
	data["meta"]["name"] = "Slot 1"
	data["meta"]["last_played"] = Time.get_datetime_string_from_unix_time(modified, true)
	return SaveGame.write_dict(data, target)  # the old file stays where it was either way


## The build being played, for the title screen, the session log and the console. "dev build" when
## play.bat didn't write one (running from the editor, a test, a cloud session).
static func version_line() -> String:
	if not FileAccess.file_exists(version_path):
		return "dev build"
	var f := FileAccess.open(version_path, FileAccess.READ)
	if f == null:
		return "dev build"
	var line := f.get_line().trim_prefix("\ufeff").strip_edges()
	return line if line != "" else "dev build"
