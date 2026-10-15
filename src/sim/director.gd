class_name Director
extends RefCounted
## Keeps a "heat" score for how much noise your base is leaking. Loud machines heard 50 m out
## (through any gap in your walls) push it up, faster at night; it cools when things are quiet.
## Every check_every seconds it may send zombies in from a road end, walking toward the loudest
## machine: wanderers once heat passes wanderers_at, and at night groups (group_at) or a horde (horde_at).
## Sending a wave spends heat. Numbers live in data/noise.json "director".
## W1b: wanderers still come from any of the four EDGES straight at the noise, but groups and hordes come
## from the north or south end of the road (EDGES 0 and 1) and walk down the road first: to the road point
## nearest the noise, then they turn toward it (ZombieBrain.hear_via with road_route()).

## M17a: the north road end is past the industrial park's north fence (ParkPlan.ROAD_NORTH_Z), so a wave from
## the north walks the park road south first, comes round the factory hall's west side (NORTH_VIA), and then
## down the town road. ROAD_LINE is that whole way, north end first.
const EDGES := [Vector3(0, 0, -266), Vector3(0, 0, 35), Vector3(-40, 0, -60), Vector3(40, 0, -60)]
const EDGE_NAMES := ["north", "south", "west", "east"]
const ROAD_X := 0.0
const ROAD_NORTH_Z := -258.0  # M17a: the north end of the park road (was -106, the town road's north end)
const TOWN_NORTH_Z := -106.0  # the north end of the town road, in front of the factory's south doorway
const PARK_SOUTH_Z := -142.0  # where the park road meets the way round the hall, by its north doorway
const ROAD_SOUTH_Z := 10.0    # the south end of the asphalt
## Round the factory hall's west side, from the park road to the town road.
const NORTH_VIA := [Vector3(-25, 0, -142), Vector3(-25, 0, -106)]
const ROAD_LINE := [Vector3(0, 0, -258), Vector3(0, 0, -142), Vector3(-25, 0, -142), Vector3(-25, 0, -106),
		Vector3(0, 0, -106), Vector3(0, 0, 10)]
const ROAD_LEG := 40.0        # longest stretch between road waypoints (each leg gets lure_time to walk)

var cfg: Dictionary
var heat := 0.0
## Permanent: every bit of noise you've made that the dead could hear. It never cools off, and as it
## climbs new kinds of zombie join the waves (data/noise.json "infamy").
var infamy := 0.0
var data: GameData
var difficulty: Difficulty
var unlocked: Array = []  # zombie types infamy has let in so far
var newly_unlocked: Dictionary = {}  # the unlock that happened this tick ({} if none), for a message
var gain := 0.0  # heat per second from noise right now (before cooling)
var _check: float
var _gain_timer := 0.0
var _rng := RandomNumberGenerator.new()
## M15 (from docs/perf/stress-2026-10-13.md): each continuous source's outdoor wall count, by where it stands.
## Machines don't move, so this only changes when the build grid does (a piece added, removed, opened or
## broken); watch() clears it then. Sources that move (cars) just get a new entry; entries no source used in
## the last pass are dropped. `recounts` counts the 8-direction walks actually done (tests, the stress report).
var _walls_cache: Dictionary = {}
var recounts := 0
## V29: the scripted first-night beats. Saved so loading around dusk cannot repeat them.
var first_night_warning_sent := false
var first_night_wave_sent := false
var first_morning_sent := false
var first_night_sheltered := false
var first_night_ids: Array[int] = []
var first_night_deaths := 0


func _init(p_data: GameData, seed_value: int = 1, p_difficulty: Difficulty = null) -> void:
	data = p_data
	difficulty = p_difficulty
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
	_add_infamy(dt, noise)
	_check -= dt
	if _check > 0.0:
		return {}
	_check = float(cfg["check_every"])
	var kind := wave_kind(night)
	if kind == "" or noise.continuous.is_empty():
		return {}
	var count_rule := "night_wave_size" if night and kind != "wanderers" else "zombie_count"
	var wanted := difficulty.count(count_rule, int(cfg[kind]), 1) if difficulty != null else int(cfg[kind])
	var size := mini(wanted, int(cfg["max_alive"]) - horde.alive_count())
	if size <= 0:
		return {}
	var lure := _loudest(noise)
	var by_road := kind != "wanderers"
	var e := _rng.randi_range(0, 1) if by_road else _rng.randi_range(0, EDGES.size() - 1)
	var route := road_route(EDGE_NAMES[e], lure["pos"]) if by_road else []
	var type_counts := {}
	var live_counts := {}
	for living: ZombieBrain in horde.zombies.values():
		if not living.is_dead():
			live_counts[living.type] = int(live_counts.get(living.type, 0)) + 1
	for i in size:
		var spot: Vector3 = EDGES[e] + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
		var type := pick_type(night, type_counts, kind, live_counts)
		type_counts[type] = int(type_counts.get(type, 0)) + 1
		live_counts[type] = int(live_counts.get(type, 0)) + 1
		var z := horde.spawn(type, spot)
		var first: Vector3 = route[0] if not route.is_empty() else lure["pos"]
		z.facing = (first - spot).normalized()
		z.hear_via(route, lure["pos"], lure["key"], float(cfg["lure_time"]))
	heat = maxf(0.0, heat - size * float(cfg["heat_per_zombie"]))
	return {"size": size, "edge": EDGE_NAMES[e], "kind": kind, "route": route, "types": type_counts}


