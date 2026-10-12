class_name SimWorld
extends RefCounted
## Owns all game-rule state and steps it on a fixed tick, separate from the frame rate.
## The world layer calls update(frame_delta) every frame; rules only ever see TICK-sized steps,
## so the same total time always gives the same result no matter how frames were sliced.

const TICK_RATE := 20
const TICK := 1.0 / TICK_RATE
## Cap per update so a long freeze (debugger, alt-tab) can't snowball into thousands of ticks.
const MAX_TICKS_PER_UPDATE := 10

var clock: GameClock
var data: GameData
var inventory := Inventory.new()
var build: BuildGrid
var factory: Factory
var horde: Horde
var noise: NoiseField
var power: PowerGrid
var defense: Defense
## The town's cars: position, fuel (gas cans, siphoned with G), damage, wrecks, and the one you drive.
var vehicles: Vehicles
## Skills that level by doing (just Mechanics until M12).
var skills: Skills
var director: Director
## Short notices for the HUD ("Moaning to the north..."): {text, time_left}.
var messages: Array = []
var loot: Loot
## Storage crates: piece key -> Inventory.
var storages: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var player := PlayerStats.new()
## Written by the world each frame: where the player stands and whether the flashlight is on.
var player_pos := Vector3.ZERO
var player_lit := false
var spawn_point := Vector3.ZERO
## Bags dropped where the player died: {id: int, pos: Vector3, items: {item: count}}.
var bags: Array = []
var _next_bag := 1
var ticks: int = 0
var seed_value: int = 1
var paused := false
var _accumulator := 0.0


func _init(start_hour: float = 8.0, p_data: GameData = null, p_seed: int = 1) -> void:
	seed_value = p_seed
	clock = GameClock.new(start_hour)
	data = p_data if p_data != null else GameData.load_default()
	build = BuildGrid.new(data)
	factory = Factory.new(data)
	power = PowerGrid.new(data, build, factory)
	defense = Defense.new(data, build, factory)
	horde = Horde.new(data, seed_value)
	noise = NoiseField.new(data, build)
	director = Director.new(data, seed_value)
	loot = Loot.new(data, seed_value)
	vehicles = Vehicles.new(data)
	skills = Skills.new(data)
	player.cfg = data.survival
	_rng.seed = hash([seed_value, "sim"])
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	build.piece_added.connect(_on_piece_added)
	build.piece_removed.connect(_on_piece_removed)


## Starting materials for testing builds (data/debug_kit.json).
func give_debug_kit() -> void:
	inventory.give_all(data.debug_kit)


## Feeds real frame time in; runs as many whole ticks as fit. Returns how many ran.
func update(real_delta: float) -> int:
	if paused:
		return 0
	_accumulator += real_delta
	var ran := 0
	while _accumulator >= TICK and ran < MAX_TICKS_PER_UPDATE:
		_accumulator -= TICK
		step()
		ran += 1
	if ran == MAX_TICKS_PER_UPDATE:
		_accumulator = minf(_accumulator, TICK)
	return ran


