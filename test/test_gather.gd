extends "res://test/base_test.gd"
## P5 (Emmitt: "how should we make users gather materials for things like the smelter?"): E on a resource node
## gathers there by hand, round after round, while you stay close; the build line says what you're short of and
## where it comes from.

const TICK := SimWorld.TICK
var data := GameData.load_default()


func _node(sim: SimWorld, kind: String, purity: String = "") -> Dictionary:
	for n: Dictionary in sim.resource_nodes:
		if n["kind"] == kind and (purity == "" or n["purity"] == purity):
			return n
	return {}


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _at(sim: SimWorld, n: Dictionary) -> void:
	sim.player_pos = n["prop_pos"] + Vector3(1.5, 0, 0)


func test_gathering_scrap_by_hand() -> void:
	var sim := SimWorld.new(12.0)
	var heap := _node(sim, "scrap_heap", "normal")
	check(not heap.is_empty(), "a normal scrap heap")
	sim.player_pos = heap["pos"] + Vector3(30, 0, 0)
	check(sim.gather_start(heap["id"]).begins_with("Get closer"), "too far: get closer")
	_at(sim, heap)
	var before := sim.inventory.count("scrap_metal")
	check(sim.gather_start(heap["id"]).begins_with("You pull scrap from the heap by hand"), "E: you start gathering")
	var secs := sim.gather_seconds(heap)
	near(secs, float(data.resources["kinds"]["scrap_heap"]["hand"]["seconds"]), "a normal heap: the data's time", 0.01)
	sim.noise.recent.clear()
	_run(sim, secs + 0.1)
	eq(sim.inventory.count("scrap_metal"), before + 1, "a scrap metal")
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "gather_scrap_heap"), "and a clank zombies can hear")
	_run(sim, secs)
	eq(sim.inventory.count("scrap_metal"), before + 2, "it keeps going while you stay")
	eq(sim.stats.gathered, 2, "the session log counts it")
	check(sim.stats.summary_lines().has("Gathered by hand: 2 items."), "and says so")
	eq(sim.gather_start(heap["id"]), "Stopped gathering", "E again stops")
	_run(sim, secs * 2.0)
	eq(sim.inventory.count("scrap_metal"), before + 2, "and nothing more comes")


func test_walking_away_or_full_pockets_stop_it() -> void:
	var sim := SimWorld.new(12.0)
	var heap := _node(sim, "scrap_heap")
	_at(sim, heap)
	sim.gather_start(heap["id"])
	sim.player_pos = heap["pos"] + Vector3(20, 0, 0)
	_run(sim, 0.2)
	eq(sim.gathering, "", "walked away: it stops")
	_at(sim, heap)
	sim.gather_start(heap["id"])
	sim.inventory.add("scrap_metal", 2000)  # far too heavy to carry more
	_run(sim, sim.gather_seconds(heap) + 0.1)
	eq(sim.gathering, "", "pockets full: it stops")
	check(sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).begins_with("Your pockets are full")), "and says why")


func test_purity_and_the_other_nodes() -> void:
	var sim := SimWorld.new(12.0)
	var rich := _node(sim, "scrap_heap", "rich")
	var normal := _node(sim, "scrap_heap", "normal")
	check(sim.gather_seconds(rich) < sim.gather_seconds(normal), "a rich heap is quicker by hand too")
	for kind: String in ["well", "timber", "fuel_tank"]:
		var n := _node(sim, kind)
		check(not sim.hand_gather(n).is_empty(), "a %s can be worked by hand" % kind)
	var timber := _node(sim, "timber")
	_at(sim, timber)
	sim.gather_start(timber["id"])
	var planks := sim.inventory.count("plank")
	_run(sim, sim.gather_seconds(timber) + 0.1)
	eq(sim.inventory.count("plank"), planks + 1, "a timber stand gives planks")
	check(float(data.resources["kinds"]["fuel_tank"]["hand"]["seconds"]) >= 30.0, "gas by hand is slow")


func test_the_build_line_says_what_is_missing_and_where_it_comes_from() -> void:
	var sim := SimWorld.new(12.0)
	var empty := Inventory.new()
	var words := sim.missing_words("smelter", empty)
	check(words.contains("10 Plank (") and words.contains("10 Scrap metal ("), "both shortfalls with counts: '%s'" % words)
	check(words.contains("scrap heap"), "and scrap's sources include the scrap heap")
	var some := Inventory.new()
	some.give_all({"plank": 10, "scrap_metal": 4})
	eq(sim.missing_words("smelter", some).begins_with("6 Scrap metal"), true, "only what's still short")
	for item: String in ["plank", "scrap_metal", "nails", "metal_plate", "gas_can", "wall_panel"]:
		check(str(data.items[item].get("where", "")) != "", "%s says where it comes from" % item)


func test_the_node_says_how() -> void:
	var sim := SimWorld.new(12.0)
	var heap := _node(sim, "scrap_heap")
	var it := Interactor.new()
	it.sim = sim
	var text := it.node_status(heap["id"])
	check(text.contains("[E] pull scrap from the heap by hand"), "looking at a heap: E gathers by hand ('%s')" % text)
	check(text.contains("Or build a Salvager"), "or build its machine")
	_at(sim, heap)
	sim.gather_start(heap["id"])
	_run(sim, 1.0)
	check(it.node_status(heap["id"]).contains("Gathering scrap metal..."), "while gathering it shows how far along")
	it.free()