## The waypoints a wave from the `edge` road end ("north" or "south") walks before turning toward
## `lure`: along ROAD_LINE from that end (in legs of at most ROAD_LEG) to the point on it nearest the lure.
## M17a: from the north that's the park road, round the factory hall's west side, then the town road.
static func road_route(edge: String, lure: Vector3) -> Array:
	var line: Array = ROAD_LINE.duplicate()
	if edge != "north":
		line.reverse()
	var at := Vector2(lure.x, lure.z)
	var best_seg := 0
	var best_point := Vector2.ZERO
	var best_d := INF
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(at, a, b)
		if at.distance_to(q) < best_d - 1e-6:
			best_d = at.distance_to(q)
			best_seg = i
			best_point = q
	var points: Array = [line[0]]
	for i in best_seg + 1:
		var from: Vector3 = line[i]
		var to: Vector3 = line[i + 1] if i < best_seg else Vector3(best_point.x, 0, best_point.y)
		var legs := maxi(1, ceili(from.distance_to(to) / ROAD_LEG))
		for k in range(1, legs + 1):
			points.append(from.lerp(to, float(k) / legs))
	var out: Array = []
	for p: Vector3 in points:  # drop points on top of the one before
		if out.is_empty() or p.distance_to(out.back()) > 3.0:
			out.append(p)
	return out


## Heat per second from the machines running now: each adds gain_rate per dB it's heard over
## gain_floor at listen_distance, x night_multiplier after dark.
func gain_now(noise: NoiseField, night: bool) -> float:
	var g := 0.0
	var dist := float(cfg["listen_distance"])
	var used := {}
	for s: Dictionary in noise.continuous:
		var at: Vector3 = s["pos"]
		var walls: int
		if _walls_cache.has(at):
			walls = _walls_cache[at]
		else:
			walls = noise.outdoor_walls(at, dist)
			recounts += 1
		used[at] = walls
		g += maxf(0.0, noise.level(s["loudness"], dist, walls) - float(cfg["gain_floor"])) * float(cfg["gain_rate"])
	_walls_cache = used
	var total := g * (float(cfg["night_multiplier"]) if night else 1.0)
	return difficulty.scale("director_heat_gain", total) if difficulty != null else total


## V29: fixed day-one beats, independent of heat and machine noise. Returns events for the HUD/log.
## A sheltered wave approaches the outside of the room, investigates briefly, then mills around. A new
## player-made sound changes those same zombies into hunters.
func first_night_events(clock: GameClock, player_pos: Vector3, sheltered: bool, player_noisy: bool,
		deaths: int, horde: Horde) -> Array:
	var events := []
	if clock.day == 1 and clock.time_of_day >= 19.0 and not first_night_warning_sent:
		first_night_warning_sent = true
		events.append({"kind": "warning"})
	if clock.day == 1 and clock.time_of_day >= 21.0 and not first_night_wave_sent:
		first_night_wave_sent = true
		first_night_deaths = deaths
		first_night_sheltered = sheltered and not player_noisy
		var wave := _send_first_night(player_pos, first_night_sheltered, horde)
		events.append({"kind": "night", "wave": wave})
	if first_night_wave_sent and first_night_sheltered and player_noisy:
		first_night_sheltered = false
		for id: int in first_night_ids:
			var z: ZombieBrain = horde.zombies.get(id)
			if z != null and not z.is_dead():
				z.hunt(player_pos)
	if first_night_wave_sent and not first_morning_sent and clock.day > 1 and clock.time_of_day >= 6.0:
		first_morning_sent = true
		if deaths == first_night_deaths:
			events.append({"kind": "morning"})
	return events


