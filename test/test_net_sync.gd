extends "res://test/base_test.gd"
## Co-op B (docs/COOP_PLAN.md): the host's world goes to a joiner as a save (NetSync.snapshot) and then as refreshes
## (NetSync.refresh -> apply_refresh): the clock, the players, the zombies, belts and machines, the cars, the pieces that
## changed, containers searched, the supplies. The joiner's own position is its own. A joiner's position comes up the
## other way (player_state -> apply_player_state) and the host's zombies mind it.

const N := BuildGrid.Side.NORTH


func _world(seed_value: int) -> SimWorld:
	var sim := SimWorld.new(12.0, null, seed_value, "normal")
	var plan := TownPlan.generate(seed_value, sim.data)
	sim.place_town(plan)
	sim.place_factory(plan)
	sim.place_props(plan)
	sim.horde.spawn_town(6)  # the plan alone spawns nobody and registers no containers; main.gd does that
	sim.loot.add("fridge_test", "fridge", Vector3(4, 0, 6))
	sim.power.free = true
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	return sim


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func _door_key(sim: SimWorld) -> String:
	for key: String in sim.build.pieces:
		if sim.build.pieces[key]["id"] == "door":
			return key
	return ""


func _round_trip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_the_snapshot_is_the_save_and_a_copy_loads_from_it() -> void:
	var host := _world(3)
	host.add_player("Kaleb")
	var d := _round_trip(NetSync.snapshot(host))
	eq(int(d["version"]), SaveGame.VERSION, "the snapshot is a save of the current version")
	eq((d["players"] as Array).size(), 2, "with both players")
	var copy := _world(3)
	eq(SaveGame.apply(copy, d), "", "a copy built the way a load is")
	eq(copy.players.size(), 2, "has both players")
	eq(copy.players[1].name, "Kaleb", "by name")
	eq(copy.horde.zombies.size(), host.horde.zombies.size(), "and the same zombies")


