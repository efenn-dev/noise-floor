extends Node3D
## Greybox town (road, houses, cars, the factory) under a day/night sun, walked by a first-person Player.
## Game rules live in SimWorld (src/sim), stepped on a fixed tick; this node only draws them.
## Game flags go after `--`:
##   --screenshot[=PATH]   freeze time, save one frame as PNG, quit (tools/shot.sh wraps this)
##   --time=HOURS          start at this hour, e.g. --time=22 for night
##   --cam=X,Y,Z[,YAW[,PITCH]]  put the player's feet at X,Y,Z looking YAW/PITCH degrees
##                        (0,0 = north, level; +yaw turns left, +pitch looks up)
##   --flashlight          start with the flashlight on
##   --build=PIECE         start in build mode holding PIECE (foundation or wall)
##   --demo-base           pre-build a small base in front of the spawn point
##   --demo-factory        pre-build a smelter -> belts -> press line in front of spawn, loaded with scrap
##   --demo-farm           pre-build rain collector -> purifier and planter -> canner north of spawn
##   --demo-defense        pre-build a walled square north of spawn: door, barricades, nail turret, spikes
##   --advance=SECONDS     run the sim this long before starting (e.g. so a screenshot shows items moving)
##   --zombies=N           how many zombies roam the street at start (default 8; 0 for none)
##   --zombie=X,Z[,X,Z...] add a zombie at each point, facing the player (for framing screenshots)
##   --hurt=N              start with N damage taken (--hurt=100 shows the death screen)
##   --noise-overlay       start with the noise overlay (N) on
##   --heat=N              start the Director's heat at N
##   --title / --pause / --settings   open that menu (for screenshots)
## With no flags at all you get the title screen first (Continue / New game / Settings / Quit).

const SHOT_DELAY_FRAMES := 30
const SPAWN := Vector3(0, 0, 6)
const DEFAULT_ZOMBIES := 8
const STASH_CELL := Vector2i(1, 3)  # just east of the spawn point
## The area the zombie navmesh covers: the street and a margin around it.
const NAV_BOUNDS := AABB(Vector3(-45, -1, -160), Vector3(90, 8, 200))

var sim: SimWorld
var player: Player
var build_view: BuildView
var builder: BuildController
var factory_view: FactoryView
var interactor: Interactor
var nav: NavBaker
var zombie_view: ZombieView
var melee: Melee
var bag_view: BagView
var noise_overlay: NoiseOverlay

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _hud: Label
var _build_label: Label
var _materials_hud: Label
var _interact_label: Label
var _health_label: Label
var _hurt_flash: ColorRect
var _death_label: Label
var _last_health := 100.0
var _message_label: Label
var _heat_label: Label
var _step_timer := 0.0
var menus: Menus
var _loaded := false  # this scene was rebuilt from a save
var _autosave := 0.0

const WALK_STEP := 0.5    # seconds between walking footstep sounds
const SPRINT_STEP := 0.35
var _shot_path := ""
var _frames := 0


func _ready() -> void:
	InputSetup.register()
	Settings.load_settings()
	var args := _parse_user_args()
	var save := {}
	if GameSession.pending_load != "":
		save = SaveGame.read(GameSession.pending_load)
		GameSession.pending_load = ""
		_loaded = not save.is_empty()
	sim = SimWorld.new(float(args.get("time", "8.0")), null, int(save.get("seed", 1)))
	sim.clock.seconds_per_day = Settings.day_minutes * 60.0
	if args.has("screenshot"):
		_shot_path = args["screenshot"] if args["screenshot"] != "" else "user://shot.png"
		sim.paused = true
	_build_environment()
	_build_ground()
	_build_town()
	_build_player(args)
	_build_building(args)
	_build_zombies(args)
	_build_hud()
	if _loaded:
		_apply_save(save)
	_build_menus(args)
	_apply_settings()
	if args.has("heat"):
		sim.director.heat = args["heat"].to_float()
	if args.has("hurt"):
		sim.player.damage(args["hurt"].to_float())
	for i in roundi(float(args.get("advance", "0")) * SimWorld.TICK_RATE):
		sim.step()
	_apply_time()
	if _shot_path == "" and not menus.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _shot_path == "" and not get_tree().paused and not sim.player.dead:
		_autosave += delta / maxf(Engine.time_scale, 1.0)
		if _autosave >= GameSession.AUTOSAVE_SECONDS:
			_autosave = 0.0
			if save_game() == "":
				sim.add_message("Autosaved", 2.0)
	_sync_player()
	if _shot_path == "":
		_footsteps(delta)
	_update_hud(delta)
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


