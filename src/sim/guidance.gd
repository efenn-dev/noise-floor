class_name Guidance
extends RefCounted
## V25: first-hour progress owned by the sim. The world only draws this state.
## Old/non-guided games leave `active` false. A new game starts it from main.gd, and saves keep it.

const COMPLETE := 4
const CELL_DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var active := false
var completed := false
var start_day := 1
var ate := false
var drank := false
var bed_found := false
var saw_night := false
var night_failed := false
var night_deaths := 0
var survived_night := false

## F4 (the loop closes): "Defend your base", the second chapter. It starts once the first night's goals are done (or,
## in a game from before the guidance, from day 2) and leads from a turret to a factory that feeds it: build a turret,
## make its ammo with a machine (a Press makes nails, bolts and rifle rounds), feed a turret by belt or hopper, and
## hold a night (a turret kills a zombie in the dark and a turret still stands at dawn). Saved.
const DEFEND_STEPS := 4
const DEFEND_HOWTO := [
	"New goal: defend your base. Build a nail turret (B, Defense). O shows the goals.",
	"Turret built. Now make its ammo with a Press: load it with metal plates (it makes nails; R switches what it makes).",
	"Ammo made. Now feed the turret by belt from the Press's front, or put an ammo hopper in front of it.",
	"Fed by belt. Now hold a night: keep it loaded and let it fight. A louder base draws a bigger horde.",
]
const DEFEND_DONE := "Your base defends itself. The bigger your factory, the louder it is: expect bigger hordes."
var defend_active := false
var defend_done := false
var defend_ammo_made := false
var defend_fed := false
var defend_held := false
var defend_night_kills := -1  # turret kills when tonight began; -1 when it isn't watching a night
var defend_told := -1  # the last goal it said how to do (so a goal met between ticks still gets its message)

## F6 (compact and deep): "Live off your base", the third chapter. It starts when "Defend your base" is done, or from
## FEED_START_DAY in any game (so a player still on the defence gets it too), and walks a food and water chain: collect
## water with a machine (rain collector or well pump), clean it (purifier or water tap), grow food (planter), can it
## (canner). A goal is met the first time a machine makes that; goals met early count. Saved.
const FEED_STEPS := 4
const FEED_START_DAY := 5
const FEED_RECIPES := [["collect_rain", "pump_water"], ["purify_water", "tap_water"], ["grow_vegetables", "grow_cotton"],
		["can_food", "pack_bandages"]]
const FEED_HOWTO := [
	"New goal: live off your base. Collect water with a machine: a rain collector (B, Factory) or a water pump on a farm well.",
	"Water collected. Now clean it: a purifier (it needs power) turns dirty water into clean water.",
	"Clean water made. Now grow food: a planter with seeds and dirty water. Every harvest gives a seed back.",
	"Food growing. Now can it: a canner turns two vegetables and a metal plate into canned food that keeps.",
]
const FEED_DONE := "Your base feeds you. L shows what it made today. R on a planter grows cotton; R on the canner packs it into bandages."
var feed_active := false
var feed_done := false
var feed_met: Array = [false, false, false, false]
var feed_told := -1

## The most recent acquired piece that was better when found. It is checked again before wearing.
var better_gear_uid := -1
var better_gear_seconds := 0.0


func start(day: int, deaths: int = 0) -> void:
	active = true
	completed = false
	start_day = day
	ate = false
	drank = false
	bed_found = false
	saw_night = false
	night_failed = false
	night_deaths = deaths
	survived_night = false
	clear_better_gear()


func note_consumed(food: float, water: float) -> void:
	ate = ate or food > 0.0
	drank = drank or water > 0.0


func note_bed() -> void:
	bed_found = true


func note_better_gear(uid: int) -> void:
	better_gear_uid = uid
	better_gear_seconds = 8.0


func clear_better_gear() -> void:
	better_gear_uid = -1
	better_gear_seconds = 0.0


