class_name PortView
extends Node3D
## P4 (Emmitt: "the conveyor belts were hard to tell if they snapped into a machine like in Satisfactory"): shows how
## the factory connects. Every machine gets an arrow on the ground at its back, pointing in and marked IN (blue), and
## one at its front, pointing out and marked OUT (orange). Every belt end that meets something gets a green tick if
## it connects (a machine's IN, a crate, a turret, a splitter's taking side, the Hub) and a red X if it doesn't (a
## machine's side, a belt running back at it); a machine whose OUT runs into a belt pointing back gets a red X too.
## The rules are SimWorld.belt_target / Factory.belt_link; this only draws them, rebuilt when the build grid changes.
## P4 (Emmitt: "can we make the graphics a bit better where the belt actually connects to the machines so items don't
## look like they float"): a machine model is narrower than its 2 m cell (a Press is 1.35 m deep), so a belt used to
## stop short of it. A connected port now gets a chute from the belt's end to the machine's face and a dark opening
## on the face; a machine feeding straight into the next gets a bridge between them. Free ports keep their arrow.
## FactoryView carries belt items across the chute and into the opening (port_depths).

const TICK_COLOR := Color(0.35, 0.95, 0.4)
const CROSS_COLOR := Color(1.0, 0.25, 0.2)
const SHOW_WITHIN := 45.0  # markers fade out past this, so a big base isn't a forest of labels
const DECK_TOP := 0.065     # a belt model's rubber deck, above the belt's centre (tools/art/belt.py)
const CHUTE_WIDTH := 0.8
const RAIL := Color(0.15, 0.15, 0.16)
const RUBBER := Color(0.06, 0.06, 0.07)
const MOUTH := Color(0.02, 0.02, 0.02)
static var _depths: Dictionary = {}  # machine id -> Vector2(front, back): its model's faces from its centre

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
		var depth := port_depths(m.id)
		var deck := _deck_y(Factory.input_cell(m), floor_y)
		var at_in := Factory.input_cell(m)
		if sim.factory.belts.has(at_in) and sim.factory.belt_link(at_in)["kind"] == "machine":
			add_child(chute(center - flow * (g / 2.0), center - flow * depth.y, deck, "IN"))  # the belt plugs in
		elif not (sim.factory.machines.has(at_in) and Factory.output_cell(sim.factory.machines[at_in]) == cell):
			add_child(arrow(center - flow * (g / 2.0 + 0.15), flow, BuildView.INPUT_COLOR, "IN"))
		var out := Factory.output_cell(m)
		if sim.factory.belts.has(out) and out + Factory.DIRS[sim.factory.belts[out].facing] != cell:
			add_child(chute(center + flow * depth.x, center + flow * (g / 2.0), _deck_y(out, floor_y), "OUT"))
		elif sim.factory.machines.has(out) and Factory.input_cell(sim.factory.machines[out]) == cell:
			var next_depth := port_depths(sim.factory.machines[out].id)  # straight into the next machine: a bridge
			add_child(chute(center + flow * depth.x, center + flow * (g - next_depth.y), floor_y + 0.45, "BRIDGE"))
		else:
			add_child(arrow(center + flow * (g / 2.0 + 0.15), flow, BuildView.OUTPUT_COLOR, "OUT"))
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


## P4: how far a machine model's front (OUT) and back (IN) faces are from its centre: Vector2(front, back), measured
## once from the model's meshes (a placeholder box: 0.85 m).
static func port_depths(id: String) -> Vector2:
	if _depths.has(id):
		return _depths[id]
	var out := Vector2(0.85, 0.85)  # a placeholder box is about 1.7 m deep
	if BuildView.MODELS.has(id) and ResourceLoader.exists(BuildView.MODELS[id]):
		var root: Node3D = (load(BuildView.MODELS[id]) as PackedScene).instantiate()
		var box := AABB()
		var first := true
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = mesh.transform * mesh.get_aabb()
			var parent: Node = mesh.get_parent()
			while parent is Node3D and parent != root:
				a = (parent as Node3D).transform * a
				parent = parent.get_parent()
			box = a if first else box.merge(a)
			first = false
		root.free()
		if not first:
			out = Vector2(-box.position.z, box.end.z)
	_depths[id] = out
	return out


## The belt deck's height on `cell` (a belt there, or the machine's floor if none).
func _deck_y(cell: Vector2i, floor_y: float) -> float:
	var key := "o:%d:%d" % [cell.x, cell.y]
	if sim.build.pieces.has(key) and sim.factory.belts.has(cell):
		return sim.build.piece_center(key).y + DECK_TOP
	return floor_y + 0.15


## P4: a short run of belt deck from `from` to `to` (world points at ground height; it sits with its top at `deck`),
## with side rails, and a dark opening where it meets a machine's face: the belt plugged into the port.
static func chute(from: Vector3, to: Vector3, deck: float, label: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Chute_" + label
	var span := Vector3(to.x - from.x, 0, to.z - from.z)
	var length := maxf(span.length(), 0.05)
	root.position = Vector3((from.x + to.x) / 2.0, deck, (from.z + to.z) / 2.0)
	root.rotation.y = atan2(-span.x, -span.z) if span.length() > 0.001 else 0.0
	_part(root, Vector3(CHUTE_WIDTH - 0.02, 0.04, length + 0.04), Vector3(0, -0.02, 0), RUBBER)  # the deck
	for x: float in [-CHUTE_WIDTH / 2.0, CHUTE_WIDTH / 2.0]:
		_part(root, Vector3(0.07, 0.1, length + 0.04), Vector3(x, 0.01, 0), RAIL)  # rails
	if label == "IN":  # a port frame on the machine's back face (the far end, -Z), the machine seen through it
		_frame(root, -length / 2.0)
	elif label == "OUT":  # on its front face (the near end, +Z)
		_frame(root, length / 2.0)
	return root


## P4: a port frame (two posts and a lintel) standing across the chute at `z`.
static func _frame(root: Node3D, z: float) -> void:
	for x: float in [-CHUTE_WIDTH / 2.0, CHUTE_WIDTH / 2.0]:
		_part(root, Vector3(0.08, 0.46, 0.08), Vector3(x, 0.23, z), MOUTH)
	_part(root, Vector3(CHUTE_WIDTH + 0.08, 0.08, 0.08), Vector3(0, 0.46, z), MOUTH)


static func _part(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh


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
