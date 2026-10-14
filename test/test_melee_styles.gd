extends "res://test/base_test.gd"
## V11: attack animations. Every weapon has a swing style and a model; poses are finite and start and end at
## rest; a trained weapon swings quicker; what you see of a hit waits for the strike moment.

const MAIN := "res://scenes/main.tscn"


func test_every_weapon_has_a_style_and_a_model() -> void:
	var data := GameData.load_default()
	for id: String in data.weapons:
		var s := String(data.weapons[id].get("style", ""))
		check(Melee.STYLES.has(s), "%s has a known swing style (%s)" % [id, s])
		if id != "fists":
			check(Melee.MODELS.has(id), "%s has a model path" % id)
			check(ResourceLoader.exists(Melee.MODELS[id]), "%s's model file exists" % id)


func test_poses_start_and_end_at_rest() -> void:
	for s: String in Melee.STYLES:
		var rest: Array = Melee.pose_at(s, 0.0)
		var end: Array = Melee.pose_at(s, 1.0)
		check((rest[0] as Vector3).is_equal_approx(end[0]) and (rest[1] as Vector3).is_equal_approx(end[1]), "%s ends where it starts" % s)
		var moved := false
		for i in 21:
			var p: Array = Melee.pose_at(s, i / 20.0)
			check((p[0] as Vector3).is_finite() and (p[1] as Vector3).is_finite(), "%s pose finite at %.2f" % [s, i / 20.0])
			if (p[0] as Vector3).distance_to(rest[0]) > 0.1:
				moved = true
		check(moved or s == "punch", "%s actually swings" % s)
		var strike := float(Melee.STYLES[s]["strike"])
		check(strike > 0.2 and strike < 0.8, "%s strikes mid-swing" % s)


func test_weapon_materials_are_all_mapped() -> void:
	for id: String in Melee.MODELS:
		if not ResourceLoader.exists(Melee.MODELS[id]):
			continue
		var node := (load(Melee.MODELS[id]) as PackedScene).instantiate() as Node3D
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var m := mesh.mesh.surface_get_material(i)
				if m != null:
					check(Melee.WEAPON_LOOKS["materials"].has(m.resource_name) or m.resource_name in Melee.WEAPON_LOOKS["untextured"],
							"%s material %s is mapped" % [id, m.resource_name])
		node.free()


func test_swings_quicken_with_skill_and_hits_land_at_the_strike() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var melee: Melee = main.melee
	var piece := sim.gear.make("machete", "civilian", "white")
	sim.gear.pieces.append(piece)
	eq(sim.gear.equip(piece["uid"]), "", "hold the machete")
	eq(melee.style(), "slash", "a machete slashes")
	var t0 := melee.swing_seconds()
	near(t0, float(Melee.STYLES["slash"]["time"]), "untrained: the style's time")
	sim.skills.xp["blades"] = float(sim.data.skills["levels"][5])
	near(melee.swing_seconds(), t0 * 0.8, "Blades 5: the swing animation is 20% quicker too")
	# A zombie right in front of the camera.
	var cam: Camera3D = main.player.camera
	var ahead := cam.global_position - cam.global_basis.z * 1.3
	var z := sim.horde.spawn("shambler", Vector3(ahead.x, 0.0, ahead.z))
	z.hp = 10000.0
	for i in 6:
		await tree.physics_frame
	var feel: ViewFeel = main.view_feel
	feel.marker_time = 0.0
	var id := melee.swing()
	eq(id, z.id, "the swing hits")
	eq(feel.marker_time, 0.0, "nothing shows at the click")
	var strike := melee.swing_seconds() * float(Melee.STYLES["slash"]["strike"])
	var waited := 0.0
	while feel.marker_time == 0.0 and waited < 1.0:
		await tree.process_frame
		waited += main.get_process_delta_time()
	check(feel.marker_time > 0.0, "the hit marker shows")
	check(waited >= strike * 0.5, "at the strike, not the click (%.2f s, strike %.2f s)" % [waited, strike])
	main.free()
