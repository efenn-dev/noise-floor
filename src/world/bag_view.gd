class_name BagView
extends Node3D
## Draws the bags you dropped when you died, so you can walk back and pick them up (E).

var sim: SimWorld
var _bodies: Dictionary = {}  # bag id -> StaticBody3D


func setup(p_sim: SimWorld) -> void:
	sim = p_sim


func _process(_delta: float) -> void:
	var live := {}
	for bag: Dictionary in sim.bags:
		live[bag["id"]] = true
		if not _bodies.has(bag["id"]):
			_bodies[bag["id"]] = _make(bag)
	for id: int in _bodies.keys():
		if not live.has(id):
			_bodies[id].queue_free()
			_bodies.erase(id)


func _make(bag: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.BAG
	body.collision_mask = 0
	body.set_meta("bag_id", bag["id"])
	body.position = Vector3(bag["pos"].x, 0.25, bag["pos"].z)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.5, 0.4)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.32, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.15, 0.05)
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body
