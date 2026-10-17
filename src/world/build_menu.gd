class_name BuildMenu
extends CanvasLayer
## S3: B opens this. Every piece you can build, with its cost. Click one to start building it (build mode, the
## ghost, as before). Hover or click one and press 1-9 or 0 to put it on that hotbar key (Hotbar). Esc or B closes
## it. The game keeps running. The rules stay in the sim: this reads BuildController.PIECES, GameData, Learning,
## Milestones and Hotbar and shows them.
## P10 (playtest: a six-year-old who can't read yet was lost in a wall of text): pictures first. A sidebar of group
## pictures on the left; the group's pieces as big picture tiles, each with its cost as item pictures and counts (red
## when the crates near you and your pockets can't pay). Pieces you haven't learned yet (Learning) or a Hub milestone
## locks are dark, with a padlock and the picture of what to build first, after the open ones; newly learned ones say
## NEW. The right side shows the piece you point at: its picture, what it costs (have / need, and where to find what's
## missing), what it makes (as item pictures) and a plain line.

signal message(text: String)
signal picked(id: String)

const GOLD := Color(0.95, 0.8, 0.55)
const GOOD := Color(0.6, 0.9, 0.6)
const SHORT := Color(1.0, 0.5, 0.42)
const DIM := Color(1, 1, 1, 0.68)
const COLUMNS := 5
const TILE := Vector2(126, 156)
const PIC := 88
## P10: each group's picture in the sidebar (one of its pieces, as the hotbar draws it).
const GROUP_PICS := {"Base": "wall", "Hub": "hub", "Factory": "smelter", "Extractors": "salvager", "Power": "generator",
		"Defense": "nail_turret"}
