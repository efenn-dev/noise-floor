extends "res://test/base_test.gd"
## W1b: the factory is a hall of grid pieces where the solid block stood: a 15 x 12 floor, brick walls,
## a two-cell open doorway on the road end, the three supply crates inside. With real physics you walk
## in through the doorway (not through a wall), and a zombie on the road follows you in.

const S := BuildGrid.Side

var _scene: Node3D
var sim: SimWorld
var player: Player


func test_factory_pieces_doorway_and_crates() -> void:
	var f := TownPlan.factory()
	eq(f, TownPlan.generate(5)["factory"], "the same hall in every town")
	var floors := 0
	var walls := 0
	var windows := 0
	var odd_style := 0
	for p: Dictionary in f["pieces"]:
		match p["id"]:
			"town_floor": floors += 1
			"town_wall": walls += 1
			"window": windows += 1
		if p["style"] != ("floor" if p["id"] == "town_floor" else "factory"):
			odd_style += 1
	eq(odd_style, 0, "walls drawn in the factory's brick, floors as floor")
	eq(floors, 15 * 12, "a 15 x 12-cell floor")
	eq(walls + windows, 2 * (15 + 12) - 4, "walls and windows all round, less the two-cell doorways (M17a: north and south)")
	eq(f["north_doorway"].size(), 2, "M17a: the north doorway onto the park road is two edges")
	eq(windows, f["windows"], "with a few windows")
	var r := TownPlan.factory_rect()
	check(r.has_point(Vector2(0, -125)), "where the old factory block stood")
	eq(f["doorway"].size(), 2, "the doorway is two edges")
	var sim := SimWorld.new(12.0)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	eq(sim.place_factory(plan), f["pieces"].size(), "every piece laid")
	for key: String in f["doorway"]:
		check(not sim.build.pieces.has(key), "doorway edge %s is empty (no door)" % key)
		var e: PackedStringArray = key.split(":")
		var mid_x := (int(e[1]) + 0.5) * BuildGrid.GRID
		check(absf(mid_x) < 4.0, "on the road (x %.0f)" % mid_x)
		eq(int(e[2]) * BuildGrid.GRID, r.end.y, "in the south wall, at the road end")
	for cell: Vector2i in f["crates"]:
		check(cell in f["cells"], "crate at %s is inside the hall" % cell)
	for c: Vector2i in f["cells"]:
		if TownPlan.house_at(plan, c) != -1:
			check(false, "the hall overlaps a house at %s" % c)
	var house_cells := 0
	for h: Dictionary in plan["houses"]:
		house_cells += h["cells"].size()
	check(house_cells > 0, "and no house overlaps it")
	# Sound: a smelter-loud noise inside is muffled to the street by the walls, but the doorway lets it out.
	var inside := Vector3(0, 0, -128)
	eq(sim.noise.walls_between(inside, Vector3(0, 0, -100)), 0, "straight out through the doorway: no wall")
	eq(sim.noise.walls_between(inside, Vector3(10, 0, -100)), 1, "off to the side: one wall")


func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(80, 2, 80)
	shape.shape = slab
	shape.position = Vector3(0, -1.0, -120)
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	sim.place_factory(TownPlan.generate(1))
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func test_walk_in_through_the_doorway() -> void:
	_setup()
	player.position = Vector3(0, 0, -108)  # on the road, 6 m from the doorway
	player.set_look(0, 0)  # facing north, into the hall
	player.wish_move = Vector2(0, 1)
	await _run(4.0)
	var z := player.global_position.z
	check(z < -116.0, "walked in through the doorway (z %.1f)" % z)
	player.position = Vector3(9, 0, -108)  # in front of the wall, off the doorway
	await _run(3.0)
	check(player.global_position.z > -114.0, "the wall beside it stops you (z %.1f)" % player.global_position.z)
	player.wish_move = Vector2.ZERO
	await _teardown()


func test_a_zombie_follows_you_in() -> void:
	_setup()
	var nav := NavBaker.new()
	_scene.add_child(nav)
	nav.setup(_scene, AABB(Vector3(-22, -1, -142), Vector3(44, 6, 44)))
	nav.bake_now()
	await nav.wait_synced()  # W3a: the map syncs on a worker thread
	player.position = Vector3(-6, 0.1, -128)  # deep inside, off to the side of the doorway
	var z := sim.horde.spawn("shambler", Vector3(8, 0, -106))  # out on the road, past the corner
	z.take_hit(0, player.position, 0)  # it knows where you are
	var zview := ZombieView.new()
	_scene.add_child(zview)
	zview.setup(sim, player)
	await _run(22.0)
	var d := Vector2(z.pos.x - player.position.x, z.pos.z - player.position.z).length()
	check(d < 2.5, "it came in through the doorway (%.1f m away, %s at %s)" % [d, z.state_name(), z.pos])
	check(z.pos.z < -114.0, "it's inside the hall")
	eq(z.break_key, "", "without breaking a wall")
	await _teardown()
