extends "res://test/base_test.gd"
## F5 part 2 (loudness as a puzzle): hordes go for the sound that's loudest outside its walls, and the wave says
## where; supply carts drive an outpost's crates home along the roads; a decoy noisemaker shakes itself apart a
## little with every blare.

const N := 0
const E := 1
const S := 2
const W := 3
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999, "wall_panel": 99, "gas_can": 20})
	return inv


## A world where nothing else happens: no zombies, no first-night beats.
func _quiet_sim(hour: float = 12.0) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	sim.player_pos = Vector3(0, 0, 0)
	return sim


func _walls_round(sim: SimWorld, cell: Vector2i, id: String = "wall") -> void:
	sim.build.place("foundation", cell, N, _rich())
	for side: int in [N, E, S, W]:
		eq(sim.build.place(id, cell, side, _rich()), "", "%s on side %d" % [id, side])


func test_a_horde_goes_for_the_loudest_sound_outside() -> void:
	var sim := _quiet_sim()
	var home := Vector3(81, 1, 81)   # cell (40, 40)
	var outpost := Vector3(161, 1, 81)  # cell (80, 40), 80 m east, out in the open
	sim.noise.continuous = [{"pos": home, "loudness": 70.0, "key": "home", "kind": "test"},
			{"pos": outpost, "loudness": 65.0, "key": "outpost", "kind": "test"}]
	eq(sim.director._loudest(sim.noise)["key"], "home", "both in the open: the louder one at home")
	_walls_round(sim, Vector2i(40, 40))
	sim.director._walls_cache.clear()
	eq(sim.director._loudest(sim.noise)["key"], "outpost", "walled in at home: the outpost is louder outside, so it's the target")


func test_the_wave_says_what_its_heading_for() -> void:
	var sim := _quiet_sim()
	var stock := _rich()
	sim.build.place("foundation", Vector2i(0, 0), N, stock)
	sim.build.place("smelter", Vector2i(0, 0), E, stock)
	var key := sim.build.key_for("smelter", Vector2i(0, 0))
	check(sim.wave_target_words({"key": key}).begins_with("your smelter"), "a wave at a smelter: 'your smelter ...'")
	eq(sim.wave_target_words({"key": "car_0"}), "", "a car isn't one of your pieces: nothing said")
	sim.power.free = true
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 99
	sim.clock.time_of_day = 23.0
	sim.director.heat = 120.0
	sim.director._check = 0.0
	sim.director._gain_timer = 0.0
	sim.messages.clear()
	for i in 10:
		sim.step()
	check(sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).contains("heading for your smelter")),
			"the warning says the horde is heading for your smelter")


## Two cart stops 80 m apart along the main road, each with a storage crate beside it. The first built is home.
func _cart_world() -> Dictionary:
	var sim := _quiet_sim()
	var stock := _rich()
	var home_cell := Vector2i(1, 10)
	var pick_cell := Vector2i(1, 50)
	for c: Vector2i in [home_cell, pick_cell]:
		eq(sim.build.place("cart_stop", c, N, stock), "", "a cart stop at %s" % c)
		sim.build.place("foundation", c + Vector2i(1, 0), N, stock)
		eq(sim.build.place("storage", c + Vector2i(1, 0), N, stock), "", "a crate beside it")
	var home_key := sim.build.key_for("cart_stop", home_cell)
	var pick_key := sim.build.key_for("cart_stop", pick_cell)
	return {"sim": sim, "home": home_key, "pick": pick_key,
			"home_crate": sim.storages[sim.build.key_for("storage", home_cell + Vector2i(1, 0))],
			"pick_crate": sim.storages[sim.build.key_for("storage", pick_cell + Vector2i(1, 0))]}


func test_a_cart_brings_an_outposts_crate_home() -> void:
	var w := _cart_world()
	var sim: SimWorld = w["sim"]
	eq(sim.carts.home, w["home"], "the first stop built is home")
	check(sim.carts.carts.has(w["pick"]), "the second is a pickup with its own cart")
	(w["pick_crate"] as Inventory).add("scrap_metal", 50)
	sim.carts.tick(TICK)
	var c: Dictionary = sim.carts.carts[w["pick"]]
	eq(c["state"], "home", "something to carry: it sets off")
	eq(int(c["cargo"].get("scrap_metal", 0)), int(data.buildables["cart_stop"]["cap"]), "loaded up to its cap (40)")
	eq((w["pick_crate"] as Inventory).count("scrap_metal"), 10, "10 left behind")
	var length: float = sim.carts.path_of(w["pick"])["length"]
	check(length > 70.0, "it drives the roads (%.0f m)" % length)
	check(sim.carts.status(w["pick"]).contains("driving home with 40 items"), "the stop says so")
	var noisy := sim.carts.noise_sources()
	eq(noisy.size(), 1, "a moving cart is a noise source")
	near(float(noisy[0]["loudness"]), float(data.buildables["cart_stop"]["loudness"]), "at the stop's loudness")
	for i in roundi((length / float(data.buildables["cart_stop"]["speed"]) + 1.0) / TICK):
		sim.carts.tick(TICK)
	eq((w["home_crate"] as Inventory).count("scrap_metal"), 40, "home: unloaded into the crate by the home stop")
	eq(sim.carts.delivered, 40, "40 delivered")
	eq(c["state"], "back", "and on its way back")
	for i in roundi((length / float(data.buildables["cart_stop"]["speed"]) + 1.0) / TICK):
		sim.carts.tick(TICK)
	eq(c["state"], "home", "back at its stop it loads the rest and goes again")
	eq(int(c["cargo"].get("scrap_metal", 0)), 10, "the last 10")


