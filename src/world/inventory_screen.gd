class_name InventoryScreen
extends CanvasLayer
## Tab: your pockets beside the nearest storage crate within reach. Click an item to see it and use,
## move or drop it; shift-click moves the whole stack to the other side, ctrl-click moves one.
## The game keeps running (a zombie can walk up while you sort). The rules are in the sim
## (use_item, drop_items, move_container_item/gear, take_all, equipment checks); this only shows them.
## M13/V14 slots: gear pieces sit after the stacks; the center paper doll shows every equipped slot.
## V18: searched world loot uses the same screen, and every tile/slot/hotbar key is a drag target.

class DragButton:
	extends Button
	var screen: InventoryScreen
	var drag_value := ""
	var drag_side := ""
	var drop_target := ""

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if screen == null or drag_value == "":
			return null
		var data := screen.drag_data(drag_value, drag_side, Input.is_key_pressed(KEY_CTRL))
		if data.is_empty():
			return null
		screen.begin_drag(data)
		set_drag_preview(screen.drag_preview(data))
		return data

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if screen == null or not data is Dictionary:
			return false
		return screen.can_drop(data, drop_target)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if screen != null:
			screen.drop_data(data, drop_target)


class DropGrid:
	extends GridContainer
	var screen: InventoryScreen
	var drop_target := ""

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if screen == null or not data is Dictionary:
			return false
		return screen.can_drop(data, drop_target)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if screen != null:
			screen.drop_data(data, drop_target)

class CharacterSilhouette:
	extends Control

	func _draw() -> void:
		var ink := Color(0.42, 0.43, 0.46, 0.14)  # faint: the slot tiles are what you read
		draw_circle(Vector2(164, 48), 28.0, ink)
		draw_rect(Rect2(136, 77, 56, 112), ink, true)
		draw_line(Vector2(137, 96), Vector2(87, 170), ink, 20.0, true)
		draw_line(Vector2(191, 96), Vector2(241, 170), ink, 20.0, true)
		draw_line(Vector2(150, 184), Vector2(132, 276), ink, 24.0, true)
		draw_line(Vector2(178, 184), Vector2(196, 276), ink, 24.0, true)

signal message(text: String)

const SLOT := Vector2(78, 78)
const COLS := 4
const POCKETS := "pockets"
const CRATE := "crate"
const WORN := "worn"
const MOD := "mod"
const GEAR := "gear:"  # a selected gear piece is "gear:<uid>"
const BAG := "bag:"    # the worn stackable bag is "bag:<item>"
const MOD_PART := "modpart:"  # a fitted slot drag is "modpart:<slot>"
const SLOT_NAMES := {"weapon": "Melee", "head": "Head", "body": "Body", "hands": "Hands", "legs": "Legs",
		"feet": "Feet", "back": "Back", "light": "Light", "primary": "Primary", "sidearm": "Sidearm",
		"part": "Firearm part"}
const DOLL_SIZE := Vector2(328, 382)
const SLOT_RECTS := {
		"head": Rect2(128, 5, 72, 68), "body": Rect2(128, 83, 72, 72),
		"hands": Rect2(38, 100, 72, 72), "legs": Rect2(128, 166, 72, 72),
		"feet": Rect2(128, 249, 72, 68), "back": Rect2(218, 100, 72, 72),
		"light": Rect2(218, 17, 72, 68), "weapon": Rect2(4, 326, 76, 54),
		"primary": Rect2(89, 326, 128, 54), "sidearm": Rect2(226, 326, 98, 54),
}

static var _icons: Dictionary = {}

var sim: SimWorld
var _root: Control
var _pockets_grid: GridContainer
var _crate_grid: GridContainer
var _crate_title: Label
var _crate_prev: Button
var _crate_next: Button
var _weight_label: Label
var _weight_bar: ProgressBar
var _details: Label
var _wearing: Control
var _actions: HBoxContainer
var _mod_panel: PanelContainer
var _mod_gun_name: Label
var _mod_gun_picture: Control
var _mod_slots: HBoxContainer
var _mod_stats: GridContainer
var _hotbar_targets: Array[Button] = []
var _crates: Array = []  # crate keys within reach, nearest first
var _crate_index := 0
var _container_id := ""
var _open_health := 0.0
var _invalid_drop_shown := false
var _drag_data: Dictionary = {}
var _selected := ""
var _selected_side := ""
var _mod_gun_uid := -1


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_crates = sim.crates_near(sim.player_pos)
	_crate_index = 0
	_container_id = _crates[0] if not _crates.is_empty() else ""
	_selected = ""
	_selected_side = ""
	_mod_gun_uid = -1
	_open_health = sim.player.health
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


## E on a searched fridge, trunk, corpse or crate opens that exact container.
func open_container(id: String) -> void:
	_crates = []
	_crate_index = 0
	_container_id = id
	_selected = ""
	_selected_side = ""
	_mod_gun_uid = -1
	_open_health = sim.player.health
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func close() -> void:
	_root.visible = false
	_container_id = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The crate on the right, or null if none is within reach.
func crate() -> Inventory:
	if _container_id == "":
		return null
	return sim.container_inventory(_container_id)


func container_id() -> String:
	return _container_id


