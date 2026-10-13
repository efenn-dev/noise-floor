class_name InputSetup
extends RefCounted
## The one place input actions are registered (instead of hand-editing project.godot).
## P3: every action here needs a row in HelpScreen.ROWS (test_help_screen.gd checks it).

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
	"build_mode": [KEY_B],  # S3: opens the build menu
	"build_rotate": [KEY_R],
	# S3: the hotbar (Hotbar): each key builds the piece or uses the item on that slot, anywhere on foot.
	"hotbar_1": [KEY_1],
	"hotbar_2": [KEY_2],
	"hotbar_3": [KEY_3],
	"hotbar_4": [KEY_4],
	"hotbar_5": [KEY_5],
	"hotbar_6": [KEY_6],
	"hotbar_7": [KEY_7],
	"hotbar_8": [KEY_8],
	"hotbar_9": [KEY_9],
	"hotbar_10": [KEY_0],
	"inventory": [KEY_TAB, KEY_I],
	"eat": [KEY_Z],
	"drink": [KEY_X],
	"bandage": [KEY_H],
	"siphon": [KEY_G],
	"refuel": [KEY_R],  # R also turns pieces, but only in build mode
	"repair": [KEY_T],
	"interact": [KEY_E],
	"upgrade": [KEY_U],
	"noise_overlay": [KEY_N],
	"skills": [KEY_K],  # the skills and perks screen (M12)
	"base_log": [KEY_L],  # M15: the base log screen
	"swap_hands": [KEY_Q],  # M14: melee weapon or gun in your hands (R reloads, via "refuel", when on foot)
	"help": [KEY_F1],  # P3: the controls screen (HelpScreen describes every action here)
}
const MOUSE := {
	"build_place": MOUSE_BUTTON_LEFT,
	"build_remove": MOUSE_BUTTON_RIGHT,
	"attack": MOUSE_BUTTON_LEFT,
	"build_next": MOUSE_BUTTON_WHEEL_DOWN,
	"build_prev": MOUSE_BUTTON_WHEEL_UP,
	"aim": MOUSE_BUTTON_RIGHT,  # P2: hold to zoom with a scope (in build mode right click removes instead)
}


## Tests set this: headless runs can't really lock the mouse, but input should act as if it were.
static var assume_captured := false


## True while the mouse is locked to the game (look around, swing, build).
static func captured() -> bool:
	return assume_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## S3: the hotbar slot (0-9) an event's action presses, or -1.
static func hotbar_slot(event: InputEvent) -> int:
	for i in 10:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			return i
	return -1


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
