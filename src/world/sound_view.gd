class_name SoundView
extends Node3D
## Plays the world's sounds from sim state, so what you hear is what the zombies hear:
## - a looping hum on every working machine and running generator, as loud as its loudness in the
##   noise system (a muffled machine really sounds quieter)
## - a one-off for each new noise event (footsteps, hits, bashes, doors) and each turret shot
## - wind, which turns colder and howls at night
## V4 (Sprint 4): walls between you and a sound muffle it (the same NoiseField.walls_between the zombies'
## hearing uses), world sounds echo indoors (the World bus reverb follows `indoor`, which main.gd sets
## from its indoor fog), the wind dulls indoors (the Ambience bus low-pass), and now and then a far-off
## moan or clang (a creak indoors) plays for atmosphere. Those are presentation only: zombies don't hear them.
## Zombie voices live on ZombieBody. Sounds come from tools/audio/synth.py and assets/sounds/zombie/.

const LOOPS := {"smelter": "hum_smelter", "press": "hum_press", "purifier": "hum_purifier",
		"canner": "hum_canner", "generator": "engine_generator", "car": "engine_car",
		# M17a: work on the water tower (hammering borrows the press, the pump the generator's engine)
		"tower_hammer": "hum_press", "tower_pump": "engine_generator"}
const STEPS := ["step_1", "step_2", "step_3", "step_4"]
const EVENTS := {"footstep_walk": STEPS, "footstep_sprint": STEPS, "melee_hit": ["hit_body"],
		"zombie_bash": ["bash"], "wreck": ["bash"], "door": ["door"], "horn": ["horn"],
		# M14: guns (the sim's shot loudness sets the volume) and the reload click
		"gunshot_pistol": ["shot_pistol"], "gunshot_rifle": ["shot_rifle"],
		"gunshot_pistol_suppressed": ["shot_pistol_suppressed"], "gunshot_rifle_suppressed": ["shot_rifle_suppressed"],
		"reload": ["reload"],
		# M15: a decoy noisemaker is a horn; a tripwire bell borrows the click until it gets its own sound
		"noisemaker": ["horn"], "bell": ["click"]}
## Gunshots are 85-95 loud, so the usual boost would blare: they play this much under their level instead.
const GUN_BOOST := -8.0
## One-offs play this much above their loudness level; footsteps much less (Emmitt: the first ones
## were "too loud and sharp"), since they're right under your ears.
const EVENT_BOOST := 10.0
const STEP_BOOST := 2.0
## Volume = (loudness - LOUD_REF) * LOUD_SLOPE dB. The sim's loudness range (5-80) is wide, so it's
## squeezed: a generator (80) plays at +7.5 dB, a purifier (40) at -12.5 dB, a muffler takes 7.5 dB off.
const LOUD_REF := 65.0
const LOUD_SLOPE := 0.5
const MAX_DISTANCE := 70.0
## V4: [volume dB, low-pass cutoff Hz] for 0, 1, 2 and 3+ walls between you and the sound.
const OCCLUSION := [Vector2(0.0, 5000.0), Vector2(-7.0, 1500.0), Vector2(-12.0, 850.0), Vector2(-16.0, 550.0)]
const OCCLUSION_EVERY := 0.25  # seconds between wall re-counts for machine hums
const EAR_HEIGHT := 1.6
const WORLD_BUS := "World"
const AMBIENCE_BUS := "Ambience"
## V4: background one-offs, seconds between them ([min, max]); nights are busier.
const AMBIENT_DELAY := {"day": Vector2(35.0, 75.0), "night": Vector2(12.0, 30.0)}
const AMBIENT_FAR := Vector2(35.0, 60.0)  # metres away for moans and clangs

static var _streams: Dictionary = {}
## Headless runs (tests, cloud) do all the bookkeeping but start no playback: nothing can hear it, and
## a sound still playing at quit is reported as a leak.
static var audible: bool = DisplayServer.get_name() != "headless"

var sim: SimWorld
var _hums: Dictionary = {}  # noise key -> AudioStreamPlayer3D
var _heard: Array = []  # noise events already played (by reference)
var _shots: Array = []  # turret shots already played (by reference)
var _scares: Array = []  # S4: jumpscare stings already played (by reference)
var scares_played := 0  # for tests
## S4: the stings, not positional: they're in your head, not in the world.
const STINGS := {"close": ["sting_close", -3.0], "horde": ["sting_horde", -1.0]}
var _wind_day: AudioStreamPlayer
var _wind_night: AudioStreamPlayer
var _step := 0
var indoor := 0.0  # V4: 0 outside, 1 under a roof (main.gd sets it every frame from its indoor fog)
var ambient_played := 0  # V4: for tests
var _occlusion_timer := 0.0
var _ambient_timer := 20.0


static func stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := "res://assets/sounds/%s.wav" % sound
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


