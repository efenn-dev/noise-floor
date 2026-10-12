class_name InputSetup
extends RefCounted
## The one place input actions are registered (instead of hand-editing project.godot).

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C],
	"flashlight": [KEY_F],
	"free_mouse": [KEY_ESCAPE],
	"build_mode": [KEY_B],
	"build_rotate": [KEY_R],
	"build_pick_1": [KEY_1],
	"build_pick_2": [KEY_2],
}
const MOUSE := {
	"build_place": MOUSE_BUTTON_LEFT,
	"build_remove": MOUSE_BUTTON_RIGHT,
}


static func register() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE[action]
		InputMap.action_add_event(action, mb)
