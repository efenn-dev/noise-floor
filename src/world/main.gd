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
##   --zombies=N           how many zombies roam the street at start (default 8; 0 for none, house zombies included)
##   --zombie=X,Z[,X,Z...] add a zombie at each point, facing the player (for framing screenshots)
##   --hurt=N              start with N damage taken (--hurt=100 shows the death screen)
##   --noise-overlay       start with the noise overlay (N) on
##   --heat=N              start the Director's heat at N
##   --title / --pause / --settings   open that menu (for screenshots)
##   --inventory                     open the inventory screen (Tab in game)
##   --skills                        open the skills and perks screen (K in game)
##   --gear[=RARITY]                 a rolled gear piece (white, blue, yellow (default), gold, set) in your pockets,
##                                   shown in the inventory screen (M13)
##   --zombie-type=TYPE              what --zombie spawns (shambler, runner, screamer)
##   --drive[=car_N]                 start in a car (car_0, a sedan, by default; wrecks can't be driven)
##   --no-hints                      no first-game hints (they only show in a new game without --demo-*/--cam)
##   --hints                         show the first-game hints anyway (for screenshots)
##   --inside[=N]                    start inside house N (0-11, default 0), looking at its fridge
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
var sound_view: SoundView
var inventory_screen: InventoryScreen
var skills_screen: SkillsScreen
var interactor: Interactor
var nav: NavBaker
var zombie_view: ZombieView
var melee: Melee
var shooter: Shooter  # M14: the gun in your hands
var workbench_screen: WorkbenchScreen  # M14: E on a workbench
var sensor_screen: SensorScreen  # M15: E on a sensor
var base_log_screen: BaseLogScreen  # M15: L (or the pause menu)
var defense_view: DefenseView
var bag_view: BagView
var noise_overlay: NoiseOverlay
var session_log: SessionLog
var hints: Hints  # first-game hints; null after a load, with --demo-*/--cam/--no-hints, or in screenshots
var cars: Dictionary = {}  # car id -> CarBody
var town: Dictionary = {}  # TownPlan.generate(seed): the houses, their pieces, containers and beds (W1a)
var town_view: TownView
var town_pieces := 0  # pieces the town plan laid this run (0 when a save brought its own houses)
var first_bake_ms := 0.0  # how long the first navmesh bake took
var driving: CarBody = null  # the car you're in, or null when walking

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _title_camera: Camera3D  # set while the title screen shows its dusk view
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

const CAR_TYPES := ["sedan", "pickup", "van", "sedan"]  # town cars in order; car_0 (a sedan near the start) always drives
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
	session_log = SessionLog.new()
	session_log.enabled = _shot_path == "" and DisplayServer.get_name() != "headless"
	if session_log.enabled and SessionLog.carried != null:
		sim.stats = SessionLog.carried  # loading a save or quitting to the title is still the same sitting
	sim.stats.muted = true  # building the town, a save or a demo base isn't the player's doing
	add_child(session_log)
	session_log.setup(sim)
	if session_log.enabled and not GameSession.build_printed:
		GameSession.build_printed = true  # once per run, not on every scene reload
		print("Noise Floor build: " + GameSession.version_line())
	_build_environment()
	_build_ground()
	# A W1a+ save brings the houses back itself, and a W1b+ save the factory hall.
	# W1c: a new game lays the furniture with the town; a pre-W1c save gets it after the save is applied.
	_build_town(not (_loaded and SaveGame.holds_town(save)), not (_loaded and SaveGame.holds_factory(save)), not _loaded)
	_build_player(args)
	_build_building(args)
	_build_zombies(args)
	_build_hud()
	inventory_screen = InventoryScreen.new()
	add_child(inventory_screen)
	inventory_screen.setup(sim)
	inventory_screen.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
	skills_screen = SkillsScreen.new()
	add_child(skills_screen)
	skills_screen.setup(sim)
	skills_screen.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
	workbench_screen = WorkbenchScreen.new()
	add_child(workbench_screen)
	workbench_screen.setup(sim)
	workbench_screen.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
	sensor_screen = SensorScreen.new()
	add_child(sensor_screen)
	sensor_screen.setup(sim)
	sensor_screen.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
	base_log_screen = BaseLogScreen.new()
	add_child(base_log_screen)
	base_log_screen.setup(sim)
	if _wants_hints(args):
		hints = Hints.new()
		hints.setup(sim, inventory_screen, noise_overlay)
		hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
		hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hints.position.y -= 110
		_hud.get_parent().add_child(hints)  # the HUD layer, so the title screen hides it too
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
	var drive_id: String = args.get("drive", "")
	if drive_id == "":
		drive_id = "car_0"
	if args.has("drive") and sim.enter_car(drive_id) == "":
		_enter_car(drive_id)  # --drive[=car_N]: start in a car (screenshots)
		if args.has("flashlight"):
			driving.toggle_lights()  # --drive --flashlight: headlights on
	if args.has("inventory"):
		sim.player_pos = player.global_position
		inventory_screen.open()
		if args["inventory"] != "":
			inventory_screen.select(args["inventory"], InventoryScreen.POCKETS)  # --inventory=chips, for screenshots
	if args.has("gear"):
		_give_rolled_gear(args["gear"])  # --gear=yellow: a rolled piece in your pockets, selected
	if args.has("skills"):
		skills_screen.open()  # --skills, for screenshots
	if args.has("gun") or args.has("workbench") or args.has("shoot"):
		_give_gun(args.get("gun", ""), args.has("workbench"))  # M14: --gun[=pistol|rifle|pete], --workbench
	if args.has("shoot"):
		shooter.fire.call_deferred()  # --shoot: fire once (screenshots of the HUD line after a shot)
	if args.has("sensor-screen"):
		_open_sensor(_demo_sensor_key())  # M15: --sensor-screen (with --demo-defense), for screenshots
	if args.has("base-log"):
		_fill_demo_log()
		base_log_screen.open()  # M15: --base-log, for screenshots
	if _shot_path == "" and not menus.is_open() and not inventory_screen.is_open() and not skills_screen.is_open() \
			and not workbench_screen.is_open() and not _m15_screen_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sim.stats.muted = false


