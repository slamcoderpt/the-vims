extends Control
## Dark translucent panel with one icon + colour bar per need (ref top-left).
## Drawn entirely in _draw (one canvas item, no child nodes).

const UI := preload("res://scripts/ui/ui_kit.gd")
const PAD_Y := 9.0
const ICON := 23.0

var member: Dictionary = {}
var row_h := 25.5
var _style: StyleBoxFlat
var _shown := {}  # need -> displayed value (eases toward real value)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = UI.card_style(10, UI.NEED_PANEL, 6)
	_style.shadow_color = Color(0, 0, 0, 0.18)


func setup(m: Dictionary) -> void:
	member = m
	_shown.clear()
	for k in m.get("needs", {}):
		_shown[k] = m.needs[k]
	custom_minimum_size = Vector2(176, preferred_height())
	size = custom_minimum_size
	queue_redraw()


func preferred_height() -> float:
	return PAD_Y * 2.0 + row_h * maxi(1, member.get("needs", {}).size()) - 3.0


func refresh() -> void:
	var changed := false
	var needs: Dictionary = member.get("needs", {})
	for k in needs:
		var v: float = needs[k]
		if absf(_shown.get(k, -1.0) - v) > 0.002:
			_shown[k] = v
			changed = true
	if changed:
		queue_redraw()


func _icon_for(need: String) -> Texture2D:
	if need == "hunger" and member.get("kind", "") == "dog":
		return UI.icon("bone")
	return UI.icon(UI.NEED_ICONS.get(need, "star"))


func _draw() -> void:
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var needs: Dictionary = member.get("needs", {})
	var y := PAD_Y
	var bar_x := 40.0
	var bar_w := size.x - bar_x - 14.0
	for k in needs:
		var v: float = _shown.get(k, needs[k])
		var tex := _icon_for(k)
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(10.0, y + (row_h - ICON) * 0.5 - 1.0), Vector2(ICON, ICON)), false)
		var col: Color = UI.NEED_COLORS.get(k, Color.WHITE)
		if v < 0.2:
			col = col.lerp(Color("f04848"), 0.75)
		UI.draw_bar(self, Rect2(bar_x, y + row_h * 0.5 - 6.5, bar_w, 12.0), v, col, UI.NEED_TRACK)
		y += row_h
