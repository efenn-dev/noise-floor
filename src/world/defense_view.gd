class_name DefenseView
extends Node3D
## M15: draws what the automated defense is doing. Floodlights the sim says are lit get a spotlight and a
## glowing lamp; a sensor's lamp is red while it's on; a noisemaker's lamp flashes while it blares and is
## amber while it recharges. The rules are in Automation; this only reads them.

const LIGHT_RANGE := 22.0

var sim: SimWorld
var build_view: BuildView
var _lights: Dictionary = {}  # floodlight key -> SpotLight3D
var _t := 0.0


func setup(p_sim: SimWorld, p_build_view: BuildView) -> void:
	sim = p_sim
	build_view = p_build_view


func _process(delta: float) -> void:
	_t += delta
	var auto := sim.automation
	for key: String in _lights.keys():
		if not auto.floodlights.has(key) or not is_instance_valid(_lights[key]):
			_lights.erase(key)
	for key: String in auto.floodlights:
		var lit: bool = auto.floodlights[key]["lit"]
		var body := build_view.body_for(key)
		if body == null:
			continue
		if lit and not _lights.has(key):
			var spot := SpotLight3D.new()
			spot.light_color = Color(1.0, 0.95, 0.82)
			spot.light_energy = 6.0
			spot.spot_range = LIGHT_RANGE
			spot.spot_angle = 55.0
			spot.shadow_enabled = false
			spot.position = Vector3(0, 1.3, -0.3)
			spot.rotation_degrees = Vector3(-50, 0, 0)  # down and out, the way it faces
			body.add_child(spot)
			_lights[key] = spot
		if _lights.has(key):
			_lights[key].visible = lit
		_lamp(body, Color(1.0, 0.95, 0.75) if lit else Color(0.25, 0.25, 0.22), lit)
	for key: String in auto.sensors:
		var sbody := build_view.body_for(key)
		if sbody != null:
			var on: bool = auto.sensors[key]["on"]
			_lamp(sbody, Color(1.0, 0.15, 0.1) if on else Color(0.15, 0.6, 0.2), true)
	for key: String in auto.noisemakers:
		var nbody := build_view.body_for(key)
		if nbody == null:
			continue
		var n: Dictionary = auto.noisemakers[key]
		if n["blare"] > 0.0:
			var flash := fmod(_t, 0.5) < 0.25
			_lamp(nbody, Color(1.0, 0.2, 0.1) if flash else Color(0.3, 0.05, 0.05), flash)
		elif n["recharge"] > 0.0:
			_lamp(nbody, Color(1.0, 0.6, 0.1), true)
		else:
			_lamp(nbody, Color(0.2, 0.9, 0.3), true)


func _lamp(body: Node3D, color: Color, glow: bool) -> void:
	var lamp := body.get_node_or_null("Lamp") as MeshInstance3D
	if lamp == null or not lamp.material_override is StandardMaterial3D:
		return
	var mat := lamp.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission_enabled = glow
	mat.emission = color
