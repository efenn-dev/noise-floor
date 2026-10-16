class_name Factory
extends RefCounted
## Machines and belts, stepped on the sim tick. Everything sits on the 2 m build grid.
## A machine takes items in at its back (input port) and pushes products out of its front (output port).
## A belt carries items toward its front and hands them to whatever is ahead: another belt
## (entering from its back or a side, so belts can turn) or a machine's input port.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # N, E, S, W
## Belt speed in cells per second (1 cell = 2 m). Items keep SPACING (in cells) between them.
const BELT_SPEED := 1.0
const SPACING := 0.25
const INPUT_CAP := 20   # per input item
const OUTPUT_CAP := 50  # per output item
const ROUTER_CAP := 2   # F3: items a splitter or merger holds while its outputs are blocked
const STORAGE_FROM_BELT_CAP := 500  # F3: a crate fed by a belt stops taking at this many items
## A planter's crop: Farming adds planter_extra of these per harvest grown (M12).
const CROP := "vegetable"
## F6 (compact and deep): a machine fed straight from the machine behind it (no belt between) works this much faster,
## for CHAIN_HOLD seconds after each hand-over, so a tight layout beats a sprawling one.
const CHAIN_BONUS := 0.15
const CHAIN_HOLD := 10.0


class Machine:
	extends RefCounted
	var id: String
	var cell: Vector2i
	var facing: int
	var recipe: Dictionary  # {name, time, in, out}
	var recipe_id := ""     # M13: which one, for machines with a choice (the Press: nails or repair kits)
	var input: Dictionary = {}
	var output: Dictionary = {}
	var progress := 0.0  # seconds into the current craft
	var crafting := false
	var crafted := 0     # crafts finished, ever
	var muffled := false
	var boxed := false     # F5: a sound box over the muffler (the second tier)
	var time_scale := 1.0  # a muffler slows the machine down
	var watts := 0.0       # power it draws while working (0 = needs no power)
	var powered := true    # set by PowerGrid each tick; an unpowered machine does nothing
	var frozen := false    # M16: a planter in winter: its timer pauses (set by Factory.tick)
	var node_rate := 1.0   # F1: an extractor works its resource node this many times its recipe's speed (purity)
	var chained := 0.0     # F6: seconds left of the chain bonus (fed straight from the machine behind it)

	## Would draw power this tick: working, or able to start.
	func wants_power() -> bool:
		return crafting or _can_start()

	func craft_time() -> float:
		return recipe["time"] * time_scale / maxf(node_rate, 0.01) / (1.0 + CHAIN_BONUS if chained > 0.0 else 1.0)

	func accepts(item: String) -> bool:
		return recipe["in"].has(item) and input.get(item, 0) < INPUT_CAP

	func status() -> String:
		if frozen and id == "water_tap":
			return "Dry: the water tower isn't running"
		if frozen:
			return "Frozen: nothing grows in winter"
		if not powered:
			return "no power"
		if crafting:
			return "working %d%%" % int(100.0 * progress / craft_time())
		for item: String in recipe["out"]:
			if not recipe["in"].has(item) and output.get(item, 0) + recipe["out"][item] > OUTPUT_CAP:
				return "output full"
		return "needs input"

	func tick(dt: float) -> void:
		chained = maxf(0.0, chained - dt)
		if not powered:
			return
		if not crafting:
			_try_start()
		if crafting:
			progress += dt
			if progress >= craft_time() - 1e-6:
				for item: String in recipe["out"]:
					if recipe["in"].has(item):  # F6: what its own recipe uses goes straight back in (a planter's seed)
						input[item] = mini(input.get(item, 0) + recipe["out"][item], INPUT_CAP)
					else:
						output[item] = output.get(item, 0) + recipe["out"][item]
				crafting = false
				progress = 0.0
				crafted += 1
				_try_start()  # roll straight into the next one, so a busy machine never goes quiet for a tick

	func _try_start() -> void:
		if not _can_start():
			return
		for item: String in recipe["in"]:
			input[item] -= recipe["in"][item]
			if input[item] == 0:
				input.erase(item)
		crafting = true
		progress = 0.0

	func _can_start() -> bool:
		for item: String in recipe["in"]:
			if input.get(item, 0) < recipe["in"][item]:
				return false
		for item: String in recipe["out"]:
			if not recipe["in"].has(item) and output.get(item, 0) + recipe["out"][item] > OUTPUT_CAP:
				return false
		return true


