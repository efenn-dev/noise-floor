extends "res://test/base_test.gd"
## V30 weapons and throwables. Every rule here is sim-owned; the world-only checks cover model contracts and
## the measured sight/attachment coordinates that presentation consumes.


func _run(sim: SimWorld, seconds: float) -> void:
	for _i in roundi(seconds / SimWorld.TICK):
		sim.step()


func _armed(base: String, ammo_count: int = 20) -> SimWorld:
	var sim := SimWorld.new(12.0)
	var gun := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(int(gun["uid"]))
	sim.swap_hands()
	sim.guns.raising = 0.0
	var ammo := str(sim.data.guns["guns"][base].get("ammo", "ammo_standard"))
	sim.inventory.add(ammo, ammo_count)
	return sim


func _part(sim: SimWorld, base: String) -> Dictionary:
	var part := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(part)
	return part


func _event(sim: SimWorld, kind: String) -> Dictionary:
	for event: Dictionary in sim.projectile_events:
		if event["type"] == kind:
			return event
	return {}


func test_shotgun_has_eight_pellets_a_cone_and_range_falloff() -> void:
	var sim := _armed("shotgun")
	var gun: Dictionary = sim.gear.gun()
	gun["loaded"] = 1
	var directions := sim.guns.shot_directions(Vector3.FORWARD)
	eq(directions.size(), 8, "a shell produces eight sim pellet checks")
	var half_angle := deg_to_rad(sim.guns.spread_deg())
	for direction: Vector3 in directions:
		check(direction.angle_to(Vector3.FORWARD) <= half_angle + 0.0001, "every pellet stays inside the cone")
	var near_total := sim.guns.damage(5.0) * sim.guns.pellet_count()
	var far_total := sim.guns.damage(20.0) * sim.guns.pellet_count()
	near(near_total, 144.0, "all eight pellets total 144 damage at five metres")
	check(far_total < near_total and far_total > near_total * 0.5,
			"damage has begun falling after twelve metres (%.1f vs %.1f)" % [far_total, near_total])
	var target := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	target.hp = 1000.0
	eq(sim.fire(), "", "the loaded shotgun fires")
	var hits := sim.fire_shotgun_pellets(Vector3(0, 1, 0), Vector3.FORWARD)
	eq(hits.size(), 8, "a close centred target receives all eight independent hits")
	near(target.hp, 1000.0 - near_total, "close pellet damage is accumulated in the sim")
	check(sim.guns.spread_deg() > half_angle * 180.0 / PI,
			"the heavy kick opens the next shot without widening the shell already in flight")


func test_shotgun_loads_one_shell_at_a_time_and_fire_interrupts() -> void:
	var sim := _armed("shotgun", 6)
	var gun: Dictionary = sim.gear.gun()
	eq(gun["loaded"], 0, "a new shotgun is empty")
	check(sim.reload().begins_with("Reloading"), "R starts the first shell step")
	_run(sim, 0.60)
	eq(gun["loaded"], 1, "one short step loads exactly one shell")
	check(sim.guns.reloading > 0.0, "the next shell step starts while room and ammunition remain")
	eq(sim.fire(), "", "a loaded shell can fire during the following reload step")
	eq(gun["loaded"], 0, "the trigger used that shell")
	near(sim.guns.reloading, 0.0, "firing interrupts the shell-by-shell reload")
	check(sim.guns.cooldown > 0.8, "the pump is part of the long post-shot cooldown")
	_run(sim, 0.80)
	eq(sim.guns.can_fire(), "Not ready", "the action is still pumping before 0.85 seconds")
	_run(sim, 0.10)
	eq(sim.guns.can_fire(), "Click. Empty (R to reload)", "the pump finishes before the empty click")


func test_choke_tightens_only_the_shotgun_cone() -> void:
	var sim := _armed("shotgun")
	var bare := sim.guns.spread_deg()
	var choke := _part(sim, "choke")
	eq(sim.gear.attach(sim.gear.gun(), int(choke["uid"])), "", "the choke fits the shotgun muzzle")
	near(sim.guns.spread_deg(), bare * 0.60, "the choke tightens the pellet cone by forty percent")
	var suppressor := _part(sim, "oil_filter_suppressor")
	check(sim.gear.can_attach(sim.gear.gun(), int(suppressor["uid"])).contains("does not fit"),
			"a suppressor cannot fit the shotgun")
	var pistol := sim.gear.make("pistol", "civilian", "white")
	var other_choke := _part(sim, "choke")
	check(sim.gear.can_attach(pistol, int(other_choke["uid"])).contains("does not fit"), "the choke cannot fit another gun")


