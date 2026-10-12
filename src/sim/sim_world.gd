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
var ticks: int = 0
var paused := false
var _accumulator := 0.0


func _init(start_hour: float = 8.0) -> void:
	clock = GameClock.new(start_hour)


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
