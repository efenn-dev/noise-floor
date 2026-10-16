class_name PowerGrid
extends RefCounted
## Electricity. Generators (burn fuel, loud), solar panels (silent, daylight only) and power poles form
## networks with the machines that need power:
##   * a power pole links to anything within its reach (12 m), including other poles
##   * other powered things link to each other within DEVICE_REACH (next-door cells)
## Each network adds up supply and demand every tick. If demand is more than supply, it browns out:
## every machine on it stops. Solar is used first (it's free); generators cover the rest and burn fuel
## in proportion to that load. An idle generator burns nothing and makes no noise.
## Machines that draw no watts (rain collector, planter) don't need power at all.

const DEVICE_REACH := 3.0
const MAX_CANS := 10

var data: GameData
## Set by SimWorld (M12): Dampened Gears makes generators quieter.
var skills: Skills
var build: BuildGrid
var factory: Factory
## Debug/tests: every machine is powered.
var free := false
## Generators: piece key -> {cans: int, fuel: float (seconds of full load left in the open can),
##   running: bool, load: float 0..1, muffled: bool, boxed: bool (F5: a sound box over the muffler)}
var generators: Dictionary = {}
## Networks after the last tick: [{keys: Array, supply: float, demand: float, brownout: bool}]
var networks: Array = []
## Every connection, for drawing wires: [[key_a, key_b], ...]
var links: Array = []
var _network_of: Dictionary = {}  # piece key -> index into networks
## M15: pieces a sensor's quiet mode has switched off (machines and generators): key -> true. Set by Automation.
var switched_off: Dictionary = {}
## M15: whether a powered piece that isn't a machine (turret, floodlight, noisemaker, fence, repair station)
## wants power this tick: key -> bool (missing = true). Set by Defense and Automation.
var wants: Dictionary = {}
var _on: Dictionary = {}  # key -> it has power this tick (see is_powered)
## M17a: loads that aren't build pieces (the water tower's pump): id -> {pos: Vector3, watts: float, on: bool}.
## One joins the network of the nearest powered piece that reaches it (a pole within its reach, anything else
## within DEVICE_REACH + EXTERNAL_SIZE). It runs only if that network has its watts spare after everything
## else; then it counts in the demand, so generators run and burn for it. Set `on` to say it wants power.
const EXTERNAL_SIZE := 3.0  # half the tower's footprint: a pole by any leg counts
var external: Dictionary = {}
var external_on: Dictionary = {}     # id -> powered this tick
var external_spare: Dictionary = {}  # id -> spare watts on its network before it (-1 = on no network)
var _dirty := true
var _refunds: Dictionary = {}  # key -> full cans left in a generator that was just removed


func _init(p_data: GameData, p_build: BuildGrid, p_factory: Factory) -> void:
	data = p_data
	build = p_build
	factory = p_factory
	build.piece_added.connect(_on_added)
	build.piece_removed.connect(_on_removed)


## Is this piece part of the electric world (makes, carries or needs power)?
func is_node(key: String) -> bool:
	if not build.pieces.has(key):
		return false
	var b: Dictionary = data.buildables[build.pieces[key]["id"]]
	return b["kind"] in ["generator", "solar", "pole", "sensor"] or b["watts"] > 0.0  # M15: sensors join a network to know it


## M15: does this powered piece (not a machine) have power this tick? For one that wants power: its network
## isn't browned out. For one that doesn't want any right now: its network has room for it.
func is_powered(key: String) -> bool:
	return free or _on.get(key, false)


func network_of(key: String) -> Dictionary:
	return networks[_network_of[key]] if _network_of.has(key) else {}


## Loads fuel into a generator from `inv`, up to MAX_CANS. Returns how many went in.
func load_fuel(key: String, inv: Inventory) -> int:
	if not generators.has(key):
		return 0
	var g: Dictionary = generators[key]
	var fuel: String = data.buildables[build.pieces[key]["id"]]["fuel"]
	var n := mini(inv.count(fuel), MAX_CANS - g["cans"])
	if n > 0 and inv.remove(fuel, n):
		g["cans"] += n
		return n
	return 0


## Fuel left in a generator, in seconds at full load.
func fuel_seconds(key: String) -> float:
	var g: Dictionary = generators[key]
	return g["fuel"] + g["cans"] * data.buildables[build.pieces[key]["id"]]["burn_time"]


## Rebuilds the networks now if building changed since the last tick (the world calls this to draw wires).
func refresh() -> void:
	if _dirty:
		_rebuild()


