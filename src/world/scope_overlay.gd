class_name ScopeOverlay
extends Control
## V39 (Emmitt: "I found a scope but it doesn't zoom in much and has no reticle"): the view through a fitted scope.
## The gun model hides at full aim (Shooter), so this draws what the eye sees in the eyepiece: black round a round
## lens, a soft dark rim, and a duplex reticle (thick posts outside, fine lines and a red dot in the middle, three
## holdover ticks below for longer shots). HUD only: it never catches the mouse.

const LENS := 0.44  # the lens radius as a fraction of the smaller screen side
const POST := 7.0  # thick outer post width, pixels
const LINE := 1.6  # fine centre line width
const FINE := 0.36  # the fine lines reach this fraction of the lens radius from the centre
const TICKS := [0.09, 0.17, 0.25]  # holdover ticks below the centre, as fractions of the lens radius


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Fades the view in with the aim (`weight` 0-1); hidden below about 80 percent.
func show_scope(weight: float) -> void:
	visible = weight > 0.8
	modulate.a = clampf((weight - 0.8) / 0.2, 0.0, 1.0)
	if visible:
		queue_redraw()


## The lens circle for a screen of `size`: [centre, radius].
static func lens(size: Vector2) -> Array:
	return [size * 0.5, minf(size.x, size.y) * LENS]


func _draw() -> void:
	var size := get_viewport_rect().size
	var l := lens(size)
	var c: Vector2 = l[0]
	var r: float = l[1]
	var far := size.length()
	# Everything outside the lens is the scope's black tube; a soft band inside the edge darkens the rim.
	draw_arc(c, r + far * 0.5, 0.0, TAU, 160, Color.BLACK, far, true)
	draw_arc(c, r - 9.0, 0.0, TAU, 160, Color(0, 0, 0, 0.55), 18.0, true)
	draw_arc(c, r - 26.0, 0.0, TAU, 160, Color(0, 0, 0, 0.18), 16.0, true)
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	var fine := r * FINE
	# Thick posts from the rim in to where the fine lines start.
	draw_rect(Rect2(c.x - r, c.y - POST * 0.5, r - fine, POST), ink)
	draw_rect(Rect2(c.x + fine, c.y - POST * 0.5, r - fine, POST), ink)
	draw_rect(Rect2(c.x - POST * 0.5, c.y + fine, POST, r - fine), ink)
	draw_rect(Rect2(c.x - POST * 0.5, c.y - r, POST, r - fine), ink)
	# Fine cross through the middle.
	draw_line(Vector2(c.x - fine, c.y), Vector2(c.x + fine, c.y), ink, LINE, true)
	draw_line(Vector2(c.x, c.y - fine), Vector2(c.x, c.y + fine), ink, LINE, true)
	for t: float in TICKS:
		var y := c.y + r * t
		var half := r * 0.03
		draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), ink, LINE, true)
	draw_circle(c, 2.6, Color(0.85, 0.08, 0.05, 0.95))
