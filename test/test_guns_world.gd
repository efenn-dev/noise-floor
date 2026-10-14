extends "res://test/base_test.gd"
## M14 guns, world side: a physics run firing a pistol at a placed zombie until it dies, the gun model in
## view and the recoil kick, R reloading through the interactor, and the workbench screen attaching a part.

var _scene: Node3D
var sim: SimWorld
var player: Player
var zview: ZombieView
var builder: BuildController
var shooter: Shooter


func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	ground.position = Vector3(0, -1, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	shape.shape = box
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)
	zview = ZombieView.new()
	_scene.add_child(zview)
	builder = BuildController.new()
	_scene.add_child(builder)
	builder.setup(sim, player.camera, [player.get_rid()])
	shooter = Shooter.new()
	_scene.add_child(shooter)
	shooter.setup(sim, player.camera, builder, [player.get_rid()])


func _arm(base: String) -> Dictionary:
	var gun := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(gun["uid"])
	gun["loaded"] = int(sim.gear.gun_stats(gun)["magazine"])
	sim.inventory.add("ammo_standard", 20)
	sim.swap_hands()
	return gun


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_pistol_kills_a_placed_zombie() -> void:
	_setup()
	var gun := _arm("pistol")
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -7))
	z.facing = Vector3.BACK
	zview.setup(sim, player)
	await _run(0.5)  # raise the gun, let the body appear
	player.set_look(0, -4)
	shooter.no_spread = true
	var shots := 0
	var hit_id := -1
	while not z.is_dead() and shots < 8:
		z.pos = Vector3(0, 0, -7)  # keep it standing where we aim
		var id := shooter.fire()
		if id >= 0:
			hit_id = id
		shots += 1
		await _run(0.3)
	eq(hit_id, z.id, "the ray from the camera meets the zombie")
	check(z.is_dead(), "the pistol kills it (%d shots)" % shots)
	eq(int(gun["loaded"]), 8 - shots, "one round a shot")
	check(sim.skills.xp.get("firearms", 0.0) >= shots + 3.0, "Firearms xp for shots and hits")
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "gunshot_pistol"), "the shots were heard")
	eq(sim.tally["kills"], 1, "a kill counted")
	await _teardown()


func test_gun_in_view_kick_and_reload_key() -> void:
	_setup()
	var interactor := Interactor.new()
	_scene.add_child(interactor)
	interactor.setup(sim, player.camera, builder, [player.get_rid()])
	await tree.process_frame
	check(not player.camera.find_child("Gun_pistol", true, false).visible, "no gun shown with the pipe out")
	_arm("pistol")
	await _run(0.5)
	var model: Node3D = player.camera.find_child("Gun_pistol", true, false)
	check(model.visible, "the pistol is held in view")
	check(model.find_children("*", "MeshInstance3D", true, false).size() > 0, "drawn from the kit model")
	shooter.no_spread = true
	player.set_look(0, 30)  # at the sky
	eq(shooter.fire(), -1, "a shot at the sky meets nothing")
	eq(shooter.last_message, "Missed", "and says so")
	await tree.process_frame
	await tree.process_frame
	check(player.camera.rotation.x > 0.0, "the camera kicks up")
	await _run(1.0)
	near(player.camera.rotation.x, 0.0, "and settles", 0.01)
	eq(interactor.refuel(), "Reloading standard rounds...", "R with nothing in front of you reloads")
	await _run(2.0)
	eq(int(sim.gear.gun()["loaded"]), 8, "full again")
	sim.swap_hands()
	await tree.process_frame
	await tree.process_frame
	check(not model.visible, "Q puts it away")
	await _teardown()


func test_gun_models_load() -> void:
	for path: String in Shooter.MODELS.values():
		var scene := load(path) as PackedScene
		check(scene != null, "%s exists" % path)
		if scene == null:
			continue
		var root := scene.instantiate() as Node3D
		var aabb := AABB()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge(mi.get_aabb()) if aabb.size != Vector3.ZERO else mi.get_aabb()
		check(aabb.size.z > aabb.size.x * 3.0, "%s is long front to back (%s)" % [path, aabb.size])
		check(aabb.size.z < 1.15, "%s fits in your hands" % path)
		root.free()
	for kind: String in ["gunshot_pistol", "gunshot_rifle", "gunshot_pistol_suppressed", "gunshot_rifle_suppressed", "reload"]:
		check(SoundView.EVENTS.has(kind) and SoundView.stream(SoundView.EVENTS[kind][0]) != null,
				"a %s noise plays its synth.py sound" % kind)


