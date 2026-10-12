class_name FactoryView
extends Node3D
## Draws what the factory is doing: items riding belts (smoothed between sim ticks), a lamp on each
## machine (green working, amber output full, red wants power but has none) and on each generator
## (green running), and the power wires between connected pieces.

const ITEM_SIZE := 0.3

var sim: SimWorld
var build_view: BuildView
var _pool: Array[MeshInstance3D] = []
var items_shown := 0  # belt items drawn last frame
var _materials: Dictionary = {}  # item -> material
var _item_mesh := BoxMesh.new()


func setup(p_sim: SimWorld, p_build_view: BuildView) -> void:
	sim = p_sim
	build_view = p_build_view
	_item_mesh.size = Vector3.ONE * ITEM_SIZE


var _wires := ImmediateMesh.new()
var _wire_node: MeshInstance3D
var _wired_links: Array = []


var _tracers := ImmediateMesh.new()
var _tracer_node: MeshInstance3D


func _process(_delta: float) -> void:
	_draw_items()
	_draw_lamps()
	_draw_wires()
	_draw_turrets()


## Turret heads swing toward their target; each shot leaves a brief tracer.
func _draw_turrets() -> void:
	for cell: Vector2i in sim.factory.turrets:
		var t: Factory.Turret = sim.factory.turrets[cell]
		var body := build_view.body_for("o:%d:%d" % [cell.x, cell.y])
		var head := body.get_node_or_null("Head") as Node3D if body != null else null
		if head == null or not sim.horde.zombies.has(t.target):
			continue
		var to: Vector3 = sim.horde.zombies[t.target].pos - head.global_position
		head.global_rotation.y = atan2(-to.x, -to.z)
	if _tracer_node == null:
		_tracer_node = MeshInstance3D.new()
		_tracer_node.mesh = _tracers
		_tracer_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.9, 0.5)
		_tracer_node.material_override = mat
		add_child(_tracer_node)
	_tracers.clear_surfaces()
	if sim.defense.recent_shots.is_empty():
		return
	_tracers.surface_begin(Mesh.PRIMITIVE_LINES)
	for s: Dictionary in sim.defense.recent_shots:
		_tracers.surface_add_vertex(s["from"])
		_tracers.surface_add_vertex(s["to"])
	_tracers.surface_end()


## Wires sag a little between the tops of connected pieces; redrawn only when the network changes.
func _draw_wires() -> void:
	sim.power.refresh()
	if sim.power.links == _wired_links:
		return
	_wired_links = sim.power.links.duplicate()
	if _wire_node == null:
		_wire_node = MeshInstance3D.new()
		_wire_node.mesh = _wires
		_wire_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.08, 0.08, 0.08)
		_wire_node.material_override = mat
		add_child(_wire_node)
	_wires.clear_surfaces()
	if _wired_links.is_empty():
		return
	_wires.surface_begin(Mesh.PRIMITIVE_LINES)
	for link: Array in _wired_links:
		var a := _wire_end(link[0])
		var b := _wire_end(link[1])
		var mid := (a + b) / 2.0 - Vector3(0, 0.03 * a.distance_to(b), 0)
		for seg in [[a, mid], [mid, b]]:
			_wires.surface_add_vertex(seg[0])
			_wires.surface_add_vertex(seg[1])
	_wires.surface_end()


func _wire_end(key: String) -> Vector3:
	var piece: Dictionary = sim.build.pieces[key]
	var size: Vector3 = sim.data.buildables[piece["id"]]["size"]
	return sim.build.piece_center(key) + Vector3(0, size.y / 2.0 - (0.2 if sim.build.kind_of(piece["id"]) == "pole" else 0.0), 0)


func _draw_items() -> void:
	var alpha := sim.alpha()
	var used := 0
	var grid := sim.build
	var belt_h: float = sim.data.buildables["belt"]["size"].y
	var y := grid.foundation_top() + belt_h + ITEM_SIZE / 2.0
	for cell: Vector2i in sim.factory.belts:
		var belt: Factory.Belt = sim.factory.belts[cell]
		var d: Vector2i = Factory.DIRS[belt.facing]
		var dir := Vector3(d.x, 0, d.y)
		var center := Vector3((cell.x + 0.5) * BuildGrid.GRID, y, (cell.y + 0.5) * BuildGrid.GRID)
		for entry: Dictionary in belt.items:
			var t := lerpf(entry["prev"], entry["pos"], alpha)
			var mesh := _get_mesh(used)
			used += 1
			mesh.position = center + dir * (t - 0.5) * BuildGrid.GRID
			mesh.material_override = _material(entry["item"])
			mesh.visible = true
	for i in range(used, _pool.size()):
		_pool[i].visible = false
	items_shown = used


func _draw_lamps() -> void:
	for key: String in sim.power.generators:
		var gbody := build_view.body_for(key)
		var glamp := gbody.get_node_or_null("Lamp") as MeshInstance3D if gbody != null else null
		if glamp != null:
			var running: bool = sim.power.generators[key]["running"]
			var gm := glamp.material_override as StandardMaterial3D
			gm.albedo_color = Color(0.2, 1.0, 0.3) if running else Color(0.25, 0.25, 0.25)
			gm.emission_enabled = running
			gm.emission = gm.albedo_color
	for cell: Vector2i in sim.factory.machines:
		var body := build_view.body_for("o:%d:%d" % [cell.x, cell.y])
		if body == null:
			continue
		var lamp := body.get_node_or_null("Lamp") as MeshInstance3D
		if lamp == null:
			continue
		var m: Factory.Machine = sim.factory.machines[cell]
		var mat := lamp.material_override as StandardMaterial3D
		var status := m.status()
		var color := Color(0.2, 1.0, 0.3) if m.crafting and m.powered else (Color(1.0, 0.6, 0.1) if status == "output full"
				else (Color(0.9, 0.15, 0.15) if status == "no power" and m.wants_power() else Color(0.25, 0.25, 0.25)))
		mat.albedo_color = color
		mat.emission_enabled = color != Color(0.25, 0.25, 0.25)
		mat.emission = color


func _get_mesh(i: int) -> MeshInstance3D:
	while _pool.size() <= i:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _item_mesh
		add_child(mesh)
		_pool.append(mesh)
	return _pool[i]


func _material(item: String) -> StandardMaterial3D:
	if not _materials.has(item):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = sim.data.item_color(item)
		_materials[item] = mat
	return _materials[item]