## Tells the sim where the player is; freezes the player while dead.
func _sync_player() -> void:
	var p := sim.player
	player.frozen = p.dead or p.asleep
	player.speed_multiplier = p.speed_multiplier()
	player.can_sprint = p.can_sprint()
	p.sprinting = Vector2(player.velocity.x, player.velocity.z).length() > Player.WALK_SPEED + 0.5
	if _shot_path == "":
		Engine.time_scale = float(sim.data.survival["sleep_time_scale"]) if p.asleep else 1.0
	if not sim.player.dead:
		sim.player_pos = player.global_position
	sim.player_lit = player.flashlight.visible


## Footsteps make noise: walking barely carries, sprinting does; crouching is silent.
func _footsteps(delta: float) -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if sim.player.dead or player.crouching or not player.is_on_floor() or speed < 0.5:
		_step_timer = 0.0
		return
	var sprinting := speed > Player.WALK_SPEED + 0.5
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = SPRINT_STEP if sprinting else WALK_STEP
		sim.make_noise(player.global_position, "footstep_sprint" if sprinting else "footstep_walk")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("free_mouse"):
		if not menus.is_open():
			_open_pause()  # closing it again is handled by Menus, which runs while paused
			get_viewport().set_input_as_handled()
		return
	if menus.is_open():
		return
	if event.is_action_pressed("quicksave"):
		var why := save_game()
		sim.add_message("Game saved (F9 loads it)" if why == "" else why, 3.0)
		return
	if event.is_action_pressed("quickload"):
		load_game()
		return
	if sim.player.asleep:
		if event is InputEventKey and event.pressed and not event.echo:
			sim.player.wake()  # any key wakes you
		return
	if not InputSetup.captured():
		return
	var msg := ""
	if event.is_action_pressed("eat"):
		msg = sim.eat_best()
	elif event.is_action_pressed("drink"):
		msg = sim.drink_best()
	elif event.is_action_pressed("bandage"):
		msg = sim.use_bandage()
	if msg != "":
		sim.add_message(msg, 2.5)


# --- Menus, saving, settings ----------------------------------------------------

func _build_menus(args: Dictionary) -> void:
	menus = Menus.new()
	add_child(menus)
	menus.new_game.connect(_start_playing)
	menus.continue_game.connect(func() -> void: _reload_with(GameSession.save_path))
	menus.resume.connect(_resume)
	menus.save_requested.connect(func() -> void:
		var why := save_game()
		menus.set_status("Saved." if why == "" else why))
	menus.load_requested.connect(load_game)
	menus.quit_to_title.connect(func() -> void:
		save_game()
		GameSession.started = false
		_reload_with(""))
	menus.settings_changed.connect(_apply_settings)
	var has_save := FileAccess.file_exists(GameSession.save_path)
	var flags := not args.is_empty() and not (args.size() == 1 and args.has("title"))
	if args.has("title") or (not flags and not GameSession.skip_menu and not GameSession.started and not _loaded):
		menus.show_title(has_save)
		if _shot_path == "":  # a screenshot needs the frame counter running
			get_tree().paused = true
	elif args.has("pause"):
		menus.show_pause(has_save)
	elif args.has("settings"):
		menus.show_settings("pause")
	else:
		GameSession.started = true


func _start_playing() -> void:
	GameSession.started = true
	menus.hide_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_pause() -> void:
	menus.show_pause(FileAccess.file_exists(GameSession.save_path))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	Settings.save_settings()
	menus.hide_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_settings() -> void:
	player.mouse_sensitivity = Player.MOUSE_SENSITIVITY * Settings.mouse_sensitivity
	sim.clock.seconds_per_day = Settings.day_minutes * 60.0
	Settings.apply_engine()


## Saves the game (sim state plus where you're looking). Returns "" or what went wrong.
func save_game() -> String:
	sim.player_pos = player.global_position
	return SaveGame.write(sim, GameSession.save_path,
			{"look": [player.rotation_degrees.y, player.head.rotation_degrees.x]})


## Loads the last save: the scene restarts and lays the save over a freshly built town.
func load_game() -> void:
	if not FileAccess.file_exists(GameSession.save_path):
		sim.add_message("No save yet (F5 saves)", 3.0)
		return
	_reload_with(GameSession.save_path)


