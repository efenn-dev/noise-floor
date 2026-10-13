class_name SimWorld
extends RefCounted
## Owns all game-rule state and steps it on a fixed tick, separate from the frame rate.
## The world layer calls update(frame_delta) every frame; rules only ever see TICK-sized steps,
## so the same total time always gives the same result no matter how frames were sliced.

const TICK_RATE := 20
const TICK := 1.0 / TICK_RATE
## Cap per update so a long freeze (debugger, alt-tab) can't snowball into thousands of ticks.
const MAX_TICKS_PER_UPDATE := 10
## What the HUD says the first time you sit in a car you have no key for.
const NO_KEY_MESSAGE := "No key. The glovebox is searched from the trunk, or try the nearest house"

var clock: GameClock
var data: GameData
var inventory := Inventory.new()
var build: BuildGrid
var factory: Factory
var horde: Horde
var noise: NoiseField
var power: PowerGrid
var defense: Defense
## M15: sensors and their actions, floodlights, noisemakers, locked doors.
var automation: Automation
## M15: what happened at your base (the last 50 events with game time). L opens it.
var base_log: BaseLog
## M15: radio alerts sent to the HUD (far events while you carry a radio), newest last. For tests.
var radio_lines: Array = []
var _pete_busy := false
## The town's cars: position, fuel (gas cans, siphoned with G), damage, wrecks, and the one you drive.
var vehicles: Vehicles
## Skills that level by doing and the perks they earn (M12). Kept when you die.
var skills: Skills
## M13: your gear (weapon and things you wear, each piece rolled). Skills.bonus() includes it.
var gear: Gear
## M14: what's in your hands (melee or gun), spread, magazine and reloads.
var guns: Gunplay
## For the stats screen: zombies killed (by you, your turrets, traps or your car) and your deaths.
var tally := {"kills": 0, "deaths": 0}  # saved; `stats` below is the per-sitting session log
var _counted_dead: Dictionary = {}
var _day := 1
var director: Director
## Short notices for the HUD ("Moaning to the north..."): {text, time_left}.
var messages: Array = []
## Cars you've already been told have no key (see enter_car).
var _told_no_key := {}
var loot: Loot
## Storage crates: piece key -> Inventory.
var storages: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var player := PlayerStats.new()
## What happened this session (deaths, builds, loudest sounds...), for the playtest session log.
var stats := RunStats.new()
## Written by the world each frame: where the player stands and whether the flashlight is on.
var player_pos := Vector3.ZERO
var player_lit := false
## Written by the world each frame: moving while crouched (Sneaking xp near zombies that haven't noticed you).
var player_sneaking := false
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
	base_log = BaseLog.new(data, build)
	automation = Automation.new(data, build, power, noise)
	automation.base_log = base_log
	defense.power = power
	defense.base_log = base_log
	director.watch(build)  # M15: the Director's wall counts are cached until the grid changes
	skills = Skills.new(data)
	factory.skills = skills  # belt speed, craft speed, planter yield
	noise.skills = skills    # quieter machines (Dampened Gears)
	power.skills = skills    # quieter generators
	loot.skills = skills     # search time, Lucky Find
	gear = Gear.new(data)
	skills.gear = gear       # M13: every bonus(effect) query includes what you wear
	gear.give_start()        # the pipe, white, in the weapon slot
	guns = Gunplay.new(data, gear, skills)
	defense.gear = gear  # M15: turret suppressors and scopes are gear pieces
	_day = clock.day
	player.cfg = data.survival
	_rng.seed = hash([seed_value, "sim"])
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	build.piece_added.connect(_on_piece_added)
	build.piece_removed.connect(_on_piece_removed)
	build.piece_built.connect(_on_piece_built)


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
	base_log.now = when_text()
	stats.tick(TICK, clock.seconds_per_day)
	power.tick(TICK, clock.daylight())
	factory.tick(TICK)
	vehicles.tick(TICK)
	_tick_hotwire()
	noise.refresh(factory, TICK, power, vehicles)
	_note_noise()
	player.carry_ratio = carry_ratio()
	player.stamina_regen_mult = 1.0 + skills.bonus("stamina_regen")
	var sprinted := player.sprinting and not player.asleep and player.can_sprint()
	player.tick(TICK)
	guns.tick(TICK, inventory)
	if sprinted:
		_practice("fitness", "sprint_second", TICK)
	if player_sneaking and not player.dead and _unnoticed_zombie_near():
		_practice("sneaking", "sneak_second", TICK)
	var found := loot.tick(TICK, player_pos)
	if not found.is_empty():
		_practice("scavenging", "search")
		found["items"] = _rot_old_food(found["items"])
		inventory.give_all(found["items"])
		var names := PackedStringArray()
		if not found["items"].is_empty():
			names.append(_list(found["items"]))
		for piece: Dictionary in _search_gear(found):
			gear.pieces.append(piece)
			names.append(piece["name"])
			_announce(piece, "You find")
		var armoury := _search_guns(found)  # M14: guns, parts and ammo, on their own seeded stream
		if not armoury["items"].is_empty():
			inventory.give_all(armoury["items"])
			names.append(_list(armoury["items"]))
		for piece: Dictionary in armoury["pieces"]:
			gear.pieces.append(piece)
			names.append(piece["name"])
		add_message(("Found " + ", ".join(names)) if not names.is_empty() else "Nothing useful", 4.0)
	var night := clock.is_night()
	var ctx := {"player_pos": player_pos, "player_dead": player.dead, "night": night,
			"player_lit": player_lit or automation.in_light(player_pos), "pieces": build.pieces, "noise": noise}
	for e: Dictionary in horde.tick(TICK, ctx):
		var z: ZombieBrain = horde.zombies.get(e["zombie"])
		if z == null:
			continue
		if e["target"] == "scream":
			noise.emit(z.pos, float(z.stats["scream_loudness"]), "scream")  # pulls in everything nearby
		elif e["target"] == "player" and vehicles.driving != "":
			vehicles.damage(vehicles.driving, float(z.stats["damage"]))  # the car takes it while you're inside
			noise.emit_kind(z.pos, "zombie_bash")
		elif e["target"] == "player":
			player.damage(float(z.stats["damage"]) * maxf(0.0, 1.0 - skills.bonus("damage_cut")), z.type)
			if not player.dead and _rng.randf() < bleed_chance():
				if not player.bleeding:
					add_message("You're bleeding (H to bandage)", 4.0)
				player.bleeding = true
		elif build.pieces.has(e["target"]):
			var at := z.pos  # the noise is where the zombie stands, not inside the wall it hits
			noise.emit_kind(at, "zombie_bash")  # banging on your walls draws more of them
			var target: String = e["target"]
			if build.player_placeable(build.pieces[target]["id"]):  # M15: your own walls, doors, machines
				base_log.add_once("hit:" + target, float(data.defense["log"]["attack_every"]), "%s under attack: %s" % [
						base_log.place_name(target), _zombies_near(build.piece_center(target))], build.piece_center(target))
			if build.damage(target, int(z.stats["structure_damage"])):
				noise.emit_kind(at, "wreck")
	defense.tick(TICK, horde, noise)
	automation.tick(TICK, horde, night, defense.bells)
	base_log.tick(TICK)
	if ticks % TICK_RATE == 0:
		_watch_pete()
	var wave := director.tick(TICK, noise, night, horde)
	if stats.is_peak_heat(director.heat):
		stats.note_heat(director.heat, when_text())
	if not director.newly_unlocked.is_empty():
		add_message(director.newly_unlocked["message"], 8.0)
	_count_kills()
	if clock.day != _day:
		_day = clock.day
		_new_day()
	if not wave.is_empty():
		stats.note_wave(wave["kind"], wave["edge"])
		var what: String = {"wanderers": "Something is stirring", "group": "Moaning", "horde": "A horde is coming"}[wave["kind"]]
		add_message("%s from the %s..." % [what, wave["edge"]])
		var label: String = {"wanderers": "Wanderers", "group": "A group", "horde": "A horde"}[wave["kind"]]
		base_log.add("%s coming from the %s: %d zombies" % [label, wave["edge"], wave["size"]],
				Director.EDGES[Director.EDGE_NAMES.find(wave["edge"])])
	_radio()
	for m: Dictionary in messages:
		m["time_left"] -= TICK
	messages = messages.filter(func(m: Dictionary) -> bool: return m["time_left"] > 0.0)