## One fixed tick of every rule. New systems (machines, noise, zombies) hook in here.
func step() -> void:
	ticks += 1
	clock.advance(TICK)
	power.tick(TICK, clock.daylight())
	factory.tick(TICK)
	vehicles.tick(TICK)
	_tick_hotwire()
	noise.refresh(factory, TICK, power, vehicles)
	player.carry_ratio = carry_ratio()
	player.tick(TICK)
	var found := loot.tick(TICK, player_pos)
	if not found.is_empty():
		inventory.give_all(found["items"])
		add_message(("Found " + _list(found["items"])) if not found["items"].is_empty() else "Nothing useful", 4.0)
	var night := clock.is_night()
	var ctx := {"player_pos": player_pos, "player_dead": player.dead, "night": night,
			"player_lit": player_lit, "pieces": build.pieces, "noise": noise}
	for e: Dictionary in horde.tick(TICK, ctx):
		var z: ZombieBrain = horde.zombies.get(e["zombie"])
		if z == null:
			continue
		if e["target"] == "player" and vehicles.driving != "":
			vehicles.damage(vehicles.driving, float(z.stats["damage"]))  # the car takes it while you're inside
			noise.emit_kind(z.pos, "zombie_bash")
		elif e["target"] == "player":
			player.damage(float(z.stats["damage"]))
			if not player.dead and _rng.randf() < float(data.survival["bleed_chance"]):
				if not player.bleeding:
					add_message("You're bleeding (H to bandage)", 4.0)
				player.bleeding = true
		elif build.pieces.has(e["target"]):
			var at := z.pos  # the noise is where the zombie stands, not inside the wall it hits
			noise.emit_kind(at, "zombie_bash")  # banging on your walls draws more of them
			if build.damage(e["target"], int(z.stats["structure_damage"])):
				noise.emit_kind(at, "wreck")
	defense.tick(TICK, horde, noise)
	var wave := director.tick(TICK, noise, night, horde)
	if not wave.is_empty():
		var what: String = {"wanderers": "Something is stirring", "group": "Moaning", "horde": "A horde is coming"}[wave["kind"]]
		add_message("%s from the %s..." % [what, wave["edge"]])
	for m: Dictionary in messages:
		m["time_left"] -= TICK
	messages = messages.filter(func(m: Dictionary) -> bool: return m["time_left"] > 0.0)


func add_message(text: String, seconds: float = 6.0) -> void:
	messages.append({"text": text, "time_left": seconds})


## A one-off sound from the player ("footstep_walk", "footstep_sprint", ...; see data/noise.json).
## Footsteps get louder when you carry more than your limit.
func make_noise(pos: Vector3, kind: String) -> void:
	var loudness := float(data.noise["sounds"][kind])
	if kind.begins_with("footstep") and carry_ratio() > 1.0:
		loudness += float(data.survival["carry_footstep_bonus"])
	noise.emit(pos, loudness, kind)


# --- Carrying ---------------------------------------------------------------

## Carry limit in kg: carry_base plus the best bag you're carrying (only one bag counts).
func carry_limit() -> float:
	var best := 0.0
	for item: String in inventory.items():
		best = maxf(best, data.item_value(item, "bag"))
	return float(data.survival["carry_base"]) + best


func carry_ratio() -> float:
	return inventory.weight(data) / carry_limit()


## Your pockets plus every storage crate within storage_range of `at`: what building and hand-feeding use.
func stock_at(at: Vector3) -> Stock:
	var crates := []
	var reach := float(data.survival["storage_range"])
	for key: String in storages:
		if build.pieces.has(key) and _flat_dist(build.piece_center(key), at) <= reach:
			crates.append(storages[key])
	return Stock.new(inventory, crates)


## Puts every building material you carry (not food, drink, bandages or bags) into a storage crate.
func deposit(key: String) -> Dictionary:
	if not storages.has(key):
		return {}
	var moved := {}
	for item: String in inventory.items():
		if _is_supply(item):
			continue
		moved[item] = inventory.count(item)
	if not moved.is_empty():
		inventory.take_all(moved)
		storages[key].give_all(moved)
	return moved


## Puts the debug kit in a new storage crate on a new foundation at `cell` (the start-of-game stash).
func place_start_stash(cell: Vector2i) -> String:
	var kit := Inventory.new()
	kit.give_all(data.debug_kit)
	kit.give_all({"plank": 12, "nails": 8})  # pays for the foundation and crate themselves
	if build.place("foundation", cell, BuildGrid.Side.NORTH, kit) != "":
		return ""
	if build.place("storage", cell, BuildGrid.Side.WEST, kit) != "":
		return ""
	var key := build.key_for("storage", cell)
	storages[key].give_all(_counts_of(kit))
	return key


