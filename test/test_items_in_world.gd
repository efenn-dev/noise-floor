extends "res://test/base_test.gd"
## V34 (Emmitt: "skins for the items dropped, also allow placing items"): dropped and placed things lie in the
## world as themselves (own model, turned the way they went down), stack when dropped on the same spot, are
## picked up with E, survive a save, and every item and wearable has a model to show.

const PLAIN := ["Item Cardboard", "Item Paper", "Item Glass", "Item Food", "Item Label"]


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 9, "normal")
	sim.player_pos = Vector3(2, 0, 3)
	sim.player_facing = Vector3(0, 0, -1)
	return sim


func test_a_drop_lies_in_front_of_you_as_itself_and_stacks() -> void:
	var sim := _sim()
	sim.inventory.add("canned_food", 3)
	eq(sim.drop_items("canned_food", 1), "Dropped 1 Canned food", "dropped")
	var lying: Dictionary = sim.bags.back()
	eq(lying["kind"], SimWorld.ITEM, "as itself, not in a bag")
	eq(SimWorld.lying_look(lying), "canned_food", "it looks like a can")
	near((lying["pos"] as Vector3).distance_to(sim.player_pos), SimWorld.DROP_AHEAD, "a step in front of you", 0.01)
	check((lying["pos"] as Vector3).z < sim.player_pos.z, "in the direction you face")
	var count := sim.bags.size()
	sim.drop_items("canned_food", 2)
	eq(sim.bags.size(), count, "the same thing dropped on the same spot joins the stack")
	eq(int(lying["items"]["canned_food"]), 3, "three cans in it")
	eq(sim.lying_name(lying["id"]), "3 Canned food", "its name says how many")
	sim.inventory.add("nails", 5)
	sim.drop_items("nails", 5)
	eq(sim.bags.size(), count + 1, "something else lies on its own")
	var took := sim.take_bag(lying["id"])
	eq(int(took.get("canned_food", 0)), 3, "E picks the stack back up")
	eq(sim.inventory.count("canned_food"), 3, "into your pockets")


func test_gear_drops_and_places_as_itself() -> void:
	var sim := _sim()
	var jacket := sim.gear.make("jacket", "civilian", "white")
	sim.gear.pieces.append(jacket)
	sim.drop_gear(int(jacket["uid"]))
	var lying: Dictionary = sim.bags.back()
	eq(SimWorld.lying_look(lying), "jacket", "a dropped jacket looks like a jacket")
	eq(sim.lying_name(lying["id"]), str(jacket["name"]), "and is named like one")
	sim.take_bag(lying["id"])
	check(not sim.gear.find(int(jacket["uid"])).is_empty(), "picked up again")
	eq(sim.place_gear(int(jacket["uid"]), sim.player_pos + Vector3(0.5, 0.9, -1), 1.2), "", "and placed on a table")
	eq(float(sim.bags.back()["yaw"]), 1.2, "turned the way it was put down")
	check(sim.gear.find(int(jacket["uid"])).is_empty(), "out of your pockets")


func test_placing_puts_one_down_where_you_aim_within_reach() -> void:
	var sim := _sim()
	sim.inventory.add("soda", 2)
	var on_counter := sim.player_pos + Vector3(0.4, 0.92, -1.1)
	eq(sim.place_item("soda", on_counter, 0.5), "", "a soda on the counter in front of you")
	var lying: Dictionary = sim.bags.back()
	eq(lying["pos"], on_counter, "exactly where you aimed")
	eq(int(lying["items"]["soda"]), 1, "one at a time")
	eq(sim.inventory.count("soda"), 1, "one left in your pockets")
	eq(sim.place_item("soda", sim.player_pos + Vector3(0, 0, -6), 0.0), "Too far away", "not across the room")
	eq(sim.place_item("soda", sim.player_pos + Vector3(0, 3.5, -1), 0.0), "Too far away", "not on the roof")
	eq(sim.place_item("chips", on_counter, 0.0), "No chips left", "only what you have")
	eq(sim.place_item("soda", Vector3.INF, 0.0), "Nowhere to put it", "and only somewhere")