class Belt:
	extends RefCounted
	var cell: Vector2i
	var facing: int
	## Front-most first. Each: {item: String, pos: float 0..1 along the belt, prev: pos last tick}.
	## A blocked belt holds 5: one waiting at each end and three between, SPACING apart.
	var items: Array = []

	func can_accept() -> bool:
		return items.is_empty() or items.back()["pos"] >= SPACING

	func accept(item: String) -> void:
		items.append({"item": item, "pos": 0.0, "prev": 0.0})


## F3: a splitter or a merger. A splitter takes items at its back and hands them out front, left and right in
## turn (skipping a side that's full or empty of belts); a merger takes them at its back, left and right and
## hands them out front. Holds up to ROUTER_CAP while its outputs are blocked.
class Router:
	extends RefCounted
	var cell: Vector2i
	var facing: int
	var kind := "splitter"
	var items: Array = []  # waiting to go out, oldest first
	var next_out := 0      # a splitter's turn: 0 front, 1 left, 2 right

	func can_accept() -> bool:
		return items.size() < ROUTER_CAP


## A turret's magazine: takes its ammo by hand, from a belt on any side or from a hopper behind it (M15).
## M15: it may also carry gun parts (a suppressor in "muzzle", a scope in "sight"), gear pieces attached by hand.
class Turret:
	extends RefCounted
	var id := "nail_turret"
	var parts: Dictionary = {}  # slot -> gear piece
	var ammo_item: String
	var cap: int
	var ammo := 0
	var cooldown := 0.0
	var target := -1  # zombie id it's aiming at, -1 if none
	var shots := 0
	var kills := 0  # F4: zombies it has killed
	var fed := 0    # F4: rounds a belt, a hopper or a machine has handed it (not your hands)

	func accepts(item: String) -> bool:
		return item == ammo_item and ammo < cap


var data: GameData
var machines: Dictionary = {}  # Vector2i -> Machine
var turrets: Dictionary = {}   # Vector2i -> Turret
var belts: Dictionary = {}     # Vector2i -> Belt
var bins: Dictionary = {}      # Vector2i -> Bin (M15: hoppers and repair stations)
var routers: Dictionary = {}   # Vector2i -> Router (F3: splitters and mergers)
## F6: everything machines have made, ever: item -> count (SimWorld turns it into "made yesterday / today").
var made: Dictionary = {}
## F3: the storage crate at a cell, if any (SimWorld sets it): a belt ending at a crate puts its items in.
var storage_at: Callable
## F4: (cell, item) -> whether something standing there took the item from a belt (SimWorld sets it: the Hub
## takes the parts its open milestones still need).
var sink_at: Callable


## M15: a piece that holds a stack of one item: a hopper (any turret ammo; feeds the turret in front of it)
## or a repair station (wall panels). Fed by hand or by a belt on any side.
class Bin:
	extends RefCounted
	var id: String
	var cell: Vector2i
	var facing: int
	var feeds: Array = []  # items it takes
	var item := ""         # what it holds now ("" when empty)
	var count := 0
	var cap := 0
	var timer := 0.0       # repair station: seconds since its last repair

	func accepts(it: String) -> bool:
		return it in feeds and count < cap and (count == 0 or it == item)

	func put(it: String, n: int) -> int:
		if n <= 0 or not (it in feeds) or (count > 0 and it != item):
			return 0
		var took := mini(n, cap - count)
		if took > 0:
			item = it
			count += took
		return took

	func take_one() -> void:
		count -= 1
		if count <= 0:
			count = 0
			item = ""


