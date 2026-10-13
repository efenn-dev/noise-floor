class_name InventoryScreen
extends CanvasLayer
## Tab: your pockets beside the nearest storage crate within reach. Click an item to see it and use,
## move or drop it; shift-click moves the whole stack to the other side, ctrl-click moves one.
## The game keeps running (a zombie can walk up while you sort). The rules are in the sim
## (use_item, drop_items, Inventory.move_to, crates_near); this only shows them.
## M13: gear pieces sit in your pockets after the stacks, each a tile in its rarity colour with its
## condition; click one for its stats and Equip / Drop / Repair. The "Wearing" column shows your slots.

signal message(text: String)

const SLOT := Vector2(88, 88)
const COLS := 5
const POCKETS := "pockets"
const CRATE := "crate"
const WORN := "worn"
const GEAR := "gear:"  # a selected gear piece is "gear:<uid>"
const SLOT_NAMES := {"weapon": "Weapon", "head": "Head", "body": "Body", "hands": "Hands", "light": "Light"}

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
var _wearing: VBoxContainer
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
	if is_open() and (event.is_action_pressed("inventory") or event.is_action_pressed("free_mouse")):
		close()
		get_viewport().set_input_as_handled()


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


func selected_gear() -> Dictionary:
	return sim.gear.find(int(_selected.trim_prefix(GEAR))) if _selected.begins_with(GEAR) else {}


func equip_selected() -> void:
	message.emit(sim.equip_gear(int(_selected.trim_prefix(GEAR))))
	_selected_side = WORN
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
	var bag := _best_bag()
	_weight_label.text = "Carrying %.1f / %.0f kg" % [carried, limit] \
			+ ("   (%s +%d kg)" % [sim.data.item_name(bag), sim.data.item_value(bag, "bag")] if bag != "" else "")
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


## A gear piece's tile: the placeholder icon in its rarity colour, its condition in the corner.
func _gear_slot(piece: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == POCKETS
	b.tooltip_text = piece["name"]
	b.name = "Gear%d" % piece["uid"]
	var icon := gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], SLOT - Vector2(16, 16))
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
	return b


## Placeholder gear icon until there are pictures: a rounded square in the rarity colour with the
## base's first letter. (Codex icons for gear are a later job on the PC.)
static func gear_icon(color: Color, base_name: String, size: Vector2) -> Control:
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
	var letter := Label.new()
	letter.text = base_name.left(1).to_upper()
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", int(size.y * 0.5))
	letter.add_theme_color_override("font_color", color)
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(letter)
	return panel


## The "Wearing" column: one row per slot, the piece's name in its rarity colour (click to select it).
func _fill_wearing() -> void:
	for child in _wearing.get_children():
		if child is Button:
			_wearing.remove_child(child)  # now, so the new row can take its name
			child.queue_free()
	for slot: String in sim.gear.slots():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 40)
		b.add_theme_font_size_override("font_size", 17)
		b.name = "Wear_" + slot
		var piece: Dictionary = sim.gear.equipped.get(slot, {})
		if piece.is_empty():
			b.text = "%s: -" % SLOT_NAMES[slot]
			b.disabled = true
		else:
			b.text = "%s: %s" % [SLOT_NAMES[slot], piece["name"]]
			b.add_theme_color_override("font_color", sim.gear.color(piece))
			b.add_theme_color_override("font_hover_color", sim.gear.color(piece).lightened(0.3))
			b.tooltip_text = sim.gear.condition_text(piece)
			b.toggle_mode = true
			b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == WORN
			b.pressed.connect(select_gear.bind(int(piece["uid"]), WORN))
		_wearing.add_child(b)


## The details for a gear piece: its name in the rarity colour, what it is, its condition and stats.
func _show_gear(piece: Dictionary) -> void:
	for child in _actions.get_children():
		child.queue_free()
	if piece.is_empty() or _selected == "":
		_details.remove_theme_color_override("font_color")
		_details.text = "Click an item to see it.  Shift-click moves the stack, ctrl-click moves one."
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
	return b


func _show_details(held: Inventory) -> void:
	for child in _actions.get_children():
		child.queue_free()
	_details.remove_theme_color_override("font_color")
	if _selected == "":
		_details.text = "Click an item to see it.  Shift-click moves the stack, ctrl-click moves one."
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
		effects.append("Bag: +%d kg carrying while in your pockets (the best bag counts)" % d.item_value(_selected, "bag"))
	if not effects.is_empty():
		lines.append(", ".join(effects))
	_details.text = "\n".join(lines)

	var arrow := "->" if _selected_side == POCKETS else "<-"
	if _selected_side == POCKETS and sim.can_use(_selected):
		_action("Use", use_selected)
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


func _best_bag() -> String:
	var best := ""
	for item: String in sim.inventory.items():
		if sim.data.item_value(item, "bag") > (sim.data.item_value(best, "bag") if best != "" else 0.0):
			best = item
	return best


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
	sides.add_theme_constant_override("separation", 28)
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

	_wearing = VBoxContainer.new()
	_wearing.add_theme_constant_override("separation", 6)
	sides.add_child(_wearing)
	_wearing.add_child(_title("Wearing"))

	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 20)
	_details.custom_minimum_size = Vector2(0, 84)
	column.add_child(_details)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.custom_minimum_size = Vector2(0, 44)
	column.add_child(_actions)
	var hint := Label.new()
	hint.text = "Tab or Esc: close    The game keeps running while this is open"
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
