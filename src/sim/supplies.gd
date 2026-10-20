class_name Supplies
extends RefCounted
## R1b (Emmitt: "should we make loot respawn?" and "more places like where we got Pete's old rifle"): what the world
## puts out on a schedule, from data/supplies.json. Supply trucks: every few game days one goes off the road at one of
## the listed roadside spots (seeded, never the same spot twice running); its back is a loot container (the
## "supply_truck" table), its horn is stuck on for `horn_hours` or until it's searched (a continuous noise the zombies
## and the Director hear), and the base log and the radio say roughly where. Forage piles (Rust-style): small scrap
## and log piles that turn up round town, one a day up to `max`, on a seeded clear spot; gathered by hand until picked
## clean (a resource node with no extractor: data/resources.json kinds with "holds"). Named guardians: which of
## data/supplies.json "guardians" SimWorld.spawn_guardians has put at their posts. Saved under "supplies". Only the
## lists and the schedule live here; SimWorld registers the containers and the noise and says the words.

var data: GameData
var seed_value: int
var trucks: Array = []  # {id, pos: Vector3, yaw, day, horn_until (absolute game hours), model, spot, where}
var piles: Array = []  # {id, kind, pos: Vector3, left, day}
var guardians: Array = []  # named types put at their posts (once a game)
var last_truck_day := -1
var next_id := 1
var changes := 0  # goes up when a truck or pile appears or goes, so the views look again


func _init(p_data: GameData, p_seed: int) -> void:
	data = p_data
	seed_value = p_seed


func truck_cfg() -> Dictionary:
	return data.supplies.get("truck", {})


func piles_cfg() -> Dictionary:
	return data.supplies.get("piles", {})


func kind_cfg(kind: String) -> Dictionary:
	return (data.resources.get("kinds", {}) as Dictionary).get(kind, {})


## A new game day `day` (at `hours` absolute game hours): the schedule. `taken(pos)` says whether a spot is built
## over, on a road or otherwise no good for a pile. Returns {"trucks": [...], "piles": [...]}: what appeared.
func new_day(day: int, hours: float, taken: Callable) -> Dictionary:
	var out := {"trucks": [], "piles": []}
	var t := _due_truck(day, hours)
	if not t.is_empty():
		out["trucks"].append(t)
	var pc := piles_cfg()
	if not pc.is_empty() and day >= int(pc.get("first_day", 1)):
		for i in int(pc.get("per_day", 1)):
			var p := _new_pile(day, i, taken)
			if p.is_empty():
				break
			out["piles"].append(p)
	return out


func _due_truck(day: int, hours: float) -> Dictionary:
	var tc := truck_cfg()
	var spots: Array = tc.get("spots", [])
	if spots.is_empty() or day < int(tc.get("first_day", 2)):
		return {}
	if last_truck_day >= 0 and day - last_truck_day < int(tc.get("every_days", 3)):
		return {}
	var last_spot := int(trucks[-1]["spot"]) if not trucks.is_empty() else -1
	var pick := posmod(hash([seed_value, "truck", day]), spots.size())
	if spots.size() > 1 and pick == last_spot:
		pick = (pick + 1) % spots.size()
	var s: Dictionary = spots[pick]
	return add_truck(Vector3(float(s["pos"][0]), 0.0, float(s["pos"][1])), deg_to_rad(float(s.get("yaw", 0))), day,
			hours + float(tc.get("horn_hours", 6.0)), pick, str(s.get("name", "the road")))


## A truck off the road at `pos` (the schedule, a flag or a test). Returns its record.
func add_truck(pos: Vector3, yaw: float, day: int, horn_until: float, spot: int = -1, where: String = "the road") -> Dictionary:
	var t := {"id": "truck_%d" % next_id, "pos": pos, "yaw": yaw, "day": day, "horn_until": horn_until,
			"model": str(truck_cfg().get("model", "van")), "spot": spot, "where": where}
	next_id += 1
	trucks.append(t)
	last_truck_day = day
	changes += 1
	return t


func _new_pile(day: int, i: int, taken: Callable) -> Dictionary:
	var pc := piles_cfg()
	if piles.size() >= int(pc.get("max", 4)):
		return {}
	var raw: Array = pc.get("area", [-90, -100, 180, 150])
	var area := Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	var kinds: Array = pc.get("kinds", ["scrap_pile"])
	var apart := float(pc.get("apart", 12.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "pile", day, i])
	var kind := str(kinds[rng.randi_range(0, kinds.size() - 1)])
	for attempt in int(pc.get("tries", 40)):
		var at := Vector3(area.position.x + rng.randf() * area.size.x, 0.0, area.position.y + rng.randf() * area.size.y)
		if bool(taken.call(at)) or not clear_of_piles(at, apart):
			continue
		return add_pile(kind, at, day)
	return {}


