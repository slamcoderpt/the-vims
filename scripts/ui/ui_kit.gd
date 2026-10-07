extends RefCounted
## Shared HUD look: palette, Nunito weights, icon cache, card styles and a few
## drawing helpers. Everything is static so widgets can `const UI := preload(...)`.

const INK := Color("2a2f45")
const INK_SOFT := Color("5d6480")
const WHITE := Color(1, 1, 1)
const CARD := Color("fdfdfe")
## Slightly see-through white used by the fixed HUD cards (refs show a hint of the scene).
const GLASS := Color(1, 1, 1, 0.94)
const BLUE := Color("3d8ef0")
const BLUE_DARK := Color("2a72dc")
const BLUE_LIGHT := Color("6fb0ff")
const GREEN := Color("55c449")
const GREEN_DARK := Color("3aa532")
const DONE_ROW := Color("ddf4d6")
const TRACK := Color("d8dee8")
const SHADOW := Color(0.08, 0.1, 0.2, 0.22)
const NEED_PANEL := Color(0.13, 0.15, 0.21, 0.78)
const NEED_TRACK := Color(0.36, 0.38, 0.45, 0.85)
const SEG_BG := Color("ccd1e0")
const SEG_ACTIVE := Color("9198b1")
const SEG_ICON := Color("2c3a5e")
const ORANGE := Color("e8801e")

## Need colours (bars + tints), matching the refs.
const NEED_COLORS := {
	"fun": Color("5fd04a"),
	"hunger": Color("f7b92f"),
	"hygiene": Color("3ab7ef"),
	"energy": Color("ae69f2"),
	"social": Color("f36b7c"),
	"bladder": Color("e0c050"),
}
const NEED_ICONS := {
	"fun": "need_fun", "hunger": "need_hunger", "hygiene": "need_hygiene",
	"energy": "need_energy", "social": "need_social", "bladder": "need_bladder",
}
## Aliases so callers can use loose icon names.
const ICON_ALIAS := {
	"email": "laptop", "computer": "laptop", "work": "laptop", "paint": "palette",
	"homework": "book", "skill": "chart", "dog": "paw", "play": "paw",
	"food": "burger", "grill": "burger", "friend": "heart", "photo": "camera",
	"clean": "broom", "groceries": "cart", "neighbor": "people", "prize": "gift",
	"snack": "cart", "game": "target", "teeth": "brush", "story": "book_open",
	"sleep_bubble": "zzz", "creativity": "bulb", "practice": "music",
	"compare": "scale", "talk": "chat", "...": "dots",
}

static var _fonts := {}
static var _icons := {}
static var _base_font: Font


static func font(weight := 800) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	if _base_font == null:
		_base_font = load("res://assets/fonts/Nunito.ttf")
	var fv := FontVariation.new()
	fv.base_font = _base_font
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[weight] = fv
	return fv


static func icon(icon_name: String) -> Texture2D:
	if icon_name == "":
		return null
	if _icons.has(icon_name):
		return _icons[icon_name]
	var n: String = ICON_ALIAS.get(icon_name, icon_name)
	var path := "res://assets/ui/icons/%s.png" % n
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		path = "res://assets/ui/icons/star.png"
		if ResourceLoader.exists(path):
			tex = load(path)
	_icons[icon_name] = tex
	return tex


static func card_style(radius := 14, bg := CARD, shadow := 10, border := 0, border_col := WHITE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.8
	if shadow > 0:
		sb.shadow_color = SHADOW
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 3)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_col
	return sb


static func flat(bg: Color, radius := 8) -> StyleBoxFlat:
	return card_style(radius, bg, 0)


static func label(text: String, size := 16, weight := 800, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func money_text(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var rem := n - 1 - i
		if rem > 0 and rem % 3 == 0:
			out += ","
	return ("-$ " if v < 0 else "$ ") + out


## Draw a horizontal rounded progress bar on `ci` (a CanvasItem in _draw).
static func draw_bar(ci: CanvasItem, rect: Rect2, value: float, fill: Color, track: Color) -> void:
	var r := rect.size.y * 0.5
	_draw_pill(ci, rect, track, r)
	var v := clampf(value, 0.0, 1.0)
	if v <= 0.001:
		return
	var w := maxf(rect.size.y, rect.size.x * v)
	var fr := Rect2(rect.position, Vector2(w, rect.size.y))
	_draw_pill(ci, fr, fill, r)
	# glossy top highlight
	var hi := Rect2(fr.position + Vector2(r * 0.6, 1.0), Vector2(maxf(0.0, fr.size.x - r * 1.2), maxf(1.0, rect.size.y * 0.32)))
	if hi.size.x > 1.0:
		ci.draw_rect(hi, Color(1, 1, 1, 0.28))


static func _draw_pill(ci: CanvasItem, rect: Rect2, col: Color, r: float) -> void:
	var sb := _pill_cache(col, r)
	sb.draw(ci.get_canvas_item(), rect)


static var _pills := {}


static func _pill_cache(col: Color, r: float) -> StyleBoxFlat:
	var key := col.to_rgba32() * 31 + int(r * 4.0)
	if _pills.has(key):
		return _pills[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(ceil(r)))
	sb.corner_detail = 5
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.7
	_pills[key] = sb
	return sb


## White check mark inside `rect`.
static func draw_check(ci: CanvasItem, rect: Rect2, col := WHITE, width := 2.6) -> void:
	var p := rect.position
	var s := rect.size
	var pts := PackedVector2Array([p + Vector2(s.x * 0.22, s.y * 0.52), p + Vector2(s.x * 0.42, s.y * 0.72), p + Vector2(s.x * 0.78, s.y * 0.3)])
	ci.draw_polyline(pts, col, width, true)