## Set by SimWorld (M12): Fast Lines speeds belts, Tuned Machines speeds crafting, Farming grows more.
var skills: Skills
## M16: this season's speed for planters (0 in winter: frozen) and rain collectors (data/seasons.json),
## set by SimWorld every tick.
var crop_speed := 1.0
var rain_speed := 1.0
## M17a: set by SimWorld from the projects done: the water tower running fills rain collectors faster
## (rain_boost, its reward's rain_mult) and lets water taps run (tap_on); a tap is dry otherwise.
var rain_boost := 1.0
var tap_on := false


func _init(p_data: GameData) -> void:
	data = p_data


func add_machine(id: String, cell: Vector2i, facing: int) -> Machine:
	var m := Machine.new()
	m.id = id
	m.cell = cell
	m.facing = facing
	set_recipe(m, data.buildables[id]["recipe"])
	m.watts = data.buildables[id]["watts"]
	machines[cell] = m
	return m


## F6: the crop a planter grows with its recipe: the first thing it makes that isn't seeds.
static func crop_of(m: Machine) -> String:
	for item: String in m.recipe["out"]:
		if item != "seeds":
			return item
	return CROP


func set_recipe(m: Machine, recipe_id: String) -> void:
	m.recipe_id = recipe_id
	m.recipe = data.recipes[recipe_id]


func add_belt(cell: Vector2i, facing: int) -> Belt:
	var b := Belt.new()
	b.cell = cell
	b.facing = facing
	belts[cell] = b
	return b


func add_turret(id: String, cell: Vector2i) -> Turret:
	var t := Turret.new()
	t.id = id
	t.ammo_item = data.buildables[id]["ammo"]
	t.cap = data.buildables[id]["ammo_cap"]
	turrets[cell] = t
	return t


## M15: a hopper (feeds: the turret ammo in defense.json) or a repair station (wall panels).
func add_bin(id: String, cell: Vector2i, facing: int) -> Bin:
	var b := Bin.new()
	b.id = id
	b.cell = cell
	b.facing = facing
	if data.buildables[id]["kind"] == "hopper":
		b.feeds = Array(data.defense["hopper"]["feeds"])
		b.cap = int(data.defense["hopper"]["cap"])
	else:
		b.feeds = [str(data.defense["repair_station"]["item"])]
		b.cap = int(data.defense["repair_station"]["cap"])
	bins[cell] = b
	return b


## Removes whatever is at `cell` and returns the items it held ({item: count}).
func remove_at(cell: Vector2i) -> Dictionary:
	var held := contents_at(cell)
	for item: Variant in (routers[cell].items if routers.has(cell) else []):
		held[item] = int(held.get(item, 0)) + 1
	routers.erase(cell)
	machines.erase(cell)
	belts.erase(cell)
	turrets.erase(cell)
	bins.erase(cell)
	return held


func contents_at(cell: Vector2i) -> Dictionary:
	var held := {}
	if machines.has(cell):
		var m: Machine = machines[cell]
		var bags: Array = [m.input, m.output]
		if m.crafting:
			bags.append(m.recipe["in"])  # the half-made item's inputs come back
		for bag: Dictionary in bags:
			for item: String in bag:
				held[item] = held.get(item, 0) + bag[item]
	if belts.has(cell):
		for entry: Dictionary in belts[cell].items:
			held[entry["item"]] = held.get(entry["item"], 0) + 1
	if turrets.has(cell) and turrets[cell].ammo > 0:
		held[turrets[cell].ammo_item] = held.get(turrets[cell].ammo_item, 0) + turrets[cell].ammo
	if bins.has(cell) and bins[cell].count > 0:
		held[bins[cell].item] = held.get(bins[cell].item, 0) + bins[cell].count
	return held


