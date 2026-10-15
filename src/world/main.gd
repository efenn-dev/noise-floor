extends Node3D
## Greybox town (road, houses, cars, the factory) under a day/night sun, walked by a first-person Player.
## Game rules live in SimWorld (src/sim), stepped on a fixed tick; this node only draws them.
## Game flags go after `--`:
##   --screenshot[=PATH]   freeze time, save one frame as PNG, quit (tools/shot.sh wraps this)
##   --time=HOURS          start at this hour, e.g. --time=22 for night
##   --day=N               start on day N (M16: days 1-7 summer, 8-14 autumn, 15-21 winter, 22-28 spring)
##   --cam=X,Y,Z[,YAW[,PITCH]]  put the player's feet at X,Y,Z looking YAW/PITCH degrees
##   --demo-outpost        F1: an extractor on the first node of each kind (salvager, water pump, fuel pump, sawmill), power free
##   --at=PLACE            W3a: stand at a named spot on the bigger map (AT_PLACES: market, south, highway, woods, farms, west, junkyard, timber)
##                        (0,0 = north, level; +yaw turns left, +pitch looks up)
##   --flashlight          start with the flashlight on
##   --graphics=Q          V1: low, medium or high for this run only (not saved), for screenshots
##   --blood=off|on        V32: blood sprays and stains off (or on) for this run only (not saved)
##   --hitboxes            V33: draw the zombies' bone hit zones (head red, body yellow, arms blue, legs green)
##   --weapon=BASE         V11: hold a mint melee weapon (pipe, bat, axe, machete, knife)
##   --gun=BASE            V30: hold pistol, rifle, shotgun or crossbow (pete is the unique rifle)
##   --throw=ITEM          V30: ready pipe_bomb or bottle with its predicted arc visible
##   --drop=A,B,...        V34: lay these items or gear bases (rifle, jacket, axe...) in a row in front of you
##   --place=ITEM          V34: start placing ITEM (an item or a gear base) with its see-through ghost showing
##   --swing-at=T          V11: freeze the melee swing at fraction T (0-1), for screenshots
##   --reload-at=T         V13: freeze a held gun's reload at fraction T (0-1), for screenshots
##   --inspect-at=T        V13: freeze the held gun, melee weapon or fists inspecting at T (0-1)
##   --block               V15: hold the melee/fists guard pose, for screenshots
##   --break-windows[=R]   W2: break every window within R m (default 12) at the start, for screenshots
##   --vault-at=T          V17: face the nearest broken window and freeze its climb at fraction T (0-1)
##   --fists               V12: start bare-handed (your weapon goes to your pockets)
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
##   --slots                         open the title screen's save-slot picker (for screenshots)
##   --inventory                     open the inventory screen (Tab in game)
##   --loot[=KIND]                   start beside searched loot of KIND (fridge by default), with it open
##   --skills                        open the skills and perks screen (K in game)
##   --gear[=RARITY]                 a rolled gear piece (white, blue, yellow (default), gold, set) in your pockets,
##                                   shown in the inventory screen (M13)
##   --mod-screen[=pistol|rifle]     that gun plus every part in pockets, with its modding panel open (V23)
##   --zombie-type=TYPE              what --zombie spawns (shambler, runner, crawler, screamer, brute)
##   --drive[=car_N]                 start in a car (car_0, a sedan, by default; wrecks can't be driven)
##   --no-hints                      no first-game hints (they only show in a new game without --demo-*/--cam)
##   --hints                         show the first-game hints anyway (for screenshots)
##   --objectives                    show the first-night objectives midway through (for screenshots)
##   --inside[=N]                    start inside house N (0-11, default 0), looking at its fridge
## With no flags at all you get the title screen first (Continue / New game / Settings / Quit).

