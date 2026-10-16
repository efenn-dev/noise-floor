class_name PortView
extends Node3D
## P4 (Emmitt: "the conveyor belts were hard to tell if they snapped into a machine like in Satisfactory"): shows how
## the factory connects. Every machine gets an arrow on the ground at its back, pointing in and marked IN (blue), and
## one at its front, pointing out and marked OUT (orange). Every belt end that meets something gets a green tick if
## it connects (a machine's IN, a crate, a turret, a splitter's taking side, the Hub) and a red X if it doesn't (a
## machine's side, a belt running back at it); a machine whose OUT runs into a belt pointing back gets a red X too.
## The rules are SimWorld.belt_target / Factory.belt_link; this only draws them, rebuilt when the build grid changes.

const TICK_COLOR := Color(0.35, 0.95, 0.4)
const CROSS_COLOR := Color(1.0, 0.25, 0.2)
const SHOW_WITHIN := 45.0  # markers fade out past this, so a big base isn't a forest of labels

var sim: SimWorld
var _dirty := true


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	sim.build.piece_added.connect(func(_k: String) -> void: _dirty = true)
	sim.build.piece_removed.connect(func(_k: String, _p: Dictionary) -> void: _dirty = true)
	sim.build.piece_changed.connect(func(_k: String) -> void: _dirty = true)


func _process(_delta: float) -> void:
	if _dirty and sim != null:
		_dirty = false
		rebuild()


## Every marker again (tests call it straight away).
func rebuild() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var g := BuildGrid.GRID
	for cell: Vector2i in sim.factory.machines:
		var m: Factory.Machine = sim.factory.machines[cell]
		var key := "o:%d:%d" % [cell.x, cell.y]
		if not sim.build.pieces.has(key):
			continue
		var floor_y := sim.build.piece_center(key).y - float(sim.data.buildables[m.id]["size"].y) / 2.0 + 0.04
		var center := Vector3((cell.x + 0.5) * g, floor_y, (cell.y + 0.5) * g)
		var flow := Vector3(Factory.DIRS[m.facing].x, 0, Factory.DIRS[m.facing].y)
		add_child(arrow(center - flow * (g / 2.0 + 0.15), flow, BuildView.INPUT_COLOR, "IN"))
		add_child(arrow(center + flow * (g / 2.0 + 0.15), flow, BuildView.OUTPUT_COLOR, "OUT"))
		var out := Factory.output_cell(m)
		if sim.factory.belts.has(out) and out + Factory.DIRS[sim.factory.belts[out].facing] == cell:
			add_child(mark(center + flow * (g / 2.0) + Vector3(0, 0.9, 0), false))  # its output runs into a belt pointing back
	for cell: Vector2i in sim.factory.belts:
		var link := sim.belt_target(cell)
		if link["kind"] == "belt" or link["kind"] == "open":
			continue
		var b: Factory.Belt = sim.factory.belts[cell]
		var key := "o:%d:%d" % [cell.x, cell.y]
		var y := sim.build.piece_center(key).y if sim.build.pieces.has(key) else 0.1
		var front := Vector3((cell.x + 0.5) * g, y, (cell.y + 0.5) * g) + Vector3(Factory.DIRS[b.facing].x, 0, Factory.DIRS[b.facing].y) * (g / 2.0)
		add_child(mark(front + Vector3(0, 0.7, 0), bool(link["ok"])))


## A flat arrow on the ground at `at` pointing along `flow`, in `color`, with `text` floating above it.
static func arrow(at: Vector3, flow: Vector3, color: Color, text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Port_" + text
	root.position = at
	root.rotation.y = atan2(-flow.x, -flow.z)
	var tri := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 0.55, 0.04)
	tri.mesh = prism
	tri.rotation_degrees.x = -90.0  # lie flat, the point toward -Z (the way things flow)
	tri.material_override = _flat(color)
	tri.visibility_range_end = SHOW_WITHIN
	root.add_child(tri)
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = color.lightened(0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.45, 0)
	label.visibility_range_end = SHOW_WITHIN
	root.add_child(label)
	return root


## A green tick (connects) or a red X (doesn't) floating at `at`.
static func mark(at: Vector3, ok: bool) -> Label3D:
	var label := Label3D.new()
	label.name = "Tick" if ok else "Cross"
	label.text = "✓" if ok else "X"
	label.font_size = 96
	label.pixel_size = 0.005
	label.outline_size = 14
	label.modulate = TICK_COLOR if ok else CROSS_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.visibility_range_end = SHOW_WITHIN
	return label


static func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
