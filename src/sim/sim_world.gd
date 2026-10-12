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
var ticks: int = 0
var paused := false
var _accumulator := 0.0


func _init(start_hour: float = 8.0, p_data: GameData = null) -> void:
	clock = GameClock.new(start_hour)
	data = p_data if p_data != null else GameData.load_default()
	build = BuildGrid.new(data)
	factory = Factory.new(data)
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
func _on_piece_removed(_key: String, piece: Dictionary) -> void:
	if build.is_object(piece["id"]):
		inventory.give_all(factory.remove_at(piece["cell"]))
