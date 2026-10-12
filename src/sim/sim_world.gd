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
var director: Director
## Short notices for the HUD ("Moaning to the north..."): {text, time_left}.
var messages: Array = []
var player := PlayerStats.new()
## Written by the world each frame: where the player stands and whether the flashlight is on.
var player_pos := Vector3.ZERO
var player_lit := false
var spawn_point := Vector3.ZERO
## Bags dropped where the player died: {id: int, pos: Vector3, items: {item: count}}.
var bags: Array = []
var _next_bag := 1
var ticks: int = 0
var paused := false
var _accumulator := 0.0


func _init(start_hour: float = 8.0, p_data: GameData = null, seed_value: int = 1) -> void:
	clock = GameClock.new(start_hour)
	data = p_data if p_data != null else GameData.load_default()
	build = BuildGrid.new(data)
	factory = Factory.new(data)
	horde = Horde.new(data, seed_value)
	noise = NoiseField.new(data, build)
	director = Director.new(data, seed_value)
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
	factory.tick(TICK)
	noise.refresh(factory, TICK)
	player.tick(TICK)
	var night := clock.is_night()
	var ctx := {"player_pos": player_pos, "player_dead": player.dead, "night": night,
			"player_lit": player_lit, "pieces": build.pieces, "noise": noise}
	for e: Dictionary in horde.tick(TICK, ctx):
		var z: ZombieBrain = horde.zombies.get(e["zombie"])
		if z == null:
			continue
		if e["target"] == "player":
			player.damage(float(z.stats["damage"]))
		elif build.pieces.has(e["target"]):
			var at := z.pos  # the noise is where the zombie stands, not inside the wall it hits
			noise.emit_kind(at, "zombie_bash")  # banging on your walls draws more of them
			if build.damage(e["target"], int(z.stats["structure_damage"])):
				noise.emit_kind(at, "wreck")
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
func make_noise(pos: Vector3, kind: String) -> void:
	noise.emit_kind(pos, kind)


## Fits a muffler to the machine at `cell`: -15 loudness, 10% slower. Returns "" or why not.
func fit_muffler(cell: Vector2i) -> String:
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
	var items := {}
	for item: String in inventory.items():
		items[item] = inventory.count(item)
	if not items.is_empty():
		inventory.take_all(items)
		bags.append({"id": _next_bag, "pos": player_pos, "items": items})
		_next_bag += 1


## How far into the next tick we are (0..1), for smoothing visuals between ticks.
func alpha() -> float:
	return clampf(_accumulator / TICK, 0.0, 1.0)


## Building a machine or belt adds it to the factory.
func _on_piece_added(key: String) -> void:
	var piece: Dictionary = build.pieces[key]
	match build.kind_of(piece["id"]):
		"machine":
			factory.add_machine(piece["id"], piece["cell"], piece["side"])
		"belt":
			factory.add_belt(piece["cell"], piece["side"])


## Removing one hands back whatever it was holding, on top of the build refund.
## If zombies wrecked it, the contents are lost.
func _on_piece_removed(_key: String, piece: Dictionary) -> void:
	if build.is_object(piece["id"]):
		var m: Factory.Machine = factory.machines.get(piece["cell"])
		var muffled := m != null and m.muffled
		var held := factory.remove_at(piece["cell"])
		if not piece.get("destroyed", false):
			inventory.give_all(held)
			if muffled:
				inventory.give_all(data.noise["muffler"]["cost"])
