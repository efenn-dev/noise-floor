extends "res://test/base_test.gd"
## F2 (Emmitt: building "more like Satisfactory"): the Hub's milestones unlock the advanced pieces tier by tier;
## the last one unlocks the radio mast, whose one-night rescue broadcast wins the game.

const TICK := SimWorld.TICK


func _sim(hour: float = 12.0) -> SimWorld:
	var sim := SimWorld.new(hour, null, 6, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	sim.milestones.done.clear()  # a real new game: every milestone ahead (test worlds start unlocked)
	return sim


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999, "wall_panel": 99, "gas_can": 99,
			"radio": 9, "dirty_water": 99})
	return inv


func _hub(sim: SimWorld, cell: Vector2i = Vector2i(4, 8)) -> String:
	eq(sim.build.place("hub", cell, BuildGrid.Side.NORTH, _rich()), "", "a Hub built")
	return sim.hub_key()


func test_the_data_checks_out() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "milestones.json checks out")
	var m := Milestones.new(data)
	check(m.all().size() >= 6, "there are milestones to do (%d)" % m.all().size())
	eq(m.final_id(), "rescue_signal", "the last one is the rescue signal")
	eq(m.unlocked_by("radio_mast"), "rescue_signal", "which unlocks the radio mast")


func test_tiers_open_in_order_and_parts_go_in_part_at_a_time() -> void:
	var sim := _sim()
	var m := sim.milestones
	check(m.available("salvage_rig") and m.available("lumber_yard"), "tier 1 is open from the start")
	check(not m.available("fuel_line"), "tier 2 waits")
	var inv := Inventory.new()
	inv.give_all({"plank": 5})
	var moved := m.deliver("salvage_rig", inv)
	eq(int(moved.get("plank", 0)), 5, "part of the parts go in")
	eq(int(m.missing("salvage_rig")["plank"]), 15, "and stay handed in")
	check(not m.is_done("salvage_rig"), "not done yet")
	m.deliver("salvage_rig", _rich())
	check(m.is_done("salvage_rig"), "the rest goes in: done")
	check(not m.available("fuel_line"), "tier 2 still waits for the rest of tier 1")
	m.deliver("lumber_yard", _rich())
	check(m.available("fuel_line") and m.available("sentry"), "all of tier 1 done: tier 2 opens")
	check(not m.available("heavy_defense"), "tier 3 still waits")


func test_milestones_lock_and_unlock_pieces() -> void:
	var sim := _sim()
	var heap: Dictionary = sim.resource_nodes.filter(func(n: Dictionary) -> bool: return n["kind"] == "scrap_heap")[0]
	check(sim.build.can_place("salvager", heap["cell"], BuildGrid.Side.NORTH, _rich()).begins_with("Unlock it at the Hub: Salvage rig"),
			"a new game: the salvager says which milestone opens it")
	check(sim.build.can_place("crossbow_turret", Vector2i(30, 30), BuildGrid.Side.NORTH, _rich()).begins_with("Unlock it at the Hub"),
			"so does a crossbow turret (F4: the nail turret is there from the start)")
	eq(sim.build.can_place("hub", Vector2i(30, 30), BuildGrid.Side.NORTH, _rich()), "", "the Hub itself is free")
	sim.milestones.deliver("salvage_rig", _rich())
	eq(sim.build.can_place("salvager", heap["cell"], BuildGrid.Side.NORTH, _rich()), "", "done: the salvager can go on its spot")
	check(sim.milestones.unlocked("smelter") and sim.milestones.unlocked("foundation"), "the basics are never locked")


func test_one_hub_and_handing_in_from_crates_near_it() -> void:
	var sim := _sim()
	eq(sim.hub_deliver("salvage_rig"), "Build a Hub first", "no Hub: nothing to hand in to")
	var hub := _hub(sim)
	check(sim.build.can_place("hub", Vector2i(10, 10), BuildGrid.Side.NORTH, _rich()) == "You already have a Hub", "one Hub a game")
	sim.inventory.give_all({"plank": 20})
	var crate_cell := Vector2i(6, 8)
	sim.build.place("foundation", crate_cell, BuildGrid.Side.NORTH, _rich())
	eq(sim.build.place("storage", crate_cell, BuildGrid.Side.NORTH, _rich()), "", "a crate beside the Hub")
	var crate_key := ""
	for key: String in sim.storages:
		if sim.build.pieces[key]["cell"] == crate_cell:
			crate_key = key
	(sim.storages[crate_key] as Inventory).give_all({"scrap_metal": 20, "nails": 10})
	var msg := sim.hub_deliver("salvage_rig")
	check(msg.begins_with("Salvage rig done!"), "pockets and the crate together finish it (%s)" % msg)
	check(msg.contains("Salvager") and msg.contains("Water pump"), "and say what it unlocked")
	eq(sim.inventory.count("plank"), 0, "the planks came from your pockets")
	eq((sim.storages[crate_key] as Inventory).count("scrap_metal"), 0, "the scrap from the crate")
	check(hub != "", "the Hub is there")