const SHOT_DELAY_FRAMES := 30
const SPAWN := Vector3(0, 0, 6)
const DEFAULT_ZOMBIES := 8
const STASH_CELL := Vector2i(1, 3)  # just east of the spawn point
## The area the zombie navmesh covers. W3a: the whole bigger map (WorldMap.EXTENT), in NavBaker tiles.
const NAV_BOUNDS := AABB(Vector3(-360, -1, -460), Vector3(720, 8, 760))
const GROUND_SIZE := Vector2(840, 880)  # W3a: x -420..420, z -520..360 (centred at GROUND_Z), past the map's edge
const GROUND_Z := -80.0
## W3a: --at=PLACE spots: [feet position, yaw, pitch] (yaw 0 = north, +90 = west).
const AT_PLACES := {
	"market": [Vector3(4, 0, 66), -70.0, 0.0],        # Market Street, looking east toward downtown
	"south": [Vector3(3, 0, 130), 0.0, 0.0],          # the south road, looking back north at the town
	"highway": [Vector3(262, 0, 120), 0.0, 0.0],      # on the highway looking north at a jam
	"woods": [Vector3(-120, 0, -192), 60.0, 0.0],     # on the woods track, looking north-west into the trees
	"farms": [Vector3(-170, 0, 100), 0.0, 0.0],       # the farm lane by the county road
	"west": [Vector3(-60, 0, 0), 0.0, 0.0],           # West Street, looking north
	"junkyard": [Vector3(150, 0, -46), 15.0, -12.0],  # F1: the junkyard's scrap heaps, from the lane
	"timber": [Vector3(-114, 0, -170), 75.0, -14.0],  # F1: a timber stand in the woods, from the track
}

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
var thrower: Thrower  # V30: throwable input, arc and projectile presentation
var placer: Placer  # V34: Place from the inventory: put a thing down where you aim
var workbench_screen: WorkbenchScreen  # M14: E on a workbench
var sensor_screen: SensorScreen  # M15: E on a sensor
var project_screen: ProjectScreen  # M17a: E on the water tower
var park: Dictionary = {}  # M17a: ParkPlan.generate(seed): warehouses, crates, zombies, wrecks, fences, the tower
var park_view: ParkView
var road_view: RoadView  # W3a: the bigger map's new roads
var country_view: CountryView  # W3a: woods, field trees, highway wrecks, the map's edge
var country: Dictionary = {}
var node_view: NodeView  # F1: resource nodes (their models and yellow spots)
var park_pieces := 0  # M17a: warehouse pieces the park plan laid this run (0 when the save holds them)
var base_log_screen: BaseLogScreen  # M15: L (or the pause menu)
var help_screen: HelpScreen  # P3: F1 (or Controls on the title screen and in the pause menu)
var build_menu: BuildMenu  # S3: B; click a piece to build it, 1-9/0 puts it on the hotbar
var hotbar_view: HotbarView  # S3: the ten slots along the bottom of the HUD
var defense_view: DefenseView
var bag_view: BagView
var noise_overlay: NoiseOverlay
var session_log: SessionLog
var hints: Hints  # first-game hints; null after a load, with --demo-*/--cam/--no-hints, or in screenshots
var objectives_panel: ObjectivesPanel  # V25: saved first-night loop, under the clock
var cars: Dictionary = {}  # car id -> CarBody
var town: Dictionary = {}  # TownPlan.generate(seed): the houses, their pieces, containers and beds (W1a)
var town_view: TownView
var street: Dictionary = {}  # A1: StreetPlan.generate (lamp posts, mailboxes, fences, trash cans, trees)
var street_view: StreetView
var town_pieces := 0  # pieces the town plan laid this run (0 when a save brought its own houses)
var first_bake_ms := 0.0  # how long the first navmesh bake took
var driving: CarBody = null  # the car you're in, or null when walking

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial  # V1: its colours follow the sun (Atmosphere.sky_colors)
var _ground_mesh: MeshInstance3D
var season_shown := ""  # M16: the season whose look is applied (ground, trees, roofs, fog)
## Q2: under a roof the fog thins to INDOOR_FOG of outside's, eased over FOG_EASE seconds (Old Pete was
## grey at 7 m in the factory hall). _apply_time sets the outdoor densities; _apply_fog scales them.
const INDOOR_FOG := 0.2
const MATERIALS_WIDTH := 380.0  # Q2: the top-right pockets block wraps at this width
const FOG_EASE := 0.5
var indoor_fog := 0.0  # 0 = outside's fog, 1 = fully thinned
var _fog_density := 0.008
var _vol_fog_density := 0.0
var _fog_started := false
var _title_camera: Camera3D  # set while the title screen shows its dusk view
var _hud: Label
var _build_label: Label
var _materials_hud: Label
var view_feel: ViewFeel  # V3: bob, sway, shake, hit marker, red edge, impact puffs
var crosshair: Crosshair  # P2: shown with a gun in hand; the gap is the spread
var _dot: ColorRect      # the centre dot, shown otherwise
var _keys_label: Label   # P3: the one-line key hint at the bottom, for what you're doing now
## P3: the key hint line never gets longer than this (it drops its least useful keys first).
const KEY_HINT_MAX := 110
## S3: the hotbar's bottom edge sits this far above the window's bottom (the health and key-hint lines are
## bottom-left under it, the first-game hints above it).
const HOTBAR_BOTTOM := 92.0
var _interact_label: Label
var _health_label: Label
var _hurt_flash: ColorRect
var _death_label: Label
var _last_health := 100.0
var _message_label: Label
var _perk_badge: PanelContainer
var _perk_badge_label: Label
var _gear_toast_label: Label
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
	if not GameSession.skip_menu:
		var migration_error := GameSession.migrate_legacy_save()
		if migration_error != "":
			push_warning(migration_error)
	if args.has("graphics"):
		Settings.graphics = Atmosphere.valid_quality(str(args["graphics"]))  # V1: this run only, not saved
	if args.has("blood"):
		Settings.blood = str(args["blood"]) != "off"  # V32: this run only, not saved
	ZombieHitboxes.show = args.has("hitboxes")  # V33
	var save := {}
	if GameSession.pending_load != "":
		save = SaveGame.read(GameSession.pending_load)
		GameSession.pending_load = ""
		_loaded = not save.is_empty()
	sim = SimWorld.new(float(args.get("time", "8.0")), null, int(save.get("seed", 1)),
			GameSession.current_difficulty)
	sim.clock.seconds_per_day = Settings.day_minutes * 60.0
	if args.has("day"):
		sim.clock.day = maxi(1, int(args["day"]))  # M16: --day=16 starts in winter (a save sets its own day)
	if args.has("screenshot"):
		_shot_path = args["screenshot"] if args["screenshot"] != "" else "user://shot.png"
		sim.paused = true
	if not _loaded and not args.has("no-hints") and (_wants_hints(args) or args.has("objectives")):
		sim.guidance.start(sim.clock.day, int(sim.tally["deaths"]))
	session_log = SessionLog.new()
	session_log.enabled = _shot_path == "" and DisplayServer.get_name() != "headless"
	SessionLog.prepare_slot()
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
	_build_park(not (_loaded and SaveGame.holds_park(save)))  # M17a: a pre-park save gets the park laid fresh
	_build_country()  # W3a: the bigger map round the town (nothing in it is saved: the same land every game)
	_build_player(args)
	_build_building(args)
	_build_zombies(args)
	_build_hud()
	inventory_screen = InventoryScreen.new()
	add_child(inventory_screen)
	inventory_screen.setup(sim)
	inventory_screen.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
	inventory_screen.place_requested.connect(func(item: String, uid: int) -> void:
		builder.set_active(false)
		thrower.cancel()
		placer.start(item, uid)
		if placer.active():
			sim.add_message(placer.last_message, 4.0))
	sim.container_searched.connect(_open_loot_container)
	build_menu = BuildMenu.new()
	add_child(build_menu)
	build_menu.setup(sim, builder)
	build_menu.message.connect(func(text: String) -> void: sim.add_message(text, 2.5))
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
	project_screen = ProjectScreen.new()
	add_child(project_screen)
	project_screen.setup(sim)
	project_screen.message.connect(func(text: String) -> void: sim.add_message(text, 4.0))
	base_log_screen = BaseLogScreen.new()
	add_child(base_log_screen)
	base_log_screen.setup(sim)
	help_screen = HelpScreen.new()
	add_child(help_screen)
	help_screen.setup()
	if _wants_hints(args):
		hints = Hints.new()
		hints.setup(sim, inventory_screen, noise_overlay)
		hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
		hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hints.position.y -= HOTBAR_BOTTOM + 84  # S3: above the hotbar
		_hud.get_parent().add_child(hints)  # the HUD layer, so the title screen hides it too
	if _loaded:
		_apply_save(save)
	if args.has("objectives") and not args.has("no-hints"):
		sim.guidance.debug_midway()
		objectives_panel.force_visible = true
	objectives_panel.suppressed = args.has("no-hints") or GameSession.skip_hints
	objectives_panel.refresh()
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
	if args.has("loot"):
		_setup_loot_flag(str(args["loot"]))
	if args.has("build-menu"):
		_open_build_menu()  # S3: --build-menu, for screenshots (B in game)
	if args.has("gear"):
		_give_rolled_gear(args["gear"])  # --gear=yellow: a rolled piece in your pockets, selected
	if args.has("skills"):
		skills_screen.open()  # --skills, for screenshots
	if args.has("weapon"):  # V11: --weapon=axe holds a mint melee weapon of that base (pipe, bat, axe, machete, knife)
		var base := str(args["weapon"])
		if sim.data.gear["bases"].has(base) and sim.data.gear["bases"][base]["slot"] == "weapon":
			var piece := sim.gear.make(base, "civilian", "white")
			sim.gear.pieces.append(piece)
			sim.gear.equip(piece["uid"])
	if args.has("break-windows"):  # W2: --break-windows[=R] breaks every window within R m (12) of you, for screenshots
		var r := float(args["break-windows"]) if str(args["break-windows"]).is_valid_float() else 12.0
		for key: String in sim.build.pieces.keys():
			if sim.piece_material(key) == "glass" and sim.build.piece_center(key).distance_to(player.global_position) <= r:
				sim.player_hit_piece(key, 50.0, "bullet")  # as a shot would: no weapon wear
	if args.has("vault-at"):
		_setup_vault_shot(clampf(float(args["vault-at"]), 0.0, 1.0))
	if args.has("fists"):
		sim.gear.unequip("weapon")  # V12: --fists starts bare-handed (the weapon goes to your pockets)
	if args.has("swing-at"):
		melee.hold_at = clampf(float(args["swing-at"]), 0.0, 1.0)  # V11: freeze the swing there, for screenshots
	if args.has("mod-screen"):
		_give_mod_screen(str(args["mod-screen"]))
	elif args.has("gun") or args.has("workbench") or args.has("shoot") or args.has("aim"):
		_give_gun(args.get("gun", ""), args.has("workbench"))  # M14: --gun[=pistol|rifle|pete], --workbench
	if args.has("demo-outpost"):  # F1: one of each extractor on its node, running
		sim.power.free = true
		var stock := Inventory.new()
		stock.give_all({"metal_plate": 200, "nails": 200, "scrap_metal": 200})
		var done := {}
		for n: Dictionary in sim.resource_nodes:
			if not done.has(n["kind"]):
				done[n["kind"]] = true
				sim.build.place(n["extractor"], n["cell"], BuildGrid.Side.NORTH, stock)
	if args.has("drop"):  # V34: a row of things lying 1.6-3 m ahead, for screenshots
		var looks := str(args["drop"]).split(",", false)
		var ahead := -player.global_basis.z
		var side := player.global_basis.x
		for i in looks.size():
			var at := player.global_position + ahead * 1.8 + side * (float(i) - (looks.size() - 1) / 2.0) * 0.55
			_lay_for_shot(looks[i], at, player.global_rotation.y + PI + 0.4 * i)
	if args.has("place"):
		var look := str(args["place"])
		if sim.data.items.has(look):
			sim.inventory.add(look, 3)
			placer.start(look)
		else:
			if sim.data.gear["bases"].has(look):
				var piece := sim.gear.make(look, "civilian", "white")
				sim.gear.pieces.append(piece)
				placer.start("", int(piece["uid"]))
	if args.has("throw"):
		var throwable := str(args["throw"])
		if throwable not in ["pipe_bomb", "bottle"]:
			throwable = "pipe_bomb"
		sim.inventory.add(throwable, 1)
		thrower.ready(throwable)
		thrower.hold_preview = true
	if args.has("window"):
		var wh: PackedStringArray = str(args["window"]).split("x")  # P2: --window=1280x720, a smaller window
		if wh.size() == 2:
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	if args.has("aim"):
		if str(args["aim"]) != "irons":  # V15: --aim=irons holds iron-sight ADS without fitting the scope
			var scope := sim.gear.make("scope", "civilian", "white")  # P2: --aim fits a scope and holds the
			sim.gear.pieces.append(scope)                              # zoom, for screenshots
			sim.attach_part(scope["uid"])
		sim.guns.raising = 0.0  # already up, so the screenshot is aimed
		shooter.hold_aim = true
	if args.has("block"):
		melee.hold_block = true  # V15: default pipe, or combine with --weapon / --fists
	if args.has("shoot"):
		shooter.fire.call_deferred()  # --shoot: fire once (screenshots of the HUD line after a shot)
	if args.has("reload-at"):
		shooter.hold_reload_at = clampf(float(args["reload-at"]), 0.0, 1.0)
	if args.has("inspect-at"):
		var at := clampf(float(args["inspect-at"]), 0.0, 1.0)
		if sim.guns.in_hand():
			shooter.hold_inspect_at = at
			shooter.start_inspect()
		else:
			melee.hold_inspect_at = at
			melee.start_inspect()
	if args.has("sensor-screen"):
		_open_sensor(_demo_sensor_key())  # M15: --sensor-screen (with --demo-defense), for screenshots
	if args.has("base-log"):
		_fill_demo_log()
		base_log_screen.open()  # M15: --base-log, for screenshots
	if args.has("tower"):
		_setup_tower(args["tower"])  # M17a: --tower[=N], N phases done and the next one's materials in your pockets
	if args.has("project-screen"):
		_open_project("water_tower")  # M17a: --project-screen, for screenshots
	if args.has("help"):
		help_screen.open()  # P3: --help, the controls screen (F1 in game), for screenshots
	if _shot_path == "" and not menus.is_open() and not inventory_screen.is_open() and not skills_screen.is_open() \
			and not workbench_screen.is_open() and not _m15_screen_open() and not build_menu.is_open():
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


