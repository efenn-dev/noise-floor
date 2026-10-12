extends "res://test/base_test.gd"
## Every car type in data/vehicles.json has a model (tools/art/<type>.py) with four separate wheels,
## the "Car Paint" and "Car Glass" materials the game swaps out, and a body that fits its size.


func test_each_type_has_a_drivable_model() -> void:
	var data := GameData.load_default()
	for type: String in data.vehicles:
		var path := "res://assets/models/%s.glb" % type
		check(ResourceLoader.exists(path), "%s has a model" % type)
		if not ResourceLoader.exists(path):
			continue
		var root := (load(path) as PackedScene).instantiate() as Node3D
		var wheels := root.find_children("Wheel_*", "MeshInstance3D", true, false)
		eq(wheels.size(), 4, "%s has four separate wheels" % type)
		var fronts := wheels.filter(func(w: Node3D) -> bool: return w.position.z < 0.0).size()
		eq(fronts, 2, "%s: two at the front (-Z)" % type)
		var mats := {}
		for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				if mat != null:
					mats[mat.resource_name] = true
		check(mats.has("Car Paint") and mats.has("Car Glass"), "%s uses Car Paint and Car Glass" % type)
		var size: Array = data.vehicles[type]["size"]
		for w: MeshInstance3D in wheels:
			check(absf(w.position.x) <= float(size[0]) / 2.0 and absf(w.position.z) <= float(size[2]) / 2.0,
					"%s/%s sits inside the footprint" % [type, w.name])
		root.free()
