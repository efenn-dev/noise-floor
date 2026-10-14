extends "res://test/base_test.gd"
## V7: hits and deaths read. Blood stains (Decals) under hits and spreading under bodies, capped and
## fading; a dying zombie turns to fall away from the blow and slides back; headshots have their own
## burst and sound.

const MAIN := "res://scenes/main.tscn"


func test_stain_faces_out_of_the_surface() -> void:
	var up := ImpactFx.basis_facing(Vector3.UP)
	check(up.y.dot(Vector3.UP) > 0.99, "a floor stain projects down onto the floor")
	var wall := ImpactFx.basis_facing(Vector3.RIGHT)
	check(wall.y.dot(Vector3.RIGHT) > 0.99, "a wall stain projects into the wall")
	check(absf(wall.determinant() - 1.0) < 0.01, "a proper rotation, not a mirror")
	var odd := ImpactFx.basis_facing(Vector3.ZERO)
	check(odd.y.dot(Vector3.UP) > 0.99, "no normal: falls back to the floor")


func test_stains_are_capped() -> void:
	ImpactFx.clear_cache()
	var root := Node3D.new()
	tree.root.add_child(root)
	for i in ImpactFx.MAX_STAINS + 12:
		ImpactFx.stain(root, Vector3(i, 0, 0), Vector3.UP, 0.5)
	await tree.process_frame
	check(ImpactFx.stain_count() <= ImpactFx.MAX_STAINS, "never more than %d stains (%d)" % [ImpactFx.MAX_STAINS, ImpactFx.stain_count()])
	var d := ImpactFx.stain(root, Vector3.ZERO, Vector3.UP, 1.5, 60.0, 4.0)
	check(d.size.x < 1.0, "a pool starts small and spreads")
	root.free()
	ImpactFx.clear_cache()


func test_headshot_burst_and_sound() -> void:
	check(ImpactFx.KINDS["blood_head"]["amount"] > ImpactFx.KINDS["blood"]["amount"], "a headshot sprays more")
	check(SoundView.stream("headshot") != null, "headshot.wav loads")


func test_a_dying_zombie_falls_away_and_bleeds() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var at: Vector3 = main.player.global_position + Vector3(0, 0, -5)
	var z := sim.horde.spawn("shambler", at)
	for i in 5:
		await tree.physics_frame
	var body: ZombieBody = null
	for b: ZombieBody in main.zombie_view.find_children("*", "ZombieBody", true, false):
		if b.brain == z:
			body = b
	check(body != null, "the zombie has a body")
	if body == null:
		main.free()
		return
	var start := body.global_position
	# Hit from the east: it should fall west.
	check(z.take_hit(1000.0, start + Vector3(3, 0, 0), 4.0), "killed")
	for i in 45:
		await tree.physics_frame
	check(body.death_dir.dot(Vector3.LEFT) > 0.9, "knocked west, away from the blow (%s)" % body.death_dir)
	check((-body.global_basis.z).dot(Vector3.LEFT) > 0.7, "turned to fall that way")
	check((body.global_position - start).dot(Vector3.LEFT) > 0.15, "slid back a little (%.2f m)" % (body.global_position - start).dot(Vector3.LEFT))
	var pool := false
	for d: Node in main.find_children("BloodStain*", "Decal", true, false):
		if (d as Decal).global_position.distance_to(body.global_position) < 2.0:
			pool = true
	check(pool, "a pool of blood under the body")
	main.free()
	ImpactFx.clear_cache()
