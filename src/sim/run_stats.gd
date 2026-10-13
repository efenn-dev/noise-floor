class_name RunStats
extends RefCounted
## What happened in one play session, for the session log (src/world/session_log.gd) that playtests
## leave behind: time played, deaths and what caused them, the Director's peak heat, what got built,
## kills, the loudest sounds, and a timeline of the first few real minutes.
## SimWorld calls the note_* functions where the events already happen; the world adds real time.
## While `muted` (the world building the town, a save or a demo base) nothing is recorded.

## The timeline only covers the first five real minutes, and stays short enough to read.
const TIMELINE_SECONDS := 300.0
const TIMELINE_MAX := 15
const DEATHS_SHOWN := 8

var muted := false
## Real seconds of play (the world adds frame time while the game runs; not paused or in menus).
var real_seconds := 0.0
## In-game hours lived through (counted per tick, so a load or a day-length change doesn't skew it).
var game_hours := 0.0
## {cause: String, real: float, when: String}
var deaths: Array = []
var peak_heat := 0.0
var peak_heat_when := ""
var waves := 0
## Piece id ("wall", "smelter") -> how many the player built.
var built: Dictionary = {}
var kills := 0
var mufflers := 0
var used_crate := false
## {kind, loudness, when} or {} if nothing yet.
var loudest_sound: Dictionary = {}
var loudest_continuous: Dictionary = {}
## [real seconds, text, repeats]
var timeline: Array = []


func add_real_time(seconds: float) -> void:
	if not muted:
		real_seconds += seconds


## One sim tick of `dt` seconds on a clock running `seconds_per_day`.
func tick(dt: float, seconds_per_day: float) -> void:
	if not muted:
		game_hours += dt / seconds_per_day * GameClock.HOURS_PER_DAY


## A notable action, for the first-five-minutes timeline. The same action twice in a row is counted, not repeated.
func note(text: String) -> void:
	if muted or real_seconds >= TIMELINE_SECONDS:
		return
	if not timeline.is_empty() and timeline[-1][1] == text:
		timeline[-1][2] += 1
		return
	if timeline.size() < TIMELINE_MAX:
		timeline.append([real_seconds, text, 1])


func note_built(id: String) -> void:
	if muted:
		return
	built[id] = int(built.get(id, 0)) + 1
	note("built a " + _words(id))


func note_death(cause: String, when: String) -> void:
	if muted:
		return
	deaths.append({"cause": cause, "real": real_seconds, "when": when})
	note("died (%s)" % cause_text(cause))


## E on a storage crate (the first hint asks for it).
func note_crate() -> void:
	if muted:
		return
	used_crate = true
	note("used the crate")


func note_kill() -> void:
	if not muted:
		kills += 1


func note_muffler() -> void:
	if muted:
		return
	mufflers += 1
	note("fitted a muffler")


func note_wave(kind: String, edge: String) -> void:
	if muted:
		return
	waves += 1
	note("the Director sent %s from the %s" % [kind, edge])


## True if `heat` beats the peak so far (so the caller only builds the time text when it matters).
func is_peak_heat(heat: float) -> bool:
	return not muted and heat > peak_heat


func note_heat(heat: float, when: String) -> void:
	if is_peak_heat(heat):
		peak_heat = heat
		peak_heat_when = when


func is_loudest_sound(loudness: float) -> bool:
	return not muted and (loudest_sound.is_empty() or loudness > float(loudest_sound["loudness"]))


func note_sound(kind: String, loudness: float, when: String) -> void:
	if is_loudest_sound(loudness):
		loudest_sound = {"kind": kind, "loudness": loudness, "when": when}


func is_loudest_continuous(loudness: float) -> bool:
	return not muted and (loudest_continuous.is_empty() or loudness > float(loudest_continuous["loudness"]))


func note_continuous(kind: String, loudness: float, when: String) -> void:
	if is_loudest_continuous(loudness):
		loudest_continuous = {"kind": kind, "loudness": loudness, "when": when}


## "killed by a shambler", "starvation", ...
static func cause_text(cause: String) -> String:
	if cause in ["starvation", "dehydration", "bleeding", "unknown"]:
		return cause
	return "killed by a " + _words(cause)


## 125 seconds -> "2:05".
static func stamp(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


## The plain-words summary the session log writes (under 30 lines; the log adds a short header).
func summary_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var days := floori(game_hours / 24.0)
	var minutes := int(game_hours * 60.0) % (24 * 60)
	out.append("Real time played: %s (m:ss). Game time lived through: %d d %d:%02d (days, h:mm)." % [
			stamp(real_seconds), days, floori(minutes / 60.0), minutes % 60])
	out.append("Deaths: %d" % deaths.size())
	for i in mini(deaths.size(), DEATHS_SHOWN):
		var d: Dictionary = deaths[i]
		out.append("  %d. at %s real (%s): %s" % [i + 1, stamp(d["real"]), d["when"], cause_text(d["cause"])])
	if deaths.size() > DEATHS_SHOWN:
		out.append("  ...and %d more" % (deaths.size() - DEATHS_SHOWN))
	if peak_heat > 0.0:
		out.append("Director heat peaked at %d (%s). Waves sent: %d." % [roundi(peak_heat), peak_heat_when, waves])
	else:
		out.append("Director heat never rose. Waves sent: %d." % waves)
	var parts := PackedStringArray()
	var total := 0
	for id: String in built:
		parts.append("%d %s" % [built[id], _words(id)])
		total += int(built[id])
	out.append(("Built %d piece%s: %s." % [total, "" if total == 1 else "s", ", ".join(parts)]) if total > 0 else "Built nothing.")
	out.append("Mufflers fitted: %d. Zombies killed: %d." % [mufflers, kills])
	out.append(_loud_line("Loudest one-off sound", loudest_sound))
	out.append(_loud_line("Loudest machine or engine", loudest_continuous))
	out.append("First five minutes:")
	if timeline.is_empty():
		out.append("  (nothing notable)")
	for e: Array in timeline:
		out.append("  %s %s%s" % [stamp(e[0]), e[1], (" x%d" % e[2]) if e[2] > 1 else ""])
	return out


func _loud_line(label: String, s: Dictionary) -> String:
	if s.is_empty():
		return label + ": none"
	return "%s: %s, %d loud (%s)" % [label, _words(s["kind"]), roundi(float(s["loudness"])), s["when"]]


static func _words(id: String) -> String:
	return id.replace("_", " ")
