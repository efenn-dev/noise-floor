class_name RuralView
extends Node3D
## W3d: what the farms and the hunting cabin (RuralPlan) have that neither TownView nor a CountryView draws: each
## barn's pitched roof (a barn-red gable on the wall pieces, dark roof slopes over it, a ceiling the walker bumps
## its head on) and the fixtures (barn crates, the tractor, the hay inside, the cabin's gun locker: DowntownView's
## props, "container_id" on the searchable ones). The farmhouses' and cabin's roofs are a TownView's; the corn,
## fences and yard hay a second CountryView's; the walls, doors, windows and floors are BuildGrid pieces. No rules.

const WALL_TOP := 2.8
const RISE := 2.6          # the barn roof's ridge above the wall tops
const OVERHANG := 0.4
const SLOPE_THICK := 0.16

var sim: SimWorld
var plan: Dictionary
var roof_meshes: Array = []  # the roof slopes, retinted by apply_season (snow in winter)
var fixtures: Dictionary = {}  # fixture id -> StaticBody3D (tests)
var barns := 0


func setup(p_sim: SimWorld, p_plan: Dictionary) -> void:
	sim = p_sim
	plan = p_plan
	var roof_mat := Surfaces.material("scrap_wall", 2.0, Color(0.36, 0.36, 0.38))
	var red := BuildView.town_material("barn")
	for barn: Dictionary in plan["barns"]:
		_barn(barn, roof_mat, red)
	for f: Dictionary in plan["fixtures"]:
		var body := DowntownView.make_prop(f)
		add_child(body)
		fixtures[f["id"]] = body


## Is `pos` under a barn's roof (main.gd thins the fog there)?
func is_under_roof(pos: Vector3) -> bool:
	if pos.y >= WALL_TOP + RISE:
		return false
	for barn: Dictionary in plan.get("barns", []):
		if (barn["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)):
			return true
	return false


func apply_season(season: String) -> void:
	var mat := SeasonLook.roof_material(season)
	for m: MeshInstance3D in roof_meshes:
		m.material_override = mat


## The gable (a prism along the barn's length, ridge down the middle, ends barn red), two roof slopes on it, a
## pale ceiling at the wall tops and its head-bump slab.
func _barn(barn: Dictionary, roof_mat: Material, red: Material) -> void:
	var r: Rect2 = barn["rect"]
	var mid := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var gable := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(r.size.x, RISE, r.size.y)
	gable.mesh = prism
	gable.material_override = red
	gable.position = mid + Vector3(0, WALL_TOP + RISE / 2.0, 0)
	add_child(gable)
	var half := r.size.x / 2.0 + OVERHANG
	var angle := atan2(RISE, r.size.x / 2.0)
	var slope_len := half / cos(angle)
	for sx: float in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(slope_len, SLOPE_THICK, r.size.y + 2.0 * OVERHANG)
		slab.mesh = box
		slab.material_override = roof_mat
		# Half-way down the slope from the ridge, lifted by half its thickness so it sits on the gable.
		var along := Vector2(sx * cos(angle), -sin(angle)) * (slope_len / 2.0)
		slab.position = mid + Vector3(along.x, WALL_TOP + RISE + along.y + SLOPE_THICK / 2.0 / cos(angle), 0)
		slab.rotation.z = -sx * angle
		add_child(slab)
		roof_meshes.append(slab)
	var ceiling := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(r.size.x, 0.04, r.size.y)
	ceiling.mesh = cbox
	ceiling.material_override = Surfaces.material("concrete_floor", 3.0, Color(0.55, 0.45, 0.36))
	ceiling.position = mid + Vector3(0, WALL_TOP - 0.02, 0)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ceiling)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.CEILING
	body.collision_mask = 0
	body.position = mid + Vector3(0, WALL_TOP + 0.1, 0)
	var shape := CollisionShape3D.new()
	var slab_shape := BoxShape3D.new()
	slab_shape.size = Vector3(r.size.x, 0.2, r.size.y)
	shape.shape = slab_shape
	body.add_child(shape)
	add_child(body)
	barns += 1
