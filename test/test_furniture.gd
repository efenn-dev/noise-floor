extends "res://test/base_test.gd"
## W1c: furniture is a piece. The town plan puts counters, tables, couches, shelves, bathtubs and toilets
## in the houses (and shelves and a table in the factory hall); they stand against walls, never block a
## doorway or wall anything in, are town pieces you can't build but can pull apart for a few planks,
## zombies wreck them like a crate, and they're saved with the other pieces.

const S := BuildGrid.Side
const PROPS := ["counter", "table", "couch", "shelf", "bathtub", "toilet"]
const LOW := ["counter", "table", "couch", "bathtub", "toilet"]  # may stand under a window; a shelf may not
const STEP := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _edges(plan: Dictionary) -> Dictionary:
	var edges := {}
	for p: Dictionary in plan["pieces"] + plan["factory"]["pieces"]:
		if p["id"] != "town_floor":
			edges[TownPlan.piece_key(p)] = p["id"]
	return edges


func test_props_are_town_pieces() -> void:
	var data := GameData.load_default()
	check(data.validate().is_empty(), "data validates (%s)" % " | ".join(data.validate()))
	for id: String in PROPS:
		var b: Dictionary = data.buildables[id]
		eq(b["kind"], "prop", "%s is a prop" % id)
		check(not b["player_placeable"] and not id in BuildController.PIECES, "%s isn't in the build menu" % id)
		check(b["against_wall"], "%s stands against a wall" % id)
		check(b["hp"] > 0 and b["hp"] <= 150, "%s has modest hp (%d)" % [id, b["hp"]])
		check(b["cost"].get("plank", 0) >= 1 and b["cost"].get("plank", 0) <= 3, "%s salvages for a few planks" % id)
		check(BuildView.MODELS.has(id), "%s is drawn from a model" % id)
	var broken := GameData.load_default()
	broken.buildables["couch"]["size"] = Vector3(2.0, 0.85, 0.85)
	check(not broken.validate().is_empty(), "a prop too wide for a cell is caught")


func test_same_seed_same_furniture() -> void:
	eq(TownPlan.generate(1)["props"], TownPlan.generate(1)["props"], "seed 1 twice gives the same furniture")
	var plan := TownPlan.generate(1)
	eq(plan["props"].size(), 12 * 6, "six pieces of furniture in every house")
	var per_room := {}
	for p: Dictionary in plan["props"]:
		per_room[p["id"]] = per_room.get(p["id"], 0) + 1
	eq(per_room["counter"], 12, "a kitchen counter in every house")
	eq(per_room["couch"], 12, "a couch in every house")
	check(per_room["shelf"] >= 24, "a shelf in every living room and bedroom (%d)" % per_room["shelf"])
	check(per_room.get("table", 0) > 0 and per_room.get("bathtub", 0) > 0 and per_room.get("toilet", 0) > 0,
			"tables, bathtubs and toilets in use (%s)" % per_room)


## Every prop is inside its house, has its back to a wall (a low one may stand under a window), faces away
## from it, and isn't on a door's cell, a container's, the bed's, or another prop's.
func test_props_stand_against_walls_out_of_the_way() -> void:
	for seed_value in [1, 5, 77]:
		var plan := TownPlan.generate(seed_value)
		var edges := _edges(plan)
		var taken := {}
		for c: Dictionary in plan["containers"]:
			taken[c["cell"]] = "container"
		for b: Dictionary in plan["beds"]:
			taken[b["cell"]] = "bed"
		for h: Dictionary in plan["houses"]:
			taken[h["door_cell"]] = "front door"
			for c: Vector2i in h["cells"]:
				for side in 4:
					if edges.get(BuildGrid.key_for_wall_edge(c, side), "") == "door":
						taken[c] = "door"
		for p: Dictionary in plan["props"]:
			var where := "seed %d %s %s at %s" % [seed_value, p["house"], p["id"], p["cell"]]
			var h := TownPlan.house_at(plan, p["cell"])
			check(h != -1 and plan["houses"][h]["name"] == p["house"], "%s is inside its house" % where)
			var back: String = edges.get(BuildGrid.key_for_wall_edge(p["cell"], p["wall"]), "")
			check(back == "town_wall" or (back == "window" and p["id"] in LOW), "%s has its back to a wall (%s)" % [where, back])
			eq(p["side"], (p["wall"] + 2) % 4, "%s faces into the room" % where)
			check(not taken.has(p["cell"]), "%s isn't on a %s cell" % [where, taken.get(p["cell"], "")])
			taken[p["cell"]] = "prop"


