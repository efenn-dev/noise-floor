class_name TownView
extends Node3D
## What the town plan has that isn't a build piece (W1a): a flat roof over each house with a pale
## ceiling under it (so rooms are dark and the flashlight matters), and a strip of wall above each
## door, up to the roof. No colliders for sound or rules (sound is 2-D in this game, so a roof has no rule; V24: only a
## ceiling slab the walker bumps its head on), and nothing
## can climb up there. The walls, doors, windows and floors are BuildGrid pieces drawn by BuildView.

const WALL_TOP := 2.8   # foundation top (0.1) + town_wall height (2.7)
const ROOF := 0.25
const OVERHANG := 0.35
const FACTORY_TOP := 6.0  # W1b: the factory hall's roof; brick runs up from the wall pieces to here

var roofs := 0  # roof slabs drawn, for tests
var factory_cells := 0  # W1b: cells under the factory roof, for tests
var ceiling_bodies := 0  # V24: ceiling colliders made, for tests
var roof_meshes: Array = []  # M16: every roof slab, retinted by apply_season
var _roofed := {}  # Q2: Vector2i cell -> true for every house cell under a roof
var _has_factory := false


## Q2: is `pos` (the camera, say) under a roof: in a house's cells below its ceiling, or in the factory
## hall below its ceiling? main.gd thins the fog there.
func is_under_roof(pos: Vector3) -> bool:
	if _has_factory and pos.y < FACTORY_TOP and TownPlan.factory_rect().has_point(Vector2(pos.x, pos.z)):
		return true
	return pos.y < WALL_TOP and _roofed.has(BuildGrid.world_to_cell(pos))


func setup(plan: Dictionary, grid: BuildGrid) -> void:
	var g := BuildGrid.GRID
	var roof_mat := Surfaces.material("asphalt", 3.0, Color(0.42, 0.36, 0.34))
	var ceiling_mat := Surfaces.material("concrete_floor", 3.0, Color(0.8, 0.79, 0.75))
	for house: Dictionary in plan["houses"]:
		# One slab per row of cells running along the road (every plan is solid along each row).
		var rows := {}
		var min_x := 1 << 30
		var max_x := -(1 << 30)
		for c: Vector2i in house["cells"]:
			_roofed[c] = true
			var r: Array = rows.get(c.x, [c.y, c.y])
			rows[c.x] = [mini(r[0], c.y), maxi(r[1], c.y)]
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
		for x: int in rows:
			var z0: float = rows[x][0] * g - OVERHANG
			var z1: float = (rows[x][1] + 1) * g + OVERHANG
			var x0 := x * g - (OVERHANG if x == min_x else 0.0)
			var x1 := (x + 1) * g + (OVERHANG if x == max_x else 0.0)
			var mid := Vector3((x0 + x1) / 2.0, 0.0, (z0 + z1) / 2.0)
			roof_meshes.append(_box(Vector3(x1 - x0, ROOF, z1 - z0), mid + Vector3(0, WALL_TOP + ROOF / 2.0, 0), roof_mat))
			_ceiling_body(Vector3(x1 - x0, ROOF + 0.04, z1 - z0), mid + Vector3(0, WALL_TOP + ROOF / 2.0 - 0.02, 0))
			_box(Vector3(g, 0.04, (rows[x][1] - rows[x][0] + 1) * g), Vector3((x + 0.5) * g, WALL_TOP - 0.02, mid.z),
					ceiling_mat, false)
			roofs += 1
	if plan.has("factory"):
		_has_factory = true
		_factory(plan["factory"], roof_mat, ceiling_mat)
	var door_top: float = grid.foundation_top() + grid.data.buildables["door"]["size"].y
	var wall_mat := {}
	for p: Dictionary in plan["pieces"]:
		if p["id"] != "door":
			continue
		var style: String = p["style"]  # the house's brick or siding
		if not wall_mat.has(style):
			wall_mat[style] = BuildView.town_material(style)
		var center := grid.center_for("town_wall", p["cell"], p["side"])
		var lintel := _box(Vector3(g, WALL_TOP - door_top, 0.2), Vector3(center.x, (WALL_TOP + door_top) / 2.0, center.z),
				wall_mat[style])
		lintel.rotation_degrees.y = grid.yaw_for("town_wall", p["cell"], p["side"])


## M16: the roofs in this season's tint (snow-white in winter).
func apply_season(season: String) -> void:
	var mat := SeasonLook.roof_material(season)
	for m: MeshInstance3D in roof_meshes:
		m.material_override = mat


## W1b: the factory hall's roof and ceiling at FACTORY_TOP, and the brick band from the top of its wall
## pieces up to the roof all round (over the doorway too, as a lintel). No colliders, like the houses' roofs.
func _factory(f: Dictionary, roof_mat: Material, ceiling_mat: Material) -> void:
	var r := TownPlan.factory_rect()
	var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
	roof_meshes.append(_box(Vector3(r.size.x + 2 * OVERHANG, ROOF, r.size.y + 2 * OVERHANG), mid + Vector3(0, FACTORY_TOP + ROOF / 2.0, 0), roof_mat))
	_box(Vector3(r.size.x, 0.04, r.size.y), mid + Vector3(0, FACTORY_TOP - 0.02, 0), ceiling_mat, false)
	_ceiling_body(Vector3(r.size.x, ROOF + 0.04, r.size.y), mid + Vector3(0, FACTORY_TOP + ROOF / 2.0 - 0.02, 0))
	roofs += 1
	var brick := BuildView.town_material("factory")
	var h := FACTORY_TOP - WALL_TOP
	var y := WALL_TOP + h / 2.0
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.position.y), brick)  # north
	_box(Vector3(r.size.x + 0.2, h, 0.2), Vector3(mid.x, y, r.end.y), brick)       # south, over the doorway
	_box(Vector3(0.2, h, r.size.y), Vector3(r.position.x, y, mid.z), brick)       # west
	_box(Vector3(0.2, h, r.size.y), Vector3(r.end.x, y, mid.z), brick)            # east
	factory_cells = f["cells"].size()


## V24 (Emmitt: "if you jump in a house you can see through the roof"): the roofs had no colliders, so a jump
## (or a jump off the furniture) put your head and the camera up through the ceiling. A slab on its own layer
## that only the walker bumps into: sound, the navmesh and every ray still ignore roofs, as before.
func _ceiling_body(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.CEILING
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	ceiling_bodies += 1


func _box(size: Vector3, pos: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	if not shadows:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m
