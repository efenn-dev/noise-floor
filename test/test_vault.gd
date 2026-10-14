extends "res://test/base_test.gd"
## V17: Zomboid-style broken-window vaulting, sharp glass, zombie climbs and save migration.

const N := BuildGrid.Side.NORTH
const TICK := SimWorld.TICK


func _window(broken: bool = true, shards: bool = true) -> SimWorld:
	var sim := SimWorld.new(10.0)
	var piece := {"id": "window", "cell": Vector2i(0, 0), "side": N, "hp": 40, "town": true}
	sim.build.restore("w:0:0:n", piece)
	if broken:
		sim.build.damage("w:0:0:n", 40)
		if not shards:
			sim.build.clear_shards("w:0:0:n")
	sim.player_pos = Vector3(1, 0, 1.05)
	return sim


func _run(sim: SimWorld, seconds: float) -> void:
	for _i in ceili(seconds / TICK):
		sim.step()


func _ground(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(1, -0.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 1, 8)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _walk_at_window(broken: bool) -> float:
	var scene := Node3D.new()
	tree.root.add_child(scene)
	_ground(scene)
	var sim := _window(false)
	var view := BuildView.new()
	scene.add_child(view)
	view.setup(sim.build)
	if broken:
		sim.build.damage("w:0:0:n", 40)
	var player := Player.new()
	player.use_device_input = false
	player.position = Vector3(1, 0, 1.8)
	player.wish_move = Vector2(0, 1)
	scene.add_child(player)
	for _i in 100:
		await tree.physics_frame
	var z := player.position.z
	scene.queue_free()
	await tree.process_frame
	return z


func _nav_around_window(broken: bool) -> float:
	var scene := Node3D.new()
	tree.root.add_child(scene)
	_ground(scene)
	var sim := _window(false)
	var view := BuildView.new()
	scene.add_child(view)
	view.setup(sim.build)
	if broken:
		sim.build.damage("w:0:0:n", 40)
	var nav := NavBaker.new()
	scene.add_child(nav)
	nav.setup(scene, AABB(Vector3(-3, -1, -4), Vector3(8, 5, 8)))
	nav.bake_now()
	for i in 12:  # the map takes a few frames to sync after a bake (test_zombie_world waits 0.2 s)
		await tree.physics_frame
	var map := scene.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(1, 0, 1.8), Vector3(1, 0, -1.8), true)
	var detour := 0.0
	for point: Vector3 in path:
		detour = maxf(detour, absf(point.x - 1.0))
	scene.queue_free()
	await tree.process_frame
	return detour


func test_intact_and_broken_windows_block_player_and_zombie_paths() -> void:
	var intact := _window(false)
	var broken := _window(true)
	check(intact.build.edge_blocks_walk("w:0:0:n"), "intact glass is a walking barrier in the rules")
	check(broken.build.edge_blocks_walk("w:0:0:n"), "a broken frame is still a walking barrier in the rules")
	var intact_stop: float = await _walk_at_window(false)
	var broken_stop: float = await _walk_at_window(true)
	check(intact_stop > Player.RADIUS - 0.05, "the intact collider stops the player (z %.2f)" % intact_stop)
	check(broken_stop > Player.RADIUS - 0.05, "the broken collider stops the player (z %.2f)" % broken_stop)
	var intact_detour: float = await _nav_around_window(false)
	var broken_detour: float = await _nav_around_window(true)
	check(intact_detour > 1.0, "zombie nav goes around intact glass (%.2f m sideways)" % intact_detour)
	check(broken_detour > 1.0, "zombie nav also goes around a broken frame (%.2f m sideways)" % broken_detour)


func test_player_vault_takes_about_point_nine_seconds_costs_stamina_and_makes_noise() -> void:
	var sim := _window(true, false)
	var before := sim.player.stamina
	eq(sim.start_vault("w:0:0:n"), "", "Space starts the climb")
	near(float(sim.player_vault["duration"]), 0.9, "base vault time", 0.001)
	near(sim.player.stamina, before - float(sim.data.survival["vault_stamina"]), "stamina paid", 0.001)
	_run(sim, 0.85)
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "vault"), "vault noise emitted")  # one-offs land in `recent` on the next tick
	check(not sim.player_vault.is_empty(), "still crossing before 0.9 s")
	_run(sim, 0.1)
	check(sim.player_vault.is_empty(), "finished at about 0.9 s")
	check(sim.player_pos.z < 0.0, "the sim moved the player to the other side")
	var fit := _window(true, false)
	fit.skills.xp["fitness"] = 1250.0
	check(fit.vault_duration() < 0.9, "high Fitness makes the same vault quicker")


func test_shards_cut_and_cleared_frames_do_not() -> void:
	var sharp := _window(true, true)
	eq(sharp.start_vault("w:0:0:n"), "", "climb through sharp glass")
	near(sharp.player.health, 95.0, "small glass cut", 0.001)
	check(sharp.player.bleeding, "the cut uses existing bleeding")
	var safe := _window(true, false)
	eq(safe.start_vault("w:0:0:n"), "", "climb through cleared frame")
	near(safe.player.health, 100.0, "cleared frame does no damage", 0.001)
	check(not safe.player.bleeding, "and causes no bleeding")


