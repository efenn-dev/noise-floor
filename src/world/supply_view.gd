class_name SupplyView
extends Node3D
## R1b: draws what Supplies puts out. A crashed supply truck: a rusted van off the road, solid, its body the loot
## container (the Interactor searches "container_id"; once quiet it's a wreck a swing strips, like the highway's).
## A forage pile: its kind's model at a smaller scale, solid, carrying "resource_node" so E gathers from it; gone when
## it's picked clean. Watches Supplies.changes. No rules live here.

const PILE_SCALE := {"scrap_heap": 0.45, "timber_stand": 0.55}  # the big node models, cut down to a pile

var sim: SimWorld
var trucks: Dictionary = {}  # truck id -> StaticBody3D
var piles: Dictionary = {}  # pile id -> StaticBody3D
var _seen := -1


func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	name = "SupplyView"


func _process(_delta: float) -> void:
	if sim == null or sim.supplies.changes == _seen:
		return
	_seen = sim.supplies.changes
	for t: Dictionary in sim.supplies.trucks:
		if not trucks.has(t["id"]):
			trucks[t["id"]] = _add_truck(t)
	var live := {}
	for p: Dictionary in sim.supplies.piles:
		live[p["id"]] = true
		if not piles.has(p["id"]):
			piles[p["id"]] = _add_pile(p)
	for id: String in piles.keys():
		if not live.has(id):
			piles[id].queue_free()
			piles.erase(id)


func _add_truck(t: Dictionary) -> StaticBody3D:
	var type := str(t["model"])
	var size: Array = (sim.data.vehicles.get(type, {}) as Dictionary).get("size", [2.0, 2.1, 4.9])
	var box := Vector3(float(size[0]), float(size[1]), float(size[2]))
	var body := StaticBody3D.new()
	body.name = "Truck_" + str(t["id"])
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = t["pos"]
	body.rotation.y = float(t["yaw"])
	body.set_meta("container_id", t["id"])  # E searches its back; a swing strips it once the horn's quiet
	var path := "res://assets/models/%s.glb" % type
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.rotation.y = PI  # the car models face -Z like everything else
		model.position.y = box.y / 2.0  # kit models are centred on their box
		CountryView._rust(model)
		body.add_child(model)
	else:
		body.add_child(_box_mesh(box))
	body.add_child(_box_shape(box))
	add_child(body)
	return body


func _add_pile(p: Dictionary) -> StaticBody3D:
	var kind := sim.supplies.kind_cfg(str(p["kind"]))
	var model_id := str(kind.get("model", p["kind"]))
	var scale := float(kind.get("scale", PILE_SCALE.get(model_id, 0.5)))
	var box: Vector3 = (NodeView.PROP_BOXES.get(model_id, Vector3(2, 1.5, 2)) as Vector3) * scale
	var body := StaticBody3D.new()
	body.name = "Pile_" + str(p["id"])
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = p["pos"]
	body.rotation.y = float(hash(str(p["id"])) % 628) / 100.0  # each pile lies its own way
	body.set_meta("resource_node", p["id"])
	var path := "res://assets/models/%s.glb" % model_id
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.scale = Vector3.ONE * scale
		model.position.y = box.y / 2.0
		CountryView.texture_props(model)
		body.add_child(model)
	else:
		body.add_child(_box_mesh(box))
	body.add_child(_box_shape(box))
	add_child(body)
	return body


static func _box_mesh(box: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box
	mesh.mesh = bm
	mesh.position.y = box.y / 2.0
	return mesh


static func _box_shape(box: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box
	cs.shape = shape
	cs.position.y = box.y / 2.0
	return cs
