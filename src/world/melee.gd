class_name Melee
extends Node3D
## Left-click (outside build mode) swings the pipe. A hit above a zombie's shoulders is a head hit.

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
var feel: ViewFeel  # V3: bob, sway, hit marker, impact puffs (null in tests that build Melee alone)

var _pipe: MeshInstance3D
var _swing := 1.0  # 0 -> 1 over one swing animation
var _message_time := 0.0

const SWING_TIME := 0.25


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude
	_pipe = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 0.6
	_pipe.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.48)
	mat.metallic = 0.6
	_pipe.material_override = mat
	_pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no flashlight shadow across the view
	camera.add_child(_pipe)
	_pose(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and InputSetup.captured() and not builder.active and not sim.guns.in_hand():
		swing()


func _process(delta: float) -> void:
	_pipe.visible = not builder.active and not sim.player.dead and sim.gear.equipped.has("weapon") \
			and not sim.guns.in_hand()  # bare fists: no pipe; M14: not while the gun is out
	_swing = minf(1.0, _swing + delta / SWING_TIME)
	_pose(_swing)
	_message_time -= delta
	if _message_time <= 0.0:
		last_message = ""


## Swings if ready. Returns the id of the zombie hit, -1 for a miss, -2 if the swing wasn't ready.
func swing() -> int:
	if not sim.swing():
		return -2
	_swing = 0.0
	SoundView.play_at(self, "swing", camera.global_position, -8.0, randf_range(0.9, 1.1))
	var from := camera.global_position
	var to := from - camera.global_basis.z * float(sim.weapon_stats()["range"])
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.BUILT | Layers.ZOMBIE, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] == null or not hit["collider"].has_meta("zombie_id"):
		if not hit.is_empty() and feel != null:  # V3: a swing into a wall puffs dust and jars the view
			feel.impact(hit["position"], hit["normal"], "dust")
			feel.add_trauma(ViewFeel.TRAUMA_MELEE_WALL)
		return -1
	var body: Node3D = hit["collider"]
	var id: int = body.get_meta("zombie_id")
	var head: bool = hit["position"].y > body.global_position.y + ZombieBody.HEAD_Y
	var killed := sim.hit_zombie(id, head)
	last_message = "Killed it" if killed else ("Headshot!" if head else "Hit")
	_message_time = 1.0
	if feel != null:
		feel.impact(hit["position"], hit["normal"], "blood")
		feel.hit_zombie(killed, head)
		feel.add_trauma(ViewFeel.TRAUMA_MELEE_HIT)
	return id


## Resting pose at the lower right; mid-swing it sweeps down and across.
func _pose(t: float) -> void:
	var arc := sin(t * PI)
	_pipe.position = Vector3(0.32 - 0.3 * arc, -0.38 + 0.05 * arc, -0.6 - 0.15 * arc)
	_pipe.rotation = Vector3(deg_to_rad(-55.0 - 45.0 * arc), 0.0, deg_to_rad(35.0 + 30.0 * arc))
	if feel != null:  # V3: the pipe bobs with your steps and lags the mouse
		_pipe.position += feel.hold_position_offset()
		_pipe.rotation += feel.hold_rotation_offset()
