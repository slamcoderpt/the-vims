extends Control
## The green plumbob floating over the selected sim: a faceted spinning gem
## drawn in 2D (no 3D node, no draw-call cost in the world). `draw_gem` is
## also used by the portrait card.

const BASE := Color(0.27, 0.86, 0.3)

var tip := Vector2.ZERO   # screen point just above the head
var active := false
var gem_scale := 1.15
var _t := 0.0
var _pts := PackedVector2Array()
var _cols := PackedColorArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if active:
		queue_redraw()


func _draw() -> void:
	if not active:
		return
	var bob := sin(_t * 2.2) * 4.0
	var c := tip + Vector2(0, -34.0 * gem_scale + bob)
	# soft glow halo
	for i in 5:
		draw_circle(c, (12.0 + i * 5.0) * gem_scale, Color(0.55, 1.0, 0.5, 0.045))
	draw_gem(self, c, 14.0 * gem_scale, 30.0 * gem_scale, _t * 1.4)


static func draw_gem(ci: CanvasItem, c: Vector2, hw: float, hh: float, phase: float) -> void:
	var top := c + Vector2(0, -hh)
	var bot := c + Vector2(0, hh)
	var eq: Array[Vector2] = []
	var depth: Array[float] = []
	for k in 4:
		var a := phase + k * PI * 0.5
		var d := cos(a)
		eq.append(c + Vector2(hw * sin(a), d * hw * 0.22))
		depth.append(d)
	var tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	for k in 4:
		var k2 := (k + 1) % 4
		if depth[k] + depth[k2] <= 0.0:
			continue
		var m := phase + (k + 0.5) * PI * 0.5
		# light from the upper left/front
		var lit := clampf(0.55 - 0.4 * sin(m) + 0.15 * cos(m), 0.0, 1.0)
		var up_col := BASE.darkened(0.25).lerp(Color(0.72, 1.0, 0.62), lit)
		var dn_col := BASE.darkened(0.45).lerp(Color(0.38, 0.9, 0.36), lit)
		tri[0] = top; tri[1] = eq[k]; tri[2] = eq[k2]
		ci.draw_colored_polygon(tri, up_col)
		tri[0] = bot
		ci.draw_colored_polygon(tri, dn_col)
	# silhouette outline
	var left := c
	var right := c
	for p in eq:
		if p.x < left.x:
			left = p
		if p.x > right.x:
			right = p
	var outline := PackedVector2Array([top, right, bot, left, top])
	ci.draw_polyline(outline, Color(0.08, 0.45, 0.12, 0.55), maxf(1.0, hw * 0.09), true)
	# specular glint
	ci.draw_line(top + Vector2(-hw * 0.12, hh * 0.25), top + Vector2(-hw * 0.42, hh * 0.72), Color(1, 1, 1, 0.75), maxf(1.0, hw * 0.12), true)
