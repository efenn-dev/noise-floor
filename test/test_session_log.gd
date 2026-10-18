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
	var previous_slot_name := GameSession.current_slot_name
	GameSession.current_slot_name = "Dad"
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
	check("Save slot: Dad" in text, "the log names its save slot")
	check("World seed 1" in text, "the seed, since the game has no version string")
	check("Real time played: 1:05 (m:ss). Game time lived through: 0 d 0:0" in text, "real and game time played")
	check("Deaths: 1" in lines, "one death")
	check("  1. at 1:05 real (day 1 10:0" in text and "): killed by a shambler" in text, "what killed you, in plain words")
	check("Built 1 piece: 1 foundation." in lines, "what you built")
	check("  0:00 built a foundation" in lines, "the timeline")
	check("Wearing at the end: Melee: Pipe (white)." in lines, "what you wore at the end (P3)")
	check("Weapons: never fired or thrown." in lines and "Throws: none." in lines \
			and "Houses entered: 0." in lines, "the P3/V30 lines")
	DirAccess.remove_absolute(PATH)
	slog.queue_free()
	await tree.process_frame
	check(FileAccess.file_exists(PATH), "leaving the game writes it again")
	DirAccess.remove_absolute(PATH)
	GameSession.current_slot_name = previous_slot_name


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
func test_a_full_log_stays_under_60_lines() -> void:
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
	st.note_gear_equipped("Rare work boots")
	for g: String in ["Pistol", "Rifle", "Shotgun", "Old Pete's Deer Rifle"]:
		st.note_shot(g)
	for i in 9:
		st.note_away("North wall destroyed", "day 1 11:00")
	for i in 12:
		st.note_house("house %d" % i)
	st.perk_picks_offered = 3  # P12
	st.perk_picks_later = 2
	st.perk_picks_closed = 1
	st.note_goal("first night", 2, 4, "day 1 12:00")
	st.note_goal("first night", 4, 4, "day 2 06:10")
	st.note_goal("first night", 3, 4, "day 2 07:00")  # never goes backwards
	st.note_goal("defend your base", 1, 4, "day 2 09:00")
	st.build_menu_opens = 12
	st.build_menu_seconds = 250.0
	st.note_removed("hub")
	st.note_removed("hub")
	st.note_removed("door")
	st.remove_taps = 6
	var lines := slog.lines()
	check(lines.size() <= 58, "at most 58 lines (%d)" % lines.size())  # P12: two more lines (goals, the build menu)
	check("Perk points earned: 4, spent: 1 (soft step). Picks offered: 3 (Later 2, a zombie closed 1)." in lines, "perk points and picks are recorded")
	check("Goals: first night 4/4 (day 2 06:10); defend your base 1/4 (day 2 09:00)." in lines, "the goals line (%s)" % lines)
	check("Build menu: opened 12 times, 4:10 in it. Took down 3 pieces: 2 hub, 1 door. Right-click taps too short to take anything down: 6." in lines,
			"the build menu line")
	check(lines[2].contains("Difficulty: Normal"), "the header says the difficulty (%s)" % lines[2])
	check("Gear equipped: Rare work boots." in lines, "equipped gear is recorded")
	check("First five minutes:" in lines, "the first-five-minutes timeline is still there")
	slog.free()


func test_the_sim_notes_how_far_the_goals_got() -> void:
	var sim := SimWorld.new(10.0)
	sim.guidance.start(1)
	for i in SimWorld.TICK_RATE + 1:
		sim.step()
	check(sim.stats.goals.has("first night"), "the first-night chapter is noted once it's active")
	eq(int(sim.stats.goals["first night"]["step"]), 0, "at its first goal")
	sim.guidance.note_consumed(100.0, 100.0)
	sim.guidance.note_bed()
	for i in SimWorld.TICK_RATE + 1:
		sim.step()
	eq(int(sim.stats.goals["first night"]["step"]), 2, "two goals done: step 2 (%s)" % sim.stats.goals)
	check("day 1" in String(sim.stats.goals["first night"]["when"]), "with when")
	check(not sim.stats.goals.has("defend your base"), "a chapter that hasn't started isn't listed")
	var slog := SessionLog.new()
	slog.path_override = PATH
	slog.setup(sim)
	var said := false
	for l: String in slog.lines():
		said = said or l.begins_with("Goals: first night 2/4")
	check(said, "and the log says so")
	slog.free()