func _reload_with(path: String) -> void:
	GameSession.pending_load = path
	if path != "":
		GameSession.started = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _apply_save(save: Dictionary) -> void:
	var why := SaveGame.apply(sim, save)
	if why != "":
		sim.add_message(why, 6.0)
		return
	player.position = sim.player_pos
	var look: Array = save.get("look", [0.0, 0.0])
	player.set_look(float(look[0]), float(look[1]))
	nav.bake_now()  # the saved base changes where zombies can walk
	_apply_time()
	sim.add_message("Loaded: day %d, %s" % [sim.clock.day, sim.clock.clock_text()], 3.0)


func _on_respawned() -> void:
	player.position = sim.spawn_point
	player.velocity = Vector3.ZERO


func _update_hud(delta: float) -> void:
	_build_label.text = builder.status_text()
	_materials_hud.text = builder.materials_text()
	var use := interactor.status_text()
	_interact_label.text = use if use != "" else melee.last_message
	var notes := PackedStringArray()
	for m: Dictionary in sim.messages:
		notes.append(m["text"])
	_message_label.text = "\n".join(notes)
	var overlay := noise_overlay.status_text()
	var level := sim.director.level_name()
	_heat_label.text = overlay if overlay != "" else ({"calm": "", "noticed": "The noise is being noticed",
			"group": "The dead are gathering", "horde": "Something big is coming"}[level])
	var hp := sim.player.health
	var p := sim.player
	_health_label.text = "Health %d   Food %d   Water %d   Energy %d   Stamina %d%s%s" % [ceili(hp), ceili(p.food),
			ceili(p.water), ceili(p.energy), ceili(p.stamina), "   BLEEDING (H)" if p.bleeding else "",
			"   Sleeping... (any key wakes you)" if p.asleep else ""]
	var low := hp <= 30.0 or p.bleeding or p.food < 15.0 or p.water < 15.0
	_health_label.modulate = Color(1, 0.35, 0.3) if low else Color.WHITE
	if hp < _last_health:
		_hurt_flash.color.a = 0.45
	_last_health = hp
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 1.5)
	_death_label.visible = sim.player.dead
	if sim.player.dead:
		_hurt_flash.color.a = 0.6
		_death_label.text = "You died\nYour things are in a bag where you fell\nRespawning in %d" % ceili(sim.player.respawn_timer)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mesh.mesh = plane
	mesh.material_override = _flat_material(Color(0.32, 0.36, 0.28))
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()  # a box, not an endless plane, so the navmesh baker can read it
	slab.size = Vector3(400, 2, 400)
	shape.shape = slab
	shape.position.y = -1.0
	ground.add_child(shape)
	add_child(ground)


