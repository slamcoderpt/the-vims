extends Control
## Bottom-left Build / Buy / Decorate / Manage buttons. The active mode is the
## blue one; in plain live mode Build is shown as the primary (blue) button,
## as in every reference shot. Tapping sets Game.mode (tap again -> "live").

const UI := preload("res://scripts/ui/ui_kit.gd")
const TapArea := preload("res://scripts/ui/tap_area.gd")
const BTN := Vector2(100, 100)
const GAP := 6.0
const MODES := [
	["build", "Build", "house_white"],
	["buy", "Buy", "armchair"],
	["decorate", "Decorate", "sprout"],
	["manage", "Manage", "hammer"],
]

var _buttons: Array = []
var _white: StyleBoxFlat
var _blue: StyleBoxFlat


class ModeButton extends Control:
	var label_text := ""
	var icon_tex: Texture2D
	var house := false
	var hot := false
	var white_sb: StyleBoxFlat
	var blue_sb: StyleBoxFlat
	var shine: Gradient

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if hot:
			draw_style_box(blue_sb, r)
			# top sheen
			var sheen := Rect2(r.position + Vector2(5, 5), Vector2(r.size.x - 10, r.size.y * 0.42))
			draw_rect(sheen, Color(1, 1, 1, 0.10))
		else:
			draw_style_box(white_sb, r)
		var isz := 50.0
		var ip := Vector2((size.x - isz) * 0.5, 12.0)
		if icon_tex:
			var mod := UI.WHITE
			if house and not hot:
				mod = UI.BLUE
			draw_texture_rect(icon_tex, Rect2(ip, Vector2(isz, isz)), false, mod)
		var f := UI.font(700)
		var fs := 17
		var tw := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y - 16.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.WHITE if hot else UI.INK)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white = UI.card_style(14, UI.GLASS, 9)
	_blue = UI.card_style(14, UI.BLUE, 10, 3, Color(1, 1, 1, 0.95))
	_blue.shadow_color = Color(0.1, 0.35, 0.85, 0.35)
	for i in MODES.size():
		var m: Array = MODES[i]
		var tap := TapArea.new()
		tap.position = Vector2(i * (BTN.x + GAP), 0)
		tap.size = BTN
		tap.hit_pad = Vector4(3, 8, 3, 8)
		add_child(tap)
		var b := ModeButton.new()
		b.size = BTN
		b.label_text = m[1]
		b.icon_tex = UI.icon(m[2])
		b.house = m[0] == "build"
		b.white_sb = _white
		b.blue_sb = _blue
		tap.add_child(b)
		tap.visual = b
		tap.tapped.connect(_on_tap.bind(m[0]))
		_buttons.append(b)
	size = Vector2(MODES.size() * (BTN.x + GAP) - GAP, BTN.y)
	Game.mode_changed.connect(func(_m): _refresh())
	_refresh()


func _on_tap(mode: String) -> void:
	Game.mode = "live" if Game.mode == mode else mode


func _refresh() -> void:
	var hot: String = Game.mode if Game.mode != "live" else "build"
	for i in MODES.size():
		var b = _buttons[i]
		b.hot = MODES[i][0] == hot
		b.queue_redraw()
