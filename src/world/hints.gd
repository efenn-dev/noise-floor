class_name Hints
extends Label
## First-game hints: one line at a time above the health bar, for a new game only (main.gd decides).
## Each moves on when the sim shows you did it, or after TIMEOUT seconds so it never nags.
## It's only a label: it never takes input or pauses anything.

const TIMEOUT := 90.0
const NOISE_SECONDS := 40.0  # the noise hint is just information, so it goes sooner
const STEPS := [
	"Find the crate next to you and press E (Tab looks inside)",
	"Press B and build a foundation and a smelter",
	"It's loud. Zombies hear it. Press N to see how far",
	"Wall it in, or press U on it to fit a muffler",
]

var sim: SimWorld
var inventory_screen: InventoryScreen  # optional: opening it counts as finding the crate
var overlay: Node3D  # optional: the noise overlay (N)
var step := 0
var _time := 0.0


func setup(p_sim: SimWorld, p_inventory: InventoryScreen = null, p_overlay: Node3D = null) -> void:
	sim = p_sim
	inventory_screen = p_inventory
	overlay = p_overlay
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 24)
	add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 5)
	text = STEPS[0]


func _process(delta: float) -> void:
	advance(delta)


## Moves the hints on by `delta` seconds of play. Returns the current step (STEPS.size() when done).
func advance(delta: float) -> int:
	if step < STEPS.size():
		_time += delta
		if _time >= TIMEOUT or _done(step):
			step += 1
			_time = 0.0
	visible = step < STEPS.size()
	if visible:
		text = "Tip: " + STEPS[step]
	return step


func _done(i: int) -> bool:
	match i:
		0:
			return sim.stats.used_crate or (inventory_screen != null and inventory_screen.is_open())
		1:
			return int(sim.stats.built.get("smelter", 0)) > 0
		2:
			return _time >= NOISE_SECONDS or (overlay != null and overlay.visible)
		3:
			return sim.stats.mufflers > 0 or _walls() >= 4
	return true


func _walls() -> int:
	var n := 0
	for key: String in sim.build.pieces:
		if sim.build.pieces[key]["id"] == "wall":
			n += 1
	return n