func _process(_delta: float) -> void:
	if not is_open() or _container_id == "":
		return
	if sim.player.health < _open_health - 0.001:
		message.emit("Loot closed: you were hurt")
		close()
	elif not sim.container_exists(_container_id) or not sim.container_in_reach(_container_id):
		message.emit("Loot closed: too far away")
		close()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("free_mouse"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		take_selected()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("refuel") and _container_id != "":
		take_everything()
		get_viewport().set_input_as_handled()
		return
	var slot := InputSetup.hotbar_slot(event)
	if slot != -1:
		message.emit(assign_hotbar(slot))  # S3: 1-9, 0 puts the picked item on that key
		get_viewport().set_input_as_handled()


## Godot only calls _drop_data for accepted targets. On a refused release, find the hovered target
## after NOTIFICATION_DRAG_END and explain why the preview snapped back.
func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or _drag_data.is_empty() or not is_inside_tree():
		return
	if not get_viewport().gui_is_drag_successful():
		var hovered := get_viewport().gui_get_hovered_control()
		var target := ""
		if hovered is DragButton:
			target = (hovered as DragButton).drop_target
		elif hovered is DropGrid:
			target = (hovered as DropGrid).drop_target
		var why := drop_reason(_drag_data, target)
		if why != "":
			message.emit(why)
	_drag_data = {}


## S3: puts the selected pocket item on hotbar key `i` (0-9). V19: a selected weapon (worn or in your pockets)
## puts its slot on the key instead, so the key draws whatever weapon you have in that slot. Returns the message.
func assign_hotbar(i: int) -> String:
	if _selected.begins_with(GEAR):
		var piece := selected_gear()
		var slot := sim.gear.slot_of(piece) if not piece.is_empty() else ""
		if not Hotbar.WEAPON_SLOTS.has(slot):
			return "Only weapons, food, drink and bandages go on the hotbar"
		var why_slot := sim.hotbar.assign(i, Hotbar.slot_entry(slot))
		refresh()
		return why_slot if why_slot != "" else "%s (%s) is on key %s" % [Hotbar.WEAPON_SLOTS[slot], piece["name"], Hotbar.key_name(i)]
	if _selected == "" or _selected_side != POCKETS:
		return "Click an item in your pockets first"
	var why := sim.assign_hotbar_item(i, _selected)
	refresh()
	return why if why != "" else "%s is on key %s" % [_name(_selected), Hotbar.key_name(i)]


# --- What the clicks do (tests call these directly) ---------------------------

func select(item: String, side: String) -> void:
	_selected = item
	_selected_side = side
	refresh()


## Moves one or the whole stack of `item` from `side` to the other side.
func move(item: String, side: String, whole_stack: bool) -> void:
	var from := sim.inventory if side == POCKETS else crate()
	if from == null or crate() == null:
		message.emit("No container within reach")
		return
	var result := sim.move_container_item(_container_id, item, from.count(item) if whole_stack else 1, side != POCKETS)
	if result["why"] != "":
		message.emit(result["why"])
	refresh()


## M13: selects a gear piece (in your pockets, or WORN).
func select_gear(uid: int, side: String = POCKETS) -> void:
	_selected = GEAR + str(uid)
	_selected_side = side
	var piece := _gear_at(uid, side)
	if sim.gear.is_gun(piece):
		_mod_gun_uid = uid
	refresh()


func select_bag(item: String) -> void:
	select(BAG + item, WORN)


func selected_gear() -> Dictionary:
	if not _selected.begins_with(GEAR):
		return {}
	var uid := int(_selected.trim_prefix(GEAR))
	if _selected_side == CRATE:
		for piece: Dictionary in sim.container_gear(_container_id):
			if int(piece["uid"]) == uid:
				return piece
		return {}
	return sim.gear.find(uid)


func _gear_at(uid: int, side: String) -> Dictionary:
	if side == CRATE:
		for piece: Dictionary in sim.container_gear(_container_id):
			if int(piece["uid"]) == uid:
				return piece
		return {}
	return sim.gear.find(uid)


func selected_mod_gun() -> Dictionary:
	return sim.gun_piece(_mod_gun_uid, _container_id)


func fit_part(uid: int, slot: String = "") -> void:
	message.emit(sim.attach_part_to_gun(_mod_gun_uid, uid, slot, _container_id))
	refresh()


func remove_part(slot: String) -> void:
	message.emit(sim.detach_part_from_gun(_mod_gun_uid, slot, _container_id))
	refresh()


func equip_selected() -> void:
	message.emit(sim.equip_gear(int(_selected.trim_prefix(GEAR))))
	_selected_side = WORN
	refresh()


func equip_bag_selected() -> void:
	message.emit(sim.equip_bag(_selected))
	refresh()


func unequip_selected() -> void:
	var piece := selected_gear()
	if not piece.is_empty():
		message.emit(sim.unequip_gear(sim.gear.slot_of(piece)))
		_selected_side = POCKETS
	refresh()


func repair_selected() -> void:
	message.emit(sim.repair_gear(int(_selected.trim_prefix(GEAR))))
	refresh()


func drop_gear_selected() -> void:
	message.emit(sim.drop_gear(int(_selected.trim_prefix(GEAR))))
	refresh()


func use_selected() -> void:
	message.emit(sim.use_item(_selected))
	refresh()


func drop_selected(whole_stack: bool) -> void:
	message.emit(sim.drop_items(_selected, sim.inventory.count(_selected) if whole_stack else 1))
	refresh()


## E or a double-click: while a container is open, move the selected stack/piece to the other side.
func take_selected() -> void:
	if _selected == "":
		message.emit("Click an item first")
		return
	if _selected_side == WORN:
		message.emit("Drag worn gear back to your pockets")
		return
	if _container_id == "":
		message.emit("No container open")
		return
	if _selected.begins_with(GEAR):
		var result := sim.move_container_gear(_container_id, int(_selected.trim_prefix(GEAR)), _selected_side == CRATE)
		if result["why"] != "":
			message.emit(result["why"])
	else:
		var held := sim.inventory if _selected_side == POCKETS else crate()
		if held == null:
			message.emit("Container closed")
			return
		var result := sim.move_container_item(_container_id, _selected, held.count(_selected), _selected_side == CRATE)
		if result["why"] != "":
			message.emit(result["why"])
	refresh()


## R while looting: take every stack and piece that fits, and name what stayed behind.
func take_everything() -> void:
	if _container_id == "":
		return
	var result := sim.take_all(_container_id)
	var missed := PackedStringArray()
	for item: String in result["not_fit"]:
		missed.append("%d %s" % [result["not_fit"][item], _name(item)])
	for piece: String in result["gear_not_fit"]:
		missed.append(piece)
	if not missed.is_empty():
		message.emit("Too heavy: couldn't fit " + ", ".join(missed))
	elif result["items"].is_empty() and result["gear"].is_empty():
		message.emit("Nothing to take")
	else:
		message.emit("Took everything")
	refresh()


func _on_slot(item: String, side: String) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		move(item, side, true)
	elif Input.is_key_pressed(KEY_CTRL):
		move(item, side, false)
	else:
		select(item, side)


## Marks a double-click as used; tests drive these handlers on a screen that isn't in the tree.
func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_item_input(event: InputEvent, item: String, side: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		select(item, side)
		if _container_id != "":
			take_selected()
		elif side == POCKETS and sim.data.item_value(item, "bag") > 0.0:
			message.emit(sim.equip_bag(item))
		refresh()
		_handled()


func _on_gear_input(event: InputEvent, uid: int, side: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		var piece := _gear_at(uid, side)
		select_gear(uid, side)
		if not piece.is_empty() and sim.gear.slot_of(piece) == "part" and side == POCKETS and not selected_mod_gun().is_empty():
			fit_part(uid)
		elif _container_id != "" and side != WORN:
			take_selected()
		elif side == WORN:
			var worn_piece := sim.gear.find(uid)
			if not worn_piece.is_empty():
				message.emit(sim.unequip_gear(sim.gear.slot_of(worn_piece)))
		else:
			message.emit(sim.equip_gear(uid))
		refresh()
		_handled()


func _on_mod_slot_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		remove_part(slot)
		_handled()


func _on_equipment_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		message.emit(sim.unequip_gear(slot))
		refresh()
		_handled()


# --- Drag and drop --------------------------------------------------------------

func begin_drag(data: Dictionary = {}) -> void:
	_invalid_drop_shown = false
	_drag_data = data


## Public for tests: the data Godot carries between _get_drag_data and a drop target.
func drag_data(value: String, side: String, ctrl: bool = false) -> Dictionary:
	if value.begins_with(MOD_PART):
		var slot := value.trim_prefix(MOD_PART)
		var gun := selected_mod_gun()
		var part: Dictionary = gun.get("parts", {}).get(slot, {})
		return {} if part.is_empty() else {"kind": "gun_part", "uid": int(part["uid"]), "gun_uid": _mod_gun_uid,
				"slot": slot, "side": MOD, "amount": 1, "name": part["name"]}
	if value.begins_with(GEAR):
		var piece := {}
		var uid := int(value.trim_prefix(GEAR))
		if side == CRATE:
			for held: Dictionary in sim.container_gear(_container_id):
				if int(held["uid"]) == uid:
					piece = held
		else:
			piece = sim.gear.find(uid)
		return {} if piece.is_empty() else {"kind": "gear", "uid": uid, "side": side, "amount": 1,
				"name": piece["name"]}
	if value.begins_with(BAG):
		var bag := value.trim_prefix(BAG)
		return {"kind": "bag", "item": bag, "side": WORN, "amount": 1, "name": _name(bag)}
	var held := sim.inventory if side == POCKETS else crate()
	if held == null or held.count(value) <= 0:
		return {}
	return {"kind": "item", "item": value, "side": side,
			"amount": 1 if ctrl else held.count(value), "name": _name(value)}


func drag_preview(data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(64, 64)
	var value := str(data.get("item", ""))
	if data.get("kind", "") in ["gear", "gun_part"]:
		var piece := sim.gear.find(int(data["uid"]))
		if piece.is_empty() and data.get("kind", "") == "gun_part":
			piece = selected_mod_gun().get("parts", {}).get(str(data.get("slot", "")), {})
		if piece.is_empty():
			for held: Dictionary in sim.container_gear(_container_id):
				if int(held["uid"]) == int(data["uid"]):
					piece = held
		if not piece.is_empty():
			panel.add_child(gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], Vector2(64, 64), piece["base"]))
	else:
		var texture := icon_for(value)
		if texture != null:
			var picture := TextureRect.new()
			picture.texture = texture
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = Vector2(64, 64)
			panel.add_child(picture)
		else:
			var fallback := Label.new()
			fallback.text = _name(value)
			fallback.custom_minimum_size = Vector2(64, 64)
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			panel.add_child(fallback)
	var count := Label.new()
	count.text = str(data.get("amount", 1))
	count.position = Vector2(34, 38)
	count.add_theme_font_size_override("font_size", 18)
	count.add_theme_constant_override("outline_size", 5)
	panel.add_child(count)
	return panel


## Why this payload cannot land on pockets, the open container, slot:<name> or hotbar:<0-9>.
func drop_reason(data: Dictionary, target: String) -> String:
	if data.is_empty() or not data.has("kind") or not data.has("side"):
		return "Can't move that"
	var kind := str(data["kind"])
	var side := str(data["side"])
	if target == POCKETS:
		if side == POCKETS:
			return "Already in your pockets"
		if side == MOD and kind == "gun_part":
			return ""
		if side == WORN:
			if kind == "bag":
				return sim.can_unequip_gear("back")
			var worn := sim.gear.find(int(data.get("uid", -1)))
			return "Nothing there" if worn.is_empty() else sim.can_unequip_gear(sim.gear.slot_of(worn))
		if side != CRATE:
			return "Can't move that"
		return sim.can_take_container_gear(_container_id, int(data["uid"])) if kind == "gear" \
				else sim.can_take_container_item(_container_id, str(data["item"]), int(data["amount"]))
	if target == CRATE:
		if _container_id == "" or not sim.container_exists(_container_id) or not sim.container_in_reach(_container_id):
			return "No container within reach"
		return "" if side == POCKETS and kind in ["item", "gear"] else "Move it to your pockets first"
	if target.begins_with("mod:"):
		if selected_mod_gun().is_empty():
			return "Select a firearm first"
		if side != POCKETS:
			return "Move the part to your pockets first"
		if kind != "gear":
			return "Only firearm parts fit attachment slots"
		var piece := sim.gear.find(int(data["uid"]))
		if piece.is_empty() or sim.gear.slot_of(piece) != "part":
			return "Only firearm parts fit attachment slots"
		return sim.can_attach_part_to_gun(_mod_gun_uid, int(data["uid"]), target.trim_prefix("mod:"), _container_id)
	if target.begins_with("slot:"):
		if side != POCKETS:
			return "Move it to your pockets first"
		var slot := target.trim_prefix("slot:")
		if kind == "gear":
			return sim.can_equip_gear(int(data["uid"]), slot)
		if kind == "item":
			return sim.can_equip_item(str(data["item"]), slot)
		return "Doesn't fit that slot"
	if target.begins_with("hotbar:"):
		if side != POCKETS or kind != "item":
			return "Only pocket items go on the hotbar"
		return sim.hotbar.validate(Hotbar.item_entry(str(data["item"])))
	return "Can't move that"


func can_drop(data: Dictionary, target: String) -> bool:
	return drop_reason(data, target) == ""


## Public for tests: reports one short reason for a refused payload/target pair.
func check_drop(data: Variant, target: String) -> bool:
	if not data is Dictionary:
		return false
	var why := drop_reason(data, target)
	if why != "" and not _invalid_drop_shown:
		_invalid_drop_shown = true
		message.emit(why)
	return why == ""


func drop_data(data: Variant, target: String) -> String:
	if not data is Dictionary:
		return "Can't move that"
	var why := drop_reason(data, target)
	if why != "":
		message.emit(why)
		return why
	var result := ""
	var kind := str(data["kind"])
	var side := str(data["side"])
	if target == POCKETS and side == MOD:
		result = sim.detach_part_from_gun(int(data["gun_uid"]), str(data["slot"]), _container_id)
	elif target == POCKETS and side == WORN:
		var slot := "back" if kind == "bag" else sim.gear.slot_of(sim.gear.find(int(data["uid"])))
		result = sim.unequip_gear(slot)
	elif target == POCKETS:
		if kind == "gear":
			result = sim.move_container_gear(_container_id, int(data["uid"]), true)["why"]
		else:
			result = sim.move_container_item(_container_id, str(data["item"]), int(data["amount"]), true)["why"]
	elif target == CRATE:
		if kind == "gear":
			result = sim.move_container_gear(_container_id, int(data["uid"]), false)["why"]
		else:
			result = sim.move_container_item(_container_id, str(data["item"]), int(data["amount"]), false)["why"]
	elif target.begins_with("mod:"):
		result = sim.attach_part_to_gun(_mod_gun_uid, int(data["uid"]), target.trim_prefix("mod:"), _container_id)
	elif target.begins_with("slot:"):
		var slot := target.trim_prefix("slot:")
		result = sim.equip_gear_to_slot(int(data["uid"]), slot) if kind == "gear" \
				else sim.equip_item_to_slot(str(data["item"]), slot)
	elif target.begins_with("hotbar:"):
		var hotbar_slot := int(target.trim_prefix("hotbar:"))
		result = sim.assign_hotbar_item(hotbar_slot, str(data["item"]))
		if result == "":
			result = "%s is on key %s" % [_name(str(data["item"])), Hotbar.key_name(hotbar_slot)]
	if result != "":
		message.emit(result)
	refresh()
	return result


# --- Drawing -------------------------------------------------------------------

func refresh() -> void:
	if sim == null:
		return
	var box := crate()
	_fill(_pockets_grid, sim.inventory, POCKETS)
	_fill(_crate_grid, box, CRATE)
	if box == null:
		_crate_title.text = "No container within reach"
	elif _crates.size() > 1:
		_crate_title.text = "Crate %d of %d" % [_crate_index + 1, _crates.size()]
	else:
		_crate_title.text = sim.container_name(_container_id)
	_crate_prev.visible = _crates.size() > 1
	_crate_next.visible = _crates.size() > 1
	for i in _hotbar_targets.size():
		_hotbar_targets[i].text = "%s\n%s" % [Hotbar.key_name(i), sim.hotbar.label(i)]

	var carried := sim.carried_kg()
	var limit := sim.carry_limit()
	_weight_bar.max_value = limit
	_weight_bar.value = minf(carried, limit)
	var bag := str(sim.gear.equipped.get("back", ""))
	_weight_label.text = "Carrying %.1f / %.0f kg" % [carried, limit] \
			+ ("   (wearing %s +%d kg)" % [sim.data.item_name(bag), sim.data.item_value(bag, "bag")] if bag != "" else "")
	var over := carried > limit
	_weight_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if over else Color(0.9, 0.9, 0.85))
	_weight_bar.modulate = Color(1.0, 0.4, 0.3) if over else (Color(1.0, 0.85, 0.4) if carried > limit * 0.8 else Color.WHITE)
	if over:
		_weight_label.text += "   Overloaded: slower and louder"
	var mech := sim.skills.progress("mechanics")
	_weight_label.text += "\nMechanics %d%s" % [sim.skills.level("mechanics"),
			("  (%d / %d xp to the next level)" % [mech[0], mech[1]]) if mech[1] > 0 else ""]

	_fill_wearing()
	_fill_modding()
	if _selected.begins_with(BAG):
		var worn := _selected.trim_prefix(BAG)
		if str(sim.gear.equipped.get("back", "")) != worn:
			_selected = ""
		_show_bag(worn)
		return
	if _selected.begins_with(GEAR):
		var piece := selected_gear()
		if piece.is_empty() or (_selected_side in [POCKETS, WORN] \
				and sim.gear.is_equipped(piece["uid"]) != (_selected_side == WORN)):
			_selected = ""  # dropped, or moved between pockets and slots
		_show_gear(piece)
		return
	var held := sim.inventory if _selected_side == POCKETS else box
	if _selected != "" and (held == null or held.count(_selected) == 0):
		_selected = ""  # used up or moved away
	_show_details(held)


func _fill(grid: GridContainer, inv: Inventory, side: String) -> void:
	for child in grid.get_children():
		child.queue_free()
	if inv == null:
		return
	for item: String in inv.items():
		grid.add_child(_slot(item, inv.count(item), side))
	if side == POCKETS:
		for piece: Dictionary in sim.gear.pieces:
			grid.add_child(_gear_slot(piece, POCKETS))
	elif side == CRATE:
		for piece: Dictionary in sim.container_gear(_container_id):
			grid.add_child(_gear_slot(piece, CRATE))


## A carried gear tile: base icon when available, rarity border, and condition in the corner.
func _gear_slot(piece: Dictionary, side: String) -> Button:
	var b := DragButton.new()
	b.screen = self
	b.drag_value = GEAR + str(piece["uid"])
	b.drag_side = side
	b.drop_target = side
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == side
	b.tooltip_text = piece["name"]
	b.name = "Gear%d" % piece["uid"]
	var icon := gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], SLOT - Vector2(16, 16), piece["base"])
	icon.position = Vector2(8, 8)
	b.add_child(icon)
	var n := Label.new()
	n.text = "%d%%" % roundi(float(piece["condition"]) * 100.0)
	n.position = SLOT - Vector2(52, 28)
	n.size = Vector2(46, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 16)
	n.add_theme_constant_override("outline_size", 6)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if not sim.gear.working(piece) else Color.WHITE)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	b.pressed.connect(select_gear.bind(int(piece["uid"]), side))
	b.gui_input.connect(_on_gear_input.bind(int(piece["uid"]), side))
	return b


