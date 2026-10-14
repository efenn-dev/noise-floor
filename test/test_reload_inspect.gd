extends "res://test/base_test.gd"
## V13: visible reload and inspect poses are pure, continuous and return exactly to the combat hold. The
## live checks cover cancellation and input; the arm contract is checked only once the other job's GLB lands.

const MAIN := "res://scenes/main.tscn"
const ARM_BONES := ["Forearm", "Hand", "Thumb1", "Thumb2", "Thumb3", "Index1", "Index2", "Index3",
		"Middle1", "Middle2", "Middle3", "Ring1", "Ring2", "Ring3", "Pinky1", "Pinky2", "Pinky3"]
const ARM_POSES := ["Grip", "Open", "Flat", "HoldMag", "Pinch", "Fist"]


func test_reload_and_gun_inspect_start_and_end_at_the_hold() -> void:
	for gun_id: String in Shooter.MODELS:
		var configured: Array = Hands.GUNS[gun_id]["left"]
		var left_position: Vector3 = configured[0]
		var degrees: Vector3 = configured[1]
		var left_rotation := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
		for kind: String in ["reload", "inspect"]:
			var start := Shooter.reload_pose(gun_id, 0.0) if kind == "reload" else Shooter.inspect_pose(gun_id, 0.0)
			var finish := Shooter.reload_pose(gun_id, 1.0) if kind == "reload" else Shooter.inspect_pose(gun_id, 1.0)
			for pose: Dictionary in [start, finish]:
				check((pose["position"] as Vector3).is_zero_approx(), "%s starts/ends at the gun hold" % gun_id)
				check((pose["rotation"] as Vector3).is_zero_approx(), "%s starts/ends at the gun angle" % gun_id)
				check((pose["left_position"] as Vector3).is_equal_approx(left_position), "%s left hand returns exactly" % gun_id)
				check((pose["left_rotation"] as Vector3).is_equal_approx(left_rotation), "%s left wrist returns exactly" % gun_id)
				eq(pose["left_pose"], "Grip", "%s finishes with a grip" % gun_id)


func test_melee_inspect_starts_and_ends_at_each_weapon_rest() -> void:
	for weapon_id: String in Melee.STYLE_BY_WEAPON:
		var rest: Array = Melee.pose_at(String(Melee.STYLE_BY_WEAPON[weapon_id]), 0.0)
		for t: float in [0.0, 1.0]:
			var pose := Melee.inspect_pose(weapon_id, t)
			check((pose["position"] as Vector3).is_equal_approx(rest[0]), "%s inspect position returns to rest" % weapon_id)
			check((pose["rotation"] as Vector3).is_equal_approx(rest[1]), "%s inspect rotation returns to rest" % weapon_id)


## A step of 0.005 is 8 ms of a pistol reload: a fast wrist turn moves 0.1-0.13 rad in that, a snap 0.3 or more.
func test_reload_and_inspect_paths_are_continuous() -> void:
	for gun_id: String in Shooter.MODELS:
		for kind: String in ["reload", "inspect"]:
			var previous := Shooter.reload_pose(gun_id, 0.0) if kind == "reload" else Shooter.inspect_pose(gun_id, 0.0)
			for i in range(1, 201):
				var pose := Shooter.reload_pose(gun_id, i * 0.005) if kind == "reload" else Shooter.inspect_pose(gun_id, i * 0.005)
				var jump := (pose["position"] as Vector3).distance_to(previous["position"] as Vector3)
				jump = maxf(jump, (pose["rotation"] as Vector3).distance_to(previous["rotation"] as Vector3))
				jump = maxf(jump, (pose["left_position"] as Vector3).distance_to(previous["left_position"] as Vector3))
				jump = maxf(jump, (pose["left_rotation"] as Vector3).distance_to(previous["left_rotation"] as Vector3))
				check(jump < 0.15, "%s gun pose continuous at %.3f (jump %.3f)" % [gun_id, i * 0.005, jump])
				previous = pose
	for weapon_id: String in Melee.STYLE_BY_WEAPON:
		var previous := Melee.inspect_pose(weapon_id, 0.0)
		for i in range(1, 201):
			var pose := Melee.inspect_pose(weapon_id, i * 0.005)
			var jump := (pose["position"] as Vector3).distance_to(previous["position"] as Vector3)
			jump = maxf(jump, (pose["rotation"] as Vector3).distance_to(previous["rotation"] as Vector3))
			check(jump < 0.09, "%s melee inspect continuous at %.3f (jump %.3f)" % [weapon_id, i * 0.005, jump])
			previous = pose


