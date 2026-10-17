extends "res://test/base_test.gd"
## P11 (playtest: "We need a way to chop down trees for lumber and a way to get metal scrap"): melee hits fell trees
## for planks and strip cars that won't drive (and the highway's wrecks) for scrap metal (Salvage, SimWorld
## player_hit_tree / player_hit_wreck), in the sim and in the game scene.

const MAIN := "res://scenes/main.tscn"


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 6, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	return sim


func _hold(sim: SimWorld, base: String) -> void:
	var piece := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(piece)
	eq(sim.gear.equip(piece["uid"]), "", "holding the %s" % base)


func _hits_to_fell(sim: SimWorld, id: String, kind: String) -> int:
	var hits := 0
	while not sim.salvage.felled.has(id) and hits < 200:
		sim.player_hit_tree(id, kind, Vector3(5, 0, 5))
		hits += 1
	return hits


func test_the_data_checks_out() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "the data checks out")
	var cfg: Dictionary = data.resources["salvage"]
	for kind: String in CountryView.TREES:
		check(cfg["trees"].has(kind) and int(cfg["trees"][kind]["planks"]) > 0, "%s gives planks" % kind)
	for type: String in data.vehicles:
		check(int(cfg["wrecks"].get(type, 0)) > 0, "a %s wreck has scrap in it" % type)
	for cls: String in ["axe", "blade", "blunt", "fists"]:
		check(cfg["wood_factor"].has(cls) and cfg["metal_factor"].has(cls), "%s hits wood and metal" % cls)
	for kind: String in ["chop", "tree_fall", "metal_strip"]:
		check(data.noise["sounds"].has(kind), "%s is a noise" % kind)
		check(SoundView.EVENTS.has(kind) and ResourceLoader.exists("res://assets/sounds/%s.wav" % kind), "and has a sound")
	check("chop down a tree" in String(data.items["plank"]["where"]), "planks say trees")
	check("broken-down car" in String(data.items["scrap_metal"]["where"]), "scrap says cars")


func test_an_axe_fells_a_tree_quickly_and_a_pipe_slowly() -> void:
	var sim := _sim()
	_hold(sim, "axe")
	var axe := _hits_to_fell(sim, "tree_a", "tree")
	check(axe >= 4 and axe <= 6, "an axe fells a tree in about five hits (%d)" % axe)
	eq(sim.inventory.count("plank"), 6, "six planks in your pockets")
	eq(sim.player_hit_tree("tree_a", "tree", Vector3.ZERO), "", "a felled tree can't be hit again")
	var sim2 := _sim()
	_hold(sim2, "pipe")
	var pipe := _hits_to_fell(sim2, "tree_a", "tree")
	check(pipe > axe * 2 and pipe < 30, "a pipe takes far longer (%d hits)" % pipe)
	var sim3 := _sim()
	sim3.gear.equipped.erase("weapon")  # bare-handed
	var fists := _hits_to_fell(sim3, "tree_a", "pine_tree_small")
	check(fists > 10 and fists < 40, "a small pine falls to bare fists, slowly (%d)" % fists)
	eq(sim3.inventory.count("plank"), 3, "and gives three planks")


func test_chopping_is_heard_wears_the_axe_and_full_pockets_drop_the_rest() -> void:
	var sim := _sim()
	_hold(sim, "axe")
	var cond := float(sim.gear.equipped["weapon"]["condition"])
	var said := sim.player_hit_tree("tree_c", "tree", Vector3(3, 0, 3))
	check(said.begins_with("Chopping: "), "a hit says how far along (%s)" % said)
	eq(String(sim.noise._pending.back()["kind"]), "chop", "a chop is a noise")
	check(float(sim.gear.equipped["weapon"]["condition"]) < cond, "and wears the axe")
	sim.inventory.add("metal_plate", 39)  # 19.5 kg of a 20 kg limit
	var bags := sim.bags.size()
	while not sim.salvage.felled.has("tree_c"):
		said = sim.player_hit_tree("tree_c", "tree", Vector3(3, 0, 3))
	check(said.begins_with("Timber!") and "on the ground" in said, "full pockets: the planks that don't fit lie on the ground (%s)" % said)
	eq(String(sim.noise._pending.back()["kind"]), "tree_fall", "a falling tree is louder")
	eq(sim.bags.size(), bags + 1, "one pile")
	eq(int(sim.bags[-1]["items"]["plank"]) + sim.inventory.count("plank"), 6, "every plank is somewhere")
	eq(sim.salvage.last_felled, "tree_c", "the views know which tree to tip over")