func test_clearing_takes_time_removes_shards_and_makes_glass_noise() -> void:
	var sim := _window(true, true)
	sim.gear.unequip("weapon")  # bare hands use the full 1.5 seconds
	eq(sim.start_clear_glass("w:0:0:n"), "Clearing the glass...", "E starts clearing")
	near(float(sim.clearing_glass["duration"]), 1.5, "bare-hand clear time", 0.001)
	_run(sim, 1.45)
	check(sim.build.has_shards("w:0:0:n"), "shards remain until the interaction finishes")
	_run(sim, 0.1)
	check(not sim.build.has_shards("w:0:0:n"), "clearing removes the shards")
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "glass_clear"), "clearing makes glass noise")
	var armed := _window(true, true)
	armed.start_clear_glass("w:0:0:n")
	near(float(armed.clearing_glass["duration"]), 0.975, "a melee weapon clears faster", 0.001)


func test_zombies_only_climb_broken_windows_for_about_two_point_five_seconds() -> void:
	var whole := _window(false)
	var zw := whole.horde.spawn("shambler", Vector3(1, 0, 1.05))
	zw.state = ZombieBrain.State.CHASE
	zw.last_seen = Vector3(1, 0, -4)
	zw.blocked_by = "w:0:0:n"
	zw.think(TICK, Vector3(1, 0, -4), false, false, whole.build.pieces)
	eq(zw.state, ZombieBrain.State.BREAK, "an intact window is broken first")
	var bashes := zw.think(TICK, Vector3(1, 0, -0.1), true, false, whole.build.pieces)
	eq(zw.state, ZombieBrain.State.BREAK, "it does not attack through intact glass even when you are close")
	eq(bashes, [{"target": "w:0:0:n"}], "it keeps bashing the intact window")
	var broken := _window(true)
	var z := broken.horde.spawn("shambler", Vector3(1, 0, 1.05))
	z.state = ZombieBrain.State.CHASE
	z.last_seen = Vector3(1, 0, -4)
	z.blocked_by = "w:0:0:n"
	var events := z.think(TICK, Vector3(1, 0, -4), false, false, broken.build.pieces)
	eq(z.state, ZombieBrain.State.CLIMB, "a broken window starts a climb")
	eq(events.size(), 0, "it cannot attack as the climb starts")
	for _i in floori(2.4 / TICK):
		events.append_array(z.think(TICK, Vector3(1, 0, -4), true, false, broken.build.pieces))
	eq(z.state, ZombieBrain.State.CLIMB, "still struggling at 2.4 seconds")
	eq(events.size(), 0, "never attacks during the climb")
	for _i in ceili(0.2 / TICK):
		z.think(TICK, Vector3(1, 0, -4), true, false, broken.build.pieces)
	check(z.state != ZombieBrain.State.CLIMB, "through after about 2.5 seconds")
	check(z.pos.z < 0.0, "the zombie ends on the other side")


func test_cannot_vault_while_aiming_reloading_swinging_or_over_encumbered() -> void:
	var aiming := _window(true)
	aiming.player.aiming = true
	check(aiming.start_vault("w:0:0:n").contains("aim"), "aiming blocks the vault")
	var reloading := _window(true)
	reloading.guns.reloading = 1.0
	check(reloading.start_vault("w:0:0:n").contains("reload"), "reloading blocks the vault")
	var swinging := _window(true)
	swinging.player.swing_cooldown = 0.5
	check(swinging.start_vault("w:0:0:n").contains("swing"), "swinging blocks the vault")
	var loaded := _window(true)
	loaded.inventory.add("scrap_metal", 100)
	check(loaded.carry_ratio() > 1.0, "test load is over the carry limit")
	check(loaded.start_vault("w:0:0:n").contains("encumbered"), "over-encumbered blocks the vault")


func test_shards_save_round_trip_and_version_15_broken_windows_gain_shards() -> void:
	var cleared := _window(true, false)
	var current: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(cleared)))
	var loaded := SimWorld.new()
	eq(SaveGame.apply(loaded, current), "", "current save loads")
	check(loaded.build.is_broken("w:0:0:n"), "broken state round-trips")
	check(not loaded.build.has_shards("w:0:0:n"), "cleared shard state round-trips")
	var old := SaveGame.read("res://test/fixtures/save_v15.json")
	eq(int(old.get("version", 0)), 15, "old fixture is version 15")
	var migrated := SimWorld.new()
	eq(SaveGame.apply(migrated, old), "", "version-15 fixture loads")
	check(migrated.build.is_broken("w:0:0:n"), "fixture window is broken")
	check(migrated.build.has_shards("w:0:0:n"), "old broken windows migrate with shards")