## --gun[=pistol|rifle|shotgun|crossbow|pete]: a loaded gun in its slot, raised and in your hands.
## It also supplies that gun's ammo. --workbench gives every part and the crafting ingredients
## the bench uses, fits a crude suppressor and opens the workbench screen (for screenshots and trying it).
func _give_gun(which: String, bench: bool) -> void:
	var piece := {}
	if which == "pete":
		piece = sim.gear.roll_unique(RandomNumberGenerator.new(), "petes_deer_rifle")
	else:
		var gun_base: String = {"rifle": "hunting_rifle", "shotgun": "shotgun", "crossbow": "crossbow"}.get(which, "pistol")
		piece = sim.gear.make(gun_base, "civilian", "white")
	sim.gear.pieces.append(piece)
	sim.gear.equip(int(piece["uid"]))  # V14: a pistol lands in the sidearm slot, a rifle in primary
	piece["loaded"] = int(sim.gear.gun_stats(piece)["magazine"])
	var ammo := str(sim.data.guns["guns"][piece["base"]].get("ammo", "ammo_standard"))
	sim.inventory.add(ammo, 24 if ammo == "shells" else (12 if ammo == "bolt" else 30))
	if not sim.guns.in_hand():
		sim.swap_hands()
	sim.guns.raising = 0.0
	if bench:
		for base: String in ["oil_filter_suppressor", "scope", "extended_mag", "padded_stock", "choke"]:
			sim.gear.pieces.append(sim.gear.make(base, "civilian", "blue" if base == "scope" else "white",
					{"accuracy": 0.1} if base == "scope" else {}))
		var first_part := sim.gear.pieces.size() - 5
		if sim.gear.can_attach(piece, int(sim.gear.pieces[first_part]["uid"])) == "":
			sim.attach_part(int(sim.gear.pieces[first_part]["uid"]))
		sim.inventory.give_all({"ammo_casing": 20, "scrap_metal": 8, "gunpowder": 3, "nails": 16, "plank": 5})
		sim.player_pos = player.global_position
		_open_workbench("")


## --mod-screen[=pistol|rifle]: a bare gun and all five parts in pockets, selected in Tab so the
## data-driven slot panel and stat deltas are ready for screenshots.
func _give_mod_screen(which: String) -> void:
	var gun_base := "hunting_rifle" if which == "rifle" else "pistol"
	var gun := sim.gear.make(gun_base, "civilian", "white")
	sim.gear.pieces.append(gun)
	for part_base: String in sim.data.guns["parts"]:
		sim.gear.pieces.append(sim.gear.make(part_base, "civilian", "white"))
	sim.player_pos = player.global_position
	if not inventory_screen.is_open():
		inventory_screen.open()
	inventory_screen.select_gear(int(gun["uid"]), InventoryScreen.POCKETS)


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
	return sensor_screen.is_open() or base_log_screen.is_open() or help_screen.is_open() \
			or project_screen.is_open()  # P3: and help; M17a: and the project screen


## M17a: E on the water tower.
func _open_project(id: String) -> void:
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	sim.player_pos = player.global_position
	project_screen.open(id)


func _open_loot_container(id: String) -> void:
	if not sim.container_exists(id):
		return
	if skills_screen.is_open():
		skills_screen.close()
	if build_menu.is_open():
		build_menu.close()
	if workbench_screen.is_open():
		workbench_screen.close()
	if sensor_screen.is_open():
		sensor_screen.close()
	if project_screen.is_open():
		project_screen.close()
	if base_log_screen.is_open():
		base_log_screen.close()
	if help_screen.is_open():
		help_screen.close()
	inventory_screen.open_container(id)


func _open_storage(key: String) -> void:
	_open_loot_container(key)


## --loot[=KIND]: a deterministic searched container, open and within reach for layout screenshots.
func _setup_loot_flag(requested: String) -> void:
	var kind := requested if requested != "" else "fridge"
	kind = str({"cabinet": "kitchen", "crate": "factory_crate", "trunk": "car_trunk",
			"corpse": "zombie"}.get(kind, kind))
	var id := ""
	for candidate: String in sim.loot.containers:
		if sim.loot.containers[candidate]["table"] == kind:
			id = candidate
			break
	if id == "" and kind == "zombie":
		var z := sim.horde.spawn("shambler", player.global_position + Vector3(0, 0, -2.0))
		z.take_hit(1000.0, Vector3.ZERO, 0.0)
		sim.step()
		id = SimWorld.CORPSE + str(z.id)
	if id == "":
		sim.add_message("No loot container of kind " + kind, 5.0)
		return
	var at: Vector3 = sim.loot.containers[id]["pos"]
	player.position = Vector3(at.x, 0.0, at.z + 1.5)
	var look := at - player.position
	player.set_look(rad_to_deg(atan2(-look.x, -look.z)), -12.0)
	sim.player_pos = player.position
	if sim.loot.containers[id]["searched"]:
		_open_loot_container(id)
	else:
		sim.reveal_container(id)


