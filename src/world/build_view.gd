class_name BuildView
extends Node3D
## Draws the pieces in a BuildGrid: one solid box per piece, added and freed as the grid changes.
## Each body carries meta "piece_key" so a raycast can tell which piece it hit.

var grid: BuildGrid
var _bodies: Dictionary = {}  # key -> StaticBody3D

const COLORS := {"foundation": Color(0.55, 0.45, 0.32), "wall": Color(0.62, 0.52, 0.38)}


func setup(p_grid: BuildGrid) -> void:
	grid = p_grid
	grid.piece_added.connect(_on_added)
	grid.piece_removed.connect(_on_removed)
	for key: String in grid.pieces:
		_on_added(key)


func body_for(key: String) -> StaticBody3D:
	return _bodies.get(key)


func _on_added(key: String) -> void:
	var piece: Dictionary = grid.pieces[key]
	var id: String = piece["id"]
	var info: Dictionary = grid.data.buildables[id]
	var size: Vector3 = info["size"]
	var body := StaticBody3D.new()
	body.collision_layer = Layers.BUILT
	body.collision_mask = 0
	body.set_meta("piece_key", key)
	body.position = grid.piece_center(key)
	body.rotation_degrees.y = grid.yaw_for(id, piece["cell"], piece.get("side", 0))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(info["kind"], Color.GRAY)
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	_bodies[key] = body


func _on_removed(key: String) -> void:
	if _bodies.has(key):
		_bodies[key].queue_free()
		_bodies.erase(key)
