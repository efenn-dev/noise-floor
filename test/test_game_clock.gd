extends "res://test/base_test.gd"


func test_starts_at_requested_hour() -> void:
	var c := GameClock.new(8.0)
	near(c.time_of_day, 8.0, "starts at 08:00")
	eq(c.day, 1, "starts on day 1")
	eq(c.clock_text(), "08:00", "HUD text")


func test_one_real_minute_is_one_hour_by_default() -> void:
	var c := GameClock.new(8.0)
	c.advance(60.0)
	near(c.time_of_day, 9.0, "60 real seconds = 1 in-game hour")


func test_rolls_over_midnight() -> void:
	var c := GameClock.new(23.0, 2400.0)  # 100 real seconds per hour
	c.advance(200.0)
	near(c.time_of_day, 1.0, "23:00 + 2 h = 01:00")
	eq(c.day, 2, "midnight starts day 2")


func test_multi_day_jump() -> void:
	var c := GameClock.new(12.0, 24.0)  # 1 real second per hour
	c.advance(72.0)
	eq(c.day, 4, "three full days later is day 4")
	near(c.time_of_day, 12.0, "same time of day")


func test_night_is_short() -> void:
	check(not GameClock.new(12.0).is_night(), "noon is day")
	check(not GameClock.new(5.0).is_night(), "sunrise counts as day")
	check(GameClock.new(21.0).is_night(), "sunset starts the night")
	check(GameClock.new(2.0).is_night(), "02:00 is night")


func test_sun_path() -> void:
	near(GameClock.new(5.0).sun_elevation_deg(), 0.0, "sun on the horizon at sunrise")
	near(GameClock.new(13.0).sun_elevation_deg(), 90.0, "sun highest halfway through the day")
	near(GameClock.new(21.0).sun_elevation_deg(), 0.0, "sun on the horizon at sunset")
	near(GameClock.new(1.0).sun_elevation_deg(), -90.0, "sun lowest halfway through the night")
	near(GameClock.new(1.0).daylight(), 0.0, "no daylight at night")
	near(GameClock.new(13.0).daylight(), 1.0, "full daylight at the top of the day")
