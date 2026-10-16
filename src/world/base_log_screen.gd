class_name BaseLogScreen
extends CanvasLayer
## M15: L (or "Base log" in the pause menu). The base log, newest first, with the game time of each event:
## what your turrets, traps, sensors and walls went through while you were away. The sim keeps it
## (BaseLog); this only shows it. F6: at the top, what your machines made today and yesterday next to what you eat
## and drink in a day (SimWorld.supplies_lines).

const GOLD := Color(0.95, 0.8, 0.55)

var sim: SimWorld
var _root: Control
var _list: Label
var _radio: Label
var _made: Label  # F6


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("base_log") or event.is_action_pressed("interact")
			or event.is_action_pressed("free_mouse") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		refresh()


func text() -> String:
	return _list.text


func refresh() -> void:
	var lines := sim.base_log.lines()
	_list.text = "\n".join(lines) if not lines.is_empty() else "Nothing has happened at your base yet."
	_made.text = "\n".join(sim.supplies_lines())  # F6
	_radio.text = ("You carry a radio: events more than %d m away show on your screen as they happen." % int(sim.data.defense["radio"]["far"])) \
			if sim.carries_radio() else "No radio in your pockets: far events only show up here (there's one in the starting crate)."


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80 if side in ["top", "bottom"] else 60)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Base log"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)
	_radio = Label.new()
	_radio.add_theme_font_size_override("font_size", 16)
	_radio.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_radio)
	_made = Label.new()  # F6: what your machines made, next to what you eat and drink
	_made.add_theme_font_size_override("font_size", 18)
	_made.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	_made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_made)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = Label.new()
	_list.add_theme_font_size_override("font_size", 18)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_list)
	var foot := Label.new()
	foot.text = "Newest first, the last %d events    L, E or Esc: close" % int(sim.data.defense["log"]["size"])
	foot.add_theme_font_size_override("font_size", 16)
	foot.modulate = Color(1, 1, 1, 0.65)
	column.add_child(foot)