func test_broken_cars_and_wrecks_give_scrap_but_running_cars_dont() -> void:
	var sim := _sim()
	sim.add_car("car_0", "sedan", Vector3(0, 0.75, -10))  # car_0 always drives
	sim.vehicles.add("junker", "pickup", Vector3(6, 0.9, -10), 0.0, 0, "Flat tyres", "lost")
	sim.salvage.wrecks["hw_1"] = "sedan"  # a highway wreck (CountryPlan)
	_hold(sim, "pipe")
	eq(sim.wreck_type("car_0"), "", "a car that drives isn't a wreck")
	check("still runs" in sim.player_hit_wreck("car_0", Vector3.ZERO), "hitting it says so")
	eq(sim.inventory.count("scrap_metal"), 0, "and gives nothing")
	eq(sim.wreck_type("junker"), "pickup", "a car with flat tyres is")
	var hits := 0
	var said := ""
	while sim.salvage.scrap_left("junker", "pickup") > 0 and hits < 100:
		said = sim.player_hit_wreck("junker", Vector3(6, 1, -10))
		hits += 1
	eq(sim.inventory.count("scrap_metal"), 10, "a pickup gives ten scrap metal")
	check(hits >= 12 and hits <= 20, "a pipe strips it in a dozen or so hits (%d)" % hits)
	check("(0 left in it)" in said, "the last says it's empty (%s)" % said)
	eq(String(sim.noise._pending.back()["kind"]), "metal_strip", "stripping is loud")
	check("nothing left" in sim.player_hit_wreck("junker", Vector3.ZERO), "a stripped car says so")
	eq(sim.wreck_type("hw_1"), "sedan", "a highway wreck can be stripped too")
	while sim.salvage.scrap_left("hw_1", "sedan") > 0:
		sim.player_hit_wreck("hw_1", Vector3.ZERO)
	eq(sim.inventory.count("scrap_metal"), 18, "eight more from a sedan")


func test_felled_trees_and_stripped_cars_are_saved() -> void:
	var sim := _sim()
	_hold(sim, "axe")
	_hits_to_fell(sim, "tree_9", "tree")
	sim.salvage.wrecks["hw_2"] = "van"
	sim.player_hit_wreck("hw_2", Vector3.ZERO)
	sim.player_hit_wreck("hw_2", Vector3.ZERO)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	var s := Salvage.new(sim.data)
	s.load_dict(d["salvage"])
	check(s.felled.has("tree_9"), "a felled tree stays down")
	eq(s.scrap_left("hw_2", "van"), sim.salvage.scrap_left("hw_2", "van"), "a wreck keeps what you took")
	var before := s.changes
	s.load_dict({})
	check(s.felled.is_empty() and s.changes > before, "an older save has every tree standing, and the views look again")


func test_swinging_at_a_town_tree_fells_it_in_the_game() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var street: StreetView = main.street_view
	var body: StaticBody3D = null
	for b: StaticBody3D in street.bodies:
		if b.get_meta("street_kind", "") == "tree":
			body = b
			break
	check(body != null, "the town has a tree")
	var info: Array = body.get_meta("tree")
	eq(info[0], Salvage.tree_id(info[2]), "it knows its id")
	_hold(sim, "axe")
	# Stand a step from the trunk, facing it.
	var cam: Camera3D = main.player.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var foot: Vector3 = info[2]
	main.player.global_position = Vector3(foot.x, main.player.global_position.y, foot.z) - fwd * 1.2
	for i in 6:
		await tree.physics_frame
	sim.player_pos = main.player.global_position
	main.interactor.update_target()
	eq(main.interactor.target_tree, info, "looking at it, the interactor sees the tree")
	check("chop it down for planks" in main.interactor.status_text(), "and says what to do (%s)" % main.interactor.status_text())
	main.melee.swing()
	check(main.melee.last_message.begins_with("Chopping"), "a real swing chops it (%s)" % main.melee.last_message)
	while not sim.salvage.felled.has(info[0]):
		sim.player_hit_tree(info[0], info[1], info[2])
	for i in 4:
		await tree.process_frame
	check((body.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D).disabled, "felled: you can walk through where it stood")
	var waited := 0.0
	while body.visible and waited < CountryView.FALL_TIME + 1.0:
		await tree.process_frame
		waited += 1.0 / 60.0
	check(not body.visible, "it tips over and is gone (%.1f s)" % waited)
	# The countryside's trees: one shape per trunk, each with its id.
	var country: CountryView = main.country_view
	var solid := country.get_node_or_null("Solid_pine_tree") as StaticBody3D
	check(solid != null and solid.has_meta("trees"), "the pines' trunks carry their ids")
	var first: Array = CountryView.tree_at(solid, 0)
	eq(first[1], "pine_tree", "shape 0 is a pine")
	sim.salvage.felled[first[0]] = true
	sim.salvage.changes += 1
	await tree.process_frame
	check(country.is_gone(first[0]), "a felled pine is taken out")
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