static var _small: Dictionary = {}  # F5: small_icon's cache
const GROUPS := [
	["Base", ["foundation", "wall", "soundproof_wall", "door", "barricade", "bed", "storage", "workbench", "stove", "electric_heater"]],
	["Hub", ["hub", "radio_mast"]],
	["Factory", ["belt", "splitter", "merger", "smelter", "press", "rain_collector", "purifier", "planter", "canner", "water_tap"]],
	["Extractors", ["salvager", "water_pump", "fuel_pump", "sawmill", "cart_stop"]],
	["Power", ["generator", "solar_panel", "power_pole", "dusk_timer"]],
	["Defense", ["spikes", "nail_turret", "crossbow_turret", "rifle_turret", "hopper", "motion_sensor", "noise_sensor",
			"floodlight", "noisemaker", "bear_trap", "tripwire", "electric_fence", "repair_station"]],
]
## S4: one line under each group's title saying how its pieces work (Playtest #1).
const GROUP_NOTES := {
	"Base": "Lay foundations first (key 1): walls, doors and machines stand on them.",
	"Factory": "Machines stand on a foundation and most need power. They take items IN at the back (blue arrow) and put them OUT at the front (orange). Belts snap to them.",
	"Hub": "F2: build a Hub at your base and press E on it: milestones unlock the advanced machines. Locked pieces say which milestone opens them.",
	"Extractors": "Built on a resource node's yellow spot (no foundation): scrap heaps, farm wells, fuel tankers, timber stands. Before you have one, E on the node gathers by hand. Loud: an outpost draws zombies.",
	"Power": "A generator (E loads gas cans) or a solar panel, plus a power pole within reach of what it feeds.",
	"Defense": "Turrets need ammo (E, a belt or a hopper). Sensors pick an action with E.",
}
## One plain line per piece (test_build_menu.gd checks every piece has one).
const BLURBS := {
	"foundation": "A 2 m floor square. Walls and machines stand on it.",
	"wall": "Blocks zombies, sight and most sound. Needs a foundation on one side.",
	"soundproof_wall": "A double wall lined with metal plates: stops twice the sound of a plain wall. Box a generator in with them.",
	"dusk_timer": "Switches off the machines on its power line from dusk to dawn, when zombies hear furthest. Stand it by a pole.",
	"cart_stop": "Build one at home (the first is the home stop) and one by each outpost's crate: a cart drives what's in the outpost's crates home along the roads.",
	"door": "A wall you can open. E opens and closes it; it swings away from you.",
	"barricade": "Low boards: blocks sound and zombies, turrets shoot over it. Boards up a broken window.",
	"bed": "Sleep here (E). Heals you fast and becomes where you respawn.",
	"storage": "A crate. E opens it; building draws from crates nearby.",
	"workbench": "Make firearm parts and ammo by hand (E).",
	"stove": "Burns planks (E to load). Warms the room in winter; crackles a little.",
	"electric_heater": "Warms the room on power. Silent.",
	"belt": "Carries items forward at 2 m a second. R turns it. Runs on bare ground too; drag to lay a row. A belt ending at a crate fills it.",
	"splitter": "Takes items at its back and sends them out the front, left and right in turn. Unlocked by Logistics.",
	"merger": "Joins belts: takes items at its back, left and right and sends them out the front. Unlocked by Logistics.",
	"smelter": "Scrap metal into metal plates. Loud. Needs power.",
	"hub": "Your base's command post (one per game). E: milestones. Hand in parts to unlock new machines, ending with the rescue.",
	"radio_mast": "Calls for rescue. Start the broadcast at dusk, keep it powered for 8 hours of signal and standing until help comes at dawn. Every zombie for miles hears it.",
	"salvager": "Grinds a scrap heap into scrap metal, nonstop. Very loud. Needs power. Build it on a scrap heap's yellow spot.",
	"water_pump": "Pumps dirty water from a farm well. Needs power. Build it on a well's yellow spot.",
	"fuel_pump": "Draws gas cans out of a crashed fuel tanker. Needs power. Build it on a tanker's yellow spot.",
	"sawmill": "A portable bandsaw mill: logs from a timber stand into planks. Loud. Needs power. Build it on a timber stand's yellow spot.",
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
var group := "Base"  # P10: the group whose tiles show

var _root: Control
var _buttons: Dictionary = {}  # id -> its tile (a Button)
var _tiles: Dictionary = {}  # id -> {"pic", "lock", "first", "new", "name", "costs": [[item, Label]]}
var _grids: Dictionary = {}  # group -> GridContainer
var _sides: Dictionary = {}  # group -> its sidebar Button
var _side_new: Dictionary = {}  # group -> its sidebar NEW badge
var _note: Label
var _center: CenterContainer
var _info: VBoxContainer  # the right-hand side: the piece you point at
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
	group = group_of(highlighted)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	fit()


## P10: the menu is drawn for a 1600 x 900 window and scaled up on a bigger one (pictures a child can see on a
## 1440p screen), never down; it leaves the hotbar along the bottom in view.
func fit() -> void:
	var view := _root.get_viewport_rect().size
	var s := clampf(minf(view.x / 1600.0, view.y / 900.0), 1.0, 1.6)
	_center.scale = Vector2(s, s)
	_center.position = Vector2.ZERO
	_center.size = Vector2(view.x, view.y - 100.0 * s) / s


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Clicking a piece: build mode with it, and the menu goes. A locked piece says what opens it instead.
func pick(id: String) -> void:
	if not _buttons.has(id):
		return
	highlight(id)
	var why := lock_text(id)
	if why != "":
		message.emit(why)
		return
	builder.select_id(id)
	builder.set_active(true)
	close()
	picked.emit(id)


func highlight(id: String) -> void:
	if _buttons.has(id):
		highlighted = id
		sim.learning.seen(id)  # P10: NEW goes once you've looked at it
		refresh()


## P10: the sidebar: show the group `g`'s tiles.
func show_group(g: String) -> void:
	if _grids.has(g) and g != group:
		group = g
		refresh()


static func group_of(id: String) -> String:
	for g: Array in GROUPS:
		if id in g[1]:
			return g[0]
	return GROUPS[0][0]


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
	if is_open():
		fit()  # wrapped labels settle over a frame or two, and the window may change size


# --- What the menu says -------------------------------------------------------------

## "" when `id` may be built (cost aside); otherwise why not, in a few words (as BuildGrid.can_place says it).
func lock_text(id: String) -> String:
	var learning := sim.learning
	if learning != null and not learning.knows(id):
		return "Build a %s first to learn this" % String(sim.data.buildables[learning.after(id)]["name"]).to_lower()
	var ms := sim.milestones
	if ms != null and not ms.unlocked(id):
		return "Unlock it at the Hub: %s" % ms.cfg(ms.unlocked_by(id)).get("name", "a milestone")
	if sim.build.projects != null and not sim.build.projects.unlocked(id):
		var project := str(sim.data.buildables[id].get("needs_project", ""))
		return "Needs the %s running first" % String(sim.data.projects.get(project, {}).get("name", "project")).to_lower()
	return ""


## P10: the piece whose picture a locked tile shows: what to build first (the piece before it, or the Hub).
func first_piece(id: String) -> String:
	if sim.learning != null and not sim.learning.knows(id):
		return sim.learning.after(id)
	if sim.milestones != null and not sim.milestones.unlocked(id):
		return "hub"
	return ""


## The piece's numbers: loudness, power, range, hp.
func facts_text(id: String) -> String:
	var info: Dictionary = sim.data.buildables[id]
	var facts := PackedStringArray()
	if float(info.get("loudness", 0.0)) > 0.0:
		facts.append("loudness %d" % int(info["loudness"]))
	if float(info.get("watts", 0.0)) > 0.0:
		facts.append("needs %d W" % int(info["watts"]))
	if float(info.get("watts_out", 0.0)) > 0.0:
		facts.append("makes %d W" % int(info["watts_out"]))
	if float(info.get("range", 0.0)) > 0.0:
		facts.append("range %d m" % int(info["range"]))
	facts.append("%d hp" % int(info["hp"]))
	return " · ".join(facts)


func key_text(id: String) -> String:
	var slot := sim.hotbar.find(Hotbar.build_entry(id))
	return ("On key %s. " % Hotbar.key_name(slot) if slot != -1 else "") + "Press 1-9 or 0 to put it on that key. Click to build it."


## The words for `id`: name, cost and numbers, a plain line, what locks it and which key it's on.
func details_text(id: String) -> String:
	if id == "" or not sim.data.buildables.has(id):
		return "Point at a piece to read about it."
	var info: Dictionary = sim.data.buildables[id]
	var lines := PackedStringArray([" · ".join([String(info["name"]), cost_text(info["cost"]), facts_text(id)]),
			String(BLURBS.get(id, ""))])
	if lock_text(id) != "":
		lines.append(lock_text(id))
	lines.append(key_text(id))
	return "\n".join(lines)


func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in cost:
		parts.append("%d %s" % [cost[item], sim.data.item_name(item)])
	return ", ".join(parts)


## P10: the recipes a machine piece can run (its "recipes", or its one "recipe").
func recipes_of(id: String) -> Array:
	var info: Dictionary = sim.data.buildables[id]
	var out: Array = info.get("recipes", [])
	if out.is_empty() and str(info.get("recipe", "")) != "":
		out = [str(info["recipe"])]
	return out.filter(func(r: String) -> bool: return sim.data.recipes.has(r))


## P10: a group's pieces in the order its tiles show: the ones you can build first, then the locked ones.
func tile_order(g: String) -> Array:
	var ids := _ids_of(g)
	var open := ids.filter(func(id: String) -> bool: return lock_text(id) == "")
	var locked := ids.filter(func(id: String) -> bool: return lock_text(id) != "")
	return open + locked


# --- Drawing -------------------------------------------------------------------

func refresh() -> void:
	if sim == null:
		return
	var stock := sim.stock_at(sim.player_pos)
	for g: String in _grids:
		var grid: GridContainer = _grids[g]
		grid.visible = g == group
		(_sides[g] as Button).button_pressed = g == group
		var order := tile_order(g)
		var fresh := false
		for i in order.size():
			grid.move_child(_buttons[order[i]], i)
			fresh = fresh or (sim.learning.fresh.has(order[i]) and lock_text(order[i]) == "")
		(_side_new[g] as Control).visible = fresh
	for id: String in _buttons:
		_refresh_tile(id, stock)
	_stop.visible = builder.active
	_note.text = String(GROUP_NOTES.get(group, ""))
	_show_info(highlighted, stock)


func _ids_of(g: String) -> Array:
	for entry: Array in GROUPS:
		if entry[0] == g:
			return (entry[1] as Array).filter(func(id: String) -> bool: return sim.data.buildables.has(id))
	return []


func _refresh_tile(id: String, stock: Inventory) -> void:
	var b: Button = _buttons[id]
	var t: Dictionary = _tiles[id]
	var locked := lock_text(id) != ""
	b.button_pressed = id == highlighted or (builder.active and builder.piece() == id)
	(t["pic"] as TextureRect).modulate = Color(0.3, 0.3, 0.32) if locked else Color.WHITE
	(t["lock"] as Control).visible = locked
	var first := first_piece(id) if locked else ""
	(t["first"] as TextureRect).texture = _piece_pic(first, 48) if first != "" else null
	(t["first"] as Control).visible = first != ""
	(t["new"] as Control).visible = sim.learning.fresh.has(id) and not locked
	(t["name"] as Control).modulate = Color(1, 1, 1, 0.5) if locked else Color.WHITE
	var cost: Dictionary = sim.data.buildables[id]["cost"]
	for pair: Array in t["costs"]:
		var label: Label = pair[1]
		label.add_theme_color_override("font_color", GOOD if stock.count(pair[0]) >= int(cost[pair[0]]) else SHORT)
		label.modulate.a = 0.5 if locked else 1.0


## The right-hand side for `id`, built afresh: picture and name, what locks it, costs, what it makes, a plain line.
func _show_info(id: String, stock: Inventory) -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	if id == "" or not sim.data.buildables.has(id):
		_info.add_child(_label("Point at a piece to see it.", 16, true))
		return
	var info: Dictionary = sim.data.buildables[id]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_info.add_child(top)
	var big := _pic_rect(_piece_pic(id, 112), 112)
	if lock_text(id) != "":
		big.modulate = Color(0.45, 0.45, 0.47)
	top.add_child(big)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	var name_label := _label(String(info["name"]), 24, true)
	name_label.add_theme_color_override("font_color", GOLD)
	words.add_child(name_label)
	var facts := _label(facts_text(id), 14, true)
	facts.modulate = DIM
	words.add_child(facts)

	var why := lock_text(id)
	if why != "":
		var row := HFlowContainer.new()  # a long path wraps
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 4)
		_info.add_child(row)
		var lock := LockIcon.new()
		lock.custom_minimum_size = Vector2(24, 28)
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lock)
		var path: Array = sim.learning.path_to(id) if sim.learning != null else []
		if path.is_empty() and first_piece(id) != "":
			path = [first_piece(id)]
		for i in path.size():  # P10: every piece to build on the way, as pictures, the one you can build now first
			if i > 0:
				var arrow := _label("→", 18)
				arrow.modulate = DIM
				arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(arrow)
			row.add_child(_pic_rect(_piece_pic(path[i], 44), 44))
		if path.size() > 1:
			var names := path.map(func(p: String) -> String: return String(sim.data.buildables[p]["name"]))
			why = "Learn it by building these in order: %s" % " → ".join(names)
		var why_label := _label(why, 16, true)
		why_label.add_theme_color_override("font_color", SHORT)
		_info.add_child(why_label)

	_info.add_child(_heading("Costs"))
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override("h_separation", 14)
	_info.add_child(costs)
	var where := PackedStringArray()
	for item: String in info["cost"]:
		var need := int(info["cost"][item])
		var have := stock.count(item)
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.tooltip_text = sim.data.item_name(item)
		costs.add_child(chip)
		chip.add_child(_pic_rect(item_pic(item, 36), 36))
		var count := _label("%d / %d" % [mini(have, 999), need], 18)
		count.add_theme_color_override("font_color", GOOD if have >= need else SHORT)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(count)
		if have < need:
			var from := str(sim.data.items.get(item, {}).get("where", ""))
			if from != "":
				where.append("%s: %s" % [sim.data.item_name(item), from])
	for line: String in where:
		var w := _label(line, 13, true)
		w.modulate = DIM
		_info.add_child(w)

	var recipes := recipes_of(id)
	if not recipes.is_empty():
		_info.add_child(_heading("Makes" if recipes.size() == 1 else "Makes (R switches)"))
		for r: String in recipes.slice(0, 4):
			_info.add_child(_recipe_row(sim.data.recipes[r]))

	_info.add_child(_label(String(BLURBS.get(id, "")), 16, true))
	var keys := _label(key_text(id), 13, true)
	keys.modulate = DIM
	_info.add_child(keys)


