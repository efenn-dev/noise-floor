class_name ProjectScreen
extends CanvasLayer
## M17a: E on the water tower. Lists the project's phases (done, now, later), what the current one still
## needs (and how many you have in your pockets and crates within reach), the work's progress, and the
## Deliver and Start Work buttons. The rules are in Projects and SimWorld; this only shows them.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)
const DONE := Color(0.6, 0.85, 0.6)

var sim: SimWorld
var project_id := ""
var _root: Control
var _head: Label
var _phases: Label
var _needs: Label
var _state: Label
var _deliver: Button
var _start: Button


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(id: String) -> void:
	project_id = id
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
		refresh()


## The Deliver button (tests call it).
func deliver() -> void:
	message.emit(sim.project_deliver(project_id))
	refresh()


## The Start Work button (tests call it).
func start_work() -> void:
	message.emit(sim.project_start(project_id))
	refresh()


func button(button_name: String) -> Button:
	return _root.find_child(button_name, true, false) as Button


func refresh() -> void:
	var p := sim.projects
	var cfg := p.cfg(project_id)
	if cfg.is_empty():
		_head.text = "Nothing here"
		return
	_head.text = "%s · %d m around it is the work site; delivering takes from your pockets and crates within %d m" % [
			cfg["name"], int(cfg["work_radius"]), int(cfg["deliver_range"])]
	var lines := PackedStringArray()
	var all := p.phases(project_id)
	for i in all.size():
		var ph: Dictionary = all[i]
		var mark := "[x]" if i < p.phase(project_id) else ("[>]" if i == p.phase(project_id) else "[ ]")
		var needs := _list(ph.get("needs", {}))
		var extra := ("%d W spare power, " % int(ph["watts"])) if float(ph.get("watts", 0.0)) > 0.0 else ""
		lines.append("%s Phase %d: %s · needs %s · then %s%d game-hour%s of work, loudness %d" % [mark, i + 1, ph["name"],
				needs if needs != "" else "nothing", extra, int(ph["work_hours"]), "" if int(ph["work_hours"]) == 1 else "s",
				int(ph["loudness"])])
	_phases.text = "\n".join(lines)
	_needs.text = needs_text()
	_state.text = state_text()
	var done := p.is_done(project_id)
	_deliver.disabled = done or p.missing(project_id).is_empty()
	_start.disabled = done or p.is_working(project_id) or not p.missing(project_id).is_empty()


## What the current phase still needs, with how many you have to hand.
func needs_text() -> String:
	var p := sim.projects
	if p.is_done(project_id):
		var reward: Dictionary = p.cfg(project_id).get("reward", {})
		return "Running. Rain collectors fill %dx as fast; you can build a water tap (B, mouse wheel)." % int(reward.get("rain_mult", 1.0))
	var left := p.missing(project_id)
	if left.is_empty():
		return "Everything for this phase is delivered."
	var stock := sim.stock_at(p.sites.get(project_id, sim.player_pos))
	var parts := PackedStringArray()
	for item: String in left:
		parts.append("%d %s (you have %d)" % [left[item], sim.data.item_name(item), stock.count(item)])
	return "Still needed: " + ", ".join(parts)


func state_text() -> String:
	var p := sim.projects
	if p.is_done(project_id):
		return ""
	var st: Dictionary = p.state.get(project_id, {})
	var pct := floori(100.0 * float(st.get("progress", 0.0)))
	var ph := p.current(project_id)
	if p.is_running(project_id):
		return "WORKING %d%% · %s · loudness %d: zombies can hear it" % [pct, ph["name"], int(ph["loudness"])]
	if p.is_working(project_id):
		var why := "come within %d m to carry on" % int(p.cfg(project_id)["work_radius"])
		if float(ph.get("watts", 0.0)) > 0.0:
			why += " (the pump needs %d W spare: a pole within reach of the tower)" % int(ph["watts"])
		return "PAUSED %d%% · %s" % [pct, why]
	return "Not started"


func _list(counts: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in counts:
		parts.append("%d %s" % [int(counts[item]), sim.data.item_name(item)])
	return ", ".join(parts)


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
	title.text = "Project"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)
	_head = _label(column, 18)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phases = _label(column, 18)
	_phases.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_needs = _label(column, 19)
	_needs.add_theme_color_override("font_color", GOLD)
	_needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state = _label(column, 18)
	_state.modulate = Color(1, 0.75, 0.6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_deliver = _button(row, "Deliver", "Deliver what it needs")
	_deliver.pressed.connect(deliver)
	_start = _button(row, "StartWork", "Start work")
	_start.pressed.connect(start_work)
	var foot := Label.new()
	foot.text = "E or Esc: close    The game keeps running while this is open. Work goes on while you stay close."
	foot.add_theme_font_size_override("font_size", 16)
	foot.modulate = Color(1, 1, 1, 0.65)
	column.add_child(foot)


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(parent: Control, button_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(260, 52)
	b.add_theme_font_size_override("font_size", 19)
	parent.add_child(b)
	return b
