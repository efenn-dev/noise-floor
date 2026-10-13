class_name BuildGrid
extends RefCounted
## Where player-built pieces are and the rules for placing and removing them.
## The ground is a grid of 2 m cells. North is -Z. A foundation fills one cell; a wall stands on
## one edge of a cell and needs a foundation on at least one side of that edge. Doors and barricades
## are edge pieces too (one per edge, same rules as walls).
## Edges are stored once, so "south of cell A" and "north of the cell below A" are the same wall.
## Windows (W1a, town houses only) are edge pieces too: intact they block sound but not sight; broken
## (hp 0) they stay as a piece but are an opening, until a barricade is built over them.
## Town pieces (town_floor, town_wall, window) are "player_placeable": false: the town plan lays them
## with restore(), the player can't place them, but can remove them for a small refund.
## Machines and belts ("objects") stand on a foundation, one per cell, facing a side.

signal piece_added(key: String)
signal piece_removed(key: String, piece: Dictionary)
signal piece_changed(key: String)  # a door opened or closed
## The player (or a demo) placed a piece with place(), not restore(): Building xp (M12).
signal piece_built(key: String)

const EDGE_KINDS := ["wall", "door", "barricade", "window"]

const GRID := 2.0
const WALL_HALF := 0.1   # half a wall's thickness: a wall's face is this far inside the cell
const WALL_GAP := 0.02   # what stands "against_wall" keeps this gap to the wall's face
enum Side { NORTH, EAST, SOUTH, WEST }
const SIDE_NAMES := ["north", "east", "south", "west"]

var data: GameData
## key -> {id, cell: Vector2i, side: int}. Walls: canonical NORTH or WEST edge. Objects: the way it faces.
var pieces: Dictionary = {}


func _init(p_data: GameData) -> void:
	data = p_data


static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))


## Edge sides are stored as NORTH or WEST of some cell: SOUTH of (x, z) is NORTH of (x, z + 1).
static func canonical_edge(cell: Vector2i, side: int) -> Array:
	match side:
		Side.SOUTH:
			return [cell + Vector2i(0, 1), Side.NORTH]
		Side.EAST:
			return [cell + Vector2i(1, 0), Side.WEST]
	return [cell, side]


func key_for(id: String, cell: Vector2i, side: int = Side.NORTH) -> String:
	if is_edge(id):
		return key_for_wall_edge(cell, side)
	if is_object(id):
		return "o:%d:%d" % [cell.x, cell.y]
	return "f:%d:%d" % [cell.x, cell.y]


## Machines, belts, beds, crates, power pieces, traps, turrets and props: one per cell, facing a side.
## All but power poles and traps need a foundation. Props (W1c) are town pieces like town walls: laid by
## the town plan, never built by the player, removable for a small refund, bashed by zombies.
func is_object(id: String) -> bool:
	return _kind(id) in ["machine", "belt", "bed", "storage", "generator", "solar", "pole", "trap", "turret", "prop"]


func kind_of(id: String) -> String:
	return _kind(id)


## Walls, doors, barricades and windows: they stand on a cell edge.
func is_edge(id: String) -> bool:
	return _kind(id) in EDGE_KINDS


## A built edge piece blocks sound and sight unless it's an open door. Barricades are low, so a
## turret can shoot over them (they still count for sound).
func edge_blocks(key: String, for_sight: bool = false) -> bool:
	if not pieces.has(key):
		return false
	var kind := _kind(pieces[key]["id"])
	if kind == "door":
		return not pieces[key].get("open", false)
	if kind == "barricade":
		return not for_sight
	if kind == "window":
		return not for_sight and pieces[key]["hp"] > 0  # glass: you see through it; broken, it's a hole
	return true


## A window whose glass is gone (hp 0). It stays in `pieces` so a barricade can board it up.
func is_broken(key: String) -> bool:
	return pieces.has(key) and _kind(pieces[key]["id"]) == "window" and pieces[key]["hp"] <= 0


## False for town pieces (data "player_placeable": false): the build menu never offers them.
func player_placeable(id: String) -> bool:
	return data.buildables.has(id) and data.buildables[id].get("player_placeable", true)


## Opens or closes a door. Returns the new state (true = open).
func toggle_door(key: String) -> bool:
	if not pieces.has(key) or _kind(pieces[key]["id"]) != "door":
		return false
	pieces[key]["open"] = not pieces[key].get("open", false)
	piece_changed.emit(key)
	return pieces[key]["open"]


