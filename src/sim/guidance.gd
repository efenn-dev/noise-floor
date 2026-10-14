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
func tick(dt: float, clock: GameClock, build: BuildGrid, deaths: int) -> void:
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
	update_completion(build)


func step(build: BuildGrid) -> int:
	if not ate or not drank:
		return 0
	if not bed_found:
		return 1
	if not shelter_complete(build):
		return 2
	if not survived_night:
		return 3
	return COMPLETE


func update_completion(build: BuildGrid) -> void:
	if active and survived_night and shelter_complete(build) and ate and drank and bed_found:
		completed = true


## [foundation, bed, wall count around that bed, door, enclosed]. Only the player's pieces count: town houses
## should teach where beds are, not finish the game's base-building half for the player.
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


func shelter_complete(build: BuildGrid) -> bool:
	var p := shelter_progress(build)
	return bool(p[4])


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
			elif kind == "door":
				door = true
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


func to_dict() -> Dictionary:
	return {"active": active, "completed": completed, "start_day": start_day, "ate": ate, "drank": drank,
			"bed_found": bed_found, "saw_night": saw_night, "night_failed": night_failed,
			"night_deaths": night_deaths,
			"survived_night": survived_night, "better_gear_uid": better_gear_uid,
			"better_gear_seconds": better_gear_seconds}


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


## Screenshot helper: show the first two goals complete and the shelter partly built.
func debug_midway() -> void:
	active = true
	completed = false
	ate = true
	drank = true
	bed_found = true

