extends Control
## Top-right clock card: sun/moon/season icon, "Tue.  2:16 PM", optional
## season line, and the pause / play / fast segmented control.

const UI := preload("res://scripts/ui/ui_kit.gd")
const TapArea := preload("res://scripts/ui/tap_area.gd")
const W := 288.0
const BAND_X := 66.0
const SEG_W := [76.0, 66.0, 62.0]

var show_season := true
var _card: StyleBoxFlat
var _band: StyleBoxFlat
var _seg_on: StyleBoxFlat
var _taps: Array = []
var _time_text := ""
var _season_text := ""
var _icon: Texture2D
var _f_time: Font
var _f_season: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = UI.card_style(16, UI.GLASS, 10)
	_band = UI.card_style(12, UI.SEG_BG, 0)
	_band.shadow_size = 0
	_seg_on = UI.card_style(10, UI.SEG_ACTIVE, 0)
	_f_time = UI.font(800)
	_f_season = UI.font(800)
	for i in 3:
		var t := TapArea.new()
		t.tapped.connect(_on_seg.bind(i))
		add_child(t)
		_taps.append(t)
	Game.time_changed.connect(_on_time)
	Game.speed_changed.connect(func(_s): queue_redraw())
	_on_time(Game.day, Game.minutes)
	_layout()


func set_show_season(v: bool) -> void:
	show_season = v
	_layout()


func _band_rect() -> Rect2:
	var y := 62.0 if show_season else 44.0
	return Rect2(BAND_X, y, W - BAND_X - 4.0, 38.0)


func _layout() -> void:
	var b := _band_rect()
	custom_minimum_size = Vector2(W, b.end.y + 4.0)
	size = custom_minimum_size
	var x := b.position.x
	for i in 3:
		var t: Control = _taps[i]
		t.position = Vector2(x, b.position.y)
		t.size = Vector2(SEG_W[i], b.size.y)
		# extend the touch target downwards/upwards to phone size
		t.hit_pad = Vector4(0, 18, 0, 40)
		x += SEG_W[i]
	queue_redraw()


func _on_seg(i: int) -> void:
	match i:
		0:
			Game.speed = 0
		1:
			Game.speed = 1
		2:
			Game.speed = 3 if Game.speed == 2 else 2
	queue_redraw()


func _on_time(d: int, minutes: float) -> void:
	var h := int(minutes / 60.0) % 24
	var m := int(minutes) % 60
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	var t := "%s  %d:%02d %s" % [Game.DAY_NAMES[d % 7], h12, m, "AM" if h < 12 else "PM"]
	var s: String = Game.SEASONS[Game.season % 4]
	var ic := _pick_icon()
	if t != _time_text or s != _season_text or ic != _icon:
		_time_text = t
		_season_text = s
		_icon = ic
		queue_redraw()


func _pick_icon() -> Texture2D:
	if Game.is_night():
		return UI.icon("moon_blue")
	match Game.season % 4:
		2:
			return UI.icon("leaf")
		3:
			return UI.icon("snow")
	return UI.icon("sun")


func _draw() -> void:
	var b := _band_rect()
	draw_style_box(_card, Rect2(0, 0, W, b.end.y + 4.0))
	if _icon:
		var isz := 46.0
		var iy := 12.0 if not show_season else 18.0
		draw_texture_rect(_icon, Rect2(13, iy, isz, isz), false)
	var tx := 72.0
	draw_string(_f_time, Vector2(tx, 31), _time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)
	if show_season:
		var sc := UI.ORANGE
		match Game.season % 4:
			0:
				sc = Color("e2609a")
			1:
				sc = Color("e5a114")
			3:
				sc = Color("4a8fdc")
		draw_string(_f_season, Vector2(tx, 53), _season_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, sc)
	# segmented speed control
	draw_style_box(_band, b)
	var active := 0 if Game.speed == 0 else (1 if Game.speed == 1 else 2)
	var x := b.position.x
	for i in 3:
		var r := Rect2(x, b.position.y, SEG_W[i], b.size.y)
		if i == active:
			draw_style_box(_seg_on, r.grow(-2.0) if i != 0 else Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)))
		var col := UI.WHITE if i == active else UI.SEG_ICON
		var c := r.get_center()
		match i:
			0:
				draw_rect(Rect2(c + Vector2(-7, -9), Vector2(5, 18)), col)
				draw_rect(Rect2(c + Vector2(2, -9), Vector2(5, 18)), col)
			1:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -10), c + Vector2(10, 0), c + Vector2(-6, 10)]), col)
			2:
				var cc := c + Vector2(-4, 0)
				draw_colored_polygon(PackedVector2Array([cc + Vector2(-12, -10), cc + Vector2(2, 0), cc + Vector2(-12, 10)]), col)
				draw_colored_polygon(PackedVector2Array([cc + Vector2(2, -10), cc + Vector2(16, 0), cc + Vector2(2, 10)]), col)
				if Game.speed == 3:
					draw_colored_polygon(PackedVector2Array([cc + Vector2(16, -10), cc + Vector2(30, 0), cc + Vector2(16, 10)]), col)
		x += SEG_W[i]
	# little chevron at the far end (ultra speed hint)
	var ch := Vector2(b.end.x - 9.0, b.get_center().y)
	draw_polyline(PackedVector2Array([ch + Vector2(-3, -5), ch + Vector2(1, 0), ch + Vector2(-3, 5)]), Color(UI.SEG_ICON, 0.45), 2.0, true)
