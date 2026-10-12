class_name BuildView
extends Node3D
## Draws the pieces in a BuildGrid: one solid box per piece, added and freed as the grid changes.
## Each body carries meta "piece_key" so a raycast can tell which piece it hit.

var grid: BuildGrid
var _bodies: Dictionary = {}  # key -> StaticBody3D

const COLORS := {
	"foundation": Color(0.55, 0.45, 0.32),
	"wall": Color(0.62, 0.52, 0.38),
	"belt": Color(0.16, 0.16, 0.18),
	"machine": Color(0.42, 0.44, 0.4),
	"bed": Color(0.35, 0.4, 0.6),
	"storage": Color(0.5, 0.38, 0.22),
}
const INPUT_COLOR := Color(0.25, 0.45, 0.9)
const OUTPUT_COLOR := Color(0.95, 0.55, 0.15)


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
	match info["kind"]:
		"belt":
			# Two pale chevron bars toward the front (-Z) show which way it runs.
			for z in [-0.55, 0.25]:
				_add_part(body, Vector3(0.7, 0.02, 0.12), Vector3(0, size.y / 2.0 + 0.01, z), Color(0.8, 0.75, 0.3))
		"machine":
			_add_part(body, Vector3(0.7, 0.5, 0.12), Vector3(0, -size.y / 2.0 + 0.4, -size.z / 2.0 - 0.06), OUTPUT_COLOR)
			_add_part(body, Vector3(0.7, 0.5, 0.12), Vector3(0, -size.y / 2.0 + 0.4, size.z / 2.0 + 0.06), INPUT_COLOR)
			var lamp := _add_part(body, Vector3(0.25, 0.25, 0.25), Vector3(0, size.y / 2.0 + 0.125, 0), Color(0.2, 0.2, 0.2))
			lamp.name = "Lamp"
		"bed":
			_add_part(body, Vector3(0.7, 0.12, 0.35), Vector3(0, size.y / 2.0 + 0.06, -size.z / 2.0 + 0.25), Color(0.92, 0.92, 0.9))
		"storage":
			_add_part(body, Vector3(size.x + 0.04, 0.08, size.z + 0.04), Vector3(0, size.y / 2.0 - 0.1, 0), Color(0.3, 0.22, 0.12))
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	_bodies[key] = body


func _add_part(body: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	part.material_override = mat
	body.add_child(part)
	return part


func _on_removed(key: String, _piece: Dictionary) -> void:
	if _bodies.has(key):
		_bodies[key].queue_free()
		_bodies.erase(key)
