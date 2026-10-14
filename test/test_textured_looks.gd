extends "res://test/base_test.gd"
## S3-1c: every authored zombie/gun material has an intentional treatment, deterministic clothes have
## real variety, and every configured albedo/normal pair is present.

const ZOMBIE_MODELS := [
	"res://assets/models/zombie.glb",
	"res://assets/models/zombie_heavy.glb",
	"res://assets/models/zombie_slim.glb",
	"res://assets/models/zombie_short.glb",
	"res://assets/models/zombie_woman.glb",
]


func test_every_model_material_is_accounted_for() -> void:
	for path: String in ZOMBIE_MODELS:
		for material_name: String in _material_names(path):
			check(ZombieBody.LOOK_DATA["materials"].has(material_name)
					or material_name in ZombieBody.LOOK_DATA["untextured"],
					"%s material '%s' is textured or explicitly untextured" % [path, material_name])
	for path: String in Shooter.MODELS.values() + Shooter.PART_MODELS.values() + Thrower.MODELS.values():
		for material_name: String in _material_names(path):
			check(Shooter.GUN_LOOKS["materials"].has(material_name)
					or material_name in Shooter.GUN_LOOKS["untextured"],
					"%s material '%s' is textured or explicitly untextured" % [path, material_name])


func test_shirt_look_is_deterministic_and_varied() -> void:
	var seen := {}
	var fabrics := {}
	for id in range(21):
		var first := ZombieBody.shirt_look_for(id)
		var second := ZombieBody.shirt_look_for(id)
		eq(second, first, "zombie %d gets the same shirt look every time" % id)
		var tint: Color = first["tint"]
		seen["%s|%s" % [first["texture"], tint.to_html()]] = true
		fabrics[first["texture"]] = true
	check(seen.size() >= 3, "ids 0-20 include at least three shirt looks (%d)" % seen.size())
	eq(fabrics.size(), ZombieBody.LOOK_DATA["shirt_textures"].size(), "ids 0-20 use all three shirt fabrics")


func test_every_mapped_texture_pair_exists() -> void:
	var textures := {}
	for mapping: Dictionary in ZombieBody.LOOK_DATA["materials"].values():
		textures[mapping["texture"]] = true
	for texture: String in ZombieBody.LOOK_DATA["shirt_textures"]:
		textures[texture] = true
	for mapping: Dictionary in Shooter.GUN_LOOKS["materials"].values():
		textures[mapping["texture"]] = true
	for texture: String in textures:
		for kind in ["albedo", "normal"]:
			var path := "res://assets/textures/%s_%s.jpg" % [texture, kind]
			check(ResourceLoader.exists(path), "%s exists" % path)


func test_runtime_materials_use_object_space_triplanar_and_normals() -> void:
	var data := GameData.load_default()
	var body := ZombieBody.new()
	tree.root.add_child(body)
	body.setup(ZombieBrain.new(8, "shambler", data.zombies["shambler"], Vector3.ZERO, 1), null)
	_check_overrides(body._model, ZombieBody.LOOK_DATA["materials"], "zombie")
	body.free()

	for path: String in Shooter.MODELS.values() + Shooter.PART_MODELS.values() + Thrower.MODELS.values():
		var gun := (load(path) as PackedScene).instantiate() as Node3D
		Shooter.apply_textured_materials(gun)
		_check_overrides(gun, Shooter.GUN_LOOKS["materials"], path)
		gun.free()


func _material_names(path: String) -> PackedStringArray:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var found := {}
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if material != null:
				found[material.resource_name] = true
	root.free()
	var names := PackedStringArray()
	for material_name: String in found:
		names.append(material_name)
	names.sort()
	return names


func _check_overrides(root: Node3D, mappings: Dictionary, label: String) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			if source == null or not mappings.has(source.resource_name):
				continue
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			check(material != null, "%s %s has an override" % [label, source.resource_name])
			if material == null:
				continue
			check(material.uv1_triplanar, "%s %s uses triplanar" % [label, source.resource_name])
			check(not material.uv1_world_triplanar, "%s %s uses object space" % [label, source.resource_name])
			check(material.normal_enabled and material.normal_texture != null,
					"%s %s has its normal map" % [label, source.resource_name])