func tick(dt: float, daylight: float) -> void:
	refresh()
	for cell: Vector2i in factory.machines:
		var m: Factory.Machine = factory.machines[cell]
		m.powered = free or m.watts <= 0.0  # networked machines get set below
	for g: Dictionary in generators.values():
		g["running"] = false
		g["load"] = 0.0
	_on = {}
	external_on = {}
	external_spare = {}
	var ext_net := {}  # network index -> [external ids]
	for id: String in external:
		var ni := _network_reaching(external[id]["pos"])
		external_spare[id] = -1.0
		if ni >= 0:
			if not ext_net.has(ni):
				ext_net[ni] = []
			ext_net[ni].append(id)
	for ni in networks.size():
		var net: Dictionary = networks[ni]
		var solar := 0.0
		var gen_capacity := 0.0
		var gens := []
		var machines := []
		var others := []  # M15: turrets, floodlights, noisemakers, fences, repair stations
		var demand := 0.0
		for key: String in net["keys"]:
			var b: Dictionary = data.buildables[build.pieces[key]["id"]]
			match b["kind"]:
				"solar":
					solar += b["watts_out"] * daylight
				"generator":
					if fuel_seconds(key) > 0.0 and not switched_off.has(key):
						gen_capacity += b["watts_out"]
						gens.append(key)
				"machine":
					var m: Factory.Machine = factory.machines.get(build.pieces[key]["cell"])
					if m != null and m.watts > 0.0 and not switched_off.has(key):
						machines.append(m)
						if m.wants_power():
							demand += m.watts
					elif m != null and m.watts > 0.0:
						m.powered = false  # quiet mode
				_:
					if b["watts"] > 0.0:
						others.append(key)
						if wants.get(key, true):
							demand += b["watts"]
		for id: String in ext_net.get(ni, []):
			var spare := solar + gen_capacity - demand
			external_spare[id] = spare
			if external[id]["on"] and spare + 1e-6 >= float(external[id]["watts"]):
				demand += float(external[id]["watts"])
				external_on[id] = true
		net["supply"] = solar + gen_capacity
		net["demand"] = demand
		net["brownout"] = demand > net["supply"] + 1e-6
		for m: Factory.Machine in machines:
			m.powered = free or not net["brownout"]
		for key: String in others:
			var w: float = data.buildables[build.pieces[key]["id"]]["watts"]
			_on[key] = not net["brownout"] if wants.get(key, true) else net["supply"] + 1e-6 >= demand + w
		if net["brownout"] or gen_capacity <= 0.0:
			continue
		var load := maxf(0.0, demand - solar) / gen_capacity  # solar first, generators cover the rest
		if load <= 0.0:
			continue
		for key: String in gens:
			var g: Dictionary = generators[key]
			g["running"] = true
			g["load"] = load
			g["fuel"] -= dt * load
			while g["fuel"] <= 0.0 and g["cans"] > 0:
				g["cans"] -= 1
				g["fuel"] += data.buildables[build.pieces[key]["id"]]["burn_time"]
			g["fuel"] = maxf(0.0, g["fuel"])


## Running generators, as noise sources: {pos, loudness, key, kind}.
func noise_sources() -> Array:
	var out := []
	var quiet := skills.bonus("machine_quiet") if skills != null else 0.0  # Dampened Gears (once, not per generator)
	for key: String in generators:
		var g: Dictionary = generators[key]
		if g["running"]:
			var id: String = build.pieces[key]["id"]
			var cut := (float(data.noise["muffler"]["cut"]) if g["muffled"] else 0.0) \
					+ (float(data.noise["sound_box"]["cut"]) if g.get("boxed", false) else 0.0)  # F5: the sound box
			out.append({"pos": build.piece_center(key), "loudness": maxf(0.0, data.buildables[id]["loudness"] - cut - quiet),
					"key": key, "kind": id})
	return out


## Full gas cans that were in generator `key` when it was removed (once).
func take_refund(key: String) -> int:
	var n: int = _refunds.get(key, 0)
	_refunds.erase(key)
	return n


func _on_added(key: String) -> void:
	if build.kind_of(build.pieces[key]["id"]) == "generator":
		generators[key] = {"cans": 0, "fuel": 0.0, "running": false, "load": 0.0, "muffled": false, "boxed": false}
	_dirty = true


func _on_removed(key: String, _piece: Dictionary) -> void:
	if generators.has(key):
		_refunds[key] = generators[key]["cans"]
	generators.erase(key)
	_dirty = true


## Groups the powered pieces into networks (union-find over every pair in reach).
func _rebuild() -> void:
	_dirty = false
	var keys := []
	for key: String in build.pieces:
		if is_node(key):
			keys.append(key)
	keys.sort()
	var parent := {}
	links = []
	for k: String in keys:
		parent[k] = k
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			var reach := maxf(_reach(a), _reach(b))
			var pa := build.piece_center(a)
			var pb := build.piece_center(b)
			if Vector2(pa.x - pb.x, pa.z - pb.z).length() <= reach + 1e-3:
				parent[_find(parent, a)] = _find(parent, b)
				links.append([a, b])
	var index := {}
	networks = []
	_network_of = {}
	for k: String in keys:
		var root := _find(parent, k)
		if not index.has(root):
			index[root] = networks.size()
			networks.append({"keys": [], "supply": 0.0, "demand": 0.0, "brownout": false})
		networks[index[root]]["keys"].append(k)
		_network_of[k] = index[root]


## M17a: the network (index) of the nearest powered piece that reaches `pos`, or -1.
func _network_reaching(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for key: String in _network_of:
		var c := build.piece_center(key)
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		var b: Dictionary = data.buildables[build.pieces[key]["id"]]
		var reach: float = b["reach"] if b["kind"] == "pole" else DEVICE_REACH + EXTERNAL_SIZE
		if d <= reach + 1e-3 and d < best_d:
			best_d = d
			best = _network_of[key]
	return best


func _reach(key: String) -> float:
	var b: Dictionary = data.buildables[build.pieces[key]["id"]]
	return b["reach"] if b["kind"] == "pole" else DEVICE_REACH


static func _find(parent: Dictionary, k: String) -> String:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k
