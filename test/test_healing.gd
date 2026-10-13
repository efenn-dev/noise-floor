extends "res://test/base_test.gd"
## Natural healing: health comes back slowly while fed, watered, not bleeding and not cold; faster asleep;
## First Aid speeds it up.

const TICK := SimWorld.TICK


func _stats() -> PlayerStats:
	var data := GameData.load_default()
	var p := PlayerStats.new()
	p.cfg = data.survival
	return p


func _run(p: PlayerStats, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		p.tick(TICK)


func test_heals_slowly_while_fed_and_watered() -> void:
	var p := _stats()
	p.health = 50.0
	check(p.is_healing(), "healing when hurt, fed and watered")
	_run(p, 10.0)
	near(p.health, 50.0 + 10.0 * p._c("heal_rate"), "heal_rate per second awake", 0.01)


func test_heals_faster_asleep() -> void:
	var p := _stats()
	p.health = 50.0
	p.energy = 10.0
	p.sleep()
	_run(p, 10.0)
	check(p.asleep, "still asleep")
	near(p.health, 50.0 + 10.0 * p._c("heal_sleep_rate"), "heal_sleep_rate per second asleep", 0.01)
	check(p._c("heal_sleep_rate") > p._c("heal_rate") * 2.0, "sleep heals much faster")


func test_stops_at_max_health() -> void:
	var p := _stats()
	p.health = p.max_health - 0.01
	_run(p, 5.0)
	eq(p.health, p.max_health, "capped at max")
	check(not p.is_healing(), "not healing when full")


func test_no_healing_when_hungry_thirsty_bleeding_or_cold() -> void:
	var p := _stats()
	var floor_value := p._c("heal_min")
	p.health = 50.0
	p.food = floor_value - 1.0
	check(not p.is_healing(), "hungry: no healing")
	_run(p, 5.0)
	check(p.health <= 50.0, "health didn't rise while hungry")
	p = _stats()
	p.health = 50.0
	p.water = floor_value - 1.0
	check(not p.is_healing(), "thirsty: no healing")
	p = _stats()
	p.health = 50.0
	p.bleeding = true
	_run(p, 2.0)
	check(p.health < 50.0, "bleeding still hurts, no healing")
	p = _stats()
	p.cold_cfg = GameData.load_default().seasons["warmth"]
	p.health = 50.0
	p.warmth = float(p.cold_cfg["cold_at"]) - 1.0
	check(not p.is_healing(), "cold: no healing")
	p.dead = true
	p.warmth = 100.0
	check(not p.is_healing(), "dead: no healing")


func test_first_aid_speeds_healing() -> void:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.player.health = 50.0
	sim.step()
	near(sim.player.heal_mult, 1.0, "no First Aid: x1")
	sim.skills.xp["first_aid"] = float(sim.data.skills["levels"][5])
	sim.step()
	near(sim.player.heal_mult, 1.5, "First Aid 5: x1.5")
	var before := sim.player.health
	sim.step()
	near(sim.player.health - before, sim.player._c("heal_rate") * 1.5 * TICK, "heals 50% faster", 0.0001)
