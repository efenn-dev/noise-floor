extends "res://test/base_test.gd"
## V33 (Emmitt: "better hitboxes"): zombies are hit through zones on their animated bones (head, torso, arms,
## legs), each with its own damage; a round through the gap between arm and body misses, a swing doesn't.


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 5, "normal")
	for id: int in sim.horde.zombies.keys():
		sim.horde.zombies.erase(id)
	return sim


func test_zone_names_and_old_callers() -> void:
	eq(SimWorld.hit_zone(true), "head", "true still means the head")
	eq(SimWorld.hit_zone(false), "torso", "false still means the body")
	eq(SimWorld.hit_zone("leg"), "leg", "zones pass through")
	eq(SimWorld.hit_zone("tail"), "torso", "anything unknown counts as the body")


func test_each_zone_does_its_own_damage() -> void:
	var sim := _sim()
	var lost := {}
	for zone: String in ["head", "torso", "arm", "leg"]:
		var z := sim.horde.spawn("brute", Vector3(0, 0, -5))  # plenty of health, so no hit kills
		var before := z.hp
		sim.hit_zombie(z.id, zone)
		lost[zone] = before - z.hp
	var base: float = lost["torso"]
	check(base > 0.0, "a body hit hurts")
	near(float(lost["arm"]) / base, float(sim.data.hit_zones["damage"]["arm"]), "an arm hit does the arm share", 0.01)
	near(float(lost["leg"]) / base, float(sim.data.hit_zones["damage"]["leg"]), "a leg hit does the leg share", 0.01)
	check(float(lost["head"]) > base * 1.5, "the head is still the place to hit")


func test_a_leg_hit_makes_it_limp() -> void:
	var sim := _sim()
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	z.state = ZombieBrain.State.CHASE
	var full := z.move_speed()
	sim.hit_zombie(z.id, "leg")
	check(z.limp > 0.0, "the leg hit gives a limp")
	check(z.move_speed() < full * 0.8, "it chases slower while it limps (%.2f vs %.2f)" % [z.move_speed(), full])
	for i in int((float(sim.data.hit_zones["limp_time"]) + 0.2) / SimWorld.TICK):
		z.limp = maxf(0.0, z.limp - SimWorld.TICK)
	near(z.move_speed(), full, "and walks it off")


func test_bolts_find_the_zone_where_they_land() -> void:
	var sim := _sim()
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -5))
	eq(sim.zone_at(z, z.pos + Vector3(0, 1.6, 0)), "head", "high on the body is the head")
	eq(sim.zone_at(z, z.pos + Vector3(0, 1.1, 0)), "torso", "the middle is the body")
	eq(sim.zone_at(z, z.pos + Vector3(0, 0.4, 0)), "leg", "low is the legs")
	var c := sim.horde.spawn("crawler", Vector3(0, 0, -5))
	c.facing = Vector3(0, 0, 1)
	eq(sim.zone_at(c, c.pos + Vector3(0, 0.3, 0.7)), "head", "a crawler's head is the front of its body")
	eq(sim.zone_at(c, c.pos + Vector3(0, 0.3, -0.4)), "torso", "the rest of a crawler is body, however low")


func _body(type: String) -> ZombieBody:
	var data := GameData.load_default()
	var brain := ZombieBrain.new(41, type, data.zombies[type], Vector3.ZERO, 1)
	brain.facing = Vector3(0, 0, 1)  # facing the rays below, which come from +Z
	var body := ZombieBody.new()
	tree.root.add_child(body)
	body.setup(brain, null)
	body.set_physics_process(false)  # stand still; the animation keeps playing
	body._animate(0.016)  # its own animation (a crawler crawls)
	body._set_hitboxes(true)
	return body


func _zone_centre(body: ZombieBody, bone: String) -> Vector3:
	var attach := body._model.find_child("Hit_" + bone.replace(".", "_"), true, false) as Node3D
	var cs := attach.get_child(0).get_child(0) as CollisionShape3D
	return cs.global_position


