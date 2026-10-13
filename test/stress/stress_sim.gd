extends SceneTree
## Headless stress test (numbers only): how expensive one sim tick is with many zombies and machines.
## Not a test_*.gd, so tools/test.sh never runs it. Run it with tools/stress.sh.
## Builds a SimWorld with the W1a town, power.free, 50 machines (smelters and presses on foundations,
## topped up by hand so they never stop) and N shamblers on the main street, steps it for one game-day
## (shrunk to 4 game hours if a day would take more than ~90 s of wall time), then times single calls
## of the main per-tick costs on the end state. Three runs: town + 200, no town + 200, town + 20.
## Note: zombies don't move in a sim-only run (their world bodies move them), so navmesh, physics and
## drawing are NOT in these numbers; this is the rules tick alone.

const TICK := SimWorld.TICK
const START_HOUR := 19.0  # so a shrunk run still crosses sunset (night hearing, night waves)
const MACHINES := 50
const FEED_EVERY := 200  # ticks (10 s); a full input (20) lasts 40 s, outputs fill in ~26 s
const SHRUNK_HOURS := 4.0
const WALL_BUDGET_S := 90.0
const PROBE_TICKS := 1200  # one game hour at default speed: used to decide whether to shrink

var _ticks_total := -1
var _shrunk := false