func test_carts_count_in_the_session_log_and_wait_when_empty() -> void:
	var w := _cart_world()
	var sim: SimWorld = w["sim"]
	for i in 30:
		sim.step()
	eq(sim.carts.carts[w["pick"]]["state"], "wait", "nothing in the crate: it waits")
	eq(sim.carts.noise_sources().size(), 0, "silent while it waits")
	(w["pick_crate"] as Inventory).add("plank", 5)
	var length: float = sim.carts.path_of(w["pick"])["length"]
	for i in roundi((float(data.buildables["cart_stop"]["interval"]) + length / float(data.buildables["cart_stop"]["speed"]) + 2.0) / TICK):
		sim.step()
	eq((w["home_crate"] as Inventory).count("plank"), 5, "it noticed the planks and brought them home")
	eq(sim.stats.cart_items, 5, "the session log counts them")
	check(sim.stats.summary_lines().has("Supply carts brought home 5 items."), "and says so")


func test_removing_stops() -> void:
	var w := _cart_world()
	var sim: SimWorld = w["sim"]
	(w["pick_crate"] as Inventory).add("scrap_metal", 12)
	sim.carts.tick(TICK)
	var before := sim.inventory.count("scrap_metal")
	sim.build.remove(w["pick"], sim.inventory)
	eq(sim.inventory.count("scrap_metal") - before, 12 + int(data.buildables["cart_stop"]["cost"].get("scrap_metal", 0)),
			"pulling a pickup down gives back what its cart carried (and the stop)")
	check(not sim.carts.carts.has(w["pick"]), "its cart is gone")
	var w2 := _cart_world()
	var sim2: SimWorld = w2["sim"]
	(w2["pick_crate"] as Inventory).add("scrap_metal", 5)
	sim2.carts.tick(TICK)
	sim2.build.remove(w2["home"], sim2.inventory)
	eq(sim2.carts.home, "", "no home stop now")
	eq(sim2.carts.carts[w2["pick"]]["state"], "back", "the cart turns round")
	check(sim2.carts.status(w2["pick"]).contains("no home stop"), "and the stop says why")


func test_make_home_and_saving() -> void:
	var w := _cart_world()
	var sim: SimWorld = w["sim"]
	check(sim.make_cart_home(w["pick"]).begins_with("Home stop"), "E on the other stop makes it home")
	eq(sim.carts.home, w["pick"], "it's home now")
	check(sim.carts.carts.has(w["home"]) and not sim.carts.carts.has(w["pick"]), "the old home is a pickup")
	check(sim.make_cart_home(w["pick"]).begins_with("This is already"), "E again: already home")
	(w["home_crate"] as Inventory).add("nails", 7)
	sim.carts.tick(TICK)
	sim.carts.carts[w["home"]]["d"] = 12.5
	var back := SimWorld.new(12.0)
	SaveGame.apply(back, SaveGame.to_dict(sim))
	eq(back.carts.home, w["pick"], "the home stop saves and loads")
	check(back.carts.carts.has(w["home"]), "so does the pickup")
	near(float(back.carts.carts[w["home"]]["d"]), 12.5, "with where its cart is", 1e-4)
	eq(int(back.carts.carts[w["home"]]["cargo"].get("nails", 0)), 7, "and what it carries")


func test_a_decoy_shakes_itself_apart() -> void:
	var sim := _quiet_sim()
	sim.power.free = true
	var stock := _rich()
	eq(sim.build.place("noisemaker", Vector2i(30, 30), N, stock), "", "a noisemaker")
	var key := sim.build.key_for("noisemaker", Vector2i(30, 30))
	var wear := int(data.defense["noisemaker"]["wear"])
	var hp := int(sim.build.pieces[key]["hp"])
	var blares := ceili(float(hp) / float(wear))
	for b in blares:
		check(sim.automation.fire_noisemaker(key), "blare %d" % (b + 1))
		for i in roundi((float(data.defense["noisemaker"]["blare"]) + 0.5) / TICK):
			sim.automation.tick(TICK, sim.horde, false, [])
		if b < blares - 1:
			eq(int(sim.build.pieces[key]["hp"]), hp - wear * (b + 1), "each blare costs %d hp" % wear)
			sim.automation.noisemakers[key]["recharge"] = 0.0
	check(not sim.build.pieces.has(key), "after %d blares it fell apart" % blares)
	check(not sim.automation.noisemakers.has(key), "and is no longer a noisemaker")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("shook itself apart")), "the base log says so")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("nearly shaken apart")), "and warned first")


func test_the_cart_view_draws_a_cart_per_pickup() -> void:
	var w := _cart_world()
	var sim: SimWorld = w["sim"]
	var view := CartView.new(sim)
	tree.root.add_child(view)
	view._process(0.016)
	eq(view.get_child_count(), 1, "one pickup: one cart")
	var cart: Node3D = view.get_child(0)
	check(cart.position.distance_to(sim.carts.cart_at(w["pick"])["pos"]) < 0.01, "where the sim says")
	check(not (cart.get_node("Crate") as Node3D).visible, "empty: no crate on the back")
	(w["pick_crate"] as Inventory).add("plank", 3)
	sim.carts.tick(TICK)
	view._process(0.016)
	check((cart.get_node("Crate") as Node3D).visible, "loaded: a crate on the back")
	view.free()


func test_the_cart_stop_is_in_the_data_and_menus() -> void:
	eq(data.buildables["cart_stop"]["kind"], "cart_stop", "a cart stop")
	check(int(data.buildables["cart_stop"]["cap"]) > 0 and float(data.buildables["cart_stop"]["speed"]) > 0.0, "with a cap and a speed")
	check(BuildController.PIECES.has("cart_stop"), "it can be built")
	eq(data.load_errors.size(), 0, "the data loads clean")
