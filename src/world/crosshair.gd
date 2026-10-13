class_name Crosshair
extends Control
## P2: four short ticks round the middle of the screen while a gun is in hand. Their gap is the spread
## cone's real size on screen (Gunplay.spread_deg through the camera's field of view), so it opens up after
## a shot, closes as the recoil settles, and is tighter with a scope, Firearms levels or zoomed in. HUD only:
## it never catches the mouse (see test_main_input.gd).

const ARM := Vector2(10, 2)  # length and thickness of each tick, in pixels
const MIN_GAP := 3.0
const MAX_GAP := 220.0

var gap := MIN_GAP  # pixels from the centre to the inner end of each tick
var _arms: Array[ColorRect] = []
var _shadows: Array[ColorRect] = []  # a dark edge round each tick, so it reads against fog and sky


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		var sh := ColorRect.new()
		sh.color = Color(0, 0, 0, 0.45)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sh)
		_shadows.append(sh)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_arms.append(r)
	_place()


## The gap for a cone `spread_deg` wide (half-angle) seen through a camera with vertical `fov_deg` on a
## screen `height` pixels tall.
static func gap_for(spread_deg: float, fov_deg: float, height: float) -> float:
	var r := tan(deg_to_rad(spread_deg)) / tan(deg_to_rad(fov_deg) * 0.5) * height * 0.5
	return clampf(r, MIN_GAP, MAX_GAP)


func update_from(spread_deg: float, camera: Camera3D) -> void:
	gap = gap_for(spread_deg, camera.fov, get_viewport_rect().size.y)
	_place()


func _place() -> void:
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	for i in 4:
		var d: Vector2 = dirs[i]
		var sz := ARM if d.y == 0.0 else Vector2(ARM.y, ARM.x)
		_arms[i].size = sz
		var tip := d * (gap + ARM.x * 0.5)  # the middle of the tick
		_arms[i].position = tip - sz * 0.5
		_shadows[i].size = sz + Vector2(2, 2)
		_shadows[i].position = _arms[i].position - Vector2(1, 1)
