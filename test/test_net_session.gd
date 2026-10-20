extends "res://test/base_test.gd"
## Co-op B: the link itself, host and joiner in this one process (two multiplayer branches under the tree's root, ENet
## over 127.0.0.1): the joiner says hello and gets a slot, the world arrives as a save file, refreshes flow into the
## joiner's copy, the joiner's position flows up, and the host's beacon is heard.

const PORT := 40711
const WAIT := 900  # frames, at most (15 s at 60 fps)


## A branch under the tree's root with its own multiplayer (the runner's root isn't in the tree until a frame passes).
func _branch(p_name: String) -> Node:
	var root := Node.new()
	root.name = p_name
	tree.root.add_child(root)
	await tree.process_frame
	tree.set_multiplayer(SceneMultiplayer.new(), root.get_path())
	return root


func _until(what: Callable) -> bool:
	for i in WAIT:
		if what.call():
			return true
		await tree.process_frame
	return what.call()


func _world(seed_value: int) -> SimWorld:
	var sim := SimWorld.new(12.0, null, seed_value, "normal")
	var plan := TownPlan.generate(seed_value, sim.data)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	sim.horde.spawn_town(6)  # the plan alone spawns nobody; main.gd does that
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	return sim


func test_a_joiner_gets_a_slot_the_world_refreshes_and_the_host_gets_its_position() -> void:
	var a: Node = await _branch("NetA")
	var b: Node = await _branch("NetB")
	var host := NetSession.new()
	host.name = "NetSession"
	host.beacon_address = "127.0.0.1"
	a.add_child(host)
	var joiner := NetSession.new()
	joiner.name = "NetSession"
	b.add_child(joiner)
	await tree.process_frame  # both links are ready
	var sim := _world(4)
	eq(host.host("Dad", PORT), "", "hosting")
	host.attach(sim)
	check(NetSession.pack({"a": 1}).size() > 0 and NetSession.unpack(NetSession.pack({"a": Vector3(1, 2, 3)}))["a"] == Vector3(1, 2, 3),
			"dictionaries pack and unpack")
	eq(joiner.listen(), "", "the joiner listens for games")
	eq(joiner.join("127.0.0.1", PORT, "Kaleb"), "", "joining")
	check(await _until(func() -> bool: return joiner.local_slot >= 0), "the joiner is welcomed (%s)" % joiner.status)
	eq(joiner.local_slot, 1, "into slot 1")
	eq(sim.players.size(), 2, "the host added a player")
	if sim.players.size() == 2:
		eq(sim.players[1].name, "Kaleb", "by name")
	check(sim.messages.any(func(m: Dictionary) -> bool: return "Kaleb joined" in str(m["text"])), "and says so")
	check(await _until(func() -> bool: return joiner.snapshot_ready), "the world arrives (%s)" % joiner.status)
	var d := SaveGame.read(NetSession.JOIN_FILE)
	eq(int(d.get("version", 0)), SaveGame.VERSION, "as a save of the current version")
	eq((d.get("players", []) as Array).size(), 2, "with both players")
	var copy := _world(4)
	eq(SaveGame.apply(copy, d), "", "the joiner's copy loads from it")
	copy.local = 1
	copy.active = 1
	copy.paused = true
	joiner.attach(copy)
	for i in 60:
		sim.step()  # the host's world moves on 3 s
	check(await _until(func() -> bool: return joiner.counts["refreshes_got"] >= 3), "refreshes arrive (%d)" % joiner.counts["refreshes_got"])
	near(copy.clock.time_of_day, sim.clock.time_of_day, "the copy's clock follows the host's", 0.01)
	eq(copy.horde.zombies.size(), sim.horde.zombies.size(), "and its zombies")
	copy.players[1].pos = Vector3(5, 0, 9)
	check(await _until(func() -> bool: return sim.players[1].pos.distance_to(Vector3(5, 0, 9)) < 0.01),
			"the host has where the joiner walked to (%s)" % str(sim.players[1].pos))
	check(await _until(func() -> bool: return not joiner.games.is_empty()), "the joiner heard the host's beacon")
	if not joiner.games.is_empty():
		var g: Dictionary = joiner.games.values()[0]
		eq(g["name"], "Dad", "whose game it is")
		eq(int(g["port"]), PORT, "and its port")
	check(host.counts["refreshes_sent"] >= 3 and host.counts["states_got"] >= 1, "the host counted refreshes out and states in")
	joiner.close()
	host.close()
	eq(joiner.role, "", "closed")
	tree.set_multiplayer(null, a.get_path())
	tree.set_multiplayer(null, b.get_path())
	a.queue_free()
	b.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetSession.JOIN_FILE))


func test_a_joiner_with_nobody_there_is_told() -> void:
	var b: Node = await _branch("NetLonely")
	var joiner := NetSession.new()
	joiner.name = "NetSession"
	b.add_child(joiner)
	await tree.process_frame
	var why := [""]  # a lambda copies a plain local; an array it can write into
	joiner.link_failed.connect(func(w: String) -> void: why[0] = w)
	eq(joiner.join("127.0.0.1", PORT + 5, "Kaleb"), "", "joining a port with nobody on it starts")
	check(await _until(func() -> bool: return why[0] != ""), "and fails in words (%s)" % why[0])
	check("Nobody answered" in why[0], "which say nobody answered")
	joiner.close()
	tree.set_multiplayer(null, b.get_path())
	b.queue_free()
	await tree.process_frame
