class_name PerkPickScreen
extends CanvasLayer
## F4: the perk pick (his son's session logs: 14 perk points earned, none spent). At a quiet moment with points to
## spend (SimWorld.perk_offer_ready), main.gd opens this: three big cards, one perk from each tree (Skills.offer). A
## click spends a point on that perk; with points left it shows the next three, otherwise it closes. "Later" (or
## Esc) puts it off a few game hours (`later`); a zombie coming close puts it off one (`close_for`). K still opens
## the full skills screen any time. P12 (it was once a day at dawn with no zombie within 25 m, which in a busy town
## never came: 24 points unspent between the two of them): the first pick explains itself (`_intro`).

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)
const TREE_COLORS := {"engineer": Color(0.55, 0.75, 0.95), "ghost": Color(0.7, 0.9, 0.7), "fighter": Color(0.95, 0.6, 0.5)}

var sim: SimWorld
var offered: Array = []  # the perk ids on the cards now
var _root: Control
var _points: Label
var _intro: Label  # P12
var _center: CenterContainer  # P12: scaled by fit()
var _cards: HBoxContainer


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
	fit()


## P12: drawn for a 1600 x 900 window and scaled up on a bigger one (like the build menu), never down.
func fit() -> void:
	var view := _root.get_viewport_rect().size
	var s := clampf(minf(view.x / 1600.0, view.y / 900.0), 1.0, 1.6)
	_center.scale = Vector2(s, s)
	_center.position = Vector2.ZERO
	_center.size = view / s


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("free_mouse"):
		later()
		get_viewport().set_input_as_handled()


## P12: "Later" or Esc: closed by choice, back in a few game hours.
func later() -> void:
	sim.perk_snooze(SimWorld.PERK_SNOOZE_LATER)
	close()


## P12: closed by the game (`why` "zombie": one came close): back sooner, and it says so.
func close_for(why: String) -> void:
	sim.perk_snooze(SimWorld.PERK_SNOOZE_CLOSED, why)
	if why == "zombie":
		message.emit("A zombie's close. The perk pick comes back when it's quiet (or press K)")
	close()


## Spends a point on card `i` (the card buttons; tests call it).
func pick(i: int) -> void:
	if i < 0 or i >= offered.size():
		return
	var perk: String = offered[i]
	var why := sim.skills.spend(perk)
	message.emit(why if why != "" else "%s is now rank %d" % [sim.skills.perk_name(perk), sim.skills.rank(perk)])
	if sim.skills.perk_points <= 0:
		close()
		return
	refresh()


func refresh() -> void:
	var sk := sim.skills
	_points.text = "%d perk point%s to spend" % [sk.perk_points, "" if sk.perk_points == 1 else "s"]
	_intro.visible = sk.perks.is_empty()  # P12: the first pick explains what this is
	offered = sk.offer(sim.clock.day + sk.perks.values().reduce(func(a: int, r: int) -> int: return a + r, 0))
	for c: Node in _cards.get_children():
		c.queue_free()
		_cards.remove_child(c)
	for i in offered.size():
		_cards.add_child(_card(i, offered[i]))


func _card(i: int, perk: String) -> Button:
	var sk := sim.skills
	var tree := sk.tree_of(perk)
	var b := Button.new()
	b.name = "Card%d" % i
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 260)
	b.pressed.connect(pick.bind(i))
	var colour: Color = TREE_COLORS.get(tree, Color.WHITE)
	for state: String in ["normal", "hover", "pressed"]:  # a clear card with its tree's colour round it
		var box_style := StyleBoxFlat.new()
		box_style.bg_color = Color(0.12, 0.12, 0.14, 0.95) if state == "normal" else Color(0.2, 0.2, 0.24, 0.98)
		box_style.border_color = colour if state == "normal" else GOLD
		box_style.set_border_width_all(3 if state == "normal" else 5)
		box_style.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, box_style)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var tree_label := _label(box, 18, str(sim.data.skills["trees"][tree]["name"]).to_upper())
	tree_label.add_theme_color_override("font_color", TREE_COLORS.get(tree, Color.WHITE))
	var title := _label(box, 30, sk.perk_name(perk))
	title.add_theme_color_override("font_color", GOLD)
	var text := _label(box, 19, str(sim.data.skills["perks"][perk]["text"]))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label(box, 18, "Rank %d  >  %d" % [sk.rank(perk), sk.rank(perk) + 1]).modulate = Color(1, 1, 1, 0.75)
	return b


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	_center = center
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	var heading := _label(col, 40, "A quiet moment: pick a perk!")
	heading.add_theme_color_override("font_color", GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points = _label(col, 22, "")
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro = _label(col, 19, "You earn a perk point every %d skill levels, just by doing things. A perk is a bonus you keep for good. Click a card to take it; the other two come round again." % int(sim.data.skills["levels_per_perk_point"]))
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size = Vector2(900, 0)
	_intro.modulate = Color(1, 1, 1, 0.85)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 24)
	col.add_child(_cards)
	var later := Button.new()
	later.name = "Later"
	later.text = "Later"
	later.focus_mode = Control.FOCUS_NONE
	later.custom_minimum_size = Vector2(200, 48)
	later.add_theme_font_size_override("font_size", 20)
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(self.later)
	col.add_child(later)
	var foot := _label(col, 16, "Click a card to take it. K shows every skill and perk any time.")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.modulate = Color(1, 1, 1, 0.65)


func _label(parent: Control, size: int, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
