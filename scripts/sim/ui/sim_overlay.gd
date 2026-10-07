extends CanvasLayer
## Gameplay HUD additions, driven only by Game state/signals:
##   * Sims 3 style action-queue strip next to the selected sim's portrait
##     (current action with progress + queued ones; tap a tile to cancel it)
##   * overall mood pill (green / yellow / red) + moodlet chips
##   * a Mood / Skills panel (tap the mood pill or the skills button):
##     every moodlet with its effect and time left, skill levels 1-10
##   * toasts for Game.notify (warnings: "Lily is hungry", level ups...)
##   * tints the HUD plumbob + portrait gems by mood (hue shift material, so
##     the HUD's own drawing code is untouched)
## Everything is drawn in _draw of a few Controls (no per-frame allocations
## besides the throttled redraws).

const UI := preload("res://scripts/ui/ui_kit.gd")
const Careers := preload("res://scripts/sim/careers.gd")
const Traits := preload("res://scripts/sim/traits.gd")

const TILE := 56.0
## Height of the strip (queue row + mood row).
const STRIP_H := TILE + 9.0 + 34.0
const TILE_SMALL := 44.0
const GAP := 7.0
const CHIP := 34.0
const PANEL_W := 362.0
const TOAST_TTL := 3.2
const TAB_W := 58.0
const TABS := [["mood", "Mood", 10.0], ["skills", "Skills", 71.0], ["rels", "Friends", 132.0], ["wishes", "Wishes", 193.0], ["career", "Job", 254.0]]
## Career tab: rows (in panel rows of 44 px) and the tendency buttons' y.
const CAREER_ROWS := 5
const REL_ROWS := 7
const HUE_SHADER := """
shader_type canvas_item;
uniform float hue_shift = 0.0;
uniform float sat_mul = 1.0;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void fragment() {
	vec4 c = COLOR;
	vec3 h = rgb2hsv(c.rgb);
	h.x = fract(h.x + hue_shift);
	h.y = clamp(h.y * sat_mul, 0.0, 1.0);
	COLOR = vec4(hsv2rgb(h), c.a);
}
"""
## Plumbob hue shift per mood band (the gem is drawn green).
const HUE := {"good": 0.0, "okay": -0.19, "bad": -0.335}

var hud: Node
## When true (screenshot staging) nothing reacts to taps.
var static_mode := false
var root: Control
var strip: Control
var panel: Control
var toasts: Control
var panel_tab := "mood"   # "mood" | "skills" | "rels" | "wishes" | "career"
var panel_open := false

var _hits: Array = []        # [Rect2 (global), kind, arg]
var _press := Vector2.INF
var _redraw_t := 0.0
var _toast_list: Array = []  # {text, icon, t}
var _hue_shader: Shader
var _plumbob_mat: ShaderMaterial
var _gem_mats := {}          # portrait -> material
var _shown_hue := {}         # index -> current hue (eases)
var _card: StyleBoxFlat
var _card_dark: StyleBoxFlat
var _tile_cur: StyleBoxFlat
var _tile: StyleBoxFlat
var _tab_on: StyleBoxFlat
var _tab_off: StyleBoxFlat


func _ready() -> void:
	layer = 11
	root = Control.new()
	root.name = "SimOverlayRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	strip = Control.new()
	strip.name = "QueueMood"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(_draw_strip)
	root.add_child(strip)
	panel = Control.new()
	panel.name = "MoodSkills"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	panel.draw.connect(_draw_panel)
	root.add_child(panel)
	toasts = Control.new()
	toasts.name = "Toasts"
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.draw.connect(_draw_toasts)
	root.add_child(toasts)

	_card = UI.card_style(14, UI.GLASS, 8)
	_card_dark = UI.card_style(12, UI.NEED_PANEL, 6)
	_card_dark.shadow_color = Color(0, 0, 0, 0.16)
	_tile_cur = UI.card_style(13, UI.WHITE, 8, 3, UI.BLUE)
	_tile = UI.card_style(11, Color(1, 1, 1, 0.9), 5)
	_tab_on = UI.card_style(9, UI.BLUE, 0)
	_tab_off = UI.card_style(9, Color("eef1f6"), 0)

	_hue_shader = Shader.new()
	_hue_shader.code = HUE_SHADER
	_plumbob_mat = ShaderMaterial.new()
	_plumbob_mat.shader = _hue_shader

	Game.queue_changed.connect(func(_i): _dirty())
	Game.moodlets_changed.connect(func(_i): _dirty())
	Game.mood_changed.connect(func(_i, _m): _dirty())
	Game.selected_changed.connect(func(_i): _dirty())
	Game.skill_changed.connect(func(_i, _s, _l): _dirty())
	Game.relationship_changed.connect(func(_a, _b, _v): _dirty())
	Game.household_changed.connect(_dirty)
	Game.wishes_changed.connect(func(_i): _dirty())
	Game.career_changed.connect(func(_i): _dirty())
	Game.bills_changed.connect(_dirty)
	Game.mode_changed.connect(_on_mode)
	Game.notify.connect(toast)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _on_mode(_m: String) -> void:
	panel.visible = false
	panel_open = false
	_hits.clear()
	_dirty()


