extends "res://test/base_test.gd"
## P3: the controls screen (F1) lists every registered action with a description, and the key hint line at
## the bottom shows only the keys that fit what you're doing, on one short line.

const MAIN := "res://scenes/main.tscn"


func _key(vp: Viewport, key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = pressed
		vp.push_input(ev)


func test_every_action_has_a_row() -> void:
	InputSetup.register()
	var described := {}
	for row: Array in HelpScreen.ROWS:
		check(row[0] in HelpScreen.GROUPS, "row '%s' is in a known group (%s)" % [row[3], row[0]])
		check(String(row[3]).strip_edges() != "", "row %s has a description" % [row[1]])
		check(HelpScreen.keys_for(row) != "", "row '%s' shows its keys" % row[3])
		for action: String in row[1]:
			check(InputMap.has_action(action), "'%s' in the help screen is a registered action" % action)
			described[action] = true
	for action: String in HelpScreen.registered_actions():
		check(described.has(action), "the help screen describes '%s'" % action)
	for group: String in HelpScreen.GROUPS:
		var in_columns := false
		for col: Array in HelpScreen.COLUMNS:
			in_columns = in_columns or group in col
		check(in_columns, "group '%s' has a column" % group)
	eq(HelpScreen.keys_for(["Game", ["quicksave"], "", "save"]), "F5", "keys come from InputSetup")
	eq(HelpScreen.keys_for(["Fight", ["attack"], "", "swing"]), "Left click", "mouse buttons by name")


func test_f1_opens_and_closes_it_in_game() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var vp := main.get_viewport()
	var help: HelpScreen = main.help_screen
	check(not help.is_open(), "closed at start")
	_key(vp, KEY_F1)
	check(help.is_open(), "F1 opens the controls screen")
	var text := help.text()
	for row: Array in HelpScreen.ROWS:
		check(("%s:  %s" % [HelpScreen.keys_for(row), row[3]]) in text, "it shows '%s'" % row[3])
	check(not main.get_tree().paused, "the game keeps running underneath")
	var guide := help.guide_text()  # S4
	for step: String in HelpScreen.GUIDE:
		check(step in guide, "the first-factory guide shows '%s'" % step.left(30))
	check("power" in guide and "E on the smelter" in guide, "it covers power and loading")
	_key(vp, KEY_F1)
	check(not help.is_open(), "F1 closes it")
	_key(vp, KEY_F1)
	_key(vp, KEY_ESCAPE)
	check(not help.is_open(), "Esc closes it too")
	check(not main.menus.is_open(), "without opening the pause menu")
	# From the title screen's Controls button, and back.
	main.menus.show_title(false)
	main.menus.help_requested.emit("title")
	check(help.is_open() and not main.menus.is_open(), "Controls on the title opens it over the title")
	help.close()
	check(main.menus.title_open(), "closing goes back to the title")
	main.menus.help_requested.emit("pause")
	help.close()
	check(main.menus.is_open() and not main.menus.title_open(), "from the pause menu, back to the pause menu")
	main.menus.hide_all()
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_key_hints_fit_the_moment() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var max_len: int = main.get_script().get_script_constant_map()["KEY_HINT_MAX"]
	main.player.set_look(0, 60)  # at the sky: nothing to use
	await tree.physics_frame
	main.interactor.update_target()
	var foot: String = main.key_hint_text()
	check("WASD move" in foot and "B build" in foot and foot.ends_with("F1 help"), "on foot: walking keys, F1 help last (%s)" % foot)
	check(not "LMB fire" in foot and not "R rotate" in foot, "no gun or build keys on foot")
	main._give_gun("pistol", false)
	var gun: String = main.key_hint_text()
	check(gun != foot, "the line changes when a gun is drawn")
	check("LMB fire" in gun and "R reload" in gun and "Q pipe" in gun, "gun keys (%s)" % gun)
	check(not "RMB zoom" in gun, "no zoom without a scope")
	main.builder.set_active(true)
	var build: String = main.key_hint_text()
	check("R rotate" in build and "LMB place" in build and "RMB remove" in build and "B menu" in build and "Esc stop" in build, "build keys (%s)" % build)
	check(not "WASD move" in build and not "LMB fire" in build, "and only those")
	main.builder.set_active(false)
	for line: String in [foot, gun, build]:
		check(line.length() <= max_len, "under %d characters (%d)" % [max_len, line.length()])
		check(not "\n" in line, "one line")
	# However much is offered, it stays one short line with F1 help on the end.
	var many := PackedStringArray()
	for i in 40:
		many.append("K%d something long" % i)
	var fitted: String = main.fit_key_hint(many)
	check(fitted.length() <= max_len and fitted.ends_with("F1 help"), "a crowded line is cut to fit (%d)" % fitted.length())
	eq(main.fit_key_hint(PackedStringArray(["E search", "E use", "T repair"])), "E search · T repair · F1 help", "one hint per key")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
