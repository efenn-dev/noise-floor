class_name NavBaker
extends Node3D
## Bakes the navmesh zombies walk on from the solid things under `root` (ground, town, built pieces).
## Building or wrecking something calls request_rebake(); the bake runs on a worker thread about a
## second later, and the new mesh swaps in when it's done.
## W3a (the bigger world): the bounds are cut into TILE-metre tiles, each its own NavigationRegion3D (tiles on
## one navigation map join up at their shared edges, border_size keeps those edges from being eaten by the
## agent radius). A change re-bakes only the tiles round it, one tile at a time on a worker thread. When the
## built pieces have their own root (`build_root`, BuildView), the fixed scenery (WORLD colliders) is read once
## and only the pieces (BUILT) are read again per re-bake.

const REBAKE_DELAY := 1.0
const TILE := 64.0  # metres; a multiple of the 0.25 m cell size
const NEAR_TILES := 1  # bake_near() also bakes this many tiles round the one it's given

var region: NavigationRegion3D  # the first tile's region (older tests read it)
var root: Node
var build_root: Node
var bounds: AABB
var bakes := 0  # finished tile bakes, for tests

var _template := NavigationMesh.new()
var _tiles: Dictionary = {}  # Vector2i -> NavigationRegion3D
var _dirty: Dictionary = {}  # Vector2i -> true, waiting for the delay
var _queue: Array[Vector2i] = []  # waiting to bake, one at a time
var _wait := 0.0
var _baking := false
var _static: NavigationMeshSourceGeometryData3D  # the fixed scenery, read once (only with a build_root)
var _round: NavigationMeshSourceGeometryData3D  # the geometry the queued tiles bake from


func setup(p_root: Node, p_bounds: AABB, p_build_root: Node = null) -> void:
	root = p_root
	build_root = p_build_root
	bounds = p_bounds
	_template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_template.geometry_collision_mask = Layers.WORLD | Layers.BUILT
	_template.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	# Multiples of the 0.25 m cell size/height, or the baker rounds them and warns.
	_template.agent_radius = 0.5
	_template.agent_height = 1.75
	_template.agent_max_climb = 0.25
	_template.border_size = 1.0  # more than the agent radius: a wall on a tile edge is seen whole by both tiles
	for t: Vector2i in tiles():
		var r := NavigationRegion3D.new()
		r.name = "Nav_%d_%d" % [t.x, t.y]
		add_child(r)
		_tiles[t] = r
		if region == null:
			region = r


## Every tile that covers the bounds.
func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i(floori(bounds.position.x / TILE), floori(bounds.position.z / TILE))
	var hi := Vector2i(ceili(bounds.end.x / TILE) - 1, ceili(bounds.end.z / TILE) - 1)
	for tz in range(lo.y, hi.y + 1):
		for tx in range(lo.x, hi.x + 1):
			out.append(Vector2i(tx, tz))
	return out


## The tile under `at`.
static func tile_of(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / TILE), floori(at.z / TILE))


## The part of the bounds tile `t` bakes.
func tile_aabb(t: Vector2i) -> AABB:
	var box := AABB(Vector3(t.x * TILE, bounds.position.y, t.y * TILE), Vector3(TILE, bounds.size.y, TILE))
	return box.intersection(bounds)


## Bakes every tile right now, on this thread. Use in tests.
func bake_now() -> void:
	var source := _source(true)
	for t: Vector2i in _tiles:
		_bake_tile_now(t, source)


## Bakes the tiles round `at` right now (startup: where you are), and queues the rest for the background.
func bake_near(at: Vector3) -> void:
	var source := _source(true)
	var centre := tile_of(at)
	for t: Vector2i in _tiles:
		if absi(t.x - centre.x) <= NEAR_TILES and absi(t.y - centre.y) <= NEAR_TILES:
			_bake_tile_now(t, source)
		elif not _queue.has(t):
			_queue.append(t)
	_round = source


