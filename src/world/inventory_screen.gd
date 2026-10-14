class_name InventoryScreen
extends CanvasLayer
## Tab: your pockets beside the nearest storage crate within reach. Click an item to see it and use,
## move or drop it; shift-click moves the whole stack to the other side, ctrl-click moves one.
## The game keeps running (a zombie can walk up while you sort). The rules are in the sim
## (use_item, drop_items, Inventory.move_to, crates_near); this only shows them.
## M13/V14 slots: gear pieces sit after the stacks; the center paper doll shows every equipped slot.

class CharacterSilhouette:
	extends Control

	func _draw() -> void:
		var ink := Color(0.42, 0.43, 0.46, 0.32)
		draw_circle(Vector2(164, 48), 28.0, ink)
		draw_rect(Rect2(136, 77, 56, 112), ink, true)
		draw_line(Vector2(137, 96), Vector2(87, 170), ink, 20.0, true)
		draw_line(Vector2(191, 96), Vector2(241, 170), ink, 20.0, true)
		draw_line(Vector2(150, 184), Vector2(132, 276), ink, 24.0, true)
		draw_line(Vector2(178, 184), Vector2(196, 276), ink, 24.0, true)

signal message(text: String)

const SLOT := Vector2(78, 78)
const COLS := 4
const POCKETS := "pockets"
const CRATE := "crate"
const WORN := "worn"
const GEAR := "gear:"  # a selected gear piece is "gear:<uid>"
const BAG := "bag:"    # the worn stackable bag is "bag:<item>"
const SLOT_NAMES := {"weapon": "Melee", "head": "Head", "body": "Body", "hands": "Hands", "legs": "Legs",
		"feet": "Feet", "back": "Back", "light": "Light", "primary": "Primary", "sidearm": "Sidearm",
		"part": "Firearm part"}
const DOLL_SIZE := Vector2(328, 382)
const SLOT_RECTS := {
		"head": Rect2(128, 5, 72, 68), "body": Rect2(128, 83, 72, 72),
		"hands": Rect2(38, 100, 72, 72), "legs": Rect2(128, 166, 72, 72),
		"feet": Rect2(128, 249, 72, 68), "back": Rect2(218, 100, 72, 72),
		"light": Rect2(218, 17, 72, 68), "weapon": Rect2(4, 326, 76, 54),
		"primary": Rect2(89, 326, 128, 54), "sidearm": Rect2(226, 326, 98, 54),
}

static var _icons: Dictionary = {}

var sim: SimWorld
var _root: Control
var _pockets_grid: GridContainer
var _crate_grid: GridContainer
var _crate_title: Label
var _crate_prev: Button
var _crate_next: Button
var _weight_label: Label
var _weight_bar: ProgressBar
var _details: Label
var _wearing: Control
var _actions: HBoxContainer
var _crates: Array = []  # crate keys within reach, nearest first
var _crate_index := 0
var _selected := ""
var _selected_side := ""


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_crates = sim.crates_near(sim.player_pos)
	_crate_index = 0
	_selected = ""
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The crate on the right, or null if none is within reach.
func crate() -> Inventory:
	if _crates.is_empty():
		return null
	return sim.storages.get(_crates[_crate_index])


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("free_mouse"):
		close()
		get_viewport().set_input_as_handled()
		return
	var slot := InputSetup.hotbar_slot(event)
	if slot != -1:
		message.emit(assign_hotbar(slot))  # S3: 1-9, 0 puts the picked item on that key
		get_viewport().set_input_as_handled()


## S3: puts the selected pocket item on hotbar key `i` (0-9). Returns the message shown.
func assign_hotbar(i: int) -> String:
	if _selected == "" or _selected_side != POCKETS or _selected.begins_with(GEAR):
		return "Click an item in your pockets first"
	var why := sim.hotbar.assign(i, Hotbar.item_entry(_selected))
	refresh()
	return why if why != "" else "%s is on key %s" % [_name(_selected), Hotbar.key_name(i)]


# --- What the clicks do (tests call these directly) ---------------------------

func select(item: String, side: String) -> void:
	_selected = item
	_selected_side = side
	refresh()


## Moves one or the whole stack of `item` from `side` to the other side.
func move(item: String, side: String, whole_stack: bool) -> void:
	var from := sim.inventory if side == POCKETS else crate()
	var to := crate() if side == POCKETS else sim.inventory
	if from == null or to == null:
		message.emit("No crate within reach")
		return
	from.move_to(to, item, from.count(item) if whole_stack else 1)
	refresh()


