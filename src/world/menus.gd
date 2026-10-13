class_name Menus
extends CanvasLayer
## Title screen, pause menu and settings panel, built in code. Runs while the game is paused.

signal new_game
signal continue_game
signal resume
signal save_requested
signal load_requested
signal quit_to_title
signal settings_changed

var _title: Control
var _heading: Label
var _stats_label: Label
var _flicker := 0.0
var _pause: Control
var _settings: Control
var _status: Label
var _continue_button: Button
var _load_button: Button
var _settings_back_to := ""  # "title" or "pause"


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title = _screen()
	_title.color = Color(0.02, 0.02, 0.03, 0.4)  # let the foggy dusk street show through
	_heading = _label("NOISE FLOOR", 96)
	var heading := _heading
	heading.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	heading.add_theme_constant_override("outline_size", 10)
	heading.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.85))
	_title.get_child(0).add_child(heading)
	_title.get_child(0).add_child(_label("Machines make noise. Noise draws the dead.", 22))
	_title.get_child(0).add_child(_spacer())
	_continue_button = _button(_title, "Continue", func() -> void: continue_game.emit())
	_button(_title, "New game", func() -> void: new_game.emit())
	_button(_title, "Settings", func() -> void: show_settings("title"))
	_button(_title, "Quit", func() -> void: get_tree().quit())

	_pause = _screen()
	_pause.get_child(0).add_child(_label("Paused", 48))
	_pause.get_child(0).add_child(_spacer())
	_button(_pause, "Resume", func() -> void: resume.emit())
	_button(_pause, "Save game", func() -> void: save_requested.emit())
	_load_button = _button(_pause, "Load last save", func() -> void: load_requested.emit())
	_button(_pause, "Settings", func() -> void: show_settings("pause"))
	_button(_pause, "Save and quit to title", func() -> void: quit_to_title.emit())
	_stats_label = _label("", 20)
	_stats_label.modulate = Color(1, 1, 1, 0.75)
	_pause.get_child(0).add_child(_stats_label)
	_status = _label("", 20)
	_pause.get_child(0).add_child(_status)

	_settings = _screen()
	_build_settings(_settings.get_child(0))
	hide_all()


## While paused the game itself isn't listening, so Esc to resume (or back out of settings) lives here.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("free_mouse"):
		return
	if _pause.visible:
		resume.emit()
		get_viewport().set_input_as_handled()
	elif _settings.visible:
		Settings.save_settings()
		if _settings_back_to == "title":
			show_title(not _continue_button.disabled)
		else:
			show_pause(not _load_button.disabled)
		get_viewport().set_input_as_handled()


func show_title(has_save: bool) -> void:
	hide_all()
	_continue_button.disabled = not has_save
	_title.visible = true


func show_pause(has_save: bool) -> void:
	hide_all()
	_load_button.disabled = not has_save
	_status.text = ""
	_pause.visible = true


func show_settings(back_to: String) -> void:
	_settings_back_to = back_to
	hide_all()
	_settings.visible = true


func set_status(text: String) -> void:
	_status.text = text


func hide_all() -> void:
	for c in [_title, _pause, _settings]:
		c.visible = false


func is_open() -> bool:
	return _title.visible or _pause.visible or _settings.visible


func title_open() -> bool:
	return _title.visible


func _build_settings(box: VBoxContainer) -> void:
	box.add_child(_label("Settings", 48))
	box.add_child(_spacer())
	var sens_label := _label("", 22)
	box.add_child(sens_label)
	var sens := _slider(0.2, 3.0, 0.1, Settings.mouse_sensitivity)
	box.add_child(sens)
	var vol_label := _label("", 22)
	box.add_child(vol_label)
	var vol := _slider(0.0, 1.0, 0.05, Settings.volume)
	box.add_child(vol)
	var day_label := _label("Day length (real minutes per in-game day)", 22)
	box.add_child(day_label)
	var days := OptionButton.new()
	for m: int in Settings.DAY_LENGTHS:
		days.add_item("%d minutes%s" % [m, " (default)" if m == 24 else ""])
	days.select(Settings.DAY_LENGTHS.find(Settings.day_minutes))
	days.custom_minimum_size = Vector2(420, 44)
	days.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(days)
	var full := CheckBox.new()
	full.text = "Fullscreen"
	full.button_pressed = Settings.fullscreen
	full.add_theme_font_size_override("font_size", 22)
	full.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(full)
	var refresh := func() -> void:
		sens_label.text = "Mouse sensitivity: %.1fx" % Settings.mouse_sensitivity
		vol_label.text = "Volume: %d%%" % roundi(Settings.volume * 100.0)
	refresh.call()
	sens.value_changed.connect(func(v: float) -> void:
		Settings.mouse_sensitivity = v
		refresh.call()
		settings_changed.emit())
	vol.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		refresh.call()
		settings_changed.emit())
	days.item_selected.connect(func(i: int) -> void:
		Settings.day_minutes = Settings.DAY_LENGTHS[i]
		settings_changed.emit())
	full.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		settings_changed.emit())
	box.add_child(_spacer())
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(420, 52)
	back.add_theme_font_size_override("font_size", 24)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		Settings.save_settings()
		if _settings_back_to == "title":
			show_title(not _continue_button.disabled)
		else:
			show_pause(not _load_button.disabled))
	box.add_child(back)


## A full-screen dark panel with a centred column.
func _screen() -> Control:
	var root := ColorRect.new()
	root.color = Color(0.02, 0.02, 0.03, 0.82)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)
	add_child(root)
	return root


func _button(screen: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(action)
	screen.get_child(0).add_child(b)
	return b


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(420, 32)
	s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return s


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 16)
	return c


## The title flickers now and then, like a failing sign.
func _process(delta: float) -> void:
	if _title == null or not _title.visible:
		return
	_flicker -= delta
	if _flicker <= 0.0:
		_flicker = randf_range(0.04, 0.12) if randf() < 0.3 else randf_range(0.8, 3.0)
		_heading.modulate.a = randf_range(0.55, 0.85) if randf() < 0.5 else 1.0


## The stats line under the pause menu: days, deaths, kills, noise made.
func set_stats(text: String) -> void:
	_stats_label.text = text