## --gear=RARITY (white, blue, yellow, gold, set): puts a rolled piece of that rarity in your pockets and
## opens the inventory screen with it selected, for screenshots and trying gear out.
func _give_rolled_gear(rarity: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var piece := {}
	if rarity == "gold":
		piece = sim.gear.roll_unique(rng, "petes_fire_axe")
	else:
		for i in 2000:
			piece = sim.gear.roll_piece(rng, "factory_crate")
			if piece["rarity"] == (rarity if rarity != "" else "yellow"):
				break
	sim.gear.pieces.append(piece)
	sim.player_pos = player.global_position
	if not inventory_screen.is_open():
		inventory_screen.open()
	inventory_screen.select_gear(piece["uid"])


## --gun[=pistol|rifle|pete]: a gun (pistol by default; pete = Old Pete's Deer Rifle) in your gun slot,
## loaded, raised and in your hands, with 30 standard rounds. --workbench also gives the parts and casings
## the bench uses, fits a crude suppressor and opens the workbench screen (for screenshots and trying it).
func _give_gun(which: String, bench: bool) -> void:
	var piece := {}
	if which == "pete":
		piece = sim.gear.roll_unique(RandomNumberGenerator.new(), "petes_deer_rifle")
	else:
		piece = sim.gear.make("hunting_rifle" if which == "rifle" else "pistol", "civilian", "white")
	sim.gear.equipped["gun"] = piece
	piece["loaded"] = int(sim.gear.gun_stats(piece)["magazine"])
	sim.inventory.add("ammo_standard", 30)
	if sim.guns.hands != "gun":
		sim.swap_hands()
	sim.guns.raising = 0.0
	if bench:
		for base: String in ["oil_filter_suppressor", "scope", "extended_mag", "padded_stock"]:
			sim.gear.pieces.append(sim.gear.make(base, "civilian", "blue" if base == "scope" else "white",
					{"accuracy": 0.1} if base == "scope" else {}))
		sim.attach_part(sim.gear.pieces[sim.gear.pieces.size() - 4]["uid"])
		sim.inventory.give_all({"ammo_casing": 20, "scrap_metal": 6, "nails": 12, "plank": 4})
		sim.player_pos = player.global_position
		_open_workbench("")


func _open_workbench(key: String) -> void:
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	workbench_screen.open(key)


## M15: E on a sensor.
func _open_sensor(key: String) -> void:
	if key == "":
		return
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	sensor_screen.open(key)


func _m15_screen_open() -> bool:
	return sensor_screen.is_open() or base_log_screen.is_open()


## The demo base's first sensor (--sensor-screen), or any sensor.
func _demo_sensor_key() -> String:
	var keys := sim.automation.sensors.keys()
	keys.sort()
	return keys[0] if not keys.is_empty() else ""


## --base-log on a fresh game: a few made-up nights so the screen has something to show (screenshots only).
func _fill_demo_log() -> void:
	if not sim.base_log.entries.is_empty():
		return
	var lines := [["day 3 21:12", "Motion sensor (north): 3 zombies, floodlights on"], ["day 3 21:12", "Nail turret (north) killed a shambler"],
			["day 3 21:14", "North barricade under attack: 4 zombies"], ["day 3 21:15", "Noisemaker (east) going off"],
			["day 3 21:19", "Nail turret (north) out of nails"], ["day 3 21:30", "North barricade destroyed"],
			["day 3 22:02", "A horde coming from the north: 8 zombies"], ["day 4 02:40", "Repair station fixed the west wall (200/200 hp)"]]
	for l: Array in lines:
		sim.base_log.now = l[0]
		sim.base_log.add(l[1], Vector3(0, 0, -100), false)
	sim.base_log.now = sim.when_text()


## First-game hints: a new game only (no save loaded, no --demo-*/--cam/--no-hints, not a screenshot).
func _wants_hints(args: Dictionary) -> bool:
	if args.has("hints"):
		return true
	if _loaded or _shot_path != "" or args.has("no-hints") or args.has("cam") or args.has("inside") or GameSession.skip_hints:
		return false
	for key: String in args:
		if key.begins_with("demo"):
			return false
	return true


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
		if not sim.paused:
			sim.stats.add_real_time(delta / maxf(Engine.time_scale, 1.0))  # sleeping speeds time up
		if sim.update(delta) > 0:
			_apply_time()
		return
	_frames += 1
	if _frames == SHOT_DELAY_FRAMES:
		_save_screenshot()


func _apply_time() -> void:
	if _title_camera != null:
		return  # the title screen keeps its own dusk look
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
	# Thicker, darker fog at night; the volumetric part (Forward+ only) is what shows the flashlight beam.
	_env.fog_density = lerpf(0.02, 0.006, light)
	_env.fog_light_color = Color(0.05, 0.06, 0.09).lerp(Color(0.62, 0.66, 0.7), light)
	_env.volumetric_fog_density = lerpf(0.022, 0.002, light)
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
	_env.fog_sky_affect = 0.5
	_env.volumetric_fog_enabled = true  # Forward+ only; the Compatibility renderer (cloud screenshots) ignores it
	_env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	_env.volumetric_fog_length = 48.0
	_env.glow_enabled = true  # machine lamps bloom a little at night
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.04
	_env.ssao_enabled = true
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
	if inventory_screen.is_open() and (p.dead or p.asleep):
		inventory_screen.close()
	if skills_screen.is_open() and (p.dead or p.asleep):
		skills_screen.close()
	if workbench_screen.is_open() and (p.dead or p.asleep):
		workbench_screen.close()
	if sensor_screen.is_open() and (p.dead or p.asleep):
		sensor_screen.close()
	# no walking while sorting your pockets, spending perk points or at the workbench
	player.frozen = p.dead or p.asleep or inventory_screen.is_open() or skills_screen.is_open() or workbench_screen.is_open() \
			or _m15_screen_open()
	player.speed_multiplier = p.speed_multiplier()
	player.can_sprint = p.can_sprint()
	p.sprinting = Vector2(player.velocity.x, player.velocity.z).length() > Player.WALK_SPEED + 0.5
	if _shot_path == "":
		Engine.time_scale = float(sim.data.survival["sleep_time_scale"]) if p.asleep else 1.0
	if driving != null and p.dead:
		_exit_car()
	if not sim.player.dead and driving == null:
		sim.player_pos = player.global_position  # while driving, the car reports where you are
	sim.player_lit = player.flashlight.visible
	sim.player_sneaking = driving == null and player.crouching and player.is_on_floor() \
			and Vector2(player.velocity.x, player.velocity.z).length() > 0.5


## Footsteps make noise: walking barely carries, sprinting does; crouching is silent.
func _footsteps(delta: float) -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if driving != null or sim.player.dead or player.crouching or not player.is_on_floor() or speed < 0.5:
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
	if driving != null:
		if event.is_action_pressed("interact"):
			_exit_car()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("bandage"):  # H is the horn while you drive
			sim.honk()
			return
		if event.is_action_pressed("refuel"):  # R in a car without its key: hotwire
			var why := sim.hotwire()
			if why != "":
				sim.add_message(why, 3.0)
			return
		if event.is_action_pressed("inventory") or event.is_action_pressed("skills"):
			return  # no rummaging while driving
	if workbench_screen.is_open() or _m15_screen_open():
		return  # they close themselves on E, Tab or Esc (the base log on L too)
	if event.is_action_pressed("base_log") and not sim.player.dead:
		base_log_screen.open()  # M15: L
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap_hands") and not sim.player.dead and InputSetup.captured():
		sim.add_message(sim.swap_hands(), 2.0)  # M14: Q, melee weapon or gun
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and not sim.player.dead:
		sim.player_pos = player.global_position
		if skills_screen.is_open():
			skills_screen.close()
		inventory_screen.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("skills") and not sim.player.dead and not inventory_screen.is_open():
		skills_screen.open()
		get_viewport().set_input_as_handled()
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
	menus.base_log_requested.connect(func() -> void:
		_resume()
		base_log_screen.open())
	menus.quit_to_title.connect(func() -> void:
		save_game()
		GameSession.started = false
		_reload_with(""))
	menus.settings_changed.connect(_apply_settings)
	var has_save := FileAccess.file_exists(GameSession.save_path)
	var flags := not args.is_empty() and not (args.size() == 1 and args.has("title"))
	if args.has("title") or (not flags and not GameSession.skip_menu and not GameSession.started and not _loaded):
		menus.show_title(has_save)
		_title_view(true)
		if _shot_path == "":  # a screenshot needs the frame counter running
			get_tree().paused = true
	elif args.has("pause"):
		menus.set_stats(sim.stats_text())
		menus.show_pause(has_save)
	elif args.has("settings"):
		menus.show_settings("pause")
	else:
		GameSession.started = true


func _start_playing() -> void:
	GameSession.started = true
	_title_view(false)
	menus.hide_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_pause() -> void:
	menus.set_stats(sim.stats_text())
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
	if not SaveGame.holds_props(save):
		town_pieces += sim.place_props(town)  # W1c: furnish an older save's houses (not where you built)
	player.position = sim.player_pos
	for car: CarBody in cars.values():
		car.place_from_sim()  # parked where you left it
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
	_materials_hud.text = builder.materials_text() + "\n" + sim.guns.hands_text()  # M13, M14: what's in your hands
	var use := _car_hud() if driving != null else interactor.status_text()
	_interact_label.text = use if use != "" else (shooter.last_message if shooter.last_message != "" else melee.last_message)
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
	mesh.material_override = Surfaces.material("ground", 6.0, Color(0.62, 0.64, 0.56))
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()  # a box, not an endless plane, so the navmesh baker can read it
	slab.size = Vector3(400, 2, 400)
	shape.shape = slab
	shape.position.y = -1.0
	ground.add_child(shape)
	add_child(ground)


func _build_town(lay_houses: bool = true, lay_factory: bool = true, lay_props: bool = true) -> void:
	# A road running north (-Z) with houses on both sides and the factory at the far end.
	# Houses (W1a) are build-grid pieces from TownPlan: floors, walls, doors, windows and a bed, laid as
	# if built (so they muffle, break and save like the player's own), plus a roof drawn by TownView.
	# Searchable things: fridges and cabinets inside the houses, every car's trunk, crates in the factory.
	# The factory (W1b) is a hall of the same pieces: brick walls, a wide open doorway on the road, windows.
	_add_block(Vector3(0, 0.01, -55), Vector3(8, 0.02, 130), Color(0.17, 0.17, 0.19), false, Surfaces.material("asphalt", 4.0, Color(0.55, 0.55, 0.55)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 48:
		rng.randf()  # the twelve old box houses drew 4 numbers each: keep the draws so the cars don't move
	town = TownPlan.generate(sim.seed_value, sim.data)
	if lay_houses:
		town_pieces = sim.place_town(town)
	if lay_factory:
		town_pieces += sim.place_factory(town)
	if lay_props:
		town_pieces += sim.place_props(town)  # W1c: furniture
	for c: Dictionary in town["containers"]:
		var fridge: bool = c["table"] == "fridge"
		var box := _add_container(c["id"], c["table"], SimWorld.town_container_pos(c), Vector3(0.7, 1.6, 0.7),
				Color(0.85, 0.85, 0.8) if fridge else Color(0.55, 0.42, 0.3))
		var out := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][c["side"]] as Vector2
		_dress(box, "fridge" if fridge else "cabinet", atan2(out.x, out.y))  # back to the wall, facing the room
	town_view = TownView.new()
	add_child(town_view)
	town_view.setup(town, sim.build)
	for i in 3:
		var cell: Vector2i = town["factory"]["crates"][i]
		var at := Vector3((cell.x + 0.5) * BuildGrid.GRID, 0.6, (cell.y + 0.5) * BuildGrid.GRID)  # on the hall's floor
		var crate := _add_container("factory_crate_%d" % i, "factory_crate", at, Vector3(1.2, 1.0, 1.0),
				Color(0.45, 0.4, 0.25))
		_dress(crate, "storage", 0.0, Color.WHITE, Vector3(1.2 / 1.4, 1.0, 1.0))  # the player's crate model, a bit narrower
	for i in 4:
		var car_color := Color(0.5, 0.2, 0.15).lerp(Color(0.2, 0.3, 0.45), rng.randf())
		var id := "car_%d" % i
		var type: String = CAR_TYPES[i % CAR_TYPES.size()]
		var size: Array = sim.data.vehicles[type]["size"]
		var car_pos := Vector3(rng.randf_range(-2.5, 2.5), float(size[1]) / 2.0, -15.0 - i * 22.0)
		sim.loot.add(id, "car_trunk", car_pos)  # look at the back of the car to search its trunk
		sim.add_car(id, type, car_pos, 0.0 if i % 2 == 0 else PI)
		var car := CarBody.new()
		add_child(car)
		car.setup(sim, id, car_color * 1.6)
		cars[id] = car


func _add_container(id: String, table: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := _add_block(pos, size, color)
	body.set_meta("container_id", id)
	sim.loot.add(id, table, pos)
	return body


## Swap a town block's box for assets/models/<model>.glb (tools/art/<model>.py), keeping its collider.
## `paint` tints the model's "Car Paint" surface. If the model hasn't been made, the box stays.
func _dress(body: StaticBody3D, model: String, yaw: float, paint := Color.WHITE, scale := Vector3.ONE) -> void:
	var path := "res://assets/models/%s.glb" % model
	if body == null or not ResourceLoader.exists(path):
		return
	for child in body.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.rotation.y = yaw
	node.scale = scale
	body.add_child(node)
	if paint == Color.WHITE:
		return
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.resource_name == "Car Paint":
				mat = mat.duplicate()
				mat.albedo_color = paint.clamp()
				mesh.set_surface_override_material(s, mat)


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
	if args.has("inside"):
		var inside := String(args["inside"]).split(",")
		_stand_inside(inside[0].to_int(), inside[1] if inside.size() > 1 else "")
	if args.has("flashlight"):
		player.flashlight.visible = true
	if _shot_path != "":
		player.use_device_input = false  # stand still for the photo
	player.camera.current = true
	sim.spawn_point = player.position
	sim.player_pos = player.position
	sim.player.respawned.connect(_on_respawned)


## --inside=N: stand in house N's kitchen, across the cell from its fridge, looking at it.
## --inside=N,PROP (W1c): stand in front of that house's PROP (counter, table, couch, shelf, bathtub, toilet).
func _stand_inside(n: int, prop := "") -> void:
	var house: Dictionary = town["houses"][clampi(n, 0, town["houses"].size() - 1)]
	for p: Dictionary in town["props"]:
		if p["house"] != house["name"] or p["id"] != prop:
			continue
		var facing := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][p["side"]] as Vector3
		var cell_mid := Vector3((p["cell"].x + 0.5) * BuildGrid.GRID, 0.1, (p["cell"].y + 0.5) * BuildGrid.GRID)
		player.position = cell_mid + facing * 0.75  # across the cell from it, clear of the wall opposite
		player.set_look(rad_to_deg(atan2(facing.x, facing.z)), -20.0)
		return
	for c: Dictionary in town["containers"]:
		if c["id"] != "%s_fridge" % house["name"]:
			continue
		var fridge := SimWorld.town_container_pos(c)
		var out := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][c["side"]] as Vector3
		var cell_mid := Vector3((c["cell"].x + 0.5) * BuildGrid.GRID, 0.1, (c["cell"].y + 0.5) * BuildGrid.GRID)
		player.position = cell_mid - out * 0.75
		var d := fridge - player.position
		player.set_look(rad_to_deg(atan2(-d.x, -d.z)), -12.0)


func _build_building(args: Dictionary) -> void:
	# The debug kit waits in a crate next to the start; you carry a little food, water and a bandage.
	# (A loaded save brings back its own crates and pockets instead.)
	if not _loaded:
		sim.place_start_stash(STASH_CELL)
		sim.inventory.give_all({"clean_water": 1, "chips": 1, "bandage": 1})
	build_view = BuildView.new()
	add_child(build_view)
	for p: Dictionary in town["pieces"] + town["factory"]["pieces"]:
		build_view.styles[TownPlan.piece_key(p)] = p["style"]  # brick, siding, plaster, factory or floor
	build_view.setup(sim.build)
	builder = BuildController.new()
	add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	factory_view = FactoryView.new()
	add_child(factory_view)
	factory_view.setup(sim, build_view)
	sound_view = SoundView.new()
	add_child(sound_view)
	sound_view.setup(sim)
	interactor = Interactor.new()
	add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])
	interactor.entered_car.connect(_enter_car)
	interactor.opened_workbench.connect(_open_workbench)
	interactor.opened_sensor.connect(_open_sensor)
	defense_view = DefenseView.new()
	add_child(defense_view)
	defense_view.setup(sim, build_view)
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
	var t0 := Time.get_ticks_usec()
	nav.bake_now()
	first_bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if DisplayServer.get_name() != "headless":
		print("Town: %d town pieces laid (houses and factory), first navmesh bake %.0f ms" % [town_pieces, first_bake_ms])
	sim.build.piece_added.connect(func(_k: String) -> void: nav.request_rebake())
	sim.build.piece_removed.connect(func(_k: String, _p: Dictionary) -> void: nav.request_rebake())
	sim.build.piece_changed.connect(func(_k: String) -> void: nav.request_rebake())  # doors
	if not _loaded:
		sim.horde.spawn_town(int(args.get("zombies", str(DEFAULT_ZOMBIES))))
		if args.get("zombies", "") != "0":
			sim.spawn_house_zombies(town)  # W1b: one waits inside about one house in three
			sim.spawn_old_pete()  # M13: the named zombie in the factory hall, with his fire axe
	if args.has("zombie"):
		var v := String(args["zombie"]).split(",")
		for i in range(0, v.size() - 1, 2):
			var z := sim.horde.spawn(args.get("zombie-type", "shambler"), Vector3(v[i].to_float(), 0, v[i + 1].to_float()))
			z.facing = (player.position - z.pos).normalized()
	zombie_view = ZombieView.new()
	add_child(zombie_view)
	zombie_view.setup(sim, player)
	melee = Melee.new()
	add_child(melee)
	melee.setup(sim, player.camera, builder, [player.get_rid()])
	shooter = Shooter.new()
	add_child(shooter)
	shooter.setup(sim, player.camera, builder, [player.get_rid()])
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
	# M15: a hopper of nails behind the turret, a motion sensor that turns on two floodlights, a bear trap,
	# a tripwire in front, a generator for the lights, and a decoy noisemaker 30 m east on its own pole line.
	stock.give_all({"metal_plate": 40, "nails": 200, "plank": 20, "scrap_metal": 10, "gas_can": 2})
	sim.build.place("hopper", Vector2i(0, 0), S.NORTH, stock)
	sim.factory.hand_interact(Vector2i(0, 0), stock)
	sim.build.place("generator", Vector2i(-1, 0), S.NORTH, stock)
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(-1, 0)), stock)
	for c: Vector2i in [Vector2i(-2, -2), Vector2i(1, -2)]:
		sim.build.place("floodlight", c, S.NORTH, stock)
		sim.toggle_floodlight(sim.build.key_for("floodlight", c))  # lit every night, for the demo
	sim.build.place("motion_sensor", Vector2i(-2, -1), S.NORTH, stock)
	sim.set_sensor_action(sim.build.key_for("motion_sensor", Vector2i(-2, -1)), "decoy")
	for c: Vector2i in [Vector2i(1, -1), Vector2i(7, -1), Vector2i(13, -1)]:
		sim.build.place("power_pole", c, S.NORTH, stock)
	sim.build.place("noisemaker", Vector2i(15, -1), S.NORTH, stock)
	sim.build.place("bear_trap", Vector2i(-1, -4), 0, stock)
	for x in [-1, 0]:
		sim.build.place("tripwire", Vector2i(x, -4), S.NORTH, stock)


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
	hint.text = "WASD move · Shift sprint · Space jump · Ctrl crouch · F flashlight · LMB attack · Q gun · R reload · E use · T repair · G siphon · Z eat · X drink · H bandage · B build · U muffle · N noise · K skills · F5 save · Esc menu"
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


