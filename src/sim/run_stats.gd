class_name RunStats
extends RefCounted
## What happened in one play session, for the session log (src/world/session_log.gd) that playtests
## leave behind: time played, deaths and what caused them, the Director's peak heat, what got built,
## kills, the loudest sounds, and a timeline of the first few real minutes. Since P3 also gear found by
## rarity, what you equipped and wore at the end, skill levels and perk points, shots per gun, the base-log
## events that mattered most while you were away, and the houses you went into.
## SimWorld calls the note_* functions where the events already happen; the world adds real time.
## While `muted` (the world building the town, a save or a demo base) nothing is recorded.

## The timeline only covers the first five real minutes, and stays short enough to read.
const TIMELINE_SECONDS := 300.0
const TIMELINE_MAX := 15
const DEATHS_SHOWN := 8
const AWAY_SHOWN := 5  # P3: the most important base-log events while you were far from your base
const GUNS_SHOWN := 3
## P3: how much a base-log event matters, by what its text says (first match wins; anything else is 1).
const AWAY_WEIGHTS := [["destroyed", 6], ["under attack", 5], ["coming from", 4], [" out of ", 4],
		["Old Pete", 3], ["worn out", 3], ["caught", 2], ["rang", 2], ["went off", 2]]

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
## V28: session-log breakdown by zombie type (the timeline already says "killed a crawler").
var kills_by_type: Dictionary = {}
var mufflers := 0
var used_crate := false
## {kind, loudness, when} or {} if nothing yet.
var loudest_sound: Dictionary = {}
var loudest_continuous: Dictionary = {}
## [real seconds, text, repeats]
var timeline: Array = []
## P3: rarity ("white", "blue", "yellow", "gold", "set") -> pieces found in searches and zombie drops.
var gear_found: Dictionary = {}
## P3: what you wore at the end ("Pipe (white)", ...); the session log fills it in just before writing.
var worn: PackedStringArray = []
## P3: skill id -> levels gained this sitting.
var levels_gained: Dictionary = {}
var perk_points_earned := 0
## P3: perk id -> ranks bought this sitting.
var perks_spent: Dictionary = {}
## V25: piece name -> times equipped this sitting (quick-equip and the inventory use the same sim path).
var gear_equipped: Dictionary = {}
## P3: gun name -> {"shots", "hits", "kills"}.
var guns: Dictionary = {}
## P3: the most important base-log events that happened more than the radio's range from you:
## [{"text", "when", "weight"}], best first, at most AWAY_SHOWN. away_total counts them all.
var away: Array = []
var away_total := 0
## P3: house names you walked into, in order.
var houses: Array = []


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


## V18: E opening a storage crate (the first hint asks for it), plus legacy/direct deposits.
func note_crate() -> void:
	if muted:
		return
	used_crate = true
	note("used the crate")


func note_kill(type: String = "") -> void:
	if muted:
		return
	kills += 1
	if type != "":
		kills_by_type[type] = int(kills_by_type.get(type, 0)) + 1


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


## P3: a gear piece of `rarity` turned up (a search or a zombie's drop).
func note_gear(rarity: String) -> void:
	if not muted:
		gear_found[rarity] = int(gear_found.get(rarity, 0)) + 1


## P3: `skill` reached `level` by practice.
func note_level(skill: String, level: int) -> void:
	if muted:
		return
	levels_gained[skill] = int(levels_gained.get(skill, 0)) + 1
	note("%s reached level %d" % [_words(skill), level])


func note_perk_points(n: int) -> void:
	if not muted:
		perk_points_earned += n


func note_perk(perk: String) -> void:
	if muted:
		return
	perks_spent[perk] = int(perks_spent.get(perk, 0)) + 1
	note("took the perk " + _words(perk))


func note_gear_equipped(piece_name: String) -> void:
	if muted:
		return
	gear_equipped[piece_name] = int(gear_equipped.get(piece_name, 0)) + 1
	note("equipped " + piece_name)


## P3: a shot from `gun` (its name); then note_gun_hit if the ray met a zombie.
func note_shot(gun: String) -> void:
	if not muted:
		_gun(gun)["shots"] += 1


func note_gun_hit(gun: String, killed: bool) -> void:
	if muted:
		return
	var g := _gun(gun)
	g["hits"] += 1
	if killed:
		g["kills"] += 1


func _gun(gun: String) -> Dictionary:
	if not guns.has(gun):
		guns[gun] = {"shots": 0, "hits": 0, "kills": 0}
	return guns[gun]


