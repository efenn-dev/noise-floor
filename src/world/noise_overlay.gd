class_name NoiseOverlay
extends Node3D
## Debug view of the noise system (N toggles). For each working machine, two rings on the ground show
## how far zombies hear it through its leakiest side: solid = by day, faint = at night. One-off sounds
## flash a ring. A mark over each zombie shows its state (grey idle, yellow investigating, red chasing,
## orange breaking). Rings ignore the town's buildings, as the noise rules do for now.

const SEGMENTS := 72
const STATE_COLORS := {
	"idle": Color(0.6, 0.6, 0.6), "wander": Color(0.6, 0.6, 0.6), "investigate": Color(1.0, 0.9, 0.2),
	"chase": Color(1.0, 0.2, 0.2), "attack": Color(1.0, 0.2, 0.2), "break": Color(1.0, 0.55, 0.1),
}

var sim: SimWorld
var _mesh := ImmediateMesh.new()
var _draw: MeshInstance3D


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	_draw = MeshInstance3D.new()
	_draw.mesh = _mesh
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true  # see rings through walls
	_draw.material_override = mat
	add_child(_draw)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("noise_overlay"):
		visible = not visible


## Radius (m) at which a sound of `loudness` drops to `threshold` in open air.
static func reach(loudness: float, threshold: float) -> float:
	return pow(10.0, (loudness - threshold) / 20.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var z: Dictionary = sim.data.zombies["shambler"]
	var dist := float(sim.data.noise["director"]["listen_distance"])
	for s: Dictionary in sim.noise.continuous:
		# The leakiest direction's level at `dist`, turned back into an equivalent open-air loudness.
		var effective := sim.noise.outdoor_level(s, dist) + 20.0 * log(dist) / log(10.0)
		_ring(s["pos"], reach(effective, float(z["hearing_day"])), Color(1.0, 0.45, 0.2, 0.9))
		_ring(s["pos"], reach(effective, float(z["hearing_night"])), Color(0.5, 0.6, 1.0, 0.5))
	for s: Dictionary in sim.noise.recent:
		var fade: float = 1.0 - s["age"] / NoiseField.DRAW_TIME
		_ring(s["pos"], reach(sim.noise.level(s["loudness"], 1.0, 0), float(z["hearing_day"])), Color(1.0, 1.0, 1.0, 0.8 * fade))
	for id: int in sim.horde.zombies:
		var b: ZombieBrain = sim.horde.zombies[id]
		if b.is_dead():
			continue
		var c: Color = STATE_COLORS.get(b.state_name(), Color.WHITE)
		_line(b.pos + Vector3.UP * 2.0, b.pos + Vector3.UP * 2.6, c)
		if b.state == ZombieBrain.State.INVESTIGATE:
			_line(b.pos + Vector3.UP * 0.1, b.target_pos, Color(c, 0.35))
	_mesh.surface_end()


func _ring(center: Vector3, radius: float, color: Color) -> void:
	if radius < 0.5:
		return
	var y := 0.15
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		_line(Vector3(center.x + cos(a0) * radius, y, center.z + sin(a0) * radius),
				Vector3(center.x + cos(a1) * radius, y, center.z + sin(a1) * radius), color)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)


## Lines for the HUD while the overlay is on.
func status_text() -> String:
	if not visible:
		return ""
	var d := sim.director
	# V28: the debug HUD names every live type as well as drawing its state marker.
	var counts := {}
	for brain: ZombieBrain in sim.horde.zombies.values():
		if not brain.is_dead():
			counts[brain.type] = int(counts.get(brain.type, 0)) + 1
	var names := counts.keys()
	names.sort()
	var types := PackedStringArray()
	for type: String in names:
		types.append("%s %d" % [sim.data.zombies[type]["name"], counts[type]])
	var alive := "none" if types.is_empty() else ", ".join(types)
	return "NOISE  heat %d (%s)  ·  +%.1f/s from machines, -%.2f/s cooling  ·  alive: %s  ·  N hides" % [
		roundi(d.heat), d.level_name(), d.gain, float(d.cfg["decay"]), alive]
