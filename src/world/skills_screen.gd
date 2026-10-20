class_name SkillsScreen
extends CanvasLayer
## K: every skill with its level and a bar to the next one (left), and the three perk trees (right). The game
## keeps running while it's open (like the inventory). The rules are in the sim (Skills.spend, Skills.bonus,
## SimWorld.reset_perks); this only shows them.
## P13 (Emmitt: "a skill tree like in Diablo 2"): each tree is three rows of picture nodes. A row opens with
## Skills.rows() points in that tree (0, 3, 6); an arrow from a perk above means a point in it first
## (Skills.needs). A click puts a point in; pips under the picture are the rank; a glowing gold border means you
## can afford it now. "Take points back" returns a tree's points once a game day. P12's quiet-moment pick opens
## this screen with a banner and a Later button (open_prompt) instead of three cards.

signal message(text: String)

const GOLD := Color(0.95, 0.8, 0.55)
const GREY := Color(0.55, 0.55, 0.55)
const GREEN := Color(0.55, 0.85, 0.58)
const DIM := Color(1, 1, 1, 0.65)
const NODE := 76         # a perk node's square
const NODE_GAP := 8
const PIC := 46          # the picture inside it
const SKILLS_W := 350    # width of the skills column
const TREE_W := 250      # width of each perk tree's column (three nodes a row)
const TREE_GAP := 16
## Height the screen leaves for its title lines, the foot and the panel's margins; the scrolling columns
## get the rest of the window, so the screen fits a 1280x720 window as well as 1600x900.
const CHROME_H := 220  # P13: the details line and the reset buttons took 50 more
const TREE_H := 372      # P13: three rows of nodes with their names and the two row gates

var sim: SimWorld
var prompted := false  # P13: opened by the quiet-moment pick (Later snoozes it; a zombie near closes it)
var hovered := ""  # the perk the details line describes
var _root: Control
var _center: CenterContainer
var _skill_rows: Dictionary = {}  # skill -> {"label": Label, "bar": ProgressBar}
var _nodes: Dictionary = {}  # perk -> {"button": Button, "pic": TextureRect, "pips": Pips, "name": Label, "box": Control}
var _tree_links: Dictionary = {}  # tree -> TreeLinks (the arrows)
var _tree_heads: Dictionary = {}  # tree -> Label
var _gates: Dictionary = {}  # tree -> Array of Label (row 2 and 3's "N points opens this row")
var _resets: Dictionary = {}  # tree -> Button
var _points_label: Label
var _points_panel: PanelContainer
var _prompt: HBoxContainer
var _details: Label
var _foot: Label
var _skills_scroll: ScrollContainer
var _tree_scrolls: Dictionary = {}  # tree -> ScrollContainer
static var _styles: Dictionary = {}  # node state -> StyleBoxFlat


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
	prompted = false
	_show()


## P13: the quiet-moment pick (main.gd): the tree with a banner and Later, landing on the tree with the most points.
func open_prompt() -> void:
	prompted = true
	var best := ""
	for t: String in sim.data.skills["trees"]:
		if best == "" or sim.skills.tree_points(t) > sim.skills.tree_points(best):
			best = t
	hovered = ""
	for perk: String in sim.data.skills["trees"][best]["perks"]:
		if hovered == "" and sim.skills.can_spend(perk) == "":
			hovered = perk  # the first perk you could take: the details line starts there
	_show()


func _show() -> void:
	_root.visible = true
	fit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	prompted = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## P12/P13: "Later", or K / Esc on a prompted screen: closed by choice, back in a few game hours.
func later() -> void:
	if prompted:
		sim.perk_snooze(SimWorld.PERK_SNOOZE_LATER)
	close()


## P12/P13: closed by the game (`why` "zombie": one came close): back sooner, and it says so.
func close_for(why: String) -> void:
	if prompted:
		sim.perk_snooze(SimWorld.PERK_SNOOZE_CLOSED, why)
		if why == "zombie":
			message.emit("A zombie's close. The perk pick comes back when it's quiet (or press K)")
	close()


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("skills") or event.is_action_pressed("free_mouse")):
		if prompted:
			later()
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		refresh()  # xp can change while it's open (the game keeps running)


## A node press (tests call this directly): one point into `perk`.
func spend(perk: String) -> void:
	var why := sim.spend_perk(perk)
	message.emit(why if why != "" else "%s rank %d" % [sim.skills.perk_name(perk), sim.skills.rank(perk)])
	hovered = perk
	refresh()


## P13: "Take points back" on a tree.
func reset(tree: String) -> void:
	var why := sim.reset_perks(tree)
	if why != "":
		message.emit(why)
	refresh()


