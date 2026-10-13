extends "res://test/base_test.gd"
## Zombie bodies show what kind they are and what they're doing: runners run, screamers scream.


func _body(type: String) -> ZombieBody:
	var data := GameData.load_default()
	var brain := ZombieBrain.new(7, type, data.zombies[type], Vector3.ZERO, 1)
	var body := ZombieBody.new()
	tree.root.add_child(body)
	body.setup(brain, null)
	return body


func test_runners_run() -> void:
	var body := _body("runner")
	await tree.process_frame
	body.velocity = Vector3(3.2, 0, 0)
	body.brain.state = ZombieBrain.State.CHASE
	body._animate(0.016)
	eq(body._anim.assigned_animation, "Run", "a fast runner plays Run")
	body.velocity = Vector3(0.8, 0, 0)
	body._animate(0.016)
	eq(body._anim.assigned_animation, "Walk", "slow, it walks")
	check(body._model.scale.x < 1.0, "runners are a little smaller")
	body.queue_free()
	await tree.process_frame


func test_screamers_scream() -> void:
	var body := _body("screamer")
	await tree.process_frame
	body.brain.screaming = 1.0
	body._animate(0.016)
	eq(body._anim.assigned_animation, "Scream", "a screaming screamer plays Scream")
	body.brain.screaming = 0.0
	body._animate(0.016)
	check(body._anim.assigned_animation != "Scream", "and stops when it's done")
	body.queue_free()
	await tree.process_frame


func test_kinds_look_different() -> void:
	var shirts := {}
	for type in ["shambler", "runner", "screamer"]:
		var body := _body(type)
		await tree.process_frame
		for mesh: MeshInstance3D in body._model.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var mat := mesh.get_surface_override_material(i) as StandardMaterial3D
				if mat != null and mat.resource_name == "Shirt":
					shirts[type] = mat.albedo_color
		body.queue_free()
		await tree.process_frame
	eq(shirts.size(), 3, "each kind has a tinted shirt")
	check(shirts["runner"] != shirts["screamer"] and shirts["screamer"] != shirts["shambler"], "and they differ")
