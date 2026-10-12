class_name NavBaker
extends Node3D
## Bakes the navmesh zombies walk on from the solid things under `root` (ground, town, built pieces).
## Building or wrecking something calls request_rebake(); the bake runs on a worker thread about a
## second later, and the new mesh swaps in when it's done.

const REBAKE_DELAY := 1.0

var region := NavigationRegion3D.new()
var root: Node
var bounds: AABB
var bakes := 0  # finished bakes, for tests

var _template := NavigationMesh.new()
var _dirty := false
var _wait := 0.0
var _baking := false


func setup(p_root: Node, p_bounds: AABB) -> void:
	root = p_root
	bounds = p_bounds
	_template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_template.geometry_collision_mask = Layers.WORLD | Layers.BUILT
	_template.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	# Multiples of the 0.25 m cell size/height, or the baker rounds them and warns.
	_template.agent_radius = 0.5
	_template.agent_height = 1.75
	_template.agent_max_climb = 0.25
	_template.filter_baking_aabb = bounds
	add_child(region)


## Bakes right now, on this thread. Use at startup and in tests.
func bake_now() -> void:
	var mesh: NavigationMesh = _template.duplicate()
	NavigationServer3D.bake_from_source_geometry_data(mesh, _parse(mesh))
	_finish(mesh)


func request_rebake() -> void:
	_dirty = true
	_wait = REBAKE_DELAY


func _process(delta: float) -> void:
	if not _dirty or _baking:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_dirty = false
	_baking = true
	var mesh: NavigationMesh = _template.duplicate()
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, _parse(mesh), _finish.bind(mesh))


func _parse(mesh: NavigationMesh) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)  # must run on the main thread
	return source


func _finish(mesh: NavigationMesh) -> void:
	region.navigation_mesh = mesh
	_baking = false
	bakes += 1
