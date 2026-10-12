extends Node3D
## Greybox town (road, houses, cars, the factory) under a day/night sun, walked by a first-person Player.
## Game rules live in SimWorld (src/sim), stepped on a fixed tick; this node only draws them.
## Game flags go after `--`:
##   --screenshot[=PATH]   freeze time, save one frame as PNG, quit (tools/shot.sh wraps this)
##   --time=HOURS          start at this hour, e.g. --time=22 for night
##   --cam=X,Y,Z[,YAW[,PITCH]]  put the player's feet at X,Y,Z looking YAW/PITCH degrees
##                        (0,0 = north, level; +yaw turns left, +pitch looks up)
##   --flashlight          start with the flashlight on

const SHOT_DELAY_FRAMES := 30
const SPAWN := Vector3(0, 0, 6)

var sim: SimWorld
var player: Player

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _hud: Label
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	InputSetup.register()
	var args := _parse_user_args()
	sim = SimWorld.new(float(args.get("time", "8.0")))
	if args.has("screenshot"):
		_shot_path = args["screenshot"] if args["screenshot"] != "" else "user://shot.png"
		sim.paused = true
	_build_environment()
	_build_ground()
	_build_town()
	_build_player(args)
	_build_hud()
	_apply_time()
	if _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _shot_path == "":
		if sim.update(delta) > 0:
			_apply_time()
		return
	_frames += 1
	if _frames == SHOT_DELAY_FRAMES:
		_save_screenshot()


func _apply_time() -> void:
	var clock := sim.clock
	var arc := clock.sun_arc_deg()
	var light := clock.daylight()
	_sun.rotation_degrees = Vector3(-arc, -30.0, 0.0)
	_sun.light_energy = light * 1.2
	_moon.rotation_degrees = Vector3(-(arc - 180.0), 150.0, 0.0)
	_moon.light_energy = 0.12 if clock.is_night() else 0.0
	_env.background_energy_multiplier = lerpf(0.04, 1.0, light)
	_env.ambient_light_energy = lerpf(0.08, 1.0, light)
	_env.fog_light_energy = lerpf(0.03, 1.0, light)
	_hud.text = "Day %d  %s" % [clock.day, clock.clock_text()]


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 1.0)
	add_child(_moon)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mesh.mesh = plane
	mesh.material_override = _flat_material(Color(0.32, 0.36, 0.28))
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)


func _build_town() -> void:
	# A road running north (-Z) with houses on both sides and the factory at the far end.
	_add_block(Vector3(0, 0.01, -55), Vector3(8, 0.02, 130), Color(0.17, 0.17, 0.19), false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 6:
		for side in [-1, 1]:
			var size := Vector3(rng.randf_range(7, 10), rng.randf_range(4, 7), rng.randf_range(7, 10))
			var pos := Vector3(side * (7.0 + size.x / 2.0), size.y / 2.0, -10.0 - i * 16.0)
			_add_block(pos, size, Color(0.55, 0.5, 0.45).lerp(Color(0.4, 0.42, 0.5), rng.randf()))
	_add_block(Vector3(0, 6, -125), Vector3(30, 12, 24), Color(0.45, 0.47, 0.5))
	for i in 4:
		var car_color := Color(0.5, 0.2, 0.15).lerp(Color(0.2, 0.3, 0.45), rng.randf())
		_add_block(Vector3(rng.randf_range(-2.5, 2.5), 0.75, -15.0 - i * 22.0), Vector3(1.9, 1.5, 4.4), car_color)


func _build_player(args: Dictionary) -> void:
	player = Player.new()
	player.position = SPAWN
	add_child(player)
	if args.has("cam"):
		var v := PackedFloat64Array()
		for part in String(args["cam"]).split(","):
			v.append(part.to_float())
		while v.size() < 5:
			v.append(0.0)
		player.position = Vector3(v[0], v[1], v[2])
		player.set_look(v[3], v[4])
	if args.has("flashlight"):
		player.flashlight.visible = true
	if _shot_path != "":
		player.use_device_input = false  # stand still for the photo
	player.camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

	var hint := Label.new()
	hint.text = "WASD move · Shift sprint · Space jump · Ctrl crouch · F flashlight · Esc free mouse"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	layer.add_child(hint)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	layer.add_child(dot)
	add_child(layer)


func _add_block(pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _flat_material(color)
	if not collide:
		mesh.position = pos
		add_child(mesh)
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _save_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _shot_path
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	print("SCREENSHOT ", path if err == OK else "FAILED (%s)" % error_string(err))
	get_tree().quit()


## Parses `--key=value` / `--key` flags given after `--` on the command line.
func _parse_user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else ""
	return out
