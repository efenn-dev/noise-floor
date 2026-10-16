extends "res://test/base_test.gd"
## F6 part 2 (compact and deep): the base log lists every machine you built with what it's doing, stuck ones
## first; "what your base made" says how many days of food and water that comes to; the Press makes gunpowder and
## shotgun shells; the canner packs med kits that heal and stop bleeding.

const N := 0
const E := 1
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func _machine(sim: SimWorld, id: String, cell: Vector2i, facing: int = E) -> Factory.Machine:
	var stock := _rich()
	sim.build.place("foundation", cell, N, stock)
	eq(sim.build.place(id, cell, facing, stock), "", "a %s" % id)
	return sim.factory.machines[cell]


func test_the_machine_report_puts_stuck_machines_first() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	eq(sim.machine_lines().size(), 0, "no machines built: nothing listed")
	var rain := _machine(sim, "rain_collector", Vector2i(60, 60))
	var purifier := _machine(sim, "purifier", Vector2i(64, 60))
	for i in 5:
		sim.factory.tick(TICK)
	var report := sim.machine_report()
	eq(report.size(), 2, "both machines listed")
	eq(report[0]["name"], "Purifier", "the stuck one first")
	check(report[0]["trouble"], "it's stuck")
	eq(report[0]["status"], "needs %s" % data.item_name("dirty_water"), "and says what it's waiting for")
	check(not report[1]["trouble"] and str(report[1]["status"]).begins_with("working"), "the rain collector is working")
	check(sim.machine_lines()[0].begins_with("Purifier"), "the lines read the same way")
	sim.power.free = false
	purifier.input["dirty_water"] = 5
	sim.power.tick(TICK, 1.0)
	check(sim.machine_report()[0]["status"] == "no power", "no generator: it says no power")
	check(rain.crafting, "(the rain collector needs none)")


func test_days_of_food_and_water() -> void:
	var sim := SimWorld.new(12.0)
	var need := sim.needs_per_day()
	var cans := roundi(float(need["food"]) * 3.0 / data.item_value("canned_food", "food"))  # about three days' eating
	var days := sim.days_made({"canned_food": cans, "clean_water": 0})
	check(roundi(float(days["food"])) == 3, "%d cans come to about three days of food (%.1f)" % [cans, float(days["food"])])
	near(float(days["water"]), 0.0, "and no water")
	sim.made_yesterday = {"canned_food": cans}
	check(sim.supplies_lines()[3] == "Yesterday's making comes to about 3 days of food and no water.",
			"the base log says it: '%s'" % sim.supplies_lines()[3])
	sim.made_yesterday = {"vegetable": 1}
	check(sim.supplies_lines()[3].contains("less than a day of food"), "a little: less than a day")


func test_the_press_makes_shotgun_ammo() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	var press := _machine(sim, "press", Vector2i(70, 70))
	for r: String in ["press_powder", "press_shells"]:
		check(data.buildables["press"]["recipes"].has(r), "the Press can make %s" % data.recipes[r]["name"])
	sim.factory.set_recipe(press, "press_powder")
	press.input = {"ammo_casing": 8, "scrap_metal": 1}
	for i in roundi((float(data.recipes["press_powder"]["time"]) + 0.5) / TICK):
		sim.factory.tick(TICK)
	eq(int(press.output.get("gunpowder", 0)), 2, "casings and scrap make gunpowder")
	sim.factory.set_recipe(press, "press_shells")
	press.output.clear()
	press.input = {"ammo_casing": 6, "gunpowder": 1}
	for i in roundi((float(data.recipes["press_shells"]["time"]) + 0.5) / TICK):
		sim.factory.tick(TICK)
	eq(int(press.output.get("shells", 0)), 6, "and casings and gunpowder make six shells")


func test_med_kits() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	var canner := _machine(sim, "canner", Vector2i(80, 80))
	check(data.buildables["canner"]["recipes"].has("pack_medkit"), "the canner packs med kits")
	sim.factory.set_recipe(canner, "pack_medkit")
	canner.input = {"bandage": 2, "clean_water": 1}
	for i in roundi((float(data.recipes["pack_medkit"]["time"]) * 1.2 + 0.5) / TICK):
		sim.factory.tick(TICK)
	eq(int(canner.output.get("medkit", 0)), 1, "two bandages and a clean water make a med kit")
	check(sim.can_use("medkit") and sim.hotbar.usable("medkit"), "you can use it from your pockets or a hotbar key")
	sim.inventory.add("medkit", 2)
	eq(sim.use_item("medkit"), "You're not hurt", "not when you're well")
	eq(sim.inventory.count("medkit"), 2, "and it isn't spent")
	sim.player.health = 30.0
	sim.player.bleeding = true
	check(sim.use_item("medkit").begins_with("Used a med kit"), "hurt and bleeding: use it")
	near(sim.player.health, 30.0 + data.item_value("medkit", "heal"), "it heals %d" % int(data.item_value("medkit", "heal")), 0.6)
	check(not sim.player.bleeding, "and stops the bleeding")
	sim.player.health = 50.0
	check(sim.use_bandage().begins_with("Used a med kit"), "H when hurt but not bleeding uses a med kit")
	eq(sim.inventory.count("medkit"), 0, "both used")
	eq(sim.use_bandage(), "Not bleeding", "none left: H says not bleeding, as before")
