class_name Director
extends RefCounted
## Keeps a "heat" score for how much noise your base is leaking. Loud machines heard 50 m out
## (through any gap in your walls) push it up, faster at night; it cools when things are quiet.
## Every check_every seconds it may send zombies in from a road end, walking toward the loudest
## machine: wanderers once heat passes wanderers_at, and at night groups (group_at) or a horde (horde_at).
## Sending a wave spends heat. Numbers live in data/noise.json "director".

const EDGES := [Vector3(-25, 0, -145), Vector3(0, 0, 35), Vector3(-40, 0, -60), Vector3(40, 0, -60)]
const EDGE_NAMES := ["north", "south", "west", "east"]

var cfg: Dictionary
var heat := 0.0
var gain := 0.0  # heat per second from noise right now (before cooling)
var _check: float
var _gain_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_data: GameData, seed_value: int = 1) -> void:
	cfg = p_data.noise["director"]
	_check = float(cfg["check_every"])
	_rng.seed = hash([seed_value, "director"])


func level_name() -> String:
	if heat >= float(cfg["horde_at"]):
		return "horde"
	if heat >= float(cfg["group_at"]):
		return "group"
	if heat >= float(cfg["wanderers_at"]):
		return "noticed"
	return "calm"


## One sim tick. Returns {} or the wave it sent: {size, edge, kind}.
func tick(dt: float, noise: NoiseField, night: bool, horde: Horde) -> Dictionary:
	_gain_timer -= dt
	if _gain_timer <= 0.0:
		_gain_timer = 1.0  # the 8-direction wall count is costly; once a second is plenty
		gain = gain_now(noise, night)
	heat = clampf(heat + (gain - float(cfg["decay"])) * dt, 0.0, float(cfg["max_heat"]))
	_check -= dt
	if _check > 0.0:
		return {}
	_check = float(cfg["check_every"])
	var kind := wave_kind(night)
	if kind == "" or noise.continuous.is_empty():
		return {}
	var size := mini(int(cfg[kind]), int(cfg["max_alive"]) - horde.alive_count())
	if size <= 0:
		return {}
	var lure := _loudest(noise)
	var e := _rng.randi_range(0, EDGES.size() - 1)
	for i in size:
		var spot: Vector3 = EDGES[e] + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
		var z := horde.spawn("shambler", spot)
		z.facing = (lure["pos"] - spot).normalized()
		z.hear(lure["pos"], lure["key"], float(cfg["lure_time"]))
	heat = maxf(0.0, heat - size * float(cfg["heat_per_zombie"]))
	return {"size": size, "edge": EDGE_NAMES[e], "kind": kind}


## Heat per second from the machines running now: each adds gain_rate per dB it's heard over
## gain_floor at listen_distance, x night_multiplier after dark.
func gain_now(noise: NoiseField, night: bool) -> float:
	var g := 0.0
	for s: Dictionary in noise.continuous:
		g += maxf(0.0, noise.outdoor_level(s, float(cfg["listen_distance"])) - float(cfg["gain_floor"])) * float(cfg["gain_rate"])
	return g * (float(cfg["night_multiplier"]) if night else 1.0)


## "wanderers" by day or night; "group" and "horde" only at night.
func wave_kind(night: bool) -> String:
	if night and heat >= float(cfg["horde_at"]):
		return "horde"
	if night and heat >= float(cfg["group_at"]):
		return "group"
	if heat >= float(cfg["wanderers_at"]):
		return "wanderers"
	return ""


func _loudest(noise: NoiseField) -> Dictionary:
	var best: Dictionary = noise.continuous[0]
	for s: Dictionary in noise.continuous:
		if s["loudness"] > best["loudness"]:
			best = s
	return best
