extends "res://test/base_test.gd"
## The water chain (rain collector -> purifier) and food chain (planter -> canner).

const TICK := SimWorld.TICK
const E := 1


func _run(f: Factory, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		f.tick(TICK)


func test_rain_collector_needs_nothing() -> void:
	var f := Factory.new(GameData.load_default())
	var c := f.add_machine("rain_collector", Vector2i(0, 0), E)
	_run(f, 61.0)
	eq(c.output.get("dirty_water", 0), 3, "3 rainwater a minute with no input")


func test_water_chain() -> void:
	var f := Factory.new(GameData.load_default())
	f.add_machine("rain_collector", Vector2i(0, 0), E)
	f.add_belt(Vector2i(1, 0), E)
	var p := f.add_machine("purifier", Vector2i(2, 0), E)
	_run(f, 60.0 + 1.0 + 4.0 + 0.5)  # 3rd rainwater at 60 s, 1 s on the belt, 4 s to purify
	eq(p.output.get("clean_water", 0), 3, "3 clean water in about 65 s")


func test_food_chain() -> void:
	var f := Factory.new(GameData.load_default())
	var planter := f.add_machine("planter", Vector2i(0, 0), E)
	planter.input = {"seeds": 2, "dirty_water": 2}
	f.add_belt(Vector2i(1, 0), E)
	var canner := f.add_machine("canner", Vector2i(2, 0), E)
	canner.input["metal_plate"] = 5
	_run(f, 59.0)
	eq(planter.crafted, 0, "vegetables take a minute")
	_run(f, 1.0)
	eq(planter.crafted, 1, "3 vegetables at 60 s")
	_run(f, 72.0)  # 2nd batch at 120 s; its vegetables reach the canner one by one, last can done ~131 s
	eq(planter.crafted, 2, "6 vegetables from 2 seeds and 2 rainwater")
	eq(canner.crafted, 3, "6 vegetables + 3 plates -> 3 cans of work")
	eq(canner.output.get("canned_food", 0), 6, "6 canned food")
	eq(canner.input.get("metal_plate", 0), 2, "used 3 plates")


func test_planter_waits_for_water() -> void:
	var f := Factory.new(GameData.load_default())
	var planter := f.add_machine("planter", Vector2i(0, 0), E)
	planter.input = {"seeds": 3}
	_run(f, 5.0)
	check(not planter.crafting, "seeds alone don't grow")
	eq(planter.status(), "needs input", "says it needs input")
