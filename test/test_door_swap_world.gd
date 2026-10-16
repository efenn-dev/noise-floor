extends "res://test/base_test.gd"
## P6, playtest (Emmitt's son): pulled down a house's front door, built his own in the doorway, "used it and it
## disappeared", then couldn't build a new door. Right-click in build mode took it down without a word, and
## looking through the empty doorway aimed at a wall inside the house ("Already built"). The real flow in the
## game scene: build mode, look, right-click, place, E.

const MAIN := "res://scenes/main.tscn"

var main: Node3D
var sim: SimWorld
var player: Player
var interactor: Interactor
var builder: BuildController
var house: Dictionary


func _setup() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	main = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	sim = main.sim
	player = main.player
	interactor = main.interactor
	builder = main.builder
	house = main.town["houses"][1]  # house_0_e: front door faces west
	sim.inventory.give_all({"plank": 40, "nails": 60})


func _teardown() -> void:
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame


func _look_at(target: Vector3) -> void:
	var d := target - (player.global_position + Vector3(0, 1.65, 0))
	player.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _settle() -> void:
	for i in 3:
		await tree.physics_frame
	interactor.update_target()
	builder.update_aim()


func _messages() -> String:
	var out := PackedStringArray()
	for m: Dictionary in sim.messages:
		out.append(String(m["text"]))
	return " | ".join(out)


func test_replace_a_town_door_and_use_it() -> void:
	await _setup()
	var key := BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"])
	var center := sim.build.piece_center(key)
	check(sim.build.pieces[key].get("town", false), "the front door is the town's")
	player.global_position = Vector3(center.x - 2.5, 0.0, center.z)  # on the lawn, facing the door
	_look_at(center)
	builder.set_active(true)
	builder.select_id("door")
	await _settle()
	eq(builder.aim_remove_key, key, "build mode: looking at the front door")
	eq(builder.try_remove(), "", "right-click takes it down")
	check(not sim.build.pieces.has(key), "it's gone")
	check("Took down the Door: 2 Plank back" in _messages(), "and the game says so, and what came back (%s)" % _messages())
	check("RMB removes" not in builder.status_text(), "the build line doesn't offer to remove what's already gone")
	# Looking at the empty doorway now (the ray goes through it, into the house).
	await _settle()
	eq(BuildGrid.key_for_wall_edge(builder.aim_cell, builder.aim_side), key, "the door ghost sits in the doorway")
	eq(builder.aim_reason, "", "and can go there")
	eq(builder.try_place(), "", "a new door goes in")
	await _settle()
	check(sim.build.pieces.has(key) and not sim.build.pieces[key].get("town", false), "your own door, in the same doorway")
	builder.set_active(false)
	await _settle()
	eq(interactor.target_key, key, "on foot, looking at the new door")
	eq(interactor.interact(), "Door opened", "E opens it")
	await _settle()
	var body: StaticBody3D = main.build_view.body_for(key)
	check(sim.build.pieces.has(key) and body != null and body.is_inside_tree(), "it's still there, open")
	check(body.global_position.x > center.x + 0.5, "swung into the house, away from you")
	# Taking yours down gives all of it back, and another goes straight in again.
	builder.set_active(true)
	_look_at(body.global_position)
	await _settle()
	eq(builder.aim_remove_key, key, "build mode: looking at the open door")
	eq(builder.try_remove(), "", "it comes down")
	check("Took down the Door: 6 Plank, 8 Nails back" in _messages(), "everything back (%s)" % _messages())
	_look_at(center)
	await _settle()
	eq(builder.try_place(), "", "and a new door goes in the doorway again")
	await _teardown()


## The doorway rule only fills a gap with walls on both sides: aiming past the end of a wall line still builds
## on the far edge of the cell you aim at, as before.
func test_only_a_gap_between_walls_counts() -> void:
	await _setup()
	var key := BuildGrid.key_for_wall_edge(house["door_cell"], house["door_side"])
	var cell: Vector2i = house["door_cell"]
	check(not builder.is_wall_gap(cell, house["door_side"]), "a doorway with its door in it isn't a gap")
	sim.build.remove(key, sim.inventory)
	check(builder.is_wall_gap(cell, house["door_side"]), "the empty doorway is")
	check(not builder.is_wall_gap(Vector2i(40, 40), BuildGrid.Side.WEST), "open ground isn't")
	sim.give_debug_kit()
	sim.inventory.give_all({"plank": 40, "nails": 60, "scrap_metal": 20})
	eq(sim.build.place("foundation", Vector2i(40, 40), 0, sim.inventory), "", "a foundation out in the open")
	eq(sim.build.place("foundation", Vector2i(40, 41), 0, sim.inventory), "", "and another south of it")
	eq(sim.build.place("wall", Vector2i(40, 40), BuildGrid.Side.WEST, sim.inventory), "", "a wall on the first")
	check(not builder.is_wall_gap(Vector2i(40, 41), BuildGrid.Side.WEST), "the end of a wall line isn't")
	await _teardown()
