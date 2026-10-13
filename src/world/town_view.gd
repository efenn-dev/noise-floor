class_name TownView
extends Node3D
## What the town plan has that isn't a build piece (W1a): a flat roof over each house with a pale
## ceiling under it (so rooms are dark and the flashlight matters), and a strip of wall above each
## door, up to the roof. No colliders: sound is 2-D in this game, so a roof has no rule, and nothing
## can climb up there. The walls, doors, windows and floors are BuildGrid pieces drawn by BuildView.

const WALL_TOP := 2.8   # foundation top (0.1) + town_wall height (2.7)
const ROOF := 0.25
const OVERHANG := 0.35

var roofs := 0  # roof slabs drawn, for tests


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
			_box(Vector3(x1 - x0, ROOF, z1 - z0), mid + Vector3(0, WALL_TOP + ROOF / 2.0, 0), roof_mat)
			_box(Vector3(g, 0.04, (rows[x][1] - rows[x][0] + 1) * g), Vector3((x + 0.5) * g, WALL_TOP - 0.02, mid.z),
					ceiling_mat, false)
			roofs += 1
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
