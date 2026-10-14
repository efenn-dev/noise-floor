extends "res://test/base_test.gd"
## V28: crawler and brute rules, spawn tables, hit geometry, presentation and named session stats.

const TICK := SimWorld.TICK


func _armed() -> SimWorld:
	var sim := SimWorld.new(12.0)
	var gun := sim.gear.make("pistol", "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(gun["uid"])
	sim.swap_hands()
	sim.guns.raising = 0.0
	return sim


func _place_door(sim: SimWorld, cell: Vector2i = Vector2i.ZERO) -> String:
	sim.give_debug_kit()
	eq(sim.build.place("foundation", cell, BuildGrid.Side.NORTH, sim.inventory), "", "foundation for the door")
	eq(sim.build.place("door", cell, BuildGrid.Side.NORTH, sim.inventory), "", "door placed")
	return sim.build.key_for("door", cell, BuildGrid.Side.NORTH)


func test_both_types_load_with_their_data_driven_stats() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "V28 zombie data validates")
	for type: String in ["crawler", "brute"]:
		check(data.zombies.has(type), "%s loads" % type)
		check(str(data.zombies[type]["name"]) != "", "%s has a display name" % type)
	near(float(data.zombies["crawler"]["chase_speed"]), 0.6, "crawler crawls at 0.6 m/s")
	near(float(data.zombies["crawler"]["climb_seconds"]), 4.0, "crawler takes four seconds through a window")
	near(float(data.zombies["crawler"]["stumble_time"]), 1.5, "ankle grab stumble time is data")
	check(float(data.zombies["crawler"]["hearing_day"]) > float(data.zombies["shambler"]["hearing_day"]),
			"crawler needs a louder sound and therefore has a shorter hearing radius")
	near(float(data.zombies["crawler"]["climb_arc"]), 0.0, "crawler goes through broken windows without climbing an arc")
	near(float(data.zombies["brute"]["hp"]), 3.0 * float(data.zombies["shambler"]["hp"]), "brute has 3x health")
	near(float(data.zombies["brute"]["chase_speed"]), 0.8, "brute walks at 0.8 m/s")
	near(float(data.zombies["brute"]["break_multiplier"]), 3.0, "brute break multiplier is data")
	near(float(data.zombies["brute"]["door_break_multiplier"]), 3.0, "brute door multiplier is data")
	near(float(data.zombies["brute"]["block_factor"]), 0.5, "brute block factor is data")


func test_crawler_speed_ankle_grab_and_stumble_recovery() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_pos = Vector3.ZERO
	var z := sim.horde.spawn("crawler", Vector3(0, 0, -1.0))
	z.state = ZombieBrain.State.CHASE
	near(z.move_speed(), 0.6, "crawler chase speed")
	var result := sim.zombie_hit_player(z)
	near(float(result["damage"]), 6.0, "ankle grab damage")
	check(result["stumbled"], "ankle grab starts a stumble")
	near(sim.player.speed_multiplier(), float(z.stats["stumble_slow"]), "stumble slows walking")
	sim.player.tick(float(z.stats["stumble_time"]) + TICK)
	near(sim.player.speed_multiplier(), 1.0, "the brief stumble wears off")


func test_crawler_never_breaks_a_door() -> void:
	var sim := SimWorld.new(12.0)
	var door := _place_door(sim)
	var hp: int = sim.build.pieces[door]["hp"]
	sim.player_pos = sim.build.piece_center(door) + Vector3(0, 0, -3)
	var z := sim.horde.spawn("crawler", sim.build.piece_center(door) + Vector3(0, -sim.build.piece_center(door).y, 1))
	z.take_hit(0.0, sim.player_pos, 0.0)
	for i in roundi(2.0 / TICK):
		z.blocked_by = door
		sim.step()
	check(sim.build.pieces.has(door), "crawler leaves the door standing")
	eq(sim.build.pieces[door]["hp"], hp, "crawler never damages the door")
	check(z.state != ZombieBrain.State.BREAK, "crawler never enters door-breaking state")


