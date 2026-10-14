extends "res://test/base_test.gd"
## V24 (Emmitt: "if you jump in a house you can see through the roof and you can see zombie arms sticking
## through walls"): house and factory ceilings stop your head (a slab only the walker bumps into), and a zombie
## carries a ball at arm height in front of its chest so its reaching hands stop short of walls.

const MAIN := "res://scenes/main.tscn"


func test_jumping_in_a_house_stops_at_the_ceiling() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var town: TownView = main.town_view
	check(town.ceiling_bodies >= town.roofs, "every roof slab has a ceiling collider (%d for %d)" % [town.ceiling_bodies, town.roofs])
	var cell: Vector2i = town._roofed.keys()[0]
	var player: Player = main.player
	var g := BuildGrid.GRID
	player.global_position = Vector3((cell.x + 0.5) * g, 0.2, (cell.y + 0.5) * g)
	player.velocity = Vector3(0, 9.0, 0)  # a far bigger jump than the real one, as if off the furniture
	var top := 0.0
	for i in 60:
		await tree.physics_frame
		top = maxf(top, player.global_position.y + Player.STAND_HEIGHT)
		if i == 0:
			player.velocity.y = 9.0
	check(top <= TownView.WALL_TOP + 0.02, "your head stops at the ceiling (%.2f m, ceiling %.2f)" % [top, TownView.WALL_TOP])
	check(player.camera.global_position.y < TownView.WALL_TOP - 0.1, "and the camera stays under it")
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func test_ceilings_are_only_for_the_walker() -> void:
	check(Player.MASK & Layers.CEILING != 0, "the walker bumps into ceilings")
	var zombie := ZombieBody.new()
	check(zombie.collision_mask & Layers.CEILING == 0, "zombies don't need to")
	zombie.free()


func test_a_zombie_keeps_its_arms_out_of_walls() -> void:
	var body := ZombieBody.new()
	var reach := body._reach_shape
	check(reach != null and not reach.disabled, "a live zombie has its arm-reach ball")
	var ahead := -reach.position.z + (reach.shape as SphereShape3D).radius
	check(ahead >= 0.5, "it reaches %.2f m in front of the body, where the hands are" % ahead)
	check(reach.position.y > 1.0 and reach.position.y < 1.5, "at arm height")
	body.free()