## The walk test: on half cells (1 m squares; each container, prop or bed fills the half of its cell along its
## wall, a bed its whole cell), every free square in a house can be reached from the front door's cell, and
## everything in the house has a reachable square beside it. So nothing is walled in and every doorway keeps
## a 1 m path. (Whole cells are too coarse: plan A's bathroom is only reached through the fridge's cell.)
func test_nothing_is_walled_in() -> void:
	for seed_value in [1, 5, 77]:
		var plan := TownPlan.generate(seed_value)
		var edges := _edges(plan)
		for h: Dictionary in plan["houses"]:
			var cells := {}
			for c: Vector2i in h["cells"]:
				cells[c] = true
			var blocked := {}
			var things: Array = []  # [name, its squares]
			for c: Dictionary in plan["containers"]:
				if cells.has(c["cell"]):
					things.append([c["id"], _half(c["cell"], c["side"])])
			for p: Dictionary in plan["props"]:
				if p["house"] == h["name"]:
					things.append([p["id"], _half(p["cell"], p["wall"])])
			for b: Dictionary in plan["beds"]:
				if cells.has(b["cell"]):
					things.append(["bed", _half(b["cell"], S.NORTH) + _half(b["cell"], S.SOUTH)])
			for t: Array in things:
				for q: Vector2i in t[1]:
					blocked[q] = true
			var start: Array = []
			for q: Vector2i in _half(h["door_cell"], S.NORTH) + _half(h["door_cell"], S.SOUTH):
				if not blocked.has(q):
					start.append(q)
			var seen := {}
			for q: Vector2i in start:
				seen[q] = true
			while not start.is_empty():
				var q: Vector2i = start.pop_back()
				for n: Vector2i in _steps(q, cells, edges):
					if not blocked.has(n) and not seen.has(n):
						seen[n] = true
						start.append(n)
			var stuck := 0
			for c: Vector2i in h["cells"]:
				for q: Vector2i in _half(c, S.NORTH) + _half(c, S.SOUTH):
					if not blocked.has(q) and not seen.has(q):
						stuck += 1
			eq(stuck, 0, "seed %d %s: every free square reachable from the front door" % [seed_value, h["name"]])
			for t: Array in things:
				var beside := false
				for q: Vector2i in t[1]:
					for n: Vector2i in _steps(q, cells, edges):
						beside = beside or seen.has(n)
				check(beside, "seed %d %s: you can walk up to the %s" % [seed_value, h["name"], t[0]])


## The two half-cell squares along `side` of `cell`, on a grid of 1 m squares.
func _half(cell: Vector2i, side: int) -> Array:
	var x := cell.x * 2
	var z := cell.y * 2
	match side:
		S.NORTH:
			return [Vector2i(x, z), Vector2i(x + 1, z)]
		S.SOUTH:
			return [Vector2i(x, z + 1), Vector2i(x + 1, z + 1)]
		S.WEST:
			return [Vector2i(x, z), Vector2i(x, z + 1)]
	return [Vector2i(x + 1, z), Vector2i(x + 1, z + 1)]


## Squares next to `q` you can step to: inside the same cell, or into a neighbouring house cell with no
## piece (wall, window or door) on the edge between.
func _steps(q: Vector2i, cells: Dictionary, edges: Dictionary) -> Array:
	var out: Array = []
	var cell := Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))
	for side in 4:
		var n: Vector2i = q + STEP[side]
		var ncell := Vector2i(floori(n.x / 2.0), floori(n.y / 2.0))
		if ncell == cell or (cells.has(ncell) and not edges.has(BuildGrid.key_for_wall_edge(cell, side))):
			out.append(n)
	return out


func test_factory_hall_furniture() -> void:
	var plan := TownPlan.generate(1)
	var f: Dictionary = plan["factory"]
	eq(f["props"].size(), 3, "three pieces in the hall")
	var ids := []
	var edges := _edges(plan)
	for p: Dictionary in f["props"]:
		ids.append(p["id"])
		check(p["cell"] in f["cells"], "%s at %s is in the hall" % [p["id"], p["cell"]])
		eq(edges.get(BuildGrid.key_for_wall_edge(p["cell"], p["wall"]), ""), "town_wall", "%s has its back to the wall" % p["id"])
		check(not p["cell"] in f["crates"] and p["cell"] != f["pete"]["cell"], "%s isn't on a crate or Old Pete" % p["id"])
		var door := Vector2i(TownPlan.FACTORY_DOOR[0], TownPlan.FACTORY_CELL.y + TownPlan.FACTORY_SIZE.y - 1)
		check((p["cell"] - door).length() > 5.0, "%s is well away from the doorway" % p["id"])
	ids.sort()
	eq(ids, ["shelf", "shelf", "table"], "two shelves and a table")


