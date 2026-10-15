class_name SkillsScreen
extends CanvasLayer
## K: every skill with its level and a bar to the next one, your perk points, and the three perk trees
## with each perk's rank and a button to put a point in it. The game keeps running while it's open
## (like the inventory). The rules are in the sim (Skills.spend, Skills.bonus); this only shows them.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)
const GREY := Color(0.55, 0.55, 0.55)

var sim: SimWorld
var _root: Control
var _skill_rows: Dictionary = {}  # skill -> {"label": Label, "bar": ProgressBar}
var _perk_rows: Dictionary = {}   # perk -> {"label": Label, "button": Button}
var _points_label: Label
var _points_panel: PanelContainer
var _skills_scroll: ScrollContainer
var _tree_scrolls: Dictionary = {}  # tree -> ScrollContainer

const SKILLS_W := 350  # width of the skills column
const TREE_W := 250    # width of each perk tree's column
const TREE_GAP := 16
## Height the screen leaves for its title lines, the foot and the panel's margins; the scrolling columns
## get the rest of the window, so the screen fits a 1280x720 window as well as 1600x900.
const CHROME_H := 150


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false
	if is_inside_tree():
		get_viewport().size_changed.connect(fit)  # P2: a resized window re-fits the scrolling columns


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	fit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("skills") or event.is_action_pressed("free_mouse")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		refresh()  # xp can change while it's open (the game keeps running)


## A button press (tests call this directly): one point into `perk`.
func spend(perk: String) -> void:
	var why := sim.spend_perk(perk)
	message.emit(why if why != "" else "%s rank %d" % [sim.skills.perk_name(perk), sim.skills.rank(perk)])
	refresh()


## What a skill's row says, e.g. "Strength 2" (tests read it).
func skill_text(skill: String) -> String:
	return (_skill_rows[skill]["label"] as Label).text


## What a perk's row says, e.g. "Soft Step 1/5".
func perk_text(perk: String) -> String:
	return (_perk_rows[perk]["label"] as Label).text


func perk_button(perk: String) -> Button:
	return _perk_rows[perk]["button"]


# --- Drawing -------------------------------------------------------------------

