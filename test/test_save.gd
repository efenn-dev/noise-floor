extends "res://test/base_test.gd"
## Save -> JSON text -> load gives back the same world, and it carries on the same way.

const TICK := SimWorld.TICK
const E := BuildGrid.Side.EAST
const N := BuildGrid.Side.NORTH


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## The town's containers and cars, as main.gd would register them.
func _town(sim: SimWorld) -> void:
	sim.loot.add("car_0", "car_trunk", Vector3(0, 0, -15))
	sim.add_car("car_0")
	sim.loot.add("house_0_e", "kitchen", Vector3(6.6, 0.8, -10))


func _busy_world() -> SimWorld:
	var sim := SimWorld.new(15.5, null, 42)
	_town(sim)
	sim.inventory.give_all({"plank": 300, "nails": 500, "metal_plate": 100, "scrap_metal": 40, "gas_can": 5})
	var stash := sim.place_start_stash(Vector2i(5, 5))
	for x in range(0, 4):
		sim.build.place("foundation", Vector2i(x, 0), 0, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory)
	sim.build.place("belt", Vector2i(1, 0), E, sim.inventory)
	sim.build.place("press", Vector2i(2, 0), E, sim.inventory)
	sim.build.place("generator", Vector2i(3, 0), E, sim.inventory)
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(3, 0)), sim.inventory)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 15
	sim.build.place("door", Vector2i(0, 0), N, sim.inventory)
	sim.toggle_door(sim.build.key_for("door", Vector2i(0, 0), N))
	sim.build.place("foundation", Vector2i(0, 2), 0, sim.inventory)
	sim.build.place("nail_turret", Vector2i(0, 2), N, sim.inventory)
	sim.factory.turrets[Vector2i(0, 2)].ammo = 77
	sim.build.place("wall", Vector2i(1, 0), N, sim.inventory)
	sim.build.damage(sim.build.key_for("wall", Vector2i(1, 0), N), 60)
	sim.storages[stash].add("chips", 3)
	sim.horde.spawn("shambler", Vector3(30, 0, 30)).hp = 55
	sim.horde.spawn("shambler", Vector3(-40, 0, 20))
	sim.director.heat = 33.0
	sim.player_pos = Vector3(2, 0, 9)
	sim.player.food = 61.0
	sim.player.bleeding = true
	sim.player_pos = Vector3(0.5, 0, -14)
	sim.siphon("car_0")
	sim.player_pos = Vector3(2, 0, 9)
	sim.drop_bag(Vector3(9, 0, 9), {"bandage": 2})
	_run(sim, 7.3)  # mid-craft, items on the belt
	return sim


func test_round_trip_keeps_everything() -> void:
	var a := _busy_world()
	var text := JSON.stringify(SaveGame.to_dict(a))
	var b := SimWorld.new(8.0, null, 42)
	_town(b)
	eq(SaveGame.apply(b, JSON.parse_string(text)), "", "loads cleanly")
	near(b.clock.time_of_day, a.clock.time_of_day, "clock")
	eq(b.ticks, a.ticks, "tick count")
	eq(b.build.pieces.size(), a.build.pieces.size(), "every piece is back")
	var wall := a.build.key_for("wall", Vector2i(1, 0), N)
	eq(b.build.pieces[wall]["hp"], 140, "damage kept")
	check(b.build.pieces[a.build.key_for("door", Vector2i(0, 0), N)]["open"], "door still open")
	eq(b.factory.machines[Vector2i(0, 0)].crafted, a.factory.machines[Vector2i(0, 0)].crafted, "smelter count")
	near(b.factory.machines[Vector2i(0, 0)].progress, a.factory.machines[Vector2i(0, 0)].progress, "mid-craft progress")
	eq(b.factory.belts[Vector2i(1, 0)].items.size(), a.factory.belts[Vector2i(1, 0)].items.size(), "items on the belt")
	eq(b.factory.turrets[Vector2i(0, 2)].ammo, 77, "turret ammo")
	var gen := a.build.key_for("generator", Vector2i(3, 0))
	near(b.power.fuel_seconds(gen), a.power.fuel_seconds(gen), "generator fuel")
	eq(b.storages[a.build.key_for("storage", Vector2i(5, 5))].count("chips"), 3, "crate contents")
	eq(b.inventory.count("gas_can"), a.inventory.count("gas_can"), "pockets")
	near(b.player.food, a.player.food, "food meter")
	check(b.player.bleeding, "still bleeding")
	check(b.player_pos.is_equal_approx(Vector3(2, 0, 9)), "where you stood")
	eq(b.horde.zombies.size(), 2, "both zombies")
	near(b.horde.zombies[1].hp, 55.0, "a hurt zombie stays hurt")
	near(b.director.heat, a.director.heat, "heat")
	eq(b.vehicles.cars["car_0"]["fuel"], 0.0, "the siphoned car stays dry")
	eq(b.bags.size(), 1, "death bag")
	eq(b.bags[0]["items"], {"bandage": 2}, "with its contents")


func test_loaded_world_carries_on_the_same() -> void:
	var a := _busy_world()
	var b := SimWorld.new(8.0, null, 42)
	_town(b)
	SaveGame.apply(b, JSON.parse_string(JSON.stringify(SaveGame.to_dict(a))))
	_run(a, 30.0)
	_run(b, 30.0)
	eq(b.factory.machines[Vector2i(0, 0)].crafted, a.factory.machines[Vector2i(0, 0)].crafted, "same smelting after 30 s")
	eq(b.factory.machines[Vector2i(2, 0)].output, a.factory.machines[Vector2i(2, 0)].output, "same nails")
	near(b.player.health, a.player.health, "same bleeding damage", 0.01)