## Something changed at `at` (Vector3.INF: anywhere). The tiles round it bake again after a moment.
func request_rebake(at: Vector3 = Vector3.INF) -> void:
	if not at.is_finite():
		for t: Vector2i in _tiles:
			_dirty[t] = true
	else:
		var near := AABB(at - Vector3(2, 0, 2), Vector3(4, 1, 4))  # a piece by a tile edge touches both
		for t: Vector2i in _tiles:
			var box := AABB(Vector3(t.x * TILE, 0, t.y * TILE), Vector3(TILE, 1, TILE))
			if box.intersects(near):
				_dirty[t] = true
	_wait = REBAKE_DELAY


## Waits until the navigation map has taken in the latest meshes (it syncs on a worker thread, so a path asked
## for straight after a bake can come back empty). For tests and startup checks.
func wait_synced(timeout_ms: int = 8000) -> void:
	var map := get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_iteration_id(map)
	var last := start
	var steady := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:  # real time: headless frames run faster than the map's worker
		await get_tree().physics_frame
		var now := NavigationServer3D.map_get_iteration_id(map)
		steady = steady + 1 if now == last else 0
		last = now
		if now > start and steady >= 20:  # it has taken in the change and gone quiet
			return


## Stops baking anything more (the bake already on a worker thread finishes on its own).
func stop() -> void:
	_queue.clear()
	_dirty.clear()


func _exit_tree() -> void:
	stop()


## Busy baking or waiting to (tests wait for this to be false).
func busy() -> bool:
	return _baking or not _queue.is_empty() or not _dirty.is_empty()


func _process(delta: float) -> void:
	if not _dirty.is_empty():
		_wait -= delta
		if _wait <= 0.0:
			for t: Vector2i in _dirty:
				if not _queue.has(t):
					_queue.push_front(t)  # changes first, ahead of any startup backlog
			_dirty.clear()
			_round = _source(false)
	if _baking or _queue.is_empty():
		return
	var t: Vector2i = _queue.pop_front()
	if _round == null:
		_round = _source(false)
	_baking = true
	var mesh := _tile_mesh(t)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, _round, _finish.bind(t, mesh))


func _tile_mesh(t: Vector2i) -> NavigationMesh:
	var mesh: NavigationMesh = _template.duplicate()
	# The baker leaves border_size unwalkable inside its box, so the box reaches that far past the tile: the
	# trimmed mesh then ends exactly on the tile's edge and meets the next tile's (no agent-radius gap there).
	var b := _template.border_size
	var box := tile_aabb(t)
	mesh.filter_baking_aabb = AABB(box.position - Vector3(b, 0, b), box.size + Vector3(2.0 * b, 0, 2.0 * b))
	return mesh


func _bake_tile_now(t: Vector2i, source: NavigationMeshSourceGeometryData3D) -> void:
	var mesh := _tile_mesh(t)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_tiles[t].navigation_mesh = mesh
	bakes += 1
	_queue.erase(t)


## The geometry to bake from (main thread). With a build_root: the fixed scenery read once (again if
## `fresh`) plus the built pieces read now; without one, everything under root read now.
func _source(fresh: bool) -> NavigationMeshSourceGeometryData3D:
	var out := NavigationMeshSourceGeometryData3D.new()
	if build_root == null:
		NavigationServer3D.parse_source_geometry_data(_template, out, root)  # must run on the main thread
		return out
	if fresh or _static == null:
		var fixed: NavigationMesh = _template.duplicate()
		fixed.geometry_collision_mask = Layers.WORLD
		_static = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(fixed, _static, root)
	var built: NavigationMesh = _template.duplicate()
	built.geometry_collision_mask = Layers.BUILT
	var pieces := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(built, pieces, build_root)
	out.merge(_static)
	out.merge(pieces)
	return out


func _finish(t: Vector2i, mesh: NavigationMesh) -> void:
	if _tiles.has(t):
		_tiles[t].navigation_mesh = mesh
	_baking = false
	bakes += 1
