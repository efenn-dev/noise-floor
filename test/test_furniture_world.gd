extends "res://test/base_test.gd"
## W1c with real physics: furniture is solid (you walk into a counter and stop), the navmesh goes round it,
## and a zombie on the street still reaches you in a furnished kitchen through the open front door.
## Plus the whole game: a new game is furnished once, and a pre-W1c save gets furnished when it loads.

const MAIN := "res://scenes/main.tscn"

var _scene: Node3D
var sim: SimWorld
var player: Player
var plan: Dictionary
var house: Dictionary
var counter: Dictionary


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
	sim.place_props(plan)
	house = plan["houses"][1]  # house_0_e: east of the road, front door facing west
	for p: Dictionary in plan["props"]:
		if p["house"] == house["name"] and p["id"] == "counter":
			counter = p
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


## The counter's middle on the floor, and the way it faces (into the kitchen).
func _counter_mid() -> Vector3:
	var c := sim.build.center_for("counter", counter["cell"], counter["side"])
	return Vector3(c.x, 0.1, c.z)


func _facing() -> Vector3:
	return [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][counter["side"]]


func test_you_bump_into_the_counter() -> void:
	_setup()
	check(not counter.is_empty(), "house_0_e has a kitchen counter")
	var f := _facing()
	player.position = _counter_mid() + f * 1.4
	player.set_look(rad_to_deg(atan2(f.x, f.z)), 0)  # looking at the counter
	player.wish_move = Vector2(0, 1)
	await _run(2.5)
	var gap := (player.global_position - _counter_mid()).dot(f)
	var half: float = sim.data.buildables["counter"]["size"].z / 2.0
	check(gap > half + 0.2, "you stop in front of the counter, not inside it (%.2f m from its middle)" % gap)
	check(gap < 1.0, "after walking up to it (%.2f m)" % gap)
	player.wish_move = Vector2.ZERO
	await _teardown()


func test_zombie_reaches_you_in_a_furnished_kitchen() -> void:
	_setup()
	sim.toggle_door(BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"]))
	var door := Vector3((house["door_cell"].x + 0.5) * 2.0, 0, (house["door_cell"].y + 0.5) * 2.0)
	var nav := NavBaker.new()
	_scene.add_child(nav)
	nav.setup(_scene, AABB(Vector3(-4, -1, door.z - 14), Vector3(26, 6, 28)))
	nav.bake_now()
	await nav.wait_synced()  # W3a: the map syncs on a worker thread
	player.position = _counter_mid() + _facing() * 1.0  # at the sink
	var z := sim.horde.spawn("shambler", Vector3(3.0, 0, door.z - 6.0))  # up the street a way
	z.take_hit(0, player.position, 0)  # it knows where you are
	var zview := ZombieView.new()
	_scene.add_child(zview)
	zview.setup(sim, player)
	await _run(30.0)
	var d := Vector2(z.pos.x - player.position.x, z.pos.z - player.position.z).length()
	check(d < 2.5, "it found its way round the furniture to you (%.1f m away, %s %s at %s)" % [d, z.state_name(), z.break_key, z.pos])
	check(sim.player.health < 100.0, "and bit you (health %d)" % sim.player.health)
	await _teardown()


## A version-6 save (written by the M13 game, before furniture) loads in the real game with the houses
## furnished, and saving and loading again doesn't furnish them twice.
func test_old_save_gets_furnished_once() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	GameSession.save_path = "user://test_furniture_save.json"
	GameSession.pending_load = "res://test/fixtures/save_v6.json"
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	check(main._loaded, "the version-6 save loaded")
	var s: SimWorld = main.sim
	var props := 0
	for k: String in s.build.pieces:
		props += 1 if s.build.kind_of(s.build.pieces[k]["id"]) == "prop" else 0
	var expected: int = main.town["props"].size() + main.town["factory"]["props"].size()
	eq(props, expected, "every house and the hall furnished")
	eq(main.town_pieces, expected, "the furniture was all the town laid")
	var count := s.build.pieces.size()
	eq(main.save_game(), "", "save")
	main.queue_free()
	await tree.process_frame
	GameSession.pending_load = GameSession.save_path
	var again: Node3D = load(MAIN).instantiate()
	tree.root.add_child(again)
	for i in 3:
		await tree.process_frame
	eq(again.town_pieces, 0, "loaded again, nothing laid a second time")
	eq(again.sim.build.pieces.size(), count, "the same pieces came back")
	again.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(GameSession.save_path)
	GameSession.save_path = GameSession.SAVE_PATH
	GameSession.skip_menu = false
	GameSession.skip_hints = false