func test_crawler_crawls_slowly_through_a_broken_window() -> void:
	var data := GameData.load_default()
	var z := ZombieBrain.new(1, "crawler", data.zombies["crawler"], Vector3(1, 0, 1), 1)
	z.state = ZombieBrain.State.CHASE
	z.last_seen = Vector3(1, 0, -3)
	z.blocked_by = "window"
	var pieces := {"window": {"id": "window", "hp": 0, "cell": Vector2i.ZERO, "side": BuildGrid.Side.NORTH}}
	z.think(TICK, z.last_seen, false, false, pieces)
	eq(z.state, ZombieBrain.State.CLIMB, "broken window starts a crossing")
	near(z.climb_duration, 4.0, "crawler crossing lasts four seconds")
	z.think(3.9, z.last_seen, false, false, pieces)
	eq(z.state, ZombieBrain.State.CLIMB, "still crawling at 3.9 seconds")
	z.think(0.2, z.last_seen, false, false, pieces)
	eq(z.state, ZombieBrain.State.CHASE, "through after four seconds")


func test_brute_hard_hit_knocks_the_player_back() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_pos = Vector3.ZERO
	var z := sim.horde.spawn("brute", Vector3(0, 0, -1.5))
	var result := sim.zombie_hit_player(z)
	near(float(result["damage"]), float(z.stats["damage"]), "brute deals its full hard-hit damage")
	near(sim.player.knockback.length(), float(z.stats["player_knockback"]), "brute gives the player a metre-class shove velocity")
	check(sim.player.knockback.z > 0.0, "the shove is away from the brute")


func test_brute_shove_moves_the_world_player_about_a_metre() -> void:
	var scene := Node3D.new()
	tree.root.add_child(scene)
	var ground := StaticBody3D.new()
	ground.position = Vector3(0, -1, 0)
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(20, 2, 20)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	scene.add_child(ground)
	var player := Player.new()
	player.use_device_input = false
	scene.add_child(player)
	await tree.physics_frame
	await tree.physics_frame

	var sim := SimWorld.new(12.0)
	sim.player_pos = player.global_position
	var brute := sim.horde.spawn("brute", Vector3(0, 0, -1.5))
	sim.zombie_hit_player(brute)
	player.apply_knockback(sim.player.knockback)
	for i in 60:
		await tree.physics_frame
	check(player.global_position.z >= 0.8 and player.global_position.z <= 1.2,
			"brute shove moves the player about one metre (%.2f)" % player.global_position.z)
	scene.queue_free()
	await tree.process_frame


func test_brute_breaks_three_times_as_hard_and_barely_moves_from_melee() -> void:
	var sim := SimWorld.new(12.0)
	var door := _place_door(sim)
	var shambler := sim.horde.spawn("shambler", Vector3.ZERO)
	var brute := sim.horde.spawn("brute", Vector3.ZERO)
	eq(sim.zombie_structure_damage(brute, door), 3 * sim.zombie_structure_damage(shambler, door), "brute does 3x door damage")
	brute.take_hit(1.0, Vector3(0, 0, 2), 3.0)
	near(brute.knockback.length(), 3.0 * float(brute.stats["knockback_factor"]), "melee knockback is heavily resisted")


func test_brute_block_is_half_effective_and_parry_only_stops_the_hit() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_pos = Vector3.ZERO
	sim.player_facing = Vector3(0, 0, -1)
	var brute := sim.horde.spawn("brute", Vector3(0, 0, -1.5))
	sim.player.set_blocking(true)
	sim.player.block_time = SimWorld.PARRY_WINDOW + 0.1
	var blocked := sim.zombie_hit_player(brute)
	var reduction := float(sim.weapon_stats()["block_reduction"]) * float(brute.stats["block_factor"])
	near(float(blocked["damage"]), float(brute.stats["damage"]) * (1.0 - reduction), "ordinary block gets half its usual reduction")

	var parry_sim := SimWorld.new(12.0)
	parry_sim.player_pos = Vector3.ZERO
	parry_sim.player_facing = Vector3(0, 0, -1)
	var parried_brute := parry_sim.horde.spawn("brute", Vector3(0, 0, -1.5))
	parry_sim.player.set_blocking(true)
	parry_sim.player.block_time = 0.1
	var parried := parry_sim.zombie_hit_player(parried_brute)
	check(parried["parried"], "brute hit is parried")
	near(float(parried["damage"]), 0.0, "parry still stops the hit")
	near(parried_brute.stunned, 0.0, "parry does not stagger a brute")
	near(parried_brute.knockback.length(), 0.0, "parry does not shove a brute")