func _send_first_night(player_pos: Vector3, sheltered: bool, horde: Horde) -> Dictionary:
	var wanted := difficulty.first_night_size() if difficulty != null else 5
	# This beat is guaranteed even when the map's starting population has reached the heat-wave cap.
	var size := wanted
	var runners := mini(size, difficulty.first_night_runners() if difficulty != null else 0)
	first_night_ids.clear()
	for i in size:
		var angle := TAU * float(i) / maxf(1.0, float(size)) + _rng.randf_range(-0.18, 0.18)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var spot := player_pos + outward * _rng.randf_range(18.0, 22.0)
		var type := "runner" if i < runners else "shambler"
		var z := horde.spawn(type, spot)
		first_night_ids.append(z.id)
		z.facing = -outward
		if sheltered:
			z.hear(player_pos + outward * _rng.randf_range(7.0, 10.0), "", 14.0)
		else:
			z.hunt(player_pos)
	return {"size": size, "kind": "first_night", "runners": runners, "sheltered": sheltered}


func first_night_state() -> Dictionary:
	return {"warning": first_night_warning_sent, "wave": first_night_wave_sent,
			"morning": first_morning_sent, "sheltered": first_night_sheltered,
			"ids": first_night_ids.duplicate(), "deaths": first_night_deaths}


func load_first_night_state(saved: Dictionary, clock: GameClock, legacy: bool) -> void:
	if legacy:
		first_night_warning_sent = clock.day > 1 or clock.time_of_day >= 19.0
		first_night_wave_sent = clock.day > 1 or clock.time_of_day >= 21.0
		first_morning_sent = clock.day > 1 or clock.time_of_day >= 21.0
		first_night_sheltered = false
		first_night_ids.clear()
		first_night_deaths = 0
		return
	first_night_warning_sent = bool(saved.get("warning", false))
	first_night_wave_sent = bool(saved.get("wave", false))
	first_morning_sent = bool(saved.get("morning", false))
	first_night_sheltered = bool(saved.get("sheltered", false))
	first_night_ids.clear()
	for id: Variant in saved.get("ids", []):
		first_night_ids.append(int(id))
	first_night_deaths = int(saved.get("deaths", 0))


## M15: forget the cached wall counts whenever the build grid changes.
func watch(build: BuildGrid) -> void:
	build.piece_added.connect(_on_grid_added)
	build.piece_removed.connect(_on_grid_removed)
	build.piece_changed.connect(_on_grid_added)


func _on_grid_added(_key: String) -> void:
	_walls_cache.clear()


func _on_grid_removed(_key: String, _piece: Dictionary) -> void:
	_walls_cache.clear()


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


## Infamy grows with the heat your machines make (before it cools) and with loud one-offs you make
## (horn, gunfire, crashes); zombies' own bangs and screams don't count.
func _add_infamy(dt: float, noise: NoiseField) -> void:
	var inf: Dictionary = data.noise["infamy"]
	infamy += gain * dt
	for s: Dictionary in noise.recent:
		if s["age"] == 0.0 and not (s["kind"] in inf["ignore"]):
			infamy += maxf(0.0, float(s["loudness"]) - float(inf["one_off_floor"])) * float(inf["one_off_rate"])
	newly_unlocked = {}
	for u: Dictionary in inf["unlocks"]:
		if infamy >= float(u["at"]) and not unlocked.has(u["type"]):
			unlocked.append(u["type"])
			newly_unlocked = u


## Which kind of zombie the next one in a wave is: mostly shamblers, the day-one starting mix, and whatever
## infamy has unlocked. V28 night_only and per-wave caps keep early brute groups from becoming brute walls.
func pick_type(night: bool = false, wave_counts: Dictionary = {}, wave_kind_name: String = "",
		live_counts: Dictionary = {}) -> String:
	for u: Dictionary in data.noise["infamy"]["unlocks"]:
		if not unlocked.has(u["type"]) or (bool(u.get("night_only", false)) and not night):
			continue
		var limit := int(u.get("max_per_wave", 0))
		if wave_kind_name == "horde":
			limit = int(u.get("max_per_horde", limit))
		if limit > 0 and int(wave_counts.get(u["type"], 0)) >= limit:
			continue
		var live_limit := int(u.get("max_alive", 0))
		if live_limit > 0 and int(live_counts.get(u["type"], 0)) >= live_limit:
			continue
		if _rng.randf() < float(u["chance"]):
			return u["type"]
	for entry: Dictionary in data.noise["infamy"].get("starting", []):
		if _rng.randf() < float(entry["chance"]):
			return entry["type"]
	return "shambler"
