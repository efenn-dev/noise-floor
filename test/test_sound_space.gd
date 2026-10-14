extends "res://test/base_test.gd"
## V4: sound in space. Walls between you and a sound muffle it (the zombies' own wall count), world
## sounds echo indoors, the wind dulls indoors, and background moans, clangs and creaks come and go.

const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func test_occlusion_table() -> void:
	eq(SoundView.occlusion(0), Vector2(0.0, 5000.0), "no walls: untouched")
	var last := SoundView.occlusion(0)
	for w: int in range(1, 6):
		var o := SoundView.occlusion(w)
		check(o.x <= last.x and o.y <= last.y, "each wall is at least as muffled (%d)" % w)
		last = o
	check(SoundView.occlusion(1).x <= -6.0, "one wall takes a clear bite out")
	eq(SoundView.occlusion(9), SoundView.occlusion(3), "3+ walls is the floor")


func test_indoor_echo_and_wind() -> void:
	var out := SoundView.reverb_for(0.0)
	var inside := SoundView.reverb_for(1.0)
	check(inside["wet"] > out["wet"] * 3.0, "much more echo indoors")
	check(inside["room_size"] < out["room_size"], "a smaller room indoors")
	check(SoundView.ambience_for(1.0).x < 2000.0, "the wind is dull indoors")
	check(SoundView.ambience_for(1.0).y < -6.0, "and quieter")
	eq(SoundView.ambience_for(0.0), Vector2(20000.0, 0.0), "untouched outside")


func test_background_sounds_come_more_often_at_night() -> void:
	check(SoundView.ambient_delay(true, 1.0) < SoundView.ambient_delay(false, 0.0), "the longest night gap is shorter than the shortest day gap")
	near(SoundView.ambient_delay(false, 0.5), lerpf(SoundView.AMBIENT_DELAY["day"].x, SoundView.AMBIENT_DELAY["day"].y, 0.5), "day midpoint")


func test_buses_made_once() -> void:
	SoundView.ensure_buses()
	var count := AudioServer.bus_count
	SoundView.ensure_buses()
	eq(AudioServer.bus_count, count, "no duplicate buses")
	var w := AudioServer.get_bus_index(SoundView.WORLD_BUS)
	check(w >= 0 and AudioServer.get_bus_effect(w, 0) is AudioEffectReverb, "World bus with a reverb")
	var a := AudioServer.get_bus_index(SoundView.AMBIENCE_BUS)
	check(a >= 0 and AudioServer.get_bus_effect(a, 0) is AudioEffectLowPassFilter, "Ambience bus with a low-pass")


func test_a_wall_muffles_a_machine() -> void:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.give_debug_kit()
	sim.inventory.add("plank", 200)
	sim.inventory.add("nails", 200)
	eq(sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory), "", "foundation under the smelter")
	eq(sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory), "", "smelter")
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 3
	sim.player_pos = Vector3(1.0, 0.0, 10.0)  # south of it, in the open
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	for i in 10:
		sim.step()
	view._process(0.0)
	var hum: AudioStreamPlayer3D = view.find_children("*", "AudioStreamPlayer3D", false, false)[0]
	var loud: float = sim.data.buildables["smelter"]["loudness"]
	near(hum.volume_db, SoundView.volume_for(loud), "in the open: full volume")
	eq(hum.bus, StringName(SoundView.WORLD_BUS), "machines play on the World bus (indoor echo)")
	eq(sim.build.place("foundation", Vector2i(0, 1), N, sim.inventory), "", "foundation for the wall")
	eq(sim.build.place("wall", Vector2i(0, 1), N, sim.inventory), "", "a wall between you and it")
	var src: Vector3 = sim.noise.continuous[0]["pos"]
	eq(view.walls_to(src), 1, "one wall counted (the same count the zombies' hearing uses)")
	view._process(SoundView.OCCLUSION_EVERY + 0.01)  # past the re-count interval
	near(hum.volume_db, SoundView.volume_for(loud) + SoundView.occlusion(1).x, "quieter behind the wall")
	near(hum.attenuation_filter_cutoff_hz, SoundView.occlusion(1).y, "and duller")
	view.free()


func test_indoor_value_drives_the_echo() -> void:
	var sim := SimWorld.new(10.0)
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	view.indoor = 1.0
	view._process(0.0)
	var verb := AudioServer.get_bus_effect(AudioServer.get_bus_index(SoundView.WORLD_BUS), 0) as AudioEffectReverb
	near(verb.wet, SoundView.reverb_for(1.0)["wet"], "indoors: the room echo")
	view.indoor = 0.0
	view._process(0.0)
	near(verb.wet, SoundView.reverb_for(0.0)["wet"], "outside again")
	view.free()


func test_background_sound_fires_and_reschedules() -> void:
	var sim := SimWorld.new(23.0)  # night
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	view._ambient_timer = 0.0
	view._process(0.01)
	eq(view.ambient_played, 1, "one background sound")
	var range_s: Vector2 = SoundView.AMBIENT_DELAY["night"]
	check(view._ambient_timer >= range_s.x and view._ambient_timer <= range_s.y, "next one scheduled in the night range")
	view.free()


func test_new_sounds_exist() -> void:
	for s: String in ["creak", "clang_far", "hit_body", "shot_pistol", "shot_rifle"]:
		check(SoundView.stream(s) != null, "%s.wav loads" % s)