## Gear icon with a rarity border: use the base's picture when it exists, otherwise its first letter.
static func gear_icon(color: Color, base_name: String, size: Vector2, item_id: String = "") -> Control:
	var panel := Panel.new()
	panel.size = size
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(size.x * 0.18))
	panel.add_theme_stylebox_override("panel", style)
	var texture := icon_for(item_id)
	if texture != null:
		var picture := TextureRect.new()
		picture.name = "Icon"
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # first: otherwise the 256 px picture sets a minimum size
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2(4, 4)
		picture.size = size - Vector2(8, 8)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(picture)
	else:
		var letter := Label.new()
		letter.name = "Placeholder"
		letter.text = base_name.left(1).to_upper()
		letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", int(size.y * 0.5))
		letter.add_theme_color_override("font_color", color)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(letter)
	return panel


## Paper doll: a positioned tile for every equipment slot, with firearms in the row underneath.
func _fill_wearing() -> void:
	for child in _wearing.get_children():
		if child is Button:
			_wearing.remove_child(child)  # now, so the new row can take its name
			child.queue_free()
	for slot: String in sim.gear.slots():
		var b := DragButton.new()
		b.screen = self
		b.drop_target = "slot:" + slot
		b.focus_mode = Control.FOCUS_NONE
		b.name = "Slot_" + slot
		var rect: Rect2 = SLOT_RECTS[slot]
		b.position = rect.position
		b.size = rect.size
		b.custom_minimum_size = rect.size
		b.add_theme_font_size_override("font_size", 14 if slot in ["primary", "sidearm"] else 15)
		var value: Variant = sim.gear.equipped.get(slot)
		if value == null:
			b.text = SLOT_NAMES[slot]
			b.add_theme_stylebox_override("normal", _empty_slot_style())
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62, 0.55))
		elif slot == "back":
			var item := str(value)
			b.drag_value = BAG + item
			b.drag_side = WORN
			b.tooltip_text = sim.data.item_name(item)
			var icon := gear_icon(sim.data.item_color(item), SLOT_NAMES[slot], rect.size - Vector2(10, 10), item)
			icon.position = Vector2(5, 5)
			b.add_child(icon)
			b.toggle_mode = true
			b.button_pressed = _selected == BAG + item
			b.pressed.connect(select_bag.bind(item))
			b.gui_input.connect(_on_equipment_input.bind(slot))
		else:
			var piece: Dictionary = value
			b.drag_value = GEAR + str(piece["uid"])
			b.drag_side = WORN
			b.add_theme_color_override("font_color", sim.gear.color(piece))
			b.add_theme_color_override("font_hover_color", sim.gear.color(piece).lightened(0.3))
			b.tooltip_text = "%s · %s" % [piece["name"], sim.gear.condition_text(piece)]
			b.toggle_mode = true
			b.button_pressed = _selected == GEAR + str(piece["uid"]) and _selected_side == WORN
			b.pressed.connect(select_gear.bind(int(piece["uid"]), WORN))
			b.gui_input.connect(_on_gear_input.bind(int(piece["uid"]), WORN))
			var icon := gear_icon(sim.gear.color(piece), sim.gear.base_of(piece)["name"], rect.size - Vector2(10, 10), piece["base"])
			icon.position = Vector2(5, 5)
			b.add_child(icon)
			var condition := ColorRect.new()
			condition.name = "Condition"
			condition.color = Color(0.35, 0.9, 0.4) if float(piece["condition"]) >= 0.6 else Color(1.0, 0.7, 0.2)
			condition.position = Vector2(5, rect.size.y - 7)
			condition.size = Vector2((rect.size.x - 10) * float(piece["condition"]), 3)
			condition.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(condition)
		_wearing.add_child(b)


