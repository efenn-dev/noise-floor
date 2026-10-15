class_name RoadView
extends Node3D
## W3a: draws the bigger map's new roads (WorldMap.ROADS with "drawn"; Main Street and the park road are drawn
## by main.gd as before): asphalt with white centre dashes, the highway with lane dashes and edge lines, dirt
## tracks in packed earth. Flat strips just above the ground with no colliders (the ground is the floor), a disc
## at each bend so corners have no gaps. Each road sits a hair above the one before so crossings don't flicker.

const LIFT := 0.011        # above the ground (main.gd's old roads sit at 0.01-0.02)
const STEP := 0.0015       # each road a little higher than the last
const DASH := Vector3(0.18, 0.012, 3.0)
const DASH_GAP := 9.0      # metres from one dash to the next
const LANE := 4.0          # the highway's lanes

var strips := 0  # road pieces drawn, for tests


func _ready() -> void:
	var asphalt := Surfaces.material("asphalt", 4.0, Color(0.52, 0.52, 0.52))
	var highway := Surfaces.material("asphalt", 4.0, Color(0.46, 0.46, 0.47))
	var dirt := Surfaces.material("ground", 3.0, Color(0.55, 0.45, 0.33))
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.85, 0.78)
	paint.roughness = 0.8
	var dashes: Array[Transform3D] = []
	var i := 0
	for road: Dictionary in WorldMap.ROADS:
		if not road["drawn"]:
			continue
		i += 1
		var y := LIFT + STEP * i
		var mat: Material = dirt if road["kind"] == "dirt" else (highway if road["kind"] == "highway" else asphalt)
		var width: float = road["width"]
		var pts: Array = road["points"]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			_strip(a, b, width, y, mat)
			if road["kind"] == "asphalt":
				_dash_line(a, b, 0.0, dashes)
			elif road["kind"] == "highway":
				for lane: float in [-LANE, 0.0, LANE]:
					_dash_line(a, b, lane, dashes)
				for edge: float in [-width / 2.0 + 0.4, width / 2.0 - 0.4]:
					_line(a, b, edge, y + 0.004, paint)
		for k in range(1, pts.size() - 1):
			_disc(pts[k], width, y, mat)
	if not dashes.is_empty():
		var multi := MultiMeshInstance3D.new()
		multi.name = "RoadDashes"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var box := BoxMesh.new()
		box.size = DASH
		mm.mesh = box
		mm.instance_count = dashes.size()
		for d in dashes.size():
			mm.set_instance_transform(d, dashes[d])
		multi.multimesh = mm
		multi.material_override = paint
		multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(multi)


func _strip(a: Vector2, b: Vector2, width: float, y: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := a.distance_to(b)
	box.size = Vector3(width, 0.02, length)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) / 2.0
	mesh.position = Vector3(mid.x, y - 0.01, mid.y)
	mesh.rotation.y = atan2(b.x - a.x, b.y - a.y)
	add_child(mesh)
	strips += 1


func _disc(at: Vector2, width: float, y: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = width / 2.0
	disc.bottom_radius = width / 2.0
	disc.height = 0.02
	disc.radial_segments = 24
	mesh.mesh = disc
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(at.x, y - 0.01, at.y)
	add_child(mesh)


## Dashes along a-b, `offset` metres to its right, skipping the ends (crossings).
func _dash_line(a: Vector2, b: Vector2, offset: float, out: Array[Transform3D]) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var right := Vector2(-dir.y, dir.x)
	var yaw := atan2(dir.x, dir.y)
	var along := 8.0
	while along < length - 8.0:
		var p := a + dir * along + right * offset
		out.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.035, p.y)))  # on top of the highest road
		along += DASH_GAP


## A solid painted line along a-b, `offset` metres to its right.
func _line(a: Vector2, b: Vector2, offset: float, y: float, mat: Material) -> void:
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.012, a.distance_to(b))
	mesh.mesh = box
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) / 2.0 + right * offset
	mesh.position = Vector3(mid.x, y, mid.y)
	mesh.rotation.y = atan2(dir.x, dir.y)
	add_child(mesh)