func test_placed_furniture_is_a_piece() -> void:
	var sim := SimWorld.new(10.0)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	sim.place_factory(plan)
	var n := sim.place_props(plan)
	eq(n, plan["props"].size() + 3, "every prop laid, the hall's too")
	eq(sim.place_props(plan), 0, "laying them again adds nothing")
	var p: Dictionary = plan["props"][0]
	var key := sim.build.key_for(p["id"], p["cell"])
	check(sim.build.pieces.has(key) and sim.build.is_object(p["id"]), "a prop is an object piece (%s)" % key)
	eq(sim.build.kind_of(p["id"]), "prop", "of kind prop")
	# Its box's back is just off the wall's face, its front faces the room.
	var size: Vector3 = sim.data.buildables[p["id"]]["size"]
	var mid := Vector3((p["cell"].x + 0.5) * 2.0, 0, (p["cell"].y + 0.5) * 2.0)
	var out := Vector3([0, 1, 0, -1][p["wall"]], 0, [-1, 0, 1, 0][p["wall"]])
	var c := sim.build.piece_center(key)
	near((c - mid).dot(out) + size.z / 2.0, 1.0 - BuildGrid.WALL_HALF - BuildGrid.WALL_GAP, "%s's back is against the wall" % p["id"], 0.001)
	near(c.y, sim.build.foundation_top() + size.y / 2.0, "and it stands on the floor")
	check(not sim.stats.built.has(p["id"]), "the town's furniture isn't counted as your builds")
	# You can't build one, can't put a crate on it, and pulling it apart gives a few planks.
	sim.give_debug_kit()
	var free := Vector2i(50, 50)
	sim.build.restore("f:50:50", {"id": "foundation", "cell": free, "side": 0, "hp": 400})
	eq(sim.build.can_place("couch", free, S.NORTH, sim.inventory), "Only found in town", "you can't build a couch")
	eq(sim.build.can_place("storage", p["cell"], S.NORTH, sim.inventory), "Already built", "nor build on top of one")
	var inv := Inventory.new()
	eq(sim.build.remove(key, inv), "", "pull it apart")
	eq(inv.count("plank"), sim.data.buildables[p["id"]]["cost"]["plank"], "for its planks")
	check(not sim.build.pieces.has(key), "and it's gone")


func test_zombies_wreck_furniture() -> void:
	var sim := SimWorld.new(10.0)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	sim.place_props(plan)
	var p: Dictionary = plan["props"][0]
	var key := sim.build.key_for(p["id"], p["cell"])
	var hp: int = sim.data.buildables[p["id"]]["hp"]
	check(not sim.build.damage(key, hp - 1), "a hit short of its hp leaves it standing")
	check(sim.build.damage(key, 1), "the last one wrecks it")
	check(not sim.build.pieces.has(key), "wrecked: gone, with nothing to salvage")


## House zombies (W1b) never stand inside the furniture.
func test_house_zombies_not_in_furniture() -> void:
	for seed_value in [1, 5, 77]:
		var plan := TownPlan.generate(seed_value)
		var props := {}
		for p: Dictionary in plan["props"]:
			props[p["cell"]] = true
		for z: Dictionary in plan["zombies"]:
			check(not props.has(z["cell"]), "seed %d: the zombie at %s isn't in the furniture" % [seed_value, z["cell"]])


func test_furniture_survives_save_and_load() -> void:
	var a := SimWorld.new(10.0, null, 42)
	var plan := TownPlan.generate(42)
	a.place_town(plan)
	a.place_factory(plan)
	a.place_props(plan)
	var gone := a.build.key_for(plan["props"][0]["id"], plan["props"][0]["cell"])
	var hurt := a.build.key_for(plan["props"][1]["id"], plan["props"][1]["cell"])
	a.build.remove(gone, a.inventory)
	a.build.damage(hurt, 10)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	check(SaveGame.holds_props(d), "a version-%d save holds the furniture" % SaveGame.VERSION)
	var b := SimWorld.new(8.0, null, 42)
	eq(SaveGame.apply(b, d), "", "loads cleanly")
	eq(b.build.pieces.size(), a.build.pieces.size(), "every piece back, once")
	check(not b.build.pieces.has(gone), "the piece you pulled apart stays gone")
	eq(b.build.pieces[hurt]["hp"], a.data.buildables[plan["props"][1]["id"]]["hp"] - 10, "the damaged one is still damaged")
	eq(b.build.pieces[hurt]["side"], plan["props"][1]["side"], "and still faces the room")
