extends "res://test/base_test.gd"
## V15: ADS is a sim accuracy state with measured presentation poses; blocking/parrying resolves in the sim.


func _gun(base: String = "pistol") -> SimWorld:
	var sim := SimWorld.new(12.0)
	var gun := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(gun)
	sim.equip_gear(gun["uid"])
	sim.swap_hands()
	sim.guns.raising = 0.0
	return sim


func _scope(sim: SimWorld) -> void:
	var scope := sim.gear.make("scope", "civilian", "white")
	sim.gear.pieces.append(scope)
	sim.attach_part(scope["uid"])


func _melee(base: String = "pipe") -> SimWorld:
	var sim := SimWorld.new(12.0)
	if base == "fists":
		sim.gear.unequip("weapon")
	elif base != "pipe":
		var piece := sim.gear.make(base, "civilian", "white")
		sim.gear.pieces.append(piece)
		sim.gear.equip(piece["uid"])
	return sim


func _front_zombie(sim: SimWorld) -> ZombieBrain:
	sim.player_pos = Vector3.ZERO
	sim.player_facing = Vector3(0, 0, -1)
	return sim.horde.spawn("shambler", Vector3(0, 0, -1.5))


func _raise_guard(sim: SimWorld, age: float = 0.3) -> void:
	sim.player.set_blocking(true)
	sim.player.block_time = age


func test_ads_tightens_spread_and_scope_still_adds_its_bonus() -> void:
	var sim := _gun()
	var hip := sim.guns.spread_deg()
	sim.guns.aiming = true
	var ads := sim.guns.spread_deg()
	near(ads, hip * float(sim.data.guns["guns"]["pistol"]["ads_spread"]), "pistol ADS uses its data multiplier")
	_scope(sim)
	var scoped := sim.guns.spread_deg()
	near(scoped, ads / 1.6, "the scope's +60 percent range still tightens aimed spread")
	check(scoped < ads and ads < hip, "scope ADS is tighter than iron ADS, which is tighter than hip fire")


func test_every_gun_sight_line_meets_the_camera_centre() -> void:
	for gun_id: String in Shooter.HOLD:
		var pose: Dictionary = Shooter.aim_pose(gun_id)
		var position: Vector3 = pose["position"]
		var rotation: Vector3 = pose["rotation"]
		var basis := Basis.from_euler(rotation)
		var points: Dictionary = Shooter.SIGHT_POINTS[gun_id]
		var rear := position + basis * (points["rear"] as Vector3)
		var front := position + basis * (points["front"] as Vector3)
		check(position.distance_to(Shooter.HOLD[gun_id] as Vector3) > 0.05, "%s ADS pose differs from hip" % gun_id)
		near(rear.x, 0.0, "%s rear sight centres horizontally" % gun_id, 0.003)
		near(rear.y, 0.0, "%s rear sight centres vertically" % gun_id, 0.003)
		near(front.x, 0.0, "%s front sight centres horizontally" % gun_id, 0.003)
		near(front.y, 0.0, "%s front sight centres vertically" % gun_id, 0.003)
		check(front.z < rear.z, "%s front sight remains ahead of the rear sight" % gun_id)


func test_aiming_slows_walking_and_sprint_cancels_it() -> void:
	var sim := _gun()
	var shooter := Shooter.new()
	var builder := BuildController.new()
	shooter.sim = sim
	shooter.builder = builder
	shooter.hold_aim = true
	check(shooter.aiming(), "a raised gun can aim")
	sim.player.aiming = shooter.aiming()
	near(sim.player.speed_multiplier(), PlayerStats.AIM_SPEED_MULT, "aiming slows walking")
	shooter.sprinting = true
	check(not shooter.aiming(), "requesting sprint cancels aim")
	sim.player.aiming = shooter.aiming()
	near(sim.player.speed_multiplier(), 1.0, "sprint cancellation restores normal walking multiplier")
	shooter.free()
	builder.free()


func test_reload_and_inspect_drop_aim() -> void:
	var sim := _gun()
	sim.guns.aiming = true
	var gun: Dictionary = sim.gear.gun()
	gun["loaded"] = 0
	sim.inventory.add(String(gun["ammo"]), 1)
	sim.reload()
	check(not sim.guns.aiming, "starting a reload clears the sim aim flag")
	sim.guns.reloading = 0.0
	var shooter := Shooter.new()
	var builder := BuildController.new()
	shooter.sim = sim
	shooter.builder = builder
	shooter.hold_aim = true
	check(shooter.aiming(), "aim can come back after reload")
	sim.guns.aiming = true
	check(shooter.start_inspect(), "inspection can replace aim")
	check(not shooter.aiming() and not sim.guns.aiming, "inspection immediately drops world and sim aim")
	shooter.free()
	builder.free()


