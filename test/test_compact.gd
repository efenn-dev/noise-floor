extends "res://test/base_test.gd"
## F6 (compact and deep, part 1): a planter keeps its seed (what a recipe uses goes straight back in), grows cotton
## too, and the canner packs cotton into bandages; a machine fed straight from the machine behind it works faster;
## the base log shows what your machines made against what you eat and drink; "Live off your base" leads through
## the water and food chain.

const N := 0
const E := 1
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _machine(sim: SimWorld, id: String, cell: Vector2i, facing: int = E) -> Factory.Machine:
	var stock := _rich()
	sim.build.place("foundation", cell, N, stock)
	eq(sim.build.place(id, cell, facing, stock), "", "a %s" % id)
	return sim.factory.machines[cell]


func test_a_planter_keeps_its_seed() -> void:
	var sim := SimWorld.new(12.0)
	var p := _machine(sim, "planter", Vector2i(20, 20))
	p.input = {"seeds": 1, "dirty_water": 5}
	var harvest: float = data.recipes["grow_vegetables"]["time"]
	for i in roundi((harvest * 3.0) / TICK) + 10:
		sim.factory.tick(TICK)
	check(p.crafted >= 2, "one seed grew more than one harvest (%d)" % p.crafted)
	check(int(p.output.get("vegetable", 0)) >= 6, "vegetables piled up (%d)" % int(p.output.get("vegetable", 0)))
	eq(int(p.output.get("seeds", 0)), 0, "the seed never comes out: it goes straight back in")
	check(int(p.input.get("seeds", 0)) >= 0 and p.crafted >= 2, "and it keeps going on the one seed")
	check(not sim.factory.made.has("seeds"), "a returned seed isn't counted as made")
	eq(int(sim.factory.made.get("vegetable", 0)), int(p.output.get("vegetable", 0)) + 0, "vegetables are")


func test_cotton_and_bandages() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	var p := _machine(sim, "planter", Vector2i(20, 20))
	check(sim.cycle_recipe(Vector2i(20, 20)) != "", "R on a planter switches what it grows")
	eq(p.recipe_id, "grow_cotton", "cotton")
	p.input = {"seeds": 1, "dirty_water": 3}
	for i in roundi((float(data.recipes["grow_cotton"]["time"]) + 0.5) / TICK):
		sim.factory.tick(TICK)
	eq(int(p.output.get("cotton", 0)), 2, "a harvest of cotton")
	check(p.crafting and int(p.input.get("dirty_water", 0)) == 1, "and the seed went back in: it's growing the next lot already")
	var c := _machine(sim, "canner", Vector2i(24, 20))
	sim.cycle_recipe(Vector2i(24, 20))
	eq(c.recipe_id, "pack_bandages", "R on the canner packs bandages")
	c.input = {"cotton": 2, "clean_water": 1}
	for i in roundi((float(data.recipes["pack_bandages"]["time"]) * 1.2 + 0.5) / TICK):
		sim.factory.tick(TICK)
	eq(int(c.output.get("bandage", 0)), 2, "two cotton and a clean water make two bandages")
	check(data.item_value("bandage", "bandage") > 0.0, "and they're real bandages")


func test_a_machine_fed_straight_from_the_one_behind_is_faster() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	var smelter := _machine(sim, "smelter", Vector2i(30, 30), E)
	var press := _machine(sim, "press", Vector2i(31, 30), E)
	var plain := press.craft_time()
	smelter.input["scrap_metal"] = 10
	for i in roundi(3.0 / TICK):
		sim.factory.tick(TICK)
	check(press.chained > 0.0, "the smelter handed the press a plate straight in")
	near(press.craft_time(), plain / (1.0 + Factory.CHAIN_BONUS), "so the press works %d%% faster" % roundi(Factory.CHAIN_BONUS * 100.0), 1e-4)
	var belt_fed := _machine(sim, "press", Vector2i(40, 30), E)
	sim.build.place("belt", Vector2i(39, 30), E, _rich())
	sim.factory.belts[Vector2i(39, 30)].accept("metal_plate")
	for i in roundi(1.5 / TICK):
		sim.factory.tick(TICK)
	check(belt_fed.input.get("metal_plate", 0) > 0 or belt_fed.crafting, "a belt fed the other press")
	eq(belt_fed.chained, 0.0, "but a belt doesn't count")
	for i in roundi((Factory.CHAIN_HOLD + 3.0) / TICK):
		sim.factory.tick(TICK)
	check(press.chained == 0.0 or smelter.crafting, "the bonus fades once nothing comes for a while")


