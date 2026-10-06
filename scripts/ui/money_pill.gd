extends Control
## Bottom-right household funds: green bill icon + "$ 12,450". Counts up/down
## smoothly when Game.money changes.

const UI := preload("res://scripts/ui/ui_kit.gd")

var _shown := 0.0
var _target := 0
var _text := ""
var _card: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = UI.card_style(14, UI.GLASS, 10)
	_target = Game.money
	_shown = _target
	_set_text()
	Game.money_changed.connect(_on_money)
	set_process(false)


func _on_money(m: int) -> void:
	_target = m
	set_process(true)


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, maxf(40.0, absf(_target - _shown) * 6.0) * delta)
	if absf(_shown - _target) < 0.5:
		_shown = _target
		set_process(false)
	_set_text()


func _set_text() -> void:
	var t := UI.money_text(int(round(_shown)))
	if t != _text:
		_text = t
		var f := UI.font(800)
		var w := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
		custom_minimum_size = Vector2(maxf(182.0, w + 84.0), 54.0)
		size = custom_minimum_size
		queue_redraw()


func _draw() -> void:
	draw_style_box(_card, Rect2(Vector2.ZERO, size))
	var ic := UI.icon("money")
	if ic:
		draw_texture_rect(ic, Rect2(14, 9, 38, 38), false)
	draw_string(UI.font(800), Vector2(64, 37), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, UI.INK)
