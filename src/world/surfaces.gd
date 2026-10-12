class_name Surfaces
extends RefCounted
## Textured materials from assets/textures/<name>_albedo.jpg + _normal.jpg (Codex-generated photos made
## seamless by tools/art/make_tileable.py). Mapping is world-space triplanar, so neighbouring boxes and
## pieces join without seams and nothing needs UVs. One shared material per name, tile size and tint.

const DEFAULT_TINT := Color(0.72, 0.72, 0.72)  # generated photos come out bright; noon sun washed them white

static var _cache: Dictionary = {}


## `tile_m` is how many metres one copy of the texture covers.
static func material(texture: String, tile_m: float = 2.0, tint: Color = DEFAULT_TINT) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [texture, tile_m, tint.to_html()]
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.92
		var albedo := "res://assets/textures/%s_albedo.jpg" % texture
		if not ResourceLoader.exists(albedo):  # not made yet (only the PC can make textures): plain colour
			mat.albedo_color = tint * 0.5  # about what the tint does to an average texture
			_cache[key] = mat
			return mat
		mat.albedo_texture = load(albedo)
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/%s_normal.jpg" % texture)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / tile_m
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache[key] = mat
	return _cache[key]


## Drop the shared materials (at exit, so Godot doesn't report them as still in use).
static func clear_cache() -> void:
	_cache.clear()
