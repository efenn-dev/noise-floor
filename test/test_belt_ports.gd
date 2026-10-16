extends "res://test/base_test.gd"
## P4 (Emmitt: "the conveyor belts were hard to tell if they snapped into a machine like in Satisfactory. I just built
## a machine with conveyor belts around all sides and still didn't know how it worked"): what a belt's end feeds,
## belts that snap, a machine's IN and OUT in words, and the markers that show it.

const N := 0
const E := 1
const S := 2
const W := 3
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


## A smelter at (10, 10) facing east: its IN is (9, 10), its OUT (11, 10).
func _smelter_world() -> SimWorld:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	sim.build.place("foundation", Vector2i(10, 10), N, _rich())
	eq(sim.build.place("smelter", Vector2i(10, 10), E, _rich()), "", "a smelter facing east")
	return sim


func _belt(sim: SimWorld, cell: Vector2i, facing: int) -> void:
	eq(sim.build.place("belt", cell, facing, _rich()), "", "a belt at %s" % cell)


func test_what_a_belt_end_feeds() -> void:
	var sim := _smelter_world()
	var m: Factory.Machine = sim.factory.machines[Vector2i(10, 10)]
	eq(Factory.input_cell(m), Vector2i(9, 10), "its IN is behind it")
	eq(Factory.output_cell(m), Vector2i(11, 10), "its OUT is in front")
	_belt(sim, Vector2i(9, 10), E)
	_belt(sim, Vector2i(10, 9), S)
	_belt(sim, Vector2i(11, 10), W)
	var into := sim.belt_target(Vector2i(9, 10))
	eq(into["kind"], "machine", "a belt behind it, pointing in: it feeds the machine")
	check(into["ok"], "that connects")
	eq(sim.belt_link_words(into), "feeds the Smelter's IN", "and says so")
	var side := sim.belt_target(Vector2i(10, 9))
	eq(side["kind"], "machine_side", "a belt pointing at its side doesn't")
	check(side["bad"], "that's wrong")
	check(sim.belt_link_words(side).contains("only take items in at the back"), "and it says why")
	eq(sim.belt_target(Vector2i(11, 10))["kind"], "machine_side", "nor one pointing at its front")


func test_belts_running_into_each_other_crates_and_the_hub() -> void:
	var sim := SimWorld.new(12.0)
	_belt(sim, Vector2i(20, 20), E)
	_belt(sim, Vector2i(21, 20), W)
	eq(sim.belt_target(Vector2i(20, 20))["kind"], "belt_backwards", "two belts head to head: stuck")
	_belt(sim, Vector2i(20, 22), E)
	_belt(sim, Vector2i(21, 22), E)
	eq(sim.belt_target(Vector2i(20, 22))["kind"], "belt", "a line: it carries on")
	sim.build.place("foundation", Vector2i(23, 24), N, _rich())
	sim.build.place("storage", Vector2i(23, 24), N, _rich())
	_belt(sim, Vector2i(22, 24), E)
	var crate := sim.belt_target(Vector2i(22, 24))
	eq(crate["kind"], "crate", "into a crate")
	check(crate["ok"], "connects")
	sim.build.place("hub", Vector2i(30, 30), N, _rich())
	_belt(sim, Vector2i(29, 30), E)
	eq(sim.belt_target(Vector2i(29, 30))["kind"], "hub", "into the Hub")
	eq(sim.belt_target(Vector2i(40, 40), E)["kind"], "open", "an unbuilt belt out in the open leads nowhere")


func test_belts_snap_like_satisfactory() -> void:
	var sim := _smelter_world()
	eq(sim.factory.snap_belt_facing(Vector2i(9, 10)), E, "behind the machine: it turns to feed in")
	eq(sim.factory.snap_belt_facing(Vector2i(11, 10)), E, "in front: it carries the output on")
	eq(sim.factory.snap_belt_facing(Vector2i(10, 9)), -1, "beside it: nothing to join")
	_belt(sim, Vector2i(12, 10), E)
	eq(sim.factory.snap_belt_facing(Vector2i(13, 10)), E, "after a belt that ends here: it carries on the same way")
	var bc := BuildController.new()
	bc.sim = sim
	eq(bc.snap_side("belt", Vector2i(9, 10), N), E, "the build ghost snaps a belt behind the machine")
	check(bc.snapped, "and knows it snapped")
	eq(bc.snap_side("wall", Vector2i(9, 10), N), N, "a wall doesn't snap")
	bc._manual_turn = true
	eq(bc.snap_side("belt", Vector2i(9, 10), N), N, "after R, the way you chose wins")
	check(not bc.snapped, "no snap")
	bc.free()