func _build_town() -> void:
	# A road running north (-Z) with houses on both sides and the factory at the far end.
	# Searchable things: a cabinet or fridge outside each house, every car's trunk, crates by the factory.
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = 11
	_add_block(Vector3(0, 0.01, -55), Vector3(8, 0.02, 130), Color(0.17, 0.17, 0.19), false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 6:
		for side in [-1, 1]:
			var size := Vector3(rng.randf_range(7, 10), rng.randf_range(4, 7), rng.randf_range(7, 10))
			var pos := Vector3(side * (7.0 + size.x / 2.0), size.y / 2.0, -10.0 - i * 16.0)
			_add_block(pos, size, Color(0.55, 0.5, 0.45).lerp(Color(0.4, 0.42, 0.5), rng.randf()))
			var table: String = ["kitchen", "bathroom", "fridge"][loot_rng.randi_range(0, 2)]
			var spot := Vector3(side * 6.6, 0.8, pos.z + loot_rng.randf_range(-2.0, 2.0))
			_add_container("house_%d_%s" % [i, "e" if side > 0 else "w"], table, spot,
					Vector3(0.7, 1.6, 0.7), Color(0.85, 0.85, 0.8) if table == "fridge" else Color(0.55, 0.42, 0.3))
	_add_block(Vector3(0, 6, -125), Vector3(30, 12, 24), Color(0.45, 0.47, 0.5))
	for i in 3:
		_add_container("factory_crate_%d" % i, "factory_crate", Vector3(-8.0 + i * 8.0, 0.5, -111.8),
				Vector3(1.2, 1.0, 1.0), Color(0.45, 0.4, 0.25))
	for i in 4:
		var car_color := Color(0.5, 0.2, 0.15).lerp(Color(0.2, 0.3, 0.45), rng.randf())
		var car_pos := Vector3(rng.randf_range(-2.5, 2.5), 0.75, -15.0 - i * 22.0)
		var car := _add_block(car_pos, Vector3(1.9, 1.5, 4.4), car_color)
		car.set_meta("container_id", "car_%d" % i)  # look at the car: search its trunk
		sim.loot.add("car_%d" % i, "car_trunk", car_pos)
		sim.add_car("car_%d" % i)


func _add_container(id: String, table: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := _add_block(pos, size, color)
	body.set_meta("container_id", id)
	sim.loot.add(id, table, pos)


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
	sim.spawn_point = player.position
	sim.player_pos = player.position
	sim.player.respawned.connect(_on_respawned)


func _build_building(args: Dictionary) -> void:
	# The debug kit waits in a crate next to the start; you carry a little food, water and a bandage.
	# (A loaded save brings back its own crates and pockets instead.)
	if not _loaded:
		sim.place_start_stash(STASH_CELL)
		sim.inventory.give_all({"clean_water": 1, "chips": 1, "bandage": 1})
	build_view = BuildView.new()
	add_child(build_view)
	build_view.setup(sim.build)
	builder = BuildController.new()
	add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	factory_view = FactoryView.new()
	add_child(factory_view)
	factory_view.setup(sim, build_view)
	interactor = Interactor.new()
	add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])
	if args.has("demo-base"):
		_place_demo_base()
	if args.has("demo-factory"):
		_place_demo_factory()
	if args.has("demo-farm"):
		_place_demo_farm()
	if args.has("demo-defense"):
		_place_demo_defense()
	if args.has("build"):
		builder.set_active(true)
		builder.select(maxi(0, BuildController.PIECES.find(args["build"])))


## A 4 x 3 floor just north of spawn with a back wall and two side walls.
func _place_demo_base() -> void:
	var stock := sim.stock_at(SPAWN)
	for x in range(-2, 2):
		for z in range(-1, 2):
			sim.build.place("foundation", Vector2i(x, z), 0, stock)
	for x in range(-2, 2):
		sim.build.place("wall", Vector2i(x, -1), BuildGrid.Side.NORTH, stock)
	sim.build.place("wall", Vector2i(-2, -1), BuildGrid.Side.WEST, stock)
	sim.build.place("wall", Vector2i(1, -1), BuildGrid.Side.EAST, stock)


func _build_zombies(args: Dictionary) -> void:
	nav = NavBaker.new()
	add_child(nav)
	nav.setup(self, NAV_BOUNDS)
	nav.bake_now()
	sim.build.piece_added.connect(func(_k: String) -> void: nav.request_rebake())
	sim.build.piece_removed.connect(func(_k: String, _p: Dictionary) -> void: nav.request_rebake())
	sim.build.piece_changed.connect(func(_k: String) -> void: nav.request_rebake())  # doors
	if not _loaded:
		sim.horde.spawn_town(int(args.get("zombies", str(DEFAULT_ZOMBIES))))
	if args.has("zombie"):
		var v := String(args["zombie"]).split(",")
		for i in range(0, v.size() - 1, 2):
			var z := sim.horde.spawn("shambler", Vector3(v[i].to_float(), 0, v[i + 1].to_float()))
			z.facing = (player.position - z.pos).normalized()
	zombie_view = ZombieView.new()
	add_child(zombie_view)
	zombie_view.setup(sim, player)
	melee = Melee.new()
	add_child(melee)
	melee.setup(sim, player.camera, builder, [player.get_rid()])
	bag_view = BagView.new()
	add_child(bag_view)
	bag_view.setup(sim)
	noise_overlay = NoiseOverlay.new()
	add_child(noise_overlay)
	noise_overlay.setup(sim)
	noise_overlay.visible = args.has("noise-overlay")


## Smelter -> 3 belts -> press, running east just north of spawn, with 20 scrap loaded,
## powered by a fuelled generator and a pole.
func _place_demo_factory() -> void:
	var E := BuildGrid.Side.EAST
	var stock := sim.stock_at(SPAWN)
	for x in range(-2, 3):
		sim.build.place("foundation", Vector2i(x, 0), 0, stock)
	sim.build.place("smelter", Vector2i(-2, 0), E, stock)
	for x in range(-1, 2):
		sim.build.place("belt", Vector2i(x, 0), E, stock)
	sim.build.place("press", Vector2i(2, 0), E, stock)
	# Power: a generator behind the smelter and a pole to reach the press.
	sim.build.place("foundation", Vector2i(-2, 1), 0, stock)
	sim.build.place("generator", Vector2i(-2, 1), E, stock)
	sim.build.place("power_pole", Vector2i(0, 1), E, stock)
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(-2, 1)), stock)
	var feed := Inventory.new()
	feed.add("scrap_metal", 20)
	sim.factory.hand_interact(Vector2i(-2, 0), feed)


