class_name BuildGrid
extends RefCounted
## Where player-built pieces are and the rules for placing and removing them.
## The ground is a grid of 2 m cells. North is -Z. A foundation fills one cell; a wall stands on
## one edge of a cell and needs a foundation on at least one side of that edge. Doors and barricades
## are edge pieces too (one per edge, same rules as walls).
## Edges are stored once, so "south of cell A" and "north of the cell below A" are the same wall.
## Windows (W1a, town houses only) are edge pieces too: intact they block sound but not sight; broken
## (hp 0) they stop sound-blocking but the frame always blocks walking until something climbs through it.
## Town pieces (town_floor, town_wall, window) are "player_placeable": false: the town plan lays them
## with restore(), the player can't place them, but can remove them for a small refund.
## Machines and belts ("objects") stand on a foundation, one per cell, facing a side.

signal piece_added(key: String)
signal piece_removed(key: String, piece: Dictionary)
signal piece_changed(key: String)  # a door opened or closed
## The player (or a demo) placed a piece with place(), not restore(): Building xp (M12).
signal piece_built(key: String)

const EDGE_KINDS := ["wall", "door", "barricade", "window", "tripwire", "fence"]
## M15: edge pieces that stand on bare ground (no foundation needed), and never block sound or sight.
const GROUND_EDGES := ["tripwire", "fence"]
## M15: objects that stand on bare ground, like power poles and spike strips.
const GROUND_OBJECTS := ["pole", "trap", "sensor", "floodlight", "noisemaker", "bear_trap", "hub", "radio_mast",
		"belt", "splitter", "merger"]  # F3: belts run on bare ground too (out to an outpost)
const ON_GROUND_OR_FOUNDATION := ["belt", "splitter", "merger", "hub", "radio_mast"]  # F3: sit on a foundation if there is one

const GRID := 2.0
const WALL_HALF := 0.1   # half a wall's thickness: a wall's face is this far inside the cell
const WALL_GAP := 0.02   # what stands "against_wall" keeps this gap to the wall's face
enum Side { NORTH, EAST, SOUTH, WEST }
const SIDE_NAMES := ["north", "east", "south", "west"]

var data: GameData
## key -> {id, cell: Vector2i, side: int}. Walls: canonical NORTH or WEST edge. Objects: the way it faces.
var pieces: Dictionary = {}
## Piece keys by kind (kind -> {key: true}) and each key's kind, kept up to date wherever `pieces` changes, so
## "where's the Hub / the radio mast" is one lookup, not a walk over every piece (the mast's lamp asks every frame).
var _by_kind: Dictionary = {}
var _key_kind: Dictionary = {}
## M17a: set by SimWorld, so pieces with a data "needs_project" (the water tap) wait for that project.
var projects: Projects
var milestones: Milestones  # F2: pieces the Hub's milestones unlock


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
	return _kind(id) in ["machine", "belt", "bed", "storage", "generator", "solar", "pole", "trap", "turret", "prop", "workbench",
			"hopper", "sensor", "floodlight", "noisemaker", "bear_trap", "repair_station",
			"stove", "heater",  # M16
			"hub", "radio_mast", "splitter", "merger"]  # F2, F3


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
	if kind in GROUND_EDGES:
		return false  # M15: a tripwire or a wire fence: sound and sight pass through
	if kind == "door":
		return not pieces[key].get("open", false)
	if kind == "barricade":
		return not for_sight
	if kind == "window":
		return not for_sight and pieces[key]["hp"] > 0  # glass: you see through it; broken, it's a hole
	return true


## V17: whether an edge is a physical walking barrier. Unlike sound/sight, a window frame always blocks ordinary
## movement after its glass breaks; player and zombie vaults explicitly pass that one collider.
func edge_blocks_walk(key: String) -> bool:
	if not pieces.has(key):
		return false
	var kind := _kind(pieces[key]["id"])
	if kind in GROUND_EDGES:
		return false
	if kind == "door":
		return not pieces[key].get("open", false)
	return true


## A window whose glass is gone (hp 0). It stays in `pieces` so a barricade can board it up.
func is_broken(key: String) -> bool:
	return pieces.has(key) and _kind(pieces[key]["id"]) == "window" and pieces[key]["hp"] <= 0