## M17a --tower[=N]: N (0-3) of the water tower's phases already done, and what the next one needs in your
## pockets (phase 3's: a generator, a foundation for it, a power pole and gas). Stands you by the tower.
func _setup_tower(arg: String) -> void:
	var n := clampi(int(arg) if arg != "" else 0, 0, sim.projects.phases("water_tower").size())
	var st: Dictionary = sim.projects.state["water_tower"]
	st["phase"] = n
	if n >= sim.projects.phases("water_tower").size() and not sim.projects.is_done("water_tower"):
		sim.projects.done.append("water_tower")
	if n < sim.projects.phases("water_tower").size():
		var ph := sim.projects.current("water_tower")
		sim.inventory.give_all(ph.get("needs", {}))
		if float(ph.get("watts", 0.0)) > 0.0:
			sim.inventory.give_all({"metal_plate": 12, "nails": 12, "plank": 8, "gas_can": 3})
	else:
		sim.inventory.give_all(sim.data.buildables["water_tap"]["cost"])


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
	if _loaded or _shot_path != "" or args.has("no-hints") or args.has("cam") or args.has("inside") or args.has("park") or args.has("loot") \
			or args.has("tower") or GameSession.skip_hints:
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
	_update_indoor_fog(delta)
	if sound_view != null:
		sound_view.indoor = indoor_fog  # V4: indoor echo and muffled wind follow the same eased value
	if _shot_path == "":
		if not sim.paused:
			var played := delta / maxf(Engine.time_scale, 1.0)  # sleeping speeds time up
			sim.stats.add_real_time(played)
			GameSession.slot_real_seconds += played
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
	var elev := clock.sun_elevation_deg()
	var sky_l := Atmosphere.sky_light(elev)  # V1: keeps a glow through twilight, unlike daylight()
	_sun.rotation_degrees = Vector3(-arc, -30.0, 0.0)
	_sun.light_energy = 1.2 * Atmosphere.sun_strength(elev)  # V1: a low sun is still bright, just orange
	_sun.light_color = Atmosphere.sun_color(elev)
	_moon.rotation_degrees = Vector3(-(arc - 180.0), 150.0, 0.0)
	_moon.light_energy = 0.12 if clock.is_night() else 0.0
	var sky: Array = Atmosphere.sky_colors(elev)
	_sky_mat.sky_top_color = sky[0]
	_sky_mat.sky_horizon_color = sky[1]
	_sky_mat.ground_horizon_color = sky[1]
	_env.background_energy_multiplier = lerpf(0.04, 1.0, sky_l)
	_env.ambient_light_energy = lerpf(0.08, 1.0, sky_l)
	_env.fog_light_energy = lerpf(0.03, 1.0, sky_l)
	# Thicker, darker fog at night; the volumetric part (Forward+ only) is what shows the flashlight beam.
	_fog_density = lerpf(0.02, 0.006, sky_l)
	if clock.season() != season_shown:
		apply_season(clock.season())
	var fog_day := Atmosphere.fog_tint(elev, SeasonLook.fog_day(season_shown))  # M16: colder in winter; V1: warm at dusk
	_env.fog_light_color = Color(0.05, 0.06, 0.09).lerp(fog_day, sky_l)
	_vol_fog_density = lerpf(0.022, 0.002, sky_l)
	_apply_fog()
	_hud.text = "Day %d · %s %s" % [clock.day, clock.season_name(), clock.clock_text()]


## M16: the season's look: ground, tree leaves, roofs (the fog colour follows in _apply_time).
func apply_season(season: String) -> void:
	season_shown = season
	if _ground_mesh != null:
		_ground_mesh.material_override = SeasonLook.ground_material(season)
	if street_view != null:
		street_view.apply_season(season)
	if town_view != null:
		town_view.apply_season(season)
	if park_view != null:
		park_view.apply_season(season)
	if country_view != null:
		country_view.apply_season(season)


## Q2: 1 while the camera is under a roof (TownView knows the house cells and the factory hall), else 0.
func indoor_fog_target() -> float:
	var cam := get_viewport().get_camera_3d()
	if town_view == null or cam == null or _title_camera != null:
		return 0.0
	if park_view != null and park_view.is_under_roof(cam.global_position):
		return 1.0  # M17a: inside a warehouse
	return 1.0 if town_view.is_under_roof(cam.global_position) else 0.0


## Q2: eases indoor_fog toward its target over FOG_EASE s (snaps on the first frame, so a screenshot
## taken inside shows it) and re-applies the densities. Light, colour and night darkness are untouched.
func _update_indoor_fog(delta: float) -> void:
	if _title_camera != null:
		return
	var want := indoor_fog_target()
	var was := indoor_fog
	indoor_fog = want if not _fog_started else move_toward(indoor_fog, want, delta / FOG_EASE)
	_fog_started = true
	if indoor_fog != was:
		_apply_fog()


## Q2: the fog densities for this hour, thinned by how far indoors the camera is.
func fog_targets() -> Vector2:
	var k := lerpf(1.0, INDOOR_FOG, indoor_fog)
	return Vector2(_fog_density * k, _vol_fog_density * k)


func _apply_fog() -> void:
	if _title_camera != null:
		return
	var d := fog_targets()
	_env.fog_density = d.x
	_env.volumetric_fog_density = d.y