## A one-off positional sound under `parent` that frees itself when done.
## V4: `walls` between you and it muffles it (OCCLUSION); it plays on the World bus (indoor echo).
static func play_at(parent: Node, sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, walls: int = 0) -> void:
	var s := stream(sound)
	if s == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.pitch_scale = pitch
	p.max_distance = MAX_DISTANCE
	p.unit_size = 3.0
	p.bus = WORLD_BUS if AudioServer.get_bus_index(WORLD_BUS) >= 0 else &"Master"
	var occ := occlusion(walls)
	p.volume_db = volume_db + occ.x
	p.attenuation_filter_cutoff_hz = occ.y
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	if audible:
		p.play()
	else:
		p.queue_free()


## Drop the loaded sounds (at exit, so Godot doesn't report them as still in use).
static func clear_cache() -> void:
	_streams.clear()


static func volume_for(loudness: float) -> float:
	return (loudness - LOUD_REF) * LOUD_SLOPE


## V4: how much `walls` walls take off a sound: x = dB, y = low-pass cutoff in Hz.
static func occlusion(walls: int) -> Vector2:
	return OCCLUSION[clampi(walls, 0, OCCLUSION.size() - 1)]


## V4: the World bus reverb for how far indoors you are: a small, damped room inside; outside just a
## faint slap off the houses.
static func reverb_for(indoor_amount: float) -> Dictionary:
	var k := clampf(indoor_amount, 0.0, 1.0)
	return {"wet": lerpf(0.04, 0.28, k), "room_size": lerpf(0.8, 0.35, k), "damping": lerpf(0.5, 0.7, k)}


## V4: the wind's low-pass cutoff (Hz) and volume change (dB) for how far indoors you are.
static func ambience_for(indoor_amount: float) -> Vector2:
	var k := clampf(indoor_amount, 0.0, 1.0)
	return Vector2(lerpf(20000.0, 900.0, k), lerpf(0.0, -9.0, k))


## V4: seconds until the next background sound; r is a random number 0..1.
static func ambient_delay(night: bool, r: float) -> float:
	var range_s: Vector2 = AMBIENT_DELAY["night" if night else "day"]
	return lerpf(range_s.x, range_s.y, clampf(r, 0.0, 1.0))


## V4: makes the World (reverb) and Ambience (low-pass) buses once per run; both feed Master.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(WORLD_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, WORLD_BUS)
		AudioServer.set_bus_send(i, &"Master")
		var verb := AudioEffectReverb.new()
		verb.wet = 0.04
		verb.dry = 1.0
		verb.predelay_msec = 30.0
		AudioServer.add_bus_effect(i, verb)
	if AudioServer.get_bus_index(AMBIENCE_BUS) < 0:
		var j := AudioServer.bus_count
		AudioServer.add_bus(j)
		AudioServer.set_bus_name(j, AMBIENCE_BUS)
		AudioServer.set_bus_send(j, &"Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(j, lp)


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	ensure_buses()
	_wind_day = _ambient("wind_day")
	_wind_night = _ambient("wind_night")
	_wind_day.bus = AMBIENCE_BUS
	_wind_night.bus = AMBIENCE_BUS
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())  # many machines at once mustn't clip


func _process(delta: float) -> void:
	if sim == null:
		return
	_occlusion_timer -= delta
	var recount := _occlusion_timer <= 0.0
	if recount:
		_occlusion_timer = OCCLUSION_EVERY
	_update_hums(recount)
	_play_new_events()
	_play_new_shots()
	_play_new_scares()
	_update_space()
	_tick_ambient(delta)
	var light := sim.clock.daylight()
	var wind_cut := ambience_for(indoor).y
	_wind_day.volume_db = linear_to_db(maxf(light, 0.001)) - 6.0 + wind_cut
	_wind_night.volume_db = linear_to_db(maxf(1.0 - light, 0.001)) - 4.0 + wind_cut


## V4: where your ears are (the sim knows where the player stands).
func ear() -> Vector3:
	return sim.player_pos + Vector3.UP * EAR_HEIGHT


## V4: walls between your ears and a sound at `pos`.
func walls_to(pos: Vector3) -> int:
	return sim.noise.walls_between(ear(), pos)


## V4: the indoor echo and the wind's muffling follow how far indoors you are.
func _update_space() -> void:
	var w := AudioServer.get_bus_index(WORLD_BUS)
	if w >= 0 and AudioServer.get_bus_effect_count(w) > 0:
		var verb := AudioServer.get_bus_effect(w, 0) as AudioEffectReverb
		var r := reverb_for(indoor)
		verb.wet = r["wet"]
		verb.room_size = r["room_size"]
		verb.damping = r["damping"]
	var a := AudioServer.get_bus_index(AMBIENCE_BUS)
	if a >= 0 and AudioServer.get_bus_effect_count(a) > 0:
		(AudioServer.get_bus_effect(a, 0) as AudioEffectLowPassFilter).cutoff_hz = ambience_for(indoor).x


