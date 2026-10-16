class_name CartView
extends Node3D
## F5: draws the supply carts (Carts in the sim): a small flatbed with four wheels, two glowing headlamps (so it shows
## at night) and, while it carries something, a crate on the back, where the sim says each one is on its road and
## facing the way it drives. Built from boxes and cylinders in code (no model yet). Wheels turn while it drives.

const BODY := Color(0.55, 0.22, 0.16)
const WHEEL := Color(0.1, 0.1, 0.1)
const CRATE := Color(0.5, 0.38, 0.22)

var sim: SimWorld
var _carts: Dictionary = {}  # pickup stop key -> Node3D


func _init(p_sim: SimWorld) -> void:
	sim = p_sim


func _process(delta: float) -> void:
	for key: String in _carts.keys():
		if not sim.carts.carts.has(key):
			_carts[key].queue_free()
			_carts.erase(key)
	for key: String in sim.carts.carts:
		var node: Node3D = _carts.get(key)
		if node == null:
			node = make_cart()
			add_child(node)
			_carts[key] = node
		var at: Dictionary = sim.carts.cart_at(key)
		node.position = at["pos"]
		node.rotation.y = at["yaw"]
		(node.get_node("Crate") as Node3D).visible = not (sim.carts.carts[key]["cargo"] as Dictionary).is_empty()
		if at["moving"]:
			for w: Node in node.get_children():
				if w.name.begins_with("Wheel"):
					(w as Node3D).rotate_object_local(Vector3.UP, -delta * 6.0)


## One cart, front = -Z (the way it drives), standing on the ground.
static func make_cart() -> Node3D:
	var root := Node3D.new()
	root.name = "Cart"
	_box(root, "Bed", Vector3(1.2, 0.18, 1.9), Vector3(0, 0.45, 0), BODY)
	_box(root, "Cab", Vector3(1.1, 0.55, 0.6), Vector3(0, 0.8, -0.6), BODY.darkened(0.2))
	var crate := _box(root, "Crate", Vector3(0.9, 0.6, 0.9), Vector3(0, 0.84, 0.35), CRATE)
	crate.visible = false
	for x: float in [-0.38, 0.38]:  # headlamps, so you can see it coming at night
		var lamp := _box(root, "Lamp", Vector3(0.18, 0.12, 0.04), Vector3(x, 0.78, -0.92), Color(1.0, 0.9, 0.6))
		var glow := lamp.material_override as StandardMaterial3D
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.85, 0.5)
		glow.emission_energy_multiplier = 3.0
	var i := 0
	for x: float in [-0.62, 0.62]:
		for z: float in [-0.65, 0.65]:
			var w := MeshInstance3D.new()
			w.name = "Wheel%d" % i
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = 0.16
			w.mesh = cyl
			w.material_override = _mat(WHEEL)
			w.position = Vector3(x, 0.28, z)
			w.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(w)
			i += 1
	return root


static func _box(parent: Node3D, part: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = part
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = _mat(color)
	m.position = at
	parent.add_child(m)
	return m


static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
