class_name DefenseView
extends Node3D
## M15: draws what the automated defense is doing. Floodlights the sim says are lit get a spotlight and a
## glowing lamp; a sensor's lamp is red while it's on; a noisemaker's lamp flashes while it blares and is
## amber while it recharges. The rules are in Automation; this only reads them.
## M16: a lit stove's lamp glows like a fire and it lights the room with a warm flickering light; a powered
## electric heater's lamp glows orange. The rules are in Climate.

const LIGHT_RANGE := 22.0

var sim: SimWorld
var build_view: BuildView
var _lights: Dictionary = {}  # floodlight key -> SpotLight3D
var _fires: Dictionary = {}   # M16: stove key -> OmniLight3D
const FIRE_COLOR := Color(1.0, 0.55, 0.22)
const FIRE_RANGE := 7.0
var _t := 0.0


func setup(p_sim: SimWorld, p_build_view: BuildView) -> void:
	sim = p_sim
	build_view = p_build_view


func _process(delta: float) -> void:
	_mast(delta)  # F2
	_t += delta
	_heat()
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


## M16: stoves and heaters.
func _heat() -> void:
	var c := sim.climate
	for key: String in _fires.keys():
		if not c.stoves.has(key) or not is_instance_valid(_fires[key]):
			_fires.erase(key)
	for key: String in c.stoves:
		var body := build_view.body_for(key)
		if body == null:
			continue
		var lit: bool = c.stoves[key]["lit"]
		if lit and not _fires.has(key):
			var fire := OmniLight3D.new()
			fire.light_color = FIRE_COLOR
			fire.omni_range = FIRE_RANGE
			fire.shadow_enabled = false
			fire.position = Vector3(0, 1.0, -0.9)  # in front of the firebox
			body.add_child(fire)
			_fires[key] = fire
		if _fires.has(key):
			_fires[key].visible = lit
			_fires[key].light_energy = 2.2 + 0.35 * sin(_t * 9.0) + 0.2 * sin(_t * 23.0)
		_lamp(body, FIRE_COLOR if lit else Color(0.12, 0.1, 0.1), lit)
	for key: String in c.heaters:
		var hbody := build_view.body_for(key)
		if hbody != null:
			var on := c.heater_on(key)
			_lamp(hbody, Color(1.0, 0.45, 0.15) if on else Color(0.2, 0.2, 0.2), on)


## F2: the radio mast's warning light: blinking red while it broadcasts, dark otherwise.
var _blink := 0.0


func _mast(delta: float) -> void:
	var key := sim.mast_key()
	if key == "" or build_view == null:
		return
	var body := build_view.body_for(key)
	if body == null:
		return
	_blink += delta
	var on := sim.rescue_state == "broadcasting" and fmod(_blink, 1.2) < 0.7
	_lamp(body, Color(1.0, 0.12, 0.08) if on else Color(0.25, 0.08, 0.06), on)


func _lamp(body: Node3D, color: Color, glow: bool) -> void:
	var lamp := body.get_node_or_null("Lamp") as MeshInstance3D
	if lamp == null or not lamp.material_override is StandardMaterial3D:
		return
	var mat := lamp.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission_enabled = glow
	mat.emission = color