## Storage crates within arm's reach (crate_reach) of `at`, nearest first: what the inventory screen shows.
func crates_near(at: Vector3) -> Array:
	var reach := float(data.survival["crate_reach"])
	var found := []
	for key: String in storages:
		if build.pieces.has(key):
			var d := _flat_dist(build.piece_center(key), at)
			if d <= reach:
				found.append([d, key])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return found.map(func(e: Array) -> String: return e[1])


## Drops items from your pockets in a bag at your feet (into a bag already lying there, if any).
## Pick it back up with E like a death bag. Returns a message.
func drop_items(item: String, amount: int) -> String:
	var n := mini(amount, inventory.count(item))
	if n <= 0:
		return "Nothing to drop"
	inventory.remove(item, n)
	var msg := "Dropped %d %s" % [n, data.item_name(item)]
	for bag: Dictionary in bags:
		if _flat_dist(bag["pos"], player_pos) <= 1.0:
			bag["items"][item] = int(bag["items"].get(item, 0)) + n
			return msg
	drop_bag(player_pos, {item: n})
	return msg


# --- Eating, drinking, first aid, sleep -----------------------------------------

## True if `item` can be used from the inventory screen (food, drink or a bandage).
func can_use(item: String) -> bool:
	return data.item_value(item, "food") > 0.0 or data.item_value(item, "water") > 0.0 			or data.item_value(item, "bandage") > 0.0


## Uses one of a particular item from your pockets: eat or drink it, or put on a bandage.
func use_item(item: String) -> String:
	if inventory.count(item) <= 0:
		return "You don't have that"
	if data.item_value(item, "bandage") > 0.0:
		return use_bandage()
	var food := data.item_value(item, "food")
	var water := data.item_value(item, "water")
	if food <= 0.0 and water <= 0.0:
		return "Can't use %s" % data.item_name(item)
	inventory.remove(item, 1)
	player.consume(food, water)
	return "%s %s" % ["Ate" if food >= water else "Drank", data.item_name(item)]



## Eats the most filling food you carry. Returns a message for the HUD.
func eat_best() -> String:
	return _consume_best("food", "Nothing to eat")


func drink_best() -> String:
	return _consume_best("water", "Nothing to drink")


func use_bandage() -> String:
	if not player.bleeding:
		return "Not bleeding"
	if not inventory.remove("bandage", 1):
		return "No bandages"
	player.bleeding = false
	return "Bandaged"


## Sleep in the bed `key`: it becomes your respawn point. Returns "" or why not.
func sleep_in(key: String) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "bed":
		return "No bed"
	spawn_point = build.piece_center(key) + Vector3(1.2, -build.piece_center(key).y, 0)
	if player.energy >= float(data.survival["sleep_below_energy"]):
		return "Not tired. You'll wake up here if you die"
	player.sleep()
	return ""


func _consume_best(key: String, none: String) -> String:
	var best := ""
	for item: String in inventory.items():
		if data.item_value(item, key) > (data.item_value(best, key) if best != "" else 0.0):
			best = item
	if best == "":
		return none
	inventory.remove(best, 1)
	player.consume(data.item_value(best, "food"), data.item_value(best, "water"))
	return "%s %s" % ["Ate" if key == "food" else "Drank", data.item_name(best)]


func _is_supply(item: String) -> bool:
	for key: String in ["food", "water", "bandage", "bag"]:
		if data.item_value(item, key) > 0.0:
			return true
	return false


# --- Doors and repair ---------------------------------------------------------

## Opens or closes a door (a little noise). Returns a message.
func toggle_door(key: String) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "door":
		return ""
	var open := build.toggle_door(key)
	noise.emit_kind(build.piece_center(key), "door")
	return "Door opened" if open else "Door closed"


## Repairs a piece with materials from your pockets and nearby crates. Returns "" or why not.
func repair(key: String) -> String:
	if not build.pieces.has(key):
		return "Nothing to repair"
	var why := build.repair(key, stock_at(build.piece_center(key)))
	if why == "":
		_practice("mechanics", "repair")
	return why