func _add_block(pos: Vector3, size: Vector3, color: Color, collide: bool = true,
		surface: StandardMaterial3D = null) -> StaticBody3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = surface if surface != null else _flat_material(color)
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


## The title screen's backdrop: a still, foggy dusk view down the main street. It only changes the
## camera and the lighting, never the sim, because "New game" carries on in this same world.
func _title_view(on: bool) -> void:
	for layer: CanvasLayer in find_children("*", "CanvasLayer", true, false):
		if layer != menus:
			layer.visible = not on  # no HUD over the title
	if not on:
		if _title_camera != null:
			_title_camera.queue_free()
			_title_camera = null
			player.camera.current = true
			_apply_time()
		return
	_title_camera = Camera3D.new()
	add_child(_title_camera)
	_title_camera.position = Vector3(-1.5, 2.0, 2.0)  # just north of the stash crate, so it's out of shot
	_title_camera.look_at(Vector3(1.0, 2.2, -60.0))
	_title_camera.fov = 60.0
	_title_camera.current = true
	_sun.rotation_degrees = Vector3(-7.0, -60.0, 0.0)
	_sun.light_color = Color(1.0, 0.62, 0.38)
	_sun.light_energy = 0.7
	_moon.light_energy = 0.0
	_env.background_energy_multiplier = 0.35
	_env.ambient_light_energy = 0.3
	_env.fog_density = 0.018
	_env.fog_light_color = Color(0.36, 0.33, 0.4)
	_env.fog_light_energy = 0.6
	_env.volumetric_fog_density = 0.012


