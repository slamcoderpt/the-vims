extends Control
## Object action menu (ref4 "Grill" card): title, then one row per action with
## icon + label. The first/hovered row is highlighted blue. Tapping a row emits
## `chosen`; tapping anywhere else closes the menu.

signal chosen(title: String, action: Dictionary)

const UI := preload("res://scripts/ui/ui_kit.gd")
const TapArea := preload("res://scripts/ui/tap_area.gd")
const W := 200.0
const ROW_H := 36.0
const TOP := 38.0

var title := ""
var actions: Array = []
var hot := 0
var _card: StyleBoxFlat
var _hot_sb: StyleBoxFlat
var _rows: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = UI.card_style(12, UI.WHITE, 10)
	_hot_sb = UI.card_style(7, UI.BLUE, 0)
	visible = false


func open(p_title: String, p_actions: Array, screen_pos: Vector2) -> void:
	title = p_title
	actions = p_actions
	hot = 0
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in actions.size():
		var t := TapArea.new()
		t.position = Vector2(8, TOP + i * ROW_H)
		t.size = Vector2(W - 16, ROW_H - 2)
		t.hit_pad = Vector4(8, 1, 8, 1)
		t.tapped.connect(_pick.bind(i))
		t.mouse_entered.connect(_hover.bind(i))
		add_child(t)
		_rows.append(t)
	size = Vector2(W, TOP + actions.size() * ROW_H + 8.0)
	# keep on screen
	var vp := get_viewport_rect().size
	position = Vector2(clampf(screen_pos.x, 8.0, vp.x - size.x - 8.0), clampf(screen_pos.y, 8.0, vp.y - size.y - 8.0))
	visible = true
	scale = Vector2(0.9, 0.9)
	pivot_offset = Vector2(0, size.y * 0.5)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.12)
	queue_redraw()


func close() -> void:
	visible = false


func _hover(i: int) -> void:
	hot = i
	queue_redraw()


func _pick(i: int) -> void:
	hot = i
	queue_redraw()
	var a: Dictionary = actions[i] if actions[i] is Dictionary else {"id": str(actions[i]), "label": str(actions[i])}
	chosen.emit(title, a)
	close()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	var p := Vector2.INF
	if e is InputEventMouseButton and e.pressed:
		p = e.position
	elif e is InputEventScreenTouch and e.pressed:
		p = e.position
	if p != Vector2.INF:
		var local := get_global_transform_with_canvas().affine_inverse() * p
		if not Rect2(Vector2(-8, -8), size + Vector2(16, 16)).has_point(local):
			close()


func _draw() -> void:
	draw_style_box(_card, Rect2(Vector2.ZERO, size))
	draw_string(UI.font(800), Vector2(14, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.INK)
	for i in actions.size():
		var a = actions[i]
		var label: String = a.get("label", "") if a is Dictionary else str(a)
		var ic: Texture2D = UI.icon(a.get("icon", "")) if a is Dictionary else null
		var r := Rect2(8, TOP + i * ROW_H, W - 16, ROW_H - 2)
		var hl := i == hot
		if hl:
			draw_style_box(_hot_sb, r)
		elif i > 0:
			draw_line(Vector2(r.position.x + 6, r.position.y - 1), Vector2(r.end.x - 6, r.position.y - 1), Color(0.88, 0.9, 0.93), 1.0)
		if ic:
			draw_texture_rect(ic, Rect2(r.position + Vector2(8, (r.size.y - 24) * 0.5), Vector2(24, 24)), false)
		draw_string(UI.font(700), r.position + Vector2(44, 23), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.WHITE if hl else UI.INK)