## M15: the base log's new entries that happened more than radio "far" metres from you go to the HUD as
## "Radio: ..." lines, if you carry a radio.
func _radio() -> void:
	if base_log.fresh.is_empty():
		return
	var cfg: Dictionary = data.defense["radio"]
	var carried := carries_radio()
	for e: Dictionary in base_log.fresh:
		if carried and e["radio"] and _flat_dist(e["pos"], player_pos) > float(cfg["far"]):
			radio_lines.append(e["text"])
			add_message("Radio: " + e["text"], float(cfg["seconds"]))
	base_log.fresh = []
	if radio_lines.size() > 20:
		radio_lines = radio_lines.slice(radio_lines.size() - 20)


func carries_radio() -> bool:
	return inventory.count(str(data.defense["radio"]["item"])) > 0


func _zombies_near(at: Vector3) -> String:
	var n := 0
	var r := float(data.defense["log"]["attack_radius"])
	for id: int in horde.zombies:
		if not horde.zombies[id].is_dead() and _flat_dist(horde.zombies[id].pos, at) <= r:
			n += 1
	return "1 zombie" if n == 1 else "%d zombies" % n


## M15: the base log notes Old Pete leaving his spot (chasing, investigating or breaking something).
func _watch_pete() -> void:
	var busy := false
	var at := Vector3.ZERO
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.type == "old_pete" and not z.is_dead() and z.state in [ZombieBrain.State.CHASE, ZombieBrain.State.INVESTIGATE,
				ZombieBrain.State.BREAK, ZombieBrain.State.ATTACK]:
			busy = true
			at = z.pos
	if busy and not _pete_busy:
		base_log.add_once("pete", 120.0, "Old Pete is on the move", at)
	_pete_busy = busy


