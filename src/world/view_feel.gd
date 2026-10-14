class_name ViewFeel
extends Node
## V3 (Sprint 4): how the first-person view moves and reacts. The camera bobs with your steps, held items
## lag the mouse (sway) and bob too, shots, hits and getting hurt shake the view ("trauma"), a hit marker
## flashes at the crosshair, the screen edge goes red when you're hurt (and pulses while health is low),
## and the gun's kick is applied here. Melee and Shooter report what happened; ViewFeel watches the
## player's health itself. Presentation only, no game rules.
## Settings.head_bob off turns the bob, sway and shake off (for anyone who gets motion sick); the kick, the
## hit marker and the red edge stay.

const STEP_M := 0.75            # metres per footstep; one side-to-side bob cycle is two steps
const BOB_WALK := 0.03          # camera bob in metres at walking speed
const BOB_SPRINT := 0.055
const BOB_CROUCH := 0.015
const BOB_EASE := 8.0           # how fast the bob fades in and out when you start or stop
const HOLD_BOB_SCALE := 0.6     # held items bob a little less than the camera
const SWAY_PER_PX := 0.0009     # radians of lag per pixel of mouse movement
const SWAY_MAX := 0.06
const SWAY_RETURN := 9.0        # how fast held items catch up with the view
const TRAUMA_DECAY := 1.6       # trauma lost per second
const SHAKE_MAX_DEG := Vector3(2.2, 2.2, 3.0)  # pitch, yaw, roll at full trauma
const SHAKE_SPEED := 26.0
const TRAUMA_FIRE := {"pistol": 0.14, "hunting_rifle": 0.3}
const TRAUMA_MELEE_HIT := 0.12
const TRAUMA_MELEE_WALL := 0.06
const MARKER_TIME := 0.35
const HURT_DECAY := 1.4
const LOW_HEALTH := 35.0        # below this the red edge pulses

var sim: SimWorld
var player: Player
var camera: Camera3D
var kick := 0.0                 # radians, set by Shooter every frame
var trauma := 0.0
var hurt_flash := 0.0           # 0..1, jumps when you take damage
var marker_time := 0.0
var marker_color := Color.WHITE
var bob_phase := 0.0
var bob_amp := 0.0              # eased toward bob_amplitude(...)
var sway := Vector2.ZERO        # x = yaw lag, y = pitch lag, radians
var _time := 0.0
var _last_health := -1.0
var _noise := FastNoiseLite.new()
var _vignette: ColorRect
var _marker: HitMarker


func _init() -> void:
	process_priority = 10  # after Shooter has set this frame's kick
	_noise.seed = 7
	_noise.frequency = 1.0


func setup(p_sim: SimWorld, p_player: Player) -> void:
	sim = p_sim
	player = p_player
	camera = p_player.camera
	var layer := CanvasLayer.new()
	layer.layer = 0  # under the HUD text and every menu
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/world/hurt_vignette.gdshader")
	_vignette.material = mat
	layer.add_child(_vignette)
	_marker = HitMarker.new()
	_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_marker)


## Camera bob height for this speed (m/s on the ground), 0 when still or in the air.
static func bob_amplitude(speed: float, crouching: bool, on_floor: bool) -> float:
	if not on_floor or speed < 0.3:
		return 0.0
	if crouching:
		return BOB_CROUCH
	return lerpf(BOB_WALK, BOB_SPRINT, clampf((speed - Player.WALK_SPEED) / (Player.SPRINT_SPEED - Player.WALK_SPEED), 0.0, 1.0))


