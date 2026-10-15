class_name HubScreen
extends CanvasLayer
## F2: E on the Hub. Left: every milestone, tier by tier (done, open, locked). Right: the one picked: what it's
## for, its parts (handed in / needed, and how many are in reach: your pockets and crates near the Hub), what it
## unlocks, and the Hand in button. The rules are in Milestones and SimWorld; this only shows them.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)
const DONE := Color(0.6, 0.85, 0.6)
const LOCKED := Color(0.6, 0.6, 0.6)

var sim: SimWorld
var selected := ""
var _root: Control
var _list: VBoxContainer
var _title: Label
var _blurb: Label
var _parts: Label
var _unlocks: Label
var _hand_in: Button
var _buttons: Dictionary = {}  # milestone id -> Button


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if selected == "" or sim.milestones.is_done(selected):
		selected = _first_open()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _first_open() -> String:
	for id: String in sim.milestones.all():
		if sim.milestones.available(id):
			return id
	var all := sim.milestones.all()
	return all.back() if not all.is_empty() else ""


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("interact") or event.is_action_pressed("free_mouse")
			or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		refresh()


## Picks milestone `id` (the list buttons; tests call it).
func pick(id: String) -> void:
	selected = id
	refresh()


## The Hand in button (tests call it).
func hand_in() -> void:
	message.emit(sim.hub_deliver(selected))
	refresh()


func refresh() -> void:
	var m := sim.milestones
	for id: String in _buttons:
		var b: Button = _buttons[id]
		var state := "done" if m.is_done(id) else ("open" if m.available(id) else "locked")
		b.text = "%s  %s" % [{"done": "[done]", "open": "[ ]", "locked": "[locked]"}[state], m.cfg(id)["name"]]
		b.modulate = DONE if state == "done" else (Color.WHITE if state == "open" else LOCKED)
		b.button_pressed = id == selected
	if selected == "":
		return
	var c := m.cfg(selected)
	_title.text = "%s  ·  Tier %d %s" % [c["name"], int(c["tier"]), m.tier_name(int(c["tier"]))]
	_blurb.text = str(c.get("blurb", ""))
	var stock := sim.hub_stock()
	var got: Dictionary = m.delivered.get(selected, {})
	var lines := PackedStringArray()
	for item: String in c.get("cost", {}):
		var need := int(c["cost"][item])
		var have := int(got.get(item, 0))
		var tick := "  ok" if have >= need else ""
		lines.append("%s: %d / %d handed in%s   (%d in reach)" % [sim.data.item_name(item), have, need, tick, stock.count(item)])
	_parts.text = "\n".join(lines)
	var names: Array = c.get("unlocks", []).map(func(b: String) -> String: return sim.data.buildables[b]["name"])
	_unlocks.text = "Unlocks: " + ", ".join(names)
	if m.is_done(selected):
		_hand_in.text = "Done"
		_hand_in.disabled = true
	elif not m.available(selected):
		_hand_in.text = "Finish tier %d first" % (int(c["tier"]) - 1)
		_hand_in.disabled = true
	else:
		_hand_in.text = "Hand in what's in reach"
		_hand_in.disabled = false


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
		margin.add_theme_constant_override("margin_" + side, 70 if side in ["top", "bottom"] else 60)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var heading := Label.new()
	heading.text = "Hub  ·  milestones"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	outer.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(360, 0)
	row.add_child(_list)
	var m := sim.milestones
	for tier: int in m.tiers():
		var t := Label.new()
		t.text = "Tier %d  %s" % [tier, m.tier_name(tier)]
		t.add_theme_font_size_override("font_size", 19)
		t.add_theme_color_override("font_color", GOLD)
		_list.add_child(t)
		for id: String in m.all():
			if int(m.cfg(id)["tier"]) != tier:
				continue
			var b := Button.new()
			b.name = "Milestone_" + id
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(pick.bind(id))
			_list.add_child(b)
			_buttons[id] = b
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	_title = _label(detail, 24)
	_title.add_theme_color_override("font_color", GOLD)
	_blurb = _label(detail, 18)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parts = _label(detail, 19)
	_unlocks = _label(detail, 18)
	_unlocks.add_theme_color_override("font_color", DONE)
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hand_in = Button.new()
	_hand_in.name = "HandIn"
	_hand_in.focus_mode = Control.FOCUS_NONE
	_hand_in.custom_minimum_size = Vector2(320, 52)
	_hand_in.add_theme_font_size_override("font_size", 19)
	_hand_in.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hand_in.pressed.connect(hand_in)
	detail.add_child(_hand_in)
	var foot := Label.new()
	foot.text = "E or Esc: close    Parts come from your pockets and any storage crate within %d m of the Hub." % int(sim.data.milestones.get("deliver_range", 8.0))
	foot.add_theme_font_size_override("font_size", 16)
	foot.modulate = Color(1, 1, 1, 0.65)
	outer.add_child(foot)


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