func test_the_rescue_broadcast() -> void:
	var sim := _sim(12.0)
	sim.power.free = true
	sim.milestones.grant_all_but_final()
	sim.milestones.deliver(sim.milestones.final_id(), _rich())
	check(sim.milestones.is_done("rescue_signal"), "the rescue signal milestone done")
	eq(sim.build.place("radio_mast", Vector2i(-6, 6), BuildGrid.Side.NORTH, _rich()), "", "the radio mast built")
	var mast := sim.mast_key()
	check(sim.start_broadcast(mast).begins_with("Start the broadcast at dusk"), "not at noon")
	sim.clock.time_of_day = 19.0
	check(sim.start_broadcast(mast).begins_with("Broadcasting!"), "at dusk it starts")
	eq(sim.rescue_state, "broadcasting", "broadcasting")
	sim.step()
	var loud := false
	for src: Dictionary in sim.noise.continuous:
		if src.get("kind", "") == "radio_mast" and float(src["loudness"]) >= 100.0:
			loud = true
	check(loud, "and every zombie for miles hears it")
	sim.broadcast_hours = float(sim.data.milestones["broadcast_hours"]) - 1e-6  # F4: a night of powered signal
	sim.step()
	check(sim.rescue_due >= 0.0, "enough signal: they heard you")
	sim.clock.day += 1
	sim.clock.time_of_day = 6.1
	sim.step()
	eq(sim.rescue_state, "rescued", "the mast stood till dawn: rescued")
	eq(sim.rescue_day, sim.clock.day, "on this morning")


func test_a_fallen_mast_loses_the_broadcast() -> void:
	var sim := _sim(20.0)
	sim.power.free = true  # F4: the mast needs power to broadcast
	sim.milestones.grant_all_but_final()
	sim.milestones.deliver(sim.milestones.final_id(), _rich())
	sim.build.place("radio_mast", Vector2i(-6, 6), BuildGrid.Side.NORTH, _rich())
	var mast := sim.mast_key()
	sim.start_broadcast(mast)
	sim.build.remove(mast, Inventory.new())
	sim.step()
	eq(sim.rescue_state, "", "the mast fell: the broadcast is lost")
	check(sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).begins_with("The radio mast fell")), "and it says so")


func test_saves_keep_the_hub_and_old_saves_keep_their_pieces() -> void:
	var sim := _sim()
	sim.milestones.deliver("salvage_rig", _rich())
	var inv := Inventory.new()
	inv.give_all({"plank": 4})
	sim.milestones.deliver("lumber_yard", inv)
	sim.rescue_state = "broadcasting"
	sim.rescue_day = 3
	var path := "user://test_hub_milestones.json"
	eq(SaveGame.write(sim, path), "", "saved")
	var back := _sim()
	eq(SaveGame.apply(back, SaveGame.read(path)), "", "loaded")
	check(back.milestones.is_done("salvage_rig"), "a done milestone stays done")
	eq(int(back.milestones.delivered["lumber_yard"]["plank"]), 4, "half-handed-in parts stay handed in")
	eq(back.rescue_state, "broadcasting", "the broadcast carries on")
	eq(back.rescue_day, 3, "from the same night")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var old := SaveGame.read("res://test/fixtures/save_v21.json")
	eq(int(old["version"]), 21, "a save from before the Hub")
	var migrated := SimWorld.new(12.0, null, int(old["seed"]), "normal")
	eq(SaveGame.apply(migrated, old), "", "loads")
	check(migrated.milestones.unlocked("nail_turret") and migrated.milestones.unlocked("salvager"), "everything it could build stays buildable")
	check(not migrated.milestones.is_done("rescue_signal"), "but the rescue is still ahead")


## The Hub and mast lookups come from an index kept up to date wherever pieces change (the mast's lamp asks
## every frame, so it mustn't walk every piece in the world).
func test_hub_and_mast_lookups_follow_every_change() -> void:
	var sim := _sim()
	eq(sim.hub_key(), "", "no Hub yet")
	eq(sim.mast_key(), "", "no mast yet")
	var key := _hub(sim)
	check(key != "" and sim.build.pieces.has(key), "built: found")
	eq(sim.build.remove(key, _rich()), "", "taken down")
	eq(sim.hub_key(), "", "gone from the lookup")
	key = _hub(sim)
	sim.build.destroy(key)
	eq(sim.hub_key(), "", "wrecked by zombies: gone too")
	sim.milestones.grant_all_but_final()
	sim.milestones.done.append(sim.milestones.final_id())
	eq(sim.build.place("radio_mast", Vector2i(8, 8), BuildGrid.Side.NORTH, _rich()), "", "a mast")
	var mast := sim.mast_key()
	check(mast != "", "found")
	var d := SaveGame.to_dict(sim)
	var back := _sim()
	eq(SaveGame.apply(back, d), "", "saved and loaded")
	eq(back.mast_key(), mast, "found after a load")
	eq(sim.build.place("hub", Vector2i(2, 2), BuildGrid.Side.NORTH, _rich()), "", "a Hub again")
	check(sim.build.can_place("hub", Vector2i(12, 2), BuildGrid.Side.NORTH, _rich()) == "You already have a Hub", "still only one")

