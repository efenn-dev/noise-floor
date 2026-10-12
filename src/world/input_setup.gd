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
	"free_mouse": [KEY_ESCAPE],  # opens the pause menu
	"quicksave": [KEY_F5],
	"quickload": [KEY_F9],
	"build_mode": [KEY_B],
	"build_rotate": [KEY_R],
	"build_pick_1": [KEY_1],
	"build_pick_2": [KEY_2],
	"build_pick_3": [KEY_3],
	"build_pick_4": [KEY_4],
	"build_pick_5": [KEY_5],
	"build_pick_6": [KEY_6],
	"build_pick_7": [KEY_7],
	"build_pick_8": [KEY_8],
	"build_pick_9": [KEY_9],
	"build_pick_10": [KEY_0],
	"eat": [KEY_Z],
	"drink": [KEY_X],
	"bandage": [KEY_H],
	"siphon": [KEY_G],
	"repair": [KEY_T],
	"interact": [KEY_E],
	"upgrade": [KEY_U],
	"noise_overlay": [KEY_N],
}
const MOUSE := {
	"build_place": MOUSE_BUTTON_LEFT,
	"build_remove": MOUSE_BUTTON_RIGHT,
	"attack": MOUSE_BUTTON_LEFT,
	"build_next": MOUSE_BUTTON_WHEEL_DOWN,
	"build_prev": MOUSE_BUTTON_WHEEL_UP,
}


## Tests set this: headless runs can't really lock the mouse, but input should act as if it were.
static var assume_captured := false


## True while the mouse is locked to the game (look around, swing, build).
static func captured() -> bool:
	return assume_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


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
