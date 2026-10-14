extends "res://test/base_test.gd"
## SessionLog: a death (and leaving the game) writes the plain-words summary to a file.
## Tests only ever write to path_override, never to user://sessions.

const PATH := "user://test_session_log.txt"


func _read(path: String) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	return f.get_as_text().strip_edges().split("\n")


func test_a_death_writes_the_log() -> void:
	DirAccess.remove_absolute(PATH)
	var sim := SimWorld.new(10.0)
	var slog := SessionLog.new()
	slog.path_override = PATH
	tree.root.add_child(slog)
	slog.setup(sim)
	await tree.process_frame
	check(not FileAccess.file_exists(PATH), "nothing written before anything happens")
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	sim.stats.add_real_time(65.0)
	sim.player_pos = Vector3(0, 0, -1)
	sim.player.health = 5.0
	var z := sim.horde.spawn("shambler", Vector3.ZERO)
	z.los_clear = true
	for i in 60:
		sim.step()
	check(sim.player.dead, "the zombie killed the player")
	await tree.process_frame
	var lines := _read(PATH)
	check(lines.size() > 5 and lines.size() < 55, "a short log was written (%d lines)" % lines.size())
	var text := "\n".join(lines)
	check(text.begins_with("Noise Floor session log, written "), "header")
	check("World seed 1" in text, "the seed, since the game has no version string")
	check("Real time played: 1:05 (m:ss). Game time lived through: 0 d 0:0" in text, "real and game time played")
	check("Deaths: 1" in lines, "one death")
	check("  1. at 1:05 real (day 1 10:0" in text and "): killed by a shambler" in text, "what killed you, in plain words")
	check("Built 1 piece: 1 foundation." in lines, "what you built")
	check("  0:00 built a foundation" in lines, "the timeline")
	check("Wearing at the end: Melee: Pipe (white)." in lines, "what you wore at the end (P3)")
	check("Firearms: never fired." in lines and "Houses entered: 0." in lines, "the P3 lines")
	DirAccess.remove_absolute(PATH)
	slog.queue_free()
	await tree.process_frame
	check(FileAccess.file_exists(PATH), "leaving the game writes it again")
	DirAccess.remove_absolute(PATH)


func test_off_unless_enabled() -> void:
	var sim := SimWorld.new(10.0)
	var slog := SessionLog.new()
	slog.setup(sim)
	sim.stats.add_real_time(100.0)
	eq(slog.write(), "", "no path_override and not enabled: writes nothing")
	slog.enabled = true
	sim.stats.real_seconds = 0.0
	eq(slog.write(), "", "enabled but nothing played yet (only the title screen): writes nothing")
	check(slog.path().begins_with("user://sessions/") and slog.path().ends_with(".txt"), "real logs go to user://sessions (%s)" % slog.path())
	slog.free()


## P3: everything the log can hold, each list at its longest, still fits in 55 lines.
func test_a_full_log_stays_under_55_lines() -> void:
	var sim := SimWorld.new(10.0)
	var slog := SessionLog.new()
	slog.path_override = PATH
	slog.setup(sim)
	var st := sim.stats
	for i in 12:
		st.note_death("shambler", "day 1 10:00")
	for i in 40:
		st.note("thing %d" % i)
	st.note_built("wall")
	st.note_sound("gunshot", 90.0, "day 1")
	st.note_continuous("generator", 70.0, "day 1")
	for r: String in ["white", "blue", "yellow", "gold", "set"]:
		st.note_gear(r)
	for skill: String in sim.data.skills["order"]:
		st.note_level(skill, 2)
	st.note_perk_points(4)
	st.note_perk("soft_step")
	for g: String in ["Pistol", "Rifle", "Shotgun", "Old Pete's Deer Rifle"]:
		st.note_shot(g)
	for i in 9:
		st.note_away("North wall destroyed", "day 1 11:00")
	for i in 12:
		st.note_house("house %d" % i)
	var lines := slog.lines()
	check(lines.size() <= 55, "at most 55 lines (%d)" % lines.size())
	check("First five minutes:" in lines, "the first-five-minutes timeline is still there")
	slog.free()
