extends "res://test/base_test.gd"
## M12: the skills screen (K) shows every skill's level and the perk trees, and its buttons spend
## points through Skills.spend.

const MAIN := "res://scenes/main.tscn"


func _key(vp: Viewport, key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = pressed
		vp.push_input(ev)


func test_shows_levels_and_spends_points() -> void:
	var sim := SimWorld.new(10.0)
	sim.skills.xp["strength"] = float(sim.data.skills["levels"][2])
	var screen := SkillsScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	check(not screen.is_open(), "starts closed")
	screen.open()
	check(screen.is_open(), "opens")
	eq(screen.skill_text("strength"), "Strength 2", "shows Strength's level")
	eq(screen.skill_text("fitness"), "Fitness 0", "and the others")
	check(screen.skill_text("firearms").begins_with("Firearms"), "Firearms is listed (greyed out)")
	eq(screen.perk_text("soft_step"), "Soft Step 0/5", "a perk at rank 0")
	check(screen.perk_button("soft_step").disabled, "no points: the button is greyed")
	sim.skills.perk_points = 1
	screen.refresh()
	check(not screen.perk_button("soft_step").disabled, "a point: the button works")
	var said := []
	screen.message.connect(func(t: String) -> void: said.append(t))
	screen.perk_button("soft_step").pressed.emit()
	eq(sim.skills.rank("soft_step"), 1, "pressing it spends the point")
	eq(screen.perk_text("soft_step"), "Soft Step 1/5", "and the rank shown changes")
	eq(said, ["Soft Step rank 1"], "it says so")
	check(screen.perk_button("soft_step").disabled, "no points left: greyed again")
	sim.skills.perks["soft_step"] = 5
	sim.skills.perk_points = 3
	screen.refresh()
	check(screen.perk_button("soft_step").disabled, "greyed at rank 5")
	eq(screen.perk_button("soft_step").text, "MAX", "and says so")
	screen.close()
	check(not screen.is_open(), "closes")
	screen.free()


func test_k_opens_it_in_the_game_and_esc_closes() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var vp := main.get_viewport()
	var screen: SkillsScreen = main.skills_screen
	check(not screen.is_open(), "closed at the start")
	_key(vp, KEY_K)
	check(screen.is_open(), "K opens the skills screen")
	await tree.process_frame
	check(main.player.frozen, "the player can't walk while it's open")
	var ticks: int = main.sim.ticks
	for i in 6:
		await tree.process_frame
	check(main.sim.ticks > ticks, "the game keeps running")
	_key(vp, KEY_ESCAPE)
	check(not screen.is_open(), "Esc closes it")
	check(not main.menus.is_open(), "without opening the pause menu")
	_key(vp, KEY_K)
	check(screen.is_open(), "K again opens it")
	_key(vp, KEY_K)
	check(not screen.is_open(), "and K closes it")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