func test_starting_spawn_shares_include_more_crawlers_indoors() -> void:
	var data := GameData.load_default()
	var street := Horde.new(data, 27)
	var indoors := Horde.new(data, 27)
	var street_crawlers := 0
	var indoor_crawlers := 0
	for i in 240:
		street_crawlers += 1 if street.spawn_starting(Vector3.ZERO, false).type == "crawler" else 0
		indoor_crawlers += 1 if indoors.spawn_starting(Vector3.ZERO, true).type == "crawler" else 0
	check(street_crawlers >= 10 and street_crawlers <= 32, "street share is about 1 in 12 (%d/240)" % street_crawlers)
	check(indoor_crawlers >= 40 and indoor_crawlers <= 80, "indoor crawler share is about one quarter (%d/240)" % indoor_crawlers)
	check(indoor_crawlers > street_crawlers, "crawlers are more common indoors")


func test_brutes_unlock_between_runners_and_screamers_and_only_roll_at_night() -> void:
	var sim := SimWorld.new(12.0)
	var unlocks: Array = sim.data.noise["infamy"]["unlocks"]
	var at := {}
	for entry: Dictionary in unlocks:
		at[entry["type"]] = float(entry["at"])
	check(at["runner"] < at["brute"] and at["brute"] < at["screamer"], "brute unlock is between runner and screamer")
	var locked_brutes := 0
	for i in 300:
		locked_brutes += 1 if sim.director.pick_type(true) == "brute" else 0
	eq(locked_brutes, 0, "locked brute never rolls")
	sim.director.infamy = at["brute"]
	sim.step()
	check(sim.director.unlocked.has("brute"), "brute unlocks at its infamy")
	var day_brutes := 0
	var night_brutes := 0
	for i in 500:
		day_brutes += 1 if sim.director.pick_type(false) == "brute" else 0
		night_brutes += 1 if sim.director.pick_type(true) == "brute" else 0
	eq(day_brutes, 0, "brutes never join daytime wanderers")
	check(night_brutes > 0, "brutes join the night spawn table")


func test_night_waves_only_gain_capped_brutes_after_unlock() -> void:
	var data := GameData.load_default()
	var noise := NoiseField.new(data, BuildGrid.new(data))
	noise.continuous.append({"pos": Vector3.ZERO, "loudness": 80.0, "key": "generator", "kind": "generator"})
	var before := Director.new(data, 91)
	var horde := Horde.new(data, 91)
	before.heat = 100.0
	before._check = 0.0
	before.tick(0.0, noise, true, horde)
	var locked_brutes := 0
	for z: ZombieBrain in horde.zombies.values():
		locked_brutes += 1 if z.type == "brute" else 0
	eq(locked_brutes, 0, "locked night wave has no brute")

	var after := Director.new(data, 91)
	after.unlocked = ["brute"]
	var saw_brute := false
	for wave_index in 30:
		horde.zombies.clear()
		after.heat = 100.0
		after._check = 0.0
		var wave := after.tick(0.0, noise, true, horde)
		var brutes := int(wave.get("types", {}).get("brute", 0))
		check(brutes <= 2, "an early horde is capped at two brutes (wave %d: %d)" % [wave_index, brutes])
		saw_brute = saw_brute or brutes > 0
	check(saw_brute, "post-unlock night waves include brutes")
	var capped := Director.new(data, 17)
	capped.unlocked = ["brute"]
	var full := Horde.new(data, 17)
	full.spawn("brute", Vector3.ZERO)
	full.spawn("brute", Vector3.ONE)
	capped.heat = 100.0
	capped._check = 0.0
	var capped_wave := capped.tick(0.0, noise, true, full)
	eq(int(capped_wave.get("types", {}).get("brute", 0)), 0, "two living brutes cap later waves")