# --- Fuel ---------------------------------------------------------------------

func clock_daylight() -> float:
	return clock.daylight()


## Registers a town car: its gas (fixed by the world seed and the car's id) and whether it's a wreck.
## car_0 always drives, so there's one to find near the start.
func add_car(id: String, type: String = "sedan", pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, id, "fuel"])
	var fuel := rng.randi_range(int(data.survival["car_fuel_min"]), int(data.survival["car_fuel_max"]))
	var wreck := ""
	if id != "car_0" and rng.randf() < float(data.survival["car_wreck_chance"]):
		wreck = ["Flat tyres", "The engine won't turn over", "Smashed up too badly"][rng.randi_range(0, 2)]
	if pos == Vector3.ZERO and loot.containers.has(id):
		pos = loot.containers[id]["pos"]  # registered without a spot: where its trunk is
	# Its key (Zomboid style): in the ignition, the glovebox (search the car), the nearest house, or lost.
	# car_0's is always in its glovebox, so a new game teaches you to look.
	var r := rng.randf()
	var key_in := "glovebox" if id == "car_0" else ("ignition" if r < 0.25 else ("glovebox" if r < 0.6 else ("house" if r < 0.85 else "lost")))
	vehicles.add(id, type, pos, yaw, fuel, wreck, key_in)
	if loot.containers.has(id):
		loot.containers[id]["pos"] = vehicles.trunk_pos(id)
	var key := {Vehicles.key_item(id): 1}
	if key_in == "glovebox" and loot.containers.has(id):
		loot.add_extra(id, key)
	elif key_in == "house":
		var house := _nearest_house(pos)
		if house != "":
			loot.add_extra(house, key)
		else:
			vehicles.cars[id]["key_in"] = "lost"


