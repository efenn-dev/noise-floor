class_name WorkbenchScreen
extends CanvasLayer
## M14/V14 slots: E on a workbench. Left: the selected primary or sidearm, its numbers and its four part
## slots (click a slot to take the part off). Middle: the gun parts in your pockets (click one to attach it).
## Right: what the bench makes by hand (ammo from casings, suppressors, a stock), greyed out with the reason
## when you can't. The rules are in the sim (SimWorld.attach_part, detach_part, bench_craft); this only shows them.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)

var sim: SimWorld
var bench_key := ""
var _root: Control
var _gun_label: Label
var _slots: VBoxContainer
var _parts: VBoxContainer
var _recipes: VBoxContainer


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(key: String) -> void:
	bench_key = key
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


func bench_pos() -> Vector3:
	return sim.build.piece_center(bench_key) if sim.build.pieces.has(bench_key) else sim.player_pos


## Button actions (tests call these, or press the buttons).
func attach(uid: int) -> void:
	message.emit(sim.attach_part(uid))
	refresh()


func detach(slot: String) -> void:
	message.emit(sim.detach_part(slot))
	refresh()


func craft(recipe: String) -> void:
	message.emit(sim.bench_craft(recipe, bench_pos()))
	refresh()


## The button for a part slot ("Slot_muzzle") or a part in your pockets ("Part_<uid>") or a recipe ("Make_<id>").
func button(button_name: String) -> Button:
	return _root.find_child(button_name, true, false) as Button


func gun_text() -> String:
	return _gun_label.text


func refresh() -> void:
	if sim == null:
		return
	for box: VBoxContainer in [_slots, _parts, _recipes]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var gun := sim.gear.gun()
	if gun.is_empty():
		_gun_label.text = "No firearm equipped.\nEquip a primary or sidearm from your pockets (Tab), then come back."
		_gun_label.remove_theme_color_override("font_color")
	else:
		_gun_label.text = "\n".join(PackedStringArray([gun["name"]] + sim.gear.stat_lines(gun).filter(
				func(l: String) -> bool: return not l.contains(": ") or l.begins_with("Loaded"))))
		_gun_label.add_theme_color_override("font_color", sim.gear.color(gun))
		for slot: String in sim.data.guns["part_slots"]:
			var part: Dictionary = gun["parts"].get(slot, {})
			var b := _button("Slot_" + slot, "%s: %s" % [slot.capitalize(), part.get("name", "-")])
			b.disabled = part.is_empty()
			if not part.is_empty():
				b.add_theme_color_override("font_color", sim.gear.color(part))
				b.tooltip_text = "Click to take it off.  " + sim.gear.part_text(part) + "  " + sim.gear.condition_text(part)
				b.pressed.connect(detach.bind(slot))
			_slots.add_child(b)
	var any := false
	for p: Dictionary in sim.gear.pieces:
		if sim.gear.slot_of(p) != "part":
			continue
		any = true
		var b := _button("Part_%d" % int(p["uid"]), "%s  (%s)" % [p["name"], sim.gear.condition_text(p)])
		b.add_theme_color_override("font_color", sim.gear.color(p))
		b.tooltip_text = sim.gear.part_text(p)
		b.disabled = gun.is_empty()
		b.pressed.connect(attach.bind(int(p["uid"])))
		_parts.add_child(b)
	if not any:
		_parts.add_child(_small("No firearm parts in your pockets. Factory crates and car trunks have them; the bench makes some.", 15))
	for r: String in sim.bench_recipes():
		var rec: Dictionary = sim.data.recipes[r]
		var why := sim.can_bench_craft(r, bench_pos())
		var ins := PackedStringArray()
		for item: String in rec["in"]:
			ins.append("%d %s" % [rec["in"][item], sim.data.item_name(item).to_lower()])
		var b := _button("Make_" + r, "%s  <-  %s" % [rec["name"], ", ".join(ins)])
		b.disabled = why != ""
		b.tooltip_text = why
		b.pressed.connect(craft.bind(r))
		_recipes.add_child(b)
		if why.begins_with("Needs the"):
			_recipes.add_child(_small("    " + why, 13))


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
		margin.add_theme_constant_override("margin_" + side, 80 if side in ["top", "bottom"] else 40)  # clear of the HUD
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_title("Workbench"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var left := _column(row, "Selected firearm")
	_gun_label = Label.new()
	_gun_label.add_theme_font_size_override("font_size", 18)
	left.add_child(_gun_label)
	_slots = VBoxContainer.new()
	left.add_child(_small("Parts on it (click to take one off)", 15))
	left.add_child(_slots)
	_parts = VBoxContainer.new()
	var mid := _column(row, "Parts in your pockets")
	mid.add_child(_small("Click to attach", 15))
	mid.add_child(_parts)
	_recipes = VBoxContainer.new()
	var right := _column(row, "Make by hand")
	right.add_child(_small("From your pockets and crates nearby", 15))
	right.add_child(_recipes)
	column.add_child(_small("E or Esc: close    The game keeps running while this is open", 16))


func _column(row: HBoxContainer, heading: String) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.custom_minimum_size = Vector2(380, 0)
	c.add_child(_title(heading, 22))
	row.add_child(c)
	return c


func _button(button_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = button_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 36)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _title(text: String, size: int = 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _small(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	l.modulate = Color(1, 1, 1, 0.65)
	return l