func test_searched_containers_stay_searched() -> void:
	var a := SimWorld.new(10.0)
	_town(a)
	a.player_pos = Vector3(6, 0, -10)
	a.search("house_0_e")
	_run(a, 3.0)
	var b := SimWorld.new(10.0)
	_town(b)
	SaveGame.apply(b, SaveGame.to_dict(a))
	b.player_pos = Vector3(6, 0, -10)
	eq(b.search("house_0_e"), "Already searched", "loot doesn't come back by reloading")


func test_file_write_and_read() -> void:
	var path := "user://test_save.json"
	var a := _busy_world()
	eq(SaveGame.write(a, path, {"look": [10.0, -5.0]}), "", "write")
	var d := SaveGame.read(path)
	eq(d.get("look", []), [10.0, -5.0], "extra world data comes back")
	eq(int(d.get("version", 0)), SaveGame.VERSION, "versioned")
	eq(SaveGame.read("user://no_such_save.json"), {}, "missing file: empty")
	var bad := SimWorld.new()
	check(SaveGame.apply(bad, {"version": 999}) != "", "refuses other versions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## W1a: a version-2 save (made by the game before houses were pieces) still loads. It doesn't hold
## the town, so the town plan lays the houses first and the save goes on top, as main.gd does.
func test_version_2_save_still_loads() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v2.json")
	eq(int(d.get("version", 0)), 2, "the fixture is a version-2 save")
	check(not SaveGame.holds_town(d), "it predates the town pieces")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	_town(sim)
	var laid := sim.place_town(TownPlan.generate(sim.seed_value))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.build.pieces.size(), laid + d["pieces"].size(), "the houses plus everything you built")
	var door := sim.build.key_for("door", Vector2i(-1, -1), N)
	check(sim.build.pieces.has(door) and sim.build.pieces[door]["open"], "your door is still open")
	eq(sim.build.pieces[sim.build.key_for("wall", Vector2i(-2, -1), N)]["hp"], 150, "your wall is still damaged")
	eq(sim.search("house_0_e"), "Already searched", "what you'd searched stays searched")
	near(sim.player.food, 70.0, "your food meter", 0.5)
	eq(sim.tally, {"kills": 0, "deaths": 0}, "defaults for what version 2 didn't save")


## W1b: a version-3 save (made by the W1a game, houses as pieces but the factory a solid block) still
## loads. It holds the houses but not the factory hall, so main.gd lays only the hall before applying it.
func test_version_3_save_still_loads() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v3.json")
	eq(int(d.get("version", 0)), 3, "the fixture is a version-3 save")
	check(SaveGame.holds_town(d), "it holds the houses")
	check(not SaveGame.holds_factory(d), "but not the factory hall")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	_town(sim)
	var plan := TownPlan.generate(sim.seed_value)
	var laid := sim.place_factory(plan)
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.build.pieces.size(), laid + d["pieces"].size(), "the hall plus the saved houses and your base")
	var h: Dictionary = plan["houses"][3]
	check(sim.build.pieces[BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"])]["open"], "the house door you opened is still open")
	check(sim.build.pieces[sim.build.key_for("door", Vector2i(-1, -1), N)]["open"], "and your own door")
	eq(sim.horde.zombies.size(), d["zombies"].size(), "its zombies, once")
	check(not sim.build.pieces.has(plan["factory"]["doorway"][0]), "the hall's doorway is open")


## W1a: the town is saved like your own pieces: damage, open doors and broken windows come back,
## and a version-3 save says it holds the town, so it isn't laid twice.
func test_town_damage_and_doors_survive_save_and_load() -> void:
	var a := SimWorld.new(10.0, null, 42)
	_town(a)
	var plan := TownPlan.generate(42)
	a.place_town(plan)
	var h: Dictionary = plan["houses"][3]
	var door := BuildGrid.key_for_wall_edge(h["door_cell"], h["door_side"])
	a.toggle_door(door)
	var wall := ""
	var window := ""
	for p: Dictionary in plan["pieces"]:
		if wall == "" and p["id"] == "town_wall":
			wall = TownPlan.piece_key(p)
		if window == "" and p["id"] == "window":
			window = TownPlan.piece_key(p)
	a.build.damage(wall, 250)
	a.build.damage(window, 99)
	var gone := ""
	for p: Dictionary in plan["pieces"]:
		if p["id"] == "town_wall" and p["style"] == "plaster":
			gone = TownPlan.piece_key(p)
			break
	eq(a.build.remove(gone, a.inventory), "", "knock an inside wall down")
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(a)))
	eq(int(d["version"]), SaveGame.VERSION, "saved as the current version")
	check(SaveGame.holds_town(d), "it holds the town")
	var b := SimWorld.new(8.0, null, 42)
	_town(b)
	eq(SaveGame.apply(b, d), "", "loads cleanly")
	eq(b.build.pieces.size(), a.build.pieces.size(), "every town piece is back, once")
	check(b.build.pieces[door]["open"], "the front door is still open")
	eq(b.build.pieces[wall]["hp"], 350, "the wall is still damaged")
	check(b.build.is_broken(window), "the window is still broken")
	check(not b.build.edge_blocks(window), "and still lets sound through")
	check(not b.build.pieces.has(gone), "the wall you knocked down stays down")
