class_name GameClock
extends RefCounted
## In-game time of day. Pure data + math (no nodes), so it is tested headlessly.
## Long days, short nights: by default the sun is up 05:00-21:00 (16 h) and night lasts 8 h.

const HOURS_PER_DAY := 24.0

## Real seconds per in-game day. 1440 = one real minute per in-game hour.
var seconds_per_day: float
var sunrise_hour: float = 5.0
var sunset_hour: float = 21.0
## Hours since midnight, 0 <= t < 24. 13.5 = 1:30 pm.
var time_of_day: float
var day: int = 1


func _init(start_hour: float = 8.0, p_seconds_per_day: float = 1440.0) -> void:
	time_of_day = fposmod(start_hour, HOURS_PER_DAY)
	seconds_per_day = p_seconds_per_day


## Moves time forward by real seconds (pass the frame or sim-tick delta).
func advance(real_seconds: float) -> void:
	var total := time_of_day + real_seconds / seconds_per_day * HOURS_PER_DAY
	day += int(total / HOURS_PER_DAY)
	time_of_day = fposmod(total, HOURS_PER_DAY)


func is_night() -> bool:
	return time_of_day < sunrise_hour or time_of_day >= sunset_hour


## Where the sun is on its loop: 0 = rising, 90 = highest, 180 = setting, 180..360 = below the horizon.
func sun_arc_deg() -> float:
	if not is_night():
		return (time_of_day - sunrise_hour) / (sunset_hour - sunrise_hour) * 180.0
	var night_length := HOURS_PER_DAY - (sunset_hour - sunrise_hour)
	return 180.0 + fposmod(time_of_day - sunset_hour, HOURS_PER_DAY) / night_length * 180.0


## Sun height above the horizon in degrees (-90..90). Negative means night.
func sun_elevation_deg() -> float:
	return 90.0 * sin(deg_to_rad(sun_arc_deg()))


## 0 at night, rising to 1 when the sun is highest.
func daylight() -> float:
	return maxf(0.0, sin(deg_to_rad(sun_arc_deg())))


## "HH:MM" for the HUD.
func clock_text() -> String:
	var hours := int(time_of_day)
	var minutes := int((time_of_day - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]