func _initialize() -> void:
	var rows := []
	rows.append(_run("town + 200 zombies", true, 200))
	rows.append(_run("empty map + 200 zombies", false, 200))
	rows.append(_run("town + 20 zombies", true, 20))
	print("\n=== Noise Floor stress report ===")
	print("ticks per run: %d (%s game time from %02d:00, TICK = 1/%d s)%s" % [_ticks_total,
			"%.0f h" % (_ticks_total * TICK / 60.0) if _shrunk else "one day", int(START_HOUR), SimWorld.TICK_RATE,
			"  -- SHRUNK: a full day would take more than %.0f s of wall time" % WALL_BUDGET_S if _shrunk else ""])
	print("| run | town pieces | zombies start/end alive | waves | wall s | tick avg ms | tick worst ms | loudest_heard us | gain_now us (cached) | gain_now us (recount) | horde.tick us | factory.tick us | noise.refresh us | static MB before/after |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r: Dictionary in rows:
		print("| %s | %d | %d / %d | %d | %.1f | %.3f | %.2f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f / %.1f |" % [r["name"],
				r["pieces"], r["zombies"], r["alive"], r["waves"], r["wall_s"], r["avg_ms"], r["worst_ms"],
				r["heard_us"], r["gain_us"], r["gain_cold_us"], r["horde_us"], r["factory_us"], r["refresh_us"], r["mem0"], r["mem1"]])
	quit(0)


func _run(name: String, with_town: bool, zombie_count: int) -> Dictionary:
	var mem0 := OS.get_static_memory_usage() / 1048576.0
	var sim := SimWorld.new(START_HOUR)
	sim.power.free = true
	var pieces := 0
	if with_town:
		pieces = sim.place_town(TownPlan.generate(sim.seed_value))
	for item: String in sim.data.items:
		sim.inventory.add(item, 100000)
	var placed := 0
	for i in MACHINES:
		var cell := Vector2i(-5 + i % 10, 5 + i / 10)  # 10 x 5 block just south of the town, near spawn
		var id := "smelter" if i % 2 == 0 else "press"
		var err := sim.build.place("foundation", cell, BuildGrid.Side.NORTH, sim.inventory)
		if err == "":
			err = sim.build.place(id, cell, BuildGrid.Side.EAST, sim.inventory)
		if err != "":
			push_error("stress: could not place %s at %s: %s" % [id, cell, err])
			continue
		placed += 1
	sim.player_pos = Vector3(0, 0, 500)  # far away and out of sight: the run is about noise, not chasing
	sim.horde.spawn_town(zombie_count)
	_feed(sim)
	var day_ticks := roundi(sim.clock.seconds_per_day / TICK)
	if _ticks_total < 0:
		_ticks_total = day_ticks
	var total := 0
	var worst := 0
	var min_sources := 1 << 30
	var t_run := Time.get_ticks_usec()
	var i := 0
	while i < _ticks_total:
		if i % FEED_EVERY == 0:
			_feed(sim)
			if i > 0:
				min_sources = mini(min_sources, sim.noise.continuous.size())
		var t0 := Time.get_ticks_usec()
		sim.step()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		i += 1
		if i == PROBE_TICKS and not _shrunk and _ticks_total == day_ticks:
			var projected := float(Time.get_ticks_usec() - t_run) / 1e6 * day_ticks / PROBE_TICKS
			if projected > WALL_BUDGET_S:
				_shrunk = true
				_ticks_total = roundi(SHRUNK_HOURS / GameClock.HOURS_PER_DAY * sim.clock.seconds_per_day / TICK)
				print("stress: a full day would take ~%.0f s of wall time; shrinking every run to %.0f game hours" % [projected, SHRUNK_HOURS])
	var wall_s := float(Time.get_ticks_usec() - t_run) / 1e6
	var r := {"name": name, "pieces": pieces, "zombies": zombie_count, "machines": placed,
			"avg_ms": total / 1000.0 / _ticks_total, "worst_ms": worst / 1000.0, "wall_s": wall_s,
			"alive": sim.horde.alive_count(), "waves": sim.stats.waves, "min_sources": min_sources}
	_probe_calls(sim, r)
	r["mem1"] = OS.get_static_memory_usage() / 1048576.0
	r["mem0"] = mem0
	print("stress: %s done: %d machines, sources min %d during the run / %d in the probes, %.1f s wall; other calls (us): power.tick %.1f, loot.tick %.1f, defense.tick %.1f" % [
			name, placed, min_sources, r["sources"], wall_s, r["power_us"], r["loot_us"], r["defense_us"]])
	return r


## Keeps every machine crafting: full input, empty output (outside the timed step).
func _feed(sim: SimWorld) -> void:
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		for item: String in m.recipe["in"]:
			m.input[item] = Factory.INPUT_CAP
		m.output.clear()


## Average microseconds of single calls on the end state of a run.
func _probe_calls(sim: SimWorld, r: Dictionary) -> void:
	var night := sim.clock.is_night()
	var alive := []
	for id: int in sim.horde.zombies:
		if not sim.horde.zombies[id].is_dead():
			alive.append(sim.horde.zombies[id])
	var calls := 0
	var t0 := Time.get_ticks_usec()
	while calls < 2000 and not alive.is_empty():
		for z: ZombieBrain in alive:
			sim.noise.loudest_heard(z.pos, z.hearing(night))
			calls += 1
	r["heard_us"] = float(Time.get_ticks_usec() - t0) / maxi(calls, 1)
	r["gain_us"] = _time(200, func() -> void: sim.director.gain_now(sim.noise, night))
	# M15: the Director caches each source's wall count; "recount" clears it first (the cost before M15).
	r["gain_cold_us"] = _time(20, func() -> void:
		sim.director._walls_cache.clear()
		sim.director.gain_now(sim.noise, night))
	_feed(sim)
	r["refresh_us"] = _time(1000, func() -> void: sim.noise.refresh(sim.factory, TICK, sim.power, sim.vehicles))
	_feed(sim)
	r["factory_us"] = _time(1000, func() -> void: sim.factory.tick(TICK))
	r["power_us"] = _time(1000, func() -> void: sim.power.tick(TICK, sim.clock.daylight()))
	r["loot_us"] = _time(1000, func() -> void: sim.loot.tick(TICK, sim.player_pos))
	r["defense_us"] = _time(1000, func() -> void: sim.defense.tick(TICK, sim.horde, sim.noise))
	var ctx := {"player_pos": sim.player_pos, "player_dead": sim.player.dead, "night": night,
			"player_lit": sim.player_lit, "pieces": sim.build.pieces, "noise": sim.noise}
	_feed(sim)
	sim.factory.tick(TICK)  # back to crafting, so the horde has machines to hear
	sim.noise.refresh(sim.factory, TICK, sim.power, sim.vehicles)
	r["sources"] = sim.noise.continuous.size()
	r["horde_us"] = _time(200, func() -> void: sim.horde.tick(TICK, ctx))


func _time(n: int, f: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	return float(Time.get_ticks_usec() - t0) / n
