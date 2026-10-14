class_name Menus
extends CanvasLayer
## Title screen, pause menu and settings panel, built in code. Runs while the game is paused.

signal new_game(slot: int, profile_name: String)
signal continue_game(slot: int)
signal delete_slot_requested(slot: int)
signal resume
signal save_requested
signal load_requested
signal base_log_requested  # M15
signal help_requested(from: String)  # P3: "Controls" on the title ("title") or the pause menu ("pause")
signal quit_to_title
signal settings_changed

var _title: Control
var _slot_picker: Control
var _slot_rows: VBoxContainer
var _slot_heading: Label
var _new_profile: Control
var _new_heading: Label
var _profile_name: LineEdit
var _confirm: ConfirmationDialog
var _heading: Label
var _version: Label  # the build being played, small in the bottom-right corner of the title screen
var _stats_label: Label
var _flicker := 0.0
var _pause: Control
var _settings: Control
var _status: Label
var _continue_button: Button
var _load_button: Button
var _settings_back_to := ""  # "title" or "pause"
var _slot_summaries: Array = []
var _slot_mode := "continue"
var _pending_action := ""
var _pending_slot := 0


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
	_continue_button = _button(_title, "Continue", func() -> void: open_slots(false))
	_button(_title, "New game", func() -> void: open_slots(true))
	_button(_title, "Settings", func() -> void: show_settings("title"))
	_button(_title, "Controls", func() -> void: help_requested.emit("title"))
	_button(_title, "Quit", func() -> void: get_tree().quit())
	_version = Label.new()
	_version.add_theme_font_size_override("font_size", 15)
	_version.modulate = Color(1, 1, 1, 0.6)
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title.add_child(_version)
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_slot_picker = _screen()
	_slot_heading = _label("Choose a save", 48)
	_slot_picker.get_child(0).add_child(_slot_heading)
	_slot_picker.get_child(0).add_child(_label("Each person gets their own slot.", 20))
	_slot_picker.get_child(0).add_child(_spacer())
	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 12)
	_slot_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_slot_picker.get_child(0).add_child(_slot_rows)
	_button(_slot_picker, "Back", func() -> void: show_title(_slot_summaries))

	_new_profile = _screen()
	_new_heading = _label("New game", 48)
	_new_profile.get_child(0).add_child(_new_heading)
	_new_profile.get_child(0).add_child(_label("Name this save (for example, Dad or Kaleb)", 20))
	_profile_name = LineEdit.new()
	_profile_name.name = "ProfileName"
	_profile_name.placeholder_text = "Slot name"
	_profile_name.max_length = 24
	_profile_name.custom_minimum_size = Vector2(420, 48)
	_profile_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_profile_name.add_theme_font_size_override("font_size", 22)
	_profile_name.text_submitted.connect(func(_text: String) -> void: start_new_profile())
	_new_profile.get_child(0).add_child(_profile_name)
	_button(_new_profile, "Start new game", start_new_profile)
	_button(_new_profile, "Back", func() -> void: open_slots(true))

	_confirm = ConfirmationDialog.new()
	_confirm.name = "SlotConfirmation"
	_confirm.title = "Confirm save slot"
	_confirm.confirmed.connect(confirm_pending)
	add_child(_confirm)

	_pause = _screen()
	_pause.get_child(0).add_child(_label("Paused", 48))
	_pause.get_child(0).add_child(_spacer())
	_button(_pause, "Resume", func() -> void: resume.emit())
	_button(_pause, "Save game", func() -> void: save_requested.emit())
	_load_button = _button(_pause, "Load last save", func() -> void: load_requested.emit())
	_button(_pause, "Base log (L)", func() -> void: base_log_requested.emit())
	_button(_pause, "Settings", func() -> void: show_settings("pause"))
	_button(_pause, "Controls (F1)", func() -> void: help_requested.emit("pause"))
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
			show_title(_slot_summaries)
		else:
			show_pause(not _load_button.disabled)
		get_viewport().set_input_as_handled()
	elif _new_profile.visible:
		open_slots(true)
		get_viewport().set_input_as_handled()
	elif _slot_picker.visible:
		show_title(_slot_summaries)
		get_viewport().set_input_as_handled()


func show_title(slots: Variant) -> void:
	if slots is Array:
		_slot_summaries = slots.duplicate(true)
	else:
		_slot_summaries = []
	hide_all()
	_continue_button.disabled = not _slot_summaries.any(
			func(slot: Dictionary) -> bool: return bool(slot.get("used", false)))
	_version.text = GameSession.version_line()
	_title.visible = true


## V26 title flow: Continue and New game both lead to the same three data-driven rows.
func open_slots(for_new_game: bool = false) -> void:
	_slot_mode = "new" if for_new_game else "continue"
	_slot_heading.text = "Choose a slot for a new game" if for_new_game else "Choose a save to continue"
	_rebuild_slot_rows()
	hide_all()
	_slot_picker.visible = true


func update_slots(slots: Array) -> void:
	_slot_summaries = slots.duplicate(true)
	if _slot_picker.visible:
		_rebuild_slot_rows()