func _dirty() -> void:
	if strip:
		strip.queue_redraw()
	if panel and panel.visible:
		panel.queue_redraw()


func _ui_scale() -> float:
	if hud and hud.get("ui_scale") != null:
		return float(hud.ui_scale)
	return 1.0


func _layout() -> void:
	var s := _ui_scale()
	scale = Vector2(s, s)
	var vs := get_viewport().get_visible_rect().size / s
	root.size = vs
	toasts.size = vs
	strip.position = _strip_origin()
	strip.size = Vector2(560, 120)
	panel.size = Vector2(PANEL_W, 300)
	_place_panel()


## Bottom left, right of the Build / Buy / Decorate / Manage bar (where Sims 3
## keeps the action queue): queue tiles on top, mood + moodlets below. Down
## there it never collides with the speech bubbles over the sims' heads.
func _strip_origin() -> Vector2:
	var vs := root.size if root else Vector2(1672, 941)
	var x := 470.0
	var y := vs.y - 120.0
	if hud:
		var mb = hud.get("modes")
		if mb is Control and mb.visible:
			x = mb.position.x + mb.size.x + 18.0
			y = mb.position.y + mb.size.y - STRIP_H
	return Vector2(x, y)


## The panel opens upward from the strip.
func _place_panel() -> void:
	if panel and strip:
		panel.position = strip.position + Vector2(0, -panel.size.y - 10.0)


# =================================================================== per frame

func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.2
		var o := _strip_origin()
		if o != strip.position:
			strip.position = o
			_place_panel()
		strip.queue_redraw()
		if panel.visible:
			panel.queue_redraw()
	if not _toast_list.is_empty():
		for k in range(_toast_list.size() - 1, -1, -1):
			_toast_list[k].t -= delta
			if _toast_list[k].t <= 0.0:
				_toast_list.remove_at(k)
		toasts.queue_redraw()
	_tint_gems(delta)


## Hue-shift the HUD plumbob and the selected portrait's gem by mood.
func _tint_gems(delta: float) -> void:
	if hud == null:
		return
	var sel := Game.selected
	if sel < 0 or sel >= Game.household.size():
		return
	var want: float = HUE[Game.mood_band(sel)]
	var cur: float = _shown_hue.get(sel, want)
	cur = move_toward(cur, want, delta * 0.6)
	_shown_hue[sel] = cur
	var pb = hud.get("plumbob")
	if pb is CanvasItem:
		if pb.material != _plumbob_mat:
			pb.material = _plumbob_mat
		_plumbob_mat.set_shader_parameter("hue_shift", cur)
	var ps = hud.get("_portraits")
	if ps is Array:
		for i in ps.size():
			var p = ps[i]
			if not is_instance_valid(p):
				continue
			var gem = p.get("_gem")
			if not gem is CanvasItem:
				continue
			var m: ShaderMaterial = _gem_mats.get(p)
			if m == null:
				m = ShaderMaterial.new()
				m.shader = _hue_shader
				_gem_mats[p] = m
				gem.material = m
			var h: float = _shown_hue.get(i, HUE[Game.mood_band(i)]) if i == sel else HUE[Game.mood_band(i)]
			m.set_shader_parameter("hue_shift", h)


# =================================================================== input

## Is a tappable overlay element under this (viewport) point?
func hit(p: Vector2) -> bool:
	if static_mode or Game.mode != "live":
		return false
	for h in _hits:
		if (h[0] as Rect2).has_point(p):
			return true
	if panel.visible and _global_rect(panel, Rect2(Vector2.ZERO, panel.size)).has_point(p):
		return true
	return false


func _input(e: InputEvent) -> void:
	if static_mode or not e is InputEventScreenTouch:
		return
	if e.pressed:
		_press = e.position
		# A press outside an open panel closes it.
		if panel.visible and not hit(e.position):
			panel.visible = false
			panel_open = false
		return
	if _press == Vector2.INF or e.position.distance_to(_press) > 16.0:
		_press = Vector2.INF
		return
	_press = Vector2.INF
	if Game.mode != "live":
		return
	for h in _hits:
		if (h[0] as Rect2).has_point(e.position):
			_on_hit(h[1], h[2])
			return


func _on_hit(kind: String, arg) -> void:
	match kind:
		"queue":
			Game.request_queue_cancel(Game.selected, int(arg))
		"mood":
			open_panel("mood")
		"skills":
			open_panel("skills")
		"rels":
			open_panel("rels")
		"wishes":
			open_panel("wishes")
		"career":
			open_panel("career")
		"tendency":
			Game.set_tendency(Game.selected, str(arg))
		"wish":
			var ws: Array = Game.wishes(Game.selected)
			if int(arg) < ws.size():
				Game.toggle_promise(Game.selected, ws[int(arg)].id)
		"tab":
			panel_tab = str(arg)
			panel.queue_redraw()
		"close":
			panel.visible = false
			panel_open = false
	_dirty()