## M13: selects a gear piece (in your pockets, or WORN).
func select_gear(uid: int, side: String = POCKETS) -> void:
	select(GEAR + str(uid), side)


func select_bag(item: String) -> void:
	select(BAG + item, WORN)


func selected_gear() -> Dictionary:
	return sim.gear.find(int(_selected.trim_prefix(GEAR))) if _selected.begins_with(GEAR) else {}


func equip_selected() -> void:
	message.emit(sim.equip_gear(int(_selected.trim_prefix(GEAR))))
	_selected_side = WORN
	refresh()


func equip_bag_selected() -> void:
	message.emit(sim.equip_bag(_selected))
	refresh()


func unequip_selected() -> void:
	var piece := selected_gear()
	if not piece.is_empty():
		message.emit(sim.unequip_gear(sim.gear.slot_of(piece)))
		_selected_side = POCKETS
	refresh()


func repair_selected() -> void:
	message.emit(sim.repair_gear(int(_selected.trim_prefix(GEAR))))
	refresh()


func drop_gear_selected() -> void:
	message.emit(sim.drop_gear(int(_selected.trim_prefix(GEAR))))
	refresh()


func use_selected() -> void:
	message.emit(sim.use_item(_selected))
	refresh()


func drop_selected(whole_stack: bool) -> void:
	message.emit(sim.drop_items(_selected, sim.inventory.count(_selected) if whole_stack else 1))
	refresh()


func _on_slot(item: String, side: String) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		move(item, side, true)
	elif Input.is_key_pressed(KEY_CTRL):
		move(item, side, false)
	else:
		select(item, side)


## Marks a double-click as used; tests drive these handlers on a screen that isn't in the tree.
func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_item_input(event: InputEvent, item: String, side: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click \
			and side == POCKETS and sim.data.item_value(item, "bag") > 0.0:
		message.emit(sim.equip_bag(item))
		refresh()
		_handled()


func _on_gear_input(event: InputEvent, uid: int, side: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if side == WORN:
			var piece := sim.gear.find(uid)
			if not piece.is_empty():
				message.emit(sim.unequip_gear(sim.gear.slot_of(piece)))
		else:
			message.emit(sim.equip_gear(uid))
		refresh()
		_handled()


func _on_equipment_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		message.emit(sim.unequip_gear(slot))
		refresh()
		_handled()


# --- Drawing -------------------------------------------------------------------

func refresh() -> void:
	if sim == null:
		return
	var box := crate()
	_fill(_pockets_grid, sim.inventory, POCKETS)
	_fill(_crate_grid, box, CRATE)
	if box == null:
		_crate_title.text = "No crate within reach"
	elif _crates.size() > 1:
		_crate_title.text = "Crate %d of %d" % [_crate_index + 1, _crates.size()]
	else:
		_crate_title.text = "Crate"
	_crate_prev.visible = _crates.size() > 1
	_crate_next.visible = _crates.size() > 1

	var carried := sim.carried_kg()
	var limit := sim.carry_limit()
	_weight_bar.max_value = limit
	_weight_bar.value = minf(carried, limit)
	var bag := str(sim.gear.equipped.get("back", ""))
	_weight_label.text = "Carrying %.1f / %.0f kg" % [carried, limit] \
			+ ("   (wearing %s +%d kg)" % [sim.data.item_name(bag), sim.data.item_value(bag, "bag")] if bag != "" else "")
	var over := carried > limit
	_weight_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if over else Color(0.9, 0.9, 0.85))
	_weight_bar.modulate = Color(1.0, 0.4, 0.3) if over else (Color(1.0, 0.85, 0.4) if carried > limit * 0.8 else Color.WHITE)
	if over:
		_weight_label.text += "   Overloaded: slower and louder"
	var mech := sim.skills.progress("mechanics")
	_weight_label.text += "
Mechanics %d%s" % [sim.skills.level("mechanics"),
			("  (%d / %d xp to the next level)" % [mech[0], mech[1]]) if mech[1] > 0 else ""]

	_fill_wearing()
	if _selected.begins_with(BAG):
		var worn := _selected.trim_prefix(BAG)
		if str(sim.gear.equipped.get("back", "")) != worn:
			_selected = ""
		_show_bag(worn)
		return
	if _selected.begins_with(GEAR):
		var piece := selected_gear()
		if piece.is_empty() or sim.gear.is_equipped(piece["uid"]) != (_selected_side == WORN):
			_selected = ""  # dropped, or moved between pockets and slots
		_show_gear(piece)
		return
	var held := sim.inventory if _selected_side == POCKETS else box
	if _selected != "" and (held == null or held.count(_selected) == 0):
		_selected = ""  # used up or moved away
	_show_details(held)