## The selected firearm's data-driven attachment points and sim-computed stat deltas.
func _fill_modding() -> void:
	for child in _mod_gun_picture.get_children():
		_mod_gun_picture.remove_child(child)
		child.queue_free()
	for box: Control in [_mod_slots, _mod_stats]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var gun := selected_mod_gun()
	_mod_panel.visible = not gun.is_empty()
	_details.visible = gun.is_empty()
	_actions.visible = gun.is_empty()
	if gun.is_empty():
		_mod_gun_uid = -1
		return
	_mod_gun_name.text = "%s  ·  MODDING" % gun["name"]
	var gun_icon := gear_icon(sim.gear.color(gun), sim.gear.base_of(gun)["name"], Vector2(104, 104), gun["base"])
	_mod_gun_picture.add_child(gun_icon)
	for slot_value: Variant in sim.gear.gun_part_slots(gun):
		var slot := str(slot_value)
		var part: Dictionary = gun.get("parts", {}).get(slot, {})
		var b := DragButton.new()
		b.screen = self
		b.name = "ModSlot_" + slot
		b.drop_target = "mod:" + slot
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(86, 78)
		b.add_theme_font_size_override("font_size", 13)
		if part.is_empty():
			b.text = slot.capitalize()
			b.tooltip_text = "Empty %s slot · drag a matching pocket part here" % slot
			b.add_theme_stylebox_override("normal", _empty_slot_style())
		else:
			b.drag_value = MOD_PART + slot
			b.drag_side = MOD
			b.tooltip_text = "%s · %s · drag to Pockets or double-click to remove" % [part["name"],
					sim.gear.part_text(part)]
			var icon := gear_icon(sim.gear.color(part), sim.gear.base_of(part)["name"], Vector2(70, 62), part["base"])
			icon.position = Vector2(8, 3)
			b.add_child(icon)
			var label := Label.new()
			label.text = slot.capitalize()
			label.position = Vector2(3, 57)
			label.size = Vector2(80, 18)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_constant_override("outline_size", 4)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(label)
			b.gui_input.connect(_on_mod_slot_input.bind(slot))
		_mod_slots.add_child(b)
	for row: Dictionary in sim.gear.gun_stat_rows(gun):
		var label := Label.new()
		label.text = str(row["label"])
		label.add_theme_font_size_override("font_size", 15)
		_mod_stats.add_child(label)
		var value := Label.new()
		value.text = str(row["value"])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 15)
		_mod_stats.add_child(value)
		var delta := Label.new()
		delta.text = str(row["delta_text"])
		delta.custom_minimum_size = Vector2(58, 0)
		delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta.add_theme_font_size_override("font_size", 15)
		if delta.text != "":
			delta.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45) if row["better"] else Color(1.0, 0.38, 0.3))
		_mod_stats.add_child(delta)


