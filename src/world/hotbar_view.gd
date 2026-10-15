class_name HotbarView
extends HBoxContainer
## S3: the ten hotbar slots along the bottom of the HUD (Satisfactory-style), one per key 1-9 and 0. A slot
## shows the piece or item on it (Hotbar in the sim), whether you can afford or have it, and which one you're
## building with. It only shows things: main.gd handles the keys, and nothing here takes the mouse.

const SLOT := Vector2(76, 62)  # wide enough for "Foundation" on one line at 12 px
const REFRESH := 0.2  # seconds between refreshes (the nearby-crates stock is a small search)
const GOLD := Color(0.95, 0.8, 0.55)

var sim: SimWorld
var builder: BuildController
var _panels: Array[PanelContainer] = []
var _styles: Array[StyleBoxFlat] = []
var _icons: Array[TextureRect] = []
var _names: Array[Label] = []
var _counts: Array[Label] = []
var _timer := 0.0
var _mode_label: Label  # V19: "BUILD" in front of the bar while build mode shows the build bar


func setup(p_sim: SimWorld, p_builder: BuildController) -> void:
	sim = p_sim
	builder = p_builder
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_mode_label = _label(14, GOLD)
	_mode_label.text = "BUILD"
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_label.visible = false  # a hidden child takes no room in the bar
	add_child(_mode_label)
	for i in Hotbar.SLOTS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = SLOT
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.05, 0.06, 0.6)
		style.border_color = Color(1, 1, 1, 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var inner := Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.custom_minimum_size = SLOT
		panel.add_child(inner)
		var key := _label(13, Color(1, 1, 1, 0.8))
		key.text = Hotbar.key_name(i)
		key.position = Vector2(5, 1)
		inner.add_child(key)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(SLOT.x / 2.0 - 19.0, 10)
		icon.size = Vector2(38, SLOT.y - 22)
		inner.add_child(icon)
		var name_label := _label(12, Color.WHITE)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD  # never mid-word ("Foundati-on")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.position = Vector2(3, 14)
		name_label.size = SLOT - Vector2(6, 18)
		inner.add_child(name_label)
		var count := _label(14, Color.WHITE)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.position = Vector2(SLOT.x - 34, SLOT.y - 22)
		count.size = Vector2(30, 20)
		inner.add_child(count)
		_panels.append(panel)
		_styles.append(style)
		_icons.append(icon)
		_names.append(name_label)
		_counts.append(count)
	refresh()


## V19: which bar the keys use right now: the build bar in build mode, the hands bar otherwise.
func active_bar() -> String:
	return Hotbar.BUILD_BAR if builder != null and builder.active else Hotbar.HANDS_BAR


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()


func refresh() -> void:
	if sim == null:
		return
	var stock := sim.stock_at(sim.player_pos)
	var bar := active_bar()
	_mode_label.visible = bar == Hotbar.BUILD_BAR
	for i in Hotbar.SLOTS:
		var kind := sim.hotbar.kind(i, bar)
		var id := sim.hotbar.id(i, bar)
		var selected := kind == "build" and builder != null and builder.active and builder.piece() == id
		var have := true
		var count := ""
		var icon: Texture2D = null
		if kind == "build":
			have = stock.has_all(sim.data.buildables[id]["cost"])
			icon = InventoryScreen.icon_for("piece_" + id)  # S4: rendered by tools/art/piece_icons.gd
		elif kind == "item":
			var n := sim.inventory.count(id)
			have = n > 0
			count = str(n)
			icon = InventoryScreen.icon_for(id)
			selected = sim.ready_throw == id
		elif kind == "slot":  # V19: the weapon in that slot; gold while it's the one in your hands
			var piece: Variant = sim.gear.equipped.get(id)
			have = piece is Dictionary
			if have:
				icon = InventoryScreen.icon_for(String((piece as Dictionary)["base"]))
			selected = sim.guns.hands == ("melee" if id == "weapon" else id)
		_icons[i].texture = icon
		_icons[i].visible = icon != null
		_names[i].text = sim.hotbar.label(i, bar) if icon == null else ""
		_names[i].modulate = Color.WHITE if have else Color(1, 1, 1, 0.45)
		_icons[i].modulate = Color.WHITE if have else Color(1, 1, 1, 0.4)
		_counts[i].text = count
		_counts[i].modulate = Color.WHITE if have else Color(1, 0.5, 0.4)
		_styles[i].border_color = GOLD if selected else Color(1, 1, 1, 0.35 if kind != "" else 0.15)
		_styles[i].bg_color = Color(0.25, 0.2, 0.1, 0.75) if selected else Color(0.05, 0.05, 0.06, 0.6 if kind != "" else 0.35)


## One line per slot, for tests: "1 Foundation build afford selected", "0 Bandage item x1", "4 -".
func describe() -> PackedStringArray:
	refresh()
	var out := PackedStringArray()
	var bar := active_bar()
	for i in Hotbar.SLOTS:
		var kind := sim.hotbar.kind(i, bar)
		if kind == "":
			out.append("%s -" % Hotbar.key_name(i))
			continue
		var parts := PackedStringArray([Hotbar.key_name(i), sim.hotbar.label(i, bar), kind])
		if kind == "build":
			if _names[i].modulate.a > 0.9:
				parts.append("afford")
			if _styles[i].border_color == GOLD:
				parts.append("selected")
		elif kind == "slot":
			if _styles[i].border_color == GOLD:
				parts.append("in hand")
		else:
			parts.append("x" + _counts[i].text)
		out.append(" ".join(parts))
	return out


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l
