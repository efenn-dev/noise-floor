extends "res://test/base_test.gd"
## V1: the sky and air through the day (Atmosphere) and the graphics quality presets.


func test_sky_light_spans_night_to_day() -> void:
	near(Atmosphere.sky_light(-40.0), 0.0, "deep night is dark")
	near(Atmosphere.sky_light(80.0), 1.0, "midday is full light")
	var last := -1.0
	for e: int in range(-30, 91, 5):
		var l := Atmosphere.sky_light(float(e))
		check(l >= last, "sky light never drops as the sun climbs (%d deg)" % e)
		last = l


func test_dusk_keeps_a_glow() -> void:
	# 20:30 in summer: the sun is about 9 degrees up. The old curve (daylight = sin of the arc) gave 0.1 there,
	# which is why dusk went black; the sky should still be roughly half lit.
	var clock := GameClock.new(20.5)
	var elev := clock.sun_elevation_deg()
	check(elev > 0.0 and elev < 15.0, "the sun is low at 20:30 (%.1f deg)" % elev)
	check(Atmosphere.sky_light(elev) > 0.4, "the sky still glows at 20:30")
	check(Atmosphere.sky_light(elev) > clock.daylight() * 3.0, "much brighter than the old curve")
	check(Atmosphere.sun_strength(elev) > 0.6, "a low sun is still strong")


func test_warm_light_only_near_the_horizon() -> void:
	near(Atmosphere.warmth(70.0), 0.0, "no orange at midday")
	near(Atmosphere.warmth(0.0), 1.0, "full orange on the horizon")
	near(Atmosphere.warmth(-30.0), 0.0, "no orange in deep night")
	var sun_noon := Atmosphere.sun_color(70.0)
	var sun_low := Atmosphere.sun_color(2.0)
	check(sun_low.b < sun_noon.b - 0.3, "the setting sun is orange, not white")


func test_sky_colours_dark_at_night() -> void:
	var night: Array = Atmosphere.sky_colors(-50.0)
	var day: Array = Atmosphere.sky_colors(60.0)
	check((night[0] as Color).get_luminance() < 0.05, "night sky top is near black")
	check((day[0] as Color).get_luminance() > 0.3, "day sky top is bright")
	check((day[0] as Color).b > (day[0] as Color).r, "day sky is bluish")


func test_quality_presets() -> void:
	for q: String in Atmosphere.QUALITIES:
		var p: Dictionary = Atmosphere.preset(q)
		for key: String in ["ssao", "ssil", "volumetric", "shadow_atlas", "fog_volume", "soft_shadows"]:
			check(p.has(key), "%s preset has %s" % [q, key])
	eq(Atmosphere.valid_quality("ultra"), Atmosphere.DEFAULT_QUALITY, "unknown quality falls back to the default")
	eq(Atmosphere.valid_quality("low"), "low", "a known quality is kept")
	check(not Atmosphere.preset("low")["volumetric"], "low drops the volumetric fog")
	check(Atmosphere.preset("high")["ssil"], "high has bounce light")


func test_apply_quality_sets_environment() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	Atmosphere.setup_environment(env)
	Atmosphere.apply_quality(env, sun, "low")
	check(not env.ssao_enabled and not env.ssil_enabled and not env.volumetric_fog_enabled, "low turns effects off")
	Atmosphere.apply_quality(env, sun, "high")
	check(env.ssao_enabled and env.ssil_enabled and env.volumetric_fog_enabled, "high turns them on")
	check(not env.sdfgi_enabled, "never SDFGI (it blacked out houses at noon)")
	check(sun.light_angular_distance > 0.0, "high softens sun shadows")
	eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX, "AgX tone mapping")
	Atmosphere.apply_quality(env, sun, Atmosphere.DEFAULT_QUALITY)  # leave the engine-wide sizes at the default
	sun.free()
