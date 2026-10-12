class_name InventoryScreen
extends CanvasLayer
## Tab: your pockets beside the nearest storage crate within reach. Click an item to see it and use,
## move or drop it; shift-click moves the whole stack to the other side, ctrl-click moves one.
## The game keeps running (a zombie can walk up while you sort). The rules are in the sim
## (use_item, drop_items, Inventory.move_to, crates_near); this only shows them.

signal message(text: String)

const SLOT := Vector2(88, 88)
const COLS := 5
const POCKETS := "pockets"
const CRATE := "crate"

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

	var carried := sim.inventory.weight(sim.data)
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
