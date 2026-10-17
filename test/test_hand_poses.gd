extends "res://test/base_test.gd"
## V22: the finger poses are built in the engine from the arm rig's rest pose (Hands.build_pose_library), each
## joint bent about its finger's measured curl axis, so the bends you ask for are the bends you get. Also the
## sleeve that carries the arm on to the shoulder, and a free hand's forearm turning toward its shoulder.

const ARM := "res://assets/models/fp_arm_right.glb"


## The arm in the scene tree: a Skeleton3D only recomputes its global bone poses there (and asking for one
## before that freezes the cache), so tests pose it in the tree and wait a frame before measuring.
func _skeleton() -> Skeleton3D:
	var root := (load(ARM) as PackedScene).instantiate() as Node3D
	tree.root.add_child(root)
	return root.get_node(Hands.SKELETON_PATH) as Skeleton3D


## Puts `anim`'s one key on `sk` and returns each finger bone's bend (degrees from its parent).
func _bends_after(sk: Skeleton3D, anim: Animation) -> Dictionary:
	for t in anim.get_track_count():
		var bone := sk.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
		sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(t, 0.0))
	await tree.process_frame  # the first update after entering the tree lands a frame late
	await tree.process_frame
	var out := {}
	for finger: String in Hands.FINGERS:
		var bones: Array = Hands.FINGERS[finger]
		var prev := sk.get_bone_global_pose(sk.get_bone_parent(sk.find_bone(bones[0]))).basis.y.normalized()
		var bends: Array[float] = []
		for b: String in bones:
			var dir := sk.get_bone_global_pose(sk.find_bone(b)).basis.y.normalized()
			bends.append(rad_to_deg(prev.angle_to(dir)))
			prev = dir
		out[finger] = bends
	return out


func test_every_pose_is_built_with_every_finger_bone() -> void:
	if not ResourceLoader.exists(ARM):
		return
	var sk := _skeleton()
	var lib := Hands.build_pose_library(sk)
	for pose: String in ["Grip", "Open", "Flat", "HoldMag", "Pinch", "Fist"]:
		check(lib.has_animation(pose), "%s is built" % pose)
		eq(lib.get_animation(pose).get_track_count(), 15, "%s keys all fifteen finger bones" % pose)
	sk.get_parent().get_parent().queue_free()


func test_the_bends_you_ask_for_are_the_bends_you_get() -> void:
	if not ResourceLoader.exists(ARM):
		return
	var sk := _skeleton()
	var lib := Hands.build_pose_library(sk)
	var rest := {}
	for finger: String in Hands.FINGERS:
		rest[finger] = Hands.finger_rest(sk, Hands.FINGERS[finger])["bends"]
	await _bends_after(sk, lib.get_animation("Grip"))  # warm-up: right after the rest reads above, the first pose set lands one pose late
	for pose: String in ["Fist", "Flat", "Open", "Pinch", "HoldMag"]:
		var got: Dictionary = await _bends_after(sk, lib.get_animation(pose))
		var spec: Dictionary = Hands.POSE_BENDS[pose]
		for finger: String in Hands.FINGERS:
			var want: Array = spec.get(finger, spec.get("*", []) if finger != "Thumb" else [])
			for j in 3:
				var expected: float = float(want[j]) if not want.is_empty() else float(rest[finger][j])
				near(float(got[finger][j]), expected, "%s %s joint %d bent %.0f deg" % [pose, finger, j + 1, expected], 6.0)
	# the grip is the rest pose, untouched
	var grip: Dictionary = await _bends_after(sk, lib.get_animation("Grip"))
	near(float(grip["Index"][0]), float(rest["Index"][0]), "Grip leaves the index knuckle as modelled", 0.5)
	sk.get_parent().get_parent().queue_free()


func test_a_fist_is_closed_and_flat_is_straight() -> void:
	if not ResourceLoader.exists(ARM):
		return
	var sk := _skeleton()
	var lib := Hands.build_pose_library(sk)
	var fist: Dictionary = await _bends_after(sk, lib.get_animation("Fist"))
	for finger: String in ["Index", "Middle", "Ring", "Pinky"]:
		var total: float = float(fist[finger][0]) + float(fist[finger][1]) + float(fist[finger][2])
		check(total > 220.0, "Fist: the %s curls into the palm (%.0f deg in all)" % [finger, total])
	var flat: Dictionary = await _bends_after(sk, lib.get_animation("Flat"))
	for finger: String in ["Index", "Middle", "Ring", "Pinky"]:
		check(float(flat[finger][1]) < 10.0 and float(flat[finger][2]) < 10.0, "Flat: the %s is straight" % finger)
	sk.get_parent().get_parent().queue_free()


