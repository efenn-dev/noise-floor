class_name Difficulty
extends RefCounted
## V29: the one place every difficulty-sensitive rule reads its data multiplier.

const DEFAULT := "normal"
const ORDER := ["easy", "normal", "hard"]
const REQUIRED := ["zombie_damage", "zombie_health", "zombie_count", "night_wave_size",
		"first_night_wave", "first_night_runners", "director_heat_gain", "needs_drain",
		"loot_abundance", "night_hearing", "night_speed_bonus"]

var data: Dictionary
var id := DEFAULT


func _init(p_data: Dictionary, chosen: String = DEFAULT) -> void:
	data = p_data
	set_id(chosen)


func set_id(chosen: String) -> void:
	id = chosen.to_lower() if data.has(chosen.to_lower()) else DEFAULT


func display_name() -> String:
	return str(data[id].get("name", id.capitalize()))


func multiplier(rule: String) -> float:
	return float(data[id].get(rule, 1.0))


func scale(rule: String, base: float) -> float:
	return base * multiplier(rule)


func count(rule: String, base: int, minimum: int = 0) -> int:
	return maxi(minimum, roundi(float(base) * multiplier(rule)))


func chance(rule: String, base: float) -> float:
	return clampf(scale(rule, base), 0.0, 1.0)


func first_night_size() -> int:
	return int(data[id]["first_night_wave"])


func first_night_runners() -> int:
	return int(data[id]["first_night_runners"])


func keeps_skills_on_death() -> bool:
	return bool(data[id].get("death_keeps_skills", true))


## Night hearing is the zombie type's day/night gap, scaled by difficulty. A lower threshold hears more.
func hearing(stats: Dictionary, night: bool) -> float:
	var day := float(stats["hearing_day"])
	if not night:
		return day
	var normal_bonus := day - float(stats["hearing_night"])
	return maxf(0.0, day - normal_bonus * multiplier("night_hearing"))


func move_speed(base: float, night: bool) -> float:
	if not night:
		return base
	return base * (1.0 + multiplier("night_speed_bonus"))
