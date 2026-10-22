class_name NetSync
extends RefCounted
## Co-op B (docs/COOP_PLAN.md: Kid walks into Dad's world): what goes over the house network between the host's
## SimWorld and a joiner's copy, as plain dictionaries (headless-tested; NetSession carries them). The host sends a
## joiner one `snapshot` (the save dictionary, exactly what a load uses) and then `refresh`es: the clock, every player,
## every zombie, belts and machines, the cars, the pieces that changed since the last refresh (added, removed, opened
## or closed, damaged), containers newly searched, and the supply lists when they change. `apply_refresh` lays one
## onto a joiner's sim, which never steps (`paused`): the drawing code reads the copy as if it were the real thing.
## The joiner's own position isn't overwritten: that machine owns it and sends it up (`player_state` ->
## `apply_player_state`; the host trusts it).

const HP_SWEEP := 1.0  # seconds between looks for pieces whose hp changed (damage has no signal)

var sim: SimWorld
var _ops: Array = []  # piece changes since the last refresh: ["add"|"change", key, piece] or ["remove", key]
var _hp: Dictionary = {}  # piece key -> hp as the joiners last had it
var _hp_timer := 0.0
var _searched: Dictionary = {}  # container ids the joiners know are searched
var _supplies_sent := -1


## Made on the host once the world is built (a load's restores aren't changes).
func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	sim.build.piece_added.connect(func(key: String) -> void:
		if sim.build.pieces.has(key):
			_ops.append(["add", key, sim.build.pieces[key].duplicate(true)])
			_hp[key] = int(sim.build.pieces[key]["hp"]))
	sim.build.piece_removed.connect(func(key: String, _piece: Dictionary) -> void:
		_ops.append(["remove", key])
		_hp.erase(key))
	sim.build.piece_changed.connect(func(key: String) -> void:
		if sim.build.pieces.has(key):
			_ops.append(["change", key, sim.build.pieces[key].duplicate(true)]))
	for key: String in sim.build.pieces:
		_hp[key] = int(sim.build.pieces[key]["hp"])
	for id: String in sim.loot.containers:
		if sim.loot.containers[id]["searched"]:
			_searched[id] = true
	_supplies_sent = sim.supplies.changes


## The whole world for a joiner who's just arrived: the save, which main.gd loads as it loads any save.
static func snapshot(p_sim: SimWorld) -> Dictionary:
	return SaveGame.to_dict(p_sim)


## One refresh for the joiners, `dt` seconds after the last.
func refresh(dt: float) -> Dictionary:
	var d := {"clock": [sim.clock.time_of_day, sim.clock.day], "players": [], "zombies": [], "belts": [], "machines": [],
			"cars": []}
	for s: PlayerSlot in sim.players:
		var p := s.stats
		d["players"].append({"name": s.name, "pos": s.pos, "facing": s.facing, "lit": s.lit, "sneaking": s.sneaking,
				"health": p.health, "food": p.food, "water": p.water, "energy": p.energy, "stamina": p.stamina,
				"bleeding": p.bleeding, "dead": p.dead, "asleep": p.asleep, "warmth": p.warmth})
	for id: int in sim.horde.zombies:
		var z: ZombieBrain = sim.horde.zombies[id]
		d["zombies"].append([id, z.type, z.pos, z.facing, z.state, z.hp, z.screaming, z.dead_time, z.searched])
	for cell: Vector2i in sim.factory.belts:
		d["belts"].append([cell, sim.factory.belts[cell].items.duplicate(true)])
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		d["machines"].append([cell, m.progress, m.crafting, m.muffled, m.boxed, m.input.duplicate(), m.output.duplicate(),
				m.recipe_id])
	for id: String in sim.vehicles.cars:
		var c: Dictionary = sim.vehicles.cars[id]
		d["cars"].append([id, c["pos"], c["yaw"], c["speed"], c["running"], c.get("hp", 0)])
	if not _ops.is_empty():
		d["pieces"] = _ops
		_ops = []
	_hp_timer += dt
	if _hp_timer >= HP_SWEEP:
		_hp_timer = 0.0
		var hp := []
		for key: String in sim.build.pieces:
			var now := int(sim.build.pieces[key]["hp"])
			if _hp.has(key) and int(_hp[key]) != now:
				hp.append([key, now])
			_hp[key] = now
		if not hp.is_empty():
			d["hp"] = hp
	var searched := []
	for id: String in sim.loot.containers:
		if sim.loot.containers[id]["searched"] and not _searched.has(id):
			_searched[id] = true
			searched.append(id)
	if not searched.is_empty():
		d["searched"] = searched
	if sim.supplies.changes != _supplies_sent:
		_supplies_sent = sim.supplies.changes
		d["supplies"] = sim.supplies.to_dict()
	return d