## V37: the bought arms' own jacket sleeve runs from the glove on past the elbow toward the shoulder, so no
## extension tube is added (the old arms' V31 tube stays for models with an "Arm Sleeve").
func test_the_sleeve_carries_on_to_the_shoulder() -> void:
	if not ResourceLoader.exists(ARM):
		return
	var arm := Hands.make("right")
	check(arm.find_child("SleeveExtension", true, false) == null, "the arm brings its own sleeve: no tube added")
	var sk := arm.get_node(Hands.SKELETON_PATH) as Skeleton3D
	var wrist := sk.get_bone_global_rest(sk.find_bone("Hand")).origin
	var back := (sk.get_bone_global_rest(sk.find_bone("Forearm")).origin - wrist).normalized()
	var reach := 0.0
	var looks := {}
	for mi: MeshInstance3D in arm.find_children("*", "MeshInstance3D", true, false):
		for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var source := mi.mesh.surface_get_material(i)
			if source == null:
				continue
			var shown := mi.get_surface_override_material(i)
			looks[source.resource_name] = shown if shown != null else source
			if source.resource_name == "FP Sleeve":
				for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					reach = maxf(reach, (mi.transform * v - wrist).dot(back))
	check(reach > 0.6, "the sleeve runs %.2f m back from the wrist, past the elbow" % reach)
	for name: String in ["FP Glove", "FP Sleeve"]:
		check(looks.has(name), "the arm has its %s" % name)
		var mat := looks.get(name) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null, "%s keeps the pack's own texture" % name)
		check(mat != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "%s is drawn from both sides" % name)
	var player := arm.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(player.has_animation("Fist") and player.get_animation("Fist").get_track_count() == 15,
			"the arm plays the engine-built poses")
	arm.free()


func test_a_free_hand_turns_its_forearm_to_the_shoulder() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.2, -0.2, -0.42)
	Hands.attach(holder, "pistol", Hands.GUNS)
	var left := holder.get_node("Hand_L") as Node3D
	Hands.reaim(holder, Basis())
	var on_grip := left.basis
	Hands.set_target(left, Vector3(-0.05, 0.02, -0.03), Vector3(deg_to_rad(72), deg_to_rad(-10), deg_to_rad(-18)))
	Hands.reaim(holder, Basis())
	var hand_cam := holder.position + left.position
	var want := (Vector3(Hands.SHOULDER["left"]) - hand_cam).normalized()
	var forearm := (left.basis * Hands.FOREARM).normalized()
	check(forearm.dot(want) > 0.99, "off the grip, the left forearm runs back to the left shoulder (dot %.3f)" % forearm.dot(want))
	Hands.clear_target(left)
	Hands.reaim(holder, Basis())
	check(left.basis.is_equal_approx(on_grip), "back on the grip it holds exactly as before")
	holder.free()


## V39 (Emmitt: "the left hand should be palm up and the arm is floating"): under a long gun's fore-end the left
## hand cradles it palm-up with the forearm running back and down to the left; it keeps that sliding along the
## barrel (the shotgun's pump) and lets go of it when it leaves the barrel's line (a reload).
func test_long_guns_rest_in_a_palm_up_cradle() -> void:
	for gun: String in ["hunting_rifle", "shotgun", "crossbow"]:
		var holder := Node3D.new()
		holder.position = Vector3(0.2, -0.25, -0.5)
		Hands.attach(holder, gun, Hands.GUNS)
		var left := holder.get_node("Hand_L") as Node3D
		var grip: Vector3 = left.get_meta("grip_position")
		Hands.set_target(left, grip, Vector3.ZERO)
		Hands.reaim(holder, Basis())
		var cradle: Dictionary = Hands.CRADLES[gun]
		check((left.basis * Vector3.RIGHT).normalized().dot(Vector3.UP) > 0.85, "%s: the left palm faces up" % gun)
		var palm := (cradle["palm"] as Vector3).normalized()
		var fore := ((cradle["forearm"] as Vector3) - palm * (cradle["forearm"] as Vector3).dot(palm)).normalized()
		var forearm := (left.basis * Hands.FOREARM).normalized()
		check(forearm.dot(fore) > 0.99 and forearm.z > 0.3 and forearm.x < -0.3,
				"%s: the forearm runs back and off to the left, toward the left shoulder" % gun)
		var cradled := left.basis
		Hands.set_target(left, grip + Vector3(0, 0, 0.1), Vector3.ZERO)
		Hands.reaim(holder, Basis())
		check(left.basis.is_equal_approx(cradled), "%s: sliding along the barrel keeps the cradle" % gun)
		Hands.set_target(left, grip + Vector3(0, -0.12, 0.05), Vector3(1.2, 0, 0))
		Hands.reaim(holder, Basis())
		check(not left.basis.is_equal_approx(cradled), "%s: off the barrel's line it lets go of the cradle" % gun)
		holder.free()
	var pistol := Node3D.new()
	Hands.attach(pistol, "pistol", Hands.GUNS)
	check(not (pistol.get_node("Hand_L") as Node3D).has_meta("cradle"), "a pistol's left hand still wraps the grip")
	pistol.free()
