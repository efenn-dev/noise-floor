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
