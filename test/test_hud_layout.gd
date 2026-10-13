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
	main.get_window().size = was_size
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