## V17: broken glass leaves sharp remnants in the frame until the player clears them. Saves before V16 have no
## field, so a broken window defaults to shards (the migration makes that explicit when it loads).
func has_shards(key: String) -> bool:
	return is_broken(key) and bool(pieces[key].get("shards", true))


func clear_shards(key: String) -> bool:
	if not has_shards(key):
		return false
	pieces[key]["shards"] = false
	piece_changed.emit(key)
	return true


## False for town pieces (data "player_placeable": false): the build menu never offers them.
func player_placeable(id: String) -> bool:
	return data.buildables.has(id) and data.buildables[id].get("player_placeable", true)


## Opens or closes a door. Returns the new state (true = open). S3: given where the opener stands (`from`),
## the door swings AWAY from them (stored as "swing": 1 or -1, see door_pose), so it never shoves them.
func toggle_door(key: String, from: Vector3 = Vector3.INF) -> bool:
	if not pieces.has(key) or _kind(pieces[key]["id"]) != "door":
		return false
	var piece: Dictionary = pieces[key]
	piece["open"] = not piece.get("open", false)
	if piece["open"] and from.is_finite():
		piece["swing"] = swing_away_from(key, from)
	piece_changed.emit(key)
	return piece["open"]


## Which way a door at `key` should swing to open away from `from`: 1 toward the door's own -Z side (the
## default), -1 toward its +Z side.
func swing_away_from(key: String, from: Vector3) -> int:
	var piece: Dictionary = pieces[key]
	var yaw := yaw_for(piece["id"], piece["cell"], piece["side"])
	var local := Basis(Vector3.UP, deg_to_rad(yaw)).inverse() * (from - piece_center(key))
	return 1 if local.z >= 0.0 else -1


## Where a door's box stands: closed, flat on its edge; open, turned a quarter round the hinge at its -X end
## toward the side "swing" says (1 = the door's -Z side, -1 = +Z), so an open door is still a solid, visible
## panel beside the doorway (the look ray finds it to close it again, and nothing walks through it).
func door_pose(key: String) -> Transform3D:
	var piece: Dictionary = pieces[key]
	var yaw := yaw_for(piece["id"], piece["cell"], piece["side"])
	var center := piece_center(key)
	if not piece.get("open", false):
		return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), center)
	var size: Vector3 = data.buildables[piece["id"]]["size"]
	var swing := int(piece.get("swing", 1))
	var hinge := center - Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(size.x / 2.0, 0, 0)
	var open_basis := Basis(Vector3.UP, deg_to_rad(yaw + 90.0 * swing))
	return Transform3D(open_basis, hinge + open_basis * Vector3(size.x / 2.0, 0, 0))


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


## F1: resource nodes on the map, by cell (SimWorld fills it): Vector2i -> node kind. An extractor (buildables
## "needs_node") goes only on its kind's cell, and stands on the ground there (no foundation).
var nodes: Dictionary = {}


## "" if the piece can go here with what's in `inv`, otherwise a short reason for the HUD.
func can_place(id: String, cell: Vector2i, side: int, inv: Inventory) -> String:
	if not data.buildables.has(id):
		return "Unknown piece"
	if not player_placeable(id):
		return "Only found in town"
	if milestones != null and not milestones.unlocked(id):
		return "Unlock it at the Hub: %s" % milestones.cfg(milestones.unlocked_by(id)).get("name", "a milestone")
	if _kind(id) == "hub" and first_of_kind("hub") != "":
		return "You already have a Hub"
	if projects != null and not projects.unlocked(id):
		return "Needs the %s running" % String(data.projects.get(data.buildables[id]["needs_project"], {}).get("name", "project")).to_lower()
	var existing := key_for(id, cell, side)
	if pieces.has(existing) and not (_kind(id) == "barricade" and is_broken(existing)):
		return "Already built"  # (a barricade may board up a broken window)
	if is_edge(id):
		var edge := canonical_edge(cell, side)
		if not _kind(id) in GROUND_EDGES and not _edge_supported(edge[0], edge[1], ""):
			return "Needs a foundation"
	var needs_node := str(data.buildables[id].get("needs_node", ""))
	if needs_node != "" and str(nodes.get(cell, "")) != needs_node:
		return "Build it on a %s (the yellow spot)" % String(data.resources.get("kinds", {}).get(needs_node, {}).get("name", needs_node)).to_lower()
	if is_object(id) and not _kind(id) in GROUND_OBJECTS and needs_node == "" and not pieces.has("f:%d:%d" % [cell.x, cell.y]):
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
		_unindex(key)
		window["destroyed"] = true
		piece_removed.emit(key, window)
	var piece := {"id": id, "cell": cell, "side": side, "hp": data.buildables[id]["hp"]}
	if is_edge(id):
		var edge := canonical_edge(cell, side)
		piece["cell"] = edge[0]
		piece["side"] = edge[1]
	pieces[key] = piece
	_index(key)
	piece_added.emit(key)
	piece_built.emit(key)
	return ""