func clear_of_piles(at: Vector3, apart: float) -> bool:
	for p: Dictionary in piles:
		if Vector2(at.x - p["pos"].x, at.z - p["pos"].z).length() < apart:
			return false
	return true


## A pile of `kind` at `pos`, holding its kind's `holds`. Returns its record.
func add_pile(kind: String, pos: Vector3, day: int) -> Dictionary:
	var p := {"id": "pile_%d" % next_id, "kind": kind, "pos": pos, "left": int(kind_cfg(kind).get("holds", 4)), "day": day}
	next_id += 1
	piles.append(p)
	changes += 1
	return p


func truck(id: String) -> Dictionary:
	for t: Dictionary in trucks:
		if t["id"] == id:
			return t
	return {}


func pile(id: String) -> Dictionary:
	for p: Dictionary in piles:
		if p["id"] == id:
			return p
	return {}


## A pile as a resource-node record (SimWorld.resource_node: gather_start and _tick_gather work on it unchanged):
## no extractor, no purity, "pile" true and "left" what's in it. {} if `id` isn't a pile.
func pile_node(id: String) -> Dictionary:
	var p := pile(id)
	if p.is_empty():
		return {}
	var kind := kind_cfg(str(p["kind"]))
	var pos: Vector3 = p["pos"]
	return {"id": id, "kind": p["kind"], "name": str(kind.get("name", p["kind"])), "purity": "", "rate": 1.0,
			"cell": BuildGrid.world_to_cell(pos), "pos": pos, "prop_pos": pos, "yaw": 0.0, "extractor": "",
			"model": str(kind.get("model", p["kind"])), "pile": true, "left": int(p["left"])}


## Whether truck `t`'s horn blares now: until its hours run out or it's searched (`searched(id)` says).
func horn_on(t: Dictionary, hours: float, searched: Callable) -> bool:
	return hours < float(t["horn_until"]) and not bool(searched.call(t["id"]))


## The stuck horns as NoiseField continuous sources (SimWorld appends them each tick; the key names the truck). "world"
## marks them the world's own sound: zombies in earshot walk to one, but the Director (heat, infamy, waves) skips it.
func noise_sources(hours: float, searched: Callable) -> Array:
	var out := []
	var loud := float(truck_cfg().get("horn_loudness", 70.0))
	for t: Dictionary in trucks:
		if horn_on(t, hours, searched):
			out.append({"pos": t["pos"] + Vector3(0, 1.2, 0), "loudness": loud, "key": "truck:" + str(t["id"]), "kind": "horn_truck", "world": true})
	return out


## `n` taken from pile `id` by hand. Returns what's left; at 0 the pile is gone.
func take_from_pile(id: String, n: int) -> int:
	for i in piles.size():
		var p: Dictionary = piles[i]
		if p["id"] != id:
			continue
		p["left"] = maxi(0, int(p["left"]) - n)
		if int(p["left"]) <= 0:
			piles.remove_at(i)
			changes += 1
			return 0
		return int(p["left"])
	return 0


func to_dict() -> Dictionary:
	var ts := []
	for t: Dictionary in trucks:
		ts.append({"id": t["id"], "pos": [t["pos"].x, t["pos"].y, t["pos"].z], "yaw": t["yaw"], "day": t["day"],
				"horn_until": t["horn_until"], "model": t["model"], "spot": t["spot"], "where": t["where"]})
	var ps := []
	for p: Dictionary in piles:
		ps.append({"id": p["id"], "kind": p["kind"], "pos": [p["pos"].x, p["pos"].y, p["pos"].z], "left": p["left"], "day": p["day"]})
	return {"trucks": ts, "piles": ps, "guardians": guardians.duplicate(), "last_truck_day": last_truck_day, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	trucks.clear()
	piles.clear()
	for t: Dictionary in d.get("trucks", []):
		trucks.append({"id": str(t["id"]), "pos": Vector3(float(t["pos"][0]), float(t["pos"][1]), float(t["pos"][2])),
				"yaw": float(t["yaw"]), "day": int(t["day"]), "horn_until": float(t["horn_until"]), "model": str(t["model"]),
				"spot": int(t.get("spot", -1)), "where": str(t.get("where", "the road"))})
	for p: Dictionary in d.get("piles", []):
		piles.append({"id": str(p["id"]), "kind": str(p["kind"]), "pos": Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["pos"][2])),
				"left": int(p["left"]), "day": int(p["day"])})
	guardians = []
	for g in d.get("guardians", []):
		guardians.append(str(g))
	last_truck_day = int(d.get("last_truck_day", -1))
	next_id = int(d.get("next_id", 1))
	changes += 1