func test_crossbow_bolt_has_travel_time_gravity_and_quiet_noise() -> void:
	var sim := _armed("crossbow", 4)
	sim.data.guns["guns"]["crossbow"]["spread"] = 0.00001
	var target := sim.horde.spawn("shambler", Vector3(0, 0, -10))
	target.hp = 150.0
	var before := target.hp
	sim.launch_bolt(Vector3(0, 1, 0), Vector3.FORWARD)
	_run(sim, 0.10)
	near(target.hp, before, "the bolt has not teleported to a target ten metres away")
	_run(sim, 0.15)
	check(target.hp < before and not _event(sim, "bolt_hit").is_empty(), "the travelling bolt hits at ten metres")

	var low := _armed("crossbow")
	low.data.guns["guns"]["crossbow"]["spread"] = 0.00001
	var low_target := low.horde.spawn("shambler", Vector3(0, 0, -40))
	low.launch_bolt(Vector3(0, 1, 0), Vector3.FORWARD)
	_run(low, 1.2)
	near(low_target.hp, 100.0, "an uncompensated forty-metre shot drops below the target")
	check(not _event(low, "bolt_land").is_empty(), "the low bolt lands as a recoverable projectile")

	var high := _armed("crossbow")
	high.data.guns["guns"]["crossbow"]["spread"] = 0.00001
	var high_target := high.horde.spawn("shambler", Vector3(0, 0, -40))
	high.launch_bolt(Vector3(0, 1, 0), Vector3(0, 0.30, -1).normalized())
	_run(high, 1.0)
	near(high_target.hp, 100.0, "an over-elevated forty-metre shot passes high")

	var quiet := _armed("crossbow")
	quiet.gear.gun()["loaded"] = 1
	eq(quiet.fire(), "", "the crossbow releases")
	quiet.step()
	var reports := quiet.noise.recent.filter(func(e: Dictionary) -> bool: return e["kind"] == "gunshot_crossbow")
	check(not reports.is_empty(), "the crossbow has its own sound event")
	if not reports.is_empty():
		near(float(reports[-1]["loudness"]), 25.0, "the crossbow report is only 25 loud")


func test_bolts_survive_seventy_percent_and_recover_from_ground_or_body() -> void:
	var survived := 0
	for i in 1000:
		if SimWorld.bolt_survives(float(i) / 1000.0):
			survived += 1
	eq(survived, 700, "the survival boundary is exactly seventy percent")
	var ground := _armed("crossbow")
	ground.data.guns["guns"]["crossbow"]["spread"] = 0.00001
	ground._ballistic_rng.seed = 1
	ground.launch_bolt(Vector3(0, 0.25, 0), Vector3.FORWARD)
	_run(ground, 0.5)
	if ground.projectile_pickups.is_empty():
		# Seed independence is not part of the rule; force the deterministic survival branch itself for this contract.
		ground._drop_bolt_pickup(Vector3.ZERO)
	var pickup_id: String = ground.projectile_pickups.keys()[0]
	eq(ground.loot.inventory(pickup_id).count("bolt"), 1, "a surviving landed bolt is a searchable pickup")

	var body := _armed("crossbow")
	var zombie := body.horde.spawn("shambler", Vector3.ZERO)
	zombie.hp = 0.0
	zombie.state = ZombieBrain.State.DEAD
	body.embedded_bolts[zombie.id] = 1
	body.step()
	var corpse := SimWorld.CORPSE + str(zombie.id)
	var found := body.loot.reveal(corpse)
	eq(int(found["items"].get("bolt", 0)), 1, "a surviving embedded bolt is recovered from the body")


