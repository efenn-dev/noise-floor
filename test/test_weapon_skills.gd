extends "res://test/base_test.gd"
## V9 + V10 (Emmitt, 2026-10-13: "durability so we need to get a new weapon every so often" and "Zomboid-like
## skills where you level up your blunt, blades, axe, etc skills and do more damage/faster attacks").
## Weapons wear at their own rate and break at 0; Blunt, Blades and Axe replace Melee; Maintenance slows wear.


func _hold(sim: SimWorld, base: String, condition := 1.0) -> Dictionary:
	var p := sim.gear.make(base, "civilian", "white", {}, condition)
	sim.gear.pieces.append(p)
	eq(sim.gear.equip(p["uid"]), "", "hold a %s" % base)
	return p


func _set_level(sim: SimWorld, skill: String, lv: int) -> void:
	sim.skills.xp[skill] = float(sim.data.skills["levels"][lv])


func _said_part(sim: SimWorld, part: String) -> bool:
	return sim.messages.any(func(m: Dictionary) -> bool: return String(m["text"]).contains(part))


func _target(sim: SimWorld) -> ZombieBrain:
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1.5))
	z.hp = 100000.0
	return z


func test_each_weapon_trains_its_skill() -> void:
	var sim := SimWorld.new(10.0)
	for pair: Array in [["pipe", "blunt"], ["bat", "blunt"], ["machete", "blades"], ["knife", "blades"], ["axe", "axe"]]:
		_hold(sim, pair[0])
		eq(sim.weapon_skill(), pair[1], "a %s trains %s" % pair)
		var before := float(sim.skills.xp.get(pair[1], 0.0))
		sim.hit_zombie(_target(sim).id, false)
		check(float(sim.skills.xp[pair[1]]) > before, "a hit with the %s gives %s xp" % pair)
	sim.gear.unequip("weapon")
	eq(sim.weapon_skill(), "", "bare fists train no weapon skill")
	check(float(sim.skills.xp.get("maintenance", 0.0)) > 0.0, "every hit trains Maintenance a little")


func test_skill_means_more_damage_and_quicker_swings() -> void:
	var sim := SimWorld.new(10.0)
	_hold(sim, "machete")
	var dmg0 := sim.melee_damage()
	var cd0 := sim.swing_cooldown()
	near(cd0, float(sim.data.weapons["machete"]["cooldown"]), "untrained: the machete's own swing time")
	_set_level(sim, "blades", 5)
	near(sim.melee_damage(), dmg0 * 1.30, "Blades 5: +30% damage")
	near(sim.swing_cooldown(), cd0 * 0.80, "and swings 20% quicker")
	_set_level(sim, "axe", 10)
	near(sim.melee_damage(), dmg0 * 1.30, "Axe skill does nothing for a machete")
	_set_level(sim, "blades", 10)
	check(sim.swing_cooldown() >= cd0 * 0.5 - 0.001, "never quicker than half")


func test_weapons_wear_at_their_own_rate() -> void:
	var sim := SimWorld.new(10.0)
	var knife := _hold(sim, "knife")
	sim.hit_zombie(_target(sim).id, false)
	var pipe := _hold(sim, "pipe")
	sim.hit_zombie(_target(sim).id, false)
	check(1.0 - float(knife["condition"]) > 2.0 * (1.0 - float(pipe["condition"])), "a knife wears much faster than a pipe")
	var fresh := SimWorld.new(10.0)
	var a := _hold(fresh, "bat")
	_set_level(fresh, "maintenance", 5)
	fresh.hit_zombie(_target(fresh).id, false)
	near(1.0 - float(a["condition"]), float(fresh.data.weapons["bat"]["wear"]) * (1.0 - 0.35), "Maintenance 5: 35% less wear")


func test_a_worn_weapon_warns_then_breaks() -> void:
	var sim := SimWorld.new(10.0)
	var bat := _hold(sim, "bat", float(sim.data.gear["broken_below"]) + 0.005)
	sim.hit_zombie(_target(sim).id, false)
	check(_said_part(sim, "worn out"), "dropping below the line warns you it'll break soon")
	bat["condition"] = 0.004
	sim.messages.clear()
	var xp := float(sim.skills.xp.get("blunt", 0.0))
	sim.hit_zombie(_target(sim).id, false)
	check(not sim.gear.equipped.has("weapon"), "at 0 the bat is gone")
	check(_said_part(sim, "broke"), "and you're told")
	sim.step()  # one-off sounds join the noise field on the next tick
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "weapon_break"), "it snaps loudly")
	eq(sim.gear.weapon_name(), "Fists", "back to fists")
	check(float(sim.skills.xp["blunt"]) > xp, "the hit that broke it still trained Blunt")


func test_the_knife_is_loot() -> void:
	var sim := SimWorld.new(10.0)
	check(sim.data.gear["bases"].has("knife"), "a knife base")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := false
	for i in 600:
		if sim.gear.roll_piece(rng, "kitchen")["base"] == "knife":
			seen = true
			break
	check(seen, "knives turn up in loot")
	eq(sim.data.validate(), PackedStringArray(), "the data still validates")


func test_repair_trains_maintenance() -> void:
	var sim := SimWorld.new(10.0)
	var p := _hold(sim, "axe", 0.5)
	sim.inventory.add("repair_kit", 1)
	check(sim.repair_gear(p["uid"]).begins_with("Repaired"), "repaired")
	near(float(sim.skills.xp["maintenance"]), float(sim.data.skills["skills"]["maintenance"]["xp"]["repair"]), "Maintenance xp for a repair")


## test/fixtures/save_v13.json was written by the code before V10 (a "melee" skill with 300 xp, a pipe at 60%).
func test_version_13_melee_xp_carries_over() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v13.json")
	eq(int(d.get("version", 0)), 13, "the fixture is a version-13 save")
	check(d["skills"].has("melee"), "it has the old Melee skill")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	for s: String in ["blunt", "blades", "axe"]:
		near(float(sim.skills.xp.get(s, 0.0)), 300.0, "%s gets the Melee xp" % s)
	check(not sim.skills.xp.has("melee"), "no leftover Melee")
	var again := SaveGame.to_dict(sim)
	eq(int(again["version"]), SaveGame.VERSION, "saves as the current version")
	eq(SaveGame.VERSION, 17, "save version 17: V17 window shards (16), V18 container contents (17)")