func _fill(grid: GridContainer, inv: Inventory, side: String) -> void:
	for child in grid.get_children():
		child.queue_free()
	if inv == null:
		return
	for item: String in inv.items():
		grid.add_child(_slot(item, inv.count(item), side))
	if side == POCKETS:
		for piece: Dictionary in sim.gear.pieces:
			grid.add_child(_gear_slot(piece))


## A carried gear tile: base icon when available, rarity border, and condition in the corner.
func _gear_slot(piece: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == POCKETS
	b.tooltip_text = piece["name"]
	b.name = "Gear%d" % piece["uid"]
	var icon := gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], SLOT - Vector2(16, 16), piece["base"])
	icon.position = Vector2(8, 8)
	b.add_child(icon)
	var n := Label.new()
	n.text = "%d%%" % roundi(float(piece["condition"]) * 100.0)
	n.position = SLOT - Vector2(52, 28)
	n.size = Vector2(46, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 16)
	n.add_theme_constant_override("outline_size", 6)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if not sim.gear.working(piece) else Color.WHITE)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	b.pressed.connect(select_gear.bind(int(piece["uid"]), POCKETS))
	b.gui_input.connect(_on_gear_input.bind(int(piece["uid"]), POCKETS))
	return b


## Gear icon with a rarity border: use the base's picture when it exists, otherwise its first letter.
static func gear_icon(color: Color, base_name: String, size: Vector2, item_id: String = "") -> Control:
	var panel := Panel.new()
	panel.size = size
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(size.x * 0.18))
	panel.add_theme_stylebox_override("panel", style)
	var texture := icon_for(item_id)
	if texture != null:
		var picture := TextureRect.new()
		picture.name = "Icon"
		picture.texture = texture
		picture.position = Vector2(4, 4)
		picture.size = size - Vector2(8, 8)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(picture)
	else:
		var letter := Label.new()
		letter.name = "Placeholder"
		letter.text = base_name.left(1).to_upper()
		letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", int(size.y * 0.5))
		letter.add_theme_color_override("font_color", color)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(letter)
	return panel


## Paper doll: a positioned tile for every equipment slot, with firearms in the row underneath.
func _fill_wearing() -> void:
	for child in _wearing.get_children():
		if child is Button:
			_wearing.remove_child(child)  # now, so the new row can take its name
			child.queue_free()
	for slot: String in sim.gear.slots():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.name = "Slot_" + slot
		var rect: Rect2 = SLOT_RECTS[slot]
		b.position = rect.position
		b.size = rect.size
		b.custom_minimum_size = rect.size
		b.add_theme_font_size_override("font_size", 14 if slot in ["primary", "sidearm"] else 15)
		var value: Variant = sim.gear.equipped.get(slot)
		if value == null:
			b.text = SLOT_NAMES[slot]
			b.modulate = Color(1, 1, 1, 0.38)
			b.disabled = true
		elif slot == "back":
			var item := str(value)
			b.tooltip_text = sim.data.item_name(item)
			var icon := gear_icon(sim.data.item_color(item), SLOT_NAMES[slot], rect.size - Vector2(10, 10), item)
			icon.position = Vector2(5, 5)
			b.add_child(icon)
			b.toggle_mode = true
			b.button_pressed = _selected == BAG + item
			b.pressed.connect(select_bag.bind(item))
			b.gui_input.connect(_on_equipment_input.bind(slot))
		else:
			var piece: Dictionary = value
			b.add_theme_color_override("font_color", sim.gear.color(piece))
			b.add_theme_color_override("font_hover_color", sim.gear.color(piece).lightened(0.3))
			b.tooltip_text = "%s · %s" % [piece["name"], sim.gear.condition_text(piece)]
			b.toggle_mode = true
			b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == WORN
			b.pressed.connect(select_gear.bind(int(piece["uid"]), WORN))
			b.gui_input.connect(_on_gear_input.bind(int(piece["uid"]), WORN))
			var icon := gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], rect.size - Vector2(10, 10), piece["base"])
			icon.position = Vector2(5, 5)
			b.add_child(icon)
			var condition := ColorRect.new()
			condition.name = "Condition"
			condition.color = Color(0.35, 0.9, 0.4) if float(piece["condition"]) >= 0.6 else Color(1.0, 0.7, 0.2)
			condition.position = Vector2(5, rect.size.y - 7)
			condition.size = Vector2((rect.size.x - 10) * float(piece["condition"]), 3)
			condition.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(condition)
		_wearing.add_child(b)