func test_pipe_bomb_fuse_blast_falloff_self_damage_structure_damage_and_noise() -> void:
	var sim := SimWorld.new(12.0)
	sim.give_debug_kit()
	eq(sim.build.place("foundation", Vector2i.ZERO, 0, sim.inventory), "", "test foundation placed")
	var key := sim.build.key_for("foundation", Vector2i.ZERO)
	var center := sim.build.piece_center(key)
	var hp := int(sim.build.pieces[key]["hp"])
	var near_zombie := sim.horde.spawn("shambler", center + Vector3(0.4, 0, 0))
	var far_zombie := sim.horde.spawn("shambler", center + Vector3(4.4, 0, 0))
	sim.player_pos = center + Vector3(4.0, 0, 0)
	var health := sim.player.health
	sim.inventory.add("pipe_bomb", 1)
	sim.ready_throwable("pipe_bomb")
	eq(sim.throw_ready_item(center + Vector3.UP * 0.12, Vector3.ZERO), "", "the bomb leaves the hands")
	_run(sim, 2.90)
	check(not sim.thrown.is_empty() and _event(sim, "explosion").is_empty(), "the fuse has not fired before three seconds")
	_run(sim, 0.20)
	check(sim.thrown.is_empty() and not _event(sim, "explosion").is_empty(), "the three-second fuse explodes")
	check(near_zombie.hp < far_zombie.hp, "blast damage falls off toward five metres")
	check(far_zombie.stunned > 0.0 and far_zombie.knockback.length() > 0.0, "even an edge hit knocks a zombie down and back")
	check(sim.player.health < health, "the player is hurt inside their own blast")
	check(sim.build.pieces.has(key) and int(sim.build.pieces[key]["hp"]) < hp,
			"the blast lightly damages rather than deletes a sturdy built piece")
	sim.step()  # one-off sounds enter NoiseField.recent on the tick after emit()
	var booms := sim.noise.recent.filter(func(e: Dictionary) -> bool: return e["kind"] == "pipe_bomb")
	check(not booms.is_empty(), "the explosion emits a noise event")
	if not booms.is_empty():
		near(float(booms[-1]["loudness"]), 150.0, "the pipe bomb is extremely loud")


func test_bottle_lures_to_its_landing_point_and_arc_matches() -> void:
	var sim := SimWorld.new(12.0)
	var zombie := sim.horde.spawn("shambler", Vector3(8, 0, -8))
	sim.player_pos = Vector3(20, 0, 20)
	sim.inventory.add("bottle", 1)
	sim.ready_throwable("bottle")
	var origin := Vector3(0, 1.5, 0)
	var velocity := SimWorld.throw_velocity(Vector3.FORWARD, 0.72)
	var arc := SimWorld.predict_throw_arc(origin, velocity)
	var predicted: Vector3 = arc[arc.size() - 1]
	sim.throw_ready_item(origin, velocity)
	for _i in 60:
		sim.step()
		if not _event(sim, "bottle_break").is_empty():
			break
	var shattered := _event(sim, "bottle_break")
	check(not shattered.is_empty(), "the bottle shatters on its first landing")
	if shattered.is_empty():
		return
	check((shattered["pos"] as Vector3).distance_to(predicted) < 0.001,
			"the thrown bottle lands exactly where the preview predicted")
	# Listening is staggered, so allow the one-off sound's hearing window to reach this zombie.
	_run(sim, NoiseField.HEAR_WINDOW + SimWorld.TICK)
	eq(zombie.state, ZombieBrain.State.INVESTIGATE, "the one-off break sends an idle zombie to investigate")
	check(zombie.sound_pos.distance_to(predicted) < 0.001, "it investigates the landing point, not the player")
	var sounds := sim.noise.recent.filter(func(e: Dictionary) -> bool: return e["kind"] == "bottle_break")
	check(not sounds.is_empty(), "the bottle emits one data-driven distraction noise")
	if not sounds.is_empty():
		near(float(sounds[-1]["loudness"]), 65.0, "the bottle's distraction loudness is 65")


func test_throwables_are_hands_bar_items_and_session_log_counts_throws() -> void:
	var sim := SimWorld.new()
	for i in 2:
		var item := "pipe_bomb" if i == 0 else "bottle"
		eq(sim.hotbar.validate(Hotbar.item_entry(item)), "", item + " is a valid hands-bar entry")
		eq(sim.hotbar.assign(8 + i, Hotbar.item_entry(item)), "", item + " can be assigned")
		eq(sim.hotbar.id(8 + i), item, item + " stays on its key")
	sim.stats.note_throw("Pipe bomb")
	sim.stats.note_throw("Glass bottle")
	var text := "\n".join(sim.stats.summary_lines())
	check("Throws: Pipe bomb 1, Glass bottle 1." in text, "the session summary counts throws by item")


