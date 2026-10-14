class_name HelpScreen
extends CanvasLayer
## P3: F1 (or "Controls" on the title screen and in the pause menu). Every control, grouped. The list is
## built from the actions InputSetup registers plus ROWS below, the one place their descriptions live, so a
## new action without a description fails test_help_screen.gd. Opened in play, the game keeps running
## underneath (like the other screens); from the title or the pause menu the game is paused already, and
## closing goes back to that menu. Esc or F1 closes it.

signal closed(from: String)

const GOLD := Color(0.95, 0.8, 0.55)
const GROUPS := ["Move and look", "Use and search", "Build", "Fight (melee and firearms)", "Cars", "Screens", "Game"]
## Which groups go in which column, left to right.
const COLUMNS := [["Move and look", "Use and search"], ["Build", "Fight (melee and firearms)"], ["Cars", "Screens", "Game"]]
## [group, actions it describes (InputSetup names), keys to show ("" = the actions' own keys), what it does].
## A row with no actions describes the mouse, or a key that does something else in a car.
const ROWS := [
	["Move and look", ["move_forward", "move_left", "move_back", "move_right"], "W A S D", "walk (arrow keys work too)"],
	["Move and look", [], "Mouse", "look around"],
	["Move and look", ["sprint"], "", "sprint (uses stamina)"],
	["Move and look", ["jump"], "", "jump; at a broken window, climb through"],
	["Move and look", ["crouch"], "", "crouch: quieter and harder to see"],
	["Move and look", ["flashlight"], "", "flashlight on or off"],
	["Use and search", ["interact"], "", "use what you look at: search, open doors, clear broken-window glass, use machines, sleep, get in a car"],
	["Use and search", [], "E / double-click in loot", "move the picked stack between the open container and your pockets"],
	["Use and search", [], "R in loot", "take everything from the open container that fits"],
	["Use and search", [], "Ctrl-click / drag", "move one item; Shift-click or a plain drag moves the whole stack"],
	["Use and search", [], "Drag", "move loot, equip slots, or assign a pocket item to a hotbar key"],
	["Use and search", ["upgrade"], "", "fit a muffler to the machine you look at"],
	["Use and search", ["repair"], "", "repair the piece or car you look at"],
	["Use and search", ["eat"], "", "eat the best food you carry"],
	["Use and search", ["drink"], "", "drink the best water you carry"],
	["Use and search", ["bandage"], "", "bandage yourself (stops bleeding)"],
	["Use and search", ["quick_equip"], "", "wear the most recently looted gear upgrade"],
	["Use and search", ["siphon"], "", "siphon gas from the car you look at"],
	["Build", ["build_mode"], "", "build menu: click a piece to start building it"],
	["Build", ["hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8",
			"hotbar_9", "hotbar_10"], "1-9, 0", "hotbar: build the piece or use the item on that key (same key again stops building)"],
	["Build", [], "1-9, 0 in a menu", "put the piece (build menu) or item (Tab, your pockets) you picked on that key"],
	["Build", ["build_next", "build_prev"], "Mouse wheel", "next or previous piece while building"],
	["Build", ["build_rotate"], "", "turn the piece"],
	["Build", ["build_place"], "", "build it (from your pockets and crates nearby)"],
	["Build", ["build_remove"], "", "pull down what you look at (the town's pieces give a little salvage)"],
	["Build", [], "Esc", "stop building"],
	["Fight (melee and firearms)", ["attack"], "", "swing your melee weapon, or fire the firearm in hand"],
	["Fight (melee and firearms)", ["aim"], "", "hold to aim a firearm (a scope zooms); with melee or fists, hold to block"],
	["Fight (melee and firearms)", ["swap_hands"], "", "cycle Melee, Primary and Sidearm (empty slots are skipped)"],
	["Fight (melee and firearms)", ["refuel"], "", "reload the firearm in hand (at a car: pour in gas)"],
	["Fight (melee and firearms)", ["inspect"], "", "inspect the weapon in hand and its condition"],
	["Cars", [], "E", "get in or out (at the back: search the trunk)"],
	["Cars", [], "W A S D", "drive and steer"],
	["Cars", [], "Space", "handbrake"],
	["Cars", [], "H", "horn"],
	["Cars", [], "F", "headlights"],
	["Cars", [], "R", "hotwire a car with no key (needs Mechanics)"],
	["Screens", ["inventory"], "", "your gear and pockets"],
	["Screens", ["skills"], "", "skills and perks"],
	["Screens", ["objectives"], "", "show or hide the first-night objectives"],
	["Screens", ["base_log"], "", "base log: what happened at your base"],
	["Screens", ["noise_overlay"], "", "see how far your noise carries"],
	["Screens", ["help"], "", "this help"],
	["Game", ["quicksave"], "", "save the game"],
	["Game", ["quickload"], "", "load the last save"],
	["Game", ["free_mouse"], "", "pause menu; closes any screen (while building it stops building first)"],
]
## S4: the six steps of a first factory, shown under the controls (Playtest #1: building and machines
## were not clear). test_help_screen.gd checks they're on screen.
const GUIDE := [
	"1. The crate beside you holds your starting kit: press E on it to open it.",
	"2. Press 1 and click the ground to lay foundations. Everything you build stands on them.",
	"3. Press B, click Smelter, then click a foundation to place it (R turns it). Esc stops building.",
	"4. Machines need power: build a Generator and a Power pole beside the smelter (B, Power). E on the generator loads gas cans; the crate has some, G siphons more from cars.",
	"5. E on the smelter loads scrap metal from your pockets or the crate; it makes metal plates. E again takes them. A Press turns plates into nails.",
	"6. Running machines are loud, and loud draws zombies. N shows how far. Walls block sound; U on a machine fits a muffler.",
]
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "Left click", MOUSE_BUTTON_RIGHT: "Right click",
		MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}