## Called once per fixed sim tick. Shelter progress is derived, never copied into another rule state.
func tick(dt: float, clock: GameClock, build: BuildGrid, deaths: int, player_pos: Vector3 = Vector3.INF) -> void:
	better_gear_seconds = maxf(0.0, better_gear_seconds - dt)
	if not active or completed:
		return
	if clock.is_night():
		if not night_failed:  # After a death, wait for daylight; the next night must be survived from its beginning.
			if not saw_night:
				saw_night = true
				night_deaths = deaths
			elif deaths != night_deaths:
				saw_night = false
				night_failed = true
				night_deaths = deaths
	else:
		if saw_night and clock.day > start_day and deaths == night_deaths:
			survived_night = true
		saw_night = false
		night_failed = false
	update_completion(build, player_pos)


func step(build: BuildGrid, player_pos: Vector3 = Vector3.INF) -> int:
	if not ate or not drank:
		return 0
	if not bed_found:
		return 1
	if not shelter_complete(build, player_pos):
		return 2
	if not survived_night:
		return 3
	return COMPLETE


func update_completion(build: BuildGrid, player_pos: Vector3 = Vector3.INF) -> void:
	if active and survived_night and shelter_complete(build, player_pos) and ate and drank and bed_found:
		completed = true


## F4: the "Defend your base" chapter. Call every tick; returns a message when it starts or a goal is met ("" else).
func tick_defend(clock: GameClock, build: BuildGrid, factory: Factory) -> String:
	if defend_done:
		return ""
	if not defend_active:
		if (active and completed) or (not active and clock.day >= 2):
			defend_active = true
			defend_told = defend_step(build)
			return DEFEND_HOWTO[defend_told]
		return ""
	if not defend_ammo_made:
		defend_ammo_made = _turret_ammo_made(factory)
	if not defend_fed:
		for t: Factory.Turret in factory.turrets.values():
			defend_fed = defend_fed or t.fed > 0
	var kills := 0
	for t: Factory.Turret in factory.turrets.values():
		kills += t.kills
	if clock.is_night():
		if defend_night_kills < 0:
			defend_night_kills = kills
	elif defend_night_kills >= 0:
		if kills > defend_night_kills and build.first_of_kind("turret") != "":
			defend_held = true
		defend_night_kills = -1
	var now := defend_step(build)
	if now >= DEFEND_STEPS:
		defend_done = true
		return DEFEND_DONE
	if now > defend_told:
		defend_told = now
		return DEFEND_HOWTO[now]
	return ""


## F6: the "Live off your base" chapter. Call every tick; returns a message when it starts or a goal is met ("" else).
func tick_feed(clock: GameClock, factory: Factory) -> String:
	if feed_done:
		return ""
	if not feed_active:
		if not (defend_done or clock.day >= FEED_START_DAY):
			return ""
		feed_active = true
		feed_told = -1
	for m: Factory.Machine in factory.machines.values():
		if m.crafted > 0:
			for i in FEED_STEPS:
				if m.recipe_id in FEED_RECIPES[i]:
					feed_met[i] = true
	var now := feed_step()
	if now >= FEED_STEPS:
		feed_done = true
		return FEED_DONE
	if now > feed_told:
		feed_told = now
		return FEED_HOWTO[now]
	return ""


## F6: which "Live off your base" goal is next: the first not met yet (FEED_STEPS when they're all done).
func feed_step() -> int:
	for i in FEED_STEPS:
		if not bool(feed_met[i]):
			return i
	return FEED_STEPS


## F4: which "Defend your base" goal is next (DEFEND_STEPS when they're all done).
func defend_step(build: BuildGrid) -> int:
	if build.first_of_kind("turret") == "" and not (defend_ammo_made and defend_fed and defend_held):
		return 0
	if not defend_ammo_made:
		return 1
	if not defend_fed:
		return 2
	if not defend_held:
		return 3
	return DEFEND_STEPS


## F4: has any machine made something a turret fires (nails, bolts, rifle rounds)?
static func _turret_ammo_made(factory: Factory) -> bool:
	var ammo := {}
	for id: String in factory.data.buildables:
		var b: Dictionary = factory.data.buildables[id]
		if b.get("kind", "") == "turret":
			ammo[b["ammo"]] = true
	for m: Factory.Machine in factory.machines.values():
		if m.crafted > 0 and not m.recipe.is_empty():
			for item: String in (m.recipe.get("out", {}) as Dictionary):
				if ammo.has(item):
					return true
	return false


