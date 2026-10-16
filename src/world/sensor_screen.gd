class_name SensorScreen
extends CanvasLayer
## M15: E on a motion or noise sensor. Shows what it watches and whether it's triggered, and lists the four
## actions; click one to pick it (SimWorld.set_sensor_action). The rules are in Automation; this only shows them.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)

var sim: SimWorld
var sensor_key := ""
var _root: Control
var _head: Label
var _state: Label
var _actions: VBoxContainer


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(key: String) -> void:
	sensor_key = key
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("interact") or event.is_action_pressed("free_mouse")
			or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		_state.text = _state_text()


## Button action (tests call it, or press the button "Action_<id>").
func pick(action: String) -> void:
	var why := sim.set_sensor_action(sensor_key, action)
	message.emit(why if why != "" else "Sensor action: %s" % sim.automation.action_name(action))
	refresh()


func button(button_name: String) -> Button:
	return _root.find_child(button_name, true, false) as Button


func refresh() -> void:
	if not sim.automation.sensors.has(sensor_key):
		_head.text = "Sensor gone"
		return
	var b: Dictionary = sim.data.buildables[sim.build.pieces[sensor_key]["id"]]
	var watches := "sees zombies within %d m (walls and closed doors block it)" % int(b["range"]) if b["sense"] == "motion" \
			else "hears sounds of %d or more within %d m (not your machines' hum)" % [int(sim.data.defense["sensors"]["noise_threshold"]), int(b["range"])]
	if b["sense"] == "night":  # F5: the dusk timer
		watches = "on from dusk to dawn"
	_head.text = "%s · %s" % [b["name"], watches]
	_state.text = _state_text()
	for c in _actions.get_children():
		c.queue_free()
		_actions.remove_child(c)
	var current: String = sim.automation.sensors[sensor_key]["action"]
	for a: String in sim.data.defense["action_order"]:
		var act: Dictionary = sim.data.defense["actions"][a]
		var btn := Button.new()
		btn.name = "Action_" + a
		btn.text = "%s %s\n%s" % ["[x]" if a == current else "[ ]", act["name"], act["about"]]
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(820, 64)
		btn.add_theme_font_size_override("font_size", 17)
		if a == current:
			btn.add_theme_color_override("font_color", GOLD)
		btn.pressed.connect(pick.bind(a))
		_actions.add_child(btn)


func _state_text() -> String:
	if not sim.automation.sensors.has(sensor_key):
		return ""
	var s: Dictionary = sim.automation.sensors[sensor_key]
	var net := sim.power.network_of(sensor_key)
	var extra := "" if s["action"] != "quiet" or not net.is_empty() else "   (quiet mode needs the sensor on a power network: put it next to a pole or a machine)"
	if s["on"]:
		return "TRIGGERED: %s%s" % [sim.automation.action_name(s["action"]).to_lower(), " (%d s more after it clears)" % ceili(s["hold"]) if s["hold"] > 0.0 else ""] + extra
	return "Watching" + extra


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
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Sensor"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 19)
	column.add_child(_head)
	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 18)
	_state.modulate = Color(1, 0.75, 0.6)
	column.add_child(_state)
	var pick_label := Label.new()
	pick_label.text = "When it's set off, it does one thing. Pick it:"
	pick_label.add_theme_font_size_override("font_size", 18)
	column.add_child(pick_label)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	column.add_child(_actions)
	var foot := Label.new()
	foot.text = "E or Esc: close    The game keeps running while this is open"
	foot.add_theme_font_size_override("font_size", 16)
	foot.modulate = Color(1, 1, 1, 0.65)
	column.add_child(foot)
