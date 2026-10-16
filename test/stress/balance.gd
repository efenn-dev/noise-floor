extends SceneTree
## F4 part 2: the factory-against-loot budget, numbers only. Loads the real game (scenes/main.tscn, like the soak)
## and prints a markdown report:
##   1. what every container in the world holds on average (each table's expected roll, with the difficulty's
##      abundance and its area's loot multiplier, as a search rolls it), for the parts the defense burns;
##   2. what a zombie's body gives on average (the "zombie" table): the one loot source that comes back;
##   3. what a reference defended base burns in one summer night, worked out from the data: gas for its lights,
##      fences and repair station (and the radio mast on the rescue night), nails for its turrets per zombie,
##      wall panels for repairs.
## Not a test_*.gd: run it with tools/balance.sh (one heavy job at a time on Emmitt's PC).

const MAIN := "res://scenes/main.tscn"
const WATCH := ["gas_can", "nails", "wall_panel", "metal_plate", "scrap_metal", "ammo_standard", "ammo_casing", "bolt"]
const SKIP_TABLES := ["zombie", "ground_pickup"]
## The reference base: what a player who follows "Defend your base" and adds the Sentry/Heavy defense pieces has.
const REF := {"nail_turret": 2, "floodlight": 2, "electric_fence": 6, "repair_station": 1}
const REPAIR_BUSY := 0.5  # share of the night the repair station has something to fix
const HIT_RATE := 0.8     # turret shots that land
const DAY_SECONDS := 1440.0  # the default day length (Settings: 24 minutes)


func _initialize() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	GameSession.save_path = "user://balance_save.json"  # never a real save
	change_scene_to_file(MAIN)
	_run()