func add_message(text: String, seconds: float = 6.0) -> void:
	messages.append({"text": text, "time_left": seconds})


## "day 2 21:40": game time, for the session log.
func when_text() -> String:
	return "day %d %s" % [clock.day, clock.clock_text()]


## The session log keeps the loudest one-off sound (new this tick) and the loudest machine or engine.
func _note_noise() -> void:
	for s: Dictionary in noise.recent:
		if s["age"] == 0.0 and stats.is_loudest_sound(s["loudness"]):
			stats.note_sound(s["kind"], s["loudness"], when_text())
	for s: Dictionary in noise.continuous:
		if stats.is_loudest_continuous(s["loudness"]):
			stats.note_continuous(s["kind"], s["loudness"], when_text())


## A one-off sound from the player ("footstep_walk", "footstep_sprint", ...; see data/noise.json).
## Footsteps get louder when you carry more than your limit, and quieter with Sneaking and Soft Step.
## Each step under a heavy load (over heavy_load of your limit) trains Strength.
func make_noise(pos: Vector3, kind: String) -> void:
	noise.emit(pos, noise_loudness(kind), kind)
	if kind.begins_with("footstep") and carry_ratio() > float(data.skills["heavy_load"]):
		_practice("strength", "heavy_step")


## How loud one of your sounds is right now (footsteps depend on load, Sneaking and Soft Step).
func noise_loudness(kind: String) -> float:
	var loudness := float(data.noise["sounds"][kind])
	if kind.begins_with("footstep") and carry_ratio() > 1.0:
		loudness += float(data.survival["carry_footstep_bonus"])
	if kind == "footstep_walk":
		loudness -= skills.bonus("walk_quiet")
	elif kind == "footstep_sprint":
		loudness -= skills.bonus("sprint_quiet")
	if kind.begins_with("footstep") or kind == "melee_hit":
		loudness -= skills.bonus("gear_quiet")  # M13: "N quieter" on gear: your footsteps and swings
	loudness -= skills.bonus("quiet_all")  # M13: the whole Night Shift set: every noise you make
	return maxf(0.0, loudness)


## Chance a zombie's hit makes you bleed: bleed_chance, less 2 points per First Aid level.
func bleed_chance() -> float:
	return maxf(0.0, float(data.survival["bleed_chance"]) - skills.bonus("bleed_cut"))


func _unnoticed_zombie_near() -> bool:
	var reach := float(data.skills["sneak_range"])
	var calm := [ZombieBrain.State.IDLE, ZombieBrain.State.WANDER, ZombieBrain.State.INVESTIGATE]
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.state in calm and _flat_dist(z.pos, player_pos) <= reach:
			return true
	return false


# --- Carrying ---------------------------------------------------------------

## Carry limit in kg: carry_base, plus 3 kg per Strength level (skills.json), plus the best bag you're
## carrying (only one bag counts).
func carry_limit() -> float:
	var best := 0.0
	for item: String in inventory.items():
		best = maxf(best, data.item_value(item, "bag"))
	return float(data.survival["carry_base"]) + skills.bonus("carry_kg") + best


func carry_ratio() -> float:
	return carried_kg() / carry_limit()


## What you carry in kg: your pockets' items plus the gear pieces in them (worn gear doesn't count).
func carried_kg() -> float:
	return inventory.weight(data) + gear.weight()


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
	stats.note_crate()
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
	var was_muted := stats.muted
	stats.muted = true  # the game set this up, not the player
	var key := _place_start_stash(cell)
	stats.muted = was_muted
	return key


