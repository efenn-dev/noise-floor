class_name Loot
extends RefCounted
## Rolls loot tables (data/loot.json) and keeps track of every searchable container in the world.
## Searching takes search_time seconds, makes a little noise, and stops if you walk off
## (further than search_range). Each container's loot is fixed by the world seed and its id,
## and a searched container keeps the rolled contents until the player takes them (loot never respawns).

var data: GameData
var seed_value: int
var difficulty: Difficulty
## V18: id -> {table: String, pos: Vector3, searched: bool, items: Inventory, gear: Array};
## revealed contents stay here until the player chooses what to take.
var containers: Dictionary = {}
var active := ""        # id being searched now, "" if none
var progress := 0.0     # seconds into the current search
## Set by SimWorld (M12): Scavenging and Quick Fingers make searches quicker, Lucky Find adds an item.
var skills: Skills


func _init(p_data: GameData, p_seed: int = 1, p_difficulty: Difficulty = null) -> void:
	data = p_data
	seed_value = p_seed
	difficulty = p_difficulty


## Rolls a table: `rolls` picks, each a weighted item and an amount. Returns {item: count}.
## A1: a table's optional "empty" weight is the chance a pick finds nothing (trash cans).
static func roll(table: Dictionary, rng: RandomNumberGenerator, abundance: float = 1.0) -> Dictionary:
	var out := {}
	var entries: Array = table["items"]
	var total := float(table.get("empty", 0.0))
	for e: Dictionary in entries:
		total += float(e["weight"])
	var roll_min := maxi(1, roundi(float(table["rolls"][0]) * abundance))
	var roll_max := maxi(roll_min, roundi(float(table["rolls"][1]) * abundance))
	for _i in rng.randi_range(roll_min, roll_max):
		var pick := rng.randf() * total
		for e: Dictionary in entries:
			pick -= float(e["weight"])
			if pick <= 0.0:
				out[e["item"]] = out.get(e["item"], 0) + rng.randi_range(int(e["min"]), int(e["max"]))
				break
	return out


func add(id: String, table: String, pos: Vector3) -> void:
	containers[id] = {"table": table, "pos": pos, "searched": false, "extra": {}, "items": Inventory.new(), "gear": []}


## S4/V18: gear pieces waiting in a container (including what a dead zombie carried).
func add_gear(id: String, pieces: Array) -> void:
	containers[id]["gear"].append_array(pieces)


## S4: drops a container (a cleared corpse); a search of it in progress is abandoned.
func remove(id: String) -> void:
	containers.erase(id)
	if active == id:
		active = ""
		progress = 0.0


## Puts something particular in a container (a car key in a glovebox or a kitchen drawer); a search finds it too.
func add_extra(id: String, items: Dictionary) -> void:
	for item: String in items:
		containers[id]["extra"][item] = int(containers[id]["extra"].get(item, 0)) + int(items[item])


func display_name(id: String) -> String:
	return data.loot[containers[id]["table"]]["name"] if containers.has(id) else ""


func inventory(id: String) -> Inventory:
	return containers[id]["items"] if containers.has(id) else null


func in_reach(id: String, player_pos: Vector3) -> bool:
	return containers.has(id) and _flat_dist(containers[id]["pos"], player_pos) <= float(data.survival["search_range"])


## Starts searching container `id`. Returns "" or why not.
func start(id: String, player_pos: Vector3) -> String:
	if not containers.has(id):
		return "Nothing to search"
	if containers[id]["searched"]:
		return "Already searched"
	if not in_reach(id, player_pos):
		return "Too far away"
	if active != id:
		active = id
		progress = 0.0
	return ""


## One tick. Returns {} or, when a search finishes, {"id": id, "items": {item: count}}.
func tick(dt: float, player_pos: Vector3) -> Dictionary:
	if active == "":
		return {}
	var c: Dictionary = containers[active]
	if _flat_dist(c["pos"], player_pos) > float(data.survival["search_range"]):
		active = ""  # walked away: search abandoned (and starts over next time)
		return {}
	progress += dt
	if progress < search_time() - 1e-6:
		return {}
	return reveal(active)


## Rolls and marks one container searched immediately. SimWorld adds gear/guns and announces it.
func reveal(id: String) -> Dictionary:
	if not containers.has(id) or containers[id]["searched"]:
		return {}
	var c: Dictionary = containers[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, id])
	var table: Dictionary = data.loot[c["table"]]
	var abundance := difficulty.multiplier("loot_abundance") if difficulty != null else 1.0
	abundance *= area_loot(data, c["pos"])  # W3e: the further out, the better
	var items := roll(table, rng, abundance)
	var lucky := skills != null and rng.randf() < skills.bonus("lucky_find")
	if lucky:  # one more pick from the same table
		var one := table.duplicate()
		one["rolls"] = [1, 1]
		for item: String in (roll(one, rng) as Dictionary):
			items[item] = int(items.get(item, 0)) + 1
	for item: String in c.get("extra", {}):
		items[item] = int(items.get(item, 0)) + int(c["extra"][item])
	c["searched"] = true
	var done := {"id": id, "items": items, "table": c["table"], "lucky": lucky}
	active = ""
	progress = 0.0
	return done


## W3e: how much more loot a search at `pos` finds, by the area it's in (data/areas.json "loot"; 1 outside them).
static func area_loot(p_data: GameData, pos: Vector3) -> float:
	var area := WorldMap.area_at(pos)
	return float((p_data.areas.get(area, {}) as Dictionary).get("loot", 1.0)) if area != "" else 1.0


## Seconds a search takes: search_time, 5% less per Scavenging level and 10% per Quick Fingers rank,
## never under search_time_min (a share of the base).
func search_time() -> float:
	var cut := skills.bonus("search_speed") if skills != null else 0.0
	return float(data.survival["search_time"]) * maxf(float(data.skills["search_time_min"]), 1.0 - cut)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