func refresh() -> void:
	if sim == null:
		return
	var sk := sim.skills
	for s: String in _skill_rows:
		var row: Dictionary = _skill_rows[s]
		var label: Label = row["label"]
		var bar: ProgressBar = row["bar"]
		var prog := sk.progress(s)
		if sk.is_disabled(s):
			label.text = "%s  -" % sk.skill_name(s)
			bar.value = 0.0
			continue
		label.text = "%s %d" % [sk.skill_name(s), sk.level(s)] + ("  MAX" if prog[1] == 0 else "")
		bar.max_value = maxf(1.0, prog[1])
		bar.value = prog[0] if prog[1] > 0 else bar.max_value
		bar.tooltip_text = ("%d / %d xp to level %d" % [prog[0], prog[1], sk.level(s) + 1]) if prog[1] > 0 else "Top level"
	var every := int(sim.data.skills["levels_per_perk_point"])
	_points_label.text = "Perk points: %d    (one for every %d skill levels; %d levels so far)" % [sk.perk_points, every,
			sk.total_levels()]
	if sk.perk_points > 0:
		_points_label.text = "%d UNSPENT PERK POINT%s — click +1 below" % [sk.perk_points, "" if sk.perk_points == 1 else "S"]
	_points_label.add_theme_color_override("font_color", GOLD if sk.perk_points > 0 else Color(0.9, 0.9, 0.85))
	_points_label.add_theme_font_size_override("font_size", 22 if sk.perk_points > 0 else 18)
	_points_panel.modulate = Color.WHITE if sk.perk_points > 0 else Color(1, 1, 1, 0.55)
	for p: String in _perk_rows:
		var row: Dictionary = _perk_rows[p]
		(row["label"] as Label).text = "%s %d/%d" % [sk.perk_name(p), sk.rank(p), sk.max_rank()]
		var b: Button = row["button"]
		b.disabled = sk.can_spend(p) != ""
		b.text = "MAX" if sk.rank(p) >= sk.max_rank() else "+1"


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
	sides.add_theme_constant_override("separation", 32)
	column.add_child(sides)

	# Left: the ten skills, in a column that scrolls if the window is short (P2).
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	sides.add_child(left)
	left.add_child(_title("Skills"))
	left.add_child(_small("Skills level by doing", 16))
	_skills_scroll = _scroller(SKILLS_W)
	left.add_child(_skills_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.custom_minimum_size = Vector2(SKILLS_W - 14, 0)  # room for the scroll bar
	_skills_scroll.add_child(list)
	for s: String in sim.skills.ids():
		var name := Label.new()
		name.add_theme_font_size_override("font_size", 19)
		var desc := _small(sim.data.skills["skills"][s].get("text", ""), 14)
		_wrap(desc, SKILLS_W - 14)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 10)
		if sim.skills.is_disabled(s):
			name.modulate = GREY
			desc.modulate = GREY
			bar.modulate = Color(1, 1, 1, 0.3)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		name.custom_minimum_size = Vector2(150, 0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(name)
		line.add_child(bar)
		list.add_child(line)
		list.add_child(desc)
		_skill_rows[s] = {"label": name, "bar": bar}
	# Right: perk points, then the three trees side by side; each tree's perks wrap to its column and the
	# column scrolls if the window is too short for them (P2: six Fighter perks no longer push it off screen).
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	sides.add_child(right)
	right.add_child(_title("Perks"))
	_points_panel = PanelContainer.new()
	var points_style := StyleBoxFlat.new()
	points_style.bg_color = Color(0.16, 0.12, 0.035, 0.92)
	points_style.border_color = GOLD
	points_style.set_border_width_all(2)
	points_style.set_corner_radius_all(5)
	points_style.content_margin_left = 10
	points_style.content_margin_right = 10
	points_style.content_margin_top = 6
	points_style.content_margin_bottom = 6
	_points_panel.add_theme_stylebox_override("panel", points_style)
	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 18)
	_points_panel.add_child(_points_label)
	right.add_child(_points_panel)
	var tree_row := HBoxContainer.new()
	tree_row.add_theme_constant_override("separation", TREE_GAP)
	right.add_child(tree_row)
	var trees: Dictionary = sim.data.skills["trees"]
	for t: String in trees:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		tree_row.add_child(col)
		var head := Label.new()
		head.text = trees[t]["name"]
		head.add_theme_font_size_override("font_size", 22)
		head.add_theme_color_override("font_color", GOLD)
		col.add_child(head)
		var scroll := _scroller(TREE_W)
		col.add_child(scroll)
		_tree_scrolls[t] = scroll
		var perks := VBoxContainer.new()
		perks.add_theme_constant_override("separation", 8)
		scroll.add_child(perks)
		for p: String in trees[t]["perks"]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(56, 34)
			b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			b.pressed.connect(spend.bind(p))
			row.add_child(b)
			var text := VBoxContainer.new()
			text.add_theme_constant_override("separation", 0)
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 18)
			text.add_child(label)
			var desc := _small(sim.data.skills["perks"][p].get("text", ""), 14)
			_wrap(desc, TREE_W - 56 - 8 - 14)
			text.add_child(desc)
			row.add_child(text)
			perks.add_child(row)
			_perk_rows[p] = {"label": label, "button": b, "row": row}
	right.add_child(_small("Points can't be taken back", 14))
	var foot := _small("K or Esc: close    The game keeps running while this is open", 16)
	column.add_child(foot)


## Sizes the scrolling columns to the window (open() calls it; tests call it after changing the size).
func fit() -> void:
	var h := _root.get_viewport_rect().size.y if _root.is_inside_tree() else 900.0
	var avail := maxf(200.0, h - CHROME_H)
	_skills_scroll.custom_minimum_size.y = avail - 30.0  # under "Skills" and its hint line
	for t: String in _tree_scrolls:
		(_tree_scrolls[t] as ScrollContainer).custom_minimum_size.y = avail - 100.0  # under "Perks", the points line and the tree name


## The perk's row (button and text), for layout tests.
func perk_row(perk: String) -> Control:
	return _perk_rows[perk]["row"]


func tree_scroll(tree: String) -> ScrollContainer:
	return _tree_scrolls[tree]


func panel_rect() -> Rect2:
	return (_root.get_child(0).get_child(0) as Control).get_global_rect()


func _scroller(width: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(width, 300)
	return sc


func _wrap(l: Label, width: float) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _small(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, 0.65)
	return l
