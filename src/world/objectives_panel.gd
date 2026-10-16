class_name ObjectivesPanel
extends PanelContainer
## V25: a compact view of Guidance. It owns no completion rules.

const GOLD := Color(0.95, 0.8, 0.55)
const DONE := Color(0.55, 0.85, 0.58)
const DIM := Color(0.72, 0.72, 0.72)

var sim: SimWorld
var force_visible := false
var suppressed := false
var _title: Label
var _lines: Array[Label] = []
var _detail: Label


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(350, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.035, 0.82)
	style.border_color = Color(0.4, 0.42, 0.44, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	_title = Label.new()
	_title.text = "FIRST NIGHT  ·  O hide"
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", GOLD)
	column.add_child(_title)
	for i in Guidance.COMPLETE:
		var line := Label.new()
		line.add_theme_font_size_override("font_size", 16)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(324, 0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line)
		_lines.append(line)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.add_theme_color_override("font_color", DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(324, 0)
	column.add_child(_detail)
	refresh()


func refresh() -> void:
	if sim == null:
		visible = false
		return
	var g := sim.guidance
	var first_night := g.active and not g.completed
	var feed := not first_night and g.feed_active and not g.feed_done  # F6: the third chapter (shown over the second)
	var defend := not first_night and not feed and g.defend_active and not g.defend_done  # F4: the second chapter
	visible = not suppressed and (first_night or defend or feed) and (Settings.show_objectives or force_visible)
	if not visible:
		return
	if feed:
		_show_feed(g)
		return
	if defend:
		_show_defend(g)
		return
	_title.text = "FIRST NIGHT  ·  O hide"
	var current := g.step(sim.build, sim.player_pos)
	var labels := ["Find food and water", "Find a bed (sleep when tired)",
			"Before dark (21:00): get inside a closed shelter with a bed", "Survive the night"]
	for i in _lines.size():
		var done := i < current
		_lines[i].text = ("✓ " if done else ("› " if i == current else "  ")) + labels[i]
		_lines[i].add_theme_color_override("font_color", DONE if done else (Color.WHITE if i == current else DIM))
	if current == 0:
		_detail.text = "%s Eat something    %s Drink something" % [_tick(g.ate), _tick(g.drank)]
	elif current == 2:
		var p := g.shelter_progress(sim.build)
		_detail.text = "%s Foundation  %s Bed inside  %s Walls %d  %s Closed door\nBuild it, or use a town house with intact windows" % [
				_tick(bool(p[0])), _tick(bool(p[1])), _tick(bool(p[4])), int(p[2]), _tick(bool(p[3]))]
	elif current == 3:
		_detail.text = "Night is 21:00 to dawn. Keep yourself and the shelter standing."
	else:
		_detail.text = "O hides objectives · change this in Settings"


## F4: "Defend your base": a turret, its ammo from a machine, fed by belt, a night held.
func _show_defend(g: Guidance) -> void:
	_title.text = "DEFEND YOUR BASE  ·  O hide"
	var current := g.defend_step(sim.build)
	var labels := ["Build a nail turret", "Make its ammo with a Press", "Feed the turret by belt (or a hopper)",
			"Hold a night: let the turret fight"]
	for i in _lines.size():
		var done := i < current
		_lines[i].text = ("✓ " if done else ("› " if i == current else "  ")) + labels[i]
		_lines[i].add_theme_color_override("font_color", DONE if done else (Color.WHITE if i == current else DIM))
	_detail.text = [
		"B, Defense group: a nail turret (10 metal plates, 20 nails). E on it loads nails from your pockets.",
		"A Press on a foundation, with power (generator, pole, gas). E loads it with metal plates; it makes nails. R switches what it makes: bolts, rifle rounds.",
		"Lay a belt from the Press's front to the turret (hold the button and drag). An ammo hopper in front of a turret feeds it too.",
		"Keep it loaded through the night. The louder your base, the bigger the horde that comes.",
	][mini(current, 3)]


## F6: "Live off your base": water by machine, cleaned, food grown, food canned.
func _show_feed(g: Guidance) -> void:
	_title.text = "LIVE OFF YOUR BASE  ·  O hide"
	var current := g.feed_step()
	var labels := ["Collect water with a machine", "Clean it in a purifier", "Grow food in a planter", "Can it in a canner"]
	for i in _lines.size():
		var done := bool(g.feed_met[i]) if i < g.feed_met.size() else false
		_lines[i].text = ("✓ " if done else ("› " if i == current else "  ")) + labels[i]
		_lines[i].add_theme_color_override("font_color", DONE if done else (Color.WHITE if i == current else DIM))
	_detail.text = [
		"B, Factory: a rain collector fills with rain on its own (no power). A water pump on a farm well is faster.",
		"A purifier on a foundation, with power. Feed it the dirty water (E, or a belt into its back).",
		"A planter: E loads seeds and dirty water. Every harvest gives a seed back, so one seed lasts for ever.",
		"A canner with power: two vegetables and a metal plate make two cans that never spoil. L shows what your base made.",
	][mini(current, 3)]


func text() -> String:
	var out := PackedStringArray()
	out.append(_title.text)
	for line: Label in _lines:
		out.append(line.text)
	if _detail.text != "":
		out.append(_detail.text)
	return "\n".join(out)


static func _tick(done: bool) -> String:
	return "✓" if done else "○"

