class_name SoundView
extends Node3D
## Plays the world's sounds from sim state, so what you hear is what the zombies hear:
## - a looping hum on every working machine and running generator, as loud as its loudness in the
##   noise system (a muffled machine really sounds quieter)
## - a one-off for each new noise event (footsteps, hits, bashes, doors) and each turret shot
## - wind, which turns colder and howls at night
## Zombie voices live on ZombieBody. Sounds come from tools/audio/synth.py and assets/sounds/zombie/.

const LOOPS := {"smelter": "hum_smelter", "press": "hum_press", "purifier": "hum_purifier",
		"canner": "hum_canner", "generator": "engine_generator", "car": "engine_car"}
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

static var _streams: Dictionary = {}
## Headless runs (tests, cloud) do all the bookkeeping but start no playback: nothing can hear it, and
## a sound still playing at quit is reported as a leak.
static var audible: bool = DisplayServer.get_name() != "headless"

var sim: SimWorld
var _hums: Dictionary = {}  # noise key -> AudioStreamPlayer3D
var _heard: Array = []  # noise events already played (by reference)
var _shots: Array = []  # turret shots already played (by reference)
var _wind_day: AudioStreamPlayer
var _wind_night: AudioStreamPlayer
var _step := 0


static func stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := "res://assets/sounds/%s.wav" % sound
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


## A one-off positional sound under `parent` that frees itself when done.
static func play_at(parent: Node, sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := stream(sound)
	if s == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = MAX_DISTANCE
	p.unit_size = 3.0
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


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	_wind_day = _ambient("wind_day")
	_wind_night = _ambient("wind_night")
	if AudioServer.get_bus_effect_count(0) == 0:
		AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())  # many machines at once mustn't clip


func _process(_delta: float) -> void:
	if sim == null:
		return
	_update_hums()
	_play_new_events()
	_play_new_shots()
	var light := sim.clock.daylight()
	_wind_day.volume_db = linear_to_db(maxf(light, 0.001)) - 6.0
	_wind_night.volume_db = linear_to_db(maxf(1.0 - light, 0.001)) - 4.0


func hum_count() -> int:
	return _hums.size()


func _update_hums() -> void:
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
			add_child(p)
			p.position = s["pos"]
			if p.stream != null and audible:
				p.play(randf() * p.stream.get_length())  # machines of one kind don't play in lockstep
			_hums[key] = p
		p.volume_db = volume_for(s["loudness"])
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
			play_at(self, "zombie/moan_%02d" % (1 + randi() % 13), s["pos"], volume_for(s["loudness"]), randf_range(1.5, 1.75))
			continue
		if not EVENTS.has(s["kind"]):
			continue
		var options: Array = EVENTS[s["kind"]]
		_step += 1
		var boost := STEP_BOOST if String(s["kind"]).begins_with("footstep") else EVENT_BOOST
		if String(s["kind"]).begins_with("gunshot"):
			boost = GUN_BOOST
		play_at(self, options[_step % options.size()], s["pos"], volume_for(s["loudness"]) + boost, randf_range(0.92, 1.08))
	_heard = now.duplicate()


func _play_new_shots() -> void:
	var now: Array = sim.defense.recent_shots
	for s: Dictionary in now:
		if not _seen(_shots, s):
			play_at(self, "turret_shot", s["from"], volume_for(float(sim.data.buildables["nail_turret"]["loudness"])) + 6.0,
					randf_range(0.95, 1.05))
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
