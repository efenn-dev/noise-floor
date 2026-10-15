class_name Settings
extends RefCounted
## Player settings, kept in user://settings.cfg (separate from saves, so they apply to every game).

const PATH := "user://settings.cfg"
const DAY_LENGTHS := [24, 36, 48, 72]  # real minutes per in-game day

static var mouse_sensitivity := 1.0  # multiplier on the base sensitivity, 0.2..3
static var volume := 0.8             # 0..1
static var day_minutes := 24
static var fullscreen := false
static var head_bob := true  # V3: head bob, weapon sway and camera shake (off for anyone who gets motion sick)
static var show_objectives := true  # V25: the saved first-night checklist; O toggles it during play
static var graphics := Atmosphere.DEFAULT_QUALITY  # V1: "low", "medium" or "high" (Atmosphere.PRESETS)
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", 1.0)), 0.2, 3.0)
	volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
	day_minutes = int(cfg.get_value("game", "day_minutes", 24))
	if not day_minutes in DAY_LENGTHS:
		day_minutes = 24
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	head_bob = bool(cfg.get_value("video", "head_bob", true))
	show_objectives = bool(cfg.get_value("game", "show_objectives", true))
	graphics = Atmosphere.valid_quality(str(cfg.get_value("video", "graphics", Atmosphere.DEFAULT_QUALITY)))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("game", "day_minutes", day_minutes)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("video", "head_bob", head_bob)
	cfg.set_value("game", "show_objectives", show_objectives)
	cfg.save(PATH)


## Applies the settings that live outside the sim (sound, window).
static func apply_engine() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
