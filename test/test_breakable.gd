extends "res://test/base_test.gd"
## W2 (Emmitt: "lets work on making things destructible like windows"). Glass goes in one hit from anything
## and is loud; town doors are wood (axes best, blades worst); brick, floors and your own builds don't break
## from your hits; a broken window gets jagged glass and a burst of shards.

const N := BuildGrid.Side.NORTH


func _town_piece(sim: SimWorld, id: String, cell: Vector2i) -> String:
	var key := sim.build.key_for(id, cell, N)
	sim.build.restore(key, {"id": id, "cell": cell, "side": N, "hp": int(sim.data.buildables[id]["hp"]), "open": false,
			"wear": 0.0, "town": true})
	return key


func _heard(sim: SimWorld, kind: String) -> bool:
	sim.step()
	return sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == kind)


func test_glass_breaks_in_one_hit_and_is_loud() -> void:
	var sim := SimWorld.new(10.0)
	var key := _town_piece(sim, "window", Vector2i(3, 3))
	eq(sim.piece_material(key), "glass", "a window is glass")
	eq(sim.player_hit_piece(key, 10.0, "fists"), "broke", "even a punch breaks it")
	check(sim.build.is_broken(key), "the glass is gone")
	check(sim.build.edge_blocks_walk(key), "but the frame is still a walking barrier")
	check(_heard(sim, "glass_break"), "and everything nearby heard it")
	check(float(sim.data.noise["sounds"]["glass_break"]) > float(sim.data.noise["sounds"]["melee_hit"]), "louder than a melee hit")
	eq(sim.player_hit_piece(key, 10.0, "blunt"), "", "a broken window can't break again")
	var key2 := _town_piece(sim, "window", Vector2i(5, 3))
	eq(sim.player_hit_piece(key2, 30.0, "bullet"), "broke", "a round breaks glass too")


func test_wood_takes_axes_best() -> void:
	var sim := SimWorld.new(10.0)
	var a := _town_piece(sim, "door", Vector2i(1, 1))
	var b := _town_piece(sim, "door", Vector2i(2, 1))
	eq(sim.piece_material(a), "wood", "a town door is wood")
	var hp: int = sim.build.pieces[a]["hp"]
	eq(sim.player_hit_piece(a, 20.0, "axe"), "hit", "an axe chunks it")
	eq(sim.player_hit_piece(b, 20.0, "blade"), "hit", "a blade barely marks it")
	check(hp - int(sim.build.pieces[a]["hp"]) > 4 * (hp - int(sim.build.pieces[b]["hp"])), "the axe does far more to wood")
	check(_heard(sim, "wood_hit"), "a knock you can hear")
	var hits := 0
	while sim.build.pieces.has(a) and hits < 50:
		sim.player_hit_piece(a, 40.0, "axe")
		hits += 1
	check(not sim.build.pieces.has(a), "enough axe hits break the door down (%d)" % hits)
	check(_heard(sim, "wood_break"), "with a crash")


func test_what_you_cant_break() -> void:
	var sim := SimWorld.new(10.0)
	var wall := _town_piece(sim, "town_wall", Vector2i(4, 4))
	eq(sim.piece_material(wall), "", "brick house walls don't break from your hits")
	eq(sim.player_hit_piece(wall, 999.0, "axe"), "", "not even an axe")
	sim.give_debug_kit()
	sim.inventory.add("plank", 50)
	sim.inventory.add("nails", 50)
	eq(sim.build.place("foundation", Vector2i(8, 8), N, sim.inventory), "", "a foundation")
	eq(sim.build.place("door", Vector2i(8, 8), N, sim.inventory), "", "your own door")
	var own := sim.build.key_for("door", Vector2i(8, 8), N)
	eq(sim.piece_material(own), "", "your own builds are safe from a missed swing")


func test_hitting_wood_wears_the_weapon() -> void:
	var sim := SimWorld.new(10.0)
	var door := _town_piece(sim, "door", Vector2i(1, 1))
	var piece: Dictionary = sim.gear.equipped["weapon"]
	sim.player_hit_piece(door, 20.0, sim.gear.weapon_class())
	check(float(piece["condition"]) < 1.0, "chopping at doors wears your weapon too")


func test_zombies_breaking_a_window_sound_like_glass() -> void:
	var sim := SimWorld.new(10.0)
	var key := _town_piece(sim, "window", Vector2i(3, 3))
	sim.build.pieces[key]["hp"] = 1
	var z := sim.horde.spawn("shambler", sim.build.piece_center(key) + Vector3(0, 0, 0.8))
	z.state = ZombieBrain.State.BREAK
	z.break_key = key
	z.break_from = ZombieBrain.State.CHASE
	var heard := false
	for i in 200:
		sim.step()
		if sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "glass_break"):
			heard = true
			break
		if sim.build.is_broken(key):
			break
	check(sim.build.is_broken(key) or heard, "the zombie broke it")
	check(heard or _heard(sim, "glass_break"), "and it sounded like glass, not a thud")


func test_broken_window_shows_jagged_glass() -> void:
	var glass := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.3, 0.03)
	glass.mesh = box
	var a := BuildView.shard_ring(glass, "w:3:3:0")
	var b := BuildView.shard_ring(glass, "w:3:3:0")
	check(a.mesh != null and a.mesh.get_surface_count() == 1, "shards are a mesh")
	eq(a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "the same window always breaks the same way")
	check(a.mesh.get_aabb().size.x <= 1.41, "the shards stay inside the frame")
	glass.free()
	a.free()
	b.free()