func test_zones_ride_the_bones() -> void:
	var body := _body("shambler")
	for i in 4:
		await tree.physics_frame
	check(body.hitboxes_on(), "a near zombie has its zones on")
	eq(body._hit_shapes.size(), ZombieHitboxes.ZONES.size(), "a zone on every bone")
	var head := _zone_centre(body, "Head")
	var foot := _zone_centre(body, "Foot.L")
	check(head.y > 1.35 and head.y < 1.9, "the head zone is at head height (%.2f m)" % head.y)
	check(foot.y < 0.3, "a foot zone is at the floor (%.2f m)" % foot.y)
	var before := head
	body._anim.play("Punch")
	body._anim.seek(0.4, true)
	for i in 3:
		await tree.physics_frame
	check(_zone_centre(body, "Hand.R").distance_to(before) > 0.0 and _zone_centre(body, "Head").distance_to(before) > 0.005,
			"the zones move with the animation")
	body.queue_free()
	await tree.process_frame


func test_a_ray_lands_in_the_zone_it_meets() -> void:
	var body := _body("shambler")
	for i in 4:
		await tree.physics_frame
	var space := body.get_world_3d().direct_space_state
	var none: Array[RID] = []
	for bone: String in ["Head", "Chest", "UpperLeg.L", "LowerArm.R"]:
		var at := _zone_centre(body, bone)
		var hit := ZombieHitboxes.cast(space, at + Vector3(0, 0, 3), at + Vector3(0, 0, -3), none)
		check(not hit.is_empty() and int(hit["zombie_id"]) == 41, "a shot at the %s meets the zombie" % bone)
		if not hit.is_empty():
			eq(hit["zone"], ZombieHitboxes.ZONES[bone], "and counts as its %s" % ZombieHitboxes.ZONES[bone])
	# Somewhere across the capsule at hip height there is a gap the body doesn't fill: a round flies on, a
	# swing still lands.
	var gap_found := false
	var y := 1.0
	for i in 40:
		var x := 0.02 + 0.0085 * i
		var a := Vector3(x, y, 3)
		var b := Vector3(x, y, -3)
		var capsule := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, Layers.ZOMBIE))
		if capsule.is_empty() or capsule["collider"] != body:
			continue
		var shot := ZombieHitboxes.cast(space, a, b, none)
		if shot.is_empty() or int(shot["zombie_id"]) != 41:
			gap_found = true
			var swing := ZombieHitboxes.cast(space, a, b, none, true)
			check(not swing.is_empty() and int(swing["zombie_id"]) == 41, "a swing through that gap still hits the body")
			break
	check(gap_found, "a round can pass between the zones inside the old capsule (a miss)")
	body._set_hitboxes(false)
	await tree.physics_frame
	var at := _zone_centre(body, "Head")
	var far := ZombieHitboxes.cast(space, Vector3(0, at.y, 3), Vector3(0, at.y, -3), none)
	check(not far.is_empty() and int(far["zombie_id"]) == 41 and far["zone"] == "head",
			"with its zones off (far away) the capsule and its head line still work")
	body.queue_free()
	await tree.process_frame


func test_a_crawler_is_hit_where_it_lies() -> void:
	var body := _body("crawler")
	for i in 40:  # past the 0.2 s blend into the crawl
		await tree.physics_frame
	var space := body.get_world_3d().direct_space_state
	var none: Array[RID] = []
	var head := _zone_centre(body, "Head")
	check(head.y < 0.6, "the crawler's head zone is down by the floor (%.2f m)" % head.y)
	var hit := ZombieHitboxes.cast(space, head + Vector3(0, 2, 0.01), head + Vector3(0, -1, 0.01), none)
	check(not hit.is_empty() and hit["zone"] == "head", "a shot down at its head is a headshot")
	body.queue_free()
	await tree.process_frame


func test_a_dead_zombie_has_no_live_zones() -> void:
	var body := _body("shambler")
	await tree.physics_frame
	body.brain.take_hit(1000.0, Vector3.ZERO, 0.0)
	body._physics_process(0.016)
	check(not body.hitboxes_on(), "dead: the zones are off (E searches the body as before)")
	body.queue_free()
	await tree.process_frame
