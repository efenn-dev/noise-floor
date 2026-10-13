extends "res://test/base_test.gd"
## W1a: the town plan. The same seed gives the same houses; doors face the road; loot and beds are
## inside; no two houses overlap; the twelve lots are where the old box houses stood.

const S := BuildGrid.Side


func _data() -> GameData:
	return GameData.load_default()


func test_same_seed_same_town() -> void:
	var a := TownPlan.generate(1)
	var b := TownPlan.generate(1)
	eq(a, b, "seed 1 twice gives the same plan")
	var plans_a := []
	var plans_c := []
	var c := TownPlan.generate(77)
	for i in a["houses"].size():
		plans_a.append([a["houses"][i]["plan"], a["houses"][i]["mirror"]])
		plans_c.append([c["houses"][i]["plan"], c["houses"][i]["mirror"]])
	check(plans_a != plans_c, "another seed picks other plans or mirrors")
	var used := {}
	for h: Dictionary in a["houses"]:
		used[h["plan"]] = true
	eq(used.size(), 3, "seed 1 uses all three floor plans")


func test_houses_have_front_doors_on_the_road_side() -> void:
	var plan := TownPlan.generate(1)
	eq(plan["houses"].size(), 12, "twelve houses")
	var pieces := {}
	for p: Dictionary in plan["pieces"]:
		pieces[TownPlan.piece_key(p)] = p
	for h: Dictionary in plan["houses"]:
		var door_key := BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"])
		check(pieces.has(door_key) and pieces[door_key]["id"] == "door", "%s has a front door" % h["name"])
		eq(h["door_side"], S.WEST if h["east"] else S.EAST, "%s's door faces the road" % h["name"])
		var nearest := INF
		for c: Vector2i in h["cells"]:
			nearest = minf(nearest, absf((c.x + 0.5) * BuildGrid.GRID))
		near(absf((h["door_cell"].x + 0.5) * BuildGrid.GRID), nearest, "%s's door is in its front row" % h["name"])
		var doors := 0
		var windows := 0
		for p: Dictionary in plan["pieces"]:
			if p["id"] in ["door", "window"] and _touches(h["cells"], p):
				doors += 1 if p["id"] == "door" else 0
				windows += 1 if p["id"] == "window" else 0
		eq(doors, 2, "%s has a front and a back door" % h["name"])
		check(windows >= 3 and windows <= 4, "%s has 3 or 4 windows (%d)" % [h["name"], windows])


func test_every_edge_of_a_house_is_closed() -> void:
	# Walk round each house: every outside edge has a wall, a door or a window, so it's a closed room.
	var plan := TownPlan.generate(5)
	var pieces := {}
	var doubled := []
	for p: Dictionary in plan["pieces"]:
		var k := TownPlan.piece_key(p)
		if pieces.has(k):
			doubled.append(k)
		pieces[k] = p
	eq(doubled, [], "no two pieces on one spot")
	for h: Dictionary in plan["houses"]:
		var cells := {}
		for c: Vector2i in h["cells"]:
			cells[c] = true
		var open := 0
		var floors := 0
		for c: Vector2i in h["cells"]:
			floors += 1 if pieces.has("f:%d:%d" % [c.x, c.y]) else 0
			for side in 4:
				var n: Vector2i = c + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
				if not cells.has(n) and not pieces.has(BuildGrid.key_for_wall_edge(c, side)):
					open += 1
		eq(open, 0, "%s has no gaps in its outside walls" % h["name"])
		eq(floors, h["cells"].size(), "%s has a floor under every cell" % h["name"])


func test_loot_and_beds_are_inside() -> void:
	var plan := TownPlan.generate(1)
	var all := {}
	var shared := []
	for h: Dictionary in plan["houses"]:
		for c: Vector2i in h["cells"]:
			if all.has(c):
				shared.append(c)
			all[c] = true
	eq(shared, [], "no two houses share a cell")
	eq(plan["containers"].size(), 36, "three containers per house")
	for c: Dictionary in plan["containers"]:
		var h := TownPlan.house_at(plan, c["cell"])
		check(h != -1 and c["id"].begins_with(plan["houses"][h]["name"]), "%s is inside its house" % c["id"])
		check(c["table"] in ["fridge", "kitchen", "bathroom"], "%s uses a house loot table" % c["id"])
		eq(_edge_id(plan, c["cell"], c["side"]), "town_wall", "%s stands against a wall" % c["id"])
	eq(plan["beds"].size(), 12, "a bed per house")
	for b: Dictionary in plan["beds"]:
		check(TownPlan.house_at(plan, b["cell"]) != -1, "bed at %s is inside a house" % b["cell"])
		eq(_edge_id(plan, b["cell"], b["side"]), "town_wall", "bed at %s has its head to a wall" % b["cell"])
	var data := _data()
	var sim := SimWorld.new(10.0)
	var placed := sim.place_town(plan)
	eq(placed, plan["pieces"].size() + 12, "every piece and bed is laid")
	for c: Dictionary in plan["containers"]:
		var pos := SimWorld.town_container_pos(c)
		eq(BuildGrid.world_to_cell(pos), c["cell"], "%s stands in its own cell" % c["id"])
	check(data.validate().is_empty(), "data still validates (%s)" % " | ".join(data.validate()))


func test_lots_are_where_the_old_houses_were() -> void:
	var plan := TownPlan.generate(1)
	for i in 6:
		for east in [false, true]:
			var h: Dictionary = plan["houses"][i * 2 + (1 if east else 0)]
			eq(h["name"], "house_%d_%s" % [i, "e" if east else "w"], "lot order")
			var min_z := INF
			var max_z := -INF
			var min_x := INF
			var max_x := -INF
			for c: Vector2i in h["cells"]:
				min_z = minf(min_z, c.y * 2.0)
				max_z = maxf(max_z, c.y * 2.0 + 2.0)
				min_x = minf(min_x, c.x * 2.0)
				max_x = maxf(max_x, c.x * 2.0 + 2.0)
			check(absf((min_z + max_z) / 2.0 - (-10.0 - i * 16.0)) <= 1.0, "%s is centred on its old lot" % h["name"])
			if east:
				check(min_x == 8.0 and max_x <= 17.0, "%s stands east of the road, off the lawn" % h["name"])
			else:
				check(max_x == -8.0 and min_x >= -17.0, "%s stands west of the road, off the lawn" % h["name"])


func test_town_pieces_are_not_in_the_build_menu() -> void:
	var data := _data()
	for id: String in ["town_floor", "town_wall", "window"]:
		check(data.buildables.has(id), "%s exists" % id)
		check(not data.buildables[id]["player_placeable"], "%s isn't player placeable" % id)
		check(not id in BuildController.PIECES, "%s isn't in the build menu" % id)
	eq(data.buildables["town_wall"]["hp"], 600, "house walls are tough")
	check(data.buildables["wall"]["player_placeable"], "the player's own wall still is")


func _touches(cells: Array, p: Dictionary) -> bool:
	var a: Vector2i = p["cell"]
	var b: Vector2i = a + (Vector2i(0, -1) if p["side"] == S.NORTH else Vector2i(-1, 0))
	return a in cells or b in cells


func _edge_id(plan: Dictionary, cell: Vector2i, side: int) -> String:
	var k := BuildGrid.key_for_wall_edge(cell, side)
	for p: Dictionary in plan["pieces"]:
		if p["id"] != "town_floor" and TownPlan.piece_key(p) == k:
			return p["id"]
	return ""
