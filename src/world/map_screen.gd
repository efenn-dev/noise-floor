class_name MapScreen
extends CanvasLayer
## W3e: M. The bigger world at a glance, north up: the named areas (data/areas.json, coloured by kind), every road
## (asphalt, dirt and the highway), the resource nodes (F1) by kind, your base (the middle of what you've built),
## the Hub and the radio mast if you've built them, and you: an arrow pointing the way you face. M, E, Tab or Esc
## closes it. It only draws what the sim and WorldMap know; nothing here is a rule.

const AREA_COLORS := {
	"town": Color(0.42, 0.38, 0.34), "industry": Color(0.38, 0.39, 0.42), "farm": Color(0.5, 0.5, 0.26),
	"road": Color(0.26, 0.26, 0.28), "woods": Color(0.17, 0.29, 0.18), "cabin": Color(0.44, 0.31, 0.2),
}
const ROAD_COLORS := {"asphalt": Color(0.66, 0.66, 0.63), "dirt": Color(0.58, 0.44, 0.28), "highway": Color(0.78, 0.78, 0.74)}
const NODE_COLORS := {"scrap_heap": Color(0.75, 0.75, 0.78), "well": Color(0.35, 0.65, 1.0), "fuel_tank": Color(1.0, 0.6, 0.15),
		"timber": Color(0.45, 0.85, 0.35)}
const GROUND := Color(0.24, 0.27, 0.2)
const GOLD := Color(0.95, 0.8, 0.55)
const PLAYER := Color(1.0, 0.9, 0.2)

var sim: SimWorld
var _root: Control
var _canvas: MapDraw
var base_at := Vector3.INF  # the middle of what you've built (tests); INF with nothing built


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.04, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_canvas = MapDraw.new()
	_canvas.screen = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_canvas)
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	base_at = _base_middle()
	_canvas.queue_redraw()


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("map") or event.is_action_pressed("interact")
			or event.is_action_pressed("free_mouse") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		_canvas.queue_redraw()  # you can still be moving (a car rolling on)


## Where on the screen's map rectangle `rect` the world spot `at` (x, z) is.
static func to_map(rect: Rect2, at: Vector2) -> Vector2:
	var e := WorldMap.EXTENT
	return rect.position + Vector2((at.x - e.position.x) / e.size.x * rect.size.x, (at.y - e.position.y) / e.size.y * rect.size.y)


## The map's rectangle on a screen `size` big: as large as fits with room for the title and legend, the map's
## own proportions (720 x 760 m).
static func map_rect(size: Vector2) -> Rect2:
	var e := WorldMap.EXTENT
	var room := size - Vector2(80, 150)
	var k := minf(room.x / e.size.x, room.y / e.size.y)
	var s := e.size * k
	return Rect2(Vector2((size.x - s.x) / 2.0, 70.0 + (room.y - s.y) / 2.0), s)


## The way you face, flat (x, z): the camera's forward.
func facing() -> Vector2:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return Vector2(0, -1)
	var f := -cam.global_basis.z
	var flat := Vector2(f.x, f.z)
	return flat.normalized() if flat.length() > 0.01 else Vector2(0, -1)


func _base_middle() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for key: String in sim.build.pieces:
		if sim.build.player_placeable(sim.build.pieces[key]["id"]) and not sim.build.pieces[key].get("town", false):
			sum += sim.build.piece_center(key)
			n += 1
	return sum / n if n > 0 else Vector3.INF


