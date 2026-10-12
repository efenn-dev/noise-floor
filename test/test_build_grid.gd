extends "res://test/base_test.gd"

const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST
const S := BuildGrid.Side.SOUTH
const W := BuildGrid.Side.WEST

var data := GameData.load_default()


func _fresh() -> Array:
	var inv := Inventory.new()
	inv.give_all({"plank": 100, "nails": 100})
	return [BuildGrid.new(data), inv]


func test_world_to_cell_snaps_to_2m() -> void:
	eq(BuildGrid.world_to_cell(Vector3(0.1, 0, 0.1)), Vector2i(0, 0), "just inside the origin cell")
	eq(BuildGrid.world_to_cell(Vector3(3.9, 5, 2.0)), Vector2i(1, 1), "3.9, 2.0 -> cell 1, 1")
	eq(BuildGrid.world_to_cell(Vector3(-0.1, 0, -2.1)), Vector2i(-1, -2), "negatives round down")


func test_place_foundation_pays_and_blocks_repeat() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var inv: Inventory = g[1]
	eq(grid.place("foundation", Vector2i(0, 0), N, inv), "", "places on empty ground")
	eq(inv.count("plank"), 96, "costs 4 planks")
	eq(grid.place("foundation", Vector2i(0, 0), N, inv), "Already built", "can't stack in one cell")
	eq(inv.count("plank"), 96, "failed placement is free")
	var c := grid.piece_center("f:0:0")
	near(c.x, 1.0, "centered in cell x")
	near(c.z, 1.0, "centered in cell z")


func test_wall_needs_a_foundation() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var inv: Inventory = g[1]
	eq(grid.place("wall", Vector2i(0, 0), N, inv), "Needs a foundation", "no wall on bare ground")
	grid.place("foundation", Vector2i(0, 0), N, inv)
	for side in [N, E, S, W]:
		eq(grid.place("wall", Vector2i(0, 0), side, inv), "", "wall on %s edge" % BuildGrid.SIDE_NAMES[side])
	eq(grid.pieces.size(), 5, "1 foundation + 4 walls")
	eq(inv.count("nails"), 84, "4 walls x 4 nails")


func test_shared_edge_is_one_wall() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var inv: Inventory = g[1]
	grid.place("foundation", Vector2i(0, 0), N, inv)
	grid.place("foundation", Vector2i(0, 1), N, inv)
	eq(grid.place("wall", Vector2i(0, 0), S, inv), "", "wall between the two cells")
	eq(grid.place("wall", Vector2i(0, 1), N, inv), "Already built", "same edge seen from the other cell")
	eq(grid.key_for("wall", Vector2i(3, 3), E), grid.key_for("wall", Vector2i(4, 3), W), "east of A = west of B")


func test_wall_geometry() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	grid.place("foundation", Vector2i(0, 0), N, g[1])
	var top := grid.foundation_top()
	var h: float = data.buildables["wall"]["size"].y
	var north := grid.center_for("wall", Vector2i(0, 0), N)
	var east := grid.center_for("wall", Vector2i(0, 0), E)
	check(north.is_equal_approx(Vector3(1, top + h / 2.0, 0)), "north wall sits on z = 0 edge (%s)" % north)
	check(east.is_equal_approx(Vector3(2, top + h / 2.0, 1)), "east wall sits on x = 2 edge (%s)" % east)
	near(grid.yaw_for("wall", Vector2i(0, 0), N), 0.0, "north wall runs east-west")
	near(grid.yaw_for("wall", Vector2i(0, 0), E), 90.0, "east wall runs north-south")


func test_not_enough_materials() -> void:
	var grid := BuildGrid.new(data)
	var inv := Inventory.new()
	inv.add("plank", 3)
	eq(grid.place("foundation", Vector2i(0, 0), N, inv), "Not enough materials", "3 planks isn't enough")
	eq(inv.count("plank"), 3, "nothing taken")
	eq(grid.pieces.size(), 0, "nothing built")


func test_remove_refunds_in_full() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var inv: Inventory = g[1]
	grid.place("foundation", Vector2i(2, 2), N, inv)
	grid.place("wall", Vector2i(2, 2), W, inv)
	eq(grid.remove(grid.key_for("wall", Vector2i(2, 2), W), inv), "", "remove wall")
	eq(grid.remove("f:2:2", inv), "", "remove foundation")
	eq(inv.count("plank"), 100, "all planks back")
	eq(inv.count("nails"), 100, "all nails back")
	eq(grid.remove("f:2:2", inv), "Nothing to remove", "can't remove twice")


func test_foundation_under_a_wall_is_protected() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var inv: Inventory = g[1]
	grid.place("foundation", Vector2i(0, 0), N, inv)
	grid.place("wall", Vector2i(0, 0), E, inv)
	eq(grid.remove("f:0:0", inv), "Remove the walls on it first", "would leave a floating wall")
	grid.place("foundation", Vector2i(1, 0), N, inv)
	eq(grid.remove("f:0:0", inv), "", "fine once the neighbour holds the wall up")
	eq(grid.pieces.size(), 2, "wall and neighbour remain")


func test_signals_report_changes() -> void:
	var g: Array = _fresh()
	var grid: BuildGrid = g[0]
	var log := []
	grid.piece_added.connect(func(k: String) -> void: log.append("+" + k))
	grid.piece_removed.connect(func(k: String, _p: Dictionary) -> void: log.append("-" + k))
	grid.place("foundation", Vector2i(0, 0), N, g[1])
	grid.place("foundation", Vector2i(0, 0), N, g[1])  # fails, no signal
	grid.remove("f:0:0", g[1])
	eq(log, ["+f:0:0", "-f:0:0"], "one add, one remove")
