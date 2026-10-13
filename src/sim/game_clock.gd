class_name GameClock
extends RefCounted
## In-game time of day. Pure data + math (no nodes), so it is tested headlessly.
## Long days, short nights: by default the sun is up 05:00-21:00 (16 h) and night lasts 8 h.
## M16: with a calendar (data/seasons.json, set by SimWorld through set_calendar) the year is four seasons of
## days_per_season days each (summer, autumn, winter, spring) and sunrise and sunset follow the season:
## day 1 is the first day of summer (plus start_offset_days), so winter starts on day 15 by default.

const HOURS_PER_DAY := 24.0

## Real seconds per in-game day. 1440 = one real minute per in-game hour.
var seconds_per_day: float
var sunrise_hour: float = 5.0
var sunset_hour: float = 21.0
## Hours since midnight, 0 <= t < 24. 13.5 = 1:30 pm.
var time_of_day: float
## Since M16 setting it (the clock, --day, a save, a test) also sets this season's sunrise and sunset.
var day: int = 1:
	set(value):
		if value != day:
			day = value
			_apply_season()
## M16: data/seasons.json ({} = no calendar: always summer, the sun up 05:00-21:00).
var calendar: Dictionary = {}


func _init(start_hour: float = 8.0, p_seconds_per_day: float = 1440.0) -> void:
	time_of_day = fposmod(start_hour, HOURS_PER_DAY)
	seconds_per_day = p_seconds_per_day


## Moves time forward by real seconds (pass the frame or sim-tick delta).
func advance(real_seconds: float) -> void:
	var total := time_of_day + real_seconds / seconds_per_day * HOURS_PER_DAY
	day += int(total / HOURS_PER_DAY)
	time_of_day = fposmod(total, HOURS_PER_DAY)


## M16: real seconds per game-hour (60 at the default day length).
func seconds_per_hour() -> float:
	return seconds_per_day / HOURS_PER_DAY


## M16: uses this calendar (data/seasons.json) from now on.
func set_calendar(cfg: Dictionary) -> void:
	calendar = cfg
	_apply_season()


## M16: days into the year, 0-based (day 1 is 0, plus the calendar's start offset).
func day_of_year() -> int:
	if calendar.is_empty():
		return 0
	var per := int(calendar["days_per_season"])
	return posmod(day - 1 + int(calendar.get("start_offset_days", 0)), per * calendar["order"].size())


## M16: "summer", "autumn", "winter" or "spring".
func season() -> String:
	if calendar.is_empty():
		return "summer"
	return calendar["order"][day_of_year() / int(calendar["days_per_season"])]


## M16: 1..days_per_season: how far into its season today is.
func season_day() -> int:
	if calendar.is_empty():
		return 1
	return day_of_year() % int(calendar["days_per_season"]) + 1


## M16: this season's numbers from data/seasons.json ({} without a calendar).
func season_cfg() -> Dictionary:
	return calendar["seasons"][season()] if not calendar.is_empty() else {}


## M16: "Winter".
func season_name() -> String:
	return str(season_cfg().get("name", season().capitalize()))


func _apply_season() -> void:
	var s := season_cfg()
	if s.is_empty():
		return
	sunrise_hour = float(s["sunrise"])
	sunset_hour = float(s["sunset"])


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
