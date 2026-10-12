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


class Machine:
	extends RefCounted
	var id: String
	var cell: Vector2i
	var facing: int
	var recipe: Dictionary  # {name, time, in, out}
	var input: Dictionary = {}
	var output: Dictionary = {}
	var progress := 0.0  # seconds into the current craft
	var crafting := false
	var crafted := 0     # crafts finished, ever
	var muffled := false
	var time_scale := 1.0  # a muffler slows the machine down

	func craft_time() -> float:
		return recipe["time"] * time_scale

	func accepts(item: String) -> bool:
		return recipe["in"].has(item) and input.get(item, 0) < INPUT_CAP

	func status() -> String:
		if crafting:
			return "working %d%%" % int(100.0 * progress / craft_time())
		for item: String in recipe["out"]:
			if output.get(item, 0) + recipe["out"][item] > OUTPUT_CAP:
				return "output full"
		return "needs input"

	func tick(dt: float) -> void:
		if not crafting:
			_try_start()
		if crafting:
			progress += dt
			if progress >= craft_time() - 1e-6:
				for item: String in recipe["out"]:
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
			if output.get(item, 0) + recipe["out"][item] > OUTPUT_CAP:
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


var data: GameData
var machines: Dictionary = {}  # Vector2i -> Machine
var belts: Dictionary = {}     # Vector2i -> Belt


func _init(p_data: GameData) -> void:
	data = p_data


func add_machine(id: String, cell: Vector2i, facing: int) -> Machine:
	var m := Machine.new()
	m.id = id
	m.cell = cell
	m.facing = facing
	m.recipe = data.recipes[data.buildables[id]["recipe"]]
	machines[cell] = m
	return m


func add_belt(cell: Vector2i, facing: int) -> Belt:
	var b := Belt.new()
	b.cell = cell
	b.facing = facing
	belts[cell] = b
	return b


## Removes whatever is at `cell` and returns the items it held ({item: count}).
func remove_at(cell: Vector2i) -> Dictionary:
	var held := contents_at(cell)
	machines.erase(cell)
	belts.erase(cell)
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
	return held


## Moves everything first, then does hand-offs, so an item handed on is never moved twice in one tick.
func tick(dt: float) -> void:
	var belt_cells := _sorted(belts)
	for cell: Vector2i in belt_cells:
		_move_belt(belts[cell], dt)
	for cell: Vector2i in belt_cells:
		var belt: Belt = belts[cell]
		if not belt.items.is_empty() and belt.items[0]["pos"] >= 1.0:
			if _give(cell + DIRS[belt.facing], cell, belt.items[0]["item"]):
				belt.items.pop_front()
	for cell: Vector2i in _sorted(machines):
		var m: Machine = machines[cell]
		m.tick(dt)
		for item: String in _sorted(m.output):
			if _give(cell + DIRS[m.facing], cell, item):
				m.output[item] -= 1
				if m.output[item] == 0:
					m.output.erase(item)
				break  # one item out per tick


## Hand interaction: takes everything a machine has made (or everything on a belt) into `inv`,
## then feeds the machine as much of its recipe's inputs as `inv` has. Returns what moved.
func hand_interact(cell: Vector2i, inv: Inventory) -> Dictionary:
	var took := {}
	var fed := {}
	if belts.has(cell):
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


func _move_belt(belt: Belt, dt: float) -> void:
	for i in belt.items.size():
		var entry: Dictionary = belt.items[i]
		entry["prev"] = entry["pos"]
		var limit: float = 1.0 if i == 0 else belt.items[i - 1]["pos"] - SPACING
		entry["pos"] = maxf(entry["pos"], minf(entry["pos"] + BELT_SPEED * dt, limit))


## Hands one item from `from` to whatever is at `to`, if it will take it from that side.
func _give(to: Vector2i, from: Vector2i, item: String) -> bool:
	if belts.has(to):
		var b: Belt = belts[to]
		if to + DIRS[b.facing] == from or not b.can_accept():
			return false  # can't feed a belt from its front end
		b.accept(item)
		return true
	if machines.has(to):
		var m: Machine = machines[to]
		if to - DIRS[m.facing] != from or not m.accepts(item):
			return false  # machines only take input at their back
		m.input[item] = m.input.get(item, 0) + 1
		return true
	return false


static func _sorted(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	return keys
