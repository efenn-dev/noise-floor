class_name BuildGrid
extends RefCounted
## Where player-built pieces are and the rules for placing and removing them.
## The ground is a grid of 2 m cells. North is -Z. A foundation fills one cell; a wall stands on
## one edge of a cell and needs a foundation on at least one side of that edge.
## Edges are stored once, so "south of cell A" and "north of the cell below A" are the same wall.
## Machines and belts ("objects") stand on a foundation, one per cell, facing a side.

signal piece_added(key: String)
signal piece_removed(key: String, piece: Dictionary)

const GRID := 2.0
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
	if _kind(id) == "wall":
		return key_for_wall_edge(cell, side)
	if is_object(id):
		return "o:%d:%d" % [cell.x, cell.y]
	return "f:%d:%d" % [cell.x, cell.y]


## Machines and belts: one per cell, on top of a foundation, facing a side.
func is_object(id: String) -> bool:
	return _kind(id) in ["machine", "belt"]


func kind_of(id: String) -> String:
	return _kind(id)


## "" if the piece can go here with what's in `inv`, otherwise a short reason for the HUD.
func can_place(id: String, cell: Vector2i, side: int, inv: Inventory) -> String:
	if not data.buildables.has(id):
		return "Unknown piece"
	if pieces.has(key_for(id, cell, side)):
		return "Already built"
	if _kind(id) == "wall":
		var edge := canonical_edge(cell, side)
		if not _edge_supported(edge[0], edge[1], ""):
			return "Needs a foundation"
	if is_object(id) and not pieces.has("f:%d:%d" % [cell.x, cell.y]):
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
	var piece := {"id": id, "cell": cell, "side": side}
	if _kind(id) == "wall":
		var edge := canonical_edge(cell, side)
		piece = {"id": id, "cell": edge[0], "side": edge[1]}
	pieces[key] = piece
	piece_added.emit(key)
	return ""


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
	pieces.erase(key)
	inv.give_all(data.buildables[piece["id"]]["cost"])
	piece_removed.emit(key, piece)
	return ""


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
		return corner + Vector3(GRID / 2.0, foundation_top() + size.y / 2.0, GRID / 2.0)
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
	if _kind(id) != "wall":
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


func key_for_wall_edge(cell: Vector2i, side: int) -> String:
	var edge := canonical_edge(cell, side)
	return "w:%d:%d:%s" % [edge[0].x, edge[0].y, "n" if edge[1] == Side.NORTH else "w"]