func test_refreshes_keep_the_copy_in_step_and_leave_the_joiners_own_position_alone() -> void:
	var host := _world(3)
	var kaleb := host.add_player("Kaleb")
	var rich := _rich()
	eq(host.build.place("foundation", Vector2i(3, 9), N, rich), "", "a foundation")
	eq(host.build.place("smelter", Vector2i(3, 9), N, rich), "", "a smelter on it")
	host.factory.machines[Vector2i(3, 9)].input["scrap_metal"] = 10
	eq(host.build.place("belt", Vector2i(3, 10), N, rich), "", "a belt")
	var copy := _world(3)
	eq(SaveGame.apply(copy, _round_trip(NetSync.snapshot(host))), "", "the copy loads")
	copy.local = kaleb
	copy.active = kaleb
	copy.paused = true
	var sync := NetSync.new(host)
	for i in 40:
		host.step()  # 2 s: the smelter works, the belt carries
	var first := sync.refresh(2.0)
	check(first.has("clock") and first.has("players") and first.has("zombies") and first.has("belts") and first.has("machines"),
			"a refresh carries the clock, the players, the zombies, the belts and the machines")
	check(not first.has("pieces"), "and no piece changes when nothing was built")
	# changes of every kind on the host
	eq(host.build.place("foundation", Vector2i(5, 9), N, rich), "", "the host builds a foundation")
	eq(host.build.place("wall", Vector2i(5, 9), N, rich), "", "and a wall")
	var wall := host.build.key_for("wall", Vector2i(5, 9), N)
	host.build.damage(wall, 7)
	var door := _door_key(host)
	check(door != "", "a town door to open")
	host.build.toggle_door(door)
	var standing: ZombieBrain = host.horde.zombies.values()[0]
	var victim := host.horde.spawn("shambler", Vector3(20, 0, 20))
	victim.take_hit(9999.0, Vector3(21, 0, 20), 0.0)
	var container := "fridge_test"
	eq(host.reveal_container(container), "", "a container searched")
	host.player_pos = Vector3(2, 0, -30)
	var t := host.supplies.add_truck(Vector3(9, 0, 120), 0.3, host.clock.day, host.clock_hours() + 6.0, 1, "the south road")
	host.place_truck(t)
	host.step()
	copy.players[kaleb].pos = Vector3(9, 0, 9)  # the joiner walked here on its own machine
	var wire: Variant = NetSession.unpack(NetSession.pack(sync.refresh(1.5)))
	check(wire is Dictionary, "a refresh survives the wire")
	var d: Dictionary = wire
	NetSync.apply_refresh(copy, d, kaleb)
	near(copy.clock.time_of_day, host.clock.time_of_day, "the clock", 0.0001)
	eq(copy.players[0].pos, host.players[0].pos, "the host's position")
	eq(copy.players[kaleb].pos, Vector3(9, 0, 9), "but the joiner's own position is left alone")
	near(copy.players[0].stats.food, host.players[0].stats.food, "the host's food", 0.001)
	check(copy.build.pieces.has(wall), "the new wall is there")
	if copy.build.pieces.has(wall):
		eq(int(copy.build.pieces[wall]["hp"]), int(host.build.pieces[wall]["hp"]), "with its damage")
	eq(bool(copy.build.pieces[door].get("open", false)), true, "the door is open")
	var vz: ZombieBrain = copy.horde.zombies.get(victim.id)
	check(vz != null and vz.is_dead(), "the killed zombie is dead in the copy")
	var sz: ZombieBrain = copy.horde.zombies.get(standing.id)
	check(sz != null and sz.pos == standing.pos and sz.state == standing.state, "a zombie stands where the host's does")
	check(bool(copy.loot.containers[container]["searched"]), "the searched container is searched")
	eq(copy.factory.belts[Vector2i(3, 10)].items, host.factory.belts[Vector2i(3, 10)].items, "the belt's items")
	near(copy.factory.machines[Vector2i(3, 9)].progress, host.factory.machines[Vector2i(3, 9)].progress, "the smelter's progress", 0.0001)
	eq(copy.factory.machines[Vector2i(3, 9)].output, host.factory.machines[Vector2i(3, 9)].output, "and its output")
	check(copy.loot.containers.has(t["id"]) and copy.wreck_type(t["id"]) != "", "the crashed truck is there to search and strip")
	eq(copy.supplies.trucks.size(), 1, "the supply list came across")
	host.horde.zombies.erase(victim.id)
	var again := sync.refresh(0.1)
	check(not again.has("pieces"), "piece changes are sent once")
	NetSync.apply_refresh(copy, again, kaleb)
	check(not copy.horde.zombies.has(victim.id), "a zombie cleared on the host is gone from the copy")
	eq(host.build.remove(wall, rich), "", "the host takes the wall down")
	NetSync.apply_refresh(copy, sync.refresh(0.1), kaleb)
	check(not copy.build.pieces.has(wall), "and it's gone from the copy")


func test_the_host_takes_the_joiners_position_but_never_its_own_or_a_bad_one() -> void:
	var host := _world(5)
	var kaleb := host.add_player("Kaleb")
	var st := NetSync.player_state(host, kaleb)
	eq(st.size(), 4, "position, facing, light, sneaking")
	NetSync.apply_player_state(host, kaleb, Vector3(4, 0, 7), Vector3(0, 0, 1), true, true)
	eq(host.players[kaleb].pos, Vector3(4, 0, 7), "the joiner's position")
	check(host.players[kaleb].lit and host.players[kaleb].sneaking, "light and sneaking")
	var before: Vector3 = host.players[0].pos
	NetSync.apply_player_state(host, 0, Vector3(99, 0, 99), Vector3(0, 0, 1), false, false)
	eq(host.players[0].pos, before, "slot 0 is the host's own: a joiner can't move it")
	NetSync.apply_player_state(host, kaleb, Vector3(NAN, 0, 0), Vector3(0, 0, 1), false, false)
	eq(host.players[kaleb].pos, Vector3(4, 0, 7), "a NaN position is thrown away")
	NetSync.apply_player_state(host, 7, Vector3(1, 0, 1), Vector3(0, 0, 1), false, false)
	eq(host.players.size(), 2, "an unknown slot does nothing")
	var z := host.horde.spawn("shambler", Vector3(4, 0, 12))
	host.player_pos = Vector3(0, 0, -200)  # the host is far away
	for i in 20:
		z.los_clear = true
		host.step()
	check(z.state == ZombieBrain.State.CHASE or z.state == ZombieBrain.State.ATTACK,
			"a zombie beside the joiner goes for it where it said it was (%s)" % z.state_name())
