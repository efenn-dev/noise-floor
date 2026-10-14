extends "res://test/base_test.gd"
## Q2: under a roof (a house or the factory hall) the fog thins to about a fifth of outside's, eased over
## half a second, and thickens again when you step out. Night darkness (the fog's light) is untouched.

const MAIN := "res://scenes/main.tscn"


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func test_fog_thins_under_a_roof_and_comes_back_outside() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	await _frames(3)
	var player: Player = main.player
	var env: Environment = main._env
	var outside: Vector2 = main.fog_targets()
	eq(main.indoor_fog, 0.0, "at the spawn: outside's fog")
	check(outside.x > 0.0, "there is fog (%s)" % outside.x)
	near(env.fog_density, outside.x, "the environment uses it", 1e-6)

	var house: Dictionary = main.town["houses"][1]
	var cell: Vector2i = house["cells"][house["cells"].size() / 2]
	var g := BuildGrid.GRID
	var inside := Vector3((cell.x + 0.5) * g, 0.1, (cell.y + 0.5) * g)
	check(main.town_view.is_under_roof(inside + Vector3.UP * 1.6), "TownView: house 1's cell is under a roof")
	check(not main.town_view.is_under_roof(Vector3(0, 1.6, 0)), "the spawn is not")
	player.global_position = inside
	await _frames(2)
	eq(main.indoor_fog_target(), 1.0, "the camera is under house 1's roof")
	check(main.indoor_fog > 0.0 and main.indoor_fog < 1.0, "easing in, not a jump (%s)" % main.indoor_fog)
	await _frames(40)  # past half a second
	eq(main.indoor_fog, 1.0, "fully thinned after half a second")
	near(env.fog_density, main._fog_density * main.INDOOR_FOG, "fog density about a fifth of outside's", 1e-6)
	near(env.volumetric_fog_density, main._vol_fog_density * main.INDOOR_FOG, "volumetric fog too", 1e-6)
	# V1: the fog's light follows Atmosphere.sky_light (keeps a twilight glow), not daylight().
	near(env.fog_light_energy, lerpf(0.03, 1.0, Atmosphere.sky_light(main.sim.clock.sun_elevation_deg())), "night darkness (the fog's light) as outside", 1e-6)

	var f := TownPlan.factory_rect()
	player.global_position = Vector3(f.get_center().x, 0.1, f.get_center().y)
	await _frames(2)
	eq(main.indoor_fog_target(), 1.0, "the factory hall is under a roof too")

	player.global_position = Vector3(0, 0.1, 0)
	await _frames(40)
	eq(main.indoor_fog, 0.0, "back outside: the fog comes back")
	near(env.fog_density, main._fog_density, "outside's density again", 1e-6)
	near(env.volumetric_fog_density, main._vol_fog_density, "and the volumetric fog", 1e-6)
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
