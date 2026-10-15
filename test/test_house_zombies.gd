extends "res://test/base_test.gd"
## W1b: a zombie inside some houses. The plan picks which houses (the same for the same seed, never the
## two by the spawn) and where it stands; it stays inside with nothing going on; searching the kitchen
## of its house brings it; it survives a save and load once, not twice.

const TICK := SimWorld.TICK
const FAR := Vector3(0, 0, 500)


func _town(seed_value: int) -> Array:
	var sim := SimWorld.new(12.0, null, seed_value)
	var plan := TownPlan.generate(seed_value)
	sim.place_town(plan)
	return [sim, plan]


## Thinks for `seconds` and walks each zombie straight at what it wants (the world body's job), with
## nobody to see. Returns the cells it stood on.
func _live(sim: SimWorld, ids: Array, seconds: float) -> Dictionary:
	var stood := {}
	for i in roundi(seconds / TICK):
		for id: int in ids:
			var z: ZombieBrain = sim.horde.zombies[id]
			z.think(TICK, FAR, false, false, sim.build.pieces)
			var to := Vector3(z.target_pos.x - z.pos.x, 0, z.target_pos.z - z.pos.z)
			if to.length() > 0.05:
				z.pos += to.normalized() * minf(to.length(), z.move_speed() * TICK)
			stood[BuildGrid.world_to_cell(z.pos)] = true
	return stood


func test_which_houses_is_fixed_by_the_seed() -> void:
	var a := TownPlan.generate(1)
	eq(a["zombies"], TownPlan.generate(1)["zombies"], "seed 1 twice: the same house zombies")
	var picks := {}
	for seed_value in [1, 2, 3, 42, 77]:
		var plan := TownPlan.generate(seed_value)
		var houses := []
		for hz: Dictionary in plan["zombies"]:
			var house: Dictionary = plan["houses"][hz["house"]]
			houses.append(hz["house"])
			check(not house["name"].begins_with("house_0_"), "seed %d: none on the lot by the spawn" % seed_value)
			check(hz["cell"] in house["cells"], "seed %d: %s's zombie stands inside it" % [seed_value, house["name"]])
			check(hz["cell"] != house["door_cell"], "seed %d: not in the doorway" % seed_value)
			eq(BuildGrid.world_to_cell(hz["pos"]), hz["cell"], "seed %d: placed in its cell" % seed_value)
			for c: Dictionary in plan["containers"]:
				if c["id"].begins_with(house["name"] + "_"):
					check(c["cell"] != hz["cell"], "seed %d: not on top of %s" % [seed_value, c["id"]])
		eq(houses.size(), TownPlan.HOUSE_ZOMBIES, "seed %d: %d of the 12 houses" % [seed_value, TownPlan.HOUSE_ZOMBIES])
		picks[str(houses)] = true
	check(picks.size() > 1, "other seeds pick other houses")


func test_the_game_spawns_one_per_picked_house() -> void:
	var t := _town(7)
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var ids := sim.spawn_house_zombies(plan)
	eq(ids.size(), plan["zombies"].size(), "one zombie per picked house")
	for i in ids.size():
		var z: ZombieBrain = sim.horde.zombies[ids[i]]
		eq(TownPlan.house_at(plan, BuildGrid.world_to_cell(z.pos)), plan["zombies"][i]["house"], "zombie %d is in its house" % i)
		eq(z.state_name(), "idle", "and idle")


func test_stays_inside_when_nothing_happens() -> void:
	var t := _town(1)
	var sim: SimWorld = t[0]
	var plan: Dictionary = t[1]
	var ids := sim.spawn_house_zombies(plan)
	var stood := _live(sim, ids, 300.0)  # five minutes, nobody near, no noise
	for i in ids.size():
		var z: ZombieBrain = sim.horde.zombies[ids[i]]
		var cells: Array = plan["houses"][plan["zombies"][i]["house"]]["cells"]
		eq(z.state_name(), "idle", "zombie %d still idle" % i)
		check(BuildGrid.world_to_cell(z.pos) in cells, "zombie %d still inside its house" % i)
	var out := 0
	for c: Vector2i in stood:
		if TownPlan.house_at(plan, c) == -1:
			out += 1
	eq(out, 0, "never stood on a cell outside a house")
	# The same zombie out on the street does go for strolls.
	var street := sim.horde.spawn("shambler", Vector3(5, 0, -40))
	var street_cells := _live(sim, [street.id], 60.0)
	check(street_cells.size() > 1, "a street zombie wanders (%d cells)" % street_cells.size())


func test_searching_its_kitchen_brings_it() -> void:
	for seed_value in [1, 42]:
		var t := _town(seed_value)
		var sim: SimWorld = t[0]
		var plan: Dictionary = t[1]
		for c: Dictionary in plan["containers"]:
			sim.loot.add(c["id"], c["table"], SimWorld.town_container_pos(c))
		var ids := sim.spawn_house_zombies(plan)
		for i in ids.size():
			var z: ZombieBrain = sim.horde.zombies[ids[i]]
			if z.type == "crawler":
				continue  # V28: a crawler hears less by design (test_zombie_types covers it); this is about the others
			var house: Dictionary = plan["houses"][plan["zombies"][i]["house"]]
			var nearest := ""
			for c: Dictionary in plan["containers"]:
				if c["id"].begins_with(house["name"] + "_") and c["table"] != "bathroom":
					if nearest == "" or z.pos.distance_to(sim.loot.containers[c["id"]]["pos"]) \
							< z.pos.distance_to(sim.loot.containers[nearest]["pos"]):
						nearest = c["id"]
			var at: Vector3 = sim.loot.containers[nearest]["pos"]
			sim.player_pos = Vector3(at.x, 0, at.z)
			eq(sim.search(nearest), "", "seed %d: search %s" % [seed_value, nearest])
			for k in 20:
				sim.step()
			eq(z.state_name(), "investigate", "seed %d: %s's zombie heard the search" % [seed_value, house["name"]])
			check(Vector2(z.target_pos.x - at.x, z.target_pos.z - at.z).length() < 0.5, "and comes to the %s" % nearest)
			sim.player_pos = FAR
			for k in 20 * 6:
				sim.step()  # let the search finish before the next house


func test_survives_save_and_load_once() -> void:
	var t := _town(42)
	var a: SimWorld = t[0]
	var plan: Dictionary = t[1]
	a.place_factory(plan)
	a.horde.spawn_town(8)
	var ids := a.spawn_house_zombies(plan)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	check(SaveGame.holds_factory(d), "a version-4 save holds the factory")
	var b := SimWorld.new(8.0, null, 42)
	eq(SaveGame.apply(b, d), "", "loads cleanly")
	eq(b.horde.zombies.size(), 8 + ids.size(), "8 street zombies and the house zombies, once")
	for id: int in ids:
		check(b.horde.zombies.has(id), "house zombie %d is back" % id)
		check(b.horde.zombies[id].pos.distance_to(a.horde.zombies[id].pos) < 0.01, "where it stood")
		check(ZombieBrain._indoors(b.build.pieces, b.horde.zombies[id].home), "and it's still at home indoors")
