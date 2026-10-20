class_name NetGate
extends Node
## Co-op B: on a joiner's machine the game is a window onto the host's world, and doing things comes in Phase C, so
## this swallows the actions (E, swings, building, pockets, saving...) before the rest of the scene sees them, and
## says so now and then. Added last under Main, so it gets unhandled input first. Looking, walking, the map, the
## objectives, the help and the pause menu stay yours.

const BLOCKED := ["interact", "attack", "aim", "build_mode", "build_place", "build_remove", "build_next", "build_prev",
		"build_rotate", "inventory", "skills", "upgrade", "siphon", "repair", "refuel", "bandage", "eat", "drink",
		"quicksave", "quickload", "swap_hands", "quick_equip", "inspect"]
const SAY_EVERY := 3.0

var sim: SimWorld
var blocked := 0
var _said := -SAY_EVERY


func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	name = "NetGate"


func _unhandled_input(event: InputEvent) -> void:
	if not blocks(event):
		return
	get_viewport().set_input_as_handled()
	blocked += 1
	var now := Time.get_ticks_msec() / 1000.0
	if now - _said >= SAY_EVERY and sim != null and not sim.players.is_empty():
		_said = now
		sim.add_message("You're watching %s's world: doing things comes in the next update" % sim.players[0].name, 3.0)


static func blocks(event: InputEvent) -> bool:
	if InputSetup.hotbar_slot(event) != -1:
		return true
	for action: String in BLOCKED:
		if event.is_action_pressed(action):
			return true
	return false