func _show_bag(item: String) -> void:
	for child in _actions.get_children():
		child.queue_free()
	if item == "" or _selected == "":
		_details.text = "Click an item to see it.  Double-click gear or a bag to equip it."
		return
	_details.remove_theme_color_override("font_color")
	_details.text = "%s\nBack slot · %.1f kg · +%d kg carrying capacity" % [sim.data.item_name(item),
			sim.data.item_weight(item), sim.data.item_value(item, "bag")]
	_action("Unequip", unequip_bag_selected)


func unequip_bag_selected() -> void:
	message.emit(sim.unequip_gear("back"))
	_selected = ""
	refresh()


## The details for a gear piece: its name in the rarity colour, what it is, its condition and stats.
func _show_gear(piece: Dictionary) -> void:
	for child in _actions.get_children():
		child.queue_free()
	if piece.is_empty() or _selected == "":
		_details.remove_theme_color_override("font_color")
		_details.text = "Click for details.  Double-click gear or a bag to equip it.  Shift-click moves a stack."
		return
	var g := sim.gear
	var rarity: Dictionary = sim.data.gear["rarities"][piece["rarity"]]
	var tier: Dictionary = sim.data.gear["tiers"][piece["tier"]]
	var lines := [piece["name"], "%s · %s %s · %s slot · %.1f kg · %s" % [rarity["name"], tier["name"],
			g.base_of(piece)["name"].to_lower(), SLOT_NAMES[g.slot_of(piece)].to_lower(),
			float(g.base_of(piece)["weight"]), g.condition_text(piece)]]
	var stats := g.stat_lines(piece)
	for i in range(0, stats.size(), 2):  # two to a line
		lines.append("    ".join(PackedStringArray(stats.slice(i, i + 2))))
	_details.text = "\n".join(lines)
	_details.add_theme_color_override("font_color", g.color(piece))
	if _selected_side == WORN:
		_action("Unequip", unequip_selected)
	elif g.slot_of(piece) == "part":
		_action("Drop", drop_gear_selected)  # M14: parts go on a gun at a workbench, not on you
	else:
		_action("Equip", equip_selected)
		_action("Drop", drop_gear_selected)
	if sim.inventory.count("repair_kit") > 0 and float(piece["condition"]) < 1.0:
		_action("Repair (1 kit)", repair_selected)