## Lays a refresh onto a joiner's copy. `local` is the slot this machine owns (its position isn't touched).
static func apply_refresh(p_sim: SimWorld, d: Dictionary, local: int) -> void:
	var clock: Array = d.get("clock", [])
	if clock.size() == 2:
		p_sim.clock.time_of_day = float(clock[0])
		if p_sim.clock.day != int(clock[1]):
			p_sim.clock.day = int(clock[1])
		p_sim._day = p_sim.clock.day
	var roster: Array = d.get("players", [])
	for i in roster.size():
		var pd: Dictionary = roster[i]
		if i >= p_sim.players.size():
			p_sim.add_player(str(pd["name"]))
		var s: PlayerSlot = p_sim.players[i]
		s.name = str(pd["name"])
		if i != local:
			s.pos = pd["pos"]
			s.facing = pd["facing"]
			s.lit = bool(pd["lit"])
			s.sneaking = bool(pd["sneaking"])
		var p := s.stats
		p.health = float(pd["health"])
		p.food = float(pd["food"])
		p.water = float(pd["water"])
		p.energy = float(pd["energy"])
		p.stamina = float(pd["stamina"])
		p.bleeding = pd["bleeding"]
		p.dead = bool(pd["dead"])
		p.asleep = bool(pd["asleep"])
		p.warmth = float(pd["warmth"])
	if d.has("zombies"):
		var seen := {}
		for e: Array in d["zombies"]:
			var id := int(e[0])
			seen[id] = true
			var z: ZombieBrain = p_sim.horde.zombies.get(id)
			if z == null:
				if not p_sim.data.zombies.has(str(e[1])):
					continue
				z = p_sim.horde.restore(id, str(e[1]), e[2])
			z.pos = e[2]
			z.facing = e[3]
			z.state = int(e[4])
			z.hp = float(e[5])
			z.screaming = float(e[6])
			z.dead_time = float(e[7])
			z.searched = bool(e[8])
		for id: int in p_sim.horde.zombies.keys():
			if not seen.has(id):
				p_sim.horde.zombies.erase(id)
	for b: Array in d.get("belts", []):
		var belt: Factory.Belt = p_sim.factory.belts.get(b[0])
		if belt != null:
			belt.items = b[1]
	for m: Array in d.get("machines", []):
		var mach: Factory.Machine = p_sim.factory.machines.get(m[0])
		if mach == null:
			continue
		mach.progress = float(m[1])
		mach.crafting = bool(m[2])
		mach.muffled = bool(m[3])
		mach.boxed = bool(m[4])
		mach.input = m[5]
		mach.output = m[6]
		if str(m[7]) != mach.recipe_id and p_sim.data.recipes.has(str(m[7])):
			p_sim.factory.set_recipe(mach, str(m[7]))
	for c: Array in d.get("cars", []):
		var car: Dictionary = p_sim.vehicles.cars.get(str(c[0]), {})
		if car.is_empty():
			continue
		car["pos"] = c[1]
		car["yaw"] = float(c[2])
		car["speed"] = float(c[3])
		car["running"] = bool(c[4])
		if car.has("hp"):
			car["hp"] = c[5]
	for op: Array in d.get("pieces", []):
		var key := str(op[1])
		match str(op[0]):
			"add":
				if not p_sim.build.pieces.has(key):
					p_sim.build.restore(key, op[2])
			"change":
				if p_sim.build.pieces.has(key):
					var piece: Dictionary = p_sim.build.pieces[key]
					for k: String in op[2]:
						piece[k] = op[2][k]
					p_sim.build.piece_changed.emit(key)
			"remove":
				if p_sim.build.pieces.has(key):
					p_sim.build.destroy(key)
	for h: Array in d.get("hp", []):
		var key := str(h[0])
		if p_sim.build.pieces.has(key):
			p_sim.build.pieces[key]["hp"] = int(h[1])
			p_sim.build.piece_changed.emit(key)
	for id: String in d.get("searched", []):
		if p_sim.loot.containers.has(id):
			p_sim.loot.containers[id]["searched"] = true
	if d.has("supplies"):
		p_sim.supplies.from_dict(d["supplies"])
		p_sim.register_supplies()


## What a joiner sends up about itself (STATE_HZ a second): where it stands, where it looks, its light, its sneaking.
static func player_state(p_sim: SimWorld, i: int) -> Array:
	var s: PlayerSlot = p_sim.players[i]
	return [s.pos, s.facing, s.lit, s.sneaking]


## The host takes a joiner's word for where it is.
static func apply_player_state(p_sim: SimWorld, i: int, pos: Vector3, facing: Vector3, lit: bool, sneaking: bool) -> void:
	if i <= 0 or i >= p_sim.players.size() or not pos.is_finite() or not facing.is_finite():
		return
	var s: PlayerSlot = p_sim.players[i]
	s.pos = pos
	s.facing = facing
	s.lit = lit
	s.sneaking = sneaking
