extends "res://test/base_test.gd"
## W1a: the town's houses muffle sound like the player's walls, because they are the same pieces.
## Closed doors and whole windows count as walls; an open door or a broken window lets sound out;
## a barricade on the broken window shuts it again; the Director hears less of a smelter indoors.


func _town() -> Array:
	var sim := SimWorld.new(12.0)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	return [sim, plan]


static func _mid(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * BuildGrid.GRID, 1.0, (c.y + 0.5) * BuildGrid.GRID)


static func _out(side: int) -> Vector3:
	return [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][side]


func test_front_door_lets_sound_out() -> void:
	var t := _town()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	for h: Dictionary in plan["houses"]:
		var inside := _mid(h["door_cell"])
		var street := inside + _out(h["door_side"]) * 8.0
		var door := BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"])
		var shut := sim.noise.walls_between(inside, street)
		check(shut >= 1, "%s: a closed front door muffles (%d)" % [h["name"], shut])
		sim.toggle_door(door)
		check(sim.noise.walls_between(inside, street) < shut, "%s: opening it lets sound out" % h["name"])
		sim.toggle_door(door)
		eq(sim.noise.walls_between(inside, street), shut, "%s: closing it muffles again" % h["name"])


func test_broken_window_and_barricade() -> void:
	var t := _town()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var tried := 0
	for p: Dictionary in plan["pieces"]:
		if p["id"] != "window":
			continue
		var a: Vector2i = p["cell"]
		var b: Vector2i = a + (Vector2i(0, -1) if p["side"] == BuildGrid.Side.NORTH else Vector2i(-1, 0))
		var inside_cell := a if TownPlan.house_at(plan, a) != -1 else b
		var outside_cell := b if inside_cell == a else a
		var inside := _mid(inside_cell)
		var outside := inside + (_mid(outside_cell) - inside) * 4.0
		var key := TownPlan.piece_key(p)
		var whole := sim.noise.walls_between(inside, outside)
		check(whole >= 1, "a whole window muffles (%s)" % key)
		sim.build.damage(key, 100)
		check(sim.noise.walls_between(inside, outside) < whole, "a broken one lets sound out (%s)" % key)
		sim.inventory.give_all({"plank": 10, "nails": 10})
		eq(sim.build.place("barricade", inside_cell, _side_toward(inside_cell, outside_cell), sim.inventory), "",
				"board it up (%s)" % key)
		eq(sim.noise.walls_between(inside, outside), whole, "the barricade muffles it again (%s)" % key)
		tried += 1
		if tried == 3:
			break
	eq(tried, 3, "tried three windows")


func test_director_hears_less_of_a_smelter_indoors() -> void:
	var t := _town()
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var h: Dictionary = plan["houses"][0]
	var cell: Vector2i = h["door_cell"]  # the front room, by the door
	var open_sim := SimWorld.new(12.0)
	open_sim.build.restore("f:%d:%d" % [cell.x, cell.y], {"id": "foundation", "cell": cell, "side": 0, "hp": 400})
	var levels := []
	for s: SimWorld in [sim, open_sim]:
		s.power.free = true
		s.inventory.give_all({"plank": 20, "scrap_metal": 20})
		eq(s.build.place("smelter", cell, BuildGrid.Side.NORTH, s.inventory), "", "a smelter on the floor")
		s.factory.machines[cell].input["scrap_metal"] = 10
		for i in 10:
			s.step()
		eq(s.noise.continuous.size(), 1, "it's running")
		levels.append(s.noise.outdoor_level(s.noise.continuous[0], float(s.data.noise["director"]["listen_distance"])))
	check(levels[0] < levels[1], "quieter outside a closed house (%.1f vs %.1f in the open)" % [levels[0], levels[1]])
	near(levels[1] - levels[0], 10.0, "one wall's worth quieter", 0.01)
	var gain_in := sim.director.gain_now(sim.noise, false)
	var gain_out := open_sim.director.gain_now(open_sim.noise, false)
	check(gain_in < gain_out, "the Director's heat rises slower (%.3f vs %.3f)" % [gain_in, gain_out])


static func _side_toward(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	if d == Vector2i(0, -1):
		return BuildGrid.Side.NORTH
	if d == Vector2i(1, 0):
		return BuildGrid.Side.EAST
	if d == Vector2i(0, 1):
		return BuildGrid.Side.SOUTH
	return BuildGrid.Side.WEST
