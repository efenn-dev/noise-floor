class_name Hotbar
extends RefCounted
## S3: the ten hotbar slots under keys 1-9 and 0, Satisfactory-style. A slot holds a piece to build
## ("build:wall") or an item to use ("item:bandage": food, drink or a bandage), or nothing. The world decides
## what a key press does (start building that piece, eat that thing); this only keeps and checks the slots.
## Saved with the game; a new game starts with DEFAULT.

const SLOTS := 10
const BUILD := "build:"
const ITEM := "item:"
const DEFAULT := ["build:foundation", "build:wall", "build:door", "build:storage", "build:smelter",
		"build:belt", "build:press", "build:generator", "build:bed", "item:bandage"]

var data: GameData
var slots: Array = []


func _init(p_data: GameData) -> void:
	data = p_data
	reset()


func reset() -> void:
	slots = DEFAULT.duplicate()
	for i in SLOTS:
		if validate(slots[i]) != "":
			slots[i] = ""  # a default the data no longer has (a test's cut-down data, say)


static func build_entry(id: String) -> String:
	return BUILD + id


static func item_entry(item: String) -> String:
	return ITEM + item


## "" if `entry` may go on the hotbar, otherwise why not. Pieces must be ones the player can place;
## items must be usable (food, drink or a bandage): raw materials have nothing to do on a key.
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
			return "Only food, drink and bandages go on the hotbar"
		return ""
	return "Not a piece or an item"


## Items a key can use: anything you eat, drink or bandage with.
func usable(item: String) -> bool:
	return data.item_value(item, "food") > 0.0 or data.item_value(item, "water") > 0.0 \
			or data.item_value(item, "bandage") > 0.0


## Puts `entry` on slot `i` (0-9), clearing the same entry from any other slot so a thing is on one key.
## Returns "" or why not.
func assign(i: int, entry: String) -> String:
	if i < 0 or i >= SLOTS:
		return "No such slot"
	var why := validate(entry)
	if why != "":
		return why
	for j in SLOTS:
		if slots[j] == entry:
			slots[j] = ""
	slots[i] = entry
	return ""


func clear(i: int) -> void:
	if i >= 0 and i < SLOTS:
		slots[i] = ""


func entry(i: int) -> String:
	return slots[i] if i >= 0 and i < SLOTS else ""


## "build", "item" or "" for an empty slot.
func kind(i: int) -> String:
	var e := entry(i)
	if e.begins_with(BUILD):
		return "build"
	if e.begins_with(ITEM):
		return "item"
	return ""


## The piece or item id on slot `i`, "" if empty.
func id(i: int) -> String:
	var e := entry(i)
	return e.trim_prefix(BUILD) if e.begins_with(BUILD) else e.trim_prefix(ITEM)


## Which slot holds `entry`, or -1.
func find(entry: String) -> int:
	return slots.find(entry) if entry != "" else -1


## The key a slot is under: 1-9, then 0.
static func key_name(i: int) -> String:
	return str((i + 1) % 10)


## The short name shown on the HUD slot.
func label(i: int) -> String:
	match kind(i):
		"build":
			return String(data.buildables[id(i)]["name"])
		"item":
			return data.item_name(id(i))
	return ""


func to_array() -> Array:
	return slots.duplicate()


## Loads a saved hotbar. Entries the data no longer knows are dropped; an empty or missing list (a save from
## before the hotbar) gives the defaults.
func load_array(saved: Array) -> void:
	if saved.is_empty():
		reset()
		return
	slots = []
	for i in SLOTS:
		var e := String(saved[i]) if i < saved.size() else ""
		slots.append(e if validate(e) == "" else "")
