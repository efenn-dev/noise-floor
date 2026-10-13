extends "res://test/base_test.gd"
## W1a with real physics: you walk in through an open front door and stop at the wall behind it; a
## zombie on the street follows you in through the open door; with the door shut it breaks the door.
## Plus the whole game: houses are laid once, containers are inside, and a save brings them back.

const MAIN := "res://scenes/main.tscn"

var _scene: Node3D
var sim: SimWorld
var player: Player
var plan: Dictionary
var house: Dictionary


func _setup() -> void:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(120, 2, 120)
	shape.shape = slab
	shape.position.y = -1.0
	ground.add_child(shape)
	_scene.add_child(ground)
	sim = SimWorld.new(12.0)
	plan = TownPlan.generate(1)
	sim.place_town(plan)
	house = plan["houses"][1]  # house_0_e: east of the road, front door facing west
	var view := BuildView.new()
	_scene.add_child(view)
	view.setup(sim.build)
	player = Player.new()
	player.use_device_input = false
	_scene.add_child(player)


func _bake() -> void:
	var nav := NavBaker.new()
	_scene.add_child(nav)
	var z := _door_mid().z
	nav.setup(_scene, AABB(Vector3(-4, -1, z - 14), Vector3(26, 6, 28)))
	nav.bake_now()


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await tree.physics_frame
		sim.player_pos = player.global_position
		if i % 3 == 2:
			sim.step()


func _door_key() -> String:
	return BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"])


## The middle of the front door's cell, on the floor.
func _door_mid() -> Vector3:
	var c: Vector2i = house["door_cell"]
	return Vector3((c.x + 0.5) * BuildGrid.GRID, 0.1, (c.y + 0.5) * BuildGrid.GRID)


func test_walk_in_through_the_front_door() -> void:
	_setup()
	eq(house["door_side"], BuildGrid.Side.WEST, "house_0_e's door faces west, to the road")
	sim.toggle_door(_door_key())
	var mid := _door_mid()
	player.position = mid + Vector3(-4, 0, 0)  # on the lawn, 3 m outside the door
	player.set_look(-90, 0)  # facing east, into the house
	player.wish_move = Vector2(0, 1)
	await _run(4.0)
	var x := player.global_position.x
	check(x > 8.6, "walked in through the open door (x %.2f)" % x)
	check(x < 11.8, "and stopped at the wall behind the front room (x %.2f)" % x)
	near(player.global_position.z, mid.z, "straight in", 0.3)
	player.wish_move = Vector2.ZERO
	await _teardown()


func test_closed_door_stops_you() -> void:
	_setup()
	var mid := _door_mid()
	player.position = mid + Vector3(-4, 0, 0)
	player.set_look(-90, 0)
	player.wish_move = Vector2(0, 1)
	await _run(3.0)
	check(player.global_position.x < 8.0, "a closed door keeps you out (x %.2f)" % player.global_position.x)
	player.wish_move = Vector2.ZERO
	await _teardown()


func test_zombie_follows_you_in_through_the_open_door() -> void:
	_setup()
	sim.toggle_door(_door_key())
	_bake()
	var mid := _door_mid()
	player.position = mid + Vector3(1.6, 0, 0)  # in the front room, at the far side
	var z := sim.horde.spawn("shambler", Vector3(3.0, 0, mid.z - 7.0))  # up the street a way
	z.take_hit(0, player.position, 0)  # it knows where you are
	var zview := ZombieView.new()
	_scene.add_child(zview)
	zview.setup(sim, player)
	await _run(16.0)
	var d := Vector2(z.pos.x - player.position.x, z.pos.z - player.position.z).length()
	check(d < 2.5, "it came in through the door (%.1f m away, %s %s at %s)" % [d, z.state_name(), z.break_key, z.pos])
	check(sim.player.health < 100.0, "and bit you (health %d)" % sim.player.health)
	await _teardown()


func test_zombie_breaks_a_closed_front_door() -> void:
	_setup()
	_bake()
	var mid := _door_mid()
	player.position = mid + Vector3(1.6, 0, 0)
	var z := sim.horde.spawn("shambler", mid + Vector3(-3.0, -0.1, 0))  # on the lawn, by the door
	z.take_hit(0, player.position, 0)
	var zview := ZombieView.new()
	_scene.add_child(zview)
	zview.setup(sim, player)
	await _run(5.0)
	eq(z.state_name(), "break", "the door is shut: it breaks it")
	eq(z.break_key, _door_key(), "the front door")
	check(sim.build.pieces[_door_key()]["hp"] < sim.data.buildables["door"]["hp"], "the door takes damage")
	await _teardown()


func test_game_lays_the_town_once() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	GameSession.save_path = "user://test_town_save.json"
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var s: SimWorld = main.sim
	check(main.town_pieces > 400, "the town plan laid its houses (%d pieces)" % main.town_pieces)
	print("      town: %d house pieces laid, first navmesh bake %.0f ms" % [main.town_pieces, main.first_bake_ms])
	var inside := 0
	var houses := 0
	for id: String in s.loot.containers:
		if id.begins_with("house_"):
			houses += 1
			if TownPlan.house_at(main.town, BuildGrid.world_to_cell(s.loot.containers[id]["pos"])) != -1:
				inside += 1
	eq(houses, 36, "36 house containers")
	eq(inside, houses, "all of them indoors")
	eq(main.town_view.roofs > 30, true, "roofs drawn (%d slabs)" % main.town_view.roofs)
	var door := BuildGrid.key_for_wall_edge(main.town["houses"][0]["door_cell"], main.town["houses"][0]["door_side"])
	s.toggle_door(door)
	var some_wall := ""
	for k: String in s.build.pieces:
		if s.build.pieces[k]["id"] == "town_wall":
			some_wall = k
			break
	s.build.damage(some_wall, 123)
	var count := s.build.pieces.size()
	check(s.build.pieces.has("f:0:-60"), "the factory hall is laid (W1b)")
	var in_houses := 0
	for z: ZombieBrain in s.horde.zombies.values():
		if TownPlan.house_at(main.town, BuildGrid.world_to_cell(z.pos)) != -1:
			in_houses += 1
	eq(in_houses, main.town["zombies"].size(), "a zombie in each picked house (W1b)")
	var zombies := s.horde.zombies.size()
	eq(main.save_game(), "", "save")
	main.queue_free()
	await tree.process_frame
	GameSession.pending_load = GameSession.save_path
	var again: Node3D = load(MAIN).instantiate()
	tree.root.add_child(again)
	for i in 3:
		await tree.process_frame
	check(again._loaded, "the save loaded")
	eq(again.town_pieces, 0, "the plan didn't lay the houses a second time")
	eq(again.sim.build.pieces.size(), count, "the same pieces came back")
	eq(again.sim.horde.zombies.size(), zombies, "the same zombies came back, house ones not doubled")
	check(again.sim.build.pieces[door]["open"], "the front door is still open")
	eq(again.sim.build.pieces[some_wall]["hp"], 600 - 123, "the wall is still damaged")
	again.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(GameSession.save_path)
	GameSession.save_path = GameSession.SAVE_PATH
	GameSession.skip_menu = false
	GameSession.skip_hints = false
