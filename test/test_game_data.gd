extends "res://test/base_test.gd"


func test_shipped_data_is_valid() -> void:
	var data := GameData.load_default()
	var errors := data.validate()
	eq(errors.size(), 0, "data/ validates: %s" % ", ".join(errors))
	check(data.buildables.has("foundation") and data.buildables.has("wall"), "has foundation and wall")
	check(not data.debug_kit.is_empty(), "debug kit gives something")


func test_pieces_fit_the_grid() -> void:
	var data := GameData.load_default()
	var f: Vector3 = data.buildables["foundation"]["size"]
	var w: Vector3 = data.buildables["wall"]["size"]
	near(f.x, BuildGrid.GRID, "foundation is one cell wide")
	near(f.z, BuildGrid.GRID, "foundation is one cell deep")
	near(w.x, BuildGrid.GRID, "wall spans one cell edge")
	check(f.y <= 0.1 + 1e-4, "foundation is low enough to walk onto (%.2f m)" % f.y)


func test_kit_can_build_something() -> void:
	var data := GameData.load_default()
	var inv := Inventory.new()
	inv.give_all(data.debug_kit)
	for id: String in data.buildables:
		check(inv.has_all(data.buildables[id]["cost"]), "debug kit affords a %s" % id)


func test_validator_catches_mistakes() -> void:
	var data := GameData.new()
	data.load_from({"plank": {"name": "Plank"}},
		{"bad": {"kind": "roof", "size": [2, 0, 2], "cost": {"gold": 1}}},
		{"unobtainium": 3})
	var text := " | ".join(data.validate())
	check("unknown kind" in text, "flags unknown kind")
	check("positive" in text, "flags zero size")
	check("unknown item 'gold'" in text, "flags unknown cost item")
	check("debug kit has unknown item" in text, "flags unknown kit item")
