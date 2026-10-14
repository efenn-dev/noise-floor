extends "res://test/base_test.gd"
## Q2: the heat warning has its own line under the materials block (tour tile 06 showed "The noise is being
## noticed" on the carry-weight line). With text in all three, the heat warning, the materials block and
## the top messages never overlap, at the default window size and at 1280x720.

const MAIN := "res://scenes/main.tscn"


func _rect(l: Label) -> Rect2:
	return l.get_global_rect()


func test_heat_warning_materials_and_messages_do_not_overlap() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var was_size: Vector2i = main.get_window().size
	for item: String in ["scrap_metal", "iron_ingot", "iron_plate", "nails", "bandage", "canned_food"]:
		if sim.data.items.has(item):
			sim.inventory.add(item, 5)
	sim.add_message("The smelter needs fuel", 30.0)
	sim.add_message("Found Scrap Metal x3, Nails x10", 30.0)
	# Q5: the longest real message (tour tile 06 ran it under the clock and the pockets)
	sim.add_message("Smelter placed. It needs power: a generator (E loads gas cans) or a solar panel, and a power pole within 12 m", 30.0)
	for level in ["wanderers_at", "group_at", "horde_at"]:
		sim.director.heat = float(sim.director.cfg[level]) + 5.0
		for size: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:  # the default window, and a small one
			main.get_window().size = size
			for i in 3:
				await tree.process_frame
			var heat: Label = main._heat_label
			var mats: Label = main._materials_hud
			var msgs: Label = main._message_label
			check(heat.text != "" and mats.text != "" and msgs.text != "", "%s: all three have text" % level)
			var h := _rect(heat)
			var m := _rect(mats)
			var n := _rect(msgs)
			var where := "%s at %s: heat %s, materials %s, messages %s" % [level, main.get_viewport().get_visible_rect().size, h, m, n]
			check(not h.intersects(m), "heat warning clear of the materials block (%s)" % where)
			check(not h.intersects(n), "heat warning clear of the messages (%s)" % where)
			check(not m.intersects(n), "materials block clear of the messages (%s)" % where)
			check(h.position.y >= m.end.y, "heat warning on its own line under the materials (%s)" % where)
			for corner: Label in [main._hud, main._build_label]:
				check(not _rect(corner).intersects(n), "Q5: messages clear of the top-left text %s (%s)" % [_rect(corner), where])
			check(n.position.x >= 0.0 and n.end.x <= main.get_viewport().get_visible_rect().size.x, "Q5: messages on screen (%s)" % where)
			# S3: the hotbar along the bottom keeps clear of the health line, the key hints and the look-at text.
			var bar: Rect2 = main.hotbar_view.get_global_rect()
			var health := _rect(main._health_label)
			var keys := _rect(main._keys_label)
			var look := _rect(main._interact_label)
			check(bar.size.x > 600.0 and bar.size.y > 50.0, "the hotbar is drawn (%s)" % bar)
			check(not bar.intersects(health), "hotbar clear of the health line (%s vs %s at %s)" % [bar, health, size])
			check(not bar.intersects(keys), "hotbar clear of the key hints (%s vs %s at %s)" % [bar, keys, size])
			check(not bar.intersects(look), "hotbar clear of the look-at text (%s vs %s at %s)" % [bar, look, size])
			check(bar.end.y <= main.get_viewport().get_visible_rect().size.y, "hotbar on screen at %s" % size)
	main.get_window().size = was_size
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


## S3: a new game's first hints sit above the hotbar, not on it.
func test_first_game_hints_sit_above_the_hotbar() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = false
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	check(main.hints != null and main.hints.visible, "a new game shows its hints")
	var hints: Rect2 = main.hints.get_global_rect()
	var bar: Rect2 = main.hotbar_view.get_global_rect()
	check(not hints.intersects(bar), "hints clear of the hotbar (%s vs %s)" % [hints, bar])
	check(hints.end.y <= bar.position.y, "hints above the hotbar (%s vs %s)" % [hints, bar])
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
