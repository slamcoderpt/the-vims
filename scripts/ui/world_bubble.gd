extends Control
## One world-anchored bubble. Kinds:
##   action  - icon + title + progress bar ("Work", "Paint") as in ref1
##   speech  - icon + short line ("Smells great!")
##   thought / emote - icon only (heart, zzz, ...)
##   skill   - small "+ Creativity" chip
## The owner (hud.gd) sets `tip` (screen point the tail touches) every frame.

const UI := preload("res://scripts/ui/ui_kit.gd")
const TAIL_H := 11.0

var kind := "action"
var text := ""
var sub := ""
var icon_tex: Texture2D
var progress := -1.0
var bar_color := UI.GREEN
var tail_frac := 0.36
var base_tail_frac := 0.36
var tip := Vector2.ZERO
var ttl := -1.0
var anchor: Node3D
var id := ""
## Fallbacks when there is no anchor: top-left `at` or tail `screen_pos`.
var fallback_at = null
var fallback_screen = null
var selected_side := false
var offset := Vector2.ZERO
## Horizontal lean of the tail tip (px) so it can point toward the head.
var tail_lean := 0.0
var _shown_progress := -1.0
var _body: StyleBoxFlat
var _age := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = UI.card_style(12, UI.WHITE, 6)


func configure(data: Dictionary) -> void:
	kind = data.get("kind", "action")
	text = data.get("text", "")
	sub = data.get("sub", "")
	icon_tex = UI.icon(data.get("icon", ""))
	progress = data.get("progress", -1.0)
	if _shown_progress < 0.0:
		_shown_progress = progress
	var bc = data.get("color", null)
	if bc is Color:
		bar_color = bc
	elif bc is String:
		bar_color = UI.BLUE if bc == "blue" else (Color(bc) if bc.begins_with("#") else UI.GREEN)
	ttl = data.get("ttl", 4.0 if kind == "skill" else -1.0)
	_body.set_corner_radius_all(11 if kind == "skill" else 12)
	_measure()
	queue_redraw()


func _measure() -> void:
	var f := UI.font(800)
	match kind:
		"action":
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			if sub != "":
				tw = maxf(tw, UI.font(700).get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
			size = Vector2(maxf(146.0 if progress >= 0.0 else 100.0, tw + 72.0), 50.0 if (progress >= 0.0 or sub != "") else 42.0)
		"speech":
			var tw2 := UI.font(700).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			size = Vector2(tw2 + (50.0 if icon_tex else 26.0), 40.0)
		"skill":
			var tw3 := f.get_string_size("+ " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			size = Vector2(tw3 + (40.0 if icon_tex else 22.0), 30.0)
		_:
			size = Vector2(44.0, 40.0)
	if kind == "skill":
		tail_frac = 0.2
	elif kind != "action":
		tail_frac = 0.4
	else:
		tail_frac = 0.36
	base_tail_frac = tail_frac


## Top-left position so the tail touches `tip`.
func place() -> void:
	if kind == "skill":
		# `tip` is the head point; the chip's tail ends just right of it.
		position = (tip - Vector2(size.x * tail_frac - 7.0, size.y + 8.0)).round()
	else:
		position = (tip - Vector2(size.x * tail_frac + tail_lean, size.y + TAIL_H)).round()


func tick(delta: float) -> bool:
	_age += delta
	if progress >= 0.0 and absf(_shown_progress - progress) > 0.001:
		_shown_progress = move_toward(_shown_progress, progress, delta * 0.8)
		queue_redraw()
	if ttl > 0.0 and not Game.frozen and _age > ttl:
		return false
	# pop-in
	var k := 1.0 if Game.frozen else clampf(_age / 0.2, 0.0, 1.0)
	var sc := 1.0 - 0.4 * pow(1.0 - k, 3.0)
	pivot_offset = Vector2(size.x * tail_frac, size.y + TAIL_H)
	scale = Vector2(sc, sc)
	return true


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_body, r)
	# tail
	var tx := size.x * tail_frac
	var tail := PackedVector2Array()
	if kind == "skill":
		# chip sits beside the head: short tail pointing down-left at it
		tail = PackedVector2Array([Vector2(tx - 3, size.y - 1), Vector2(tx + 9, size.y - 1), Vector2(tx - 7, size.y + 8.0)])
	else:
		tail = PackedVector2Array([Vector2(tx - 8, size.y - 1), Vector2(tx + 8, size.y - 1), Vector2(tx + tail_lean, size.y + TAIL_H)])
	draw_colored_polygon(tail, UI.WHITE)
	var f := UI.font(800)
	match kind:
		"action":
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(10, (size.y - 31.0) * 0.5, 31, 31), false)
			var ty := 23.0 if (progress >= 0.0 or sub != "") else 27.0
			draw_string(f, Vector2(50, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.INK)
			if sub != "" and progress < 0.0:
				draw_string(UI.font(700), Vector2(50, 39), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK_SOFT)
			if progress >= 0.0:
				# full-width rounded track under the label (ref1 "Work"/"Paint")
				UI.draw_bar(self, Rect2(50, 31, size.x - 50.0 - 12.0, 8.0), _shown_progress, bar_color, UI.TRACK)
		"speech":
			var x := 14.0
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(10, 8, 24, 24), false)
				x = 40.0
			draw_string(UI.font(700), Vector2(x, 25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.INK)
		"skill":
			var x2 := 12.0
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(8, 6, 19, 19), false)
				x2 = 31.0
			draw_string(f, Vector2(x2, 20), "+ " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK)
		_:
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2((size.x - 28.0) * 0.5, (size.y - 28.0) * 0.5, 28, 28), false)