## P3: a base-log event far from you (the radio's "far"). Keeps the AWAY_SHOWN that matter most,
## the earliest first among equals.
func note_away(text: String, when: String) -> void:
	if muted:
		return
	away_total += 1
	var w := away_weight(text)
	var i := 0
	while i < away.size() and int(away[i]["weight"]) >= w:
		i += 1
	if i < AWAY_SHOWN:
		away.insert(i, {"text": text, "when": when, "weight": w})
		if away.size() > AWAY_SHOWN:
			away.pop_back()


static func away_weight(text: String) -> int:
	for pair: Array in AWAY_WEIGHTS:
		if pair[0] in text:
			return pair[1]
	return 1


## P3: you walked into house `house` (counted once each).
func note_house(house: String) -> void:
	if muted or house in houses:
		return
	houses.append(house)
	note("went into " + _words(house))


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
	if cause == "cold":
		return "froze to death"  # M16
	return "killed by a " + _words(cause)


## 125 seconds -> "2:05".
static func stamp(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


## The plain-words summary the session log writes (under 50 lines; the log adds a short header).
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
	var killed := PackedStringArray()
	var kill_types := kills_by_type.keys()
	kill_types.sort()
	for type: String in kill_types:
		var n: int = kills_by_type[type]
		killed.append("%d %s%s" % [n, _words(type), "" if n == 1 else "s"])
	out.append("Mufflers fitted: %d. Zombies killed: %d%s." % [mufflers, kills,
			(" (" + ", ".join(killed) + ")") if not killed.is_empty() else ""])
	out.append(_loud_line("Loudest one-off sound", loudest_sound))
	out.append(_loud_line("Loudest machine or engine", loudest_continuous))
	out.append_array(_p3_lines())
	out.append("First five minutes:")
	if timeline.is_empty():
		out.append("  (nothing notable)")
	for e: Array in timeline:
		out.append("  %s %s%s" % [stamp(e[0]), e[1], (" x%d" % e[2]) if e[2] > 1 else ""])
	return out


## P3/V25: gear, skills and perks, guns, events at the base while you were away, houses (at most 14 lines).
func _p3_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var found := PackedStringArray()
	for rarity: String in ["white", "blue", "yellow", "gold", "set"]:
		if gear_found.has(rarity):
			found.append("%d %s" % [gear_found[rarity], rarity])
	out.append(("Gear found: " + ", ".join(found) + ".") if not found.is_empty() else "Gear found: none.")
	out.append(("Wearing at the end: " + ", ".join(worn) + ".") if not worn.is_empty() else "Wearing at the end: nothing.")
	var equipped_parts := PackedStringArray()
	for piece_name: String in gear_equipped:
		var n := int(gear_equipped[piece_name])
		equipped_parts.append(piece_name + ((" x%d" % n) if n > 1 else ""))
	out.append(("Gear equipped: " + ", ".join(equipped_parts) + ".") if not equipped_parts.is_empty() else "Gear equipped: none.")
	var lv := PackedStringArray()
	for skill: String in levels_gained:
		lv.append("%s +%d" % [_words(skill), levels_gained[skill]])
	out.append(("Skill levels gained: " + ", ".join(lv) + ".") if not lv.is_empty() else "Skill levels gained: none.")
	var spent := 0
	var pk := PackedStringArray()
	for perk: String in perks_spent:
		spent += int(perks_spent[perk])
		pk.append(_words(perk) + ((" x%d" % perks_spent[perk]) if int(perks_spent[perk]) > 1 else ""))
	out.append("Perk points earned: %d, spent: %d%s." % [perk_points_earned, spent, (" (" + ", ".join(pk) + ")") if not pk.is_empty() else ""])
	if guns.is_empty():
		out.append("Firearms: never fired.")
	else:
		out.append("Firearms (shots, hits, kills):")
		var names := guns.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return int(guns[a]["shots"]) > int(guns[b]["shots"]))
		for i in mini(names.size(), GUNS_SHOWN):
			var g: Dictionary = guns[names[i]]
			out.append("  %s: %d, %d, %d" % [names[i], g["shots"], g["hits"], g["kills"]])
	if away_total == 0:
		out.append("At your base while you were away: nothing logged.")
	else:
		out.append("At your base while you were away (%d events, the %d that mattered most):" % [away_total, away.size()])
		for e: Dictionary in away:
			out.append("  %s: %s" % [e["when"], e["text"]])
	var hs := PackedStringArray()
	for h: String in houses:
		hs.append(_words(h))
	out.append(("Houses entered: %d (%s)." % [houses.size(), ", ".join(hs)]) if not hs.is_empty() else "Houses entered: 0.")
	return out


func _loud_line(label: String, s: Dictionary) -> String:
	if s.is_empty():
		return label + ": none"
	return "%s: %s, %d loud (%s)" % [label, _words(s["kind"]), roundi(float(s["loudness"])), s["when"]]


static func _words(id: String) -> String:
	return id.replace("_", " ")