## Moves everything first, then does hand-offs, so an item handed on is never moved twice in one tick.
func tick(dt: float) -> void:
	var belt_cells := _sorted(belts)
	for cell: Vector2i in belt_cells:
		_move_belt(belts[cell], dt)
	for cell: Vector2i in _sorted(routers):  # F3: splitters and mergers hand on what they hold
		_route(routers[cell])
	for cell: Vector2i in belt_cells:
		var belt: Belt = belts[cell]
		if not belt.items.is_empty() and belt.items[0]["pos"] >= 1.0:
			if _give(cell + DIRS[belt.facing], cell, belt.items[0]["item"]):
				belt.items.pop_front()
	var craft_dt := dt * (1.0 + _bonus("craft_speed"))
	var extra := floori(_bonus("planter_extra"))
	for cell: Vector2i in _sorted(machines):
		var m: Machine = machines[cell]
		var crafted := m.crafted
		var season := season_speed(m)
		m.frozen = season <= 0.0
		if not m.frozen:
			m.tick(craft_dt * season)
		if m.crafted > crafted:  # F6: what got made, for "what your base made" (not what went back in, like seeds)
			for item: String in m.recipe["out"]:
				if not m.recipe["in"].has(item):
					made[item] = int(made.get(item, 0)) + int(m.recipe["out"][item]) * (m.crafted - crafted)
		if extra > 0 and m.id == "planter" and m.crafted > crafted:
			var crop := crop_of(m)  # F6: Farming's extra goes to whatever it grows (vegetables or cotton)
			m.output[crop] = m.output.get(crop, 0) + extra * (m.crafted - crafted)
			made[crop] = int(made.get(crop, 0)) + extra * (m.crafted - crafted)
		for item: String in _sorted(m.output):
			if _give(cell + DIRS[m.facing], cell, item):
				m.output[item] -= 1
				if m.output[item] == 0:
					m.output.erase(item)
				break  # one item out per tick
	for cell: Vector2i in _sorted(bins):  # M15: a hopper hands one round a tick to the turret in front of it
		var bin: Bin = bins[cell]
		if bin.count > 0 and data.buildables[bin.id]["kind"] == "hopper":
			var t: Turret = turrets.get(cell + DIRS[bin.facing])
			if t != null and t.accepts(bin.item):
				t.ammo += 1
				t.fed += 1
				bin.take_one()


## Hand interaction: takes everything a machine has made (or everything on a belt) into `inv`,
## then feeds the machine as much of its recipe's inputs as `inv` has. Returns what moved.
func hand_interact(cell: Vector2i, inv: Inventory) -> Dictionary:
	var took := {}
	var fed := {}
	if turrets.has(cell):
		var t: Turret = turrets[cell]
		var n := mini(inv.count(t.ammo_item), t.cap - t.ammo)
		if n > 0 and inv.remove(t.ammo_item, n):
			t.ammo += n
			fed[t.ammo_item] = n
	elif bins.has(cell):  # M15: a hopper loads what the turret in front of it fires (or what it holds already)
		var bin: Bin = bins[cell]
		var want := bin.item
		if want == "":
			var t: Turret = turrets.get(cell + DIRS[bin.facing])
			want = t.ammo_item if t != null and t.ammo_item in bin.feeds else ""
		if want == "":
			for it: String in bin.feeds:
				if inv.count(it) > 0:
					want = it
					break
		var n := mini(inv.count(want), bin.cap - bin.count) if want != "" else 0
		if n > 0 and inv.remove(want, n):
			bin.put(want, n)
			fed[want] = n
	elif belts.has(cell):
		took = contents_at(cell)
		belts[cell].items.clear()
		inv.give_all(took)
	elif machines.has(cell):
		var m: Machine = machines[cell]
		took = m.output.duplicate()
		m.output.clear()
		inv.give_all(took)
		for item: String in m.recipe["in"]:
			var n := mini(inv.count(item), INPUT_CAP - m.input.get(item, 0))
			if n > 0 and inv.remove(item, n):
				m.input[item] = m.input.get(item, 0) + n
				fed[item] = n
	return {"took": took, "fed": fed}