func _build_environment() -> void:
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	Atmosphere.setup_environment(_env)  # V1: tone mapping, colour grade, effect strengths
	_env.fog_enabled = true
	_env.fog_density = 0.008
	_env.fog_sky_affect = 0.3  # V1: the sky shows through the day haze
	_env.volumetric_fog_enabled = true  # Forward+ only; the Compatibility renderer (cloud screenshots) ignores it
	_env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	_env.volumetric_fog_length = 48.0
	_env.glow_enabled = true  # machine lamps bloom a little at night
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 1.0)
	add_child(_moon)
	_sun.directional_shadow_max_distance = 90.0
	Atmosphere.apply_quality(_env, _sun, Settings.graphics)  # V1: SSAO, SSIL, SDFGI, volumetric fog per preset


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
	if project_screen.is_open() and (p.dead or p.asleep):
		project_screen.close()
	if build_menu.is_open() and (p.dead or p.asleep):
		build_menu.close()
	var vault_active := not sim.player_vault.is_empty()
	if vault_active:
		var key: String = sim.player_vault["key"]
		if not player.vaulting:
			player.begin_vault(build_view.body_for(key))
		player.show_vault(sim.player_vault["from"] as Vector3, sim.player_vault["to"] as Vector3, sim.vault_fraction())
		view_feel.vault_fraction = sim.vault_fraction()
	elif player.vaulting:
		var landing: Vector3 = sim.vault_landing if sim.vault_landing.is_finite() else player.global_position
		player.end_vault(landing)
		sim.vault_landing = Vector3.INF
		view_feel.vault_fraction = -1.0
	else:
		view_feel.vault_fraction = -1.0
	# no walking while sorting your pockets, spending perk points, at the workbench or in the build menu
	player.frozen = p.dead or p.asleep or inventory_screen.is_open() or skills_screen.is_open() or workbench_screen.is_open() \
			or _m15_screen_open() or build_menu.is_open() or vault_active
	var sprint_requested := player.wish_sprint
	if player.use_device_input:
		sprint_requested = Input.is_action_pressed("sprint")
	shooter.sprinting = sprint_requested or driving != null or vault_active  # V15: requesting sprint drops ADS immediately
	var aimed := driving == null and not vault_active and shooter.aiming()
	sim.guns.aiming = aimed
	p.aiming = aimed
	p.set_blocking(driving == null and not vault_active and melee.blocking())
	# V28: the sim supplies a brute's shove; the CharacterBody resolves it against world collision.
	if p.knockback != Vector3.ZERO:
		player.apply_knockback(p.knockback)
		p.knockback = Vector3.ZERO
	player.speed_multiplier = p.speed_multiplier()
	player.can_sprint = p.can_sprint()
	p.sprinting = Vector2(player.velocity.x, player.velocity.z).length() > Player.WALK_SPEED + 0.5
	if _shot_path == "":
		Engine.time_scale = float(sim.data.survival["sleep_time_scale"]) if p.asleep else 1.0
	if driving != null and p.dead:
		_exit_car()
	if not sim.player.dead and driving == null and not vault_active and not player.vaulting:
		sim.player_pos = player.global_position  # while driving, the car reports where you are
	sim.player_lit = player.flashlight.visible
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		sim.player_facing = -cam.global_basis.z  # S4: for the jumpscare rules
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
			if builder.active:
				builder.set_active(false)  # S3: Esc stops building first; Esc again pauses
			else:
				_open_pause()  # closing it again is handled by Menus, which runs while paused
			get_viewport().set_input_as_handled()
		return
	if menus.is_open():
		return
	if event.is_action_pressed("objectives"):
		Settings.show_objectives = not Settings.show_objectives
		Settings.save_settings()
		objectives_panel.refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help") and not help_screen.is_open() and not inventory_screen.is_open() 			and not skills_screen.is_open() and not workbench_screen.is_open() and not _m15_screen_open():
		help_screen.open()  # P3: F1; it closes itself on F1 or Esc
		get_viewport().set_input_as_handled()
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
		if event.is_action_pressed("build_mode") or InputSetup.hotbar_slot(event) != -1:
			return  # S3: no building or snacking from the driver's seat either
	if workbench_screen.is_open() or _m15_screen_open():
		return  # they close themselves on E, Tab or Esc (the base log on L too)
	if event.is_action_pressed("base_log") and not sim.player.dead:
		base_log_screen.open()  # M15: L
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap_hands") and not sim.player.dead and InputSetup.captured():
		thrower.cancel()
		shooter.cancel_inspect()
		melee.cancel_inspect()
		sim.add_message(sim.swap_hands(), 2.0)  # M14: Q, melee weapon or gun
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quick_equip") and not sim.player.dead and driving == null:
		sim.add_message(sim.quick_equip_better(), 3.0)
		if inventory_screen.is_open():
			inventory_screen.refresh()
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
	if event.is_action_pressed("jump") and not sim.player.dead and driving == null:
		interactor.update_target()
		if interactor.target_key != "" and sim.build.is_broken(interactor.target_key):
			sim.player_pos = player.global_position
			var aiming_now := shooter.aiming()
			sim.guns.aiming = aiming_now
			sim.player.aiming = aiming_now
			var why := sim.start_vault(interactor.target_key)
			if why != "":
				sim.add_message(why, 2.5)
			else:
				shooter.cancel_inspect()
				melee.cancel_inspect()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inspect") and not sim.player.dead and driving == null:
		if sim.guns.in_hand():
			shooter.start_inspect()
		else:
			melee.start_inspect()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_mode") and not sim.player.dead:
		_open_build_menu()  # S3: B (the menu's own _input closes it)
		get_viewport().set_input_as_handled()
		return
	var slot := InputSetup.hotbar_slot(event)
	if slot != -1 and not sim.player.dead:
		_hotbar_press(slot)  # S3: 1-9, 0 (a screen with the mouse free takes these first, to assign)
		get_viewport().set_input_as_handled()
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
	menus.new_game.connect(_start_new_game)
	menus.continue_game.connect(continue_game)
	menus.delete_slot_requested.connect(func(slot: int) -> void:
		var why := GameSession.delete_slot(slot)
		menus.update_slots(GameSession.slot_summaries())
		if why != "":
			menus.set_status(why))
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
	menus.help_requested.connect(func(from: String) -> void:
		menus.hide_all()
		help_screen.open(from))
	help_screen.closed.connect(func(from: String) -> void:  # back to the menu it was opened from
		if from == "title":
			menus.show_title(GameSession.slot_summaries())
		elif from == "pause":
			menus.show_pause(FileAccess.file_exists(GameSession.save_path)))
	var has_save := FileAccess.file_exists(GameSession.save_path)
	var title_only := args.size() == 1 and (args.has("title") or args.has("slots") or args.has("new-game"))
	var flags := not args.is_empty() and not title_only
	if args.has("title") or args.has("slots") or args.has("new-game") or (not flags and not GameSession.skip_menu and not GameSession.started and not _loaded):
		menus.show_title(GameSession.slot_summaries())
		if args.has("slots"):
			menus.open_slots(false)
		elif args.has("new-game"):  # V29: the New game screen (name and difficulty) for that slot, for screenshots
			var slot_arg := str(args["new-game"])
			menus.open_slots(true)
			menus.choose_slot(int(slot_arg) if slot_arg.is_valid_int() else 2)
		_title_view(true)
		if _shot_path == "":  # a screenshot needs the frame counter running
			get_tree().paused = true
	elif args.has("pause"):
		menus.set_stats(sim.stats_text())
		menus.set_difficulty(sim.difficulty.display_name())
		menus.show_pause(has_save)
	elif args.has("settings"):
		menus.show_settings("pause")
	else:
		GameSession.started = true


func _start_new_game(slot: int, profile_name: String, difficulty: String) -> void:
	session_log.finish()  # finish the old profile's log before the selected slot name changes
	var why := GameSession.start_new_slot(slot, profile_name, difficulty)
	if why != "":
		menus.set_status(why)
		return
	GameSession.started = true
	_reload_with("")  # rebuild a truly fresh world before play starts


func continue_game(slot: int) -> void:
	session_log.finish()
	GameSession.select_slot(slot)
	_reload_with(GameSession.save_path)


func _open_pause() -> void:
	menus.set_stats(sim.stats_text())
	menus.set_difficulty(sim.difficulty.display_name())
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
	Atmosphere.apply_quality(_env, _sun, Settings.graphics)