## [foundation, bed, wall count around that bed, closed door, enclosed] for the build-it-yourself detail row.
## V29 also accepts a closed town house while the player is standing inside it (shelter_complete).
func shelter_progress(build: BuildGrid) -> Array:
	var has_foundation := false
	var has_bed := false
	var best_walls := 0
	var has_door := false
	var has_complete_room := false
	var seen: Dictionary = {}
	for key: String in build.pieces:
		var piece: Dictionary = build.pieces[key]
		if piece["id"] != "foundation" or piece.get("town", false):
			continue
		has_foundation = true
		var cell: Vector2i = piece["cell"]
		if seen.has(cell):
			continue
		var room := _room(build, cell)
		var room_cells: Dictionary = room["cells"]
		for room_cell: Vector2i in room_cells:
			seen[room_cell] = true
		var room_has_bed := _room_has_player_bed(build, room_cells)
		has_bed = has_bed or room_has_bed
		best_walls = maxi(best_walls, int(room["walls"]))
		has_door = has_door or bool(room["door"])
		has_complete_room = has_complete_room or (room_has_bed and bool(room["enclosed"])
				and int(room["walls"]) >= 3 and bool(room["door"]))
	return [has_foundation, has_bed, best_walls, has_door, has_complete_room]


func shelter_complete(build: BuildGrid, player_pos: Vector3 = Vector3.INF) -> bool:
	var p := shelter_progress(build)
	return bool(p[4]) or (player_pos != Vector3.INF and _town_sheltered(build, player_pos))


## V29: whether the player is protected from the first-night wave right now. Unlike objective progress,
## a finished hut elsewhere does not protect you: you must be standing inside it.
func is_sheltered(build: BuildGrid, player_pos: Vector3) -> bool:
	var cell := BuildGrid.world_to_cell(player_pos)
	if _player_foundation(build, cell):
		var room := _room(build, cell)
		return bool(room["enclosed"]) and bool(room["door"]) and int(room["walls"]) >= 3 \
				and _room_has_player_bed(build, room["cells"])
	return _town_sheltered(build, player_pos)


## Floods the connected, unwalled player foundations containing the bed, then checks every outside edge.
## This recognizes a one-cell hut and a larger room equally; an internal wall separates a bedroom from an
## attached machine floor, so extending the base later does not undo the goal.
func _room(build: BuildGrid, start: Vector2i) -> Dictionary:
	var pending: Array[Vector2i] = [start]
	var cells: Dictionary = {}
	cells[start] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		for side in 4:
			var neighbor: Vector2i = cell + CELL_DIRS[side]
			if cells.has(neighbor) or not _player_foundation(build, neighbor):
				continue
			var edge_key := BuildGrid.key_for_wall_edge(cell, side)
			if build.pieces.has(edge_key) and build.kind_of(build.pieces[edge_key]["id"]) in ["wall", "door"]:
				continue
			cells[neighbor] = true
			pending.append(neighbor)
	var walls := 0
	var door := false
	var enclosed := true
	for cell: Vector2i in cells:
		for side in 4:
			if cells.has(cell + CELL_DIRS[side]):
				continue
			var edge_key := BuildGrid.key_for_wall_edge(cell, side)
			if not build.pieces.has(edge_key) or build.pieces[edge_key].get("town", false):
				enclosed = false
				continue
			var kind := build.kind_of(build.pieces[edge_key]["id"])
			if kind == "wall":
				walls += 1
			elif kind == "door" and not bool(build.pieces[edge_key].get("open", false)):
				door = true
			elif kind == "door":
				enclosed = false
			else:
				enclosed = false
	return {"cells": cells, "walls": walls, "door": door, "enclosed": enclosed}


func _room_has_player_bed(build: BuildGrid, cells: Dictionary) -> bool:
	for cell: Vector2i in cells:
		var key := build.key_for("bed", cell)
		if build.pieces.has(key) and build.kind_of(build.pieces[key]["id"]) == "bed" \
				and not build.pieces[key].get("town", false):
			return true
	return false


func _player_foundation(build: BuildGrid, cell: Vector2i) -> bool:
	var key := build.key_for("foundation", cell)
	return build.pieces.has(key) and build.pieces[key]["id"] == "foundation" \
			and not build.pieces[key].get("town", false)


