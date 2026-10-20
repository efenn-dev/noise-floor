extends "res://test/base_test.gd"
## M12: the skills screen (K) shows every skill's level and the perk trees, and its buttons spend
## points through Skills.spend. P13: the trees are rows of picture nodes with arrows (test_the_tree_...).

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
	eq(screen.node_state("soft_step"), "max", "and shows it as maxed")
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


func test_the_tree_shows_rows_arrows_glow_and_a_reset() -> void:
	# P13: three rows a tree, opened by points in that tree; arrows from the perk above; a glow on what you can
	# afford; a once-a-day reset; the quiet-moment prompt opens it with a banner and Later.
	var sim := SimWorld.new(10.0)
	var screen := SkillsScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	eq(screen._nodes.size(), sim.data.skills["perks"].size(), "a node per perk (%d)" % screen._nodes.size())
	for perk: String in screen._nodes:
		check((screen._nodes[perk]["pic"] as TextureRect).texture != null, "%s has a picture" % perk)
	eq(screen.node_state("fast_lines"), "open", "no points: a row-1 perk is open but not affordable")
	eq(screen.node_state("cheap_repairs"), "locked_row", "a row-2 perk waits for 3 points in the tree")
	check((screen._gates["engineer"][0] as Label).visible and "3 points in Engineer" in (screen._gates["engineer"][0] as Label).text,
			"and the row says so (%s)" % (screen._gates["engineer"][0] as Label).text)
	sim.skills.perk_points = 10
	screen.refresh()
	eq(screen.node_state("fast_lines"), "available", "with points, a row-1 perk glows")
	eq(screen.node_state("cheap_repairs"), "locked_row", "a locked row doesn't")
	check(screen.perk_button("cheap_repairs").disabled, "and can't be clicked")
	var links: SkillsScreen.TreeLinks = screen._tree_links["engineer"]
	check(links.arrows().has(["tuned_machines", "cheap_repairs"]), "an arrow runs from Tuned Machines to Cheap Repairs (%s)" % [links.arrows()])
	for i in 3:
		screen.spend("fast_lines")
	eq(sim.skills.tree_points("engineer"), 3, "three points in Engineer")
	check(not (screen._gates["engineer"][0] as Label).visible, "row 2 is open")
	eq(screen.node_state("cheap_repairs"), "locked_arrow", "but Cheap Repairs still wants a point in Tuned Machines")
	eq(screen.node_state("pack_mule"), "available", "while Pack Mule, with no arrow, glows")
	screen.spend("tuned_machines")
	eq(screen.node_state("cheap_repairs"), "available", "a point in Tuned Machines: Cheap Repairs glows")
	check("Needs 6 points in Engineer" in screen.details_text("careful_hands"), "the words say what row 3 needs (%s)" % screen.details_text("careful_hands"))
	screen.hovered = "dampened_gears"
	screen.refresh()
	check("Synergy: every 3 points in Ghost" in screen._details.text, "a synergy is spelled out (%s)" % screen._details.text)
	# Taking the points back: once a game day.
	check(not (screen._resets["engineer"] as Button).disabled, "the tree has points: the reset button works")
	screen.reset("engineer")
	eq(sim.skills.tree_points("engineer"), 0, "every point out of Engineer")
	eq(sim.skills.perk_points, 10, "and back in your pocket")
	eq(sim.stats.perk_resets, 1, "the log counts it")
	screen.spend("heavy_swing")
	check((screen._resets["fighter"] as Button).disabled, "a second reset today is greyed")
	screen.reset("fighter")
	eq(sim.skills.tree_points("fighter"), 1, "and does nothing")
	sim.clock.day += 1
	screen.refresh()
	check(not (screen._resets["fighter"] as Button).disabled, "tomorrow it's back")
	# The prompt.
	screen.close()
	screen.open_prompt()
	check(screen.is_open() and screen.prompted and screen._prompt.visible, "the quiet-moment pick opens the tree with its banner")
	check(screen.hovered != "" and sim.skills.can_spend(screen.hovered) == "", "pointing at something you can take (%s)" % screen.hovered)
	screen.later()
	check(not screen.is_open() and sim.stats.perk_picks_later == 1, "Later closes it and is counted")
	check(sim.perk_snooze_until > sim.clock_hours() + 1.0, "and puts it off a while")
	sim.perk_snooze_until = 0.0
	screen.open_prompt()
	screen.close_for("zombie")
	check(not screen.is_open() and sim.stats.perk_picks_closed == 1, "a zombie closing it is counted")
	screen.open()
	check(not screen._prompt.visible, "K's own open has no banner")
	screen.close()
	eq(sim.stats.perk_picks_later, 1, "and closing it isn't Later")
	screen.free()


func test_fits_a_1280x720_window_with_six_perks_a_tree() -> void:
	# P2: with six Fighter perks the trees sit side by side, each wrapping its text to its column and
	# scrolling if the window is short, so nothing overlaps or runs off a 1280x720 window. P13: nine, as nodes.
	var old_size := tree.root.size
	tree.root.size = Vector2i(1280, 720)
	var sim := SimWorld.new(10.0)
	var screen := SkillsScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	for i in 3:
		await tree.process_frame
	var trees: Dictionary = sim.data.skills["trees"]
	check(trees["fighter"]["perks"].size() >= 9, "Fighter has nine perks (%d)" % trees["fighter"]["perks"].size())
	var view := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var panel := screen.panel_rect()
	check(view.encloses(panel), "the panel fits the window (%s)" % panel)
	var columns: Array[Rect2] = []
	for t: String in trees:
		var sc := screen.tree_scroll(t)
		var r := sc.get_global_rect()
		check(panel.encloses(r), "the %s column sits inside the panel" % t)
		for other: Rect2 in columns:
			check(not r.intersects(other), "the %s column doesn't overlap another tree" % t)
		columns.append(r)
		var rows: Array[Rect2] = []
		for p: String in trees[t]["perks"]:
			var row := screen.perk_row(p)
			check(row.size.x <= sc.size.x + 0.5, "%s fits its column's width (%.0f <= %.0f)" % [p, row.size.x, sc.size.x])
			check(screen.perk_button(p).size.y >= 60.0, "%s has a full-size node" % p)
			var rr := row.get_global_rect()
			check(sc.get_global_rect().grow(2.0).encloses(rr) or rr.position.y >= sc.get_global_rect().position.y,
					"%s sits in its column (scrolls if need be)" % p)
			for other: Rect2 in rows:
				check(not rr.grow(-1.0).intersects(other.grow(-1.0)), "%s doesn't overlap another node" % p)
			rows.append(rr)
	var skills_rect := screen._skills_scroll.get_global_rect()
	check(panel.encloses(skills_rect), "the skills column sits inside the panel")
	for r: Rect2 in columns:
		check(not skills_rect.intersects(r), "the skills column doesn't overlap the trees")
	tree.root.size = Vector2i(1600, 900)
	await tree.process_frame
	await tree.process_frame
	check(screen._skills_scroll.get_global_rect().size.y > skills_rect.size.y, "a taller window gives the skills column more room")
	check(screen.tree_scroll("fighter").size.y >= SkillsScreen.TREE_H - 1.0, "and the trees their full three rows")
	screen.queue_free()
	tree.root.size = old_size
	await tree.process_frame