## Lays the town's houses (TownPlan.generate) into the build grid as if built: floors, walls, doors,
## windows and a bed per house, at full hp, free, and not counted as the player's builds.
## Containers aren't pieces: the world registers them (they need bodies). Returns pieces placed.
func place_town(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["pieces"]:
		build.restore(TownPlan.piece_key(p), {"id": p["id"], "cell": p["cell"], "side": p["side"],
				"hp": data.buildables[p["id"]]["hp"]})
		n += 1
	for b: Dictionary in plan["beds"]:
		build.restore(build.key_for("bed", b["cell"]), {"id": "bed", "cell": b["cell"], "side": b["side"],
				"hp": data.buildables["bed"]["hp"]})
		n += 1
	stats.muted = was_muted
	return n


## W1b: lays the factory hall (TownPlan.factory, in plan["factory"]) the same way: floor, walls, windows,
## and an open doorway on the road end. Returns pieces placed.
func place_factory(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["factory"]["pieces"]:
		build.restore(TownPlan.piece_key(p), {"id": p["id"], "cell": p["cell"], "side": p["side"],
				"hp": data.buildables[p["id"]]["hp"]})
		n += 1
	stats.muted = was_muted
	return n


## W1c: lays the town's furniture (plan["props"], and plan["factory"]["props"]) as pieces, like place_town.
## A spot is skipped if something already stands on that cell, its floor is gone, or a zombie stands in it:
## that only happens when furnishing a loaded pre-W1c save, where the player may have built in a house.
## Returns pieces placed.
func place_props(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["props"] + plan["factory"].get("props", []):
		var key := build.key_for(p["id"], p["cell"])
		if build.pieces.has(key) or not build.pieces.has("f:%d:%d" % [p["cell"].x, p["cell"].y]):
			continue
		var taken := false
		for z: ZombieBrain in horde.zombies.values():
			taken = taken or BuildGrid.world_to_cell(z.pos) == p["cell"]
		if taken:
			continue
		build.restore(key, {"id": p["id"], "cell": p["cell"], "side": p["side"], "hp": data.buildables[p["id"]]["hp"]})
		n += 1
	stats.muted = was_muted
	return n


## W1b: one shambler in each house the plan picked (plan["zombies"]), facing its front door. Only for a
## new game: a save keeps its zombies (house ones included) and brings them back itself.
func spawn_house_zombies(plan: Dictionary) -> Array:
	var ids: Array = []
	for hz: Dictionary in plan["zombies"]:
		var z := horde.spawn("shambler", hz["pos"])
		z.facing = hz["facing"]
		ids.append(z.id)
	return ids


## Where a town container stands: against its wall in its cell, on the floor (y = its middle).
static func town_container_pos(c: Dictionary, height: float = 1.6, depth: float = 0.7) -> Vector3:
	var g := BuildGrid.GRID
	var out := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][c["side"]] as Vector2
	var push := g / 2.0 - 0.1 - depth / 2.0 - 0.02  # to the wall's inner face
	return Vector3((c["cell"].x + 0.5) * g + out.x * push, 0.1 + height / 2.0, (c["cell"].y + 0.5) * g + out.y * push)


func _place_start_stash(cell: Vector2i) -> String:
	var kit := Inventory.new()
	kit.give_all(data.debug_kit)
	kit.give_all({"plank": 12, "nails": 8})  # pays for the foundation and crate themselves
	if build.place("foundation", cell, BuildGrid.Side.NORTH, kit) != "":
		return ""
	if build.place("storage", cell, BuildGrid.Side.WEST, kit) != "":
		return ""
	var key := build.key_for("storage", cell)
	storages[key].give_all(_counts_of(kit))
	storages[key].add(str(data.defense["radio"]["item"]), 1)  # M15: the handheld radio
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
	var bag := _bag_at_feet()
	bag["items"][item] = int(bag["items"].get(item, 0)) + n
	return msg


## M13: drops a gear piece from your pockets into the bag at your feet. Returns a message.
func drop_gear(uid: int) -> String:
	var piece := gear.take(uid)
	if piece.is_empty():
		return "Nothing to drop"
	_bag_at_feet()["gear"].append(piece)
	return "Dropped " + piece["name"]


## The bag lying within 1 m of you, or a new empty one there.
func _bag_at_feet() -> Dictionary:
	for bag: Dictionary in bags:
		if _flat_dist(bag["pos"], player_pos) <= 1.0:
			if not bag.has("gear"):
				bag["gear"] = []
			return bag
	drop_bag(player_pos, {})
	return bags.back()


func equip_gear(uid: int) -> String:
	var piece := gear.find(uid)
	var why := gear.equip(uid)
	return why if why != "" else "Equipped " + piece["name"]


func unequip_gear(slot: String) -> String:
	var piece: Dictionary = gear.equipped.get(slot, {})
	var why := gear.unequip(slot)
	return why if why != "" else "Took off " + piece["name"]


## Repairs a piece (carried or worn) to mint with one repair kit from your pockets. Trains Mechanics.
func repair_gear(uid: int) -> String:
	var why := gear.repair(uid, inventory)
	if why != "":
		return why
	_practice("mechanics", "repair")
	return "Repaired " + gear.find(uid)["name"]


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
	var heal := skills.bonus("bandage_heal")
	player.health = minf(player.max_health, player.health + heal)
	_practice("first_aid", "bandage")
	return "Bandaged" + ((" (+%d health)" % roundi(heal)) if heal > 0.0 else "")


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
	if automation.is_locked(key):
		return "Locked by a sensor until it clears"
	var open := build.toggle_door(key)
	noise.emit_kind(build.piece_center(key), "door")
	return "Door opened" if open else "Door closed"


## Repairs a piece with materials from your pockets and nearby crates. Returns "" or why not.
func repair(key: String) -> String:
	if not build.pieces.has(key):
		return "Nothing to repair"
	var why := build.repair(key, stock_at(build.piece_center(key)), skills.bonus("repair_discount"))
	if why == "":
		_practice("mechanics", "repair")
		_practice("building", "repair")
	return why


## What repairing piece `key` costs you now (Building makes it cheaper).
func repair_cost(key: String) -> Dictionary:
	return build.repair_cost(key, skills.bonus("repair_discount"))


# --- Automated defense (M15) ------------------------------------------------------

## E on a turret: loads its ammo (pockets and nearby crates), then attaches a suppressor or scope from your
## pockets to an empty slot. Returns a message.
func turret_interact(cell: Vector2i, at: Vector3) -> String:
	var t: Factory.Turret = factory.turrets.get(cell)
	if t == null:
		return ""
	var said := PackedStringArray()
	var moved := factory.hand_interact(cell, stock_at(at))
	if not moved["fed"].is_empty():
		said.append("Loaded " + _list(moved["fed"]))
	for slot: String in data.defense["turret_parts"]:
		if t.parts.has(slot):
			continue
		for p: Dictionary in gear.pieces:
			if gear.slot_of(p) == "part" and str(gear.part_def(p).get("slot", "")) == slot:
				t.parts[slot] = gear.take(int(p["uid"]))
				said.append("Fitted the " + String(p["name"]))
				break
	if said.is_empty():
		return "Nothing to load (needs %s)" % String(data.item_name(t.ammo_item)).to_lower()
	return " · ".join(said)


## Picks the action a sensor runs. "" or why not.
func set_sensor_action(key: String, action: String) -> String:
	return automation.set_action(key, action)


## E on a floodlight: only when a sensor says, or every night.
func toggle_floodlight(key: String) -> String:
	return automation.toggle_floodlight(key)


## E on a noisemaker: sets it off by hand (if it's charged and has power).
func fire_noisemaker(key: String) -> String:
	if not automation.noisemakers.has(key):
		return ""
	var n: Dictionary = automation.noisemakers[key]
	if n["blare"] > 0.0:
		return "It's already going"
	if n["recharge"] > 0.0:
		return "Recharging: %d s" % ceili(n["recharge"])
	return "Noisemaker going off" if automation.fire_noisemaker(key) else "No power for it"


## E on a sprung bear trap: sets it again.
func reset_trap(key: String) -> String:
	var why := defense.reset_trap(key)
	return "Bear trap set" if why == "" else why


## E on a machine: take what it made and load it from your pockets and nearby crates (Factory.hand_interact).
## Taking a planter's vegetables trains Farming.
func machine_interact(cell: Vector2i, at: Vector3) -> Dictionary:
	var moved := factory.hand_interact(cell, stock_at(at))
	var m: Factory.Machine = factory.machines.get(cell)
	if m != null and m.id == "planter" and not moved["took"].is_empty():
		_practice("farming", "harvest")
	return moved


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
	stats.note("siphoned gas from a " + str(vehicles.cars[id].get("type", "car")))
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
		if not vehicles.can_start(id, inventory) and not _told_no_key.has(id):
			_told_no_key[id] = true  # once per car, so it doesn't nag every time you sit in it
			add_message(NO_KEY_MESSAGE, 8.0)
		stats.note("got in a " + str(c.get("type", "car")))
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
	var killed := z.take_hit(damage, car["pos"], speed * 0.6)
	if killed:
		stats.note_kill()
		stats.note("ran over a " + z.type)
	return killed


# --- Searching ----------------------------------------------------------------

## Starts searching a container (a little noise). Returns "" or why not.
func search(id: String) -> String:
	var reason := loot.start(id, player_pos)
	if reason == "" and loot.progress == 0.0:
		noise.emit(loot.containers[id]["pos"], float(data.survival["search_noise"]), "search")
		stats.note("searched " + id.replace("_", " "))
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
		stats.note_muffler()
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
	stats.note_muffler()
	return ""


## Starts a melee swing if the weapon is ready and there's stamina (PlayerStats.try_swing). Swinging
## trains Strength. Returns true if it swung.
func swing() -> bool:
	if not player.try_swing(float(weapon_stats()["cooldown"])):
		return false
	_practice("strength", "swing")
	return true


## Melee damage of one body hit: the weapon's, plus Strength, Melee and Heavy Swing.
func melee_damage() -> float:
	return float(weapon_stats()["damage"]) * (1.0 + skills.bonus("melee_damage"))


## The player hits zombie `id` with their weapon (call after swing() succeeds and the swing
## connects). `head` doubles the damage. Returns true if it killed the zombie.
func hit_zombie(id: int, head: bool) -> bool:
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null:
		return false
	var w := weapon_stats()
	var dmg := melee_damage() * (float(w["head_multiplier"]) if head else 1.0)
	noise.emit(z.pos, noise_loudness("melee_hit"), "melee_hit")
	if gear.wear_weapon():
		add_message("Your %s is worn out: its bonuses stop until you repair it" % gear.weapon_name(), 5.0)
	var killed := z.take_hit(dmg, player_pos, float(w["knockback"]) * (1.0 + skills.bonus("knockback")))
	stats.note("hit a zombie")
	_practice("melee", "hit")
	if killed:
		_practice("melee", "kill")
		stats.note_kill()
		stats.note("killed a " + z.type)
	return killed


# --- Guns (M14) --------------------------------------------------------------------

## Q: swaps between your melee weapon and your gun. Returns a message.
func swap_hands() -> String:
	return guns.swap()


## Fires the gun in your hands: uses a round, kicks up the spread, wears the gun and its suppressor, and
## makes the shot's noise where you stand (loud: it raises heat and infamy like any one-off sound).
## Trains Firearms. Returns "" if it fired, otherwise why not. The world then raycasts and calls
## shoot_zombie() if the ray met a zombie.
func fire() -> String:
	var why := guns.can_fire()
	if why != "":
		return why
	var kind := guns.shot_kind()
	var loud := guns.shot_loudness()
	for piece: Dictionary in guns.fire():
		add_message("Your %s is worn out: its bonuses stop until you repair it" % piece["name"], 5.0)
	noise.emit(player_pos, maxf(0.0, loud - skills.bonus("quiet_all")), kind)
	_practice("firearms", "shot")
	stats.note("fired a gun")
	return ""


## A shot that the world's ray put on zombie `id`: it hits (P2: the ray in the spread cone is the only roll;
## distance, Firearms, the scope and recoil act through Gunplay.spread_deg), headshots double. Trains Firearms.
## Returns {"hit": bool, "killed": bool}.
func shoot_zombie(id: int, head: bool) -> Dictionary:
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null or z.is_dead():
		return {"hit": false, "killed": false}
	var dmg := guns.damage() * (float(data.guns["head_multiplier"]) if head else 1.0)
	var killed := z.take_hit(dmg, player_pos, float(guns.stats()["knockback"]))
	stats.note("shot a zombie")
	_practice("firearms", "hit")
	if killed:
		_practice("firearms", "kill")
		stats.note_kill()
		stats.note("killed a " + z.type)
	return {"hit": true, "killed": killed}


## R with a gun in hand: starts a reload (or switches ammo type). A reload click carries a few metres.
func reload() -> String:
	var msg := guns.start_reload(inventory)
	if guns.reloading > 0.0:
		noise.emit(player_pos, noise_loudness("reload"), "reload")
	return msg


## At a workbench: attach a part from your pockets to the gun you have equipped. Returns a message.
func attach_part(uid: int) -> String:
	var part := gear.find(uid)
	var why := gear.attach(gear.gun(), uid)
	return why if why != "" else "Attached %s to %s" % [part["name"], gear.gun_name()]


## At a workbench: take a part off your gun, back into your pockets (with any rounds that no longer fit).
func detach_part(slot: String) -> String:
	var part: Dictionary = gear.gun().get("parts", {}).get(slot, {})
	var out := gear.detach(gear.gun(), slot)
	if out["why"] != "":
		return out["why"]
	if int(out["rounds"]) > 0:
		inventory.add(gear.gun()["ammo"], int(out["rounds"]))
	return "Took off " + part["name"]


## The workbench's recipes (recipes.json "station": "workbench"), in file order.
func bench_recipes() -> Array:
	return data.recipes.keys().filter(func(r: String) -> bool: return data.recipes[r]["station"] == "workbench")


## "" if you can make `recipe` at a workbench at `at` now, otherwise why not (Gunsmith, materials).
func can_bench_craft(recipe: String, at: Vector3) -> String:
	var r: Dictionary = data.recipes.get(recipe, {})
	if r.is_empty() or r["station"] != "workbench":
		return "Not a workbench recipe"
	if r["perk"] != "" and skills.rank(r["perk"]) < 1:
		return "Needs the %s perk (Fighter tree, K)" % skills.perk_name(r["perk"])
	if not stock_at(at).has_all(r["in"]):
		return "Needs " + _list(r["in"])
	return ""


## Makes `recipe` by hand at a workbench at `at`, from your pockets and crates in reach: ammo goes in
## your pockets, a part (white, civilian, mint) too. Returns a message.
func bench_craft(recipe: String, at: Vector3) -> String:
	var why := can_bench_craft(recipe, at)
	if why != "":
		return why
	var r: Dictionary = data.recipes[recipe]
	stock_at(at).take_all(r["in"])
	inventory.give_all(r["out"])
	if r["gear"] != "":
		var piece := gear.make(r["gear"], "civilian", "white")
		gear.pieces.append(piece)
		return "Made " + piece["name"]
	return "Made " + _list(r["out"])


## Guns, parts and ammo a finished search turns up (guns.json "finds" for its table, plus a small
## police_find chance anywhere of a Police-tier gun or part). Its own seeded stream.
func _search_guns(found: Dictionary) -> Dictionary:
	var out := {"pieces": [], "items": {}}
	var table: Dictionary = data.guns["finds"].get(found.get("table", ""), {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, found.get("id", ""), "guns"])
	for kind: String in ["gun", "part"]:
		if rng.randf() < float(table.get(kind, 0.0)):
			out["pieces"].append(_found_gun(rng, kind, false))
	if rng.randf() < float(data.guns["police_find"]):
		out["pieces"].append(_found_gun(rng, "gun" if rng.randf() < 0.5 else "part", true))
	if rng.randf() < float(table.get("ammo", 0.0)):
		var span: Array = data.guns["ammo_found"]
		out["items"]["ammo_standard"] = rng.randi_range(int(span[0]), int(span[1]))
	return out


func _found_gun(rng: RandomNumberGenerator, kind: String, police: bool) -> Dictionary:
	var piece := gear.roll_gun_piece(rng, kind, police)
	if kind == "gun":
		var span: Array = data.guns["loaded_when_found"]
		piece["loaded"] = mini(rng.randi_range(int(span[0]), int(span[1])) * int(gear.gun_stats(piece)["magazine"]) / 2,
				int(gear.gun_stats(piece)["magazine"]))
	return piece


## The equipped weapon's stats (M13: from its gear base and tier; fists with nothing equipped).
func weapon_stats() -> Dictionary:
	return gear.weapon_stats()


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
			var items: Dictionary = bags[i]["items"].duplicate()
			inventory.give_all(items)
			for piece: Dictionary in bags[i].get("gear", []):
				gear.pieces.append(piece)
				items[piece["name"]] = 1  # so the "Took ..." message names it
			bags.remove_at(i)
			return items
	return {}


func _on_player_respawned() -> void:
	player_pos = spawn_point


## Dying drops everything you carry in a bag where you fell, gear in your pockets too.
## What you're wearing stays on you (M13).
func _on_player_died() -> void:
	stats.note_death(player.last_cause, when_text())
	tally["deaths"] += 1
	var items := _counts_of(inventory)
	var pieces := gear.pieces.duplicate()
	if not items.is_empty() or not pieces.is_empty():
		inventory.take_all(items)
		gear.pieces.clear()
		drop_bag(player_pos, items, pieces)


func drop_bag(at: Vector3, items: Dictionary, pieces: Array = []) -> void:
	bags.append({"id": _next_bag, "pos": at, "items": items, "gear": pieces})
	_next_bag += 1


## How far into the next tick we are (0..1), for smoothing visuals between ticks.
func alpha() -> float:
	return clampf(_accumulator / TICK, 0.0, 1.0)


## Building a machine or belt adds it to the factory.
func _on_piece_added(key: String) -> void:
	var piece: Dictionary = build.pieces[key]
	stats.note_built(piece["id"])
	match build.kind_of(piece["id"]):
		"storage":
			storages[key] = Inventory.new()
		"turret":
			factory.add_turret(piece["id"], piece["cell"])
		"machine":
			factory.add_machine(piece["id"], piece["cell"], piece["side"])
		"belt":
			factory.add_belt(piece["cell"], piece["side"])
		"hopper", "repair_station":
			factory.add_bin(piece["id"], piece["cell"], piece["side"])


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
	if piece.get("destroyed", false) and build.player_placeable(piece["id"]) and build.kind_of(piece["id"]) != "foundation":
		var at := build.center_for(piece["id"], piece["cell"], piece["side"])
		var dir := base_log.direction(at)
		var what: String = String(data.buildables[piece["id"]]["name"]).to_lower()
		base_log.add("%s destroyed" % ((dir.substr(0, 1).to_upper() + dir.substr(1) + " " + what) if dir != "middle"
				else String(data.buildables[piece["id"]]["name"])), at)
	if build.is_object(piece["id"]) and build.kind_of(piece["id"]) == "turret" and factory.turrets.has(piece["cell"]):
		var parts: Dictionary = factory.turrets[piece["cell"]].parts
		if not piece.get("destroyed", false):
			for slot: String in parts:
				gear.pieces.append(parts[slot])  # M15: a suppressor or scope comes back with the turret
	if build.is_object(piece["id"]) and build.kind_of(piece["id"]) in ["machine", "belt", "turret", "hopper", "repair_station"]:
		var m: Factory.Machine = factory.machines.get(piece["cell"])
		var muffled := m != null and m.muffled
		var held := factory.remove_at(piece["cell"])
		if not piece.get("destroyed", false):
			inventory.give_all(held)
			if muffled:
				inventory.give_all(data.noise["muffler"]["cost"])


## Practising a skill (`times` over, e.g. seconds of sprinting); says so when it levels up ("Strength 2")
## and when a perk point is earned. (A signal from Skills back to here would make a reference cycle and
## leak every SimWorld.)
func _practice(skill: String, action: String, times: float = 1.0) -> void:
	var before := skills.level(skill)
	var points := skills.perk_points
	if skills.practice(skill, action, times) > before:
		add_message("%s %d" % [skills.skill_name(skill), skills.level(skill)], 5.0)
	if skills.perk_points > points:
		add_message("Perk point earned: K to spend", 6.0)


## Placing a piece yourself trains Building (not the town, a save or a demo base being laid).
func _on_piece_built(_key: String) -> void:
	if not stats.muted:
		_practice("building", "place")


# --- The world gets worse (M11) -------------------------------------------------

## Each new day: fresh food rots, and about three weeks in the town's gas goes stale.
func _new_day() -> void:
	for piece: Dictionary in gear.wear_day():
		add_message("Your %s is worn out: its bonuses stop until you repair it" % piece["name"], 5.0)
	var rotted := _spoil(inventory)
	for key: String in storages:
		_spoil(storages[key])
	if rotted > 0:
		add_message("%d of your vegetables rotted" % rotted, 5.0)
	if clock.day >= int(data.survival["gas_stale_day"]) and vehicles.go_stale() > 0:
		add_message("The gas left in the town's cars has gone stale", 6.0)


## Fresh food (items.json "spoil_days" = how long it keeps, on average) rots into rotten food.
## Returns how many rotted.
func _spoil(inv: Inventory) -> int:
	var rotted := 0
	for item: String in inv.items():
		var days := data.item_value(item, "spoil_days")
		if days <= 0.0:
			continue
		var debt: float = float(inv.spoil_debt.get(item, 0.0)) + inv.count(item) / days
		var n := mini(floori(debt), inv.count(item))
		inv.spoil_debt[item] = debt - n
		if n > 0:
			inv.remove(item, n)
			inv.add("rotten_food", n)
			rotted += n
	return rotted


## Fresh food you find in the town has been sitting there since the outbreak: after a week it's rotten.
func _rot_old_food(items: Dictionary) -> Dictionary:
	if clock.day < int(data.survival["found_food_rots_day"]):
		return items
	var out := {}
	for item: String in items:
		var key := "rotten_food" if data.item_value(item, "spoil_days") > 0.0 else item
		out[key] = int(out.get(key, 0)) + int(items[item])
	return out


func _count_kills() -> void:
	for id: int in horde.zombies:
		if horde.zombies[id].is_dead() and not _counted_dead.has(id):
			_counted_dead[id] = true
			tally["kills"] += 1
			_zombie_drop(horde.zombies[id])


# --- Loot (M13) --------------------------------------------------------------------

## Gear a finished search turns up: the container's chance (gear.json "containers"), rolled again on
## a Lucky Find. Its own seeded stream, so the same seed finds the same gear.
func _search_gear(found: Dictionary) -> Array:
	var chance := float(data.gear["containers"].get(found.get("table", ""), 0.0))
	var out := []
	if chance <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, found["id"], "gear"])
	for i in (2 if found.get("lucky", false) else 1):
		if rng.randf() < chance:
			out.append(gear.roll_piece(rng, found["table"]))
	return out