func test_a_machines_ports_in_words() -> void:
	var sim := _smelter_world()
	var words := sim.machine_port_words(Vector2i(10, 10))
	check(words.contains("IN (back, blue): nothing feeds it yet"), "nothing behind it: '%s'" % words)
	check(words.contains("OUT (front, orange): nothing takes it"), "nothing in front")
	_belt(sim, Vector2i(9, 10), E)
	_belt(sim, Vector2i(11, 10), E)
	words = sim.machine_port_words(Vector2i(10, 10))
	check(words.contains("fed by a belt") and words.contains("onto a belt"), "belts both ends: '%s'" % words)
	sim.build.remove(sim.build.key_for("belt", Vector2i(11, 10)), Inventory.new())
	_belt(sim, Vector2i(11, 10), W)
	check(sim.machine_port_words(Vector2i(10, 10)).contains("BLOCKED"), "a belt in front pointing back blocks its output")
	sim.build.remove(sim.build.key_for("belt", Vector2i(11, 10)), Inventory.new())
	sim.build.place("foundation", Vector2i(11, 10), N, _rich())
	sim.build.place("press", Vector2i(11, 10), E, _rich())
	check(sim.machine_port_words(Vector2i(10, 10)).contains("straight into the Press"), "a Press in front, its back to it")
	check(sim.machine_port_words(Vector2i(11, 10)).contains("fed straight from the Smelter"), "and the Press says where it's fed from")


func test_the_markers() -> void:
	var sim := _smelter_world()
	_belt(sim, Vector2i(9, 10), E)
	_belt(sim, Vector2i(10, 11), N)
	var view := PortView.new()
	tree.root.add_child(view)
	view.setup(sim)
	view.rebuild()
	var names := view.get_children().map(func(c: Node) -> String: return String(c.name))
	check(names.any(func(n: String) -> bool: return n.begins_with("Chute_IN")), "the belt into its IN plugs in with a chute and a port frame")
	check(not names.any(func(n: String) -> bool: return n.begins_with("Port_IN")), "so no loose IN arrow")
	check(names.any(func(n: String) -> bool: return n.begins_with("Port_OUT")), "nothing at its front: an OUT arrow")
	eq(names.filter(func(n: String) -> bool: return n.begins_with("Tick")).size(), 1, "a green tick where the belt feeds its IN")
	eq(names.filter(func(n: String) -> bool: return n.begins_with("Cross")).size(), 1, "a red X where the other points at its side")
	_belt(sim, Vector2i(11, 10), E)
	view.rebuild()
	names = view.get_children().map(func(c: Node) -> String: return String(c.name))
	check(names.any(func(n: String) -> bool: return n.begins_with("Chute_OUT")), "a belt carrying its output away: a chute at its front")
	view.free()


func test_chutes_reach_the_machine_faces() -> void:
	var press := PortView.port_depths("press")
	check(press.x > 0.5 and press.x < 0.8 and press.y > 0.5 and press.y < 0.8, "the Press model is about 1.35 m deep (%s)" % press)
	check(PortView.port_depths("smelter").x > press.x, "the smelter is deeper")
	var chute := PortView.chute(Vector3(0, 0, 1.0), Vector3(0, 0, 0.68), 0.2, "IN")
	near(chute.position.z, 0.84, "a chute sits between the belt's end and the machine's face", 0.001)
	check(chute.get_child_count() >= 6, "deck, rails and a port frame")
	chute.free()


func test_the_build_line_says_what_the_belt_will_feed() -> void:
	var sim := _smelter_world()
	var bc := BuildController.new()
	bc.sim = sim
	bc.select_id("belt")
	bc.aim_valid = true
	bc.aim_cell = Vector2i(9, 10)
	bc.aim_side = bc.snap_side("belt", bc.aim_cell, N)
	check(bc.port_text().begins_with("This belt ✓ feeds the Smelter's IN"), "'%s'" % bc.port_text())
	check(bc.port_text().contains("snapped"), "and says it snapped")
	bc._manual_turn = true
	bc.aim_cell = Vector2i(10, 9)
	bc.aim_side = bc.snap_side("belt", bc.aim_cell, S)
	check(bc.port_text().begins_with("This belt X points at the Smelter's side"), "pointed at the side: an X")
	bc.select_id("press")
	check(bc.port_text().contains("IN at the back"), "a machine: which way it takes and gives")
	bc.free()