func test_pistol_magazine_states_run_in_order() -> void:
	var samples := [0.0, 0.20, 0.34, 0.45, 1.0]
	var expected := ["in_gun", "dropping", "none", "in_hand", "in_gun"]
	for i in samples.size():
		eq(Shooter.reload_pose("pistol", samples[i])["magazine"], expected[i], "pistol magazine step %d" % i)


func test_inspect_is_cancelled_by_attack_reload_and_swap() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	main._give_gun("pistol", false)
	var shooter: Shooter = main.shooter
	check(shooter.start_inspect(), "gun inspection starts")
	check("Pistol" in shooter.last_message and "100%" in shooter.last_message and "8/8 rounds" in shooter.last_message,
			"gun inspection shows name, condition and magazine (%s)" % shooter.last_message)
	shooter.fire()
	check(not shooter.is_inspecting(), "firing cancels inspection")
	check(shooter.start_inspect(), "inspection starts again after the shot")
	main.sim.reload()
	shooter._process(0.0)
	check(not shooter.is_inspecting(), "reload cancels inspection")
	main.sim.guns.reloading = 0.0
	check(shooter.start_inspect(), "inspection starts again after reload")
	main.sim.swap_hands()
	shooter._process(0.0)
	check(not shooter.is_inspecting(), "swapping hands cancels gun inspection")
	var melee: Melee = main.melee
	check(melee.start_inspect(), "melee inspection starts")
	check("Pipe" in melee.last_message and "100%" in melee.last_message,
			"melee inspection shows name and condition (%s)" % melee.last_message)
	melee.swing()
	check(not melee.is_inspecting(), "swinging cancels melee inspection")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_inspect_action_is_v() -> void:
	InputSetup.register()
	check(InputMap.has_action("inspect"), "inspect action exists")
	var on_v := false
	for event: InputEvent in InputMap.action_get_events("inspect"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_V:
			on_v = true
	check(on_v, "inspect is bound to physical V")


func test_set_pose_is_a_noop_on_the_placeholder() -> void:
	var hand := Hands._placeholder("left")
	var before := hand.transform
	var children := hand.get_child_count()
	Hands.set_pose(hand, "Grip")
	check(hand.transform == before and hand.get_child_count() == children, "placeholder ignores rig poses")
	hand.free()


func test_rigged_arm_contract_when_the_asset_exists() -> void:
	var path := "res://assets/models/fp_arm_right.glb"
	if not ResourceLoader.exists(path):
		check(true, "rigged right arm has not landed yet")
		return
	var arm := Hands.make("right")  # also proves the rigged arm wins over the V12 static-hand fallback
	var skeletons := arm.find_children("*", "Skeleton3D", true, false)
	check(not skeletons.is_empty(), "rigged arm has a Skeleton3D")
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for bone: String in ARM_BONES:
			check(skeleton.find_bone(bone) != -1, "rigged arm has %s" % bone)
	var players := arm.find_children("*", "AnimationPlayer", true, false)
	check(not players.is_empty(), "rigged arm has an AnimationPlayer")
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		for pose: String in ARM_POSES:
			check(player.has_animation(pose), "rigged arm has %s pose" % pose)
	arm.free()