## What a skill's row says, e.g. "Strength 2" (tests read it).
func skill_text(skill: String) -> String:
	return (_skill_rows[skill]["label"] as Label).text


## What a perk's node says of its rank, e.g. "Soft Step 1/5".
func perk_text(perk: String) -> String:
	return "%s %d/%d" % [sim.skills.perk_name(perk), sim.skills.rank(perk), sim.skills.max_rank()]


func perk_button(perk: String) -> Button:
	return _nodes[perk]["button"]


## P13: how a node is drawn: "max", "available" (a point can go in now), "spent" (has ranks, can't add one
## now), "locked_row" (its row isn't open), "locked_arrow" (the perk above has no point), "open" (nothing yet).
func node_state(perk: String) -> String:
	var sk := sim.skills
	if sk.rank(perk) >= sk.max_rank():
		return "max"
	if not sk.row_open(sk.tree_of(perk), sk.row_of(perk)):
		return "locked_row"
	var need := sk.needs(perk)
	if need != "" and sk.rank(need) <= 0:
		return "locked_arrow"
	if sk.can_spend(perk) == "":
		return "available"
	return "spent" if sk.rank(perk) > 0 else "open"


## P13: the words under the trees for `perk`: name and rank, what it does, what it needs, its synergy.
func details_text(perk: String) -> String:
	if perk == "" or not sim.data.skills["perks"].has(perk):
		return "Point at a perk to read about it. Click a glowing one to put a point in."
	var sk := sim.skills
	var p: Dictionary = sim.data.skills["perks"][perk]
	var lines := PackedStringArray(["%s  ·  rank %d of %d  ·  %s row %d" % [sk.perk_name(perk), sk.rank(perk),
			sk.max_rank(), sk.tree_name(sk.tree_of(perk)), sk.row_of(perk)], str(p.get("text", ""))])
	var why := sk.why_locked(perk)
	if why != "":
		lines.append(why + ".")
	elif sk.needs(perk) != "":
		lines.append("Needs a point in %s: done." % sk.perk_name(sk.needs(perk)))
	if p.has("synergy"):
		var syn: Dictionary = p["synergy"]
		lines.append("Synergy: every %d points in %s add to it (%d now)." % [int(syn["every"]), sk.tree_name(str(syn["tree"])),
				sk.tree_points(str(syn["tree"]))])
	return "\n".join(lines)


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
		_points_label.text = "%d UNSPENT PERK POINT%s — click a glowing picture below" % [sk.perk_points, "" if sk.perk_points == 1 else "S"]
	_points_label.add_theme_color_override("font_color", GOLD if sk.perk_points > 0 else Color(0.9, 0.9, 0.85))
	_points_label.add_theme_font_size_override("font_size", 22 if sk.perk_points > 0 else 18)
	_points_panel.modulate = Color.WHITE if sk.perk_points > 0 else Color(1, 1, 1, 0.55)
	_prompt.visible = prompted
	_foot.text = ("Later or Esc: not now (it comes back in a few hours)    The game keeps running while this is open" if prompted
			else "K or Esc: close    The game keeps running while this is open")
	for t: String in sim.data.skills["trees"]:
		(_tree_heads[t] as Label).text = "%s  ·  %d point%s" % [sk.tree_name(t), sk.tree_points(t), "" if sk.tree_points(t) == 1 else "s"]
		var gates: Array = _gates[t]
		for i in gates.size():
			var row := i + 2
			var gate: Label = gates[i]
			gate.text = "" if sk.row_open(t, row) else "%d points in %s open this row" % [sk.row_needs(row), sk.tree_name(t)]
			gate.visible = not sk.row_open(t, row)
		var reset_b: Button = _resets[t]
		reset_b.disabled = sk.tree_points(t) <= 0 or not sim.can_reset_perks()
		reset_b.tooltip_text = ("Every point out of %s and back in your pocket (once a game day)" % sk.tree_name(t)) if sim.can_reset_perks() \
				else "You took points back today already: tomorrow"
		(_tree_links[t] as TreeLinks).queue_redraw()
	for perk: String in _nodes:
		_refresh_node(perk)
	_details.text = details_text(hovered)


func _refresh_node(perk: String) -> void:
	var n: Dictionary = _nodes[perk]
	var state := node_state(perk)
	var b: Button = n["button"]
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, _style(state, st == "hover"))
	b.disabled = state in ["locked_row", "locked_arrow", "max"] or (state != "available" and sim.skills.perk_points <= 0)
	var dark := state in ["locked_row", "locked_arrow"]
	(n["pic"] as TextureRect).modulate = Color(0.35, 0.35, 0.38) if dark else Color.WHITE
	(n["name"] as Label).modulate = Color(1, 1, 1, 0.45) if dark else Color.WHITE
	var pips: Pips = n["pips"]
	pips.set_ranks(sim.skills.rank(perk), sim.skills.max_rank(), state)
	b.tooltip_text = perk_text(perk) + ("\n" + sim.skills.why_locked(perk) if dark else "")