func open_panel(tab: String) -> void:
	if panel.visible and panel_tab == tab:
		panel.visible = false
		panel_open = false
		return
	panel_tab = tab
	panel.visible = true
	panel_open = true
	panel.queue_redraw()


func _global_rect(c: Control, r: Rect2) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf * r.position, xf.basis_xform(r.size))


func _add_hit(c: Control, r: Rect2, kind: String, arg = null) -> void:
	_hits.append([_global_rect(c, r.grow(4.0)), kind, arg])


func toast(text: String, icon := "") -> void:
	for t in _toast_list:
		if t.text == text:
			t.t = TOAST_TTL
			return
	_toast_list.append({"text": text, "icon": icon, "t": TOAST_TTL})
	while _toast_list.size() > 3:
		_toast_list.pop_front()
	toasts.queue_redraw()


# =================================================================== drawing

func _draw_strip() -> void:
	_hits.clear()
	var sel := Game.selected
	if sel < 0 or sel >= Game.household.size() or Game.mode != "live":
		return
	var view: Array = Game.queue_view(sel)
	var x := 0.0
	var y := 0.0
	# ---- queue tiles
	for k in mini(view.size(), 6):
		var q: Dictionary = view[k]
		var cur: bool = q.get("current", false)
		var sz := TILE if cur else TILE_SMALL
		var r := Rect2(x, y + (TILE - sz) * 0.5, sz, sz)
		var a := 0.62 if q.get("auto", false) else 1.0
		strip.draw_style_box(_tile_cur if cur else _tile, r)
		var ic := UI.icon(q.get("icon", ""))
		if ic:
			var isz := sz * (0.6 if cur else 0.62)
			strip.draw_texture_rect(ic, Rect2(r.position + (r.size - Vector2(isz, isz)) * 0.5 - Vector2(0, 3 if cur else 0), Vector2(isz, isz)), false, Color(1, 1, 1, a))
		if cur:
			var bar := Rect2(r.position.x + 8, r.end.y - 11, r.size.x - 16, 5)
			UI.draw_bar(strip, bar, float(q.get("progress", 0.0)), UI.BLUE, UI.TRACK)
		# cancel badge on the current action; queued tiles cancel on tap too
		if not q.get("forced", false):
			if cur:
				var bc := r.position + Vector2(r.size.x - 4, 4)
				strip.draw_circle(bc, 8.5, Color(0.93, 0.33, 0.3, 0.95))
				strip.draw_line(bc + Vector2(-3.2, -3.2), bc + Vector2(3.2, 3.2), Color.WHITE, 2.0, true)
				strip.draw_line(bc + Vector2(-3.2, 3.2), bc + Vector2(3.2, -3.2), Color.WHITE, 2.0, true)
			_add_hit(strip, r, "queue", k)
		x += sz + GAP
		if cur and view.size() > 1:
			# chevron between current and queued
			var cy := y + TILE * 0.5
			strip.draw_polyline(PackedVector2Array([Vector2(x - 2, cy - 6), Vector2(x + 3, cy), Vector2(x - 2, cy + 6)]), Color(1, 1, 1, 0.9), 2.5, true)
			x += 8.0
	if view.is_empty():
		# idle: a small pill instead of tiles
		var r := Rect2(0, 10, 88, 32)
		strip.draw_style_box(_card_dark, r)
		strip.draw_string(UI.font(800), Vector2(14, 31), "Idle", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
		var zz := UI.icon("dots")
		if zz:
			strip.draw_texture_rect(zz, Rect2(52, 14, 24, 24), false, Color(1, 1, 1, 0.85))
	# ---- mood pill + moodlets
	y = TILE + 9.0
	var band := Game.mood_band(sel)
	var col: Color = Game.MOOD_COLORS[band]
	var word := Game.mood_word(sel)
	var f := UI.font(800)
	var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var pill := Rect2(0, y, 38.0 + tw + 14.0, 34)
	strip.draw_style_box(_card_dark, pill)
	_draw_mood_face(strip, pill.position + Vector2(19, 17), 11.0, col, band)
	strip.draw_string(f, pill.position + Vector2(36, 22.5), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	_add_hit(strip, pill, "mood")
	x = pill.end.x + 8.0
	var mls: Array = Game.moodlets(sel)
	var shown := mini(mls.size(), 4)
	for k in shown:
		var ml: Dictionary = mls[k]
		var c := pill.position + Vector2(0, 17)
		c.x = x + CHIP * 0.5
		_draw_moodlet_chip(strip, c, ml)
		x += CHIP + 4.0
	if mls.size() > shown:
		strip.draw_string(UI.font(800), Vector2(x + 2, y + 22), "+%d" % (mls.size() - shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		x += 26.0
	if shown > 0:
		_add_hit(strip, Rect2(pill.end.x + 4, y, x - pill.end.x - 4, 34), "mood")
	# skills button
	var sb := Rect2(x + 2, y, 34, 34)
	strip.draw_style_box(_card_dark, sb)
	var sic := UI.icon("chart")
	if sic:
		strip.draw_texture_rect(sic, Rect2(sb.position + Vector2(6, 6), Vector2(22, 22)), false)
	_add_hit(strip, sb, "skills")
	# relationships button
	var rb := Rect2(sb.end.x + 6, y, 34, 34)
	strip.draw_style_box(_card_dark, rb)
	var ric := UI.icon("heart")
	if ric:
		strip.draw_texture_rect(ric, Rect2(rb.position + Vector2(6, 6), Vector2(22, 22)), false)
	_add_hit(strip, rb, "rels")
	# wishes button (gold star, with a count of promised wishes)
	var wb := Rect2(rb.end.x + 6, y, 34, 34)
	strip.draw_style_box(_card_dark, wb)
	var wic := UI.icon("star")
	if wic:
		strip.draw_texture_rect(wic, Rect2(wb.position + Vector2(6, 6), Vector2(22, 22)), false)
	var np := 0
	for w in Game.wishes(sel):
		if w.get("promised", false):
			np += 1
	if np > 0:
		var bc := wb.position + Vector2(wb.size.x - 3, 3)
		strip.draw_circle(bc, 8.0, Color("f0a43a"))
		strip.draw_string(UI.font(800), bc + Vector2(-4, 4.5), str(np), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	_add_hit(strip, wb, "wishes")
	# job / school button (laptop or book), with a red dot when bills are overdue
	var jb := Rect2(wb.end.x + 6, y, 34, 34)
	strip.draw_style_box(_card_dark, jb)
	var cm: Dictionary = Game.career(sel)
	var jic := UI.icon("book" if Careers.is_school(cm) else "laptop")
	if jic:
		strip.draw_texture_rect(jic, Rect2(jb.position + Vector2(6, 6), Vector2(22, 22)), false)
	if Game.is_at_work(sel):
		strip.draw_circle(jb.position + Vector2(jb.size.x - 3, 3), 6.0, Color("4fd34a"))
	elif Game.bills_overdue():
		strip.draw_circle(jb.position + Vector2(jb.size.x - 3, 3), 6.0, Color("ee4a3c"))
	_add_hit(strip, jb, "career")
	if panel.visible:
		_panel_hits()
		_add_hit(panel, Rect2(Vector2.ZERO, panel.size), "panel")


func _draw_mood_face(ci: CanvasItem, c: Vector2, r: float, col: Color, band: String) -> void:
	ci.draw_circle(c, r + 2.0, col.darkened(0.35))
	ci.draw_circle(c, r, col)
	ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.42), r * 0.28, Color(1, 1, 1, 0.35))
	var ink := Color(0.12, 0.14, 0.2)
	ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.18), r * 0.13, ink)
	ci.draw_circle(c + Vector2(r * 0.36, -r * 0.18), r * 0.13, ink)
	var pts := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		var px := lerpf(-r * 0.45, r * 0.45, t)
		var curve := (1.0 - pow(2.0 * t - 1.0, 2.0)) * r * 0.32
		var py := r * 0.3
		match band:
			"good": py += curve
			"bad": py += r * 0.22 - curve
		pts.append(c + Vector2(px, py))
	ci.draw_polyline(pts, ink, maxf(1.5, r * 0.14), true)


func _draw_moodlet_chip(ci: CanvasItem, c: Vector2, ml: Dictionary) -> void:
	var good: bool = ml.delta >= 0.0
	var ring := Color("56c94a") if good else Color("ec5446")
	var r := CHIP * 0.5
	ci.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.18))
	ci.draw_circle(c, r, ring)
	ci.draw_circle(c, r - 3.0, Color(1, 1, 1, 0.96))
	var ic := UI.icon(ml.get("icon", ""))
	if ic:
		var s := r * 1.15
		ci.draw_texture_rect(ic, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	# small +/- badge
	var bc := c + Vector2(r * 0.72, r * 0.72)
	ci.draw_circle(bc, 6.5, ring.darkened(0.15))
	ci.draw_line(bc + Vector2(-3, 0), bc + Vector2(3, 0), Color.WHITE, 1.8)
	if good:
		ci.draw_line(bc + Vector2(0, -3), bc + Vector2(0, 3), Color.WHITE, 1.8)


func _panel_rows() -> int:
	var sel := Game.selected
	if panel_tab == "skills":
		return maxi(1, Game.skills_list(sel).size())
	if panel_tab == "rels":
		return clampi(Game.rel_list(sel).size(), 1, REL_ROWS)
	if panel_tab == "wishes":
		return maxi(1, Game.wishes(sel).size())
	if panel_tab == "career":
		return CAREER_ROWS
	return maxi(1, Game.moodlets(sel).size())


func _panel_hits() -> void:
	for t in TABS:
		_add_hit(panel, Rect2(t[2], 12, TAB_W, 30), "tab", t[0])
	_add_hit(panel, Rect2(PANEL_W - 36, 12, 28, 30), "close")
	if panel_tab == "wishes":
		for k in Game.wishes(Game.selected).size():
			_add_hit(panel, Rect2(8, 56 + k * 44.0, PANEL_W - 16, 44.0), "wish", k)
	if panel_tab == "career" and Game.has_job(Game.selected):
		for k in Careers.TENDENCIES.size():
			_add_hit(panel, _tendency_rect(k), "tendency", Careers.TENDENCIES[k])


func _draw_panel() -> void:
	var sel := Game.selected
	if sel < 0 or sel >= Game.household.size():
		return
	var row_h := 44.0
	var h := 58.0 + _panel_rows() * row_h + 50.0
	if absf(panel.size.y - h) > 0.5:
		panel.size = Vector2(PANEL_W, h)
		_place_panel()
	panel.draw_style_box(_card, Rect2(Vector2.ZERO, panel.size))
	var f := UI.font(800)
	var f7 := UI.font(700)
	# tabs
	for t in TABS:
		var r := Rect2(t[2], 12, TAB_W, 30)
		var on: bool = panel_tab == t[0]
		panel.draw_style_box(_tab_on if on else _tab_off, r)
		panel.draw_string(f, r.position + Vector2(0, 21), t[1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, UI.WHITE if on else UI.INK_SOFT)
	# close x
	var cc := Vector2(PANEL_W - 21, 27)
	panel.draw_circle(cc, 12, Color("eef1f6"))
	panel.draw_line(cc + Vector2(-4.5, -4.5), cc + Vector2(4.5, 4.5), UI.INK_SOFT, 2.0, true)
	panel.draw_line(cc + Vector2(-4.5, 4.5), cc + Vector2(4.5, -4.5), UI.INK_SOFT, 2.0, true)
	var y := 56.0
	var m: Dictionary = Game.household[sel]
	if panel_tab == "mood":
		var mls: Array = Game.moodlets(sel)
		if mls.is_empty():
			panel.draw_string(f7, Vector2(16, y + 26), "No moodlets right now", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.INK_SOFT)
		var now := Game.total_minutes()
		for ml in mls:
			_draw_moodlet_chip(panel, Vector2(30, y + row_h * 0.5), ml)
			panel.draw_string(f, Vector2(54, y + 20), ml.label, HORIZONTAL_ALIGNMENT_LEFT, 170, 14, UI.INK)
			var sub: String = ml.get("desc", "")
			if ml.expires != INF:
				var left := maxf(0.0, ml.expires - now) / 60.0
				var tl := ("%dh left" % ceili(left)) if left >= 1.0 else ("%dm left" % ceili(left * 60.0))
				sub = tl if sub == "" else sub + " · " + tl
			elif sub == "":
				sub = "Until the need is met"
			panel.draw_string(f7, Vector2(54, y + 37), sub, HORIZONTAL_ALIGNMENT_LEFT, 190, 11, UI.INK_SOFT)
			var good: bool = ml.delta >= 0.0
			panel.draw_string(f, Vector2(PANEL_W - 62, y + 28), "%+d" % roundi(ml.delta), HORIZONTAL_ALIGNMENT_RIGHT, 46, 15, Color("3aa532") if good else Color("e04436"))
			y += row_h
		# footer: overall mood + its effect
		var band := Game.mood_band(sel)
		panel.draw_line(Vector2(14, y + 6), Vector2(PANEL_W - 14, y + 6), Color("e3e7ee"), 1.0)
		_draw_mood_face(panel, Vector2(28, y + 28), 11.0, Game.MOOD_COLORS[band], band)
		panel.draw_string(f, Vector2(48, y + 33), "%s  %+d" % [Game.mood_word(sel), roundi(Game.mood(sel))], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.INK)
		panel.draw_string(f7, Vector2(PANEL_W - 170, y + 33), "Skills & pay x%.2f" % Game.mood_mult(sel), HORIZONTAL_ALIGNMENT_RIGHT, 156, 12, UI.INK_SOFT)
	elif panel_tab == "rels":
		_draw_rels(sel, y, row_h)
	elif panel_tab == "wishes":
		_draw_wishes(sel, y, row_h)
	elif panel_tab == "career":
		_draw_career(sel, y, row_h)
	else:
		var sk: Array = Game.skills_list(sel)
		if sk.is_empty():
			panel.draw_string(f7, Vector2(16, y + 26), "%s hasn't learned any skills yet" % m.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK_SOFT)
		for s in sk:
			var ic := UI.icon(s.icon)
			if ic:
				panel.draw_texture_rect(ic, Rect2(16, y + 8, 28, 28), false)
			panel.draw_string(f, Vector2(54, y + 19), s.name, HORIZONTAL_ALIGNMENT_LEFT, 150, 14, UI.INK)
			panel.draw_string(f, Vector2(PANEL_W - 70, y + 19), "Lv %d" % s.level, HORIZONTAL_ALIGNMENT_RIGHT, 56, 13, UI.BLUE_DARK)
			# 10 segments; the next one fills with progress
			var sx := 54.0
			var sw := (PANEL_W - 54.0 - 16.0 - 9 * 3.0) / 10.0
			for k in 10:
				var r := Rect2(sx + k * (sw + 3.0), y + 26, sw, 9)
				var full: bool = k < s.level
				panel.draw_rect(r, UI.GREEN if full else UI.TRACK)
				if k == s.level and s.frac > 0.0:
					panel.draw_rect(Rect2(r.position, Vector2(r.size.x * s.frac, r.size.y)), UI.GREEN.lightened(0.35))
			y += row_h
		panel.draw_line(Vector2(14, y + 6), Vector2(PANEL_W - 14, y + 6), Color("e3e7ee"), 1.0)
		panel.draw_string(f7, Vector2(16, y + 33), "Mood boosts practice: x%.2f" % Game.mood_mult(sel), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.INK_SOFT)


## Relationships tab: everyone this sim knows, family first, with a
## -100..100 friendship bar and the Sims 3 level name.
func _draw_rels(sel: int, y: float, row_h: float) -> void:
	var f := UI.font(800)
	var f7 := UI.font(700)
	var list: Array = Game.rel_list(sel)
	if list.is_empty():
		panel.draw_string(f7, Vector2(16, y + 26), "%s hasn't met anyone yet" % Game.household[sel].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK_SOFT)
	var shown := mini(list.size(), REL_ROWS)
	for k in shown:
		var r: Dictionary = list[k]
		var c := Vector2(30, y + row_h * 0.5)
		var ring: Color = UI.BLUE if r.family else Color("f0a43a")
		panel.draw_circle(c, 16.0, ring)
		panel.draw_circle(c, 13.0, Color(1, 1, 1, 0.96))
		var ic := UI.icon("paw" if r.kind == "dog" else ("people" if not r.family else "smile"))
		if ic:
			panel.draw_texture_rect(ic, Rect2(c - Vector2(10, 10), Vector2(20, 20)), false)
		panel.draw_string(f, Vector2(54, y + 18), r.name, HORIZONTAL_ALIGNMENT_LEFT, 150, 14, UI.INK)
		var tag: String = ("Family · " if r.family else "") + r.level
		panel.draw_string(f7, Vector2(PANEL_W - 176, y + 18), tag, HORIZONTAL_ALIGNMENT_RIGHT, 160, 11, UI.INK_SOFT)
		# centred bar: left half red (dislike), right half green (friendship)
		var bar := Rect2(54, y + 26, PANEL_W - 54 - 16, 9)
		panel.draw_rect(bar, UI.TRACK)
		var mid := bar.position.x + bar.size.x * 0.5
		var v: float = clampf(r.value / 100.0, -1.0, 1.0)
		var wv := bar.size.x * 0.5 * absf(v)
		if v >= 0.0:
			panel.draw_rect(Rect2(mid, bar.position.y, wv, bar.size.y), UI.GREEN)
		else:
			panel.draw_rect(Rect2(mid - wv, bar.position.y, wv, bar.size.y), Color("e5544a"))
		panel.draw_rect(Rect2(mid - 1, bar.position.y - 2, 2, bar.size.y + 4), Color(0.3, 0.35, 0.45, 0.5))
		y += row_h
	panel.draw_line(Vector2(14, y + 6), Vector2(PANEL_W - 14, y + 6), Color("e3e7ee"), 1.0)
	var more := list.size() - shown
	var foot := "Socialize to unlock new interactions" if more <= 0 else "+%d more · socialize to unlock interactions" % more
	panel.draw_string(f7, Vector2(16, y + 33), foot, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 32, 12, UI.INK_SOFT)


## Wishes tab: up to three wishes; tap one to promise it (gold ring, pays
## 1.5x). Footer: lifetime happiness.
func _draw_wishes(sel: int, y: float, row_h: float) -> void:
	var f := UI.font(800)
	var f7 := UI.font(700)
	var list: Array = Game.wishes(sel)
	if list.is_empty():
		panel.draw_string(f7, Vector2(16, y + 26), "%s is content right now" % Game.household[sel].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK_SOFT)
	var gold := Color("f0a43a")
	for w in list:
		var promised: bool = w.get("promised", false)
		var c := Vector2(30, y + row_h * 0.5)
		if promised:
			panel.draw_rect(Rect2(8, y + 2, PANEL_W - 16, row_h - 4), Color(1.0, 0.85, 0.45, 0.25))
		panel.draw_circle(c, 16.0, gold if promised else Color("b8c2d3"))
		panel.draw_circle(c, 13.0, Color(1, 1, 1, 0.96))
		var ic := UI.icon(w.get("icon", "star"))
		if ic:
			panel.draw_texture_rect(ic, Rect2(c - Vector2(10, 10), Vector2(20, 20)), false)
		panel.draw_string(f, Vector2(54, y + 20), w.label, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 54 - 70, 14, UI.INK)
		var sub := "Promised!  x1.5" if promised else "Tap to promise"
		if w.kind == "earn":
			sub = "$%d of $%d" % [int(w.get("have", 0)), int(w.n)] + ("  · promised" if promised else "")
		panel.draw_string(f7, Vector2(54, y + 37), sub, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 54 - 70, 11, gold.darkened(0.2) if promised else UI.INK_SOFT)
		var pts := int(w.get("reward", 0)) * (3 if promised else 2) / 2
		panel.draw_string(f, Vector2(PANEL_W - 76, y + 28), "+%d" % pts, HORIZONTAL_ALIGNMENT_RIGHT, 60, 14, gold.darkened(0.15))
		y += row_h
	panel.draw_line(Vector2(14, y + 6), Vector2(PANEL_W - 14, y + 6), Color("e3e7ee"), 1.0)
	var st := UI.icon("star")
	if st:
		panel.draw_texture_rect(st, Rect2(16, y + 16, 22, 22), false)
	panel.draw_string(f, Vector2(44, y + 33), "Lifetime Happiness  %s" % _thousands(Game.lth(sel)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK)


func _tendency_rect(k: int) -> Rect2:
	var w := (PANEL_W - 32.0 - 2 * 6.0) / 3.0
	return Rect2(16 + k * (w + 6.0), 56 + 3 * 44.0 + 4.0, w, 32)


## Career tab (Sims 3 career panel): job title and level, wage and schedule,
## performance bar, what the next promotion needs, the work tendency
## (Work Hard / Normal / Take It Easy), traits and the household's bills.
func _draw_career(sel: int, y: float, row_h: float) -> void:
	var f := UI.font(800)
	var f7 := UI.font(700)
	var m: Dictionary = Game.household[sel]
	var c: Dictionary = Game.career(sel)
	var school := Careers.is_school(c)
	var gold := Color("f0a43a")
	# --- row 1: title
	var ic := UI.icon(str(Careers.track(c).get("icon", "laptop")) if not c.is_empty() else "laptop")
	panel.draw_circle(Vector2(30, y + row_h * 0.5), 16.0, UI.BLUE if not c.is_empty() else Color("b8c2d3"))
	panel.draw_circle(Vector2(30, y + row_h * 0.5), 13.0, Color(1, 1, 1, 0.96))
	if ic:
		panel.draw_texture_rect(ic, Rect2(Vector2(20, y + row_h * 0.5 - 10), Vector2(20, 20)), false)
	if c.is_empty():
		var who: String = m.name
		if m.get("kind", "") == "dog":
			panel.draw_string(f, Vector2(54, y + 20), "%s is a good dog" % who, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 14, UI.INK)
			panel.draw_string(f7, Vector2(54, y + 37), "No job needed: just walks and belly rubs", HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 11, UI.INK_SOFT)
		else:
			panel.draw_string(f, Vector2(54, y + 20), "Unemployed", HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 14, UI.INK)
			panel.draw_string(f7, Vector2(54, y + 37), "Tap the Computer → Find a Job", HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 11, UI.INK_SOFT)
	else:
		var t: Dictionary = Careers.track(c)
		var head: String = ("School · %s" % Careers.title(c)) if school else "%s · Lv %d %s" % [t.name, int(c.level), Careers.title(c)]
		panel.draw_string(f, Vector2(54, y + 20), head, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 14, UI.INK)
		var sub := Careers.schedule_text(c)
		if not school:
			sub = "$%d/h · %s" % [Careers.wage(c), sub]
		panel.draw_string(f7, Vector2(54, y + 37), sub, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 70, 11, UI.INK_SOFT)
	y += row_h
	# --- row 2: performance / grade bar
	if not c.is_empty():
		var perf: float = float(c.get("perf", 0.0))
		var label := ("Grade %s" % Careers.grade(perf)) if school else "Performance"
		panel.draw_string(f, Vector2(16, y + 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.INK)
		var tr: float = float(c.get("trend", 0.0))
		if int(c.get("shifts", 0)) > 0:
			var tc := Color("3aa532") if tr >= 0.0 else Color("e04436")
			panel.draw_string(f, Vector2(PANEL_W - 116, y + 18), ("▲ %+d" if tr >= 0.0 else "▼ %+d") % roundi(tr), HORIZONTAL_ALIGNMENT_RIGHT, 100, 12, tc)
		var bar := Rect2(16, y + 26, PANEL_W - 32, 11)
		panel.draw_rect(bar, UI.TRACK)
		var pc := Color("e5544a") if perf < 25.0 else (Color("f2c230") if perf < 60.0 else UI.GREEN)
		panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(perf / 100.0, 0.0, 1.0), bar.size.y)), pc)
		# promotion mark at the end of the bar + the number
		panel.draw_rect(Rect2(bar.end.x - 2, bar.position.y - 3, 2, bar.size.y + 6), gold)
		panel.draw_string(f, Vector2(110, y + 18), "%d / 100" % roundi(perf), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.INK_SOFT)
	else:
		panel.draw_string(f7, Vector2(16, y + 26), "Jobs: Business · Freelance · Culinary · Journalism · Music", HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 32, 12, UI.INK_SOFT)
	y += row_h
	# --- row 3: status + next promotion
	var status := ""
	if Game.is_at_work(sel):
		var w: Dictionary = m.work
		status = "%s until %s" % ["At school" if school else "At work", Game.when_text(float(w.until)).substr(5)]
	elif not c.is_empty():
		var ns := Game.next_shift(sel)
		if ns >= 0.0:
			status = "Next %s: %s" % ["school day" if school else "shift", Game.when_text(ns)]
	var need := ""
	if not c.is_empty() and not school:
		var req := Careers.next_req(c)
		var sk: String = Careers.track(c).get("skill", "")
		var nxt := c.duplicate()
		nxt.level = int(c.level) + 1
		if req < 0:
			need = "Top of the career!"
		elif req > 0:
			var have := int(Game.skill_level(sel, sk))
			need = "Next: %s · needs %s %d (has %d)" % [Careers.title(nxt), sk, req, have]
		else:
			need = "Next: %s · $%d/h" % [Careers.title(nxt), Careers.wage(nxt)]
	elif school:
		need = "Homework done today ✓" if int(m.get("homework_day", -10)) >= Game.day else "Do homework to raise the grade"
	panel.draw_string(f, Vector2(16, y + 18), status, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 32, 13, UI.INK)
	panel.draw_string(f7, Vector2(16, y + 36), need, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 32, 12, UI.INK_SOFT)
	y += row_h
	# --- row 4: work tendency (adults with a job)
	if Game.has_job(sel):
		var cur: String = c.get("tendency", "normal")
		for k in Careers.TENDENCIES.size():
			var tk: String = Careers.TENDENCIES[k]
			var r := _tendency_rect(k)
			panel.draw_style_box(_tab_on if tk == cur else _tab_off, r)
			panel.draw_string(f, r.position + Vector2(0, 21), Careers.TENDENCY_LABEL[tk], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, UI.WHITE if tk == cur else UI.INK_SOFT)
	y += row_h
	# --- row 5: traits (chips, wrapping onto a second line)
	var tx := 16.0
	var ty := y + 1.0
	panel.draw_string(f7, Vector2(tx, ty + 15), "Traits", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.INK_SOFT)
	tx += 46.0
	for tn in Traits.of(m):
		var tw := f.get_string_size(tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var r := Rect2(tx, ty, tw + 28, 20)
		if r.end.x > PANEL_W - 10:
			tx = 62.0
			ty += 22.0
			r.position = Vector2(tx, ty)
		panel.draw_style_box(_tab_off, r)
		var ti := UI.icon(Traits.icon(tn))
		if ti:
			panel.draw_texture_rect(ti, Rect2(r.position + Vector2(4, 2), Vector2(16, 16)), false)
		panel.draw_string(f, r.position + Vector2(23, 14.5), tn, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.INK)
		tx = r.end.x + 5.0
	y += row_h
	# --- footer: household bills
	panel.draw_line(Vector2(14, y + 6), Vector2(PANEL_W - 14, y + 6), Color("e3e7ee"), 1.0)
	var bi := UI.icon("bill")
	if bi:
		panel.draw_texture_rect(bi, Rect2(16, y + 16, 22, 22), false)
	var nd := maxi(1, ceili((Game.next_bill_at - Game.total_minutes()) / 1440.0))
	var bt := ("No bills due · next in %d day%s" % [nd, "" if nd == 1 else "s"]) if not Game.has_bills() else \
		("Bills $%d OVERDUE · pay at the mailbox" % Game.bills_due_total() if Game.bills_overdue() else "Bills $%d due %s" % [Game.bills_due_total(), Game.when_text(Game.bills_due_at()).get_slice(" ", 0)])
	panel.draw_string(f, Vector2(44, y + 33), bt, HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 60, 13, Color("e04436") if Game.bills_overdue() else UI.INK)


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


func _draw_toasts() -> void:
	if _toast_list.is_empty():
		return
	var f := UI.font(800)
	# Top centre, between the portraits and the clock; newest lowest.
	var cx := toasts.size.x * 0.5
	var y := 22.0
	for t in _toast_list:
		var a := clampf(t.t / 0.4, 0.0, 1.0) * clampf((TOAST_TTL - t.t) / 0.15 + 0.2, 0.0, 1.0)
		var tw := f.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var w := tw + 58.0
		var r := Rect2(cx - w * 0.5, y, w, 38)
		var sb := _card
		toasts.draw_set_transform(Vector2.ZERO)
		toasts.draw_style_box(sb, r)
		var ic := UI.icon(t.icon)
		if ic:
			toasts.draw_texture_rect(ic, Rect2(r.position + Vector2(10, 7), Vector2(24, 24)), false, Color(1, 1, 1, a))
		toasts.draw_string(f, r.position + Vector2(42, 25), t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UI.INK, a))
		y += 44.0