## A dead zombie may drop a piece into a bag where it fell: zombie_drop chance by type (runners more),
## and a named zombie always drops its unique (Old Pete: Pete's Fire Axe).
func _zombie_drop(z: ZombieBrain) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "drop", z.id])
	var piece := {}
	var unique: String = data.gear["zombie_uniques"].get(z.type, "")
	if unique != "":
		piece = gear.roll_unique(rng, unique)
	elif rng.randf() < float(data.gear["zombie_drop"].get(z.type, data.gear["zombie_drop"]["default"])):
		piece = gear.roll_piece(rng, "zombie")
	if piece.is_empty():
		return
	var extra: Dictionary = data.guns["zombie_extra_uniques"].get(z.type, {})
	if not extra.is_empty():  # M14: Old Pete also carries his deer rifle and some rounds
		drop_bag(z.pos, extra.get("ammo", {}).duplicate(), [piece, gear.roll_unique(rng, extra["unique"])])
	else:
		drop_bag(z.pos, {}, [piece])
	var who: String = data.zombies[z.type]["name"] if unique != "" else "The zombie"
	if piece["rarity"] in ["gold", "set"]:
		add_message("%s drops something %s" % [who, Gear.rarity_word(piece["rarity"])], 6.0)
	else:
		add_message("%s dropped something" % who, 3.0)