## Saves the game (sim state plus where you're looking). Returns "" or what went wrong.
func save_game() -> String:
	sim.player_pos = player.global_position
	return SaveGame.write(sim, GameSession.save_path,
			{"look": [player.rotation_degrees.y, player.head.rotation_degrees.x],
			"meta": GameSession.make_meta(sim)})


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
	if not SaveGame.holds_park(save):
		sim.spawn_park_zombies(park)  # M17a: the park is new to this save, and so are its zombies
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
	_keys_label.text = key_hint_text()
	_build_label.text = builder.status_text()
	_materials_hud.text = builder.materials_text() + "\n" + sim.guns.hands_text()  # M13, M14: what's in your hands
	var use := _car_hud() if driving != null else interactor.status_text()
	_interact_label.text = use if use != "" else (shooter.last_message if shooter.last_message != "" else melee.last_message)
	var gun_up := driving == null and sim.guns.in_hand() and sim.ready_throw == "" and not builder.active and not sim.player.dead
	crosshair.visible = gun_up and (not shooter.aiming() or sim.guns.scoped())  # V15: irons hide it, a scope keeps it as the reticle
	_dot.visible = not gun_up
	if gun_up:
		crosshair.update_from(sim.guns.spread_deg(), player.camera)
	var notes := PackedStringArray()
	for m: Dictionary in sim.messages:
		notes.append(m["text"])
	_message_label.text = "\n".join(notes)
	_perk_badge.visible = sim.skills.perk_points > 0
	_perk_badge_label.text = "K: %d perk point%s" % [sim.skills.perk_points, "" if sim.skills.perk_points == 1 else "s"]
	_update_gear_toast()
	objectives_panel.refresh()
	_build_label.position.y = 52.0
	if objectives_panel.visible:
		_build_label.position.y = objectives_panel.position.y + objectives_panel.size.y + 8.0
	var overlay := noise_overlay.status_text()
	var level := sim.director.level_name()
	_heat_label.text = overlay if overlay != "" else ({"calm": "", "noticed": "The noise is being noticed",
			"group": "The dead are gathering", "horde": "Something big is coming"}[level])
	# Q2: its own line under the materials block (it used to sit 30 px down, on the carry-weight line).
	_heat_label.position.y = _materials_hud.position.y + maxf(_materials_hud.size.y, _materials_hud.get_combined_minimum_size().y) + 6.0
	var hp := sim.player.health
	var p := sim.player
	_health_label.text = "Health %d%s   Food %d   Water %d   Energy %d   Stamina %d%s%s%s" % [ceili(hp), " (healing)" if p.is_healing() else "", ceili(p.food),
			ceili(p.water), ceili(p.energy), ceili(p.stamina), warmth_text(), "   BLEEDING (H)" if p.bleeding else "",
			"   Sleeping... (any key wakes you)" if p.asleep else ""]
	var low := hp <= 30.0 or p.bleeding or p.food < 15.0 or p.water < 15.0 or p.is_freezing()
	_health_label.modulate = Color(1, 0.35, 0.3) if low else Color.WHITE
	if hp < _last_health:
		_hurt_flash.color.a = 0.45
	_last_health = hp
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 1.5)
	_death_label.visible = sim.player.dead
	if sim.player.dead:
		_hurt_flash.color.a = 0.6
		_death_label.text = "You died\nYour things are in a bag where you fell\nRespawning in %d" % ceili(sim.player.respawn_timer)


## M16: "   Warmth 64" once you've lost any (so a summer HUD is unchanged), with COLD / FREEZING below the lines.
func warmth_text() -> String:
	var p := sim.player
	if p.warmth >= 99.5:
		return ""
	return "   Warmth %d%s" % [ceili(p.warmth), " FREEZING" if p.is_freezing() else (" COLD" if p.is_cold() else "")]


func _update_gear_toast() -> void:
	var uid := sim.guidance.better_gear_uid
	var piece := sim.gear.find(uid)
	_gear_toast_label.visible = uid >= 0 and sim.guidance.better_gear_seconds > 0.0 and not piece.is_empty()
	if not _gear_toast_label.visible:
		return
	var slot := sim.gear.slot_of(piece)
	var rarity: Dictionary = sim.data.gear["rarities"][piece["rarity"]]
	var item_name := str(piece["name"] if piece["rarity"] in ["gold", "set"] else sim.gear.base_of(piece)["name"])
	_gear_toast_label.text = "%s %s: better than your %s slot. Press Y to wear" % [rarity["name"],
			item_name.to_lower(), slot]
	_gear_toast_label.add_theme_color_override("font_color", sim.gear.color(piece))


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	mesh.mesh = plane
	mesh.position.z = GROUND_Z
	mesh.material_override = Surfaces.material("ground", 6.0, Color(0.62, 0.64, 0.56))
	_ground_mesh = mesh  # M16: retinted per season (apply_season)
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()  # a box, not an endless plane, so the navmesh baker can read it
	slab.size = Vector3(GROUND_SIZE.x, 2, GROUND_SIZE.y)
	shape.shape = slab
	shape.position = Vector3(0, -1.0, GROUND_Z)
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
	sim.know_houses(town)  # P3: which houses you go into, for the session log
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
	# A1: street scenery off the road (lamps, mailboxes, fences, searchable trash cans, trees) and road markings.
	street = StreetPlan.generate(sim.seed_value, town)
	sim.place_street(street)
	street_view = StreetView.new()
	add_child(street_view)
	street_view.setup(sim, street)


## W3a (Emmitt: "it needs a much bigger world"): the roads out of town (WorldMap) and the countryside round it.
func _build_country() -> void:
	road_view = RoadView.new()
	road_view.name = "RoadView"
	add_child(road_view)
	var keep_out: Array = []  # F1: nothing grows on the resource nodes
	for n: Dictionary in sim.resource_nodes:
		keep_out.append(Vector2(n["pos"].x, n["pos"].z))
		keep_out.append(Vector2(n["prop_pos"].x, n["prop_pos"].z))
	country = CountryPlan.generate(sim.seed_value, keep_out)
	country_view = CountryView.new()
	country_view.name = "CountryView"
	add_child(country_view)
	country_view.setup(country)
	node_view = NodeView.new()
	node_view.name = "NodeView"
	add_child(node_view)
	node_view.setup(sim)


## M17a: the industrial park north of the factory hall (ParkPlan): the park road's asphalt, the warehouses
## (pieces laid unless the save holds them), their crates, the wrecks on the road (CarBodies), the wire fence
## and the water tower (ParkView), and the tower's project site.
func _build_park(lay_pieces: bool = true) -> void:
	var road := ParkPlan.road_rect()
	_add_block(Vector3(road.get_center().x, 0.01, road.get_center().y), Vector3(road.size.x, 0.02, road.size.y),
			Color(0.17, 0.17, 0.19), false, Surfaces.material("asphalt", 4.0, Color(0.5, 0.5, 0.5)))
	park = ParkPlan.generate(sim.seed_value)
	park_pieces = sim.place_park(park, lay_pieces)
	park_view = ParkView.new()
	add_child(park_view)
	park_view.setup(sim, park)
	for w: Dictionary in park["wrecks"]:
		var car := CarBody.new()
		add_child(car)
		car.setup(sim, w["id"], Color(0.32, 0.24, 0.2))  # burned-out rust
		cars[w["id"]] = car


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
	if args.has("at") and AT_PLACES.has(str(args["at"])):  # W3a: a named spot on the bigger map, for screenshots
		var at: Array = AT_PLACES[str(args["at"])]
		player.position = at[0]
		player.set_look(at[1], at[2])
	if args.has("park"):  # M17a: at the park's south entrance, outside the hall's north doorway, looking north
		player.position = ParkPlan.ENTRANCE
		player.set_look(0.0, 0.0)
	if args.has("tower"):  # M17a: beside the tower, on its road side, looking at it
		player.position = ParkPlan.TOWER_POS + Vector3(-6.0, 0.0, 1.5)
		player.set_look(-100.0, 18.0)
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


## V17 --vault-at=T: compose the screenshot at the nearest window already broken by --break-windows,
## stand on its nearer side, face it, start the real sim action, then hold that action at T.
func _setup_vault_shot(fraction: float) -> void:
	var nearest := ""
	var best := INF
	for key: String in sim.build.pieces:
		if not sim.build.is_broken(key):
			continue
		var distance := sim.build.piece_center(key).distance_squared_to(player.global_position)
		if distance < best:
			best = distance
			nearest = key
	if nearest == "":
		push_warning("--vault-at needs a broken window; combine it with --break-windows")
		return
	var piece: Dictionary = sim.build.pieces[nearest]
	var center := sim.build.piece_center(nearest)
	var yaw := sim.build.yaw_for(piece["id"], piece["cell"], piece["side"])
	var normal := Basis(Vector3.UP, deg_to_rad(yaw)).z
	var side := 1.0 if (player.global_position - center).dot(normal) >= 0.0 else -1.0
	player.global_position = Vector3(center.x, player.global_position.y, center.z) + normal * side * 1.05
	var toward := center - player.global_position
	player.set_look(rad_to_deg(atan2(-toward.x, -toward.z)), 0.0)
	sim.player_pos = player.global_position
	var why := sim.start_vault(nearest)
	if why == "":
		sim.set_vault_fraction(fraction)
	else:
		push_warning("--vault-at could not start: " + why)


