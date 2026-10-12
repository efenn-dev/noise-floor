extends "res://test/base_test.gd"


func test_add_and_count() -> void:
	var inv := Inventory.new()
	inv.add("plank", 5)
	inv.add("plank", 3)
	inv.add("nails", 0)
	eq(inv.count("plank"), 8, "adds stack up")
	eq(inv.count("nails"), 0, "adding zero does nothing")
	eq(inv.items(), ["plank"], "only held items are listed")


func test_take_all_is_all_or_nothing() -> void:
	var inv := Inventory.new()
	inv.give_all({"plank": 4, "nails": 1})
	check(not inv.take_all({"plank": 3, "nails": 2}), "can't pay when short on one item")
	eq(inv.count("plank"), 4, "planks untouched after failed payment")
	check(inv.take_all({"plank": 4, "nails": 1}), "pays exact amount")
	eq(inv.items(), [], "empty stacks are dropped")


func test_remove_single_item() -> void:
	var inv := Inventory.new()
	inv.add("nails", 2)
	check(not inv.remove("nails", 3), "can't remove more than held")
	check(inv.remove("nails", 2), "removes what is there")
	eq(inv.count("nails"), 0, "now empty")


func test_changed_signal_fires() -> void:
	var inv := Inventory.new()
	var hits := [0]
	inv.changed.connect(func() -> void: hits[0] += 1)
	inv.add("plank", 1)
	inv.take_all({"plank": 1})
	inv.take_all({"plank": 1})  # fails, no signal
	eq(hits[0], 2, "signal on add and successful take only")
