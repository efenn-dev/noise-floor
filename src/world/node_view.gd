class_name NodeView
extends Node3D
## F1: draws the resource nodes (SimWorld.resource_nodes): each node's own model beside its spot (a scrap heap, a
## farm well, a crashed fuel tanker, a stack of felled logs), solid, and a yellow square painted on the ground
## at the spot where its extractor goes. Looking at either (the Interactor reads "resource_node") says what it
## is and what to build there. No rules live here.

const MARK_COLOR := Color(0.95, 0.75, 0.15)
const MARK_SIZE := 1.9
const PROP_BOXES := {  # the models' boxes (tools/art/f1_models.py), for colliders and placeholders
	"scrap_heap": Vector3(3.6, 1.7, 3.2), "well": Vector3(1.7, 1.5, 1.7),
	"fuel_tanker": Vector3(8.4, 3.2, 2.8), "timber_stand": Vector3(3.4, 1.3, 2.2),
}

var sim: SimWorld
var props: Array = []  # one StaticBody3D per node, in order (tests)


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	var mark_mat := StandardMaterial3D.new()
	mark_mat.albedo_color = MARK_COLOR
	mark_mat.roughness = 0.7
	mark_mat.emission_enabled = true
	mark_mat.emission = MARK_COLOR * 0.25
	for n: Dictionary in sim.resource_nodes:
		_add_prop(n)
		_add_mark(n, mark_mat)


func _add_prop(n: Dictionary) -> void:
	var model_id := str(n["model"])
	var box: Vector3 = PROP_BOXES.get(model_id, Vector3(2, 1.5, 2))
	var body := StaticBody3D.new()
	body.name = "Node_" + str(n["id"])
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = n["prop_pos"]
	body.rotation.y = float(n["yaw"])
	body.set_meta("resource_node", n["id"])
	var path := "res://assets/models/%s.glb" % model_id
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.position.y = box.y / 2.0  # kit models are centred on their box
		CountryView.texture_props(model)
		body.add_child(model)
	else:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box
		mesh.mesh = bm
		mesh.position.y = box.y / 2.0
		body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box
	cs.shape = shape
	cs.position.y = box.y / 2.0
	body.add_child(cs)
	add_child(body)
	props.append(body)


## The spot: a painted square with a gap in each side (so it reads as a marking), seen by the look ray.
func _add_mark(n: Dictionary, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = "Spot_" + str(n["id"])
	body.collision_layer = Layers.TRAP  # walk over it; only rays see it
	body.collision_mask = 0
	body.position = n["pos"]
	body.set_meta("resource_node", n["id"])
	var half := MARK_SIZE / 2.0
	for side: Array in [[Vector3(0, 0, -half), Vector3(MARK_SIZE * 0.36, 0.02, 0.12)],
			[Vector3(0, 0, half), Vector3(MARK_SIZE * 0.36, 0.02, 0.12)],
			[Vector3(-half, 0, 0), Vector3(0.12, 0.02, MARK_SIZE * 0.36)],
			[Vector3(half, 0, 0), Vector3(0.12, 0.02, MARK_SIZE * 0.36)]]:
		for k: float in [-1.0, 1.0]:  # two dashes per side
			var mesh := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = side[1]
			mesh.mesh = bm
			mesh.material_override = mat
			var along: Vector3 = Vector3(side[1].x, 0, side[1].z).normalized() * (MARK_SIZE * 0.3) * k
			mesh.position = (side[0] as Vector3) + along + Vector3(0, 0.03, 0)
			body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(MARK_SIZE, 0.1, MARK_SIZE)
	cs.shape = shape
	cs.position.y = 0.05
	body.add_child(cs)
	add_child(body)