## Fully repairs a piece, paying a share of its build cost for the damage, less `discount` (Building).
## Returns "" or why not.
func repair(key: String, inv: Inventory, discount: float = 0.0) -> String:
	if not pieces.has(key):
		return "Nothing to repair"
	var piece: Dictionary = pieces[key]
	var max_hp: int = data.buildables[piece["id"]]["hp"]
	if piece["hp"] >= max_hp:
		return "Not damaged"
	if is_broken(key):
		return "The glass is gone: build a barricade here to board it up"
	var cost := repair_cost(key, discount)
	if not inv.take_all(cost):
		return "Not enough materials"
	piece["hp"] = max_hp
	return ""


## What repairing a piece would cost: its build cost times the share of hp missing (at least 1 each),
## less `discount` (0.05 per Building level), rounded, and never below half.
func repair_cost(key: String, discount: float = 0.0) -> Dictionary:
	var piece: Dictionary = pieces[key]
	var b: Dictionary = data.buildables[piece["id"]]
	var missing := 1.0 - float(piece["hp"]) / float(b["hp"])
	var cost := {}
	for item: String in b["cost"]:
		var full := maxi(1, ceili(b["cost"][item] * missing))
		cost[item] = maxi(1, roundi(full * maxf(0.5, 1.0 - discount)))
	return cost


## "" if the piece can go here with what's in `inv`, otherwise a short reason for the HUD.
func can_place(id: String, cell: Vector2i, side: int, inv: Inventory) -> String:
	if not data.buildables.has(id):
		return "Unknown piece"
	if not player_placeable(id):
		return "Only found in town"
	var existing := key_for(id, cell, side)
	if pieces.has(existing) and not (_kind(id) == "barricade" and is_broken(existing)):
		return "Already built"  # (a barricade may board up a broken window)
	if is_edge(id):
		var edge := canonical_edge(cell, side)
		if not _edge_supported(edge[0], edge[1], ""):
			return "Needs a foundation"
	if is_object(id) and not _kind(id) in ["pole", "trap"] and not pieces.has("f:%d:%d" % [cell.x, cell.y]):
		return "Needs a foundation"
	if not inv.has_all(data.buildables[id]["cost"]):
		return "Not enough materials"
	return ""


## Places the piece and pays for it. Returns "" or the reason it failed (nothing changes then).
func place(id: String, cell: Vector2i, side: int, inv: Inventory) -> String:
	var reason := can_place(id, cell, side, inv)
	if reason != "":
		return reason
	inv.take_all(data.buildables[id]["cost"])
	var key := key_for(id, cell, side)
	if pieces.has(key):  # boarding up a broken window: it goes, with no refund
		var window: Dictionary = pieces[key]
		pieces.erase(key)
		window["destroyed"] = true
		piece_removed.emit(key, window)
	var piece := {"id": id, "cell": cell, "side": side, "hp": data.buildables[id]["hp"]}
	if is_edge(id):
		var edge := canonical_edge(cell, side)
		piece["cell"] = edge[0]
		piece["side"] = edge[1]
	pieces[key] = piece
	piece_added.emit(key)
	piece_built.emit(key)
	return ""


## Puts back a saved piece exactly as it was (no rules, no cost), announcing it like a new one.
func restore(key: String, piece: Dictionary) -> void:
	pieces[key] = piece
	piece_added.emit(key)
	if piece.get("open", false):
		piece_changed.emit(key)


func can_remove(key: String) -> String:
	if not pieces.has(key):
		return "Nothing to remove"
	var piece: Dictionary = pieces[key]
	if _kind(piece["id"]) == "foundation":
		if pieces.has("o:%d:%d" % [piece["cell"].x, piece["cell"].y]):
			return "Remove what's on it first"
		for wall_key: String in _walls_touching(piece["cell"]):
			var w: Dictionary = pieces[wall_key]
			if not _edge_supported(w["cell"], w["side"], key):
				return "Remove the walls on it first"
	return ""


## Removes the piece and refunds its full cost. Returns "" or the reason it failed.
func remove(key: String, inv: Inventory) -> String:
	var reason := can_remove(key)
	if reason != "":
		return reason
	var piece: Dictionary = pieces[key]
	var broken := is_broken(key)
	pieces.erase(key)
	if not broken:  # a broken window is worth nothing
		inv.give_all(data.buildables[piece["id"]]["cost"])
	piece_removed.emit(key, piece)
	return ""