func test_items_in_the_world_survive_a_save() -> void:
	var sim := _sim()
	sim.inventory.add("radio", 1)
	sim.place_item("radio", sim.player_pos + Vector3(0, 0.8, -1), 2.0)
	sim.drop_bag(Vector3(9, 0, 9), {"plank": 2})
	var path := "user://test_items_in_world.json"
	eq(SaveGame.write(sim, path), "", "saved")
	var back := SimWorld.new(12.0, null, 9, "normal")
	eq(SaveGame.apply(back, SaveGame.read(path)), "", "loaded")
	var radio: Dictionary = back.bags.filter(func(b: Dictionary) -> bool: return SimWorld.lying_look(b) == "radio")[0]
	eq(radio["kind"], SimWorld.ITEM, "the radio is still a radio")
	near(float(radio["yaw"]), 2.0, "still turned the same way")
	check(back.bags.any(func(b: Dictionary) -> bool: return b["kind"] == SimWorld.BAG), "the death bag is still a bag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_older_save_loads_its_bags_as_bags() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v20.json")
	eq(int(d["version"]), 20, "a version-20 save")
	var sim := SimWorld.new(12.0, null, int(d["seed"]), "normal")
	eq(SaveGame.apply(sim, d), "", "it loads")
	eq(sim.bags.size(), 2, "both of its bags")
	for b: Dictionary in sim.bags:
		eq(b["kind"], SimWorld.BAG, "each one a bag, where it was")
		near(float(b["yaw"]), 0.0, "lying flat")


func test_every_item_and_wearable_has_a_model_that_lies_on_the_floor() -> void:
	var data := GameData.load_default()
	var looks: Array = data.items.keys()
	for base: String in data.gear["bases"]:
		looks.append(base)
	for look: String in looks:
		var path := BagView.model_path(look)
		check(path != "", "%s has a model to lie on the ground" % look)
		if path == "":
			continue
		var model := BagView.make_model(look)
		var box := BagView.bounds(model)
		near(box.position.y, 0.0, "%s rests on the floor" % look, 0.002)
		near(box.get_center().x, 0.0, "%s is centred where it was put" % look, 0.002)
		check(box.size.x < 1.3 and box.size.y < 1.0 and box.size.z < 1.3, "%s is a sensible size (%s)" % [look, box.size])
		if path.contains("/item_"):
			for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for i in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(i)
					var name := mat.resource_name if mat != null else ""
					check(BagView.ITEM_LOOKS.has(name) or name in PLAIN,
							"%s: material '%s' is textured or meant to be plain" % [look, name])
		model.free()


## V38: a dropped melee weapon lies on its flat side, not balanced on its edge: an axe shows the side of its
## head, so it lies about as low as the head is thick, not as tall as the head is long (20 cm).
func test_dropped_blades_lie_flat() -> void:
	for look: String in ["axe", "machete", "knife"]:
		var model := BagView.make_model(look)
		var box := BagView.bounds(model)
		check(box.size.y < 0.06, "a dropped %s lies on its side (%.3f m high)" % [look, box.size.y])
		model.free()


func test_the_placer_puts_it_on_the_floor_you_aim_at_not_a_wall() -> void:
	var sim := _sim()
	sim.player_pos = Vector3.ZERO
	sim.inventory.add("soda", 2)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	cs.shape = box
	cs.position.y = -0.1
	floor_body.add_child(cs)
	tree.root.add_child(floor_body)
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50.0), 0.0, 0.0)), Vector3(0, 1.6, 0))  # looking down ahead
	var placer := Placer.new()
	tree.root.add_child(placer)
	placer.setup(sim, cam, [])
	placer.start("soda")
	check(placer.active(), "placing a soda")
	for i in 3:  # the new floor joins the physics space
		await tree.physics_frame
	placer._process(0.0)
	var msg := placer.place()
	eq(msg, "Placed soda (1 left)", "it goes down where you aim")
	var lying: Dictionary = sim.bags.back()
	near((lying["pos"] as Vector3).y, 0.0, "on the floor", 0.01)
	check((lying["pos"] as Vector3).z < -0.5, "in front of you")
	cam.transform = Transform3D(Basis(), Vector3(0, 1.6, 0))  # looking straight ahead at nothing within reach
	placer._process(0.0)
	eq(placer.place(), "Aim at a floor, table or shelf", "nothing under the crosshair: nowhere to put it")
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50.0), 0.0, 0.0)), Vector3(0, 1.6, 0))
	placer._process(0.0)
	placer.place()
	check(not placer.active(), "the last one placed: the placer stops")
	placer.queue_free()
	cam.queue_free()
	floor_body.queue_free()
	await tree.process_frame