static func _style(state: String, hover: bool) -> StyleBoxFlat:
	var key := state + ("+hover" if hover else "")
	if not _styles.has(key):
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(3)
		match state:
			"max":
				sb.bg_color = Color(0.1, 0.16, 0.11, 0.98)
				sb.border_color = GREEN
			"available":
				sb.bg_color = Color(0.2, 0.17, 0.08, 0.98) if not hover else Color(0.28, 0.24, 0.1, 1.0)
				sb.border_color = GOLD
				sb.set_border_width_all(4)
				sb.shadow_color = Color(0.95, 0.8, 0.55, 0.45)
				sb.shadow_size = 8
			"spent", "open":
				sb.bg_color = Color(0.14, 0.14, 0.16, 0.98) if not hover else Color(0.2, 0.2, 0.23, 1.0)
				sb.border_color = Color(0.75, 0.75, 0.72) if state == "spent" else Color(0.45, 0.45, 0.48)
			_:
				sb.bg_color = Color(0.07, 0.07, 0.08, 0.95)
				sb.border_color = Color(0.25, 0.25, 0.27)
		_styles[key] = sb
	return _styles[key]


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.02, 0.03, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks off the panels mustn't reach the game
	add_child(_root)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_center)
	var panel := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.09, 0.09, 0.1, 0.94)  # solid enough that the world doesn't show through the pictures
	look.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", look)
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 32)
	column.add_child(sides)

	# Left: the skills, in a column that scrolls if the window is short (P2).
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

	# Right: perk points, the prompt banner, then the three trees side by side.
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
	_prompt = HBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 14)
	right.add_child(_prompt)
	var prompt_label := Label.new()
	prompt_label.text = "A quiet moment: pick a perk!  Click a glowing picture."
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_color", GOLD)
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prompt.add_child(prompt_label)
	var later_b := Button.new()
	later_b.name = "Later"
	later_b.text = "Later"
	later_b.focus_mode = Control.FOCUS_NONE
	later_b.custom_minimum_size = Vector2(110, 34)
	later_b.pressed.connect(later)
	_prompt.add_child(later_b)
	_prompt.visible = false
	var tree_row := HBoxContainer.new()
	tree_row.add_theme_constant_override("separation", TREE_GAP)
	right.add_child(tree_row)
	for t: String in sim.data.skills["trees"]:
		tree_row.add_child(_make_tree(t))
	_details = _small("", 15)
	_details.modulate = Color(1, 1, 1, 0.9)
	_wrap(_details, 3 * TREE_W + 2 * TREE_GAP)
	_details.custom_minimum_size.y = 62
	right.add_child(_details)
	_foot = _small("K or Esc: close    The game keeps running while this is open", 16)
	column.add_child(_foot)


## P13: one tree's column: its name and points, its rows of nodes (the arrows drawn over them), a reset button.
func _make_tree(t: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", GOLD)
	col.add_child(head)
	_tree_heads[t] = head
	var scroll := _scroller(TREE_W)
	col.add_child(scroll)
	_tree_scrolls[t] = scroll
	var holder := MarginContainer.new()  # sizes to the rows; the arrows overlay stretches to it
	holder.custom_minimum_size = Vector2(TREE_W - 14, 0)
	scroll.add_child(holder)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 10)
	holder.add_child(rows_box)
	_gates[t] = []
	for row in range(1, sim.skills.rows().size() + 1):
		if row > 1:
			var gate := _small("", 12)
			gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gate.add_theme_color_override("font_color", Color(0.95, 0.75, 0.5))
			_wrap(gate, TREE_W - 14)
			rows_box.add_child(gate)
			(_gates[t] as Array).append(gate)
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", NODE_GAP)
		rows_box.add_child(line)
		for perk: String in sim.skills.row_perks(t, row):
			line.add_child(_make_node(perk))
	var links := TreeLinks.new()
	links.screen = self
	links.tree = t
	links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(links)
	_tree_links[t] = links
	var reset_b := Button.new()
	reset_b.name = "Reset_" + t
	reset_b.text = "Take points back"
	reset_b.focus_mode = Control.FOCUS_NONE
	reset_b.add_theme_font_size_override("font_size", 13)
	reset_b.pressed.connect(reset.bind(t))
	col.add_child(reset_b)
	_resets[t] = reset_b
	return col


