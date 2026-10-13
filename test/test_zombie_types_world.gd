extends "res://test/base_test.gd"
## Zombie bodies show what kind they are and what they're doing: runners run, screamers scream.


func _body(type: String, id: int = 7) -> ZombieBody:
	var data := GameData.load_default()
	var brain := ZombieBrain.new(id, type, data.zombies[type], Vector3.ZERO, 1)
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


## A2: each zombie wears one of five bodies, picked from its id and kind: the same one every time, and a
## mix across a crowd. Every body plays the animations.
func test_bodies_are_picked_per_zombie() -> void:
	var seen := {}
	for id in range(1, 21):
		var v := ZombieBody.variant_for(id, "shambler")
		eq(ZombieBody.variant_for(id, "shambler"), v, "zombie %d gets the same body every time" % id)
		seen[v] = true
	check(seen.size() >= 3, "ids 1-20 wear at least three different bodies (%d)" % seen.size())
	for id in [1, 2, 3, 4, 5, 6]:
		var a := _body("shambler", id)
		var b := _body("shambler", id)
		await tree.process_frame
		eq(a.body_variant, ZombieBody.BODIES[ZombieBody.variant_for(id, "shambler")], "zombie %d wears its picked body" % id)
		eq(b.body_variant, a.body_variant, "a second zombie %d wears the same body" % id)
		eq(a._model.get_parent(), a, "and only that model is on it")
		eq(a.find_children("*", "AnimationPlayer", true, false).size(), 1, "one AnimationPlayer (the old body is gone)")
		a.velocity = Vector3(0.8, 0, 0)
		a.brain.state = ZombieBrain.State.CHASE
		a._animate(0.016)
		eq(a._anim.assigned_animation, "Walk", "the %s body walks" % a.body_variant)
		a.queue_free()
		b.queue_free()
		await tree.process_frame


## A2: runners stay small and dark, screamers pale with red shirts, and Old Pete big in red, on every body.
func test_kinds_keep_their_look_on_every_body() -> void:
	var data := GameData.load_default()
	for type: String in ["runner", "screamer", "old_pete"]:
		var look: Dictionary = ZombieBody.LOOKS[type]
		var bodies := {}
		for id in range(1, 400):
			var v := ZombieBody.variant_for(id, type)
			if bodies.has(v):
				continue
			bodies[v] = true
			var body := _body(type, id)
			var colours := _colours(body)
			eq(colours.get("Zombie Skin"), look["skin"], "a %s on the %s body has its skin" % [type, body.body_variant])
			check(colours.get("Shirt") in look["shirts"], "a %s on the %s body has its shirt" % [type, body.body_variant])
			if type == "runner":
				check(body._model.scale.x < 1.0, "a runner on the %s body is smaller" % body.body_variant)
				for cloth: String in ["Vest", "Hard Hat", "Cap"]:
					if colours.has(cloth):
						check(colours[cloth].get_luminance() < 0.3, "a runner's %s is dark (%s)" % [cloth, colours[cloth]])
			if type == "old_pete":
				check(body._model.scale.x > 1.15, "Old Pete on the %s body is big (%.2f)" % [body.body_variant, body._model.scale.x])
			body.queue_free()
			await tree.process_frame
		eq(bodies.size(), ZombieBody.BODIES.size(), "%ss come in every body" % type)
	check(data.zombies.has("old_pete"), "old_pete is a zombie kind")


## Every tinted (override) colour on a body, by material name.
func _colours(body: ZombieBody) -> Dictionary:
	var out := {}
	for mesh: MeshInstance3D in body._model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(i) as StandardMaterial3D
			if mat != null:
				out[mat.resource_name] = mat.albedo_color
	return out