## Zombies hitting a piece. Returns true if that destroyed it (see destroy) or broke a window.
## A window at hp 0 isn't removed: it becomes an opening (piece_changed) and takes no more damage.
func damage(key: String, amount: int) -> bool:
	if not pieces.has(key) or amount <= 0 or is_broken(key):
		return false
	pieces[key]["hp"] -= amount
	if pieces[key]["hp"] > 0:
		return false
	if _kind(pieces[key]["id"]) == "window":
		pieces[key]["hp"] = 0
		piece_changed.emit(key)
		return true
	destroy(key)
	return true


## Wrecks a piece: no refund, and the piece dict passed to piece_removed has "destroyed" = true.
## A wrecked foundation takes down what stood on it and any wall it alone held up.
func destroy(key: String) -> void:
	if not pieces.has(key):
		return
	var piece: Dictionary = pieces[key]
	var doomed := []
	if _kind(piece["id"]) == "foundation":
		var obj := "o:%d:%d" % [piece["cell"].x, piece["cell"].y]
		if pieces.has(obj):
			doomed.append(obj)
		for wall_key: String in _walls_touching(piece["cell"]):
			var w: Dictionary = pieces[wall_key]
			if not _edge_supported(w["cell"], w["side"], key):
				doomed.append(wall_key)
	for k: String in doomed:
		destroy(k)
	pieces.erase(key)
	piece["destroyed"] = true
	piece_removed.emit(key, piece)


## World-space center of a piece (its box is data size; walls are turned 90 degrees on WEST edges).
func piece_center(key: String) -> Vector3:
	var piece: Dictionary = pieces[key]
	return center_for(piece["id"], piece["cell"], piece.get("side", Side.NORTH))


func center_for(id: String, cell: Vector2i, side: int) -> Vector3:
	var size: Vector3 = data.buildables[id]["size"]
	var corner := Vector3(cell.x * GRID, 0.0, cell.y * GRID)
	if _kind(id) == "foundation":
		return corner + Vector3(GRID / 2.0, size.y / 2.0, GRID / 2.0)
	if is_object(id):
		var mid := corner + Vector3(GRID / 2.0, foundation_top() + size.y / 2.0, GRID / 2.0)
		if data.buildables[id].get("against_wall", false):  # W1c: back against the wall behind it, not mid-cell
			var facing := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][side] as Vector3
			mid -= facing * (GRID / 2.0 - WALL_HALF - size.z / 2.0 - WALL_GAP)
		return mid
	var edge := canonical_edge(cell, side)
	corner = Vector3(edge[0].x * GRID, 0.0, edge[0].y * GRID)
	var y := foundation_top() + size.y / 2.0
	if edge[1] == Side.NORTH:
		return corner + Vector3(GRID / 2.0, y, 0.0)
	return corner + Vector3(0.0, y, GRID / 2.0)


## Yaw in degrees for a piece's box: walls on WEST edges run north-south; objects turn to face `side`
## (their box's -Z end is the front).
func yaw_for(id: String, cell: Vector2i, side: int) -> float:
	if is_object(id):
		return -90.0 * side
	if not is_edge(id):
		return 0.0
	return 0.0 if canonical_edge(cell, side)[1] == Side.NORTH else 90.0


func foundation_top() -> float:
	return data.buildables["foundation"]["size"].y if data.buildables.has("foundation") else 0.0


func _kind(id: String) -> String:
	return data.buildables[id]["kind"] if data.buildables.has(id) else ""


## A wall edge is supported if a foundation (other than `ignore_key`) is on either side of it.
func _edge_supported(cell: Vector2i, side: int, ignore_key: String) -> bool:
	var other := cell + (Vector2i(0, -1) if side == Side.NORTH else Vector2i(-1, 0))
	for c: Vector2i in [cell, other]:
		var k := "f:%d:%d" % [c.x, c.y]
		if k != ignore_key and pieces.has(k):
			return true
	return false


func _walls_touching(cell: Vector2i) -> Array:
	var out := []
	for side in 4:
		var k := key_for_wall_edge(cell, side)
		if pieces.has(k):
			out.append(k)
	return out


static func key_for_wall_edge(cell: Vector2i, side: int) -> String:
	var edge := canonical_edge(cell, side)
	return "w:%d:%d:%s" % [edge[0].x, edge[0].y, "n" if edge[1] == Side.NORTH else "w"]
