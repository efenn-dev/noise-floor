extends "res://test/base_test.gd"
## S4: dead zombies are searchable where they fell, Zomboid-style: the corpse is a loot container with the
## "zombie" table plus whatever the zombie carried (no more drop bags); a searched corpse clears sooner, an
## unsearched one after CORPSE_TIME, and the container goes with it. In the game scene the body on the
## ground is what the look ray finds, so E on it searches.

const MAIN := "res://scenes/main.tscn"


func _kill(sim: SimWorld, z: ZombieBrain) -> String:
	z.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	return SimWorld.CORPSE + str(z.id)


func _search(sim: SimWorld, cid: String) -> void:
	eq(sim.search(cid), "", "search the body")
	for i in roundi(sim.loot.search_time() / SimWorld.TICK) + 2:
		sim.step()


func test_a_dead_zombie_is_a_container_you_can_search() -> void:
	var sim := SimWorld.new()
	var z := sim.horde.spawn("shambler", Vector3(4, 0, -6))
	sim.player_pos = Vector3(4, 0, -4)
	sim.step()
	check(not sim.loot.containers.has(SimWorld.CORPSE + str(z.id)), "alive: nothing to search")
	var cid := _kill(sim, z)
	check(sim.loot.containers.has(cid), "dead: its body is a container")
	eq(sim.loot.containers[cid]["table"], "zombie", "the zombie loot table")
	eq(sim.loot.containers[cid]["pos"], z.pos, "where it fell")
	eq(sim.loot.display_name(cid), "Dead zombie", "called a dead zombie")
	check(sim.messages.any(func(m: Dictionary) -> bool: return "Dead zombies can be searched" in m["text"]), "told once how")
	eq(sim.bags.size(), 0, "no bag on the ground")
	_search(sim, cid)
	check(sim.loot.containers[cid]["searched"], "searched")
	check(z.searched, "the zombie knows")
	eq(sim.search(cid), "Already searched", "once")
	# A searched corpse clears sooner than an unsearched one, and its container goes with it.
	for i in roundi(ZombieBrain.SEARCHED_CORPSE_TIME / SimWorld.TICK) + 2:
		sim.step()
	check(not sim.horde.zombies.has(z.id), "a searched corpse is cleared after %.0f s" % ZombieBrain.SEARCHED_CORPSE_TIME)
	check(not sim.loot.containers.has(cid), "and its container is gone")


func test_loot_table_and_what_it_carried() -> void:
	var sim := SimWorld.new()
	var found := {}
	var empties := 0
	for i in 40:
		var z := sim.horde.spawn("shambler", Vector3(10 + i, 0, -6))
		sim.player_pos = z.pos
		var cid := _kill(sim, z)
		_search(sim, cid)
		var got := false
		for item: String in sim.loot.inventory(cid).items():
			found[item] = true
			got = true
		if not got:
			empties += 1
		sim.horde.zombies.erase(z.id)
		sim.loot.remove(cid)
	check(found.size() >= 3, "corpses give a few different things (%s)" % found.keys())
	check(empties > 3 and empties < 37, "some corpses have nothing on them (%d of 40)" % empties)
	for item: String in found:
		check(sim.data.loot["zombie"]["items"].any(func(e: Dictionary) -> bool: return e["item"] == item), "%s is on the zombie table" % item)
	# A runner's drop chance is higher than a shambler's; what a zombie carried is on its body, not in a bag.
	var carried := 0
	for i in 60:
		var r := sim.horde.spawn("runner", Vector3(100 + i, 0, -6))
		var cid := _kill(sim, r)
		if not sim.loot.containers[cid]["gear"].is_empty():
			carried += 1
		sim.horde.zombies.erase(r.id)
		sim.loot.remove(cid)
	check(carried >= 4 and carried <= 24, "about a fifth of runners carry a piece (%d of 60)" % carried)
	eq(sim.bags.size(), 0, "never a bag")


func test_unsearched_corpse_lasts_and_an_abandoned_search_is_dropped() -> void:
	var sim := SimWorld.new()
	var z := sim.horde.spawn("shambler", Vector3(4, 0, -6))
	sim.player_pos = Vector3(4, 0, -4)
	var cid := _kill(sim, z)
	for i in roundi(ZombieBrain.SEARCHED_CORPSE_TIME / SimWorld.TICK) + 2:
		sim.step()
	check(sim.horde.zombies.has(z.id) and sim.loot.containers.has(cid), "an unsearched corpse stays past %.0f s" % ZombieBrain.SEARCHED_CORPSE_TIME)
	eq(sim.search(cid), "", "start a search")
	sim.step()
	eq(sim.loot.active, cid, "searching it")
	z.dead_time = ZombieBrain.CORPSE_TIME  # time's up for the corpse
	sim.step()
	check(not sim.horde.zombies.has(z.id), "cleared after CORPSE_TIME")
	check(not sim.loot.containers.has(cid), "its container is gone")
	eq(sim.loot.active, "", "and the search with it")
	eq(sim.search(cid), "Nothing to search", "nothing left to search")


func test_in_the_world_e_searches_the_body() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var player: Player = main.player
	var at := player.global_position + Vector3(0, 0, -2.5)  # 2.5 m ahead (north)
	var z := sim.horde.spawn("shambler", at)
	for i in 3:
		await tree.physics_frame
	var body: ZombieBody = main.zombie_view.body_for(z.id)
	check(body != null and body.collision_layer == Layers.ZOMBIE, "a live zombie is a zombie body")
	z.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	for i in 6:
		await tree.physics_frame
	eq(body.collision_layer, Layers.BAG, "dead, the body is on the bag layer: only the look ray sees it")
	eq(body.get_meta("container_id", ""), SimWorld.CORPSE + str(z.id), "and names its container")
	player.set_look(0.0, -35.0)  # down at the body on the ground ahead
	for i in 3:
		await tree.physics_frame
	main.interactor.update_target()
	eq(main.interactor.target_container, SimWorld.CORPSE + str(z.id), "looking down at it finds the corpse")
	check("Dead zombie" in main.interactor.status_text() and "[E] search" in main.interactor.status_text(),
			"the prompt offers to search it (%s)" % main.interactor.status_text().replace("\n", " | "))
	eq(main.interactor.interact(), "", "E starts the search")
	eq(sim.loot.active, SimWorld.CORPSE + str(z.id), "searching the body")
	main.queue_free()
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
