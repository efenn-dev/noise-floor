extends "res://test/base_test.gd"

const N := 0
const E := 1
const S := 2
const W := 3
const TICK := SimWorld.TICK

var data := GameData.load_default()


func _run(f: Factory, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		f.tick(TICK)


func test_machine_crafts_on_time() -> void:
	var f := Factory.new(data)
	var m := f.add_machine("smelter", Vector2i(0, 0), E)
	m.input["scrap_metal"] = 3
	_run(f, 1.9)
	eq(m.crafted, 0, "not done before 2 s")
	_run(f, 0.1)
	eq(m.crafted, 1, "first plate at 2 s")
	eq(m.output.get("metal_plate", 0), 1, "plate waits in the output (nothing to push to)")
	_run(f, 10.0)
	eq(m.crafted, 3, "stops when input runs out")
	eq(m.status(), "needs input", "says why it stopped")
	check(m.input.is_empty(), "input used up")


func test_machine_stops_when_output_full() -> void:
	var f := Factory.new(data)
	var m := f.add_machine("press", Vector2i(0, 0), E)
	m.input["metal_plate"] = 20
	_run(f, 60.0)
	eq(m.output.get("nails", 0), 48, "fills to 48 of 50 (another 4 won't fit)")
	eq(m.crafted, 12, "12 crafts")
	eq(m.status(), "output full", "says output full")


func test_belt_carries_items_at_belt_speed() -> void:
	var f := Factory.new(data)
	for x in 3:
		f.add_belt(Vector2i(x, 0), E)
	var m := f.add_machine("press", Vector2i(3, 0), E)  # back faces west, toward the belts
	f.belts[Vector2i(0, 0)].accept("metal_plate")
	_run(f, 2.9)
	var arrived := func() -> int: return m.input.get("metal_plate", 0) + m.crafted + (1 if m.crafting else 0)
	eq(arrived.call(), 0, "not there before 3 cells at 1 cell/s")
	_run(f, 0.15)
	eq(arrived.call(), 1, "arrives at 3 s")


func test_belts_turn_corners_but_not_backwards() -> void:
	var f := Factory.new(data)
	f.add_belt(Vector2i(0, 0), E)
	f.add_belt(Vector2i(1, 0), S)  # takes from its west side: a corner
	f.add_belt(Vector2i(1, 1), S)
	f.belts[Vector2i(0, 0)].accept("nails")
	_run(f, 2.5)
	eq(f.belts[Vector2i(1, 1)].items.size(), 1, "item went round the corner")
	var g := Factory.new(data)
	g.add_belt(Vector2i(0, 0), E)
	g.add_belt(Vector2i(1, 0), W)  # head-on: would feed into its front end
	g.belts[Vector2i(0, 0)].accept("nails")
	_run(g, 3.0)
	eq(g.belts[Vector2i(0, 0)].items.size(), 1, "head-on belt refuses, item waits at the end")


func test_belt_backs_up_with_spacing() -> void:
	var f := Factory.new(data)
	var b := f.add_belt(Vector2i(0, 0), E)  # nothing ahead
	for i in 10:
		if b.can_accept():
			b.accept("nails")
		_run(f, 0.5)
	eq(b.items.size(), 5, "a blocked 1-cell belt holds 5 items (0.25 apart, one at each end)")
	var ok := true
	for i in range(1, b.items.size()):
		ok = ok and b.items[i - 1]["pos"] - b.items[i]["pos"] >= Factory.SPACING - 1e-6
	check(ok, "items never overlap")
	near(b.items[0]["pos"], 1.0, "front item waits at the end")


func test_machine_input_only_at_back() -> void:
	var f := Factory.new(data)
	f.add_belt(Vector2i(0, 0), E)
	var m := f.add_machine("smelter", Vector2i(1, 0), N)  # back faces south, not west
	f.belts[Vector2i(0, 0)].accept("scrap_metal")
	_run(f, 3.0)
	eq(m.input.size() + m.crafted, 0, "side of a machine is not an input")
	var g := Factory.new(data)
	g.add_belt(Vector2i(0, 0), E)
	var m2 := g.add_machine("smelter", Vector2i(1, 0), E)
	g.belts[Vector2i(0, 0)].accept("nails")  # wrong item
	_run(g, 3.0)
	eq(m2.input.size(), 0, "machine refuses items its recipe doesn't use")


## The M3 throughput proof: N scrap in -> N plates -> 4N nails, in a predictable time.
func test_smelter_belts_press_line_throughput() -> void:
	var f := Factory.new(data)
	var smelter := f.add_machine("smelter", Vector2i(0, 0), E)
	for x in range(1, 4):
		f.add_belt(Vector2i(x, 0), E)
	var press := f.add_machine("press", Vector2i(4, 0), E)
	var inv := Inventory.new()
	inv.add("scrap_metal", 10)
	f.hand_interact(Vector2i(0, 0), inv)
	eq(smelter.input.get("scrap_metal", 0), 10, "hand-fed 10 scrap")
	_run(f, 15.0)
	eq(smelter.crafted, 7, "7 plates smelted by 15 s (one per 2 s)")
	_run(f, 13.0)  # t = 28 s: last plate done at 20 s, ~3 s on the belts, 2 s to press
	eq(smelter.crafted, 10, "10 scrap -> 10 plates")
	eq(press.crafted, 10, "all 10 plates reached the press and were pressed")
	eq(press.output.get("nails", 0), 40, "10 plates -> 40 nails")
	var took: Dictionary = f.hand_interact(Vector2i(4, 0), inv)["took"]
	eq(took.get("nails", 0), 40, "took the nails by hand")
	eq(inv.count("nails"), 40, "nails in inventory")


func test_hand_feed_respects_cap_and_recipe() -> void:
	var f := Factory.new(data)
	var m := f.add_machine("smelter", Vector2i(0, 0), E)
	var inv := Inventory.new()
	inv.give_all({"scrap_metal": 30, "plank": 5})
	var fed: Dictionary = f.hand_interact(Vector2i(0, 0), inv)["fed"]
	eq(fed, {"scrap_metal": Factory.INPUT_CAP}, "feeds only up to the input cap")
	eq(inv.count("scrap_metal"), 30 - Factory.INPUT_CAP, "rest stays in inventory")
	eq(inv.count("plank"), 5, "doesn't take items it can't use")
	eq(m.input.get("scrap_metal", 0), Factory.INPUT_CAP, "machine has them")


func test_sim_world_builds_and_refunds_contents() -> void:
	var sim := SimWorld.new(8.0)
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	eq(sim.build.place("smelter", Vector2i(1, 0), E, sim.inventory), "Needs a foundation", "machines need a floor")
	eq(sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory), "", "smelter on the foundation")
	check(sim.factory.machines.has(Vector2i(0, 0)), "factory knows about it")
	eq(sim.build.remove("f:0:0", sim.inventory), "Remove what's on it first", "foundation under a machine stays")
	var scrap := sim.inventory.count("scrap_metal")
	sim.factory.hand_interact(Vector2i(0, 0), sim.inventory)
	for i in 50:  # 2.5 s: one plate made
		sim.step()
	eq(sim.build.remove("o:0:0", sim.inventory), "", "remove the smelter")
	check(not sim.factory.machines.has(Vector2i(0, 0)), "gone from the factory")
	eq(sim.inventory.count("scrap_metal"), scrap - 1 + 10, "unused scrap + build cost back, minus the one smelted")
	eq(sim.inventory.count("metal_plate"), data.debug_kit["metal_plate"] + 1, "the finished plate comes back too")


func test_same_result_however_frames_are_sliced() -> void:
	var results := []
	for frame in [1.0 / 60.0, 0.033, 0.1]:
		var sim := SimWorld.new(8.0)
		var f := sim.factory
		f.add_machine("smelter", Vector2i(0, 0), E).input["scrap_metal"] = 5
		f.add_belt(Vector2i(1, 0), E)
		f.add_belt(Vector2i(2, 0), E)
		while sim.ticks < 180:  # 9 s of ticks, fed in different frame sizes
			sim.update(minf(frame, (180 - sim.ticks) * SimWorld.TICK + 1e-6))
		var b: Factory.Belt = f.belts[Vector2i(2, 0)]
		results.append([sim.ticks, f.machines[Vector2i(0, 0)].crafted, b.items.size(), b.items[0]["pos"] if b.items.size() > 0 else -1.0])
	eq(results[1], results[0], "33 ms frames match 60 fps")
	eq(results[2], results[0], "100 ms frames match 60 fps")