## A message when you find a unique or set piece in a search.
func _announce(piece: Dictionary, who: String) -> void:
	if piece["rarity"] in ["gold", "set"]:
		add_message("%s something %s: %s" % [who, Gear.rarity_word(piece["rarity"]), piece["name"]], 6.0)


## M13: Old Pete, the named zombie, standing in the factory hall (TownPlan.factory()["pete"]).
func spawn_old_pete() -> ZombieBrain:
	var at: Dictionary = TownPlan.factory()["pete"]
	var z := horde.spawn("old_pete", at["pos"])
	z.facing = at["facing"]
	return z


## R on a machine that can make more than one thing (the Press: nails or repair kits): switches to the
## next recipe. What's waiting in its input, and a craft in progress, go back in your pockets.
## Returns a message ("" if the machine has only one recipe).
func cycle_recipe(cell: Vector2i) -> String:
	var m: Factory.Machine = factory.machines.get(cell)
	if m == null:
		return ""
	var ids: Array = data.buildables[m.id].get("recipes", [])
	if ids.size() < 2:
		return ""
	var back := m.input.duplicate()
	if m.crafting:
		for item: String in m.recipe["in"]:
			back[item] = int(back.get(item, 0)) + int(m.recipe["in"][item])
	inventory.give_all(back)
	m.input = {}
	m.crafting = false
	m.progress = 0.0
	factory.set_recipe(m, ids[(ids.find(m.recipe_id) + 1) % ids.size()])
	return "%s now makes %s" % [data.buildables[m.id]["name"], m.recipe["name"]]


## Days survived, deaths, kills and noise made (infamy), for the pause menu.
func stats_text() -> String:
	return "Day %d    Deaths %d    Zombies killed %d    Noise made %d" % [clock.day, tally["deaths"], tally["kills"],
			roundi(director.infamy)]
