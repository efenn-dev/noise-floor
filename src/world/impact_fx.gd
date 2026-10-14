class_name ImpactFx
extends RefCounted
## V3 (Sprint 4): a one-shot puff where something was struck. "blood" (dark red droplets that fall) on a
## zombie, "dust" (a slow grey cloud) on walls, ground and anything else. CPU particles, so they also run
## in the Compatibility renderer and headless; each frees itself when done.
## V7: blood stains (Decal nodes with tools/art/make_blood_splat.py's splat) on the ground under a hit and
## spreading under a body; they fade after a while and only MAX_STAINS exist at once (oldest go first).
## Decals need Forward+ or Mobile; the Compatibility renderer (cloud screenshots) doesn't draw them.

const KINDS := {
	"blood": {"amount": 24, "lifetime": 0.55, "speed": Vector2(1.6, 3.6), "gravity": -9.8, "spread": 38.0,
			"size": Vector2(0.05, 0.11), "color": Color(0.32, 0.02, 0.02)},
	"blood_head": {"amount": 40, "lifetime": 0.7, "speed": Vector2(2.2, 5.0), "gravity": -9.8, "spread": 60.0,
			"size": Vector2(0.06, 0.14), "color": Color(0.36, 0.02, 0.02)},
	"glass": {"amount": 34, "lifetime": 0.9, "speed": Vector2(1.2, 3.6), "gravity": -9.8, "spread": 75.0,
			"size": Vector2(0.02, 0.05), "color": Color(0.82, 0.92, 0.97, 0.9)},
	"wood": {"amount": 18, "lifetime": 0.8, "speed": Vector2(1.0, 3.0), "gravity": -9.8, "spread": 60.0,
			"size": Vector2(0.03, 0.07), "color": Color(0.46, 0.33, 0.19)},
	"dust": {"amount": 12, "lifetime": 0.9, "speed": Vector2(0.4, 1.4), "gravity": -0.6, "spread": 55.0,
			"size": Vector2(0.1, 0.26), "color": Color(0.55, 0.52, 0.47, 0.75)},
}

static var _meshes: Dictionary = {}  # kind -> QuadMesh with its billboard material

const SPLAT := preload("res://assets/textures/blood_splat.png")
const MAX_STAINS := 48
const STAIN_LIFE := 180.0  # seconds before a stain starts to fade
const STAIN_FADE := 12.0
static var _stains: Array = []  # oldest first


## A basis whose +Y is `up` (a Decal projects along its local -Y, so +Y points out of the surface).
static func basis_facing(up: Vector3) -> Basis:
	var n := up.normalized() if up.length() > 0.1 else Vector3.UP
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	return Basis(x, n, x.cross(n))


## A blood stain on the surface at `pos` (`normal` points out of it), size_m across. With grow_s > 0 it
## spreads from a quarter of that size over grow_s seconds (a pool under a body). Fades after `life` s.
static func stain(parent: Node, pos: Vector3, normal: Vector3, size_m: float, life: float = STAIN_LIFE, grow_s: float = 0.0) -> Decal:
	_stains = _stains.filter(func(d: Variant) -> bool: return is_instance_valid(d))
	var d := Decal.new()
	d.name = "BloodStain"
	d.top_level = true
	d.texture_albedo = SPLAT
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.cull_mask = 1  # the world, not the first-person weapons
	var b := basis_facing(normal)
	d.transform = Transform3D(b.rotated(b.y, randf() * TAU), pos)
	d.size = Vector3(size_m, 0.5, size_m) * (0.25 if grow_s > 0.0 else 1.0)
	d.size.y = 0.5
	parent.add_child(d)
	if d.is_inside_tree():
		var tw := d.create_tween()
		if grow_s > 0.0:
			tw.tween_property(d, "size", Vector3(size_m, 0.5, size_m), grow_s).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(maxf(0.0, life - STAIN_FADE - grow_s))
		tw.tween_property(d, "modulate:a", 0.0, STAIN_FADE)
		tw.tween_callback(d.queue_free)
	_stains.append(d)
	while _stains.size() > MAX_STAINS:
		var old: Variant = _stains.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	return d


static func stain_count() -> int:
	_stains = _stains.filter(func(d: Variant) -> bool: return is_instance_valid(d) and not (d as Node).is_queued_for_deletion())
	return _stains.size()


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
	_stains.clear()
