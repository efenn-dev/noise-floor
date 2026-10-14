class_name BuildMenu
extends CanvasLayer
## S3: B opens this. Every piece you can build, in groups, with its cost (grey when the crates near you and
## your pockets can't pay). Click one to start building it (build mode, the ghost, as before). Hover or click
## one and press 1-9 or 0 to put it on that hotbar key (Hotbar). Esc or B closes it. The game keeps running.
## The rules stay in the sim: this reads BuildController.PIECES, GameData and Hotbar and shows them.

signal message(text: String)
signal picked(id: String)

const GOLD := Color(0.95, 0.8, 0.55)
const GROUPS := [
	["Base", ["foundation", "wall", "door", "barricade", "bed", "storage", "workbench", "stove", "electric_heater"]],
	["Factory", ["belt", "smelter", "press", "rain_collector", "purifier", "planter", "canner", "water_tap"]],
	["Power", ["generator", "solar_panel", "power_pole"]],
	["Defense", ["spikes", "nail_turret", "crossbow_turret", "rifle_turret", "hopper", "motion_sensor", "noise_sensor",
			"floodlight", "noisemaker", "bear_trap", "tripwire", "electric_fence", "repair_station"]],
]
## S4: one line under each group's title saying how its pieces work (Playtest #1).
const GROUP_NOTES := {
	"Base": "Lay foundations first (key 1): walls, doors and machines stand on them.",
	"Factory": "Machines stand on a foundation and most need power. E on a machine loads it and takes what it made.",
	"Power": "A generator (E loads gas cans) or a solar panel, plus a power pole within reach of what it feeds.",
	"Defense": "Turrets need ammo (E, a belt or a hopper). Sensors pick an action with E.",
}
## One plain line per piece (test_build_menu.gd checks every piece has one).
const BLURBS := {
	"foundation": "A 2 m floor square. Walls and machines stand on it.",
	"wall": "Blocks zombies, sight and most sound. Needs a foundation on one side.",
	"door": "A wall you can open. E opens and closes it; it swings away from you.",
	"barricade": "Low boards: blocks sound and zombies, turrets shoot over it. Boards up a broken window.",
	"bed": "Sleep here (E). Heals you fast and becomes where you respawn.",
	"storage": "A crate. E opens it; building draws from crates nearby.",
	"workbench": "Make firearm parts and ammo by hand (E).",
	"stove": "Burns planks (E to load). Warms the room in winter; crackles a little.",
	"electric_heater": "Warms the room on power. Silent.",
	"belt": "Carries items forward at 2 m a second. R turns it.",
	"smelter": "Scrap metal into metal plates. Loud. Needs power.",
	"press": "Plates into nails, wall panels, repair kits or casings (R switches). Needs power.",
	"rain_collector": "Fills with rainwater over time. Quiet.",
	"purifier": "Rainwater into clean water. Needs power.",
	"planter": "Seeds into vegetables. Quiet; nothing grows in winter.",
	"canner": "Vegetables into canned food. Needs power.",
	"water_tap": "Clean water from the water tower, once the tower runs.",
	"generator": "Burns gas cans (E to load) for 100 W. Very loud; a muffler helps (U).",
	"solar_panel": "60 W in daylight. Silent.",
	"power_pole": "Joins power pieces within its reach into one network.",
	"spikes": "Slows and hurts zombies that cross it. Wears out.",
	"nail_turret": "Shoots nails at zombies in range. Load it with E, a belt or a hopper.",
	"crossbow_turret": "Quiet turret that shoots bolts. Load it with E or a hopper.",
	"rifle_turret": "Long-range turret on power. Loud without a suppressor.",
	"hopper": "Holds ammo and feeds the turret in front of it.",
	"motion_sensor": "Sees zombies in range and fires its action (E to pick one).",
	"noise_sensor": "Hears loud sounds in range and fires its action (E to pick one).",
	"floodlight": "Lights the ground around it at night, on power.",
	"noisemaker": "Blares to draw zombies away (E, or a sensor's decoy action).",
	"bear_trap": "Pins the first zombie that steps in it. E resets it.",
	"tripwire": "Rings a bell when a zombie crosses it and wakes sensors nearby.",
	"electric_fence": "Stuns zombies that touch it while powered.",
	"repair_station": "Fixes the most damaged wall nearby with wall panels, on power.",
}

var sim: SimWorld
var builder: BuildController
var highlighted := ""  # the piece last hovered or clicked: the number keys put it on the hotbar

var _root: Control
var _buttons: Dictionary = {}  # id -> Button
var _details: Label
var _stop: Button


func setup(p_sim: SimWorld, p_builder: BuildController) -> void:
	sim = p_sim
	builder = p_builder
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	if highlighted == "" or not _buttons.has(highlighted):
		highlighted = builder.piece() if builder.active else "foundation"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Clicking a piece: build mode with it, and the menu goes.
func pick(id: String) -> void:
	if not _buttons.has(id):
		return
	highlighted = id
	builder.select_id(id)
	builder.set_active(true)
	close()
	picked.emit(id)


func highlight(id: String) -> void:
	if _buttons.has(id):
		highlighted = id
		refresh()