func _build_building(args: Dictionary) -> void:
	# The debug kit waits in a crate next to the start; you carry a little food, water and a bandage.
	# (A loaded save brings back its own crates and pockets instead.)
	if not _loaded:
		sim.place_start_stash(STASH_CELL)
		sim.inventory.give_all({"clean_water": 1, "chips": 1, "bandage": 1})
	build_view = BuildView.new()
	add_child(build_view)
	for p: Dictionary in town["pieces"] + town["factory"]["pieces"] + park.get("pieces", []):
		build_view.styles[TownPlan.piece_key(p)] = p["style"]  # brick, siding, plaster, factory, floor; M17a park_brick, corrugated
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
	interactor.opened_project.connect(_open_project)
	interactor.opened_container.connect(_open_loot_container)
	interactor.opened_storage.connect(_open_storage)
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
	if args.has("demo-stove"):
		_place_demo_stove()
	if args.has("build"):
		builder.set_active(true)
		builder.select_id(args["build"])


## M16 --demo-stove: a stove loaded with 10 planks (burning) in the free floor cell of the house you stand in
## (--inside) in the same room nearest 3 m from you, its fire facing you, and you turned to look at it. Outside a house it goes
## on a new foundation 4 m ahead.
func _place_demo_stove() -> void:
	var here := BuildGrid.world_to_cell(player.global_position)
	var cells: Array = []
	for house: Dictionary in town.get("houses", []):
		if here in house["cells"]:
			cells = house["cells"]
	var taken := {here: true}
	for c: Dictionary in town.get("containers", []):
		taken[c["cell"]] = true
	var inv := Inventory.new()
	inv.give_all({"plank": 30, "scrap_metal": 20, "nails": 20})
	var best := Vector2i(here.x, here.y - 2)
	var best_d := INF
	for c: Vector2i in cells:
		var mid := Vector3((c.x + 0.5) * BuildGrid.GRID, 0.0, (c.y + 0.5) * BuildGrid.GRID)
		if taken.has(c) or sim.build.pieces.has("o:%d:%d" % [c.x, c.y]) or sim.noise.walls_between(player.global_position, mid, true) > 0:
			continue  # free, and in the same room (no wall between)
		var d := absf(Vector2((c.x + 0.5) * BuildGrid.GRID - player.global_position.x,
				(c.y + 0.5) * BuildGrid.GRID - player.global_position.z).length() - 3.0)
		if d < best_d:
			best_d = d
			best = c
	if cells.is_empty():
		sim.build.place("foundation", best, 0, inv)
	var to := Vector3((best.x + 0.5) * BuildGrid.GRID, 0.0, (best.y + 0.5) * BuildGrid.GRID) - player.global_position
	var side := (BuildGrid.Side.EAST if to.x < 0.0 else BuildGrid.Side.WEST) if absf(to.x) > absf(to.z) 			else (BuildGrid.Side.SOUTH if to.z < 0.0 else BuildGrid.Side.NORTH)
	if sim.build.place("stove", best, side, inv) == "":
		sim.climate.load_fuel(sim.build.key_for("stove", best), inv)
		sim.climate.tick(SimWorld.TICK, sim.clock.seconds_per_hour())  # lit now, for a screenshot
	player.set_look(rad_to_deg(atan2(-to.x, -to.z)), -18.0)


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
	nav.setup(self, NAV_BOUNDS, build_view)  # W3a: tiles; the pieces re-read on their own
	var t0 := Time.get_ticks_usec()
	nav.bake_near(player.global_position)  # where you are now; the rest of the map bakes in the background
	first_bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if DisplayServer.get_name() != "headless":
		print("Town: %d town pieces laid (houses and factory), %d park pieces, first navmesh bake %.0f ms" % [town_pieces,
				park_pieces, first_bake_ms])
	sim.build.piece_added.connect(func(k: String) -> void: nav.request_rebake(sim.build.piece_center(k)))
	sim.build.piece_removed.connect(func(_k: String, p: Dictionary) -> void:
		nav.request_rebake(sim.build.center_for(p["id"], p["cell"], p.get("side", BuildGrid.Side.NORTH))))
	sim.build.piece_changed.connect(func(k: String) -> void: nav.request_rebake(sim.build.piece_center(k)))  # doors
	if not _loaded:
		var street_count := int(args["zombies"]) if args.has("zombies") \
				else sim.difficulty.count("zombie_count", DEFAULT_ZOMBIES)
		sim.horde.spawn_town(street_count)
		if args.get("zombies", "") != "0":
			sim.spawn_house_zombies(town)  # W1b: one waits inside about one house in three
			sim.spawn_old_pete()  # M13: the named zombie in the factory hall, with his fire axe
			sim.spawn_park_zombies(park)  # M17a: shamblers and runners in and between the warehouses
	if args.has("zombie"):
		var v := String(args["zombie"]).split(",")
		for i in range(0, v.size() - 1, 2):
			var z := sim.horde.spawn(args.get("zombie-type", "shambler"), Vector3(v[i].to_float(), 0, v[i + 1].to_float()))
			z.facing = (player.position - z.pos).normalized()
			if args.has("dead-zombies"):  # S4: a corpse to look at (with --advance so the sim registers it)
				ZombieBody.settle_deaths = true  # V35: shown already fallen
				ZombieBody.forced_death_style = str(args.get("death-style", ""))
				z.take_hit(1000.0, Vector3.ZERO, 0.0)
	zombie_view = ZombieView.new()
	add_child(zombie_view)
	zombie_view.setup(sim, player)
	melee = Melee.new()
	add_child(melee)
	melee.setup(sim, player.camera, builder, [player.get_rid()])
	shooter = Shooter.new()
	add_child(shooter)
	shooter.setup(sim, player.camera, builder, [player.get_rid()])
	thrower = Thrower.new()
	add_child(thrower)
	thrower.setup(sim, player.camera, builder)
	view_feel = ViewFeel.new()
	add_child(view_feel)
	view_feel.setup(sim, player)
	melee.feel = view_feel
	shooter.feel = view_feel
	thrower.feel = view_feel
	bag_view = BagView.new()
	add_child(bag_view)
	bag_view.setup(sim)
	placer = Placer.new()  # V34: added after melee, shooter and thrower, so it sees the clicks first while placing
	add_child(placer)
	placer.setup(sim, player.camera, [player.get_rid()])
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
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 6  # above the live loot/inventory screen, where the upgrade is usually taken
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_perk_badge = PanelContainer.new()
	_perk_badge.position = Vector2(300, 12)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.16, 0.12, 0.035, 0.9)
	badge_style.border_color = Color(0.95, 0.8, 0.55)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(5)
	badge_style.content_margin_left = 9
	badge_style.content_margin_right = 9
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
	_perk_badge.add_theme_stylebox_override("panel", badge_style)
	_perk_badge_label = _outlined_label(16)
	_perk_badge_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	_perk_badge.add_child(_perk_badge_label)
	layer.add_child(_perk_badge)

	objectives_panel = ObjectivesPanel.new()
	objectives_panel.position = Vector2(16, 54)
	objectives_panel.setup(sim)
	layer.add_child(objectives_panel)

	_build_label = _outlined_label(20)
	_build_label.position = Vector2(16, 52)
	layer.add_child(_build_label)
	_materials_hud = _outlined_label(18)
	_materials_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_materials_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Q2: a fixed-width column that wraps, so a long pocket list can't reach the messages in the middle.
	_materials_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_materials_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_materials_hud.custom_minimum_size.x = MATERIALS_WIDTH
	_materials_hud.offset_left = -16.0 - MATERIALS_WIDTH
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
	# Q5: a centred column between the top-left and top-right blocks that wraps, so a long message
	# ("Smelter placed. It needs power: ...") can't run under the clock or the pockets.
	_message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_message_label.offset_left = MATERIALS_WIDTH + 32.0
	_message_label.offset_right = -(MATERIALS_WIDTH + 32.0)
	_message_label.offset_top = 60.0
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	layer.add_child(_message_label)

	_gear_toast_label = _outlined_label(23)
	_gear_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_gear_toast_label.offset_left = MATERIALS_WIDTH + 32.0
	_gear_toast_label.offset_right = -(MATERIALS_WIDTH + 32.0)
	_gear_toast_label.offset_top = 128.0
	_gear_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gear_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(_gear_toast_label)

	_heat_label = _outlined_label(18)
	_heat_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_heat_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_heat_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	layer.add_child(_heat_label)

	_death_label = _outlined_label(34)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_label.visible = false
	layer.add_child(_death_label)

	_keys_label = Label.new()  # P3: filled in by key_hint_text() every frame
	_keys_label.add_theme_font_size_override("font_size", 16)
	_keys_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_keys_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_keys_label.add_theme_constant_override("outline_size", 4)
	_keys_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_keys_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_keys_label)

	hotbar_view = HotbarView.new()  # S3: bottom centre, above the health and key-hint lines
	hotbar_view.setup(sim, builder)
	hotbar_view.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	hotbar_view.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar_view.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar_view.position.y -= HOTBAR_BOTTOM
	layer.add_child(hotbar_view)

	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.8)
	_dot.size = Vector2(4, 4)
	_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	layer.add_child(_dot)
	crosshair = Crosshair.new()  # P2: its ticks ignore the mouse too (it sets that on its own children)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	crosshair.visible = false
	layer.add_child(crosshair)
	# The HUD only shows things; it must never catch the mouse. A locked mouse sits in the middle of the
	# screen, right on the crosshair, and a HUD element there would swallow every look and click.
	for child in layer.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	add_child(toast_layer)


