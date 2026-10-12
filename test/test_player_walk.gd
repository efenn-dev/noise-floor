extends "res://test/base_test.gd"
## Scripted run with real physics: a Player on a floor walks north and hits a wall.

var _scene: Node3D


func _setup() -> Player:
	_scene = Node3D.new()
	tree.root.add_child(_scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	_scene.add_child(floor_body)
	var player := Player.new()
	player.use_device_input = false
	_scene.add_child(player)
	return player


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_scene.add_child(body)


func _run(frames: int) -> void:
	for i in frames:
		await tree.physics_frame


func _teardown() -> void:
	_scene.queue_free()
	await tree.process_frame


func test_walks_forward_on_open_ground() -> void:
	var p := _setup()
	await _run(10)
	check(p.is_on_floor(), "lands on the floor")
	p.wish_move = Vector2(0, 1)
	await _run(60)
	check(p.position.z < -3.0, "1 s of walking north moves > 3 m (z = %.2f)" % p.position.z)
	check(absf(p.position.x) < 0.01, "walks straight (x = %.3f)" % p.position.x)
	near(p.position.y, 0.0, "stays on the ground", 0.05)
	await _teardown()


func test_sprint_is_faster_and_crouch_slower() -> void:
	var p := _setup()
	await _run(10)
	p.wish_move = Vector2(0, 1)
	p.wish_sprint = true
	await _run(60)
	var sprint_dist := -p.position.z
	p.wish_sprint = false
	p.wish_crouch = true
	await _run(30)  # settle to crouch speed
	var before := p.position.z
	await _run(60)
	var crouch_dist := before - p.position.z
	check(sprint_dist > 5.0, "sprint covers > 5 m in 1 s (%.2f)" % sprint_dist)
	check(crouch_dist < 2.5, "crouch covers < 2.5 m in 1 s (%.2f)" % crouch_dist)
	check(p.crouching, "is crouching")
	await _teardown()


func test_wall_blocks_the_player() -> void:
	var p := _setup()
	_add_wall(Vector3(0, 2, -3), Vector3(6, 4, 0.5))  # near face at z = -2.75
	await _run(10)
	p.wish_move = Vector2(0, 1)
	p.wish_sprint = true
	await _run(180)
	check(p.position.z > -2.75 + Player.RADIUS - 0.05, "stopped at the wall (z = %.2f)" % p.position.z)
	check(p.position.z < -1.5, "but did reach it (z = %.2f)" % p.position.z)
	await _teardown()


func test_jump_leaves_ground_and_lands() -> void:
	var p := _setup()
	await _run(10)
	p.wish_jump = true
	await _run(10)
	p.wish_jump = false
	check(p.position.y > 0.3, "in the air after jumping (y = %.2f)" % p.position.y)
	await _run(90)
	check(p.is_on_floor(), "lands again")
	await _teardown()


func test_cannot_stand_up_under_a_low_ceiling() -> void:
	var p := _setup()
	await _run(10)
	p.wish_crouch = true
	await _run(5)
	_add_wall(Vector3(0, 1.5, 0), Vector3(4, 0.4, 4))  # slab from 1.3 m to 1.7 m, above a crouched head
	p.wish_crouch = false
	await _run(10)
	check(p.crouching, "stays crouched with no headroom")
	await _teardown()
