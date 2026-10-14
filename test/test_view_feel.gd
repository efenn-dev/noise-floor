extends "res://test/base_test.gd"
## V3: game feel (ViewFeel, ImpactFx). The rules here are presentation only, but a broken bob or a shake
## that never settles would be felt on every frame, so the maths gets checks.


func test_bob_amplitude() -> void:
	eq(ViewFeel.bob_amplitude(0.0, false, true), 0.0, "no bob standing still")
	eq(ViewFeel.bob_amplitude(4.0, false, false), 0.0, "no bob in the air")
	near(ViewFeel.bob_amplitude(Player.WALK_SPEED, false, true), ViewFeel.BOB_WALK, "walking bob")
	near(ViewFeel.bob_amplitude(Player.SPRINT_SPEED, false, true), ViewFeel.BOB_SPRINT, "sprinting bob")
	check(ViewFeel.bob_amplitude(Player.SPRINT_SPEED, true, true) < ViewFeel.BOB_WALK, "crouching bobs least")


func test_trauma_shakes_then_settles() -> void:
	var f := ViewFeel.new()
	f.add_trauma(0.5)
	f.add_trauma(0.8)
	eq(f.trauma, 1.0, "trauma caps at 1")
	near(ViewFeel.shake_amount(0.5), 0.25, "shake is trauma squared")
	for i: int in 120:
		f.step(1.0 / 60.0)
	eq(f.trauma, 0.0, "settled within two seconds")
	f.free()


func test_shots_and_hits() -> void:
	var f := ViewFeel.new()
	f.fired("hunting_rifle")
	var rifle := f.trauma
	f.trauma = 0.0
	f.fired("pistol")
	check(rifle > f.trauma and f.trauma > 0.0, "a rifle shakes more than a pistol")
	f.hit_zombie(false, false)
	near(f.marker_time, ViewFeel.MARKER_TIME, "hit marker shows")
	eq(f.marker_color, Color.WHITE, "white for a body hit")
	f.hit_zombie(false, true)
	check(f.marker_color.b < 0.5 and f.marker_color.r > 0.9, "yellow for a headshot")
	f.hit_zombie(true, false)
	check(f.marker_color.g < 0.3, "red for a kill")
	for i: int in 30:
		f.step(1.0 / 60.0)
	eq(f.marker_time, 0.0, "marker gone after a third of a second")
	f.free()


func test_hurt_flash_on_damage_only() -> void:
	var f := ViewFeel.new()
	f.note_health(100.0, false)
	eq(f.hurt_flash, 0.0, "first reading sets the baseline")
	f.note_health(80.0, false)
	check(f.hurt_flash > 0.5 and f.trauma > 0.0, "20 damage flashes red and shakes")
	var flash := f.hurt_flash
	f.note_health(100.0, false)
	eq(f.hurt_flash, flash, "healing or respawning doesn't flash")
	f.hurt_flash = 0.0
	check(f.vignette_strength(100.0) == 0.0, "no red edge at full health")
	check(f.vignette_strength(10.0) > 0.3, "the edge pulses red at low health")
	f.free()


func test_sway_returns_and_setting_turns_motion_off() -> void:
	var f := ViewFeel.new()
	f.sway = Vector2(0.05, -0.03)
	f.bob_amp = 0.03
	f.bob_phase = 1.0
	check(f.hold_position_offset().length() > 0.0, "held items move with bob and sway")
	var was := Settings.head_bob
	Settings.head_bob = false
	eq(f.hold_position_offset(), Vector3.ZERO, "off: no bob or sway on held items")
	eq(f.hold_rotation_offset(), Vector3.ZERO, "off: no sway rotation")
	Settings.head_bob = was
	for i: int in 60:
		f.step(1.0 / 60.0)
	check(f.sway.length() < 0.001, "sway catches up within a second")
	f.free()


func test_impact_puffs() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var blood := ImpactFx.spawn(root, Vector3(1, 1, 1), Vector3.FORWARD, "blood")
	var dust := ImpactFx.spawn(root, Vector3(0, 0, 0), Vector3.ZERO, "dust")
	check(blood.emitting and blood.one_shot, "blood puff plays once")
	check(blood.position.distance_to(Vector3(1, 1, 1)) < 0.1, "at the hit point")
	eq(dust.direction, Vector3.UP, "no normal: dust goes up")
	check(blood.gravity.y < dust.gravity.y, "blood falls, dust drifts")
	eq(root.get_child_count(), 2, "both added")
	root.free()