## Puts back a saved piece exactly as it was (no rules, no cost), announcing it like a new one.
func restore(key: String, piece: Dictionary) -> void:
	pieces[key] = piece
	_index(key)
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


## Removes the piece and gives back refund_for(it). Returns "" or the reason it failed.
func remove(key: String, inv: Inventory) -> String:
	var reason := can_remove(key)
	if reason != "":
		return reason
	var piece: Dictionary = pieces[key]
	var broken := is_broken(key)
	pieces.erase(key)
	_unindex(key)
	if not broken:  # a broken window is worth nothing
		inv.give_all(refund_for(piece))
	piece_removed.emit(key, piece)
	return ""


## What pulling `piece` down gives back. P3: a piece the town laid ("town": true: houses, beds, the factory
## hall, furniture) gives its data "salvage" if it has one (a door 2 planks, a bed 3 planks and a scrap),
## otherwise its cost, which for town-only pieces (walls, floors, windows, furniture) is already a salvage.
## Anything you built gives its full cost back.
func refund_for(piece: Dictionary) -> Dictionary:
	var b: Dictionary = data.buildables[piece["id"]]
	if piece.get("town", false) and b.has("salvage"):
		return b["salvage"]
	return b["cost"]


## Zombies hitting a piece. Returns true if that destroyed it (see destroy) or broke a window.
## A window at hp 0 isn't removed: it becomes a climbable broken frame (piece_changed) and takes no more damage.
func damage(key: String, amount: int) -> bool:
	if not pieces.has(key) or amount <= 0 or is_broken(key):
		return false
	pieces[key]["hp"] -= amount
	if pieces[key]["hp"] > 0:
		return false
	if _kind(pieces[key]["id"]) == "window":
		pieces[key]["hp"] = 0
		pieces[key]["shards"] = true
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
	_unindex(key)
	piece["destroyed"] = true
	piece_removed.emit(key, piece)


## The key of a piece of `kind` ("" if there's none): one lookup (see _by_kind).
func first_of_kind(kind: String) -> String:
	var keys: Dictionary = _by_kind.get(kind, {})
	return "" if keys.is_empty() else str(keys.keys()[0])


func _index(key: String) -> void:
	_unindex(key)
	var kind := _kind(pieces[key]["id"])
	_key_kind[key] = kind
	if not _by_kind.has(kind):
		_by_kind[kind] = {}
	_by_kind[kind][key] = true


func _unindex(key: String) -> void:
	if _key_kind.has(key):
		(_by_kind[_key_kind[key]] as Dictionary).erase(key)
		_key_kind.erase(key)


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
		var floor_y := 0.0 if str(data.buildables[id].get("needs_node", "")) != "" else foundation_top()  # F1: extractors stand on the ground
		if _kind(id) in ON_GROUND_OR_FOUNDATION and not pieces.has("f:%d:%d" % [cell.x, cell.y]):
			floor_y = 0.0  # F3: a belt out in the field lies on the ground
		var mid := corner + Vector3(GRID / 2.0, floor_y + size.y / 2.0, GRID / 2.0)
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
		if pieces.has(k) and not _kind(pieces[k]["id"]) in GROUND_EDGES:  # M15: fences stand on their own
			out.append(k)
	return out


static func key_for_wall_edge(cell: Vector2i, side: int) -> String:
	var edge := canonical_edge(cell, side)
	return "w:%d:%d:%s" % [edge[0].x, edge[0].y, "n" if edge[1] == Side.NORTH else "w"]
