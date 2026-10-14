extends "res://test/base_test.gd"
## The inventory screen: shows your pockets and the crate within reach, and its clicks move, use and
## drop through the sim's rules.

const N := BuildGrid.Side.NORTH

var sim: SimWorld
var screen: InventoryScreen
var crate_key := ""


func _setup() -> void:
	sim = SimWorld.new(10.0)
	sim.inventory.add("plank", 40)
	sim.inventory.add("nails", 40)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("storage", Vector2i(0, 0), BuildGrid.Side.WEST, sim.inventory)
	crate_key = sim.build.key_for("storage", Vector2i(0, 0))
	sim.inventory.give_all({"chips": 3, "clean_water": 2, "hiking_pack": 1})
	sim.player_pos = sim.build.piece_center(crate_key) + Vector3(1.0, 0, 0)
	screen = InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)


func _teardown() -> void:
	screen.free()


func _slots(grid_owner_side: String) -> int:
	var grids := screen.find_children("*", "GridContainer", true, false)
	var grid: GridContainer = grids[0] if grid_owner_side == InventoryScreen.POCKETS else grids[1]
	var live := 0
	for c in grid.get_children():
		if not c.is_queued_for_deletion():
			live += 1
	return live


func test_shows_pockets_and_the_crate() -> void:
	_setup()
	check(not screen.is_open(), "starts closed")
	screen.open()
	check(screen.is_open(), "Tab opens it")
	check(screen.crate() == sim.storages[crate_key], "the crate within reach is on the right")
	eq(_slots(InventoryScreen.POCKETS), sim.inventory.items().size(), "a slot per item in your pockets")
	eq(_slots(InventoryScreen.CRATE), 0, "the crate starts empty")
	screen.close()
	check(not screen.is_open(), "and closes")
	_teardown()


func test_shift_click_moves_the_stack_and_back() -> void:
	_setup()
	screen.open()
	screen.move("chips", InventoryScreen.POCKETS, true)
	eq([sim.inventory.count("chips"), screen.crate().count("chips")], [0, 3], "the whole stack went into the crate")
	screen.move("chips", InventoryScreen.CRATE, false)
	eq([sim.inventory.count("chips"), screen.crate().count("chips")], [1, 2], "ctrl-click brings one back")
	_teardown()


func test_use_and_drop_from_the_screen() -> void:
	_setup()
	screen.open()
	sim.player.water = 40.0
	screen.select("clean_water", InventoryScreen.POCKETS)
	screen.use_selected()
	eq(sim.inventory.count("clean_water"), 1, "drank one")
	check(sim.player.water > 40.0, "and you're less thirsty")
	var bags := sim.bags.size()
	screen.select("plank", InventoryScreen.POCKETS)
	screen.drop_selected(true)
	eq(sim.inventory.count("plank"), 0, "dropped all the planks")
	eq(sim.bags.size(), bags + 1, "into a bag at your feet")
	_teardown()


func test_no_crate_in_reach() -> void:
	_setup()
	sim.player_pos = Vector3(60, 0, 60)
	screen.open()
	check(screen.crate() == null, "nothing on the right")
	var messages := []
	screen.message.connect(func(t: String) -> void: messages.append(t))
	screen.move("chips", InventoryScreen.POCKETS, true)
	eq(sim.inventory.count("chips"), 3, "nothing moves")
	eq(messages, ["No crate within reach"], "and it says why")
	_teardown()


func test_bag_raises_the_limit_shown() -> void:
	_setup()
	screen.open()
	near(sim.carry_limit(), float(sim.data.survival["carry_base"]), "a bag in pockets gives no capacity")
	eq(sim.equip_bag("hiking_pack"), "Equipped Hiking pack", "equip it from the screen's rule")
	near(sim.carry_limit(), float(sim.data.survival["carry_base"]) + sim.data.item_value("hiking_pack", "bag"),
			"the worn hiking pack adds to what you can carry")
	_teardown()


## M13: a gear piece shows in your pockets in its rarity colour; clicking it shows its stats, and the
## Equip button puts it on (the paper doll then shows it, in colour).
func test_gear_piece_in_colour_and_equip_on_click() -> void:
	_setup()
	var piece := sim.gear.make("hard_hat", "civilian", "yellow", {"carry_kg": 8.0, "strength": 1.0, "durability": 0.2}, 0.7, "Grim Lid")
	sim.gear.pieces.append(piece)
	screen.open()
	var tile: Button = screen.find_child("Gear%d" % piece["uid"], true, false)
	check(tile != null, "the piece has a tile in your pockets")
	var icon: Panel = tile.get_child(0)
	var style: StyleBoxFlat = icon.get_theme_stylebox("panel")
	eq(style.border_color, sim.gear.color(piece), "drawn in its rarity colour")
	var picture := icon.find_child("Icon", true, false) as TextureRect
	var placeholder := icon.find_child("Placeholder", true, false) as Label
	if InventoryScreen.icon_for("hard_hat") != null:
		check(picture != null and picture.texture != null, "with the base's icon when one exists")
	else:
		eq(placeholder.text, "H", "otherwise with its base's first letter")
	eq((tile.get_child(1) as Label).text, "70%", "and its condition")
	tile.pressed.emit()
	var details := screen.find_children("*", "Label", true, false).filter(
			func(l: Label) -> bool: return l.text.begins_with("Grim Lid"))
	eq(details.size(), 1, "clicking shows its details")
	eq(details[0].get_theme_color("font_color"), Color.from_string("#ffe85a", Color.WHITE), "the name in yellow")
	check("+8 kg carry" in details[0].text and "Rare" in details[0].text and "Good 70%" in details[0].text,
			"its rarity, condition and stats")
	var limit := sim.carry_limit()
	var equip: Button = _button("Equip")
	check(equip != null and _button("Drop") != null, "Equip and Drop buttons")
	check(_button("Repair (1 kit)") == null, "no Repair without a kit")
	equip.pressed.emit()
	eq(sim.gear.equipped.get("head", {}).get("uid"), piece["uid"], "Equip puts it on")
	near(sim.carry_limit(), limit + 8.0 + 3.0, "+8 kg and +1 Strength (3 kg) now count")
	var row: Button = screen.find_child("Slot_head", true, false)
	check(row.tooltip_text.begins_with("Grim Lid"), "the paper doll shows it")
	eq(row.get_theme_color("font_color"), sim.gear.color(piece), "in colour")
	sim.inventory.add("repair_kit", 1)
	screen.refresh()
	_button("Repair (1 kit)").pressed.emit()
	near(piece["condition"], 1.0, "Repair with a kit")
	_button("Unequip").pressed.emit()
	check(not sim.gear.equipped.has("head"), "Unequip takes it off")
	(screen.find_child("Gear%d" % piece["uid"], true, false) as Button).pressed.emit()
	_button("Drop").pressed.emit()
	eq(sim.bags.size(), 1, "Drop puts it in a bag at your feet")
	var weapon: Button = screen.find_child("Slot_weapon", true, false)
	check(weapon.tooltip_text.begins_with("Pipe"), "the melee tile holds the pipe")
	_teardown()


func _button(text: String) -> Button:
	for b: Button in screen.find_children("*", "Button", true, false):
		if b.text == text and not b.is_queued_for_deletion():
			return b
	return null
