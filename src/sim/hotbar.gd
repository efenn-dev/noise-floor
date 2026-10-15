class_name Hotbar
extends RefCounted
## S3: the ten hotbar slots under keys 1-9 and 0, Satisfactory-style. V19 (Emmitt: "I keep wanting to hit 1 for
## a weapon but pull out a foundation"): there are two bars. The HANDS bar is what the keys do on foot: draw a
## weapon ("slot:weapon" melee, "slot:primary", "slot:sidearm") or use an item ("item:bandage": food, drink or a
## bandage). The BUILD bar ("build:wall") is what they do in build mode. An entry always lives on the bar its
## kind belongs to, so assigning never needs to be told which bar. The world decides what a key press does;
## this only keeps and checks the slots. Saved with the game; a new game starts with the defaults.

const SLOTS := 10
const BUILD := "build:"
const ITEM := "item:"
const SLOT := "slot:"
const HANDS_BAR := "hands"
const BUILD_BAR := "build"
## The weapon slots a key can draw, and their short names (the inventory's names for those slots).
const WEAPON_SLOTS := {"weapon": "Melee", "primary": "Primary", "sidearm": "Sidearm"}
const DEFAULT_HANDS := ["slot:weapon", "slot:primary", "slot:sidearm", "item:bandage", "", "", "", "", "", ""]
const DEFAULT_BUILD := ["build:foundation", "build:wall", "build:door", "build:storage", "build:smelter",
		"build:belt", "build:press", "build:generator", "build:bed", ""]

var data: GameData
var slots: Array = []        # the hands bar
var build_slots: Array = []  # the build bar


func _init(p_data: GameData) -> void:
	data = p_data
	reset()


func reset() -> void:
	slots = _checked(DEFAULT_HANDS)
	build_slots = _checked(DEFAULT_BUILD)


## A copy of `bar` with any entry the data no longer has (a test's cut-down data, say) emptied.
func _checked(bar: Array) -> Array:
	var out := []
	for e: String in bar:
		out.append(e if validate(e) == "" else "")
	return out


static func build_entry(id: String) -> String:
	return BUILD + id


static func item_entry(item: String) -> String:
	return ITEM + item


static func slot_entry(slot: String) -> String:
	return SLOT + slot


## Which bar an entry belongs on: building pieces on the build bar, everything else on the hands bar.
static func bar_for(entry: String) -> String:
	return BUILD_BAR if entry.begins_with(BUILD) else HANDS_BAR


## "" if `entry` may go on a hotbar, otherwise why not. Pieces must be ones the player can place; items must
## be usable (food, drink or a bandage): raw materials have nothing to do on a key.
func validate(entry: String) -> String:
	if entry == "":
		return ""
	if entry.begins_with(BUILD):
		var id := entry.trim_prefix(BUILD)
		if not data.buildables.has(id):
			return "Unknown piece"
		if not data.buildables[id].get("player_placeable", true):
			return "Only found in town"
		return ""
	if entry.begins_with(ITEM):
		var item := entry.trim_prefix(ITEM)
		if not data.items.has(item):
			return "Unknown item"
		if not usable(item):
			return "Only usable items and throwables go on the hotbar"
		return ""
	if entry.begins_with(SLOT):
		return "" if WEAPON_SLOTS.has(entry.trim_prefix(SLOT)) else "Not a weapon slot"
	return "Not a piece, an item or a weapon slot"


## Items a key can use: anything you eat, drink or bandage with.
func usable(item: String) -> bool:
	return (data.item_value(item, "food") > 0.0 or data.item_value(item, "water") > 0.0
			or data.item_value(item, "bandage") > 0.0
			or str(data.items.get(item, {}).get("throwable", "")) != "")


func _bar(bar: String) -> Array:
	return build_slots if bar == BUILD_BAR else slots