## P13: a perk's node: a square button with its picture and rank pips, its name under it.
func _make_node(perk: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var b := Button.new()
	b.name = "Perk_" + perk
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(NODE, NODE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(spend.bind(perk))
	b.mouse_entered.connect(func() -> void: hovered = perk)
	box.add_child(b)
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := InventoryScreen.icon_for(sim.skills.icon(perk))
	pic.texture = BuildMenu.small_icon(tex, PIC) if tex != null else null
	pic.position = Vector2((NODE - PIC) / 2.0, 7)
	pic.size = Vector2(PIC, PIC)
	b.add_child(pic)
	var pips := Pips.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.position = Vector2(0, NODE - 16)
	pips.size = Vector2(NODE, 12)
	b.add_child(pips)
	var name_label := _small(sim.skills.perk_name(perk), 11)
	name_label.modulate = Color.WHITE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(NODE, 0)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)
	_nodes[perk] = {"button": b, "pic": pic, "pips": pips, "name": name_label, "box": box}
	return box


## Sizes the screen to the window (open() calls it; tests call it after changing the size): drawn for 1600 x 900,
## scaled up on a bigger window (P13, like the build menu), the scrolling columns given the rest of the height.
func fit() -> void:
	var view := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(1600, 900)
	var s := clampf(minf(view.x / 1600.0, view.y / 900.0), 1.0, 1.6)
	_center.scale = Vector2(s, s)
	_center.position = Vector2.ZERO
	_center.size = view / s
	var avail := maxf(200.0, view.y / s - CHROME_H)
	_skills_scroll.custom_minimum_size.y = avail - 30.0  # under "Skills" and its hint line
	for t: String in _tree_scrolls:
		# Under "Perks", the points line and the tree name; three rows of nodes need about 360, so no taller than that
		# (the reset buttons and the details line sit right under the rows).
		(_tree_scrolls[t] as ScrollContainer).custom_minimum_size.y = minf(avail - 100.0, TREE_H)


## The perk's node (button and name), for layout tests.
func perk_row(perk: String) -> Control:
	return _nodes[perk]["box"]


func tree_scroll(tree: String) -> ScrollContainer:
	return _tree_scrolls[tree]


func panel_rect() -> Rect2:
	return (_center.get_child(0) as Control).get_global_rect()


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
	l.modulate = DIM
	return l


## P13: the rank pips under a node's picture: five dots, the ranks you have filled.
class Pips extends Control:
	var ranks := 0
	var of := 5
	var state := "open"

	func set_ranks(p_ranks: int, p_of: int, p_state: String) -> void:
		if p_ranks != ranks or p_of != of or p_state != state:
			ranks = p_ranks
			of = p_of
			state = p_state
			queue_redraw()

	func _draw() -> void:
		var step := 11.0
		var x0 := size.x / 2.0 - (of - 1) * step / 2.0
		var on := SkillsScreen.GREEN if state == "max" else SkillsScreen.GOLD
		for i in of:
			var c := Vector2(x0 + i * step, size.y / 2.0)
			draw_circle(c, 4.0, Color(0, 0, 0, 0.6))
			draw_circle(c, 3.2, on if i < ranks else Color(0.3, 0.3, 0.32))


## P13: the arrows between a perk and the one it needs, drawn over a tree's rows (gold once the perk above has a
## point, grey until then). Tests count them (`arrows`).
class TreeLinks extends Control:
	var screen: SkillsScreen
	var tree: String

	func arrows() -> Array:
		var out := []
		if screen == null:
			return out
		for perk: String in screen.sim.data.skills["trees"][tree]["perks"]:
			var need: String = screen.sim.skills.needs(perk)
			if need != "" and screen._nodes.has(need) and screen._nodes.has(perk):
				out.append([need, perk])
		return out

	func _draw() -> void:
		for a: Array in arrows():
			var from: Button = screen._nodes[a[0]]["button"]
			var to: Button = screen._nodes[a[1]]["button"]
			# Screen positions back into this control's own units (the whole panel is scaled up on big windows).
			var into := get_global_transform().affine_inverse()
			var p0: Vector2 = into * (from.get_global_transform() * Vector2(from.size.x / 2.0, from.size.y + 1))
			var p1: Vector2 = into * (to.get_global_transform() * Vector2(to.size.x / 2.0, -2.0))
			var lit := screen.sim.skills.rank(a[0]) > 0
			var colour := SkillsScreen.GOLD if lit else Color(0.4, 0.4, 0.42)
			draw_line(p0, p1, Color(0, 0, 0, 0.5), 5.0)
			draw_line(p0, p1, colour, 2.5)
			var dir := (p1 - p0).normalized()
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p1, p1 - dir * 9.0 + side * 5.0, p1 - dir * 9.0 - side * 5.0]), colour)