## The drawing itself, on a full-screen Control.
class MapDraw:
	extends Control
	var screen: MapScreen

	func _draw() -> void:
		var sim: SimWorld = screen.sim
		var font := ThemeDB.fallback_font
		var r := MapScreen.map_rect(size)
		draw_string(font, Vector2(r.position.x, 44), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, MapScreen.GOLD)
		draw_string(font, Vector2(r.position.x + 90, 44), "M, Tab or Esc to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
		draw_rect(r, MapScreen.GROUND)
		# Areas: the woods first (the cabin's clearing is inside them), then the rest.
		var ids: Array = WorldMap.AREAS.keys()
		ids.sort_custom(func(a: String, b: String) -> bool: return (WorldMap.AREAS[a] as Rect2).get_area() > (WorldMap.AREAS[b] as Rect2).get_area())
		for id: String in ids:
			var a: Rect2 = WorldMap.AREAS[id]
			var info: Dictionary = sim.data.areas.get(id, {})
			var p0 := MapScreen.to_map(r, a.position)
			var p1 := MapScreen.to_map(r, a.end)
			draw_rect(Rect2(p0, p1 - p0), MapScreen.AREA_COLORS.get(str(info.get("kind", "town")), Color(0.4, 0.4, 0.4)))
		for road: Dictionary in WorldMap.ROADS:
			var pts: Array = road["points"]
			var w := maxf(2.0, float(road["width"]) * r.size.x / WorldMap.EXTENT.size.x)
			for i in pts.size() - 1:
				draw_line(MapScreen.to_map(r, pts[i]), MapScreen.to_map(r, pts[i + 1]), MapScreen.ROAD_COLORS.get(road["kind"], Color.GRAY), w)
		for id: String in ids:  # names on top of the roads
			var a: Rect2 = WorldMap.AREAS[id]
			var label := str((sim.data.areas.get(id, {}) as Dictionary).get("name", id))
			var at := MapScreen.to_map(r, a.get_center())
			if id == "woods":
				at = MapScreen.to_map(r, a.position + Vector2(a.size.x * 0.5, a.size.y * 0.2))
			if id == "highway":
				at = MapScreen.to_map(r, Vector2(a.get_center().x, 230))
			if str((sim.data.areas.get(id, {}) as Dictionary).get("kind", "")) == "farm":  # off the well in the middle
				at = MapScreen.to_map(r, a.position + Vector2(a.size.x * 0.5, a.size.y * 0.2))
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, at + Vector2(-tw / 2.0 + 1, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.8))
			draw_string(font, at + Vector2(-tw / 2.0, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		for n: Dictionary in sim.resource_nodes:
			var at := MapScreen.to_map(r, Vector2(n["pos"].x, n["pos"].z))
			draw_circle(at, 4.5, Color.BLACK)
			draw_circle(at, 3.5, MapScreen.NODE_COLORS.get(n["kind"], Color.WHITE))
		if screen.base_at.is_finite():
			_house(MapScreen.to_map(r, Vector2(screen.base_at.x, screen.base_at.z)), Color(0.4, 0.9, 1.0))
		for key: String in [sim.hub_key(), sim.mast_key()]:
			if key != "":
				var c := sim.build.piece_center(key)
				var at := MapScreen.to_map(r, Vector2(c.x, c.z))
				draw_string(font, at + Vector2(-5, 6), "H" if key == sim.hub_key() else "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MapScreen.GOLD)
		var me := MapScreen.to_map(r, Vector2(sim.player_pos.x, sim.player_pos.z))
		var f := screen.facing()
		var side := Vector2(-f.y, f.x)
		var tip := me + f * 11.0
		var tri := PackedVector2Array([tip, me - f * 6.0 + side * 6.5, me - f * 3.0, me - f * 6.0 - side * 6.5])
		draw_colored_polygon(tri, MapScreen.PLAYER)
		draw_polyline(tri + PackedVector2Array([tip]), Color.BLACK, 1.5)
		# North arrow, a 100 m scale bar and the legend.
		var n_at := r.position + Vector2(r.size.x - 24, 26)
		draw_colored_polygon(PackedVector2Array([n_at + Vector2(0, -14), n_at + Vector2(7, 6), n_at + Vector2(-7, 6)]), Color.WHITE)
		draw_string(font, n_at + Vector2(-5, 24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		var px := 100.0 * r.size.x / WorldMap.EXTENT.size.x
		var bar := Vector2(r.position.x + 14, r.end.y - 16)
		draw_line(bar, bar + Vector2(px, 0), Color.WHITE, 3.0)
		draw_string(font, bar + Vector2(px + 8, 6), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var lx := r.position.x
		var ly := r.end.y + 30
		for item: Array in [["you", MapScreen.PLAYER], ["your base", Color(0.4, 0.9, 1.0)], ["scrap", MapScreen.NODE_COLORS["scrap_heap"]],
				["water", MapScreen.NODE_COLORS["well"]], ["fuel", MapScreen.NODE_COLORS["fuel_tank"]], ["timber", MapScreen.NODE_COLORS["timber"]]]:
			draw_circle(Vector2(lx + 6, ly - 5), 5.0, item[1])
			draw_string(font, Vector2(lx + 16, ly), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.85))
			lx += font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 40
		draw_string(font, Vector2(lx, ly), "H Hub   R radio mast", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MapScreen.GOLD)

	func _house(at: Vector2, color: Color) -> void:
		draw_rect(Rect2(at + Vector2(-5, -2), Vector2(10, 8)), color)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-7, -2), at + Vector2(0, -9), at + Vector2(7, -2)]), color)
