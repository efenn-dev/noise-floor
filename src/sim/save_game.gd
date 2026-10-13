class_name SaveGame
extends RefCounted
## Turns a SimWorld into plain JSON-safe data and back. What's saved: the clock, your pockets and
## body, everything you built (with hp, door state, trap wear), machine buffers and progress, items
## on belts, turret ammo, crate contents, generator fuel, zombies (where they are and how hurt, not
## what they were thinking), the Director's heat, which containers are searched, gas left in cars,
## death bags, the cars (where they're parked, fuel, damage), and the world seed. The world (town, containers, cars) is rebuilt from code, then
## this is laid over it.

## 2 = M11 (stats, infamy, fresh/stale gas). 3 = W1a: the town's houses are build pieces, saved with
## everything else (damage, open doors, broken windows, walls you knocked down).
## Older saves still load: anything they lack gets its default, and a save from before 3 gets the
## houses laid fresh by the town plan (see holds_town). 4 = W1b: the factory is a hall of pieces too;
## a save from before 4 gets it laid fresh (see holds_factory). House zombies are ordinary saved zombies.
## 5 = M12: perks and unspent perk points (skills xp was already saved). A save from before 5 gets no
## perks and the perk points its skill levels are worth.
## 6 = M13: gear (pieces in your pockets, what you wear, each with its rolls and condition), gear in
## bags, and which recipe a Press is set to. A save from before 6 gets the starting pipe (white, mint,
## in the weapon slot) and Old Pete in the factory hall.
## 7 = W1c: furniture (counters, tables, couches, shelves, bathtubs, toilets) is pieces, saved with the rest.
## A save from before 7 gets the furniture laid by the town plan after it's applied (see holds_props).
## 8 = M14: guns. A gun piece also holds its parts, rounds loaded and ammo type (all inside "gear"), and
## "hands" says whether the gun or the melee weapon was in your hands. A save from before 8 has an empty gun slot.
const VERSION := 8
const FIRST_WITH_GEAR := 6
const FIRST_WITH_PROPS := 7
const FIRST_WITH_TOWN := 3
const FIRST_WITH_FACTORY := 4


