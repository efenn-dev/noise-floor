extends "res://test/base_test.gd"
## S3: the build menu (B), the hotbar keys (1-9, 0) and the hotbar on the HUD, in the real game scene with
## keys fed through the viewport: B opens the menu, a click starts building that piece, a number key in the
## menu or in your pockets puts the thing on that key, a number key on foot builds or uses it, Esc stops
## building, and none of it works from a car.

const MAIN := "res://scenes/main.tscn"

var main: Node3D
var sim: SimWorld
var vp: Viewport


func _setup() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	main = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	sim = main.sim
	vp = main.get_viewport()


func _teardown() -> void:
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.pressed = pressed
		vp.push_input(ev)


func _last_message() -> String:
	return String(sim.messages[-1]["text"]) if not sim.messages.is_empty() else ""


func test_every_piece_is_in_the_menu_once_with_a_blurb() -> void:
	var listed := {}
	for g: Array in BuildMenu.GROUPS:
		for id: String in g[1]:
			check(not listed.has(id), "%s is listed once" % id)
			listed[id] = true
			check(id in BuildController.PIECES, "%s in the menu is a piece you can build" % id)
	for id: String in BuildController.PIECES:
		check(listed.has(id), "%s is in a group" % id)
		check(BuildMenu.BLURBS.has(id) and String(BuildMenu.BLURBS[id]).length() > 10, "%s has a blurb" % id)
		check(ResourceLoader.exists("res://assets/icons/piece_%s.png" % id), "%s has a picture (tools/art/piece_icons.gd)" % id)
	for g: Array in BuildMenu.GROUPS:
		check(BuildMenu.GROUP_NOTES.has(g[0]), "group %s has a note on how its pieces work" % g[0])
	var data := GameData.load_default()
	for id: String in data.buildables:
		if not data.buildables[id].get("player_placeable", true):
			check(not listed.has(id), "town piece %s is not in the menu" % id)


func test_b_opens_the_menu_and_a_click_starts_building() -> void:
	await _setup()
	var menu: BuildMenu = main.build_menu
	check(not menu.is_open(), "closed at start")
	_key(KEY_B)
	check(menu.is_open(), "B opens the build menu")
	await tree.process_frame  # _sync_player runs each frame
	check(main.player.frozen, "you stand still while it's open")
	for id: String in BuildController.PIECES:
		check(menu._buttons.has(id), "a button for %s" % id)
	_key(KEY_B)
	check(not menu.is_open(), "B closes it")
	_key(KEY_B)
	_key(KEY_ESCAPE)
	check(not menu.is_open() and not main.menus.is_open(), "Esc closes it without pausing")
	_key(KEY_B)
	menu.highlight("smelter")
	check("Smelter" in menu.details_text("smelter") and "loudness 60" in menu.details_text("smelter"), "details for the piece you point at")
	_key(KEY_5)
	eq(sim.hotbar.entry(4), "build:smelter", "5 in the menu puts the smelter on key 5")
	check("Smelter is on key 5" in _last_message(), "and says so (%s)" % _last_message())
	check("On key 5" in menu.details_text("smelter"), "the details say which key")
	menu.pick("wall")
	check(not menu.is_open(), "clicking a piece closes the menu")
	check(main.builder.active, "and starts build mode")
	eq(main.builder.piece(), "wall", "with that piece")
	check("B menu" in main.key_hint_text() and "Esc stop" in main.key_hint_text(), "the key hints say how to leave (%s)" % main.key_hint_text())
	_key(KEY_ESCAPE)
	check(not main.builder.active, "Esc stops building")
	check(not main.menus.is_open(), "without pausing")
	_key(KEY_ESCAPE)
	check(main.menus.is_open(), "Esc again pauses")
	main.menus.resume.emit()
	await _teardown()


func test_hotbar_keys_build_use_and_say_when_empty() -> void:
	await _setup()
	_key(KEY_1)
	check(main.builder.active, "1 on foot starts building")
	eq(main.builder.piece(), "foundation", "the foundation on key 1")
	_key(KEY_2)
	check(main.builder.active and main.builder.piece() == "wall", "2 switches to the wall")
	_key(KEY_2)
	check(not main.builder.active, "the same key again stops building")
	sim.player.food = 50.0
	sim.inventory.add("canned_food", 1)
	eq(sim.hotbar.assign(2, "item:canned_food"), "", "canned food on key 3")
	_key(KEY_3)
	check(sim.player.food > 85.0, "3 eats it (food %.0f)" % sim.player.food)
	eq(sim.inventory.count("canned_food"), 0, "it's gone")
	_key(KEY_3)
	check("don't have" in _last_message(), "pressing it with none left says so (%s)" % _last_message())
	sim.hotbar.clear(5)
	_key(KEY_6)
	check("Key 6 is empty" in _last_message(), "an empty key says how to fill it (%s)" % _last_message())
	check(not main.builder.active, "and builds nothing")
	# The HUD hotbar shows it all.
	var rows: PackedStringArray = main.hotbar_view.describe()
	eq(rows.size(), 10, "ten slots on the HUD")
	check(rows[0].begins_with("1 Foundation build afford"), "key 1: the foundation, affordable from the start crate (%s)" % rows[0])
	eq(rows[5], "6 -", "key 6 is empty")
	check(rows[9].begins_with("0 Bandage item x"), "key 0: bandages with a count (%s)" % rows[9])
	_key(KEY_1)
	rows = main.hotbar_view.describe()
	check(rows[0].ends_with("selected"), "the piece you're building is marked (%s)" % rows[0])
	_key(KEY_ESCAPE)
	# Nothing works from a car.
	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	eq(sim.enter_car("car_0"), "", "get in")
	main._enter_car("car_0")
	_key(KEY_1)
	check(not main.builder.active, "no building from the driver's seat")
	_key(KEY_B)
	check(not main.build_menu.is_open(), "no build menu either")
	main._exit_car()
	await _teardown()


func test_pockets_put_items_on_keys() -> void:
	await _setup()
	var inv: InventoryScreen = main.inventory_screen
	sim.inventory.add("canned_food", 2)
	sim.inventory.add("plank", 5)
	_key(KEY_TAB)
	check(inv.is_open(), "Tab opens your pockets")
	inv.select("canned_food", InventoryScreen.POCKETS)
	_key(KEY_4)
	eq(sim.hotbar.entry(3), "item:canned_food", "4 with food picked puts it on key 4")
	check("Canned food is on key 4" in _last_message(), "and says so (%s)" % _last_message())
	check(not main.builder.active, "the key went to the screen, not the hotbar")
	inv.select("plank", InventoryScreen.POCKETS)
	_key(KEY_4)
	eq(sim.hotbar.entry(3), "item:canned_food", "planks can't go on a key")
	check("Only food" in _last_message(), "it says why (%s)" % _last_message())
	inv.select("", InventoryScreen.POCKETS)
	eq(inv.assign_hotbar(0), "Click an item in your pockets first", "nothing picked")
	_key(KEY_TAB)
	check(not inv.is_open(), "closed")
	await _teardown()