## How much of the shake to use at this trauma: squared, so small knocks stay small.
static func shake_amount(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func fired(base: String) -> void:
	add_trauma(float(TRAUMA_FIRE.get(base, 0.15)))


## A melee or gun hit on a zombie: the hit marker (red on a kill, yellow for the head, else white).
func hit_zombie(killed: bool, head: bool) -> void:
	marker_time = MARKER_TIME
	marker_color = Color(0.95, 0.15, 0.1) if killed else (Color(1.0, 0.85, 0.2) if head else Color.WHITE)


## A puff where something was struck: "blood" on a zombie, "dust" on anything else.
func impact(pos: Vector3, normal: Vector3, kind: String) -> void:
	var parent := get_parent() if get_parent() != null else self
	ImpactFx.spawn(parent, pos, normal, kind)


## Health watching: a drop flashes the red edge and shakes the view; a rise (healing, respawn) doesn't.
func note_health(health: float, dead: bool) -> void:
	if _last_health >= 0.0 and not dead and health < _last_health - 0.5:
		var dmg := _last_health - health
		hurt_flash = clampf(hurt_flash + dmg / 25.0, 0.0, 1.0)
		add_trauma(clampf(dmg / 30.0, 0.15, 0.6))
	_last_health = health


## Red edge strength 0..1 right now: the flash from a hit, or a pulse while health is low.
func vignette_strength(health: float) -> float:
	var pulse := 0.0
	if health < LOW_HEALTH:
		pulse = (1.0 - health / LOW_HEALTH) * (0.45 + 0.15 * sin(_time * 4.0))
	return clampf(maxf(hurt_flash, pulse), 0.0, 1.0)


## Where held items sit relative to their rest pose: bob plus sway.
func hold_position_offset() -> Vector3:
	if not Settings.head_bob:
		return Vector3.ZERO
	var b := bob_amp * HOLD_BOB_SCALE
	return Vector3(sin(bob_phase) * b * 0.8 - sway.x * 0.25, -absf(sin(bob_phase)) * b + sway.y * 0.25, 0.0)


func hold_rotation_offset() -> Vector3:
	if not Settings.head_bob:
		return Vector3.ZERO
	return Vector3(sway.y, sway.x, sway.x * 0.5)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and InputSetup.captured():
		var m := event as InputEventMouseMotion
		sway.x = clampf(sway.x + m.relative.x * SWAY_PER_PX, -SWAY_MAX, SWAY_MAX)
		sway.y = clampf(sway.y + m.relative.y * SWAY_PER_PX, -SWAY_MAX, SWAY_MAX)


func _process(delta: float) -> void:
	step(delta)


## One frame of feel; tests call it directly.
func step(delta: float) -> void:
	_time += delta
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	hurt_flash = maxf(0.0, hurt_flash - HURT_DECAY * delta)
	marker_time = maxf(0.0, marker_time - delta)
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-SWAY_RETURN * delta))
	var speed := 0.0
	var target := 0.0
	if player != null:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
		target = bob_amplitude(speed, player.crouching, player.is_on_floor()) if not player.frozen else 0.0
	bob_amp = lerpf(bob_amp, target, 1.0 - exp(-BOB_EASE * delta))
	bob_phase = fposmod(bob_phase + speed * delta * PI / STEP_M, TAU)
	if sim != null:
		note_health(sim.player.health, sim.player.dead)
	if camera != null:
		_apply_camera()
	if _vignette != null:
		(_vignette.material as ShaderMaterial).set_shader_parameter("strength", vignette_strength(sim.player.health if sim != null else 100.0))
	if _marker != null:
		_marker.alpha = marker_time / MARKER_TIME
		_marker.color = marker_color
		_marker.queue_redraw()


func _apply_camera() -> void:
	var rot := Vector3(kick, 0.0, 0.0)
	var pos := Vector3.ZERO
	if Settings.head_bob:
		var s := shake_amount(trauma)
		rot += Vector3(
				deg_to_rad(SHAKE_MAX_DEG.x) * s * _noise.get_noise_1d(_time * SHAKE_SPEED),
				deg_to_rad(SHAKE_MAX_DEG.y) * s * _noise.get_noise_1d(_time * SHAKE_SPEED + 100.0),
				deg_to_rad(SHAKE_MAX_DEG.z) * s * _noise.get_noise_1d(_time * SHAKE_SPEED + 200.0))
		pos = Vector3(sin(bob_phase) * bob_amp * 0.5, -absf(sin(bob_phase)) * bob_amp, 0.0)
	camera.rotation = rot
	camera.position = pos


## Four short diagonal ticks around the crosshair.
class HitMarker extends Control:
	var alpha := 0.0
	var color := Color.WHITE

	func _draw() -> void:
		if alpha <= 0.0:
			return
		var c := Color(color, alpha)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(d * 7.0, d * 15.0, Color(0, 0, 0, alpha * 0.6), 4.0, true)
			draw_line(d * 7.0, d * 15.0, c, 2.0, true)