func _slot(item: String, count: int, side: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE  # keep Tab for closing
	b.toggle_mode = true
	b.button_pressed = item == _selected and side == _selected_side
	b.tooltip_text = _name(item)
	var icon := _icon(item)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:  # no picture yet: a coloured tile with the name
		b.text = _name(item)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_color_override("font_color", sim.data.item_color(item))
	var n := Label.new()
	n.text = str(count)
	n.position = SLOT - Vector2(40, 28)  # bottom-right corner of the slot
	n.size = Vector2(34, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 18)
	n.add_theme_constant_override("outline_size", 6)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	b.pressed.connect(_on_slot.bind(item, side))
	b.gui_input.connect(_on_item_input.bind(item, side))
	return b


func _show_details(held: Inventory) -> void:
	for child in _actions.get_children():
		child.queue_free()
	_details.remove_theme_color_override("font_color")
	if _selected == "":
		_details.text = "Click for details.  Double-click gear or a bag to equip it.  Shift-click moves a stack."
		return
	var d := sim.data
	var n := held.count(_selected)
	var lines := ["%s  x%d" % [_name(_selected), n],
			"%.2f kg each, %.1f kg in all" % [d.item_weight(_selected), d.item_weight(_selected) * n]]
	var effects := []
	if d.item_value(_selected, "food") > 0.0:
		effects.append("Food +%d" % d.item_value(_selected, "food"))
	if d.item_value(_selected, "water") > 0.0:
		effects.append("Water +%d" % d.item_value(_selected, "water"))
	if d.item_value(_selected, "bandage") > 0.0:
		effects.append("Stops bleeding")
	if d.item_value(_selected, "bag") > 0.0:
		effects.append("Bag: +%d kg carrying when equipped on your back" % d.item_value(_selected, "bag"))
	if not effects.is_empty():
		lines.append(", ".join(effects))
	if _selected_side == POCKETS and sim.hotbar.usable(_selected):  # S3
		var slot := sim.hotbar.find(Hotbar.item_entry(_selected))
		lines.append(("On key %s. " % Hotbar.key_name(slot) if slot != -1 else "") + "Press 1-9 or 0 to put it on that hotbar key.")
	_details.text = "\n".join(lines)

	var arrow := "->" if _selected_side == POCKETS else "<-"
	if _selected_side == POCKETS and sim.can_use(_selected):
		_action("Use", use_selected)
	if _selected_side == POCKETS and d.item_value(_selected, "bag") > 0.0:
		_action("Equip", equip_bag_selected)
	if crate() != null:
		_action("Move 1 " + arrow, move.bind(_selected, _selected_side, false))
		_action("Move all " + arrow, move.bind(_selected, _selected_side, true))
	if _selected_side == POCKETS:
		_action("Drop 1", drop_selected.bind(false))
		_action("Drop all", drop_selected.bind(true))


## Item names, with car keys saying which car they start.
func _name(item: String) -> String:
	if item.begins_with(GameData.CAR_KEY):
		var car := item.trim_prefix(GameData.CAR_KEY)
		if sim.vehicles.cars.has(car):
			return "Car key (%s)" % sim.vehicles.stats(car)["name"]
	return sim.data.item_name(item)


func _action(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(callback)
	_actions.add_child(b)


## S3: an item's picture, for the hotbar too (null when there is none yet).
static func icon_for(item: String) -> Texture2D:
	return _icon(item)


static func _icon(item: String) -> Texture2D:
	if item.begins_with(GameData.CAR_KEY):
		item = "car_key"  # every car's key looks the same
	if not _icons.has(item):
		var path := "res://assets/icons/%s.png" % item
		_icons[item] = load(path) if ResourceLoader.exists(path) else null
	return _icons[item]


static func clear_cache() -> void:
	_icons.clear()


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.02, 0.03, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks off the panels mustn't reach the game
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 18)
	column.add_child(sides)

	var left := VBoxContainer.new()
	sides.add_child(left)
	left.add_child(_title("Pockets"))
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 18)
	left.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(0, 10)
	left.add_child(_weight_bar)
	_pockets_grid = _grid(left)

	var character := VBoxContainer.new()
	character.custom_minimum_size = Vector2(DOLL_SIZE.x, 0)
	sides.add_child(character)
	character.add_child(_title("Character"))
	_wearing = CharacterSilhouette.new()
	_wearing.custom_minimum_size = DOLL_SIZE
	_wearing.mouse_filter = Control.MOUSE_FILTER_PASS
	character.add_child(_wearing)

	var right := VBoxContainer.new()
	sides.add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	_crate_title = _title("Crate")
	head.add_child(_crate_title)
	_crate_prev = _small_button("<", func() -> void: _cycle(-1))
	_crate_next = _small_button(">", func() -> void: _cycle(1))
	head.add_child(_crate_prev)
	head.add_child(_crate_next)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 41)  # line up with the pockets' weight label and bar
	right.add_child(spacer)
	_crate_grid = _grid(right)

	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 20)
	_details.custom_minimum_size = Vector2(0, 84)
	column.add_child(_details)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.custom_minimum_size = Vector2(0, 44)
	column.add_child(_actions)
	var hint := Label.new()
	hint.text = "Tab or Esc: close    1-9, 0: put the picked item on that hotbar key    The game keeps running while this is open"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)


func _cycle(step: int) -> void:
	if _crates.size() > 1:
		_crate_index = (_crate_index + step + _crates.size()) % _crates.size()
		if _selected_side == CRATE:
			_selected = ""
		refresh()


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	return l


func _grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS * (SLOT.x + 6), 3 * (SLOT.y + 6))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return grid


func _small_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 36)
	b.pressed.connect(callback)
	return b