func _exit_tree() -> void:
	Surfaces.clear_cache()
	InventoryScreen.clear_cache()
	SoundView.clear_cache()


## Get into a car: its camera takes over and the walker is switched off until you get out.
func _enter_car(id: String) -> void:
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	if workbench_screen.is_open():
		workbench_screen.close()
	builder.set_active(false)
	driving = cars[id]
	_set_walker(false)
	driving.drive(true)
	sim.add_message("W/S gas and brake · A/D steer · Space handbrake · H horn · F lights · E get out", 6.0)


func _exit_car() -> void:
	var at := sim.exit_car()
	driving.drive(false)
	driving = null
	player.global_position = Vector3(at.x, 0.1, at.z)
	player.velocity = Vector3.ZERO
	_set_walker(true)
	player.camera.current = true
	nav.request_rebake()  # zombies walk round the parked car


func _set_walker(on: bool) -> void:
	player.visible = on
	player.collision_layer = Layers.WORLD if on else 0
	for node: Node in [player, interactor, melee, shooter, builder]:
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## The driving readout: speed, gas, damage and the keys.
func _car_hud() -> String:
	var c: Dictionary = sim.vehicles.cars[driving.id]
	var s := sim.vehicles.stats(driving.id)
	var line := "%s · %d km/h · gas %.1f / %d · damage %d%%" % [s["name"], roundi(absf(driving.forward_speed()) * 3.6),
			c["fuel"], int(s["tank"]), roundi(100.0 * (1.0 - float(c["hp"]) / float(s["hp"])))]
	var keys := "[E] get out   [H] horn   [F] lights   [Space] handbrake"
	if sim.vehicles.hotwire_left > 0.0:
		line += " · hotwiring..."
	elif not c["running"]:
		if not sim.vehicles.can_start(driving.id, sim.inventory):
			var need := int(sim.data.skills["hotwire_level"])
			if sim.skills.level("mechanics") >= need:
				line += " · no key"
				keys = "[R] hotwire   " + keys
			else:
				line += " · no key (hotwiring needs Mechanics %d)" % need
		else:
			line += " · " + ("out of gas" if float(c["fuel"]) <= 0.0 else "engine dead")
	return line + "
" + keys