func test_workbench_screen_attaches_a_part() -> void:
	var s := SimWorld.new(12.0)
	var screen := WorkbenchScreen.new()
	tree.root.add_child(screen)
	screen.setup(s)
	screen.open("")
	check(screen.gun_text().begins_with("No gun equipped"), "no gun: it says so")
	var gun := s.gear.make("pistol", "civilian", "white")
	s.gear.pieces.append(gun)
	s.equip_gear(gun["uid"])
	var part := s.gear.make("oil_filter_suppressor", "civilian", "white")
	s.gear.pieces.append(part)
	screen.refresh()
	check(screen.gun_text().begins_with("Pistol"), "shows your gun")
	var b := screen.button("Part_%d" % int(part["uid"]))
	check(b != null and not b.disabled, "the suppressor is listed to attach")
	b.pressed.emit()
	eq(gun["parts"].get("muzzle", {}).get("uid", -1), part["uid"], "clicking it attaches it")
	eq(screen.button("Slot_muzzle").text, "Muzzle: Oil-filter suppressor", "the muzzle slot shows it")
	check(screen.gun_text().contains("Loudness 65 (suppressed)"), "and the numbers change")
	check(screen.button("Make_bench_standard").disabled, "no casings: can't make rounds")
	check(screen.button("Make_bench_subsonic").disabled, "subsonic needs Gunsmith")
	s.inventory.give_all({"ammo_casing": 10, "scrap_metal": 1})
	screen.refresh()
	screen.button("Make_bench_standard").pressed.emit()
	eq(s.inventory.count("ammo_standard"), 10, "the bench makes 10 standard rounds")
	screen.button("Slot_muzzle").pressed.emit()
	check(gun["parts"].is_empty(), "clicking the slot takes it off")
	check(s.gear.pieces.has(part), "back in your pockets")
	screen.queue_free()
	await tree.process_frame


func _right_click(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = player.get_viewport().get_visible_rect().size / 2.0
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	player.get_viewport().push_input(ev)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func test_ads_and_scope_zoom_on_right_click() -> void:
	# V15: every gun aims; iron sights narrow 15%, and the existing scope still reaches 35 degrees.
	_setup()
	InputSetup.register()
	InputSetup.assume_captured = true
	_arm("hunting_rifle")
	await _run(1.0)
	var base := player.camera.fov
	near(base, 75.0, "the normal view: 75 degrees")
	_right_click(true)
	await _frames(20)
	near(player.camera.fov, base * Shooter.IRON_FOV_MULT, "iron sights narrow the view by 15 percent")
	check(shooter.aiming(), "aiming down the iron sights")
	_right_click(false)
	var scope := sim.gear.make("scope", "civilian", "white")
	sim.gear.pieces.append(scope)
	sim.attach_part(scope["uid"])
	_right_click(true)
	await _frames(20)
	check(shooter.aiming(), "aiming down the scope")
	near(player.camera.fov, Shooter.AIM_FOV, "holding it zooms in to 35 degrees")
	await _frames(10)
	near(player.camera.fov, Shooter.AIM_FOV, "and stays zoomed while held")
	_right_click(false)
	await _frames(20)
	near(player.camera.fov, base, "letting go restores the view")
	shooter.hold_aim = true  # --aim
	await _frames(20)
	near(player.camera.fov, Shooter.AIM_FOV, "--aim holds the zoom for screenshots")
	sim.swap_hands()
	await _frames(20)
	near(player.camera.fov, base, "the pipe in hand: no zoom")
	InputSetup.assume_captured = false
	await _teardown()


func test_crosshair_shows_the_spread() -> void:
	# P2: a gun in hand shows the crosshair (the pipe shows the old centre dot); a shot opens its gap.
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var old_size := tree.root.size
	tree.root.size = Vector2i(1600, 900)  # headless windows start tiny
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await _frames(5)
	var cross: Crosshair = main.crosshair
	check(not cross.visible, "the pipe in hand: no crosshair")
	check(main._dot.visible, "the centre dot instead")
	eq(cross.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the crosshair never catches the mouse")
	check(cross.get_children().all(func(c: Node) -> bool: return (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE),
			"nor do its ticks")
	main._give_gun("pistol", false)
	await _frames(3)
	check(cross.visible, "a gun in hand: the crosshair shows")
	check(not main._dot.visible, "and the dot hides")
	var settled := cross.gap
	var expect := Crosshair.gap_for(main.sim.guns.spread_deg(), main.player.camera.fov, main.get_viewport().get_visible_rect().size.y)
	near(settled, expect, "its gap is the cone's size on screen", 0.5)
	main.shooter.hold_aim = true
	await _frames(2)
	check(not cross.visible and not main._dot.visible, "ADS hides both crosshair and centre dot")
	main.shooter.hold_aim = false
	await _frames(2)
	check(cross.visible, "letting go shows the gun crosshair again")
	main.sim.guns.raising = 0.0
	check(main.shooter.fire() != -2, "a shot")
	await _frames(2)
	check(cross.gap > settled * 1.5, "the gap opens after a shot (%.1f -> %.1f px, screen %s)" % [settled, cross.gap, main.get_viewport().get_visible_rect().size])
	for i in 150:
		main.sim.step()
	await _frames(2)
	near(cross.gap, settled, "and closes as it settles", 0.5)
	main.sim.swap_hands()
	await _frames(2)
	check(not cross.visible and main._dot.visible, "back to the pipe: the dot again")
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	main.queue_free()
	tree.root.size = old_size
	await _frames(2)
