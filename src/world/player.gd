class_name Player
extends CharacterBody3D
## First-person walker: WASD, mouse look, sprint, jump, crouch, flashlight.
## Origin is at the feet. Set use_device_input = false and fill the wish_* fields to drive it from code (tests).

const WALK_SPEED := 4.0
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const ACCEL := 12.0
const AIR_ACCEL := 2.0
const JUMP_VELOCITY := 4.5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_BELOW_TOP := 0.15
const RADIUS := 0.35
const MOUSE_SENSITIVITY := 0.0025
const CROUCH_LERP := 10.0

var use_device_input := true
## x = strafe right, y = forward (both -1..1).
var wish_move := Vector2.ZERO
var wish_sprint := false
var wish_jump := false
var wish_crouch := false

var crouching := false
var head: Node3D
var camera: Camera3D
var flashlight: SpotLight3D

var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _init() -> void:
	collision_mask = Layers.WORLD | Layers.BUILT
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_HEIGHT / 2.0
	add_child(_shape)

	head = Node3D.new()
	head.position.y = STAND_HEIGHT - EYE_BELOW_TOP
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	head.add_child(camera)

	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.15, -0.1, 0.0)
	flashlight.spot_range = 40.0
	flashlight.spot_angle = 22.0
	flashlight.spot_attenuation = 0.5
	flashlight.light_energy = 8.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.1
	flashlight.shadow_normal_bias = 2.0
	flashlight.visible = false
	camera.add_child(flashlight)


## Yaw turns the body, pitch tilts the head. Degrees.
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	rotation.y = deg_to_rad(yaw_deg)
	head.rotation.x = deg_to_rad(clampf(pitch_deg, -89.0, 89.0))


func _unhandled_input(event: InputEvent) -> void:
	if not use_device_input:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -PI / 2 + 0.01, PI / 2 - 0.01)
	elif event.is_action_pressed("free_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()  # this click only grabs the mouse; it doesn't build
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible


func _physics_process(delta: float) -> void:
	if use_device_input:
		wish_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		wish_sprint = Input.is_action_pressed("sprint")
		wish_jump = Input.is_action_pressed("jump")
		wish_crouch = Input.is_action_pressed("crouch")

	_update_crouch(delta)

	if is_on_floor():
		if wish_jump and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= _gravity * delta

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif wish_sprint and wish_move.y > 0.0:
		speed = SPRINT_SPEED
	var dir := (transform.basis * Vector3(wish_move.x, 0.0, -wish_move.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(wish_move.length(), 1.0)
	var target := dir * speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	var flat := Vector3(velocity.x, 0.0, velocity.z).lerp(target, clampf(accel * delta, 0.0, 1.0))
	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()


func _update_crouch(delta: float) -> void:
	if wish_crouch:
		crouching = true
	elif crouching and not test_move(global_transform, Vector3.UP * (STAND_HEIGHT - _capsule.height)):
		crouching = false  # only stand up if there's headroom
	var target_height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_capsule.height = target_height
	_shape.position.y = target_height / 2.0
	head.position.y = lerpf(head.position.y, target_height - EYE_BELOW_TOP, clampf(CROUCH_LERP * delta, 0.0, 1.0))