## True if the save already holds the town's houses as pieces, so the world must not lay them again.
static func holds_town(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_TOWN


## True if the save already holds the factory hall's pieces (W1b).
static func holds_factory(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_FACTORY


## True if the save already holds the town's furniture pieces (W1c), so the world must not lay them again.
## Unlike the houses, furniture for an older save is laid after the save is applied (SimWorld.place_props
## skips cells you built on), so it can't land on top of your own pieces.
static func holds_props(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_PROPS


static func to_dict(sim: SimWorld) -> Dictionary:
	var pieces := []
	for key: String in sim.build.pieces:
		var p: Dictionary = sim.build.pieces[key]
		pieces.append({"key": key, "id": p["id"], "cell": _v2(p["cell"]), "side": p["side"], "hp": p["hp"],
				"open": p.get("open", false), "wear": p.get("wear", 0.0)})
	var machines := []
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		machines.append({"cell": _v2(cell), "input": m.input, "output": m.output, "progress": m.progress,
				"crafting": m.crafting, "crafted": m.crafted, "muffled": m.muffled, "time_scale": m.time_scale,
				"recipe": m.recipe_id})
	var belts := []
	for cell: Vector2i in sim.factory.belts:
		belts.append({"cell": _v2(cell), "items": sim.factory.belts[cell].items})
	var turrets := []
	for cell: Vector2i in sim.factory.turrets:
		var t: Factory.Turret = sim.factory.turrets[cell]
		turrets.append({"cell": _v2(cell), "ammo": t.ammo, "shots": t.shots})
	var crates := {}
	for key: String in sim.storages:
		crates[key] = _counts(sim.storages[key])
	var zombies := []
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		if not z.is_dead():
			zombies.append({"id": id, "type": z.type, "pos": _v3(z.pos), "home": _v3(z.home), "hp": z.hp,
					"facing": _v3(z.facing)})
	var searched := []
	for id: String in sim.loot.containers:
		if sim.loot.containers[id]["searched"]:
			searched.append(id)
	var bags := []
	for b: Dictionary in sim.bags:
		bags.append({"id": b["id"], "pos": _v3(b["pos"]), "items": b["items"], "gear": b.get("gear", []).duplicate(true)})
	var p := sim.player
	return {
		"version": VERSION,
		"seed": sim.seed_value,
		"ticks": sim.ticks,
		"clock": {"time": sim.clock.time_of_day, "day": sim.clock.day},
		"inventory": _counts(sim.inventory),
		"player": {"health": p.health, "food": p.food, "water": p.water, "energy": p.energy, "stamina": p.stamina,
				"bleeding": p.bleeding, "deaths": p.deaths, "dead": p.dead, "respawn_timer": p.respawn_timer},
		# Saved while driving: you load standing beside the car, not inside it.
		"player_pos": _v3(sim.vehicles.exit_pos(sim.vehicles.driving) if sim.vehicles.driving != "" else sim.player_pos),
		"spawn_point": _v3(sim.spawn_point),
		"pieces": pieces,
		"machines": machines,
		"belts": belts,
		"turrets": turrets,
		"crates": crates,
		"generators": sim.power.generators,
		"zombies": zombies,
		"next_zombie": sim.horde._next_id,
		"heat": sim.director.heat,
		"searched": searched,
		"vehicles": sim.vehicles.to_dict(),
		"skills": sim.skills.xp,
		"perks": sim.skills.perks,
		"perk_points": sim.skills.perk_points,
		"gear": sim.gear.to_dict(),
		"hands": sim.guns.hands,
		"stats": sim.tally,
		"infamy": sim.director.infamy,
		"unlocked": sim.director.unlocked,
		"bags": bags,
		"next_bag": sim._next_bag,
		"rng_state": str(sim._rng.state),
	}


## Lays saved state over a freshly made SimWorld whose town (loot containers, cars) is already set up,
## but which has nothing built and no zombies yet. Returns "" or what went wrong.
static func apply(sim: SimWorld, d: Dictionary) -> String:
	var version := int(d.get("version", 0))
	if version < 1 or version > VERSION:  # unknown or from a newer game: refuse rather than guess
		return "This save is from a different version (%s)" % str(d.get("version", "?"))
	sim.ticks = int(d["ticks"])
	sim.clock.time_of_day = float(d["clock"]["time"])
	sim.clock.day = int(d["clock"]["day"])
	sim.inventory.take_all(_counts(sim.inventory))  # keep the same Inventory object: others hold it
	sim.inventory.give_all(_ints(d["inventory"]))
	var pl: Dictionary = d["player"]
	var p := sim.player
	for key: String in ["health", "food", "water", "energy", "stamina", "respawn_timer"]:
		p.set(key, float(pl[key]))
	p.bleeding = bool(pl["bleeding"])
	p.deaths = int(pl["deaths"])
	p.dead = bool(pl["dead"])
	sim.player_pos = _to_v3(d["player_pos"])
	sim.spawn_point = _to_v3(d["spawn_point"])
	for pd: Dictionary in d["pieces"]:
		sim.build.restore(pd["key"], {"id": pd["id"], "cell": _to_v2(pd["cell"]), "side": int(pd["side"]),
				"hp": int(pd["hp"]), "open": bool(pd["open"]), "wear": float(pd["wear"])})
	for md: Dictionary in d["machines"]:
		var m: Factory.Machine = sim.factory.machines.get(_to_v2(md["cell"]))
		if m == null:
			continue
		m.input = _ints(md["input"])
		m.output = _ints(md["output"])
		m.progress = float(md["progress"])
		m.crafting = bool(md["crafting"])
		m.crafted = int(md["crafted"])
		m.muffled = bool(md["muffled"])
		m.time_scale = float(md["time_scale"])
		if sim.data.recipes.has(md.get("recipe", "")):
			sim.factory.set_recipe(m, md["recipe"])
	for bd: Dictionary in d["belts"]:
		var belt: Factory.Belt = sim.factory.belts.get(_to_v2(bd["cell"]))
		if belt != null:
			belt.items = []
			for e: Dictionary in bd["items"]:
				belt.items.append({"item": e["item"], "pos": float(e["pos"]), "prev": float(e["prev"])})
	for td: Dictionary in d["turrets"]:
		var t: Factory.Turret = sim.factory.turrets.get(_to_v2(td["cell"]))
		if t != null:
			t.ammo = int(td["ammo"])
			t.shots = int(td["shots"])
	for key: String in d["crates"]:
		if sim.storages.has(key):
			sim.storages[key].give_all(_ints(d["crates"][key]))
	for key: String in d["generators"]:
		if sim.power.generators.has(key):
			var g: Dictionary = d["generators"][key]
			sim.power.generators[key] = {"cans": int(g["cans"]), "fuel": float(g["fuel"]), "running": false,
					"load": 0.0, "muffled": bool(g["muffled"])}
	for zd: Dictionary in d["zombies"]:
		var z := sim.horde.restore(int(zd["id"]), zd["type"], _to_v3(zd["pos"]))
		z.home = _to_v3(zd["home"])
		z.hp = float(zd["hp"])
		z.facing = _to_v3(zd["facing"])
	sim.horde._next_id = int(d["next_zombie"])
	sim.director.heat = float(d["heat"])
	for id: String in d["searched"]:
		if sim.loot.containers.has(id):
			sim.loot.containers[id]["searched"] = true
	if d.has("vehicles"):
		sim.vehicles.load_dict(d["vehicles"])
	for s: String in d.get("skills", {}):
		sim.skills.xp[s] = float(d["skills"][s])
	sim.skills.perks = {}
	for perk: String in d.get("perks", {}):
		sim.skills.perks[perk] = int(d["perks"][perk])
	sim.skills.perk_points = int(d.get("perk_points", sim.skills.points_earned()))
	if d.has("gear"):
		sim.gear.load_dict(d["gear"])
	else:  # before M13: the pipe you always had becomes a white piece in the weapon slot
		sim.gear.load_dict({})
		sim.gear.give_start()
	if version < FIRST_WITH_GEAR:
		sim.spawn_old_pete()  # he wasn't in the hall before M13
	sim.guns.hands = "gun" if str(d.get("hands", "melee")) == "gun" and not sim.gear.gun().is_empty() else "melee"
	var st: Dictionary = d.get("stats", {})
	sim.tally = {"kills": int(st.get("kills", 0)), "deaths": int(st.get("deaths", 0))}
	sim.director.infamy = float(d.get("infamy", 0.0))
	sim.director.unlocked = Array(d.get("unlocked", []))
	sim._day = sim.clock.day
	for id: String in d.get("car_fuel", {}):  # saves from before M10c kept only the gas
		if sim.vehicles.cars.has(id):
			sim.vehicles.cars[id]["fuel"] = float(d["car_fuel"][id])
	sim.bags = []
	for b: Dictionary in d["bags"]:
		var pieces := []
		for gp: Dictionary in b.get("gear", []):
			pieces.append(Gear.clean(gp))
		sim.bags.append({"id": int(b["id"]), "pos": _to_v3(b["pos"]), "items": _ints(b["items"]), "gear": pieces})
	sim._next_bag = int(d["next_bag"])
	sim._rng.state = int(d["rng_state"])
	return ""


static func write(sim: SimWorld, path: String, extra: Dictionary = {}) -> String:
	var d := to_dict(sim)
	d.merge(extra)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Couldn't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(d, "\t"))
	return ""


## Reads a save file. Returns {} if missing or broken.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _counts(inv: Inventory) -> Dictionary:
	var out := {}
	for item: String in inv.items():
		out[item] = inv.count(item)
	return out


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out


static func _v2(v: Vector2i) -> Array:
	return [v.x, v.y]


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v2(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


static func _to_v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