func test_what_your_base_made() -> void:
	var sim := SimWorld.new(12.0)
	var r := _machine(sim, "rain_collector", Vector2i(50, 50))
	for i in roundi((float(data.recipes["collect_rain"]["time"]) * 2.0 + 1.0) / TICK):
		sim.step()
	check(r.crafted >= 1, "it rained in")
	eq(int(sim.made_today().get("dirty_water", 0)), r.crafted, "made today counts it")
	check(sim.supplies_lines()[0].begins_with("Your machines made today: %s" % data.item_name("dirty_water")), "and says so")
	eq(sim.supplies_lines()[1], "Yesterday: nothing yet", "nothing yesterday")
	var today := int(sim.made_today().get("dirty_water", 0))
	sim._new_day()
	eq(int(sim.made_yesterday.get("dirty_water", 0)), today, "a new day: today's becomes yesterday's")
	check(sim.made_today().is_empty(), "and today starts again")
	var need := sim.needs_per_day()
	near(float(need["cans"]), float(data.survival["food_drain"]) * sim.clock.seconds_per_day / data.item_value("canned_food", "food"),
			"what you eat in a day, in cans", 1e-4)
	check(sim.supplies_lines()[2].begins_with("You eat about"), "the third line says it")
	var back := SimWorld.new(12.0)
	SaveGame.apply(back, SaveGame.to_dict(sim))
	eq(int(back.made_yesterday.get("dirty_water", 0)), today, "yesterday's counts save and load")
	eq(int(back.factory.made.get("dirty_water", 0)), int(sim.factory.made.get("dirty_water", 0)), "so do the totals")


func test_live_off_your_base() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	eq(sim.guidance.tick_feed(sim.clock, sim.factory), "", "not on day 1")
	sim.clock.day = Guidance.FEED_START_DAY
	var msg := sim.guidance.tick_feed(sim.clock, sim.factory)
	check(msg.begins_with("New goal: live off your base"), "from day %d it starts" % Guidance.FEED_START_DAY)
	eq(sim.guidance.feed_step(), 0, "first: collect water")
	var r := _machine(sim, "rain_collector", Vector2i(50, 50))
	r.crafted = 1
	check(sim.guidance.tick_feed(sim.clock, sim.factory).begins_with("Water collected"), "a rain collector made water")
	var pl := _machine(sim, "planter", Vector2i(52, 50))
	pl.crafted = 1
	eq(sim.guidance.tick_feed(sim.clock, sim.factory), "", "growing food early doesn't skip cleaning the water")
	eq(sim.guidance.feed_step(), 1, "still: clean it")
	check(bool(sim.guidance.feed_met[2]), "but it counts")
	var d := sim.guidance.to_dict()
	var g2 := Guidance.new()
	g2.load_dict(d)
	check(g2.feed_active and bool(g2.feed_met[0]) and bool(g2.feed_met[2]) and not bool(g2.feed_met[1]), "the chapter saves")
	var pu := _machine(sim, "purifier", Vector2i(54, 50))
	pu.crafted = 1
	check(sim.guidance.tick_feed(sim.clock, sim.factory).begins_with("Food growing"), "purifier done: next is canning")
	var ca := _machine(sim, "canner", Vector2i(56, 50))
	ca.crafted = 1
	check(sim.guidance.tick_feed(sim.clock, sim.factory).begins_with("Your base feeds you"), "canned: done")
	check(sim.guidance.feed_done, "the chapter is finished")


func test_the_feed_panel() -> void:
	var sim := SimWorld.new(12.0)
	sim.guidance.active = true
	sim.guidance.completed = true
	sim.guidance.defend_active = true
	sim.guidance.feed_active = true
	sim.guidance.feed_met = [true, false, false, false]
	var panel := ObjectivesPanel.new()
	tree.root.add_child(panel)
	panel.setup(sim)
	panel.force_visible = true
	panel.refresh()
	check(panel.text().begins_with("LIVE OFF YOUR BASE"), "it shows over the defence goals")
	check(panel.text().contains("✓ Collect water with a machine"), "the first goal ticked")
	check(panel.text().contains("› Clean it in a purifier"), "the next one marked")
	panel.free()