func _nearest_house(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for cid: String in loot.containers:
		if cid.begins_with("house_"):
			var d := _flat_dist(loot.containers[cid]["pos"], pos)
			if d < best_d:
				best_d = d
				best = cid
	return best


## Siphons every whole gas can's worth out of a car into your pockets (a sloshing noise). Returns a message.
func siphon(id: String) -> String:
	if not vehicles.cars.has(id):
		return "No fuel tank"
	if _flat_dist(vehicles.cars[id]["pos"], player_pos) > float(data.survival["search_range"]) + 2.5:
		return "Too far away"
	var cans := vehicles.siphon(id)
	if cans <= 0:
		return "The tank is dry"
	inventory.add("gas_can", cans)
	noise.emit(player_pos, float(data.survival["siphon_noise"]), "siphon")
	return "Siphoned %d gas can%s" % [cans, "s" if cans > 1 else ""]


# --- Driving ------------------------------------------------------------------

## Gets into car `id`. Returns "" or why not.
func enter_car(id: String) -> String:
	if player.dead:
		return "You're dead"
	var why := vehicles.enter(id)
	if why == "":
		player_pos = vehicles.cars[id]["pos"]  # you're in the car now: zombies come for it
		var c: Dictionary = vehicles.cars[id]
		c["running"] = c["fuel"] > 0.0 and vehicles.can_start(id, inventory)  # no key, no engine
	return why


## R while sitting in a car you have no key for: hotwire it. Needs Mechanics (data/skills.json
## hotwire_level); higher levels are quicker. Makes a little noise. Returns "" or why not.
func hotwire() -> String:
	var id := vehicles.driving
	if id == "":
		return "Not in a car"
	if vehicles.can_start(id, inventory):
		return "You don't need to: you can start this one"
	var need := int(data.skills["hotwire_level"])
	var lv := skills.level("mechanics")
	if lv < need:
		return "You don't know how to hotwire a car (needs Mechanics %d)" % need
	if vehicles.hotwire_left <= 0.0:
		vehicles.hotwire_left = maxf(float(data.skills["hotwire_min_seconds"]),
				float(data.skills["hotwire_seconds"]) - float(data.skills["hotwire_seconds_per_level"]) * (lv - need))
		noise.emit(vehicles.cars[id]["pos"], float(data.skills["hotwire_noise"]), "hotwire")
	return ""


func _tick_hotwire() -> void:
	if vehicles.hotwire_left <= 0.0 or vehicles.driving == "":
		return
	vehicles.hotwire_left -= TICK
	if vehicles.hotwire_left > 0.0:
		return
	vehicles.hotwire_left = 0.0
	var c: Dictionary = vehicles.cars[vehicles.driving]
	c["hotwired"] = true
	c["running"] = c["fuel"] > 0.0
	_practice("mechanics", "hotwire")
	add_message("Hotwired. The engine coughs into life" if c["running"] else "Hotwired, but the tank is empty", 4.0)


## Gets out; you end up beside the driver's door. Returns where you stand.
func exit_car() -> Vector3:
	var id := vehicles.exit()
	if id == "":
		return player_pos
	player_pos = vehicles.exit_pos(id)
	return player_pos


## The world reports the car you're driving each physics step: you're where the car is (so zombies come
## for the car), fuel burns, and the trunk moves with it.
func car_moved(pos: Vector3, yaw: float, speed: float) -> void:
	var id := vehicles.driving
	if id == "":
		return
	vehicles.moved(id, pos, yaw, speed)
	player_pos = pos
	if loot.containers.has(id):
		loot.containers[id]["pos"] = vehicles.trunk_pos(id)


func honk() -> void:
	if vehicles.driving != "":
		noise.emit_kind(vehicles.cars[vehicles.driving]["pos"], "horn")


func refuel_car(id: String) -> String:
	if not vehicles.cars.has(id):
		return "No fuel tank"
	return vehicles.refuel(id, inventory)


## Repairs a car with a metal plate and nails from your pockets and nearby crates. Returns "" or why not.
func repair_car(id: String) -> String:
	if not vehicles.cars.has(id):
		return "Nothing to repair"
	var why := vehicles.repair(id, stock_at(vehicles.cars[id]["pos"]))
	if why == "":
		_practice("mechanics", "repair_car")
	return why


## The car you're driving hit zombie `zombie_id` at `speed` m/s. Returns true if it died.
func car_hits_zombie(zombie_id: int, speed: float) -> bool:
	var z: ZombieBrain = horde.zombies.get(zombie_id)
	if z == null or z.is_dead() or vehicles.driving == "":
		return false
	var car: Dictionary = vehicles.cars[vehicles.driving]
	var damage := vehicles.ram(vehicles.driving, speed)
	noise.emit_kind(z.pos, "zombie_bash")
	return z.take_hit(damage, car["pos"], speed * 0.6)


# --- Searching ----------------------------------------------------------------

## Starts searching a container (a little noise). Returns "" or why not.
func search(id: String) -> String:
	var reason := loot.start(id, player_pos)
	if reason == "" and loot.progress == 0.0:
		noise.emit(loot.containers[id]["pos"], float(data.survival["search_noise"]), "search")
	return reason


## Fits a muffler to the machine at `cell`: -15 loudness, 10% slower. Returns "" or why not.
func fit_muffler(cell: Vector2i) -> String:
	var gen_key := "o:%d:%d" % [cell.x, cell.y]
	if power.generators.has(gen_key):
		if power.generators[gen_key]["muffled"]:
			return "Already muffled"
		if not inventory.take_all(data.noise["muffler"]["cost"]):
			return "Not enough materials"
		power.generators[gen_key]["muffled"] = true
		_practice("mechanics", "muffler")
		return ""
	var m: Factory.Machine = factory.machines.get(cell)
	if m == null:
		return "No machine there"
	if m.muffled:
		return "Already muffled"
	var muffler: Dictionary = data.noise["muffler"]
	if not inventory.take_all(muffler["cost"]):
		return "Not enough materials"
	m.muffled = true
	m.time_scale = 1.0 + float(muffler["slowdown"])
	_practice("mechanics", "muffler")
	return ""


## The player hits zombie `id` with their weapon (call after player.try_swing succeeds and the swing
## connects). `head` doubles the damage. Returns true if it killed the zombie.
func hit_zombie(id: int, head: bool) -> bool:
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null:
		return false
	var w: Dictionary = data.weapons[player.weapon]
	var dmg := float(w["damage"]) * (float(w["head_multiplier"]) if head else 1.0)
	noise.emit_kind(z.pos, "melee_hit")
	return z.take_hit(dmg, player_pos, float(w["knockback"]))


func weapon_stats() -> Dictionary:
	return data.weapons[player.weapon]


func _list(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in items:
		parts.append("%d %s" % [items[item], data.item_name(item)])
	return ", ".join(parts)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _counts_of(inv: Inventory) -> Dictionary:
	var out := {}
	for item: String in inv.items():
		out[item] = inv.count(item)
	return out


## Picks up a death bag. Returns the items it held ({} if no such bag).
func take_bag(id: int) -> Dictionary:
	for i in bags.size():
		if bags[i]["id"] == id:
			var items: Dictionary = bags[i]["items"]
			inventory.give_all(items)
			bags.remove_at(i)
			return items
	return {}


func _on_player_respawned() -> void:
	player_pos = spawn_point


## Dying drops everything you carry in a bag where you fell.
func _on_player_died() -> void:
	var items := _counts_of(inventory)
	if not items.is_empty():
		inventory.take_all(items)
		drop_bag(player_pos, items)


func drop_bag(at: Vector3, items: Dictionary) -> void:
	bags.append({"id": _next_bag, "pos": at, "items": items})
	_next_bag += 1


## How far into the next tick we are (0..1), for smoothing visuals between ticks.
func alpha() -> float:
	return clampf(_accumulator / TICK, 0.0, 1.0)


## Building a machine or belt adds it to the factory.
func _on_piece_added(key: String) -> void:
	var piece: Dictionary = build.pieces[key]
	match build.kind_of(piece["id"]):
		"storage":
			storages[key] = Inventory.new()
		"turret":
			factory.add_turret(piece["id"], piece["cell"])
		"machine":
			factory.add_machine(piece["id"], piece["cell"], piece["side"])
		"belt":
			factory.add_belt(piece["cell"], piece["side"])


## Removing one hands back whatever it was holding, on top of the build refund.
## If zombies wrecked it, the contents are lost.
func _on_piece_removed(key: String, piece: Dictionary) -> void:
	var cans := power.take_refund(key)
	if cans > 0 and not piece.get("destroyed", false):
		inventory.add(data.buildables[piece["id"]]["fuel"], cans)  # unburnt fuel comes back
	if storages.has(key):
		var held := _counts_of(storages[key])
		storages.erase(key)
		if not held.is_empty():
			drop_bag(build.center_for(piece["id"], piece["cell"], piece["side"]) * Vector3(1, 0, 1), held)
	if build.is_object(piece["id"]) and build.kind_of(piece["id"]) in ["machine", "belt", "turret"]:
		var m: Factory.Machine = factory.machines.get(piece["cell"])
		var muffled := m != null and m.muffled
		var held := factory.remove_at(piece["cell"])
		if not piece.get("destroyed", false):
			inventory.give_all(held)
			if muffled:
				inventory.give_all(data.noise["muffler"]["cost"])


## Practising a skill; says so when it levels up. (A signal from Skills back to here would make a
## reference cycle and leak every SimWorld.)
func _practice(skill: String, action: String) -> void:
	var before := skills.level(skill)
	if skills.practice(skill, action) > before:
		add_message("%s is now level %d" % [skills.skill_name(skill), skills.level(skill)], 5.0)
