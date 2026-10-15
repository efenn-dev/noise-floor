extends "res://test/base_test.gd"
## F3 (Emmitt: building "more like Satisfactory"): belts run on bare ground and fill crates, splitters and
## mergers route them, and dragging lays a straight row of pieces in one go.

const N := 0
const E := 1
const S := 2
const W := 3
const TICK := SimWorld.TICK

var data := GameData.load_default()


func _run(f: Factory, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		f.tick(TICK)


## Puts `count` items on the belt at `cell`, one whenever it has room, running the factory meanwhile.
func _feed(f: Factory, cell: Vector2i, item: String, count: int) -> void:
	var left := count
	for i in 400:
		if left == 0:
			return
		if f.belts[cell].can_accept():
			f.belts[cell].accept(item)
			left -= 1
		f.tick(TICK)


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func test_belts_lie_on_bare_ground_or_a_foundation() -> void:
	var sim := SimWorld.new(12.0)
	var size: Vector3 = data.buildables["belt"]["size"]
	var cell := Vector2i(30, 30)
	eq(sim.build.can_place("belt", cell, E, _rich()), "", "a belt goes on bare ground")
	check(is_equal_approx(sim.build.center_for("belt", cell, E).y, size.y / 2.0), "and lies on it")
	eq(sim.build.place("foundation", cell + Vector2i(1, 0), N, _rich()), "", "a foundation next door")
	check(is_equal_approx(sim.build.center_for("belt", cell + Vector2i(1, 0), E).y, sim.build.foundation_top() + size.y / 2.0),
			"a belt on a foundation sits on top of it")
	eq(sim.build.place("belt", cell, E, _rich()), "", "built in the field")
	check(sim.factory.belts.has(cell), "the factory runs it")
	eq(sim.build.can_place("smelter", cell + Vector2i(0, 1), E, _rich()), "Needs a foundation", "machines still need a floor")


func test_a_belt_ending_at_a_crate_fills_it() -> void:
	var sim := SimWorld.new(12.0)
	var crate_cell := Vector2i(30, 30)
	sim.build.place("foundation", crate_cell, N, _rich())
	eq(sim.build.place("storage", crate_cell, N, _rich()), "", "a crate")
	for x in [28, 29]:
		eq(sim.build.place("belt", Vector2i(x, 30), E, _rich()), "", "a belt toward it")
	var crate: Inventory = sim.storages["o:30:30"]
	var before := crate.count("nails")
	_feed(sim.factory, Vector2i(28, 30), "nails", 3)
	_run(sim.factory, 4.0)
	eq(crate.count("nails") - before, 3, "the nails went in the crate")
	check(sim.factory.belts[Vector2i(29, 30)].items.is_empty(), "nothing left waiting on the belt")


func test_a_splitter_takes_turns_and_skips_dead_ends() -> void:
	var f := Factory.new(data)
	f.add_belt(Vector2i(0, 0), E)
	f.add_router("splitter", Vector2i(1, 0), E)
	f.add_belt(Vector2i(2, 0), E)   # front
	f.add_belt(Vector2i(1, -1), N)  # left of east is north
	f.add_belt(Vector2i(1, 1), S)   # right
	_feed(f, Vector2i(0, 0), "nails", 6)
	_run(f, 4.0)
	for c: Vector2i in [Vector2i(2, 0), Vector2i(1, -1), Vector2i(1, 1)]:
		eq(f.belts[c].items.size(), 2, "each way out got its share (%s)" % c)
	var g := Factory.new(data)
	g.add_belt(Vector2i(0, 0), E)
	g.add_router("splitter", Vector2i(1, 0), E)
	g.add_belt(Vector2i(2, 0), E)
	_feed(g, Vector2i(0, 0), "nails", 3)
	_run(g, 3.0)
	eq(g.belts[Vector2i(2, 0)].items.size(), 3, "with only a front belt, everything goes out the front")
	var h := Factory.new(data)
	h.add_belt(Vector2i(1, -1), S)  # pointing into the splitter's side
	h.add_router("splitter", Vector2i(1, 0), E)
	h.belts[Vector2i(1, -1)].accept("nails")
	_run(h, 2.0)
	eq(h.belts[Vector2i(1, -1)].items.size(), 1, "a splitter only takes at its back")


func test_a_merger_joins_belts() -> void:
	var f := Factory.new(data)
	f.add_belt(Vector2i(0, 0), E)   # from the back
	f.add_belt(Vector2i(1, -1), S)  # from the left
	f.add_belt(Vector2i(1, 1), N)   # from the right
	f.add_router("merger", Vector2i(1, 0), E)
	for x in [2, 3, 4]:
		f.add_belt(Vector2i(x, 0), E)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(1, 1)]:
		f.belts[c].accept("nails")
	_run(f, 5.0)
	var out := 0
	for x in [2, 3, 4]:
		out += f.belts[Vector2i(x, 0)].items.size()
	eq(out, 3, "all three came out the front")
	var g := Factory.new(data)
	g.add_router("merger", Vector2i(1, 0), E)
	g.add_belt(Vector2i(2, 0), W)  # pointing into its front
	g.belts[Vector2i(2, 0)].accept("nails")
	_run(g, 2.0)
	eq(g.belts[Vector2i(2, 0)].items.size(), 1, "a merger won't take at its front")