## One recipe as pictures: what goes in (with counts), an arrow, what comes out.
func _recipe_row(recipe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ins: Dictionary = recipe.get("in", {})
	for item: String in ins:
		row.add_child(_item_count(item, int(ins[item])))
	var arrow := _label("→" if not ins.is_empty() else "makes", 22 if not ins.is_empty() else 14)
	arrow.modulate = DIM
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	var outs: Dictionary = recipe.get("out", {})
	for item: String in outs:
		row.add_child(_item_count(item, int(outs[item])))
	return row


func _item_count(item: String, n: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.tooltip_text = sim.data.item_name(item)
	box.add_child(_pic_rect(item_pic(item, 30), 30))
	if n > 1:
		var count := _label("×%d" % n, 14)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(count)
	return box


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.02, 0.03, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks off the panel mustn't reach the game
	add_child(_root)
	var center := CenterContainer.new()
	_center = center
	_root.add_child(center)
	var panel := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.09, 0.09, 0.1, 0.94)  # P10: solid enough that the world doesn't show through the pictures
	look.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", look)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
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

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)

	# The sidebar: one big picture per group.
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	for g: Array in GROUPS:
		var sb := Button.new()
		sb.name = "Group_" + g[0]
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.custom_minimum_size = Vector2(104, 74)
		sb.tooltip_text = g[0]
		sb.pressed.connect(show_group.bind(g[0]))
		side.add_child(sb)
		var inner := VBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 0)
		sb.add_child(inner)
		var gp := _pic_rect(_piece_pic(str(GROUP_PICS.get(g[0], "")), 48), 48)
		gp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inner.add_child(gp)
		var gl := _label(g[0], 14)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(gl)
		var gn := _new_badge()
		gn.position = Vector2(4, 4)
		sb.add_child(gn)
		_sides[g[0]] = sb
		_side_new[g[0]] = gn

	# The tiles: the group's pieces as pictures.
	var grid_w := COLUMNS * TILE.x + (COLUMNS - 1) * 6
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 6)
	body.add_child(middle)
	_note = _label("", 13, true)
	_note.modulate = DIM
	_note.custom_minimum_size = Vector2(grid_w, 34)
	middle.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(grid_w + 14, TILE.y * 3 + 12)
	middle.add_child(scroll)
	var stack := VBoxContainer.new()
	scroll.add_child(stack)
	for g: Array in GROUPS:
		var grid := GridContainer.new()
		grid.name = "Tiles_" + g[0]
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		stack.add_child(grid)
		_grids[g[0]] = grid
		for id: String in g[1]:
			if sim.data.buildables.has(id):
				grid.add_child(_make_tile(id))

	# The piece you point at.
	var right := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.28)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	right.add_theme_stylebox_override("panel", style)
	right.custom_minimum_size = Vector2(350, 0)
	body.add_child(right)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 7)
	right.add_child(_info)

	var hint := _label("Click a piece to build it (then LMB places, drag for a row, R turns, RMB removes, Esc stops)  ·  1-9, 0 puts the piece you point at on that hotbar key  ·  B or Esc closes this", 13, true)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.custom_minimum_size = Vector2(900, 0)
	column.add_child(hint)


