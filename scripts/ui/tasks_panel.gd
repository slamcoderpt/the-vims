extends PanelContainer
## Right-side "Tasks" card: title, then one row per task with checkbox, icon
## and label. Done rows get the pale green highlight (ref top-right).
## With bind_game = false it is a generic checklist (e.g. ref5's Shopping
## List): call set_items([{title, icon, done, count}]).

const UI := preload("res://scripts/ui/ui_kit.gd")

var title := "Tasks"
var title_icon := ""
var bind_game := true
var title_size := 19
var _items: Array = []
var _list: VBoxContainer
var _title: Label
var _row_done: StyleBoxFlat
var _row_plain: StyleBoxEmpty


class CheckBoxView extends Control:
	var done := false
	var _on: StyleBoxFlat
	var _off: StyleBoxFlat

	func _init() -> void:
		custom_minimum_size = Vector2(20, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_on = UI.card_style(5, Color("49b83e"), 0)
		_off = UI.card_style(5, UI.WHITE, 0, 2, Color("b9bfcc"))

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), Vector2(18, 18))
		if done:
			draw_style_box(_on, r)
			UI.draw_check(self, r, UI.WHITE, 2.6)
		else:
			draw_style_box(_off, r)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UI.card_style(14, UI.GLASS, 10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	_row_done = UI.card_style(8, UI.DONE_ROW, 0)
	_row_done.content_margin_left = 7
	_row_done.content_margin_right = 2
	_row_done.content_margin_top = 4
	_row_done.content_margin_bottom = 4
	_row_plain = StyleBoxEmpty.new()
	_row_plain.content_margin_left = 7
	_row_plain.content_margin_right = 2
	_row_plain.content_margin_top = 4
	_row_plain.content_margin_bottom = 4
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_title = UI.label(title, title_size, 800, UI.INK)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 11)
	tm.add_theme_constant_override("margin_bottom", 4)
	tm.add_theme_constant_override("margin_top", -2)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title_icon != "":
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 10)
		th.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ti := TextureRect.new()
		ti.texture = UI.icon(title_icon)
		ti.custom_minimum_size = Vector2(30, 30)
		ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
		th.add_child(ti)
		th.add_child(_title)
		tm.add_child(th)
	else:
		tm.add_child(_title)
	v.add_child(tm)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_list)
	if bind_game:
		Game.tasks_changed.connect(rebuild)
	rebuild()


func set_items(items: Array) -> void:
	_items = items
	if is_inside_tree():
		rebuild()


func rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var src: Array = Game.tasks if bind_game else _items
	for t in src:
		_list.add_child(_make_row(t))
	visible = not src.is_empty()
	# shrink to content
	reset_size.call_deferred()


func _make_row(t: Dictionary) -> Control:
	var done: bool = t.get("done", false)
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", _row_done if done else _row_plain)
	row.custom_minimum_size = Vector2(0, 39)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var cb := CheckBoxView.new()
	cb.done = done
	h.add_child(cb)
	var ic := TextureRect.new()
	ic.texture = UI.icon(t.get("icon", ""))
	ic.custom_minimum_size = Vector2(27, 27)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var l := UI.label(t.get("title", ""), 15, 700, UI.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(134, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_constant_override("line_spacing", -3)
	h.add_child(l)
	if t.has("count"):
		var cl := UI.label(str(t.count), 15, 700, UI.INK)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cl.custom_minimum_size = Vector2(30, 0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(cl)
	return row