func choose_slot(slot: int) -> void:
	var info := _slot_info(slot)
	if _slot_mode == "continue":
		if bool(info.get("used", false)):
			continue_game.emit(slot)
		return
	if bool(info.get("used", false)):
		_pending_action = "overwrite"
		_pending_slot = slot
		_confirm.dialog_text = "Replace '%s'?\nEverything currently in slot %d will be overwritten." % [
				str(info.get("name", "Slot %d" % slot)), slot]
		_confirm.popup_centered()
	else:
		_show_name_entry(slot)


func request_delete(slot: int) -> void:
	var info := _slot_info(slot)
	if not bool(info.get("used", false)):
		return
	_pending_action = "delete"
	_pending_slot = slot
	_confirm.dialog_text = "Delete '%s'?\nThis cannot be undone." % str(info.get("name", "Slot %d" % slot))
	_confirm.popup_centered()


## Public so the headless UI test can prove that no destructive signal fires before confirmation.
func confirm_pending() -> void:
	_confirm.hide()
	var action := _pending_action
	var slot := _pending_slot
	_pending_action = ""
	_pending_slot = 0
	if action == "overwrite":
		_show_name_entry(slot)
	elif action == "delete":
		delete_slot_requested.emit(slot)


func start_new_profile(_submitted: String = "") -> void:
	if _pending_slot < 1:
		return
	var slot := _pending_slot
	_pending_slot = 0
	new_game.emit(slot, GameSession.clean_name(_profile_name.text, slot))


func slot_text(slot: int) -> String:
	var button := _slot_rows.get_node_or_null("Slot%d" % slot) as Button
	return button.text if button != null else ""


func slot_picker_open() -> bool:
	return _slot_picker.visible


func new_profile_open() -> bool:
	return _new_profile.visible


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
	for c in [_title, _slot_picker, _new_profile, _pause, _settings]:
		c.visible = false


func is_open() -> bool:
	return _title.visible or _slot_picker.visible or _new_profile.visible or _pause.visible or _settings.visible


func title_open() -> bool:
	return _title.visible


## The build line in the title screen's corner (for tests).
func version_text() -> String:
	return _version.text


func _slot_info(slot: int) -> Dictionary:
	for info: Dictionary in _slot_summaries:
		if int(info.get("slot", 0)) == slot:
			return info
	return {"slot": slot, "used": false, "name": "", "summary": "Empty"}


func _show_name_entry(slot: int) -> void:
	_pending_action = ""
	_pending_slot = slot
	_new_heading.text = "New game — slot %d" % slot
	_profile_name.text = ""
	hide_all()
	_new_profile.visible = true
	_profile_name.grab_focus()


func _rebuild_slot_rows() -> void:
	for child: Node in _slot_rows.get_children():
		_slot_rows.remove_child(child)
		child.queue_free()
	for slot in range(1, GameSession.SLOT_COUNT + 1):
		var info := _slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var choose := Button.new()
		choose.name = "Slot%d" % slot
		choose.text = _slot_button_text(info)
		choose.custom_minimum_size = Vector2(650, 82)
		choose.add_theme_font_size_override("font_size", 20)
		choose.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choose.pressed.connect(choose_slot.bind(slot))
		row.add_child(choose)
		var remove := Button.new()
		remove.name = "Delete%d" % slot
		remove.text = "Delete"
		remove.custom_minimum_size = Vector2(110, 82)
		remove.add_theme_font_size_override("font_size", 18)
		remove.disabled = not bool(info.get("used", false))
		remove.pressed.connect(request_delete.bind(slot))
		row.add_child(remove)
		_slot_rows.add_child(row)


func _slot_button_text(info: Dictionary) -> String:
	var slot := int(info.get("slot", 0))
	if not bool(info.get("used", false)):
		return "Slot %d  —  Empty" % slot
	return "Slot %d  —  %s\n%s" % [slot, str(info.get("name", "Slot %d" % slot)),
			str(info.get("summary", ""))]


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
	box.add_child(_label("Graphics quality (lower it if the game stutters)", 22))
	var gfx := OptionButton.new()
	for q: String in Atmosphere.QUALITIES:
		gfx.add_item(q.capitalize() + (" (default)" if q == Atmosphere.DEFAULT_QUALITY else ""))
	gfx.select(Atmosphere.QUALITIES.find(Settings.graphics))
	gfx.custom_minimum_size = Vector2(420, 44)
	gfx.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(gfx)
	var full := CheckBox.new()
	full.text = "Fullscreen"
	full.button_pressed = Settings.fullscreen
	full.add_theme_font_size_override("font_size", 22)
	full.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(full)
	var bob := CheckBox.new()
	bob.text = "Head bob and camera shake"
	bob.button_pressed = Settings.head_bob
	bob.add_theme_font_size_override("font_size", 22)
	bob.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bob)
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
	gfx.item_selected.connect(func(i: int) -> void:
		Settings.graphics = Atmosphere.QUALITIES[i]
		settings_changed.emit())
	bob.toggled.connect(func(on: bool) -> void:
		Settings.head_bob = on
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
			show_title(_slot_summaries)
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