func _run() -> void:
	while current_scene == null or not current_scene.get("sim"):
		await process_frame
	for i in 10:
		await process_frame
	var sim: SimWorld = current_scene.get("sim")
	var data := sim.data
	var abundance := sim.loot.difficulty.multiplier("loot_abundance") if sim.loot.difficulty != null else 1.0
	var total := {}
	var by_table := {}  # table -> [containers, {item: expected}]
	var n := 0
	for id: String in sim.loot.containers:
		var c: Dictionary = sim.loot.containers[id]
		if c["table"] in SKIP_TABLES or c["searched"]:
			continue
		n += 1
		var e := expected(data.loot[c["table"]], abundance * Loot.area_loot(data, c["pos"]))
		for item: String in c.get("extra", {}):
			e[item] = float(e.get(item, 0.0)) + float(c["extra"][item])
		if not by_table.has(c["table"]):
			by_table[c["table"]] = [0, {}]
		by_table[c["table"]][0] += 1
		for item: String in e:
			total[item] = float(total.get(item, 0.0)) + float(e[item])
			by_table[c["table"]][1][item] = float(by_table[c["table"]][1].get(item, 0.0)) + float(e[item])
	print("## World loot (expected, %d containers, difficulty x%.2f)\n" % [n, abundance])
	print("| part | whole world |")
	print("|---|---|")
	for item: String in WATCH:
		print("| %s | %.0f |" % [item, float(total.get(item, 0.0))])
	print("\n## Where the gas, nails and panels are\n")
	print("| table | containers | gas_can | nails | wall_panel |")
	print("|---|---|---|---|---|")
	var tables := by_table.keys()
	tables.sort_custom(func(a: String, b: String) -> bool: return float(by_table[a][1].get("nails", 0.0)) > float(by_table[b][1].get("nails", 0.0)))
	for t: String in tables:
		var e: Dictionary = by_table[t][1]
		if float(e.get("gas_can", 0.0)) + float(e.get("nails", 0.0)) + float(e.get("wall_panel", 0.0)) < 0.5:
			continue
		print("| %s | %d | %.1f | %.0f | %.1f |" % [t, by_table[t][0], float(e.get("gas_can", 0.0)), float(e.get("nails", 0.0)),
				float(e.get("wall_panel", 0.0))])
	var car_gas := 0.0
	for id: String in sim.vehicles.cars:
		car_gas += float(sim.vehicles.cars[id]["fuel"])
	print("
Gas in the cars' tanks (G siphons it): %.0f cans in %d cars." % [car_gas, sim.vehicles.cars.size()])
	var body := expected(data.loot["zombie"], abundance)
	print("\n## A zombie's body (expected)\n")
	print(", ".join(WATCH.filter(func(i: String) -> bool: return body.has(i)).map(func(i: String) -> String: return "%s %.2f" % [i, body[i]])))
	_night(sim, data)
	quit(0)


## A table's expected items for one search at `abundance`: mean rolls x each entry's chance x its mean count.
static func expected(table: Dictionary, abundance: float) -> Dictionary:
	var out := {}
	var entries: Array = table["items"]
	var weight := float(table.get("empty", 0.0))
	for e: Dictionary in entries:
		weight += float(e["weight"])
	var lo := maxi(1, roundi(float(table["rolls"][0]) * abundance))
	var hi := maxi(lo, roundi(float(table["rolls"][1]) * abundance))
	var rolls := (lo + hi) / 2.0
	for e: Dictionary in entries:
		out[e["item"]] = float(out.get(e["item"], 0.0)) + rolls * float(e["weight"]) / weight * (float(e["min"]) + float(e["max"])) / 2.0
	return out


func _night(sim: SimWorld, data: GameData) -> void:
	var b: Dictionary = data.buildables
	var night_h := 24.0 - sim.clock.sunset_hour + sim.clock.sunrise_hour
	var sec_per_h := DAY_SECONDS / 24.0
	var can_ws := float(b["generator"]["watts_out"]) * float(b["generator"]["burn_time"])  # watt-seconds in a can
	var lights := float(REF["floodlight"]) * float(b["floodlight"]["watts"])
	var fences := float(REF["electric_fence"]) * float(b["electric_fence"]["watts"])
	var repair := float(REF["repair_station"]) * float(b["repair_station"]["watts"])
	var night_ws := (lights + fences + repair * REPAIR_BUSY) * night_h * sec_per_h
	var before_ws := lights * night_h * sec_per_h + (fences + repair) * 24.0 * sec_per_h  # fences and a stocked station all day
	var mast_ws := float(b["radio_mast"]["watts"]) * float(data.milestones["broadcast_hours"]) * sec_per_h
	print("\n## One summer night of the reference base (%s)\n" % ", ".join(REF.keys().map(func(k: String) -> String: return "%d %s" % [REF[k], k])))
	print("Night: %.0f game hours = %.0f real seconds at the default day length." % [night_h, night_h * sec_per_h])
	print("| draw | per night |")
	print("|---|---|")
	print("| gas cans, lights + fences + repair station (F4 part 2: fences armed at night, station only while mending) | %.1f |" % (night_ws / can_ws))
	print("| gas cans per game day under the old rules (fences and a stocked repair station on all day) | %.1f |" % (before_ws / can_ws))
	print("| extra gas cans on the rescue night (the mast, %d powered hours) | %.1f |" % [int(data.milestones["broadcast_hours"]), mast_ws / can_ws])
	var z: Dictionary = data.zombies
	var dmg := float(b["nail_turret"]["damage"])
	for kind: String in ["shambler", "runner", "brute"]:
		var shots := ceilf(float(z[kind]["hp"]) / dmg) / HIT_RATE
		print("| nails to kill one %s with a nail turret (%.0f%% hits) | %.1f |" % [kind, HIT_RATE * 100.0, shots])
	var d: Dictionary = data.noise["director"]
	print("| zombies in a full horde from a quiet / the loudest base | %d / %d |" % [int(d["horde"]), roundi(float(d["horde"]) * float(d["loud_wave_max"]))])
	var rs: Dictionary = data.defense["repair_station"]
	print("| wall panels to mend one wall from nothing (%d hp, %d hp a panel) | %.0f |" % [int(b["wall"]["hp"]), int(rs["hp_per_panel"]),
			ceilf(float(b["wall"]["hp"]) / float(rs["hp_per_panel"]))])
	print("\nThe factory side: a fuel pump makes a gas can every %.0f s (a night's worth in %.0f s); a Press makes %d nails from a plate every %.0f s; a smelter a plate from scrap every %.0f s; a salvager scrap every %.0f s." % [
			float(data.recipes["pump_fuel"]["time"]), float(data.recipes["pump_fuel"]["time"]) * night_ws / can_ws,
			int(data.recipes["press_nails"]["out"]["nails"]), float(data.recipes["press_nails"]["time"]),
			float(data.recipes["smelt_plate"]["time"]), float(data.recipes["salvage_scrap"]["time"])])