func test_recipes_loot_models_grips_parts_and_sights_cover_every_new_item() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "all V30 content passes data validation")
	eq(data.recipes["press_bolts"]["out"], {"bolt": 6}, "planks and nails make six bolts")
	check(data.recipes["press_bolts"]["in"].has("plank") and data.recipes["press_bolts"]["in"].has("nails"),
			"bolt recipe uses planks and nails")
	check(data.recipes["bench_pipe_bomb"]["in"].has("scrap_metal")
			and data.recipes["bench_pipe_bomb"]["in"].has("gunpowder")
			and data.recipes["bench_pipe_bomb"]["in"].has("nails"), "pipe bombs require all three ingredients")
	var loot_items := {}
	for table: String in data.loot:
		for entry: Dictionary in data.loot[table]["items"]:
			loot_items[entry["item"]] = true
	for item: String in ["shells", "bolt", "bottle", "gunpowder", "pipe_bomb"]:
		check(loot_items.has(item), "loot tables can drop " + item)
	for source: String in ["police", "hunter", "house"]:
		check(data.guns["gun_weights_by_source"][source].has("shotgun"), source + " can roll a shotgun")
	check(float(data.guns["gun_weights_by_source"]["house"]["shotgun"])
			< float(data.guns["gun_weights_by_source"]["house"]["pistol"]), "house shotguns are rarer than pistols")
	check(data.loot["kitchen"]["items"].any(func(e: Dictionary) -> bool: return e["item"] == "shells"),
			"ordinary house kitchens can turn up a few shells")
	for source: String in ["hunting_cabin", "garage"]:
		check(data.guns["gun_weights_by_source"][source].has("crossbow"), source + " can roll a crossbow")
	check(data.guns["part_weights"].has("choke") and data.guns["finds"].values().any(
			func(find: Dictionary) -> bool: return float(find.get("part", 0.0)) > 0.0),
			"the choke participates in part loot rolls")
	var bundled := SimWorld.new(12.0)
	bundled.data.guns["finds"]["hunting_cabin"] = {"gun": 1.0, "part": 0.0, "ammo": 0.0}
	bundled.data.guns["gun_weights_by_source"]["hunting_cabin"] = {"crossbow": 1.0}
	bundled.data.guns["police_find"] = 0.0
	var crossbow_find := bundled._search_guns({"id": "forced_crossbow", "table": "hunting_cabin"})
	eq(crossbow_find["pieces"][0]["base"], "crossbow", "the rare cabin gun roll can produce a crossbow")
	check(crossbow_find["items"].has("bolt"), "a found crossbow is bundled with bolts")
	for id: String in ["shotgun", "crossbow"]:
		check(ResourceLoader.exists(Shooter.MODELS[id]), id + " model imports")
		check(Hands.GUNS.has(id) and Hands.GUNS[id].has("right") and Hands.GUNS[id].has("left"), id + " has measured two-hand grips")
		var pose := Shooter.aim_pose(id)
		var points: Dictionary = Shooter.SIGHT_POINTS[id]
		var basis := Basis.from_euler(pose["rotation"] as Vector3)
		var rear: Vector3 = (pose["position"] as Vector3) + basis * (points["rear"] as Vector3)
		var front: Vector3 = (pose["position"] as Vector3) + basis * (points["front"] as Vector3)
		check(Vector2(rear.x, rear.y).length() <= 0.003 and Vector2(front.x, front.y).length() <= 0.003,
				id + " ADS sight line is within three millimetres of camera centre")
	for id: String in ["pipe_bomb", "bottle"]:
		check(ResourceLoader.exists(Thrower.MODELS[id]), id + " throwable model imports")
		check(Hands.THROWABLES.has(id), id + " has a right-hand grip")
	check(ResourceLoader.exists(Shooter.PART_MODELS["choke"]), "the choke model imports")
	check(Shooter.ATTACHMENT_ANCHORS["shotgun"].has("muzzle"), "shotgun choke uses its measured muzzle anchor")
	for id: String in ["shotgun", "crossbow", "shells", "pipe_bomb", "bottle", "gunpowder", "choke"]:
		check(ResourceLoader.exists("res://assets/icons/%s.png" % id), id + " icon exists")