## A town house is its connected patch of town floors. Interior dividers do not split the house; every
## outside edge must still stand, every outside door must be closed, and every outside window intact.
func _town_sheltered(build: BuildGrid, player_pos: Vector3) -> bool:
	var start := BuildGrid.world_to_cell(player_pos)
	if not _town_floor(build, start):
		return false
	var pending: Array[Vector2i] = [start]
	var cells: Dictionary = {}
	cells[start] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		for dir: Vector2i in CELL_DIRS:
			var neighbor := cell + dir
			if not cells.has(neighbor) and _town_floor(build, neighbor):
				cells[neighbor] = true
				pending.append(neighbor)
	var bed := false
	for cell: Vector2i in cells:
		var bed_key := build.key_for("bed", cell)
		bed = bed or (build.pieces.has(bed_key) and build.kind_of(build.pieces[bed_key]["id"]) == "bed")
		for side in 4:
			if cells.has(cell + CELL_DIRS[side]):
				continue
			var edge_key := BuildGrid.key_for_wall_edge(cell, side)
			if not build.pieces.has(edge_key):
				return false
			var piece: Dictionary = build.pieces[edge_key]
			var kind := build.kind_of(piece["id"])
			if kind == "door" and bool(piece.get("open", false)):
				return false
			if kind == "window" and int(piece.get("hp", 0)) <= 0:
				return false
			if not kind in ["wall", "door", "window"]:
				return false
	return bed


func _town_floor(build: BuildGrid, cell: Vector2i) -> bool:
	var piece: Variant = build.pieces.get("f:%d:%d" % [cell.x, cell.y])
	return piece is Dictionary and piece.get("id", "") == "town_floor"


func to_dict() -> Dictionary:
	return {"active": active, "completed": completed, "start_day": start_day, "ate": ate, "drank": drank,
			"bed_found": bed_found, "saw_night": saw_night, "night_failed": night_failed,
			"night_deaths": night_deaths,
			"survived_night": survived_night, "better_gear_uid": better_gear_uid,
			"better_gear_seconds": better_gear_seconds,
			"defend": {"active": defend_active, "done": defend_done, "ammo_made": defend_ammo_made, "fed": defend_fed,
					"held": defend_held, "night_kills": defend_night_kills, "told": defend_told},  # F4
			"feed": {"active": feed_active, "done": feed_done, "met": feed_met, "told": feed_told}}  # F6


func load_dict(d: Dictionary) -> void:
	active = bool(d.get("active", false))
	completed = bool(d.get("completed", false))
	start_day = int(d.get("start_day", 1))
	ate = bool(d.get("ate", false))
	drank = bool(d.get("drank", false))
	bed_found = bool(d.get("bed_found", false))
	saw_night = bool(d.get("saw_night", false))
	night_failed = bool(d.get("night_failed", false))
	night_deaths = int(d.get("night_deaths", 0))
	survived_night = bool(d.get("survived_night", false))
	better_gear_uid = int(d.get("better_gear_uid", -1))
	better_gear_seconds = float(d.get("better_gear_seconds", 0.0))
	var dd: Dictionary = d.get("defend", {})  # F4 (an older save starts the chapter fresh, from day 2)
	defend_active = bool(dd.get("active", false))
	defend_done = bool(dd.get("done", false))
	defend_ammo_made = bool(dd.get("ammo_made", false))
	defend_fed = bool(dd.get("fed", false))
	defend_held = bool(dd.get("held", false))
	defend_night_kills = int(dd.get("night_kills", -1))
	defend_told = int(dd.get("told", -1))
	var fd: Dictionary = d.get("feed", {})  # F6 (an older save starts the chapter fresh)
	feed_active = bool(fd.get("active", false))
	feed_done = bool(fd.get("done", false))
	feed_met = [false, false, false, false]
	var met: Array = fd.get("met", [])
	for i in mini(met.size(), FEED_STEPS):
		feed_met[i] = bool(met[i])
	feed_told = int(fd.get("told", -1))


## Screenshot helper: show the first two goals complete and the shelter partly built.
func debug_midway() -> void:
	active = true
	completed = false
	ate = true
	drank = true
	bed_found = true

