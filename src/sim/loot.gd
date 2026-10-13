class_name Loot
extends RefCounted
## Rolls loot tables (data/loot.json) and keeps track of every searchable container in the world.
## Searching takes search_time seconds, makes a little noise, and stops if you walk off
## (further than search_range). Each container's loot is fixed by the world seed and its id,
## and a searched container stays empty (loot never respawns).

var data: GameData
var seed_value: int
## id -> {table: String, pos: Vector3, searched: bool}
var containers: Dictionary = {}
var active := ""        # id being searched now, "" if none
var progress := 0.0     # seconds into the current search
## Set by SimWorld (M12): Scavenging and Quick Fingers make searches quicker, Lucky Find adds an item.
var skills: Skills


func _init(p_data: GameData, p_seed: int = 1) -> void:
	data = p_data
	seed_value = p_seed


## Rolls a table: `rolls` picks, each a weighted item and an amount. Returns {item: count}.
static func roll(table: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var entries: Array = table["items"]
	var total := 0.0
	for e: Dictionary in entries:
		total += float(e["weight"])
	for i in rng.randi_range(int(table["rolls"][0]), int(table["rolls"][1])):
		var pick := rng.randf() * total
		for e: Dictionary in entries:
			pick -= float(e["weight"])
			if pick <= 0.0:
				out[e["item"]] = out.get(e["item"], 0) + rng.randi_range(int(e["min"]), int(e["max"]))
				break
	return out


func add(id: String, table: String, pos: Vector3) -> void:
	containers[id] = {"table": table, "pos": pos, "searched": false, "extra": {}}


## Puts something particular in a container (a car key in a glovebox or a kitchen drawer); a search finds it too.
func add_extra(id: String, items: Dictionary) -> void:
	for item: String in items:
		containers[id]["extra"][item] = int(containers[id]["extra"].get(item, 0)) + int(items[item])


func display_name(id: String) -> String:
	return data.loot[containers[id]["table"]]["name"] if containers.has(id) else ""


## Starts searching container `id`. Returns "" or why not.
func start(id: String, player_pos: Vector3) -> String:
	if not containers.has(id):
		return "Nothing to search"
	if containers[id]["searched"]:
		return "Already searched"
	if _flat_dist(containers[id]["pos"], player_pos) > float(data.survival["search_range"]):
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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, active])
	var table: Dictionary = data.loot[c["table"]]
	var items := roll(table, rng)
	var lucky := skills != null and rng.randf() < skills.bonus("lucky_find")
	if lucky:  # one more pick from the same table
		var one := table.duplicate()
		one["rolls"] = [1, 1]
		for item: String in (roll(one, rng) as Dictionary):
			items[item] = int(items.get(item, 0)) + 1
	for item: String in c.get("extra", {}):
		items[item] = int(items.get(item, 0)) + int(c["extra"][item])
	c["searched"] = true
	var done := {"id": active, "items": items, "table": c["table"], "lucky": lucky}
	active = ""
	return done


## Seconds a search takes: search_time, 5% less per Scavenging level and 10% per Quick Fingers rank,
## never under search_time_min (a share of the base).
func search_time() -> float:
	var cut := skills.bonus("search_speed") if skills != null else 0.0
	return float(data.survival["search_time"]) * maxf(float(data.skills["search_time_min"]), 1.0 - cut)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
