class_name SessionLog
extends Node
## Leaves a plain-words summary of each play session in user://sessions/<YYYY-MM-DD_HHMM>.txt, so a
## playtest leaves evidence behind (what killed you, what you built, how loud it got) without anyone
## reading transcripts. One file per sitting, rewritten with the latest summary when the player dies and
## when the game quits (window closed, Quit on the title screen, or quitting to the title).
## The numbers come from sim.stats (RunStats); this node only writes them down.
## Off unless main.gd enables it (never in headless tests or screenshots); tests set path_override instead.

const FOLDER := "user://sessions"

## Survives scene reloads (loading a save, quitting to the title), so one sitting is one log.
static var carried: RunStats = null
static var _stamp := ""
static var _slot_name := ""

var sim: SimWorld
var enabled := false
## Tests write here instead of user://sessions (like GameSession.save_path).
var path_override := ""
var _deaths_written := 0
var _quit_written := false


static func prepare_slot() -> void:
	if _slot_name == GameSession.current_slot_name:
		return
	_slot_name = GameSession.current_slot_name
	carried = null
	_stamp = ""  # changing profiles starts a distinct, clearly named session log


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	_deaths_written = sim.stats.deaths.size()
	prepare_slot()
	if _stamp == "":
		var t := Time.get_datetime_dict_from_system()
		_stamp = "%04d-%02d-%02d_%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]


func path() -> String:
	return path_override if path_override != "" else "%s/%s.txt" % [FOLDER, _stamp]


func _process(_delta: float) -> void:
	if sim != null and sim.stats.deaths.size() > _deaths_written:
		_deaths_written = sim.stats.deaths.size()
		write()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_write_on_quit()


func _exit_tree() -> void:
	_write_on_quit()


func finish() -> void:
	_write_on_quit()


func _write_on_quit() -> void:
	if _quit_written or sim == null:
		return
	_quit_written = true
	if enabled:
		carried = sim.stats
	var written := write()
	if written != "" and enabled:
		print("Session log: %s — %s" % [GameSession.current_slot_name, ProjectSettings.globalize_path(written)])


## Writes the summary now. Returns the path written, or "" if logging is off or nothing was played yet.
func write() -> String:
	if sim == null or (path_override == "" and not enabled):
		return ""
	if path_override == "" and sim.stats.real_seconds < 1.0 and sim.stats.deaths.is_empty():
		return ""  # only looked at the title screen
	var p := path()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_warning("Session log: can't write %s (%s)" % [p, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string("\n".join(lines()) + "\n")
	f.close()
	return p


## The whole log: a short header, then RunStats' summary.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("Noise Floor session log, written %s" % Time.get_datetime_string_from_system(false, true))
	out.append("Build: " + GameSession.version_line())
	out.append("Started %s. Save slot: %s. World seed %d, game clock now %s." % [
			_stamp, GameSession.current_slot_name, sim.seed_value, sim.when_text()])
	out.append("")
	var worn := PackedStringArray()  # P3: what you wear (and hold) right now
	for slot: String in sim.gear.equipped:
		var value: Variant = sim.gear.equipped[slot]
		if value is Dictionary:
			var piece: Dictionary = value
			worn.append("%s: %s (%s)" % [InventoryScreen.SLOT_NAMES.get(slot, slot.capitalize()),
					piece.get("name", slot), piece.get("rarity", "white")])
		else:
			worn.append("%s: %s" % [InventoryScreen.SLOT_NAMES.get(slot, slot.capitalize()), sim.data.item_name(str(value))])
	sim.stats.worn = worn
	out.append_array(sim.stats.summary_lines())
	return out