var from := ""  # "title", "pause" or "" (opened in play)
var _root: Control
var _rows: Array[Label] = []
var _guide: Array[Label] = []


func setup() -> void:
	layer = 11  # over the title and pause menus
	process_mode = Node.PROCESS_MODE_ALWAYS  # opened from a menu, the game is paused
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(p_from: String = "") -> void:
	from = p_from
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_root.visible = false
	if from == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit(from)


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("help") or event.is_action_pressed("free_mouse")):
		close()
		get_viewport().set_input_as_handled()


## S4: the first-factory guide as shown, one step per line, for tests.
func guide_text() -> String:
	var out := PackedStringArray()
	for l: Label in _guide:
		out.append(l.text)
	return "\n".join(out)


## Every row as "keys:  what it does", one per line, for tests.
func text() -> String:
	var out := PackedStringArray()
	for l: Label in _rows:
		out.append(l.text)
	return "\n".join(out)


## The keys a row shows: its own label, or the keys and buttons InputSetup gives its actions.
static func keys_for(row: Array) -> String:
	if row[2] != "":
		return row[2]
	var names := PackedStringArray()
	for action: String in row[1]:
		for k: Key in InputSetup.KEYS.get(action, []):
			var n := OS.get_keycode_string(k)
			if not n in names:
				names.append(n)
		if InputSetup.MOUSE.has(action):
			names.append(MOUSE_NAMES.get(InputSetup.MOUSE[action], "Mouse"))
	return " / ".join(names)


## Every registered action (keys and mouse), for tests.
static func registered_actions() -> Array:
	return InputSetup.KEYS.keys() + InputSetup.MOUSE.keys()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36 if side in ["top", "bottom"] else 40)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var scrolled := VBoxContainer.new()  # S4: the controls and the guide scroll together on a small window
	scrolled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrolled.add_theme_constant_override("separation", 14)
	scroll.add_child(scrolled)
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 36)
	scrolled.add_child(cols)
	for groups: Array in COLUMNS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		cols.add_child(col)
		for group: String in groups:
			if col.get_child_count() > 0:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 10)
				col.add_child(gap)
			var head := Label.new()
			head.text = group
			head.add_theme_font_size_override("font_size", 21)
			head.add_theme_color_override("font_color", GOLD)
			col.add_child(head)
			for row: Array in ROWS:
				if row[0] != group:
					continue
				var l := Label.new()
				l.text = "%s:  %s" % [keys_for(row), row[3]]
				l.add_theme_font_size_override("font_size", 16)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(360, 0)
				col.add_child(l)
				_rows.append(l)
	# S4: the first factory, in two columns of three steps, under the controls.
	var guide_head := Label.new()
	guide_head.text = "Your first factory"
	guide_head.add_theme_font_size_override("font_size", 21)
	guide_head.add_theme_color_override("font_color", GOLD)
	guide_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scrolled.add_child(guide_head)
	var guide_cols := HBoxContainer.new()
	guide_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	guide_cols.add_theme_constant_override("separation", 36)
	scrolled.add_child(guide_cols)
	for half in 2:
		var gcol := VBoxContainer.new()
		gcol.add_theme_constant_override("separation", 4)
		guide_cols.add_child(gcol)
		for i in range(half * 3, half * 3 + 3):
			var l := Label.new()
			l.text = GUIDE[i]
			l.add_theme_font_size_override("font_size", 15)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(560, 0)
			gcol.add_child(l)
			_guide.append(l)
	var foot := Label.new()
	foot.text = "F1 or Esc: close"
	foot.add_theme_font_size_override("font_size", 16)
	foot.modulate = Color(1, 1, 1, 0.65)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(foot)
