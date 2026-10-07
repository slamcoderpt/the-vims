extends Control
## One world-anchored bubble. Kinds:
##   action  - icon + title + progress bar ("Work", "Paint") as in ref1
##   speech  - icon + short line ("Smells great!")
##   thought / emote - icon only (heart, zzz, ...)
##   skill   - small "+ Creativity" chip
## The owner (hud.gd) sets `tip` (screen point the tail touches) every frame.

const UI := preload("res://scripts/ui/ui_kit.gd")
const TAIL_H := 13.0
## Action bubble metrics (design px at 1672x941), sized to ref1's Work/Paint.
const A_H := 60.0
const A_H_PLAIN := 50.0
const A_ICON := 36.0
const A_TEXT_X := 60.0
const A_FONT := 20
const A_PAD_R := 18.0
const A_MIN_W := 172.0

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
## Tail tip straight above the head before layout lifts; plumbob side (+1/-1/0).
var base_tip := Vector2.ZERO
var plumb_side := 0
var offset := Vector2.ZERO
## Horizontal lean of the tail tip (px) so it can point toward the head.
var tail_lean := 0.0
## Layout state owned by hud.gd: projected head point / size, desired top-left.
var head := Vector2.INF
var head_px := 60.0
var target := Vector2.ZERO
var placed := false
var _shown_progress := -1.0
var _body: StyleBoxFlat
var _age := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = UI.card_style(14, UI.WHITE, 7)


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
	_body.set_corner_radius_all(12 if kind == "skill" else 14)
	_measure()
	queue_redraw()


func _measure() -> void:
	var f := UI.font(800)
	match kind:
		"action":
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, A_FONT).x
			if sub != "":
				tw = maxf(tw, UI.font(700).get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
			size = Vector2(maxf(A_MIN_W if progress >= 0.0 else 120.0, tw + A_TEXT_X + A_PAD_R + (22.0 if progress >= 0.0 else 0.0)), A_H if (progress >= 0.0 or sub != "") else A_H_PLAIN)
		"speech":
			var tw2 := UI.font(700).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			size = Vector2(tw2 + (58.0 if icon_tex else 30.0), 46.0)
		"skill":
			var tw3 := f.get_string_size("+ " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			size = Vector2(tw3 + (48.0 if icon_tex else 26.0), 36.0)
		_:
			size = Vector2(50.0, 46.0)
	if kind == "skill":
		tail_frac = 0.2
	elif kind != "action":
		tail_frac = 0.4
	else:
		tail_frac = 0.5
	base_tail_frac = tail_frac


## Top-left position so the tail touches `tip`.
func place() -> void:
	if kind == "skill":
		# `tip` is the head point; the chip's tail ends just right of it.
		position = (tip - Vector2(size.x * tail_frac - 7.0, size.y + 8.0)).round()
	else:
		position = (tip - Vector2(size.x * tail_frac + tail_lean, size.y + TAIL_H)).round()


func _tail_base_x() -> float:
	return clampf(tip.x - position.x, 17.0, size.x - 17.0)


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
	pivot_offset = Vector2(_tail_base_x(), size.y + TAIL_H)
	scale = Vector2(sc, sc)
	return true


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_body, r)
	# tail: base under the tip (kept inside the rounded body), short point
	# leaning toward the sim so it reads as "this one" even after nudging
	var tail := PackedVector2Array()
	var lt := tip - position
	if kind == "skill":
		# chip sits beside the head: short tail pointing down-left at it
		var cx := clampf(lt.x + 4.0, 12.0, size.x - 14.0)
		tail = PackedVector2Array([Vector2(cx - 3, size.y - 1), Vector2(cx + 9, size.y - 1), Vector2(cx - 7, size.y + 8.0)])
	elif lt.y < size.y - 4.0 and (lt.x < 0.0 or lt.x > size.x):
		# hung beside the head (no room above): tail out of the side
		var cy := clampf(lt.y, 16.0, size.y - 14.0)
		var ex := 1.0 if lt.x < 0.0 else size.x - 1.0
		var px := -TAIL_H if lt.x < 0.0 else size.x + TAIL_H
		tail = PackedVector2Array([Vector2(ex, cy - 10), Vector2(ex, cy + 10), Vector2(px, cy + 7)])
	else:
		var tx := _tail_base_x()
		var lean := clampf((lt.x - tx) * 0.5, -9.0, 9.0)
		tail = PackedVector2Array([Vector2(tx - 11, size.y - 1), Vector2(tx + 11, size.y - 1), Vector2(tx + lean, size.y + TAIL_H)])
	draw_colored_polygon(tail, UI.WHITE)
	var f := UI.font(800)
	match kind:
		"action":
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(13, (size.y - A_ICON) * 0.5, A_ICON, A_ICON), false)
			var tall := progress >= 0.0 or sub != ""
			var ty := 27.0 if tall else 32.0
			draw_string(f, Vector2(A_TEXT_X, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, A_FONT, UI.INK)
			if sub != "" and progress < 0.0:
				draw_string(UI.font(700), Vector2(A_TEXT_X, 47), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.INK_SOFT)
			if progress >= 0.0:
				# full-width rounded track under the label (ref1 "Work"/"Paint")
				UI.draw_bar(self, Rect2(A_TEXT_X, 37, size.x - A_TEXT_X - A_PAD_R, 9.0), _shown_progress, bar_color, UI.TRACK)
		"speech":
			var x := 14.0
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(11, 9, 28, 28), false)
				x = 46.0
			draw_string(UI.font(700), Vector2(x, 29), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.INK)
		"skill":
			var x2 := 12.0
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2(9, 6, 24, 24), false)
				x2 = 37.0
			draw_string(f, Vector2(x2, 24), "+ " + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.INK)
		_:
			if icon_tex:
				draw_texture_rect(icon_tex, Rect2((size.x - 32.0) * 0.5, (size.y - 32.0) * 0.5, 32, 32), false)
