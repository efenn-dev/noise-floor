extends "res://test/base_test.gd"
## V12: first-person hands on every weapon and bare fists. The hands are children of the weapon, so they follow
## its swing; each is rolled so its forearm runs off the bottom of the screen at rest.

const MAIN := "res://scenes/main.tscn"


func test_every_weapon_has_its_hands() -> void:
	for id: String in Melee.MODELS:
		check(Hands.MELEE.has(id) and Hands.MELEE[id].has("right"), "%s has a right hand on the grip" % id)
	for id: String in ["bat", "axe"]:
		check(Hands.MELEE[id].has("left"), "the %s is two-handed" % id)
	for gun: String in Shooter.MODELS:
		check(Hands.GUNS.has(gun) and Hands.GUNS[gun].has("right") and Hands.GUNS[gun].has("left"), "%s held in both hands" % gun)


func test_forearms_leave_the_bottom_of_the_screen() -> void:
	var data := GameData.load_default()
	for id: String in Melee.MODELS:
		var rest: Array = Melee.pose_at(String(data.weapons[id]["style"]), 0.0)
		var rb := Basis.from_euler(rest[1])
		for side: String in Hands.MELEE[id]:
			var r: Vector3 = Hands.MELEE[id][side][1]
			var base := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
			var dir := rb * Hands.hand_basis(base, Hands.best_roll(base, rb, Hands.ARM_DIR[side].normalized())) * Hands.FOREARM
			check(dir.y < -0.2, "%s %s forearm goes down (%s)" % [id, side, dir])
			check(dir.z > -0.35, "%s %s forearm doesn't point off toward the target (%.2f)" % [id, side, dir.z])
			check(dir.x * (1.0 if side == "right" else -1.0) > -0.1, "%s %s forearm on its own side" % [id, side])


func test_hand_materials_are_mapped() -> void:
	for side: String in Hands.MODELS:
		if not ResourceLoader.exists(Hands.MODELS[side]):
			check(true, "no %s hand model yet: placeholder boxes" % side)
			continue
		var node := (load(Hands.MODELS[side]) as PackedScene).instantiate() as Node3D
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var m := mesh.mesh.surface_get_material(i)
				if m != null:
					check(Hands.LOOKS["materials"].has(m.resource_name) or m.resource_name in Hands.LOOKS["untextured"],
							"%s hand material %s is mapped" % [side, m.resource_name])
		node.free()


func test_hands_in_the_game() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var cam: Camera3D = main.player.camera
	for id: String in Melee.MODELS:
		var w := cam.get_node_or_null("Weapon_" + id)
		check(w != null and w.get_node_or_null("Hand_R") != null, "the %s has a right hand" % id)
	for gun: String in Shooter.MODELS:
		var g := cam.get_node_or_null("Gun_" + gun)
		check(g != null and g.get_node_or_null("Hand_R") != null and g.get_node_or_null("Hand_L") != null, "the %s has both hands" % gun)
	var fists := cam.get_node_or_null("Fists") as Node3D
	check(fists != null and fists.get_node_or_null("R/Hand_R") != null and fists.get_node_or_null("L/Hand_L") != null, "bare fists")
	check(not fists.visible, "fists hidden while you hold the pipe")
	main.sim.gear.unequip("weapon")
	await tree.process_frame
	check(fists.visible, "fists up when bare-handed")
	var rest: Vector3 = (fists.get_node("R") as Node3D).position
	main.melee.hold_at = 0.42
	await tree.process_frame
	check((fists.get_node("R") as Node3D).position.z < rest.z - 0.2, "the right fist jabs forward")
	main.free()
