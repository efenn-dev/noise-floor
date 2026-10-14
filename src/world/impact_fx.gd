class_name ImpactFx
extends RefCounted
## V3 (Sprint 4): a one-shot puff where something was struck. "blood" (dark red droplets that fall) on a
## zombie, "dust" (a slow grey cloud) on walls, ground and anything else. CPU particles, so they also run
## in the Compatibility renderer and headless; each frees itself when done.

const KINDS := {
	"blood": {"amount": 24, "lifetime": 0.55, "speed": Vector2(1.6, 3.6), "gravity": -9.8, "spread": 38.0,
			"size": Vector2(0.05, 0.11), "color": Color(0.32, 0.02, 0.02)},
	"dust": {"amount": 12, "lifetime": 0.9, "speed": Vector2(0.4, 1.4), "gravity": -0.6, "spread": 55.0,
			"size": Vector2(0.1, 0.26), "color": Color(0.55, 0.52, 0.47, 0.75)},
}

static var _meshes: Dictionary = {}  # kind -> QuadMesh with its billboard material


static func spawn(parent: Node, pos: Vector3, normal: Vector3, kind: String) -> CPUParticles3D:
	var k: Dictionary = KINDS.get(kind, KINDS["dust"])
	var p := CPUParticles3D.new()
	p.name = "Impact_" + kind
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = k["amount"]
	p.lifetime = k["lifetime"]
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.spread = k["spread"]
	p.initial_velocity_min = k["speed"].x
	p.initial_velocity_max = k["speed"].y
	p.gravity = Vector3(0.0, k["gravity"], 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = k["size"].x
	p.scale_amount_max = k["size"].y
	var fade := Gradient.new()
	fade.set_color(0, k["color"])
	fade.set_color(1, Color(k["color"], 0.0))
	p.color_ramp = fade
	p.mesh = _mesh(kind)
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.position = pos + p.direction * 0.03  # just off the surface (top_level, so this is world space)
	p.emitting = true
	return p


static func _mesh(kind: String) -> QuadMesh:
	if not _meshes.has(kind):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mat := StandardMaterial3D.new()
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true  # without it every particle is a full 1 m quad
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = _soft_dot()  # round and soft-edged, not a square
		q.material = mat
		_meshes[kind] = q
	return _meshes[kind]


## A white dot fading to clear at its edge.
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


static func clear_cache() -> void:
	_meshes.clear()