## Two short lines a row apart: rain collector -> belt -> purifier, and planter -> belt -> canner.
func _place_demo_farm() -> void:
	var E := BuildGrid.Side.EAST
	var stock := sim.stock_at(SPAWN)
	for z in [-1, 1]:
		for x in range(-2, 1):
			sim.build.place("foundation", Vector2i(x, z), 0, stock)
		sim.build.place("belt", Vector2i(-1, z), E, stock)
	sim.build.place("rain_collector", Vector2i(-2, -1), E, stock)
	sim.build.place("purifier", Vector2i(0, -1), E, stock)
	sim.build.place("planter", Vector2i(-2, 1), E, stock)
	sim.build.place("canner", Vector2i(0, 1), E, stock)
	sim.build.place("foundation", Vector2i(1, 0), 0, stock)
	sim.build.place("solar_panel", Vector2i(1, 0), E, stock)  # silent power for the purifier and canner
	sim.factory.machines[Vector2i(-2, 1)].input = {"seeds": 3, "dirty_water": 3}
	sim.factory.machines[Vector2i(0, 1)].input = {"metal_plate": 3}


## A 2 x 2 walled square just north of spawn: door on the south side, barricades on the north with a
## loaded nail turret behind them, and two spike strips further out.
func _place_demo_defense() -> void:
	var stock := sim.stock_at(SPAWN)
	var S := BuildGrid.Side
	for x in [-1, 0]:
		for z in [-1, 0]:
			sim.build.place("foundation", Vector2i(x, z), 0, stock)
	for x in [-1, 0]:
		sim.build.place("barricade", Vector2i(x, -1), S.NORTH, stock)
	for z in [-1, 0]:
		sim.build.place("wall", Vector2i(-1, z), S.WEST, stock)
		sim.build.place("wall", Vector2i(0, z), S.EAST, stock)
	sim.build.place("wall", Vector2i(-1, 0), S.SOUTH, stock)
	sim.build.place("door", Vector2i(0, 0), S.SOUTH, stock)
	sim.build.place("nail_turret", Vector2i(0, -1), S.NORTH, stock)
	sim.factory.hand_interact(Vector2i(0, -1), stock)
	for x in [-1, 0]:
		sim.build.place("spikes", Vector2i(x, -3), 0, stock)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

	_build_label = _outlined_label(20)
	_build_label.position = Vector2(16, 52)
	layer.add_child(_build_label)
	_materials_hud = _outlined_label(18)
	_materials_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_materials_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_materials_hud)

	_interact_label = _outlined_label(20)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_interact_label.position += Vector2(0, 40)
	_interact_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_interact_label)

	_health_label = _outlined_label(24)
	_health_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_health_label.position.y -= 30
	layer.add_child(_health_label)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hurt_flash)
	layer.move_child(_hurt_flash, 0)  # under the text

	_message_label = _outlined_label(26)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message_label.position.y += 60
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	layer.add_child(_message_label)

	_heat_label = _outlined_label(18)
	_heat_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_heat_label.position.y += 30
	_heat_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_heat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	layer.add_child(_heat_label)

	_death_label = _outlined_label(34)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_label.visible = false
	layer.add_child(_death_label)

	var hint := Label.new()
	hint.text = "WASD move · Shift sprint · Space jump · Ctrl crouch · F flashlight · LMB swing · E use · T repair · G siphon · Z eat · X drink · H bandage · B build · U muffle · N noise · F5 save · Esc menu"
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
	# The HUD only shows things; it must never catch the mouse. A locked mouse sits in the middle of the
	# screen, right on the crosshair, and a HUD element there would swallow every look and click.
	for child in layer.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)


func _outlined_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label


func _add_block(pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> StaticBody3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _flat_material(color)
	if not collide:
		mesh.position = pos
		add_child(mesh)
		return null
	var body := StaticBody3D.new()
	body.position = pos
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body


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