## P3: the one-line key hint at the bottom: only the keys that fit what you're doing. In a car its keys; in
## build mode the piece keys; otherwise the keys of what you look at (Interactor.keys()), the gun's or the
## pipe's, then walking about. F1 help is always last, and the least useful keys drop off to fit KEY_HINT_MAX.
## V34 (--drop): lays one item or a white gear piece of base `look` on the ground at `at`, turned to `yaw`.
func _lay_for_shot(look: String, at: Vector3, yaw: float) -> void:
	if sim.data.items.has(look):
		sim.bags.append({"id": sim._next_bag, "pos": at, "items": {look: 1}, "gear": [], "kind": SimWorld.ITEM, "yaw": yaw})
		sim._next_bag += 1
	elif sim.data.gear["bases"].has(look):
		sim.bags.append({"id": sim._next_bag, "pos": at, "items": {}, "gear": [sim.gear.make(look, "civilian", "white")],
				"kind": SimWorld.ITEM, "yaw": yaw})
		sim._next_bag += 1


func key_hint_text() -> String:
	var parts := PackedStringArray()
	if sim.player.dead:
		pass
	elif driving != null:
		parts.append_array(["WASD drive", "Space handbrake", "E get out", "H horn", "F lights"])
	elif builder.active:
		parts.append_array(["1-0 hotbar", "R rotate", "LMB place", "RMB remove", "B menu", "Esc stop", "wheel next"])
	elif placer != null and placer.active():
		parts.append_array(["LMB put down", "wheel turn", "RMB or Esc stop"])  # V34
	else:
		parts.append_array(interactor.keys())
		if sim.guidance.better_gear_uid >= 0 and sim.guidance.better_gear_seconds > 0.0:
			parts.append("Y wear better gear")
		if sim.ready_throw != "":
			parts.append_array(["LMB hold/release throw", "RMB cancel"])  # V30: a throwable is readied
		elif sim.guns.in_hand():
			parts.append_array(["LMB fire", "RMB aim", "R reload", "V inspect"])
			parts.append("Q pipe")
		else:
			parts.append_array(["LMB swing", "RMB block", "V inspect"])
			if not sim.gear.gun().is_empty():
				parts.append("Q gun")
		parts.append_array(["WASD move", "E use", "B build", "1-0 hotbar", "Tab gear", "K skills", "L log", "F light"])
	return fit_key_hint(parts)


## One key per part (the first part naming a key wins), then " · " between them, "F1 help" last, dropping
## parts from the end until the line fits KEY_HINT_MAX.
static func fit_key_hint(parts: PackedStringArray) -> String:
	var out := PackedStringArray()
	var keys := {}
	for p: String in parts:
		var key := p.split(" ")[0]
		if not keys.has(key):
			keys[key] = true
			out.append(p)
	while not out.is_empty() and (" · ".join(out) + " · F1 help").length() > KEY_HINT_MAX:
		out.remove_at(out.size() - 1)
	out.append("F1 help")
	return " · ".join(out)


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
	ImpactFx.clear_cache()
	InventoryScreen.clear_cache()
	SoundView.clear_cache()


## S3: B. The build menu, with the mouse free; the other screens close.
func _open_build_menu() -> void:
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	sim.player_pos = player.global_position
	build_menu.open()


## S3: a hotbar key on foot. V19: in build mode the keys read the build bar (a piece: build it; the same key
## again stops building); otherwise the hands bar (a weapon slot: draw that weapon; an item: use it). An empty
## key says how to fill it.
func _hotbar_press(i: int) -> void:
	var bar := Hotbar.BUILD_BAR if builder.active else Hotbar.HANDS_BAR
	match sim.hotbar.kind(i, bar):
		"build":
			var id := sim.hotbar.id(i, bar)
			if builder.active and builder.piece() == id:
				builder.set_active(false)
			else:
				builder.select_id(id)
				builder.set_active(true)
		"item":
			var item := sim.hotbar.id(i, bar)
			sim.add_message(sim.use_item(item), 2.5)
			if sim.ready_throw == item:
				thrower.hold_preview = true
		"slot":
			sim.add_message(sim.draw_weapon(sim.hotbar.id(i, bar)), 2.0)
		_:
			if bar == Hotbar.BUILD_BAR:
				sim.add_message("Key %s is empty on the build bar: press it on a piece in the build menu (B)" % Hotbar.key_name(i), 4.0)
			else:
				sim.add_message("Key %s is empty: press it on an item or a weapon in your pockets (Tab)" % Hotbar.key_name(i), 4.0)


## Get into a car: its camera takes over and the walker is switched off until you get out.
func _enter_car(id: String) -> void:
	if inventory_screen.is_open():
		inventory_screen.close()
	if skills_screen.is_open():
		skills_screen.close()
	if workbench_screen.is_open():
		workbench_screen.close()
	if build_menu.is_open():
		build_menu.close()
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
	nav.request_rebake(Vector3(at.x, 0, at.z))  # zombies walk round the parked car


func _set_walker(on: bool) -> void:
	player.visible = on
	player.collision_layer = Layers.WORLD if on else 0
	# Fix 2026-10-13: while you drive, the hidden walker stood at the car door still colliding (an invisible
	# post the car could hit). Nothing collides with it until you get out.
	player.collision_mask = Player.MASK if on else 0
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
