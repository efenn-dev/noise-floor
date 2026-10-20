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
## "hands" says whether the firearm or melee weapon was in your hands. A save from before 8 has no firearm.
## 9 = M15: turret parts (suppressor, scope) ride in "turrets"; hoppers and repair stations ("bins": what they
## hold); sensors with their actions, floodlights' night setting, noisemakers' blare and recharge, doors a
## sensor holds shut ("automation"); sprung bear traps; and the base log. A save from before 9 loads with
## none of those (it had none of the pieces), an empty base log, and every sensor on its default action.
## 10 = P3: a piece the town laid (houses, beds, the factory hall, furniture) carries "town": true, so pulling
## it down gives salvage, not its full cost. A save from 3 to 9 gets the flag on every piece that stands where
## the town plan put one of the same kind (see _mark_town); one from before 3 gets the town laid fresh, flagged.
## 11 = M16: the player's warmth ("player" "warmth") and each stove's planks and burning fuel ("stoves"). A save from
## before 11 loads with full warmth and every stove (it had none) empty; the season follows from the saved day.
## 12 = M17a: the industrial park's warehouses are pieces (saved like the houses), its zombies are ordinary saved
## zombies, the factory hall has a north doorway, and the projects ("projects": each one's phase, items delivered,
## work progress and whether work was started; "projects_done"). A save from before 12 gets the park laid fresh
## (see holds_park; main.gd also spawns its zombies after applying it), the hall's north doorway opened, and every
## project at phase 0.
## 13 = S3: the hotbar (ten slots, "build:<piece>" / "item:<item>" / ""), and a door's "swing" (which way it
## opened). A save from before 13 gets the default hotbar and its open doors swing the default way.
## 14 = V10: Melee split into Blunt, Blades and Axe (a save from before 14 gives its Melee xp to all three),
## plus Maintenance. Weapons wear at their own rate and break at 0 (no new saved fields).
## 15 = V14 slots: the old gun moves to primary or sidearm by its base, and the best carried bag moves to
## the back slot. The other bags stay in the inventory and no item is discarded.
## 16 = V17 window vaulting: broken windows save whether their sharp glass remnants have been cleared.
## A broken window from any older save loads with shards, matching a newly smashed window.
## 17 = V18: searched containers keep their remaining items and gear, and built storage crates can hold gear.
## 18 = V19 two hotbars: "hotbar" is {"hands": [...], "build": [...]}; an older single bar is split by kind
## (Hotbar.load_saved), so no version check is needed to read it.
## 19 = V25 first-hour guidance: objective progress and the current better-gear suggestion. Version-18 and
## older saves are established games, so their missing guidance loads inactive instead of restarting it.
## 20 = V29 difficulty and the one-shot first-night warning/wave/morning state. Older saves are Normal and
## their elapsed day-one beats are marked sent so migration never invents a wave on load.
## 21 = V34 items in the world: each entry in "bags" has a "kind" ("bag" for death bags, "item" for something
## dropped or placed as itself) and a "yaw". Older entries load as bags lying flat, so nothing moves or vanishes.
## 22 = F2 the Hub: "milestones" (done and handed in) and "rescue" (the broadcast's state and day). A save from
## before 22 had every piece unlocked, so it gets every milestone but the final one: nothing it built is locked.
## 23 = W3b downtown: the shops' walls, doors, windows and floors are pieces (saved like the houses) and its
## zombies are ordinary saved zombies. A save from before 23 gets downtown laid fresh (see holds_downtown; main.gd
## also spawns its zombies after applying it).
## 24 = W3c West and East Street's houses: their pieces are saved like the town's, and "suburbs_skipped" names the
## houses left out because the save had something built there. A save from before 24 gets them laid fresh (see
## holds_suburbs; main.gd lays them round the save's own pieces and spawns their zombies after applying it).
## 25 = W3d the farms and the hunting cabin: their pieces are saved like the town's, and "rural_skipped" names the
## buildings left out because the save had something built there (as for 24). A save from before 25 gets them laid
## fresh round its own pieces (holds_rural) and their zombies.
const VERSION := 25
const FIRST_WITH_PARK := 12
const FIRST_WITH_DOWNTOWN := 23
const FIRST_WITH_SUBURBS := 24
const FIRST_WITH_RURAL := 25
const FIRST_WITH_TOWN_FLAG := 10
const FIRST_WITH_GEAR := 6
const FIRST_WITH_PROPS := 7
const FIRST_WITH_TOWN := 3
const FIRST_WITH_FACTORY := 4
## True if the save already holds the town's houses as pieces, so the world must not lay them again.
static func holds_town(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_TOWN


## M17a: true if the save already holds the industrial park's warehouse pieces (and its zombies).
static func holds_park(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_PARK


## W3d: true if the save already holds the farms and the hunting cabin (and their zombies).
static func holds_rural(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_RURAL


## W3c: true if the save already holds West and East Street's houses (and their zombies).
static func holds_suburbs(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_SUBURBS


## W3b: true if the save already holds downtown's shop pieces (and its zombies).
static func holds_downtown(d: Dictionary) -> bool:
	return int(d.get("version", 0)) >= FIRST_WITH_DOWNTOWN


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
				"open": p.get("open", false), "wear": p.get("wear", 0.0), "town": p.get("town", false),
				"swing": p.get("swing", 1), "shards": p.get("shards", false)})
	var machines := []
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		machines.append({"cell": _v2(cell), "input": m.input, "output": m.output, "progress": m.progress,
				"crafting": m.crafting, "crafted": m.crafted, "muffled": m.muffled, "boxed": m.boxed, "time_scale": m.time_scale,
				"recipe": m.recipe_id})
	var belts := []
	for cell: Vector2i in sim.factory.belts:
		belts.append({"cell": _v2(cell), "items": sim.factory.belts[cell].items})
	var routers := []  # F3: what splitters and mergers hold (no version bump: an older save just has none)
	for cell: Vector2i in sim.factory.routers:
		var r: Factory.Router = sim.factory.routers[cell]
		routers.append({"cell": _v2(cell), "items": r.items.duplicate(), "next_out": r.next_out})
	var turrets := []
	for cell: Vector2i in sim.factory.turrets:
		var t: Factory.Turret = sim.factory.turrets[cell]
		var parts := {}
		for slot: String in t.parts:
			parts[slot] = t.parts[slot].duplicate(true)
		turrets.append({"cell": _v2(cell), "ammo": t.ammo, "shots": t.shots, "parts": parts})
	var bins := []
	for cell: Vector2i in sim.factory.bins:
		var bin: Factory.Bin = sim.factory.bins[cell]
		bins.append({"cell": _v2(cell), "item": bin.item, "count": bin.count, "timer": bin.timer})
	var crates := {}
	var crate_gear := {}
	for key: String in sim.storages:
		crates[key] = _counts(sim.storages[key])
		crate_gear[key] = sim.storage_gear.get(key, []).duplicate(true)
	var zombies := []
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		if not z.is_dead():
			var zd := {"id": id, "type": z.type, "pos": _v3(z.pos), "home": _v3(z.home), "hp": z.hp,
					"facing": _v3(z.facing)}
			if z.is_guardian():  # Q4: a guardian's home area and spot
				var g := z.guard_area
				zd["guard"] = {"area": [g.position.x, g.position.y, g.size.x, g.size.y], "spot": _v3(z.guard_spot)}
			zombies.append(zd)
	var searched := []
	var loot_contents := {}
	for id: String in sim.loot.containers:
		if sim.loot.containers[id]["searched"]:
			searched.append(id)
			loot_contents[id] = {"items": _counts(sim.loot.inventory(id)),
					"gear": sim.loot.containers[id]["gear"].duplicate(true)}
	var bags := []
	for b: Dictionary in sim.bags:
		bags.append({"id": b["id"], "pos": _v3(b["pos"]), "items": b["items"], "gear": b.get("gear", []).duplicate(true),
				"kind": b.get("kind", SimWorld.BAG), "yaw": float(b.get("yaw", 0.0))})
	var p := sim.player
	return {
		"version": VERSION,
		"difficulty": sim.difficulty.id,
		"seed": sim.seed_value,
		"ticks": sim.ticks,
		"clock": {"time": sim.clock.time_of_day, "day": sim.clock.day},
		"inventory": _counts(sim.inventory),
		"player": {"health": p.health, "food": p.food, "water": p.water, "energy": p.energy, "stamina": p.stamina,
				"bleeding": p.bleeding, "deaths": p.deaths, "dead": p.dead, "respawn_timer": p.respawn_timer,
				"warmth": p.warmth},
		# Saved while driving: you load standing beside the car, not inside it.
		"player_pos": _v3(sim.vehicles.exit_pos(sim.vehicles.driving) if sim.vehicles.driving != "" else sim.player_pos),
		"spawn_point": _v3(sim.spawn_point),
		"pieces": pieces,
		"hotbar": sim.hotbar.to_dict(),  # S3; V19: both bars
		"machines": machines,
		"belts": belts,
		"routers": routers,
		"made": {"total": sim.factory.made, "mark": sim.made_mark, "yesterday": sim.made_yesterday},  # F6
		"turrets": turrets,
		"bins": bins,
		"automation": sim.automation.to_dict(),
		"sprung": sim.defense.sprung.keys(),
		"base_log": sim.base_log.to_dict(),
		"crates": crates,
		"suburbs_skipped": sim.suburbs_skipped.duplicate(),  # W3c
		"rural_skipped": sim.rural_skipped.duplicate(),  # W3d
		"crate_gear": crate_gear,
		"generators": sim.power.generators,
		"stoves": sim.climate.to_dict(),
		"projects": sim.projects.to_dict(),
		"carts": sim.carts.to_dict(),  # F5: the home stop and each cart's trip and load
		"projects_done": sim.projects.done.duplicate(),
		"milestones": sim.milestones.to_dict(),
		"learning": sim.learning.to_dict(),  # P10
		"perk_snooze": sim.perk_snooze_until,  # P12
		"perk_reset_day": sim.perk_reset_day,  # P13
		"salvage": sim.salvage.to_dict(),  # P11: felled trees, stripped wrecks
		"rescue": {"state": sim.rescue_state, "day": sim.rescue_day, "hours": sim.broadcast_hours, "due": sim.rescue_due},
		"zombies": zombies,
		"next_zombie": sim.horde._next_id,
		"heat": sim.director.heat,
		"searched": searched,
		"loot_contents": loot_contents,
		"vehicles": sim.vehicles.to_dict(),
		"skills": sim.skills.xp,
		"perks": sim.skills.perks,
		"perk_points": sim.skills.perk_points,
		"guidance": sim.guidance.to_dict(),
		"gear": sim.gear.to_dict(),
		"hands": sim.guns.hands,
		"stats": sim.tally,
		"infamy": sim.director.infamy,
		"unlocked": sim.director.unlocked,
		"first_night": sim.director.first_night_state(),
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
	# Difficulty did not exist before V29; the version gate is the migration, even if a hand-edited
	# old save happens to contain a field with that name.
	sim.apply_difficulty(str(d.get("difficulty", Difficulty.DEFAULT)) if version >= 20 else Difficulty.DEFAULT)
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
	p.warmth = float(pl.get("warmth", 100.0))  # M16: full for a save from before 11
	p.deaths = int(pl["deaths"])
	p.dead = bool(pl["dead"])
	sim.player_pos = _to_v3(d["player_pos"])
	sim.spawn_point = _to_v3(d["spawn_point"])
	for pd: Dictionary in d["pieces"]:
		var piece := {"id": pd["id"], "cell": _to_v2(pd["cell"]), "side": int(pd["side"]),
				"hp": int(pd["hp"]), "open": bool(pd["open"]), "wear": float(pd["wear"])}
		if piece["id"] == "window" and piece["hp"] <= 0:
			piece["shards"] = bool(pd.get("shards", version < 16))
		if bool(pd.get("town", false)):
			piece["town"] = true
		if pd.has("swing"):  # S3: before 13 every open door swung the default way
			piece["swing"] = int(pd["swing"])
		sim.build.restore(pd["key"], piece)
	if version >= FIRST_WITH_TOWN and version < FIRST_WITH_TOWN_FLAG:
		_mark_town(sim)
	if version >= FIRST_WITH_FACTORY and version < FIRST_WITH_PARK:
		for key: String in TownPlan.factory()["north_doorway"]:  # M17a: open the hall's north doorway
			if sim.build.pieces.has(key) and sim.build.pieces[key]["id"] == "town_wall":
				sim.build.remove(key, Inventory.new())
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
		m.boxed = bool(md.get("boxed", false))  # F5
		m.time_scale = float(md["time_scale"])
		if sim.data.recipes.has(md.get("recipe", "")):
			sim.factory.set_recipe(m, md["recipe"])
	for bd: Dictionary in d["belts"]:
		var belt: Factory.Belt = sim.factory.belts.get(_to_v2(bd["cell"]))
		if belt != null:
			belt.items = []
			for e: Dictionary in bd["items"]:
				belt.items.append({"item": e["item"], "pos": float(e["pos"]), "prev": float(e["prev"])})
	var made: Dictionary = d.get("made", {})  # F6: none before (counting starts on load)
	sim.factory.made = _count_dict(made.get("total", {}))
	sim.made_mark = _count_dict(made.get("mark", {}))
	sim.made_yesterday = _count_dict(made.get("yesterday", {}))
	for rd: Dictionary in d.get("routers", []):  # F3
		var r: Factory.Router = sim.factory.routers.get(_to_v2(rd["cell"]))
		if r != null:
			r.items = Array(rd["items"]).map(func(it: Variant) -> String: return str(it))
			r.next_out = int(rd.get("next_out", 0))
	for td: Dictionary in d["turrets"]:
		var t: Factory.Turret = sim.factory.turrets.get(_to_v2(td["cell"]))
		if t != null:
			t.ammo = int(td["ammo"])
			t.shots = int(td["shots"])
			t.parts = {}
			for slot: String in td.get("parts", {}):
				t.parts[slot] = Gear.clean(td["parts"][slot])
	for bd: Dictionary in d.get("bins", []):  # M15
		var bin: Factory.Bin = sim.factory.bins.get(_to_v2(bd["cell"]))
		if bin != null and int(bd["count"]) > 0:
			bin.put(str(bd["item"]), int(bd["count"]))
		if bin != null:
			bin.timer = float(bd.get("timer", 0.0))
	sim.hotbar.load_saved(d.get("hotbar", []))  # S3: defaults before 13; V19: an old single bar is split
	sim.automation.load_dict(d.get("automation", {}))
	sim.defense.sprung = {}
	for key: String in d.get("sprung", []):
		if sim.build.pieces.has(key):
			sim.defense.sprung[key] = true
	sim.base_log.load_list(d.get("base_log", []))
	if holds_suburbs(d):  # W3c (an older save keeps what place_suburbs worked out while laying them)
		sim.suburbs_skipped = Array(d.get("suburbs_skipped", []))
	if holds_rural(d):  # W3d, likewise
		sim.rural_skipped = Array(d.get("rural_skipped", []))
	for key: String in d["crates"]:
		if sim.storages.has(key):
			sim.storages[key].give_all(_ints(d["crates"][key]))
	for key: String in d.get("crate_gear", {}):
		if sim.storage_gear.has(key):
			for gp: Dictionary in d["crate_gear"][key]:
				sim.storage_gear[key].append(Gear.clean(gp))
	for key: String in d["generators"]:
		if sim.power.generators.has(key):
			var g: Dictionary = d["generators"][key]
			sim.power.generators[key] = {"cans": int(g["cans"]), "fuel": float(g["fuel"]), "running": false,
					"load": 0.0, "muffled": bool(g["muffled"]), "boxed": bool(g.get("boxed", false))}
	sim.climate.from_dict(d.get("stoves", {}))  # M16: none before 11
	sim.projects.load_dict(d.get("projects", {}), d.get("projects_done", []))  # M17a: phase 0 before 12
	sim.carts.from_dict(d.get("carts", {}))  # F5: none before
	sim._carts_seen = sim.carts.delivered
	sim.milestones.load_dict(d.get("milestones", {}))  # F2
	sim.learning.load_dict(d.get("learning", {}))  # P10: a save from before knows every piece
	sim.perk_snooze_until = float(d.get("perk_snooze", 0.0))  # P12
	sim.perk_reset_day = int(d.get("perk_reset_day", -1))  # P13
	sim.salvage.load_dict(d.get("salvage", {}))  # P11: none before
	if version < 22:
		sim.milestones.grant_all_but_final()  # F2: an older game keeps every piece it could build
	var rescue: Dictionary = d.get("rescue", {})
	sim.rescue_state = str(rescue.get("state", ""))
	sim.rescue_day = int(rescue.get("day", -1))
	sim.broadcast_hours = float(rescue.get("hours", 0.0))  # F4
	sim.rescue_due = float(rescue.get("due", -1.0))
	for zd: Dictionary in d["zombies"]:
		var z := sim.horde.restore(int(zd["id"]), zd["type"], _to_v3(zd["pos"]))
		z.home = _to_v3(zd["home"])
		z.hp = float(zd["hp"])
		z.facing = _to_v3(zd["facing"])
		if zd.has("guard"):  # Q4
			var ga: Array = zd["guard"]["area"]
			z.set_guard(Rect2(float(ga[0]), float(ga[1]), float(ga[2]), float(ga[3])), _to_v3(zd["guard"]["spot"]))
			z.home = _to_v3(zd["home"])
		elif z.type == "old_pete":  # a save from before Q4: Old Pete guards the hall from now on
			var at: Dictionary = TownPlan.factory()["pete"]
			z.set_guard(at["guard"], at["pos"])
	sim.horde._next_id = int(d["next_zombie"])
	sim.director.heat = float(d["heat"])
	for id: String in d["searched"]:
		if sim.loot.containers.has(id):
			sim.loot.containers[id]["searched"] = true
	for id: String in d.get("loot_contents", {}):
		if not sim.loot.containers.has(id):
			continue
		var saved: Dictionary = d["loot_contents"][id]
		sim.loot.inventory(id).give_all(_ints(saved.get("items", {})))
		sim.loot.containers[id]["gear"] = []
		for gp: Dictionary in saved.get("gear", []):
			sim.loot.containers[id]["gear"].append(Gear.clean(gp))
	if d.has("vehicles"):
		sim.vehicles.load_dict(d["vehicles"])
	for s: String in d.get("skills", {}):
		if s == "melee":
			# V10 (14): Melee split into Blunt, Blades and Axe. What you'd earned counts toward all three.
			for into: String in ["blunt", "blades", "axe"]:
				sim.skills.xp[into] = maxf(float(sim.skills.xp.get(into, 0.0)), float(d["skills"][s]))
			continue
		sim.skills.xp[s] = float(d["skills"][s])
	sim.skills.perks = {}
	for perk: String in d.get("perks", {}):
		sim.skills.perks[perk] = int(d["perks"][perk])
	sim.skills.perk_points = int(d.get("perk_points", sim.skills.points_earned()))
	sim.guidance.load_dict(d.get("guidance", {}))
	if d.has("gear"):
		sim.gear.load_dict(d["gear"])
	else:  # before M13: the pipe you always had becomes a white piece in the weapon slot
		sim.gear.load_dict({})
		sim.gear.give_start()
	if version < FIRST_WITH_GEAR:
		sim.spawn_old_pete()  # he wasn't in the hall before M13
	if version < 15:
		_wear_best_legacy_bag(sim)
	var saved_hands := str(d.get("hands", "melee"))
	if version < 15 and saved_hands == "gun":
		saved_hands = sim.gear.gun_slot()
	if saved_hands in Gear.FIREARM_SLOTS and sim.gear.equipped.get(saved_hands) is Dictionary:
		sim.guns.hands = saved_hands
		sim.gear.set_active_gun(saved_hands)
	else:
		sim.guns.hands = "melee"
	var st: Dictionary = d.get("stats", {})
	sim.tally = {"kills": int(st.get("kills", 0)), "deaths": int(st.get("deaths", 0))}
	sim.director.infamy = float(d.get("infamy", 0.0))
	sim.director.unlocked = Array(d.get("unlocked", []))
	sim.director.load_first_night_state(d.get("first_night", {}), sim.clock, version < 20)
	sim._day = sim.clock.day
	for id: String in d.get("car_fuel", {}):  # saves from before M10c kept only the gas
		if sim.vehicles.cars.has(id):
			sim.vehicles.cars[id]["fuel"] = float(d["car_fuel"][id])
	sim.bags = []
	for b: Dictionary in d["bags"]:
		var pieces := []
		for gp: Dictionary in b.get("gear", []):
			pieces.append(Gear.clean(gp))
		sim.bags.append({"id": int(b["id"]), "pos": _to_v3(b["pos"]), "items": _ints(b["items"]), "gear": pieces,
				"kind": str(b.get("kind", SimWorld.BAG)), "yaw": float(b.get("yaw", 0.0))})  # V34: older saves: bags
	sim._next_bag = int(d["next_bag"])
	sim._rng.state = int(d["rng_state"])
	return ""


## V15 migration: old saves counted the best bag in pockets. Wear exactly one of that stack now.
static func _wear_best_legacy_bag(sim: SimWorld) -> void:
	if str(sim.gear.equipped.get("back", "")) != "":
		return
	var best := ""
	for item: String in sim.inventory.items():
		if sim.data.item_value(item, "bag") > sim.data.item_value(best, "bag"):
			best = item
	if best != "" and sim.inventory.remove(best, 1):
		sim.gear.equipped["back"] = best


## P3 upgrade for a version 3-9 save: flags as the town's every piece standing where the seed's town plan
## (houses, beds, factory hall, furniture) puts one of the same kind. A town door you pulled down and built
## again yourself in the same spot counts as the town's: rare, and it only changes a refund.
static func _mark_town(sim: SimWorld) -> void:
	var plan := TownPlan.generate(sim.seed_value, sim.data)
	var keys := {}
	for p: Dictionary in plan["pieces"] + plan["factory"]["pieces"]:
		keys[TownPlan.piece_key(p)] = p["id"]
	for b: Dictionary in plan["beds"]:
		keys[sim.build.key_for("bed", b["cell"])] = "bed"
	for p: Dictionary in plan["props"] + plan["factory"].get("props", []):
		keys[sim.build.key_for(p["id"], p["cell"])] = p["id"]
	for key: String in keys:
		if sim.build.pieces.has(key) and sim.build.pieces[key]["id"] == keys[key]:
			sim.build.pieces[key]["town"] = true


static func write(sim: SimWorld, path: String, extra: Dictionary = {}) -> String:
	var d := to_dict(sim)
	d.merge(extra)
	return write_dict(d, path)


## Writes an already assembled save dictionary (V26 migration uses this without rebuilding a SimWorld).
static func write_dict(d: Dictionary, path: String) -> String:
	var folder := path.get_base_dir()
	if folder != "":
		var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		if dir_error != OK:
			return "Couldn't make %s (%s)" % [folder, error_string(dir_error)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Couldn't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
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


## F6: {item: count} back from JSON (numbers come back as floats).
static func _count_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for item: String in d:
		out[item] = int(d[item])
	return out