func _bonus(effect: String) -> float:
	return skills.bonus(effect) if skills != null else 0.0


## M16: how fast the season lets this machine work: planters crop_speed, rain collectors rain_speed, others 1.
func season_speed(m: Machine) -> float:
	match m.id:
		"planter":
			return crop_speed
		"rain_collector":
			return rain_speed * rain_boost
		"water_tap":
			return 1.0 if tap_on else 0.0
	return 1.0


## Belt speed in cells per second, with Fast Lines.
func belt_speed() -> float:
	return BELT_SPEED * (1.0 + _bonus("belt_speed"))


func _move_belt(belt: Belt, dt: float) -> void:
	var speed := belt_speed()
	for i in belt.items.size():
		var entry: Dictionary = belt.items[i]
		entry["prev"] = entry["pos"]
		var limit: float = 1.0 if i == 0 else belt.items[i - 1]["pos"] - SPACING
		entry["pos"] = maxf(entry["pos"], minf(entry["pos"] + speed * dt, limit))


## F3: adds a splitter or merger.
func add_router(kind: String, cell: Vector2i, facing: int) -> Router:
	var r := Router.new()
	r.kind = kind
	r.cell = cell
	r.facing = facing
	routers[cell] = r
	return r


## F3: a router hands its oldest item on: a merger out of its front, a splitter to the next side in turn that
## takes it (front, left, right).
func _route(r: Router) -> void:
	if r.items.is_empty():
		return
	var outs: Array = [r.facing] if r.kind == "merger" else [r.facing, (r.facing + 3) % 4, (r.facing + 1) % 4]
	for k in outs.size():
		var i := (r.next_out + k) % outs.size()
		if _give(r.cell + DIRS[outs[i]], r.cell, r.items[0]):
			r.items.pop_front()
			r.next_out = (i + 1) % outs.size()
			return


## Hands one item from `from` to whatever is at `to`, if it will take it from that side.
func _give(to: Vector2i, from: Vector2i, item: String) -> bool:
	if routers.has(to):  # F3
		var r: Router = routers[to]
		var side := DIRS.find(from - to)  # which way `from` is from the router
		var back := (r.facing + 2) % 4
		var takes := side == back if r.kind == "splitter" else side != r.facing
		if not takes or not r.can_accept():
			return false
		r.items.append(item)
		return true
	if belts.has(to):
		var b: Belt = belts[to]
		if to + DIRS[b.facing] == from or not b.can_accept():
			return false  # can't feed a belt from its front end
		b.accept(item)
		return true
	if turrets.has(to):
		var t: Turret = turrets[to]
		if not t.accepts(item):
			return false
		t.ammo += 1  # turrets take ammo from a belt on any side
		t.fed += 1
		return true
	if bins.has(to):
		var bin: Bin = bins[to]
		if not bin.accepts(item):
			return false
		bin.put(item, 1)  # hoppers and repair stations take from a belt on any side
		return true
	if machines.has(to):
		var m: Machine = machines[to]
		if to - DIRS[m.facing] != from or not m.accepts(item):
			return false  # machines only take input at their back
		m.input[item] = m.input.get(item, 0) + 1
		if machines.has(from):
			m.chained = CHAIN_HOLD  # F6: straight from the machine behind: the chain bonus
		return true
	if sink_at.is_valid() and sink_at.call(to, item):  # F4: the Hub, from a belt on any side
		return true
	if storage_at.is_valid():  # F3: a storage crate takes from a belt on any side
		var crate: Variant = storage_at.call(to)
		if crate != null and (crate as Inventory).items().reduce(func(acc: int, it: String) -> int: return acc + crate.count(it), 0) < STORAGE_FROM_BELT_CAP:
			(crate as Inventory).add(item, 1)
			return true
	return false


static func _sorted(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	return keys
