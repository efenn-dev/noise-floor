extends "res://test/base_test.gd"
## The models BuildView uses (assets/models/, built by tools/art/*.py): each loads, sits on the
## floor of its piece's collision box and fits inside it, is merged into one mesh, and machines
## and generators carry the status lamp FactoryView recolours, and turrets the Head it aims.

const LAMP_ALLOWANCE := 0.2  # tools/art/kit.py: a lamp or turret head may rise this far above the box
const OVERHANG := {"power_pole": Vector3(0.4, 0.0, 0.05), "floodlight": Vector3(0.4, 0.0, 0.05)}  # the crossbar is wider than the pole (M15: the floodlight is a pole too)
const SLACK := 0.01


func test_models_fit_their_pieces() -> void:
	var data := GameData.load_default()
	for id: String in BuildView.MODELS:
		var scene := load(BuildView.MODELS[id]) as PackedScene
		check(scene != null and data.buildables.has(id), "%s model loads and is a buildable" % id)
		if scene == null or not data.buildables.has(id):
			continue
		var root := scene.instantiate() as Node3D
		var half: Vector3 = data.buildables[id]["size"] / 2.0 + OVERHANG.get(id, Vector3.ZERO)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		var lamp := root.get_node_or_null("Lamp")
		var head := root.get_node_or_null("Head")
		check(meshes.size() <= 2, "%s is one merged mesh plus its lamp or head (%d meshes)" % [id, meshes.size()])
		if data.buildables[id]["kind"] in ["machine", "generator"]:
			check(lamp is MeshInstance3D, "%s has a Lamp directly under the model root" % id)
		if data.buildables[id]["kind"] == "turret":
			check(head is MeshInstance3D, "%s has a Head directly under the model root" % id)
		var lowest := INF
		for m: MeshInstance3D in meshes:
			var box := _transform_to(root, m) * m.get_aabb()
			var top := half.y + (LAMP_ALLOWANCE if m == lamp or m == head else 0.0)
			var inside := box.position.x >= -half.x - SLACK and box.end.x <= half.x + SLACK \
					and box.position.z >= -half.z - SLACK and box.end.z <= half.z + SLACK \
					and box.position.y >= -half.y - SLACK and box.end.y <= top + SLACK
			check(inside, "%s/%s fits its %s box (%s)" % [id, m.name, data.buildables[id]["size"], box])
			lowest = minf(lowest, box.position.y)
		near(lowest, -half.y, "%s stands on the floor of its box" % id, 0.02)
		root.free()


func test_models_face_the_right_way() -> void:
	# Pieces face -Z (BuildGrid), so a model's OUTPUT_ORANGE paint is at -Z and INPUT_BLUE at +Z.
	for id: String in BuildView.MODELS:
		var root := (load(BuildView.MODELS[id]) as PackedScene).instantiate() as Node3D
		for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var xf := _transform_to(root, m)
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				var paint := mat.resource_name if mat != null else ""
				if paint not in ["OUTPUT_ORANGE", "INPUT_BLUE"]:
					continue
				var z := 0.0
				var verts: PackedVector3Array = m.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				for v in verts:
					z += (xf * v).z / verts.size()
				var front := paint == "OUTPUT_ORANGE"
				check(z < 0.0 if front else z > 0.0, "%s: %s is at the %s (mean z %.2f)" % [id, paint, "front" if front else "back", z])
		root.free()


## W1c: furniture has no in/out paint, so each prop names a material that must sit at its front (-Z, the
## room) or its back (+Z, the wall). The table is symmetric: chairs at both ends.
const PROP_FACING := {"counter": ["Cupboard Doors", -1], "couch": ["Couch Back", 1], "shelf": ["Shelf Back", 1],
		"bathtub": ["Tap Chrome", 1], "toilet": ["Cistern", 1]}


func test_furniture_faces_the_room() -> void:
	for id: String in PROP_FACING:
		var root := (load(BuildView.MODELS[id]) as PackedScene).instantiate() as Node3D
		var z := 0.0
		var n := 0
		for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var xf := _transform_to(root, m)
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				if mat == null or mat.resource_name != PROP_FACING[id][0]:
					continue
				for v: Vector3 in m.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					z += (xf * v).z
					n += 1
		check(n > 0, "%s has its %s material" % [id, PROP_FACING[id][0]])
		var mean := z / maxf(n, 1)
		var back: bool = PROP_FACING[id][1] > 0
		check(mean > 0.05 if back else mean < -0.05, "%s: %s is at the %s (mean z %.2f)" % [id, PROP_FACING[id][0], "back" if back else "front", mean])
		root.free()


func test_each_machine_gets_its_own_lamp() -> void:
	var sim := SimWorld.new(10.0)
	sim.give_debug_kit()
	var view := BuildView.new()
	tree.root.add_child(view)
	view.setup(sim.build)
	for x in [0, 1]:
		sim.build.place("foundation", Vector2i(x, 0), 0, sim.inventory)
		eq(sim.build.place("press", Vector2i(x, 0), BuildGrid.Side.EAST, sim.inventory), "", "press %d placed" % x)
	var lamps := []
	for x in [0, 1]:
		var body := view.body_for("o:%d:0" % x)
		var lamp := body.get_node_or_null("Lamp") as MeshInstance3D if body != null else null
		check(lamp != null and lamp.material_override is StandardMaterial3D, "press %d has a recolourable lamp" % x)
		if lamp != null:
			lamps.append(lamp.material_override)
	check(lamps.size() == 2 and lamps[0] != lamps[1], "the two presses don't share a lamp material")
	view.free()


func _transform_to(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