func test_a_blocked_router_holds_two_and_gives_them_back() -> void:
	var sim := SimWorld.new(12.0)
	eq(sim.build.place("belt", Vector2i(29, 30), E, _rich()), "", "a belt")
	eq(sim.build.place("splitter", Vector2i(30, 30), E, _rich()), "", "into a splitter on bare ground")
	_feed(sim.factory, Vector2i(29, 30), "nails", 4)
	_run(sim.factory, 3.0)
	var r: Factory.Router = sim.factory.routers[Vector2i(30, 30)]
	eq(r.items.size(), Factory.ROUTER_CAP, "nowhere to go: it holds two")
	var d := SaveGame.to_dict(sim)
	var loaded := SimWorld.new(12.0)
	SaveGame.apply(loaded, JSON.parse_string(JSON.stringify(d)))
	eq((loaded.factory.routers[Vector2i(30, 30)] as Factory.Router).items.size(), Factory.ROUTER_CAP, "and still holds them after a load")
	var nails := sim.inventory.count("nails")
	eq(sim.build.remove("o:30:30", sim.inventory), "", "removed")
	check(not sim.factory.routers.has(Vector2i(30, 30)), "gone from the factory")
	eq(sim.inventory.count("nails") - nails, Factory.ROUTER_CAP + int(data.buildables["splitter"]["cost"]["nails"]),
			"its nails come back with the refund")


func test_logistics_unlocks_splitters_and_mergers() -> void:
	var sim := SimWorld.new(12.0)
	sim.milestones.done.clear()  # a real new game
	for id in ["splitter", "merger"]:
		check(sim.build.can_place(id, Vector2i(30, 30), E, _rich()).begins_with("Unlock it at the Hub: Logistics"), "%s is locked" % id)
	eq(sim.milestones.unlocked_by("splitter"), "logistics", "Logistics unlocks it")
	eq(sim.milestones.cfg("logistics")["tier"], 2, "in tier 2")
	check(sim.build.can_place("belt", Vector2i(30, 30), E, _rich()) == "", "plain belts need no milestone")


func test_the_hub_stands_on_its_own_cell() -> void:
	var sim := SimWorld.new(12.0)
	var cell := Vector2i(30, 30)
	eq(sim.build.place("hub", cell, N, _rich()), "", "a Hub on bare ground")
	check(sim.hub_key().begins_with("o:"), "it's an object, like a machine")
	sim.build.place("foundation", cell, N, _rich())
	eq(sim.build.can_place("smelter", cell, E, _rich()), "Already built", "no machine inside it")
	var size: Vector3 = data.buildables["hub"]["size"]
	check(is_equal_approx(sim.build.center_for("hub", cell, N).y, sim.build.foundation_top() + size.y / 2.0),
			"with a foundation under it, it stands on top")
	check(is_equal_approx(sim.build.center_for("hub", cell + Vector2i(2, 0), N).y, size.y / 2.0), "on bare ground, on the ground")


func test_drag_runs_go_straight() -> void:
	var cells := BuildController.run_cells(false, Vector2i(0, 0), Vector2i(5, 2), N)
	eq(cells.size(), 6, "dragged mostly east: 6 foundations along x")
	eq(cells[5], Vector2i(5, 0), "straight, not diagonal")
	cells = BuildController.run_cells(false, Vector2i(0, 0), Vector2i(1, -4), N)
	eq(cells, [Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3), Vector2i(0, -4)] as Array[Vector2i], "north works too")
	eq(BuildController.run_cells(false, Vector2i(3, 3), Vector2i(3, 3), N).size(), 1, "a click is one piece")
	eq(BuildController.run_cells(false, Vector2i(0, 0), Vector2i(100, 0), N).size(), BuildController.ZOOP_MAX, "at most a 32-piece run")
	cells = BuildController.run_cells(true, Vector2i(0, 0), Vector2i(1, 6), N)
	eq(cells.size(), 2, "a wall on a north edge runs east-west, whichever way you drag")
	cells = BuildController.run_cells(true, Vector2i(0, 0), Vector2i(1, 6), W)
	eq(cells.size(), 7, "a wall on a west edge runs north-south")
	eq(BuildController.run_side("belt", Vector2i(0, 0), Vector2i(4, 1), N), E, "belts face the way you drag")
	eq(BuildController.run_side("belt", Vector2i(0, 0), Vector2i(0, -3), E), N, "north too")
	eq(BuildController.run_side("foundation", Vector2i(0, 0), Vector2i(4, 0), S), S, "other pieces keep their side")
	eq(BuildController.run_side("belt", Vector2i(2, 2), Vector2i(2, 2), W), W, "a single belt keeps the way you turned it")
