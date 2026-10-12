class_name FactoryView
extends Node3D
## Draws what the factory is doing: items riding belts (smoothed between sim ticks) and a lamp on
## each machine that glows green while it works and amber when it's stuck.

const ITEM_SIZE := 0.3

var sim: SimWorld
var build_view: BuildView
var _pool: Array[MeshInstance3D] = []
var _materials: Dictionary = {}  # item -> material
var _item_mesh := BoxMesh.new()


func setup(p_sim: SimWorld, p_build_view: BuildView) -> void:
	sim = p_sim
	build_view = p_build_view
	_item_mesh.size = Vector3.ONE * ITEM_SIZE


func _process(_delta: float) -> void:
	_draw_items()
	_draw_lamps()


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


func _draw_lamps() -> void:
	for cell: Vector2i in sim.factory.machines:
		var body := build_view.body_for("o:%d:%d" % [cell.x, cell.y])
		if body == null:
			continue
		var lamp := body.get_node_or_null("Lamp") as MeshInstance3D
		if lamp == null:
			continue
		var m: Factory.Machine = sim.factory.machines[cell]
		var mat := lamp.material_override as StandardMaterial3D
		var color := Color(0.2, 1.0, 0.3) if m.crafting else (Color(1.0, 0.6, 0.1) if m.status() == "output full" else Color(0.25, 0.25, 0.25))
		mat.albedo_color = color
		mat.emission_enabled = m.crafting or m.status() == "output full"
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