## Pressing 1-9 or 0 with a piece highlighted: it goes on that key. Returns the message shown.
func assign_slot(i: int) -> String:
	if highlighted == "":
		return "Point at a piece first"
	var why := sim.hotbar.assign(i, Hotbar.build_entry(highlighted))
	var text := why if why != "" else "%s is on key %s" % [sim.data.buildables[highlighted]["name"], Hotbar.key_name(i)]
	message.emit(text)
	refresh()
	return text


func stop_building() -> void:
	builder.set_active(false)
	close()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("free_mouse") or event.is_action_pressed("build_mode"):
		close()
		get_viewport().set_input_as_handled()
		return
	var slot := InputSetup.hotbar_slot(event)
	if slot != -1:
		assign_slot(slot)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open() and sim.player.dead:
		close()


# --- Drawing -------------------------------------------------------------------

func refresh() -> void:
	if sim == null:
		return
	var stock := sim.stock_at(sim.player_pos)
	for id: String in _buttons:
		var b: Button = _buttons[id]
		var info: Dictionary = sim.data.buildables[id]
		var can := stock.has_all(info["cost"]) and _unlocked(id)
		b.add_theme_color_override("font_color", (GOLD if id == highlighted else Color.WHITE) if can else Color(0.75, 0.55, 0.5))
		b.button_pressed = id == highlighted or (builder.active and builder.piece() == id)
	_stop.visible = builder.active
	_details.text = details_text(highlighted)


## The lines under the list for `id`: name and cost, its numbers, a plain line, and which key it's on.
func details_text(id: String) -> String:
	if id == "" or not sim.data.buildables.has(id):
		return "Point at a piece to read about it."
	var info: Dictionary = sim.data.buildables[id]
	var facts := PackedStringArray([String(info["name"]), cost_text(info["cost"])])
	if float(info.get("loudness", 0.0)) > 0.0:
		facts.append("loudness %d" % int(info["loudness"]))
	if float(info.get("watts", 0.0)) > 0.0:
		facts.append("needs %d W" % int(info["watts"]))
	if float(info.get("watts_out", 0.0)) > 0.0:
		facts.append("makes %d W" % int(info["watts_out"]))
	if float(info.get("range", 0.0)) > 0.0:
		facts.append("range %d m" % int(info["range"]))
	facts.append("%d hp" % int(info["hp"]))
	var lines := PackedStringArray([" · ".join(facts), String(BLURBS.get(id, ""))])
	if not _unlocked(id):
		lines.append("Needs the %s running first" % String(sim.data.projects.get(info.get("needs_project", ""), {}).get("name", "project")).to_lower())
	var slot := sim.hotbar.find(Hotbar.build_entry(id))
	lines.append(("On key %s. " % Hotbar.key_name(slot) if slot != -1 else "") + "Press 1-9 or 0 to put it on that key. Click to build it.")
	return "\n".join(lines)


func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in cost:
		parts.append("%d %s" % [cost[item], sim.data.item_name(item)])
	return ", ".join(parts)


func _unlocked(id: String) -> bool:
	return sim.build.projects == null or sim.build.projects.unlocked(id)


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.02, 0.03, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks off the panel mustn't reach the game
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -180.0  # leave the hotbar along the bottom in view
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	column.add_child(head)
	var title := Label.new()
	title.text = "Build"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	head.add_child(title)
	_stop = Button.new()
	_stop.text = "Stop building"
	_stop.focus_mode = Control.FOCUS_NONE
	_stop.add_theme_font_size_override("font_size", 16)
	_stop.pressed.connect(stop_building)
	head.add_child(_stop)

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 18)
	column.add_child(groups)
	for g: Array in GROUPS:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		groups.add_child(box)
		var gt := Label.new()
		gt.text = g[0]
		gt.add_theme_font_size_override("font_size", 20)
		gt.add_theme_color_override("font_color", GOLD)
		box.add_child(gt)
		var note := Label.new()
		note.text = String(GROUP_NOTES.get(g[0], ""))
		note.add_theme_font_size_override("font_size", 13)
		note.modulate = Color(1, 1, 1, 0.7)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(250, 0)
		box.add_child(note)
		for id: String in g[1]:
			if not sim.data.buildables.has(id):
				continue
			var b := Button.new()
			b.name = "Piece_" + id
			b.text = "%s  (%s)" % [sim.data.buildables[id]["name"], cost_text(sim.data.buildables[id]["cost"])]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(250, 30)
			b.add_theme_font_size_override("font_size", 15)
			var pic := InventoryScreen.icon_for("piece_" + id)  # S4: tools/art/piece_icons.gd
			if pic != null:
				b.icon = pic
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 26)
			b.mouse_entered.connect(highlight.bind(id))
			b.pressed.connect(pick.bind(id))
			box.add_child(b)
			_buttons[id] = b

	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 17)
	_details.custom_minimum_size = Vector2(0, 90)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_details)
	var hint := Label.new()
	hint.text = "Click a piece to build it (then LMB places, R turns, RMB removes, Esc stops)  ·  1-9, 0 puts the piece you point at on that hotbar key  ·  B or Esc closes this"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
