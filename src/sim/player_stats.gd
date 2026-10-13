class_name PlayerStats
extends RefCounted
## The player's body: health, food, water, energy, stamina, bleeding, sleep, and the swing timer.
## All the rates live in data/survival.json (cfg). Every meter runs 0..100, and 100 is good.
##   food and water drain over time; at 0 you lose health until you eat or drink
##   energy drains while awake and refills while asleep in a bed; at 0 you can't sprint
##   stamina: sprinting and swinging use it; it refills after stamina_regen_delay seconds of rest
##   bleeding (from zombie hits) drains health until you use a bandage
##   carry_ratio (carried kg / limit, set by SimWorld): over 1 you're slower and tire faster;
##   at carry_no_sprint you can't sprint at all

signal died
signal respawned
signal woke

const RESPAWN_TIME := 3.0

var cfg: Dictionary = {}

var max_health := 100.0
var health := 100.0
var food := 100.0
var water := 100.0
var energy := 100.0
var stamina := 100.0
var bleeding := false
var asleep := false
var sprinting := false   # written by the world each frame
var carry_ratio := 0.0   # written by SimWorld each tick
## Stamina regen multiplier from Fitness and Second Wind (written by SimWorld each tick).
var stamina_regen_mult := 1.0
var dead := false
var respawn_timer := 0.0
var deaths := 0
## What hurt you last: a zombie type ("shambler"), "starvation", "dehydration", "bleeding" or "unknown".
## When health hits 0 this is what killed you.
var last_cause := "unknown"
var weapon := "pipe"
var swing_cooldown := 0.0
var _rested := 0.0  # seconds since stamina was last used


func _c(key: String, fallback: float = 0.0) -> float:
	return float(cfg.get(key, fallback))


func damage(amount: float, cause: String = "unknown") -> void:
	if dead or amount <= 0.0:
		return
	last_cause = cause
	if asleep:
		wake()
	health = maxf(0.0, health - amount)
	if health == 0.0:
		dead = true
		bleeding = false
		respawn_timer = RESPAWN_TIME
		deaths += 1
		died.emit()


## Starts a swing if the weapon is ready and there's stamina for it.
func try_swing(cooldown: float) -> bool:
	var cost := _c("swing_cost")
	if dead or asleep or swing_cooldown > 0.0 or stamina < cost:
		return false
	swing_cooldown = cooldown
	stamina -= cost
	_rested = 0.0
	return true


func can_sprint() -> bool:
	return not dead and not asleep and stamina > 1.0 and energy > 0.0 and carry_ratio < _c("carry_no_sprint", 1.5)


## Walking speed factor: slowed by carrying too much (never below carry_min_speed) and by exhaustion.
func speed_multiplier() -> float:
	var m := 1.0
	if carry_ratio > 1.0:
		m = maxf(_c("carry_min_speed", 0.5), 1.0 - (carry_ratio - 1.0) * _c("carry_slow_per_overload"))
	if energy <= 0.0:
		m *= 0.8
	return m


## Eat or drink something with these effects ({"food": 40, "water": 0}). Meters stop at 100.
func consume(item_food: float, item_water: float) -> void:
	food = minf(100.0, food + item_food)
	water = minf(100.0, water + item_water)


func sleep() -> void:
	if not dead:
		asleep = true


func wake() -> void:
	if asleep:
		asleep = false
		woke.emit()


func tick(dt: float) -> void:
	swing_cooldown = maxf(0.0, swing_cooldown - dt)
	if dead:
		respawn_timer -= dt
		if respawn_timer <= 0.0:
			_respawn()
		return
	food = maxf(0.0, food - _c("food_drain") * dt)
	water = maxf(0.0, water - _c("water_drain") * dt)
	if asleep:
		energy = minf(100.0, energy + _c("energy_sleep_gain") * dt)
		if energy >= 100.0:
			wake()
	else:
		energy = maxf(0.0, energy - _c("energy_drain") * dt)
	if sprinting and not asleep and can_sprint():
		stamina = maxf(0.0, stamina - _c("sprint_cost") * dt * maxf(1.0, carry_ratio))
		_rested = 0.0
	else:
		_rested += dt
		if _rested >= _c("stamina_regen_delay"):
			stamina = minf(100.0, stamina + _c("stamina_regen") * stamina_regen_mult * dt)
	var hurt := 0.0
	var cause := ""
	if food <= 0.0 or water <= 0.0:
		hurt += _c("starve_damage") * dt
		cause = "starvation" if food <= 0.0 else "dehydration"
	if bleeding:
		hurt += _c("bleed_damage") * dt
		cause = "bleeding"
	if hurt > 0.0:
		var was_asleep := asleep
		damage(hurt, cause)
		if was_asleep and not dead and not bleeding:
			asleep = true  # hunger alone doesn't wake you; a zombie or bleeding does


func _respawn() -> void:
	dead = false
	health = max_health
	var floor_value := _c("respawn_minimum", 50.0)
	food = maxf(food, floor_value)
	water = maxf(water, floor_value)
	energy = maxf(energy, floor_value)
	stamina = 100.0
	bleeding = false
	asleep = false
	respawned.emit()