func mod_slot(slot: String) -> Button:
	return _mod_slots.find_child("ModSlot_" + slot, true, false) as Button


func mod_panel_visible() -> bool:
	return _mod_panel.visible


## V14: an empty slot is a dark tile with a thin grey edge, so you can see where things go.
static func _empty_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.08, 0.9)
	style.border_color = Color(0.45, 0.45, 0.48, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _show_bag(item: String) -> void:
	for child in _actions.get_children():
		child.queue_free()
	if item == "" or _selected == "":
		_details.text = "Click an item to see it.  Double-click gear or a bag to equip it."
		return
	_details.remove_theme_color_override("font_color")
	_details.text = "%s\nBack slot · %.1f kg · +%d kg carrying capacity" % [sim.data.item_name(item),
			sim.data.item_weight(item), sim.data.item_value(item, "bag")]
	_action("Unequip", unequip_bag_selected)


func unequip_bag_selected() -> void:
	message.emit(sim.unequip_gear("back"))
	_selected = ""
	refresh()


## The details for a gear piece: its name in the rarity colour, what it is, its condition and stats.
func _show_gear(piece: Dictionary) -> void:
	for child in _actions.get_children():
		child.queue_free()
	if piece.is_empty() or _selected == "":
		_details.remove_theme_color_override("font_color")
		_details.text = "Click for details.  Double-click gear or a bag to equip it.  Shift-click moves a stack."
		return
	var g := sim.gear
	var rarity: Dictionary = sim.data.gear["rarities"][piece["rarity"]]
	var tier: Dictionary = sim.data.gear["tiers"][piece["tier"]]
	var lines := [piece["name"], "%s · %s %s · %s slot · %.1f kg · %s" % [rarity["name"], tier["name"],
			g.base_of(piece)["name"].to_lower(), SLOT_NAMES[g.slot_of(piece)].to_lower(),
			float(g.base_of(piece)["weight"]), g.condition_text(piece)]]
	var stats := g.stat_lines(piece)
	for i in range(0, stats.size(), 2):  # two to a line
		lines.append("    ".join(PackedStringArray(stats.slice(i, i + 2))))
	_details.text = "\n".join(lines)
	_details.add_theme_color_override("font_color", g.color(piece))
	if _selected_side == WORN:
		_action("Unequip", unequip_selected)
	elif _selected_side == CRATE:
		_action("Take", take_selected)
	elif g.slot_of(piece) == "part":
		if not selected_mod_gun().is_empty():
			_action("Fit to %s" % selected_mod_gun()["name"], fit_part.bind(int(piece["uid"])))
		_action("Drop", drop_gear_selected)
	else:
		_action("Equip", equip_selected)
		_action("Drop", drop_gear_selected)
	if _selected_side != CRATE and sim.inventory.count("repair_kit") > 0 and float(piece["condition"]) < 1.0:
		_action("Repair (1 kit)", repair_selected)


func _slot(item: String, count: int, side: String) -> Button:
	var b := DragButton.new()
	b.screen = self
	b.drag_value = item
	b.drag_side = side
	b.drop_target = side
	b.custom_minimum_size = SLOT
	b.focus_mode = Control.FOCUS_NONE  # keep Tab for closing
	b.toggle_mode = true
	b.button_pressed = item == _selected and side == _selected_side
	b.tooltip_text = _name(item)
	var icon := _icon(item)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:  # no picture yet: a coloured tile with the name
		b.text = _name(item)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_color_override("font_color", sim.data.item_color(item))
	var n := Label.new()
	n.text = str(count)
	n.position = SLOT - Vector2(40, 28)  # bottom-right corner of the slot
	n.size = Vector2(34, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 18)
	n.add_theme_constant_override("outline_size", 6)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	b.pressed.connect(_on_slot.bind(item, side))
	b.gui_input.connect(_on_item_input.bind(item, side))
	return b


func _show_details(held: Inventory) -> void:
	for child in _actions.get_children():
		child.queue_free()
	_details.remove_theme_color_override("font_color")
	if _selected == "":
		_details.text = "Click for details.  Double-click gear or a bag to equip it.  Shift-click moves a stack."
		return
	var d := sim.data
	var n := held.count(_selected)
	var lines := ["%s  x%d" % [_name(_selected), n],
			"%.2f kg each, %.1f kg in all" % [d.item_weight(_selected), d.item_weight(_selected) * n]]
	var effects := []
	if d.item_value(_selected, "food") > 0.0:
		effects.append("Food +%d" % d.item_value(_selected, "food"))
	if d.item_value(_selected, "water") > 0.0:
		effects.append("Water +%d" % d.item_value(_selected, "water"))
	if d.item_value(_selected, "bandage") > 0.0:
		effects.append("Stops bleeding")
	if d.item_value(_selected, "bag") > 0.0:
		effects.append("Bag: +%d kg carrying when equipped on your back" % d.item_value(_selected, "bag"))
	if not effects.is_empty():
		lines.append(", ".join(effects))
	if _selected_side == POCKETS and sim.hotbar.usable(_selected):  # S3
		var slot := sim.hotbar.find(Hotbar.item_entry(_selected))
		lines.append(("On key %s. " % Hotbar.key_name(slot) if slot != -1 else "") + "Press 1-9 or 0 to put it on that hotbar key.")
	_details.text = "\n".join(lines)

	var arrow := "->" if _selected_side == POCKETS else "<-"
	if _selected_side == POCKETS and sim.can_use(_selected):
		_action("Use", use_selected)
	if _selected_side == POCKETS and d.item_value(_selected, "bag") > 0.0:
		_action("Equip", equip_bag_selected)
	if crate() != null:
		_action("Move 1 " + arrow, move.bind(_selected, _selected_side, false))
		_action("Move all " + arrow, move.bind(_selected, _selected_side, true))
	if _selected_side == POCKETS:
		_action("Drop 1", drop_selected.bind(false))
		_action("Drop all", drop_selected.bind(true))


## Item names, with car keys saying which car they start.
func _name(item: String) -> String:
	if item.begins_with(GameData.CAR_KEY):
		var car := item.trim_prefix(GameData.CAR_KEY)
		if sim.vehicles.cars.has(car):
			return "Car key (%s)" % sim.vehicles.stats(car)["name"]
	return sim.data.item_name(item)


func _action(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(callback)
	_actions.add_child(b)


## S3: an item's picture, for the hotbar too (null when there is none yet).
static func icon_for(item: String) -> Texture2D:
	return _icon(item)


static func _icon(item: String) -> Texture2D:
	if item.begins_with(GameData.CAR_KEY):
		item = "car_key"  # every car's key looks the same
	if not _icons.has(item):
		var path := "res://assets/icons/%s.png" % item
		_icons[item] = load(path) if ResourceLoader.exists(path) else null
	return _icons[item]


static func clear_cache() -> void:
	_icons.clear()


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.02, 0.02, 0.03, 0.82)  # V14: dark enough that the world and held weapon don't show through the doll
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
	sides.add_theme_constant_override("separation", 18)
	column.add_child(sides)

	var left := VBoxContainer.new()
	sides.add_child(left)
	left.add_child(_title("Pockets"))
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 18)
	left.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(0, 10)
	left.add_child(_weight_bar)
	_pockets_grid = _grid(left, POCKETS)

	var character := VBoxContainer.new()
	character.custom_minimum_size = Vector2(DOLL_SIZE.x, 0)
	sides.add_child(character)
	character.add_child(_title("Character"))
	_wearing = CharacterSilhouette.new()
	_wearing.custom_minimum_size = DOLL_SIZE
	_wearing.mouse_filter = Control.MOUSE_FILTER_PASS
	character.add_child(_wearing)

	var right := VBoxContainer.new()
	sides.add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	_crate_title = _title("Crate")
	head.add_child(_crate_title)
	_crate_prev = _small_button("<", func() -> void: _cycle(-1))
	_crate_next = _small_button(">", func() -> void: _cycle(1))
	head.add_child(_crate_prev)
	head.add_child(_crate_next)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 41)  # line up with the pockets' weight label and bar
	right.add_child(spacer)
	_crate_grid = _grid(right, CRATE)

	_mod_panel = PanelContainer.new()
	_mod_panel.name = "ModdingPanel"
	_mod_panel.visible = false
	column.add_child(_mod_panel)
	var mod_margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		mod_margin.add_theme_constant_override("margin_" + side, 8)
	_mod_panel.add_child(mod_margin)
	var mod_row := HBoxContainer.new()
	mod_row.add_theme_constant_override("separation", 14)
	mod_margin.add_child(mod_row)
	var gun_box := VBoxContainer.new()
	gun_box.custom_minimum_size = Vector2(180, 112)
	_mod_gun_name = Label.new()
	_mod_gun_name.add_theme_font_size_override("font_size", 17)
	_mod_gun_name.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	gun_box.add_child(_mod_gun_name)
	_mod_gun_picture = Control.new()
	_mod_gun_picture.custom_minimum_size = Vector2(104, 104)
	gun_box.add_child(_mod_gun_picture)
	mod_row.add_child(gun_box)
	var slots_box := VBoxContainer.new()
	slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slots_title := Label.new()
	slots_title.text = "ATTACHMENT SLOTS  ·  drag from Pockets · double-click/drag off to remove"
	slots_title.add_theme_font_size_override("font_size", 14)
	slots_title.modulate = Color(1, 1, 1, 0.65)
	slots_box.add_child(slots_title)
	_mod_slots = HBoxContainer.new()
	_mod_slots.add_theme_constant_override("separation", 6)
	slots_box.add_child(_mod_slots)
	mod_row.add_child(slots_box)
	var stats_box := VBoxContainer.new()
	stats_box.custom_minimum_size = Vector2(280, 0)
	var stats_title := Label.new()
	stats_title.text = "WEAPON STATS  ·  fitted change"
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.modulate = Color(1, 1, 1, 0.65)
	stats_box.add_child(stats_title)
	_mod_stats = GridContainer.new()
	_mod_stats.columns = 3
	_mod_stats.add_theme_constant_override("h_separation", 8)
	_mod_stats.add_theme_constant_override("v_separation", 1)
	stats_box.add_child(_mod_stats)
	mod_row.add_child(stats_box)

	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 20)
	_details.custom_minimum_size = Vector2(0, 84)
	column.add_child(_details)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.custom_minimum_size = Vector2(0, 44)
	column.add_child(_actions)
	var hotbar_row := HBoxContainer.new()
	hotbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar_row.add_theme_constant_override("separation", 4)
	column.add_child(hotbar_row)
	for i in Hotbar.SLOTS:
		var target := DragButton.new()
		target.name = "HotbarDrop%d" % i
		target.screen = self
		target.drop_target = "hotbar:" + str(i)
		target.focus_mode = Control.FOCUS_NONE
		target.custom_minimum_size = Vector2(58, 44)
		target.text = "%s\n%s" % [Hotbar.key_name(i), sim.hotbar.label(i)]
		target.add_theme_font_size_override("font_size", 12)
		target.tooltip_text = "Drop a pocket item here to assign key %s" % Hotbar.key_name(i)
		hotbar_row.add_child(target)
		_hotbar_targets.append(target)
	var hint := Label.new()
	hint.text = "E/double-click: stack  ·  R: all  ·  Ctrl-click/drag: one  ·  Shift-click/plain drag: stack  ·  1-9/0: hotbar  ·  Tab/Esc: close  ·  Live game"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)


func _cycle(step: int) -> void:
	if _crates.size() > 1:
		_crate_index = (_crate_index + step + _crates.size()) % _crates.size()
		_container_id = _crates[_crate_index]
		if _selected_side == CRATE:
			_selected = ""
		refresh()


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	return l


func _grid(parent: Control, target: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS * (SLOT.x + 6), 3 * (SLOT.y + 6))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid := DropGrid.new()
	grid.screen = self
	grid.drop_target = target
	grid.custom_minimum_size = Vector2(COLS * (SLOT.x + 6), 3 * (SLOT.y + 6))
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return grid


func _small_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 36)
	b.pressed.connect(callback)
	return b
