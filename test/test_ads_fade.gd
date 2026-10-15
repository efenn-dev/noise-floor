extends "res://test/base_test.gd"
## Q6: on iron sights only the gun's own close-up surfaces fade out (not the camera's near plane), so the
## stock leaves the view while the hands on the gun stay whole.


func test_only_the_guns_own_surfaces_fade() -> void:
	for base: String in Shooter.ADS_NEAR:
		if not ResourceLoader.exists(Shooter.MODELS[base]):
			continue
		var gun := (load(Shooter.MODELS[base]) as PackedScene).instantiate() as Node3D
		Hands.attach(gun, base, Hands.GUNS)
		Shooter.apply_textured_materials(gun)
		var mats := Shooter._fading_gun_materials(gun)
		check(not mats.is_empty(), "%s: its surfaces get fading copies" % base)
		for mat: BaseMaterial3D in mats:
			eq(mat.distance_fade_mode, BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER, "%s: per-pixel fade" % base)
			check(mat.distance_fade_max_distance < 0.002, "%s: fully visible until you aim (%.4f m)" % [base, mat.distance_fade_max_distance])
		var hand_faded := false
		for hand_name: String in ["Hand_R", "Hand_L"]:
			var hand := gun.get_node_or_null(hand_name)
			if hand == null:
				continue
			for mi: MeshInstance3D in hand.find_children("*", "MeshInstance3D", true, false):
				for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
					var m := mi.get_active_material(i) as BaseMaterial3D
					if m != null and m.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
						hand_faded = true
		check(not hand_faded, "%s: the hands never fade" % base)
		gun.free()


func test_the_fade_distances_stay_behind_the_hands() -> void:
	for base: String in Shooter.ADS_NEAR:
		var pose: Array = Shooter.ADS_POSES[base]
		var grip: Vector3 = Hands.GUNS.get(base, {}).get("right", [Vector3.ZERO])[0] if Hands.GUNS.has(base) else Vector3.ZERO
		var hand_distance: float = -(pose[0] as Vector3).z - grip.z
		if Hands.GUNS.has(base):
			check(hand_distance > float(Shooter.ADS_NEAR[base]),
					"%s: the right hand (%.2f m out) is beyond the fade (%.2f m)" % [base, hand_distance, Shooter.ADS_NEAR[base]])