func test_front_blocks_use_each_class_reduction() -> void:
	var expected := {"pipe": 0.7, "axe": 0.7, "machete": 0.5, "fists": 0.3}
	for weapon: String in expected:
		var sim := _melee(weapon)
		var z := _front_zombie(sim)
		_raise_guard(sim)
		var before := sim.player.health
		var result: Dictionary = sim.zombie_hit_player(z)
		var full := float(z.stats["damage"])
		check(result["blocked"] and not result["parried"], "%s catches a frontal hit" % weapon)
		near(before - sim.player.health, full * (1.0 - float(expected[weapon])), "%s class reduction" % weapon)


func test_block_costs_stamina_wears_weapon_and_makes_noise() -> void:
	var sim := _melee("pipe")
	var z := _front_zombie(sim)
	_raise_guard(sim)
	var stamina := sim.player.stamina
	var condition := float(sim.gear.equipped["weapon"]["condition"])
	var result: Dictionary = sim.zombie_hit_player(z)
	check(result["blocked"], "the pipe blocks")
	near(stamina - sim.player.stamina, float(sim.weapon_stats()["block_stamina"]), "blocking costs the pipe's stamina value")
	check(float(sim.gear.equipped["weapon"]["condition"]) < condition, "blocking wears the pipe")
	near(float(sim.data.noise["sounds"]["block"]), 40.0, "block noise is data-driven")
	sim.noise.refresh(sim.factory, SimWorld.TICK, sim.power, sim.vehicles)
	check(sim.noise.recent.any(func(event: Dictionary) -> bool: return event["kind"] == "block"),
			"a successful guard emits block noise")
	check(SoundView.EVENTS.has("block"), "SoundView maps block noise to an existing thud")


func test_a_hit_from_behind_is_not_blocked() -> void:
	var sim := _melee()
	sim.player_pos = Vector3.ZERO
	sim.player_facing = Vector3(0, 0, -1)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, 1.5))
	_raise_guard(sim)
	var stamina := sim.player.stamina
	var result: Dictionary = sim.zombie_hit_player(z)
	check(not result["blocked"], "a rear hit passes the guard")
	near(100.0 - sim.player.health, float(z.stats["damage"]), "the rear hit deals full damage")
	near(sim.player.stamina, stamina, "a missed guard costs no stamina")


func test_parry_stops_damage_and_staggers_the_zombie() -> void:
	var sim := _melee("axe")
	var z := _front_zombie(sim)
	_raise_guard(sim, 0.1)
	var result: Dictionary = sim.zombie_hit_player(z)
	check(result["parried"], "a guard raised inside 0.25 seconds parries")
	near(sim.player.health, 100.0, "a parry stops all damage")
	check(z.stunned >= SimWorld.PARRY_STUN, "the parry stuns the zombie")
	check(z.knockback.length() >= SimWorld.PARRY_KNOCKBACK - 0.01, "the parry knocks the zombie back")


func test_no_stamina_means_no_block() -> void:
	var sim := _melee()
	var z := _front_zombie(sim)
	_raise_guard(sim)
	sim.player.stamina = 0.0
	var result: Dictionary = sim.zombie_hit_player(z)
	check(not result["blocked"] and not result["parried"], "an empty stamina bar cannot block or parry")
	near(100.0 - sim.player.health, float(z.stats["damage"]), "the hit deals full damage")


func test_cannot_attack_while_blocking() -> void:
	var sim := _melee()
	_raise_guard(sim)
	var stamina := sim.player.stamina
	near(sim.player.speed_multiplier(), PlayerStats.BLOCK_SPEED_MULT, "blocking slows walking")
	check(not sim.swing(), "the sim rejects an attack while blocking")
	near(sim.player.stamina, stamina, "the rejected attack spends no stamina")


func test_block_can_break_the_melee_weapon() -> void:
	var sim := _melee("pipe")
	var z := _front_zombie(sim)
	sim.gear.equipped["weapon"]["condition"] = 0.004
	_raise_guard(sim)
	sim.zombie_hit_player(z)
	check(not sim.gear.equipped.has("weapon"), "a worn weapon follows the existing break-to-fists path")