## V4: a far-off moan or clang now and then (a creak when you're indoors), for atmosphere only.
func _tick_ambient(delta: float) -> void:
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	var night := sim.clock.is_night()
	_ambient_timer = ambient_delay(night, randf())
	ambient_played += 1
	if indoor > 0.5 and randf() < 0.6:
		var near := ear() + Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
		play_at(self, "creak", near, -14.0, randf_range(0.85, 1.1))
		return
	var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var far := ear() + dir * randf_range(AMBIENT_FAR.x, AMBIENT_FAR.y)
	if randf() < (0.7 if night else 0.45):
		play_at(self, "zombie/moan_%02d" % (1 + randi() % 13), far, -4.0, randf_range(0.8, 0.95))
	else:
		play_at(self, "clang_far", far, -6.0, randf_range(0.9, 1.1))


func hum_count() -> int:
	return _hums.size()


func _update_hums(recount: bool = true) -> void:
	var live := {}
	for s: Dictionary in sim.noise.continuous:
		var key: String = s["key"]
		if not LOOPS.has(s["kind"]):
			continue
		live[key] = true
		var p: AudioStreamPlayer3D = _hums.get(key)
		if p == null:
			p = AudioStreamPlayer3D.new()
			p.stream = stream(LOOPS[s["kind"]])
			p.max_distance = MAX_DISTANCE
			p.unit_size = 3.0
			p.bus = WORLD_BUS if AudioServer.get_bus_index(WORLD_BUS) >= 0 else &"Master"
			p.set_meta("walls", walls_to(s["pos"]))
			add_child(p)
			p.position = s["pos"]
			if p.stream != null and audible:
				p.play(randf() * p.stream.get_length())  # machines of one kind don't play in lockstep
			_hums[key] = p
		if recount:
			p.set_meta("walls", walls_to(s["pos"]))  # V4: re-counted a few times a second, not every frame
		var occ := occlusion(int(p.get_meta("walls", 0)))
		p.volume_db = volume_for(s["loudness"]) + occ.x
		p.attenuation_filter_cutoff_hz = occ.y
		if s["kind"] == "car":  # the engine revs with speed
			var car: Dictionary = sim.vehicles.cars.get(key.trim_prefix("car:"), {})
			p.pitch_scale = 0.8 + minf(float(car.get("speed", 0.0)) / 20.0, 1.1)
			p.position = s["pos"]
	for key: String in _hums.keys():
		if not live.has(key):
			_hums[key].queue_free()
			_hums.erase(key)


func _play_new_events() -> void:
	var now: Array = sim.noise.recent
	for s: Dictionary in now:
		if _seen(_heard, s):
			continue
		if s["kind"] == "scream":  # a screamer's shriek: a moan, much higher and louder
			play_at(self, "zombie/moan_%02d" % (1 + randi() % 13), s["pos"], volume_for(s["loudness"]), randf_range(1.5, 1.75),
					walls_to(s["pos"]))
			continue
		if not EVENTS.has(s["kind"]):
			continue
		var options: Array = EVENTS[s["kind"]]
		_step += 1
		var boost := STEP_BOOST if String(s["kind"]).begins_with("footstep") else EVENT_BOOST
		if String(s["kind"]).begins_with("gunshot"):
			boost = GUN_BOOST
		play_at(self, options[_step % options.size()], s["pos"], volume_for(s["loudness"]) + boost, randf_range(0.92, 1.08),
				walls_to(s["pos"]))
	_heard = now.duplicate()


## S4: a sting for each new jumpscare the sim's Scares fired (a zombie in your face round a corner, a mob
## turning on you).
func _play_new_scares() -> void:
	for e: Dictionary in sim.scares.fired:
		if _seen(_scares, e) or not STINGS.has(e["kind"]):
			continue
		_scares.append(e)
		scares_played += 1
		var s := stream(STINGS[e["kind"]][0])
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = float(STINGS[e["kind"]][1])
		add_child(p)
		p.finished.connect(p.queue_free)
		if audible:
			p.play()
	while _scares.size() > Scares.KEEP:
		_scares.pop_front()


func _play_new_shots() -> void:
	var now: Array = sim.defense.recent_shots
	for s: Dictionary in now:
		if not _seen(_shots, s):
			play_at(self, "turret_shot", s["from"], volume_for(float(sim.data.buildables["nail_turret"]["loudness"])) + 6.0,
					randf_range(0.95, 1.05), walls_to(s["from"]))
	_shots = now.duplicate()


static func _seen(list: Array, item: Dictionary) -> bool:
	for other in list:
		if is_same(other, item):
			return true
	return false


func _ambient(sound: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	add_child(p)
	if p.stream != null and audible:
		p.play()
	return p


func _exit_tree() -> void:
	for p in find_children("*", "AudioStreamPlayer3D", false, false) + find_children("*", "AudioStreamPlayer", false, false):
		p.stop()  # a sound still playing when the node goes would be held by the audio server
