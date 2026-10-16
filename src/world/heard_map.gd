class_name HeardMap
extends Control
## F5: while you place something that makes noise, a small top-down picture on the right of how far zombies will
## hear it there: the night ring (blue) and the day ring (orange) to scale round the ghost (yellow dot), north up,
## so the walls round it show as dents. The build line says the distances; this shows the shape. It reads
## BuildController.heard (SimWorld.heard_preview), so it's the same rule the zombies use.

const SIZE := 220.0
const MARGIN := 16.0

var builder: BuildController
var _shown: Dictionary = {}


func setup(p_builder: BuildController) -> void:
	builder = p_builder
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SIZE, SIZE + 26.0)
	visible = false


func _process(_delta: float) -> void:
	visible = builder != null and builder.active and not builder.heard.is_empty()
	if not visible:
		return
	var vp := get_viewport_rect().size
	position = Vector2(vp.x - SIZE - MARGIN, vp.y * 0.42)
	if not is_same(builder.heard, _shown):
		_shown = builder.heard
		queue_redraw()


## The ring's corners on screen: direction i of RADII round the centre, world +X to the right and +Z (south) down.
static func ring_points(radii: PackedFloat32Array, center: Vector2, scale: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in radii.size():
		var a := TAU * i / radii.size()
		pts.append(center + Vector2(cos(a), sin(a)) * maxf(radii[i], 0.0) * scale)
	if not pts.is_empty():
		pts.append(pts[0])
	return pts


func _draw() -> void:
	if _shown.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(1, 1, 1, 0.35), false, 1.0)
	var night: PackedFloat32Array = _shown["night"]
	var day: PackedFloat32Array = _shown["day"]
	var far := maxf(SimWorld.heard_far(night), 1.0)
	var scale := SIZE * 0.45 / far
	var center := Vector2(SIZE, SIZE) / 2.0
	draw_polyline(ring_points(night, center, scale), BuildController.NIGHT_RING, 2.0, true)
	draw_polyline(ring_points(day, center, scale), BuildController.DAY_RING, 2.0, true)
	draw_circle(center, 4.0, Color(1.0, 0.9, 0.3))
	var font := get_theme_default_font()
	var across := far >= NoiseField.HEARD_MAX - 1.0
	draw_string(font, Vector2(6, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	draw_string(font, Vector2(0, SIZE + 18), "Night: %s" % ("across the map" if across else "%d m" % roundi(far)),
			HORIZONTAL_ALIGNMENT_LEFT, SIZE, 16, Color(1, 1, 1, 0.9))