## One piece's tile: its picture (dark, with a padlock and what to build first, when locked), its name, its cost.
func _make_tile(id: String) -> Button:
	var b := Button.new()
	b.name = "Piece_" + id
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = TILE
	b.tooltip_text = String(sim.data.buildables[id]["name"])
	b.mouse_entered.connect(highlight.bind(id))
	b.pressed.connect(pick.bind(id))
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_top = 5
	inner.add_theme_constant_override("separation", 2)
	b.add_child(inner)
	var pic := _pic_rect(_piece_pic(id, PIC), PIC)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(pic)
	var name_label := _label(String(sim.data.buildables[id]["name"]), 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(TILE.x - 8, 0)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(name_label)
	var costs := HBoxContainer.new()
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	costs.alignment = BoxContainer.ALIGNMENT_CENTER
	costs.add_theme_constant_override("separation", 2)
	inner.add_child(costs)
	var pairs := []
	var cost: Dictionary = sim.data.buildables[id]["cost"]
	for item: String in cost:
		costs.add_child(_pic_rect(item_pic(item, 18), 18))
		var n := _label(str(int(cost[item])), 12)
		costs.add_child(n)
		pairs.append([item, n])
	var first := TextureRect.new()
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	first.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	first.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	first.size = Vector2(48, 48)
	first.position = Vector2(TILE.x - 52, PIC - 40)
	b.add_child(first)
	var lock := LockIcon.new()
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.size = Vector2(22, 26)
	lock.position = Vector2(TILE.x / 2.0 - 11, PIC / 2.0 - 8)
	b.add_child(lock)
	var fresh := _new_badge()
	fresh.position = Vector2(5, 5)
	b.add_child(fresh)
	_buttons[id] = b
	_tiles[id] = {"pic": pic, "lock": lock, "first": first, "new": fresh, "name": name_label, "costs": pairs}
	return b


func _new_badge() -> Label:
	var badge := _label("NEW", 12)
	badge.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	var style := StyleBoxFlat.new()
	style.bg_color = GOLD
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	badge.add_theme_stylebox_override("normal", style)
	badge.visible = false
	return badge


func _label(text: String, px: int, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _heading(text: String) -> Label:
	var l := _label(text, 14)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _pic_rect(tex: Texture2D, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	return r


func _piece_pic(id: String, px: int) -> Texture2D:
	var pic := InventoryScreen.icon_for("piece_" + id)  # S4: tools/art/piece_icons.gd
	return small_icon(pic, px) if pic != null else null


## P10: an item's picture at `px`, or a square of its colour when it has none.
func item_pic(item: String, px: int) -> Texture2D:
	var pic := InventoryScreen.icon_for(item)
	if pic != null:
		return small_icon(pic, px)
	var key := "swatch:%s@%d" % [item, px]
	if not _small.has(key):
		var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
		img.fill(Color(str(sim.data.items.get(item, {}).get("color", "#888888"))))
		_small[key] = ImageTexture.create_from_image(img)
	return _small[key]


## F5: `pic` scaled down to `px` square (cached), for a button icon that keeps its size whatever the text.
static func small_icon(pic: Texture2D, px: int) -> Texture2D:
	var key := "%s@%d" % [pic.resource_path, px]
	if not _small.has(key):
		var img := pic.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_small[key] = ImageTexture.create_from_image(img)
	return _small[key]


## P10: a padlock, drawn (no font here is sure to have one).
class LockIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var metal := Color(0.92, 0.92, 0.9)
		var thick := maxf(2.0, w * 0.14)
		draw_arc(Vector2(w / 2.0, h * 0.42), w * 0.3, PI, TAU, 16, metal, thick)
		draw_line(Vector2(w * 0.2, h * 0.42), Vector2(w * 0.2, h * 0.5), metal, thick)
		draw_line(Vector2(w * 0.8, h * 0.42), Vector2(w * 0.8, h * 0.5), metal, thick)
		var body := Rect2(Vector2(0, h * 0.45), Vector2(w, h * 0.55))
		draw_rect(body, Color(0.95, 0.78, 0.35))
		draw_rect(body, Color(0.2, 0.15, 0.05), false, 1.5)
		draw_circle(Vector2(w / 2.0, h * 0.7), w * 0.1, Color(0.2, 0.15, 0.05))
