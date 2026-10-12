class_name PlayerStats
extends RefCounted
## The player's health, melee swing timer, death and respawn. Hunger, thirst and stamina come in M6.

signal died
signal respawned

const RESPAWN_TIME := 3.0

var max_health := 100.0
var health := 100.0
var dead := false
var respawn_timer := 0.0
var deaths := 0
var weapon := "pipe"
var swing_cooldown := 0.0


func damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health == 0.0:
		dead = true
		respawn_timer = RESPAWN_TIME
		deaths += 1
		died.emit()


## Starts a swing if the weapon is ready. Returns false while still recovering from the last one.
func try_swing(cooldown: float) -> bool:
	if dead or swing_cooldown > 0.0:
		return false
	swing_cooldown = cooldown
	return true


func tick(dt: float) -> void:
	swing_cooldown = maxf(0.0, swing_cooldown - dt)
	if dead:
		respawn_timer -= dt
		if respawn_timer <= 0.0:
			dead = false
			health = max_health
			respawned.emit()