## Puts `entry` on slot `i` (0-9) of the bar its kind belongs on, clearing it from that bar's other slots so a
## thing is on one key. Returns "" or why not.
func assign(i: int, entry: String) -> String:
	if i < 0 or i >= SLOTS:
		return "No such slot"
	var why := validate(entry)
	if why != "":
		return why
	var bar := _bar(bar_for(entry))
	for j in SLOTS:
		if bar[j] == entry:
			bar[j] = ""
	bar[i] = entry
	return ""


func clear(i: int, bar: String = HANDS_BAR) -> void:
	if i >= 0 and i < SLOTS:
		_bar(bar)[i] = ""


func entry(i: int, bar: String = HANDS_BAR) -> String:
	return _bar(bar)[i] if i >= 0 and i < SLOTS else ""


## "build", "item", "slot" or "" for an empty slot.
func kind(i: int, bar: String = HANDS_BAR) -> String:
	var e := entry(i, bar)
	if e.begins_with(BUILD):
		return "build"
	if e.begins_with(ITEM):
		return "item"
	if e.begins_with(SLOT):
		return "slot"
	return ""


## The piece, item or weapon slot id on slot `i`, "" if empty.
func id(i: int, bar: String = HANDS_BAR) -> String:
	var e := entry(i, bar)
	for prefix: String in [BUILD, ITEM, SLOT]:
		if e.begins_with(prefix):
			return e.trim_prefix(prefix)
	return ""


## Which slot of its bar holds `entry`, or -1.
func find(entry: String) -> int:
	return _bar(bar_for(entry)).find(entry) if entry != "" else -1


## The key a slot is under: 1-9, then 0.
static func key_name(i: int) -> String:
	return str((i + 1) % 10)


## The short name shown on the HUD slot.
func label(i: int, bar: String = HANDS_BAR) -> String:
	match kind(i, bar):
		"build":
			return String(data.buildables[id(i, bar)]["name"])
		"item":
			return data.item_name(id(i, bar))
		"slot":
			return String(WEAPON_SLOTS[id(i, bar)])
	return ""


## Both bars, for the save.
func to_dict() -> Dictionary:
	return {HANDS_BAR: slots.duplicate(), BUILD_BAR: build_slots.duplicate()}


## Loads a saved hotbar. Entries the data no longer knows are dropped; nothing saved (a save from before the
## hotbar) gives the defaults. A V19 save is {"hands": [...], "build": [...]}; an older single bar (an Array)
## is split: its pieces keep their keys on the build bar, its items go on the hands bar after the three
## weapon slots (keeping their key when it's free), so nobody loses what they set up.
func load_saved(saved: Variant) -> void:
	if saved is Dictionary:
		var d: Dictionary = saved
		slots = _loaded(d.get(HANDS_BAR, []), DEFAULT_HANDS)
		build_slots = _loaded(d.get(BUILD_BAR, []), DEFAULT_BUILD)
		return
	var old: Array = saved if saved is Array else []
	if old.is_empty():
		reset()
		return
	reset()
	build_slots = ["", "", "", "", "", "", "", "", "", ""]
	var items := []
	for i in mini(old.size(), SLOTS):
		var e := String(old[i])
		if validate(e) != "":
			continue
		if e.begins_with(BUILD):
			build_slots[i] = e
		elif e.begins_with(ITEM):
			items.append([i, e])
	for pair: Array in items:
		var e: String = pair[1]
		if slots.has(e):
			continue
		var at: int = pair[0]
		if at < WEAPON_SLOTS.size() or slots[at] != "":
			at = slots.find("", WEAPON_SLOTS.size())
		if at != -1:
			slots[at] = e


## One saved bar: entries the data no longer knows are emptied, entries of the wrong kind for that bar are
## dropped, and a missing bar gets its defaults.
func _loaded(saved: Array, defaults: Array) -> Array:
	if saved.is_empty():
		return _checked(defaults)
	var want_build := defaults == DEFAULT_BUILD
	var out := []
	for i in SLOTS:
		var e := String(saved[i]) if i < saved.size() else ""
		var ok := validate(e) == "" and (e == "" or e.begins_with(BUILD) == want_build)
		out.append(e if ok else "")
	return out
