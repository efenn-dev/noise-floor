extends "res://test/base_test.gd"
## SoundView turns the noise system into sound: a hum on each working machine, as loud as the sim
## says (a muffler makes it quieter), gone when the machine stops; one-offs for new noise events.

const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func _smelter_sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.give_debug_kit()
	sim.inventory.add("plank", 200)
	sim.inventory.add("nails", 200)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 3
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func _hum(view: SoundView) -> AudioStreamPlayer3D:
	var hums := view.find_children("*", "AudioStreamPlayer3D", false, false)
	return hums[0] if hums.size() == 1 else null


func test_working_machines_hum_at_their_loudness() -> void:
	var sim := _smelter_sim()
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	for i in 10:
		sim.step()
	view._process(0.0)
	eq(view.hum_count(), 1, "the working smelter hums")
	var hum := _hum(view)
	check(hum != null and hum.stream != null, "with the smelter sound")
	var loud: float = sim.data.buildables["smelter"]["loudness"]
	near(hum.volume_db if hum else 99.0, SoundView.volume_for(loud), "as loud as the noise system says")
	eq(sim.fit_muffler(Vector2i(0, 0)), "", "fit a muffler")
	sim.step()
	view._process(0.0)
	var cut: float = sim.data.noise["muffler"]["cut"]
	near(hum.volume_db if hum else 99.0, SoundView.volume_for(loud - cut), "a muffler makes it quieter")
	check(SoundView.volume_for(loud - cut) < SoundView.volume_for(loud), "quieter, not louder")
	for i in 400:  # run out of scrap
		sim.step()
	view._process(0.0)
	eq(view.hum_count(), 0, "an idle machine goes quiet")
	view.free()


func test_noise_events_play_once() -> void:
	var sim := _smelter_sim()
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	sim.step()
	view._process(0.0)  # the smelter's hum appears first
	var before := view.get_child_count()
	sim.make_noise(Vector3(0, 0, 0), "footstep_walk")
	sim.step()
	view._process(0.0)
	view._process(0.0)
	await tree.process_frame
	# Headless runs free one-offs at once (nothing can hear them), so check the bookkeeping instead.
	eq(view._heard.size(), sim.noise.recent.size(), "the new footstep is marked as played")
	eq(view.get_child_count(), before, "and nothing piles up")
	view.free()
