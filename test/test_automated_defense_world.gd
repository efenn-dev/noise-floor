extends "res://test/base_test.gd"
## M15 world side: the sensor screen picks an action, the base log screen lists the log newest first, every new
## piece gets a body (walk-over ones on the trap layer), and lit floodlights get a light.

const N := BuildGrid.Side.NORTH


func _sim(hour := 22.0) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.inventory.give_all({"plank": 400, "nails": 1000, "metal_plate": 200, "scrap_metal": 100, "gas_can": 10})
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func test_the_sensor_screen_picks_an_action() -> void:
	var sim := _sim()
	sim.build.place("motion_sensor", Vector2i(0, 0), N, sim.inventory)
	var key := sim.build.key_for("motion_sensor", Vector2i(0, 0))
	var screen := SensorScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open(key)
	check(screen.is_open(), "E on a sensor opens it")
	for a: String in ["quiet", "floodlights", "decoy", "lock_doors"]:
		check(screen.button("Action_" + a) != null, "a button for %s" % a)
	check(screen.button("Action_quiet").text.begins_with("[x] Quiet mode"), "quiet mode is ticked to start")
	var said := []
	screen.message.connect(func(t: String) -> void: said.append(t))
	screen.button("Action_decoy").pressed.emit()
	eq(sim.automation.sensors[key]["action"], "decoy", "clicking Decoy picks it")
	eq(said, ["Sensor action: Decoy"], "and says so")
	check(screen.button("Action_decoy").text.begins_with("[x] Decoy"), "now Decoy is ticked")
	screen.close()
	screen.free()


func test_the_base_log_screen_lists_newest_first() -> void:
	var sim := _sim()
	var screen := BaseLogScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	eq(screen.text(), "Nothing has happened at your base yet.", "empty to start")
	sim.base_log.now = "day 2 21:10"
	sim.base_log.add("West wall under attack: 6 zombies", Vector3.ZERO)
	sim.base_log.now = "day 2 21:12"
	sim.base_log.add("Nail turret out of nails", Vector3.ZERO)
	screen.refresh()
	eq(screen.text(), "day 2 21:12  Nail turret out of nails\nday 2 21:10  West wall under attack: 6 zombies", "newest first, with the time")
	screen.close()
	screen.free()


func test_every_new_piece_gets_a_body_and_floodlights_light_up() -> void:
	var sim := _sim()
	var view := BuildView.new()
	tree.root.add_child(view)
	view.setup(sim.build)
	var dv := DefenseView.new()
	tree.root.add_child(dv)
	dv.setup(sim, view)
	var ids := ["crossbow_turret", "rifle_turret", "hopper", "motion_sensor", "noise_sensor", "floodlight", "noisemaker",
			"bear_trap", "repair_station", "generator"]
	for i in ids.size():
		var cell := Vector2i(i * 2, 0)
		sim.build.place("foundation", cell, 0, sim.inventory)
		eq(sim.build.place(ids[i], cell, N, sim.inventory), "", "place %s" % ids[i])
	for id: String in ["tripwire", "electric_fence"]:
		eq(sim.build.place(id, Vector2i(ids.find("hopper") * 2 + (0 if id == "tripwire" else 1), 3), N, sim.inventory), "", "place %s" % id)
	for key: String in sim.build.pieces:
		check(view.body_for(key) != null, "%s has a body" % key)
	var trap := view.body_for(sim.build.key_for("bear_trap", Vector2i(ids.find("bear_trap") * 2, 0)))
	eq(trap.collision_layer, Layers.TRAP, "you walk over a bear trap")
	var wire := view.body_for(BuildGrid.key_for_wall_edge(Vector2i(ids.find("hopper") * 2, 3), N))
	eq(wire.collision_layer, Layers.TRAP, "and a tripwire")
	var rifle := view.body_for(sim.build.key_for("rifle_turret", Vector2i(2, 0)))
	check(rifle.get_node_or_null("Head/Barrel") != null, "the rifle turret's head has its long barrel")
	var light_key := sim.build.key_for("floodlight", Vector2i(ids.find("floodlight") * 2, 0))
	check(view.body_for(light_key).get_node_or_null("Lamp") != null, "the floodlight has a lamp")
	sim.toggle_floodlight(light_key)
	sim.power.free = true
	for i in 3:
		sim.step()
	check(sim.automation.floodlights[light_key]["lit"], "lit at night")
	dv._process(0.1)
	var spot := view.body_for(light_key).find_children("*", "SpotLight3D", true, false)
	check(spot.size() == 1 and spot[0].visible, "a spotlight shines from it")
	dv.free()
	view.free()
