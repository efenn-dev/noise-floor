extends "res://test/base_test.gd"
## Hunger, thirst, energy, stamina, bleeding and sleep.

const TICK := SimWorld.TICK


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func test_meters_drain_over_time() -> void:
	var sim := _sim()
	_run(sim, 100.0)
	near(sim.player.food, 100.0 - 3.5, "food: 0.035 a second", 0.01)
	near(sim.player.water, 100.0 - 7.0, "water drains twice as fast", 0.01)
	near(sim.player.energy, 100.0 - 5.0, "energy: 0.05 a second", 0.01)
	near(sim.player.health, 100.0, "no damage while fed")


func test_starving_hurts_and_eating_fixes_it() -> void:
	var sim := _sim()
	sim.player.food = 0.0
	_run(sim, 10.0)
	near(sim.player.health, 100.0 - 2.5, "empty stomach: 0.25 health a second", 0.01)
	eq(sim.eat_best(), "Nothing to eat", "nothing in pockets")
	sim.inventory.give_all({"chips": 1, "canned_food": 1, "plank": 3})
	eq(sim.eat_best(), "Ate Canned food", "picks the most filling food")
	near(sim.player.food, 40.0, "canned food: +40", 0.1)
	sim.player.food = 95.0
	sim.eat_best()
	near(sim.player.food, 100.0, "meters stop at 100")
	eq(sim.inventory.count("plank"), 3, "doesn't eat planks")


func test_drinking() -> void:
	var sim := _sim()
	sim.player.water = 20.0
	sim.inventory.give_all({"soda": 1, "clean_water": 1, "dirty_water": 2})
	eq(sim.drink_best(), "Drank Clean water", "clean water first")
	near(sim.player.water, 60.0, "+40", 0.1)
	eq(sim.drink_best(), "Drank Soda", "then soda")
	eq(sim.drink_best(), "Nothing to drink", "rainwater has to be purified first")


func test_stamina_sprint_and_swing() -> void:
	var sim := _sim()
	sim.player.sprinting = true
	_run(sim, 4.0)
	near(sim.player.stamina, 100.0 - 60.0, "sprinting: 15 a second", 0.1)
	_run(sim, 2.6)
	check(not sim.player.can_sprint(), "out of breath after 6.6 s")
	sim.player.sprinting = false
	_run(sim, 0.9)
	near(sim.player.stamina, 1.0, "no recovery for the first second", 0.2)
	_run(sim, 2.1)
	check(sim.player.stamina > 10.0, "then 12 a second (%.1f)" % sim.player.stamina)
	sim.player.stamina = 20.0
	check(sim.player.try_swing(0.0), "a swing costs 12")
	check(not sim.player.try_swing(0.0), "too tired for another with 8 left")


func test_bites_cause_bleeding_and_bandages_stop_it() -> void:
	var sim := _sim()
	sim.player_pos = Vector3(0, 0, -1)
	var z := sim.horde.spawn("shambler", Vector3.ZERO)
	z.los_clear = true
	var bled := false
	for i in 6:
		_run(sim, 1.2)
		bled = bled or sim.player.bleeding
		sim.player.health = 100.0  # keep the test about bleeding, not dying
	check(bled, "6 bites at 30% bleed chance: bled at least once (seeded)")
	sim.horde.zombies.clear()
	sim.player.bleeding = true
	var hp := sim.player.health
	_run(sim, 10.0)
	near(sim.player.health, hp - 5.0, "bleeding: 0.5 health a second", 0.05)
	eq(sim.use_bandage(), "No bandages", "need a bandage")
	sim.inventory.add("bandage", 1)
	eq(sim.use_bandage(), "Bandaged", "bandage it")
	check(not sim.player.bleeding, "bleeding stopped")
	eq(sim.use_bandage(), "Not bleeding", "nothing to bandage now")


func test_bed_sleep_and_respawn() -> void:
	var sim := _sim()
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(5, 5), 0, sim.inventory)
	eq(sim.build.place("bed", Vector2i(5, 5), 0, sim.inventory), "", "build a bed")
	var bed := sim.build.key_for("bed", Vector2i(5, 5))
	eq(sim.sleep_in(bed), "Not tired. You'll wake up here if you die", "full energy: no sleep, but sets respawn")
	check(Vector2(sim.spawn_point.x, sim.spawn_point.z).distance_to(Vector2(11 + 1.2, 11)) < 0.01, "respawn point is by the bed")
	sim.player.energy = 40.0
	sim.player.bleeding = true
	eq(sim.sleep_in(bed), "You're bleeding. Bandage first (H)", "Q5: bleeding: no sleep (it would wake you at once)")
	check(not sim.player.asleep, "still awake while bleeding")
	sim.player.bleeding = false
	eq(sim.sleep_in(bed), "", "tired: sleep")
	check(sim.player.asleep, "asleep")
	_run(sim, 100.0)
	near(sim.player.energy, 40.0 + 21.0, "sleep restores 0.21 a second", 0.1)
	sim.player.damage(5)
	check(not sim.player.asleep, "getting hurt wakes you")
	sim.player.sleep()
	sim.player.energy = 99.0
	_run(sim, 5.0)
	check(not sim.player.asleep, "you wake up rested")
	sim.player.damage(1000)
	_run(sim, PlayerStats.RESPAWN_TIME + 0.1)
	check(sim.player_pos.distance_to(sim.spawn_point) < 0.01, "died and woke up at the bed")


func test_respawn_tops_up_needs() -> void:
	var sim := _sim()
	sim.player.food = 5.0
	sim.player.water = 70.0
	sim.player.bleeding = true
	sim.player.damage(1000)
	_run(sim, PlayerStats.RESPAWN_TIME + 0.1)
	near(sim.player.food, 50.0, "food back to at least 50", 0.1)
	check(sim.player.water > 65.0, "water kept when higher")
	check(not sim.player.bleeding, "no longer bleeding")