func test_new_types_round_trip_through_the_versioned_save() -> void:
	var a := SimWorld.new(12.0)
	var crawler := a.horde.spawn("crawler", Vector3(1, 0, -2))
	var brute := a.horde.spawn("brute", Vector3(-1, 0, -3))
	crawler.hp = 41.0
	brute.hp = 222.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(saved["version"], SaveGame.VERSION, "V28 writes the current save version")
	var b := SimWorld.new(12.0)
	eq(SaveGame.apply(b, saved), "", "save with both new types loads")
	eq(b.horde.zombies[crawler.id].type, "crawler", "crawler type survives")
	near(b.horde.zombies[crawler.id].hp, 41.0, "crawler health survives")
	eq(b.horde.zombies[brute.id].type, "brute", "brute type survives")
	near(b.horde.zombies[brute.id].hp, 222.0, "brute health survives")


func test_crawler_low_shot_hit_and_low_headshot() -> void:
	var data := GameData.load_default()
	var brain := ZombieBrain.new(1, "crawler", data.zombies["crawler"], Vector3.ZERO, 1)
	var body := ZombieBody.new()
	body.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(body)
	body.setup(brain, null)
	await tree.physics_frame
	var space := body.get_world_3d().direct_space_state
	var chest_y := body.global_position.y + 1.0
	var chest := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, chest_y, 2), Vector3(0, chest_y, -2), Layers.ZOMBIE))
	check(chest.is_empty(), "a chest-height shot passes over the crawler")
	var ground_y := body.global_position.y + 0.30
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, ground_y, 2), Vector3(0, ground_y, -2), Layers.ZOMBIE))
	check(not ground.is_empty() and ground["collider"] == body, "a ground-height shot hits the crawler")
	check(ground_y > body.global_position.y + body.head_y(), "that low hit is above the crawler's head line")
	body.queue_free()
	await tree.physics_frame

	var sim := _armed()
	var head := sim.horde.spawn("crawler", Vector3.ZERO)
	var torso := sim.horde.spawn("crawler", Vector3.ZERO)
	sim.shoot_zombie(head.id, true)
	sim.shoot_zombie(torso.id, false)
	near(70.0 - head.hp, 2.0 * (70.0 - torso.hp), "low headshot gets the gun head multiplier")


func test_bodies_use_crawl_and_heavy_scaled_looks() -> void:
	var data := GameData.load_default()
	var crawler := ZombieBody.new()
	tree.root.add_child(crawler)
	crawler.setup(ZombieBrain.new(7, "crawler", data.zombies["crawler"], Vector3.ZERO, 1), null)
	crawler.brain.state = ZombieBrain.State.ATTACK
	crawler._animate(0.016)
	eq(crawler._anim.assigned_animation, "Crawl", "crawler uses Crawl even while attacking")
	crawler.brain.take_hit(1000.0, Vector3.ZERO, 0.0)
	crawler._animate(0.016)
	eq(crawler._anim.assigned_animation, "Death", "crawler dies from its ground pose")
	near(crawler._voice.max_distance, float(data.zombies["crawler"]["voice_distance"]), "crawler voice has short range")

	var brute := ZombieBody.new()
	tree.root.add_child(brute)
	brute.setup(ZombieBrain.new(8, "brute", data.zombies["brute"], Vector3.ZERO, 1), null)
	eq(brute.body_variant, "heavy", "brute always uses the heavy body with vest and hard hat pieces")
	near(brute._model.scale.x, 1.28, "brute model is scaled up")
	check(brute._voice.pitch_scale < crawler._voice.pitch_scale, "brute voice is deeper")
	check(brute._voice.max_distance > crawler._voice.max_distance, "brute voice carries farther")
	crawler.queue_free()
	brute.queue_free()
	await tree.process_frame


func test_kill_stats_session_text_and_noise_labels_name_the_new_types() -> void:
	var sim := SimWorld.new(12.0)
	var crawler := sim.horde.spawn("crawler", Vector3(0, 0, -1))
	crawler.hp = 1.0
	check(sim.hit_zombie(crawler.id, false), "crawler killed")
	eq(sim.stats.timeline[-1][1], "killed a crawler", "kill timeline names the crawler")
	check("1 crawler" in "\n".join(sim.stats.summary_lines()), "session kill breakdown names the crawler")
	sim.horde.spawn("brute", Vector3(0, 0, -3))
	var overlay := NoiseOverlay.new()
	overlay.setup(sim)
	overlay.visible = true
	var text := overlay.status_text()
	check("Crawler" in text and "Brute" in text, "N overlay labels both new types")
	overlay.free()
