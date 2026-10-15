extends "res://test/base_test.gd"
## V16: reload mechanics follow the visible keyframes, survive coarse frames, and replace the generic click.

const SOUND_IDS: Array[String] = ["mag_out", "mag_in", "slide_rack", "bolt_open", "bolt_close",
		"round_in", "shell_in", "pump_back", "pump_forward", "draw_string", "bolt_in",
		"gun_handle", "blade_handle"]
const EXPECTED := {
	"pistol": [[0.18, "mag_out"], [0.62, "mag_in"], [0.74, "slide_rack"]],
	"hunting_rifle": [[0.12, "bolt_open"], [0.47, "round_in"], [0.56, "round_in"],
			[0.65, "round_in"], [0.72, "bolt_close"]],
	"shotgun": [[0.62, "shell_in"]],
	"crossbow": [[0.18, "draw_string"], [0.84, "bolt_in"]],
}


func test_mechanical_sound_assets_exist_and_load() -> void:
	for sound_id: String in SOUND_IDS:
		var path := "res://assets/sounds/%s.wav" % sound_id
		check(ResourceLoader.exists(path), "%s exists" % path)
		var sound := load(path) as AudioStream
		check(sound != null, "%s loads" % path)
		if sound != null:
			check(sound.get_length() >= 0.08 and sound.get_length() <= 0.7,
					"%s is a short one-shot (%.3f s)" % [sound_id, sound.get_length()])
			var wav := sound as AudioStreamWAV
			check(wav != null and not wav.stereo, "%s is mono" % sound_id)
			check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s does not loop" % sound_id)


func test_reload_sound_tables_match_choreography_keys() -> void:
	for gun_id: String in EXPECTED:
		var cues: Array = Shooter.reload_sounds(gun_id)
		eq(cues, EXPECTED[gun_id], "%s sound timing table" % gun_id)
		var keys: Array = {"pistol": Shooter.PISTOL_RELOAD_KEYS,
				"hunting_rifle": Shooter.RIFLE_RELOAD_KEYS,
				"shotgun": Shooter.SHOTGUN_RELOAD_KEYS,
				"crossbow": Shooter.CROSSBOW_RELOAD_KEYS}[gun_id]
		var previous := 0.0
		for cue: Array in cues:
			var progress := float(cue[0])
			check(progress > 0.0 and progress < 1.0, "%s %.2f is inside the reload" % [gun_id, progress])
			check(progress > previous, "%s cues increase at %.2f" % [gun_id, progress])
			check(keys.any(func(key: Array) -> bool: return is_equal_approx(float(key[0]), progress)),
					"%s %.2f belongs to a pose keyframe" % [gun_id, progress])
			previous = progress
	near(float(Shooter.reload_sounds("pistol")[1][0]), 0.62, "pistol mag-in lands at the seat key")
	eq(Shooter.passed_pump_sounds(0.0, 1.0), ["pump_back", "pump_forward"],
			"one coarse pump frame still plays both mechanical cues")


func test_small_and_large_steps_emit_every_cue_once_in_order() -> void:
	for gun_id: String in EXPECTED:
		var expected_ids := _sound_ids(EXPECTED[gun_id])
		eq(_step_reload(gun_id, 0.01), expected_ids, "%s small frames" % gun_id)
		eq(_step_reload(gun_id, 1.0), expected_ids, "%s one large frame" % gun_id)


func test_cancelled_reload_stops_and_a_new_reload_starts_again() -> void:
	var heard := _sound_ids(Shooter.passed_reload_sounds("pistol", 0.0, 0.5))
	eq(heard, ["mag_out"], "cancelling halfway only heard cues already passed")
	# Cancellation makes no more helper calls. A new reload starts from zero and owns a fresh list.
	eq(_sound_ids(Shooter.passed_reload_sounds("pistol", 0.0, 1.0)),
			["mag_out", "mag_in", "slide_rack"], "a new reload plays the full choreography again")


func test_generic_reload_only_plays_without_choreography() -> void:
	for gun_id: String in Shooter.MODELS:
		eq(SoundView.generic_reload_enabled(gun_id), Shooter.reload_sounds(gun_id).is_empty(),
				"%s generic reload policy matches its choreography" % gun_id)
	check(SoundView.generic_reload_enabled("future_gun"), "an unchoreographed gun keeps the generic reload")


func _step_reload(gun_id: String, step: float) -> Array:
	var heard: Array = []
	var previous := 0.0
	while previous < 1.0:
		var current := minf(1.0, previous + step)
		heard.append_array(_sound_ids(Shooter.passed_reload_sounds(gun_id, previous, current)))
		previous = current
	return heard


func _sound_ids(cues: Array) -> Array:
	var ids: Array = []
	for cue: Array in cues:
		ids.append(String(cue[1]))
	return ids
