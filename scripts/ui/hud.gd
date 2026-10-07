extends CanvasLayer
## The Vims HUD (added by main.gd). Layout matches the reference shots at the
## 1672x941 design size; the project stretches canvas items so it scales with
## the viewport, and on phones the whole HUD gets an extra size bump.
##
##   top-left     household portrait cards (live voxel heads) + need bars
##   top-right    clock card (icon, day/time, season, pause/play/fast) + Tasks
##   bottom-left  Build / Buy / Decorate / Manage
##   bottom-right money
##   world        action / speech / emote bubbles, skill chips, plumbob
##   popup        object action menu (Game.menu_requested)
##
## Public API (besides Game signals):
##   apply_preset(preset_name, preset_dict)   stage a screenshot
##   show_bubble(anchor, data) / clear_bubbles()
##   open_menu(title, actions, screen_pos)
##   find_actor(key) -> Node3D               resolves a household/NPC actor

signal action_chosen(title: String, action: Dictionary)

const UI := preload("res://scripts/ui/ui_kit.gd")
const Portrait := preload("res://scripts/ui/portrait.gd")
const NeedPanel := preload("res://scripts/ui/need_panel.gd")
const ClockPanel := preload("res://scripts/ui/clock_panel.gd")
const TasksPanel := preload("res://scripts/ui/tasks_panel.gd")
const ModeBar := preload("res://scripts/ui/mode_bar.gd")
const MoneyPill := preload("res://scripts/ui/money_pill.gd")
const WorldBubble := preload("res://scripts/ui/world_bubble.gd")
const Plumbob := preload("res://scripts/ui/plumbob.gd")
const ActionMenu := preload("res://scripts/ui/action_menu.gd")
const HudPresets := preload("res://scripts/ui/hud_presets.gd")

var ui_scale := 1.0
var root: Control
var household_box: Control
var clock: Control
var tasks: Control
var modes: Control
var money: Control
var bubble_layer: Control
var plumbob: Control
var menu: Control
var side_list: Control

var _portraits: Array = []
var _needs: Array = []
## key -> bubble. key = "<anchor id or screen>|main" or "|skill"
var _bubbles := {}
var _actor_cache := {}
var _actor_cache_loc: Object
var _cam: Camera3D
## Screen area of the household column; world bubbles are nudged off it.
var _household_rect := Rect2()


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	bubble_layer = Control.new()
	bubble_layer.name = "Bubbles"
	bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bubble_layer)
	plumbob = Plumbob.new()
	plumbob.name = "Plumbob"
	plumbob.z_index = 1
	bubble_layer.add_child(plumbob)

	household_box = Control.new()
	household_box.name = "Household"
	household_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	household_box.position = Vector2(22, 27)
	root.add_child(household_box)

	clock = ClockPanel.new()
	clock.name = "Clock"
	root.add_child(clock)

	tasks = TasksPanel.new()
	tasks.name = "Tasks"
	tasks.custom_minimum_size = Vector2(237, 0)
	root.add_child(tasks)

	side_list = TasksPanel.new()
	side_list.name = "SideList"
	side_list.bind_game = false
	side_list.custom_minimum_size = Vector2(272, 0)
	side_list.visible = false
	root.add_child(side_list)

	modes = ModeBar.new()
	modes.name = "Modes"
	root.add_child(modes)

	money = MoneyPill.new()
	money.name = "Money"
	root.add_child(money)

	menu = ActionMenu.new()
	menu.name = "ActionMenu"
	root.add_child(menu)
	menu.chosen.connect(_on_menu_chosen)

	Game.household_changed.connect(_rebuild_household)
	Game.selected_changed.connect(func(_i): _layout_household())
	Game.time_changed.connect(_on_time)
	Game.bubble_requested.connect(show_bubble)
	Game.bubble_cleared.connect(_on_bubble_cleared)
	Game.menu_requested.connect(open_menu)
	Game.location_changed.connect(func(_l): _actor_cache.clear())
	get_viewport().size_changed.connect(_layout)
	_rebuild_household()
	_layout()


# --------------------------------------------------------------- layout

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	ui_scale = 1.0
	if OS.has_feature("mobile") or (DisplayServer.is_touchscreen_available() and DisplayServer.screen_get_size().y < 900):
		ui_scale = 1.12
	scale = Vector2(ui_scale, ui_scale)
	var s := vs / ui_scale
	root.size = s
	bubble_layer.size = s
	clock.position = Vector2(s.x - clock.size.x - 22.0, 22.0)
	tasks.position = Vector2(s.x - 237.0 - 22.0, clock.position.y + clock.size.y + 20.0)
	var compact := side_list.visible
	modes.position = Vector2(26.0, s.y - modes.size.y - (31.0 if compact else 42.0))
	if compact:
		side_list.position = Vector2(18.0, modes.position.y - side_list.size.y - 9.0)
	money.position = Vector2(s.x - money.size.x - 26.0, s.y - money.size.y - 41.0)


func _rebuild_household() -> void:
	for c in household_box.get_children():
		c.queue_free()
	_portraits.clear()
	_needs.clear()
	for i in Game.household.size():
		var m: Dictionary = Game.household[i]
		var np := NeedPanel.new()
		np.setup(m)
		household_box.add_child(np)
		_needs.append(np)
		var p := Portrait.new()
		p.setup(i, m, i == Game.selected, Vector2(100, 100))
		p.tapped.connect(_on_portrait_tapped.bind(i))
		household_box.add_child(p)
		_portraits.append(p)
	_layout_household()


func _layout_household() -> void:
	# Compact spacing when a side list (ref5 shopping list) shares the column.
	var compact := side_list != null and side_list.visible
	var y := 0.0
	for i in _portraits.size():
		var m: Dictionary = Game.household[i]
		var sel := i == Game.selected
		var np = _needs[i]
		np.row_h = 23.0 if compact else 25.5
		var ph: float = np.preferred_height()
		var dog: bool = m.get("kind", "") == "dog"
		var cw := 113.0 if sel else 100.0
		var ch: float
		if sel:
			ch = 136.0 if compact else 146.0
		else:
			ch = (84.0 if compact else 92.0) if dog else maxf(92.0 if compact else 110.0, ph)
		var p = _portraits[i]
		p.setup(i, m, sel, Vector2(cw, ch))
		p.position = Vector2(0, y)
		var py := y + (8.0 if compact else (12.0 if sel else 8.0))
		np.position = Vector2(cw + 2.0, py)
		np.custom_minimum_size = Vector2.ZERO
		np.size = Vector2(176.0 if sel else 172.0, ph)
		np.queue_redraw()
		y = maxf(y + ch, py + ph) + (8.0 if compact else (12.0 if sel else 10.0))
	_household_rect = Rect2(household_box.position, Vector2(cw_max(), y))


func cw_max() -> float:
	var w := 0.0
	for np in _needs:
		w = maxf(w, np.position.x + np.size.x)
	return w


func _on_portrait_tapped(i: int) -> void:
	Game.selected = i


func _on_time(_d: int, _m: float) -> void:
	for np in _needs:
		np.refresh()


# --------------------------------------------------------------- world bubbles

func show_bubble(anchor: Node3D, data: Dictionary) -> void:
	var slot := "skill" if data.get("kind", "action") == "skill" else "main"
	var base: String
	if anchor:
		base = str(anchor.get_instance_id())
	else:
		base = "screen:%s:%s:%s:%s" % [data.get("who", ""), data.get("id", ""), data.get("text", ""), str(data.get("at", data.get("screen_pos", "")))]
	var key := base + "|" + slot
	var b = _bubbles.get(key)
	if b == null or not is_instance_valid(b):
		b = WorldBubble.new()
		bubble_layer.add_child(b)
		_bubbles[key] = b
	b.anchor = anchor
	b.id = str(data.get("id", ""))
	b.configure(data)
	b.fallback_screen = data.get("screen_pos", null)
	b.fallback_at = data.get("at", null)
	b.selected_side = data.get("selected_side", false)
	b.offset = data.get("offset", Vector2.ZERO)
	_position_bubble(b)


func _on_bubble_cleared(anchor: Node3D, id: String) -> void:
	for key in _bubbles.keys():
		var b = _bubbles[key]
		if not is_instance_valid(b):
			_bubbles.erase(key)
			continue
		if b.anchor == anchor and (id == "" or b.id == id):
			b.queue_free()
			_bubbles.erase(key)


func clear_bubbles() -> void:
	for key in _bubbles:
		if is_instance_valid(_bubbles[key]):
			_bubbles[key].queue_free()
	_bubbles.clear()


func _anchor_point(a: Node3D) -> Vector3:
	if a.has_method("head_top"):
		return a.head_top()
	return a.global_position + Vector3(0, 1.9, 0)


## Screen point (HUD units) of a world point, or Vector2.INF when off-screen.
func _project(p: Vector3) -> Vector2:
	if _cam == null or not is_instance_valid(_cam) or not _cam.current:
		_cam = get_viewport().get_camera_3d()
	if _cam == null or _cam.is_position_behind(p):
		return Vector2.INF
	return _cam.unproject_position(p) / ui_scale


func _is_selected_actor(a: Node3D) -> bool:
	return a != null and a == _selected_actor()


## Screen gap (px) between the top of a sim's head and the tip of its
## bubble's tail; scales a little with head size so far sims stay snug.
const MIN_GAP := 5.0
const MAX_GAP := 12.0
## Top of the area bubbles may use (below the screen edge).
const SAFE_TOP := 12.0
const BUBBLE_PAD := 14.0
## Plumbob slot beside the selected sim's bubble (ref1: right of "Work").
const PB_W := 40.0
const PB_H := 70.0
## Candidate tail positions (fraction of bubble width) and extra lifts; the
## layout picks the cheapest combination per bubble (greedy, selected first).
const FRACS: Array[float] = [0.5, 0.38, 0.62, 0.26, 0.74, 0.16, 0.84]
const LIFTS: Array[float] = [0.0, 22.0, 46.0, 76.0, 110.0]
## Hard obstacle weight per px² of overlap, soft (background NPC heads).
const W_HARD := 12.0
const W_SOFT := 0.35
## Base cost of hanging a bubble beside the head instead of above it.
const SIDE_COST := 9000.0
const _SIDE_DY: Array[float] = [0.0, -30.0, 30.0]

## Per-frame scratch (reused, no allocations in the steady state).
var _heads: Array[Rect2] = []
var _head_actors: Array = []
var _mains: Array = []
var _chips: Array = []
var _hud_rects: Array[Rect2] = []
var _placed: Array[Rect2] = []
var _scene_actors: Array = []
var _head_hard: Array[bool] = []
var _n_hard := 0
var _scan_loc: Node
var _scan_t := 0.0
var _sel_actor: Node3D
var _sort_mains := func(p, q) -> bool:
	var ps: bool = p.anchor != null and p.anchor == _sel_actor
	var qs: bool = q.anchor != null and q.anchor == _sel_actor
	if ps != qs:
		return ps
	return p.tip.y < q.tip.y


## Head point + head height in pixels (z), used to scale gaps/rects.
func _head_metrics(a: Node3D) -> Vector3:
	var hp := _anchor_point(a)
	var h := _project(hp)
	if h == Vector2.INF:
		return Vector3.INF
	# Head height in pixels: from the head bone (neck) up to the anchor when
	# the actor exposes its skeleton, else a 0.5 m estimate.
	var lo := Vector2.INF
	var sk = a.get("skeleton")
	var bh = a.get("b_head")
	if sk is Skeleton3D and bh is int and bh >= 0 and sk.is_inside_tree():
		lo = _project((sk.global_transform * sk.get_bone_global_pose(bh)).origin)
	if lo == Vector2.INF or lo.y - h.y < 12.0:
		lo = _project(hp - Vector3(0, 0.5, 0))
	var dy := 60.0 if lo == Vector2.INF else clampf(lo.y - h.y, 18.0, 220.0)
	return Vector3(h.x, h.y, dy)


func _gap_for(dy: float) -> float:
	return clampf(dy * 0.16, MIN_GAP, MAX_GAP)


## Anchor point for one bubble: `head` (projected head top) and the base tail
## tip straight above it. The layout pass then picks the body position.
func _position_bubble(b) -> void:
	var tip := Vector2.INF
	var a: Node3D = b.anchor
	b.head = Vector2.INF
	if a != null and is_instance_valid(a) and a.is_inside_tree():
		var hm := _head_metrics(a)
		if hm != Vector3.INF:
			var head := Vector2(hm.x, hm.y)
			b.head = head
			b.head_px = hm.z
			tip = head + Vector2(0, -_gap_for(hm.z)) + b.offset
			b.base_tip = tip
	else:
		var at = b.fallback_at
		var sp = b.fallback_screen
		if at is Vector2:
			b.target = at
			tip = at + Vector2(b.size.x * b.base_tail_frac, b.size.y + WorldBubble.TAIL_H)
		elif sp is Vector2:
			tip = sp
			b.target = sp - Vector2(b.size.x * b.base_tail_frac, b.size.y + WorldBubble.TAIL_H)
	b.visible = tip != Vector2.INF
	if b.visible:
		b.tip = tip


func _collect_hud_rects() -> void:
	_hud_rects.clear()
	if _household_rect.size.x > 0.0:
		_hud_rects.append(_household_rect.grow(10.0))
	for c in [clock, tasks, modes, money, side_list]:
		if c != null and c.visible:
			_hud_rects.append(Rect2(c.position, c.size).grow(10.0))
	if menu != null and menu.visible:
		_hud_rects.append(Rect2(menu.position, menu.size).grow(8.0))


## Screen rects around every visible sim's head; bubbles and chips keep off.
func _collect_heads() -> void:
	_heads.clear()
	_head_actors.clear()
	for m in Game.household:
		var a := find_actor(m.get("name", ""))
		if a != null and not _head_actors.has(a):
			_head_actors.append(a)
	for key in _bubbles:
		var b = _bubbles[key]
		if is_instance_valid(b) and b.anchor != null and is_instance_valid(b.anchor) and not _head_actors.has(b.anchor):
			_head_actors.append(b.anchor)
	_n_hard = _head_actors.size()
	# every other sim in the location (NPCs, shoppers, guests), rescanned now and then
	_scan_t -= get_process_delta_time()
	var loc := _location()
	if loc != _scan_loc or _scan_t <= 0.0:
		_scan_loc = loc
		_scan_t = 2.5
		_scene_actors.clear()
		if loc != null:
			for n in loc.find_children("*", "Node3D", true, false):
				if n is SimActor:
					_scene_actors.append(n)
	for a in _scene_actors:
		if is_instance_valid(a) and not _head_actors.has(a):
			_head_actors.append(a)
	_head_hard.clear()
	for i in _head_actors.size():
		var a = _head_actors[i]
		if not is_instance_valid(a) or not a.is_inside_tree() or not a.is_visible_in_tree():
			continue
		var hm := _head_metrics(a)
		if hm == Vector3.INF:
			continue
		# the face: from just above the head top down to the chin (+ a bit)
		var w := maxf(hm.z * 0.95, 34.0)
		_heads.append(Rect2(hm.x - w * 0.5, hm.y - 4.0, w, hm.z * 1.15 + 4.0))
		# household + bubble owners are hard obstacles; extras are soft
		_head_hard.append(i < _n_hard)


static func _ov(a: Rect2, b: Rect2) -> float:
	var x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return x * y if (x > 0.0 and y > 0.0) else 0.0


## Cost of covering `r` on screen: overlap with placed bubbles/chips/plumbob,
## faces, HUD cards, and leaving the safe area.
func _cost(r: Rect2, vs: Vector2) -> float:
	var c := 0.0
	var g := r.grow(BUBBLE_PAD * 0.5)
	for pr in _placed:
		c += _ov(g, pr) * W_HARD
	for i in _heads.size():
		c += _ov(r, _heads[i]) * (W_HARD if _head_hard[i] else W_SOFT)
	for hr in _hud_rects:
		c += _ov(r, hr) * W_HARD
	var out := maxf(0.0, SAFE_TOP - r.position.y) + maxf(0.0, 8.0 - r.position.x) \
		+ maxf(0.0, r.end.x - (vs.x - 8.0)) + maxf(0.0, r.end.y - (vs.y - 8.0))
	c += out * r.size.x * W_HARD
	return c


## Screen-space layout: every bubble floats straight above its own sim with
## the tail tip just over the head; per bubble we try a few tail positions
## and lifts and keep the cheapest, so bubbles, chips, the plumbob, faces
## and HUD cards never touch. Chips go beside their bubble.
func _resolve_layout() -> void:
	_sel_actor = _selected_actor()
	_mains.clear()
	_chips.clear()
	for key in _bubbles:
		var b = _bubbles[key]
		if is_instance_valid(b) and b.visible:
			if b.kind == "skill":
				_chips.append(b)
			else:
				_mains.append(b)
	_collect_heads()
	_collect_hud_rects()
	_placed.clear()
	var vs: Vector2 = root.size
	_mains.sort_custom(_sort_mains)
	for b in _mains:
		_place_main(b, vs)
	for ch in _chips:
		_place_chip(ch, vs)
	for b in _mains:
		_apply(b)
	for ch in _chips:
		_apply(ch)


func _place_main(b, vs: Vector2) -> void:
	b.plumb_side = 0
	b.pb_rect = Rect2()
	if b.head == Vector2.INF:
		_placed.append(Rect2(b.target, b.size + Vector2(0, WorldBubble.TAIL_H)))
		return
	var sel: bool = _sel_actor != null and b.anchor == _sel_actor
	var full: Vector2 = b.size + Vector2(0, WorldBubble.TAIL_H)
	if sel and _place_selected(b, vs, full):
		return
	var best := INF
	var best_pos := Vector2.ZERO
	var best_lift := 0.0
	var best_side := 0
	var pref := 0.5
	if sel or b.selected_side:
		pref = 0.62   # bubble leans left, plumbob slot on the right (ref1)
	for li in LIFTS.size():
		var lift: float = LIFTS[li]
		# lifting costs about as much as a 12 px² face overlap per px
		var base_c := lift * lift * 0.9 + lift * 30.0
		if base_c >= best:
			break
		for fr in FRACS:
			var pos := Vector2(b.base_tip.x - b.size.x * fr, b.base_tip.y - lift - full.y)
			var r := Rect2(pos, full)
			var c := base_c + absf(fr - pref) * 900.0 + _cost(r, vs)
			var side := 0
			if sel:
				# plumbob slot right (preferred) or left of the bubble
				var pr := _pb_rect(pos, b.size, 1)
				var pl := _pb_rect(pos, b.size, -1)
				var cr := _cost(pr, vs)
				var cl := _cost(pl, vs) + 400.0
				side = 1 if cr <= cl else -1
				c += minf(cr, cl)
			if c < best:
				best = c
				best_pos = pos
				best_lift = lift
				best_side = side
	var best_tip: Vector2 = b.base_tip - Vector2(0, best_lift)
	if best > SIDE_COST:
		# no room above (head near the top edge / crowded): try beside the
		# head, body level with the face, tail reaching in toward the head
		var hw: float = maxf(b.head_px * 0.5, 18.0)
		for dir in [1.0, -1.0]:
			for dy in _SIDE_DY:
				var x: float = b.head.x + hw + 10.0 if dir > 0.0 else b.head.x - hw - 10.0 - b.size.x
				var pos := Vector2(x, b.head.y + dy - b.size.y * 0.5)
				var r := Rect2(pos, full)
				var c: float = SIDE_COST + absf(dy) * 20.0 + _cost(r, vs)
				var side := 0
				if sel:
					var pr := _pb_rect(pos, b.size, int(dir))
					c += _cost(pr, vs)
					side = int(dir)
				if c < best:
					best = c
					best_pos = pos
					best_side = side
					best_tip = Vector2(b.head.x + dir * hw * 0.6, b.head.y + 6.0)
	b.target = best_pos
	b.tip = best_tip
	b.plumb_side = best_side
	_placed.append(Rect2(best_pos, full))
	if best_side != 0:
		_placed.append(_pb_rect(best_pos, b.size, best_side))


const _SEL_SIDES: Array[int] = [-1, 1]
const _SEL_LIFTS: Array[float] = [0.0, 16.0, 34.0, 56.0]
const _SEL_DX: Array[float] = [0.0, 14.0, 30.0]


## Selected sim (ref1 "Work" + gem): the plumbob floats straight over the
## head with its own clear space, and the action bubble hangs beside the gem
## (left preferred) with its tail dipping toward the head. Returns false when
## neither side fits so the generic layout takes over.
func _place_selected(b, vs: Vector2, full: Vector2) -> bool:
	var gap := _gap_for(b.head_px)
	var h: float = PB_H * plumbob.gem_scale
	var pbr := Rect2(b.head.x - PB_W * 0.5, b.head.y - gap * 0.6 - h, PB_W, h)
	if pbr.position.y < SAFE_TOP:
		return false
	var pc := _cost(pbr, vs)
	var best := INF
	var best_pos := Vector2.ZERO
	var best_side := 0
	for side in _SEL_SIDES:
		for lift in _SEL_LIFTS:
			for dx in _SEL_DX:
				var x: float = pbr.position.x - 14.0 - dx - b.size.x if side < 0 else pbr.end.x + 14.0 + dx
				# bubble body roughly level with the gem, tail bottom near
				# the gem's lower half
				var y: float = pbr.end.y - full.y - 6.0 - lift
				var r := Rect2(Vector2(x, y), full)
				var c: float = _cost(r, vs) + lift * 8.0 + dx * 6.0 + (0.0 if side < 0 else 300.0)
				if c < best:
					best = c
					best_pos = r.position
					best_side = side
	if best + pc > 4000.0:
		return false
	b.target = best_pos
	var tx: float = best_pos.x + b.size.x - 22.0 if best_side < 0 else best_pos.x + 22.0
	b.tip = Vector2(lerpf(tx, b.head.x, 0.5), best_pos.y + full.y)
	b.plumb_side = best_side
	b.pb_rect = pbr
	_placed.append(Rect2(best_pos, full))
	_placed.append(pbr.grow(6.0))
	return true


## Plumbob slot beside a bubble at `pos`: level with the bubble, bottom a bit
## below the body like the gem in ref1.
func _pb_rect(pos: Vector2, sz: Vector2, side: int) -> Rect2:
	var h: float = PB_H * plumbob.gem_scale
	var y: float = pos.y + sz.y - 2.0 - h
	var x: float = pos.x + sz.x + 4.0 if side > 0 else pos.x - PB_W - 4.0
	return Rect2(x, y - 4.0, PB_W, h + 8.0)


const _CHIP_DX: Array[float] = [0.0, 30.0, -30.0, 60.0]
const _CHIP_SLOTS: Array[Vector3] = [
	# (fx of bubble width, fy: 1 below / 0 middle / -1 above, extra cost)
	Vector3(0.6, 1.0, 0.0), Vector3(0.35, 1.0, 120.0), Vector3(1.0, 0.0, 200.0),
	Vector3(0.75, 1.0, 160.0), Vector3(0.6, -1.0, 500.0), Vector3(-1.0, 0.0, 600.0),
	Vector3(0.0, 1.0, 400.0), Vector3(0.6, 2.0, 900.0), Vector3(1.0, 1.0, 300.0),
]


## Skill chip ("+ Creativity"): just below-right of its own bubble (ref1),
## else beside it, never on a face, bubble or HUD card.
func _place_chip(ch, vs: Vector2) -> void:
	var mb = _main_bubble_for(ch.anchor) if ch.anchor != null and is_instance_valid(ch.anchor) else null
	var origin := Rect2()
	if mb != null:
		origin = Rect2(mb.target, mb.size)
	elif ch.head != Vector2.INF:
		# no action bubble: hang beside the head
		origin = Rect2(ch.head + Vector2(-ch.size.x * 0.5, -ch.size.y - 40.0), Vector2(ch.size.x, ch.size.y + 10.0))
	else:
		_placed.append(Rect2(ch.target, ch.size))
		ch.tip = ch.target + Vector2(4.0, ch.size.y + 9.0)
		return
	var best := INF
	var best_pos: Vector2 = ch.target
	for s in _CHIP_SLOTS:
		var pos := Vector2.ZERO
		if s.x >= 1.0:
			pos.x = origin.end.x + 8.0
		elif s.x <= -1.0:
			pos.x = origin.position.x - ch.size.x - 8.0
		else:
			pos.x = origin.position.x + origin.size.x * s.x
		if s.y >= 2.0:
			pos.y = origin.end.y + 12.0 + ch.size.y + 8.0
		elif s.y >= 1.0:
			pos.y = origin.end.y + 12.0
		elif s.y <= -1.0:
			pos.y = origin.position.y - ch.size.y - 8.0
		else:
			pos.y = origin.position.y + (origin.size.y - ch.size.y) * 0.5
		for dx in _CHIP_DX:
			var p2 := pos + Vector2(dx, 0)
			var c: float = s.z + absf(dx) * 4.0 + _cost(Rect2(p2, ch.size + Vector2(0, 9)), vs)
			if c < best:
				best = c
				best_pos = p2
	ch.target = best_pos
	ch.tip = best_pos + Vector2(4.0, ch.size.y + 9.0)
	_placed.append(Rect2(best_pos, ch.size + Vector2(0, 9)))


## Nudge a bubble off the HUD cards and inside the screen (fallback bubbles).
func _keep_off_hud(b, vs: Vector2) -> void:
	for hr in _hud_rects:
		var r := Rect2(b.target, b.size)
		if not hr.intersects(r):
			continue
		var to_right: float = hr.end.x - r.position.x
		var to_left: float = r.end.x - hr.position.x
		if to_right < to_left:
			b.target.x += to_right
		else:
			b.target.x -= to_left
	b.target.x = clampf(b.target.x, 8.0, maxf(8.0, vs.x - b.size.x - 8.0))
	b.target.y = clampf(b.target.y, 8.0, maxf(8.0, vs.y - b.size.y - 8.0))


func _apply(b) -> void:
	var t: Vector2 = b.target.round()
	if b.placed and not Game.frozen:
		var k := 1.0 - exp(-14.0 * get_process_delta_time())
		b.position = b.position.lerp(t, k)
		if b.position.distance_squared_to(t) < 0.25:
			b.position = t
	else:
		b.position = t
		b.placed = true
	b.queue_redraw()


# --------------------------------------------------------------- actors

func _location() -> Node:
	var p := get_parent()
	if p == null:
		return null
	var loc = p.get("location")
	return loc if loc is Node and is_instance_valid(loc) else null


## Resolve an actor by household name ("Jack"), look ("dad") or NPC key.
## Uses location.get_actor(key) when the location provides it, otherwise
## scans the location once for SimActor-like nodes (have head_top + look).
func find_actor(key: String) -> Node3D:
	var loc := _location()
	if loc == null or key == "":
		return null
	if _actor_cache_loc != loc:
		_actor_cache.clear()
		_actor_cache_loc = loc
	var hit = _actor_cache.get(key)
	if hit != null and is_instance_valid(hit) and hit.is_inside_tree():
		return hit
	var found: Node3D = null
	var keys := [key]
	for m in Game.household:
		if m.get("name", "") == key:
			keys.append(m.get("look", ""))
	if loc.has_method("get_actor"):
		for k in keys:
			var a = loc.get_actor(k)
			if a is Node3D:
				found = a
				break
	if found == null:
		for n in loc.find_children("*", "Node3D", true, false):
			if n.get_script() == null or not n.has_method("head_top"):
				continue
			var look = n.get("look")
			if n.name in keys or (look is String and look in keys):
				found = n
				break
	if found:
		_actor_cache[key] = found
	return found


func _selected_actor() -> Node3D:
	if Game.selected < 0 or Game.selected >= Game.household.size():
		return null
	return find_actor(Game.household[Game.selected].get("name", ""))


# --------------------------------------------------------------- side list

## Location checklist on the left (ref5 "Shopping List"). items: [{title, icon, done, count}]
func show_side_list(title: String, icon_name: String, items: Array) -> void:
	if side_list.title != title or side_list.title_icon != icon_name:
		var fresh := TasksPanel.new()
		fresh.name = "SideList"
		fresh.bind_game = false
		fresh.title = title
		fresh.title_icon = icon_name
		fresh.custom_minimum_size = Vector2(272, 0)
		side_list.queue_free()
		side_list = fresh
		root.add_child(side_list)
		root.move_child(side_list, modes.get_index())
	side_list.set_items(items)
	side_list.visible = true
	side_list.reset_size()
	_layout_household()
	_layout.call_deferred()


func hide_side_list() -> void:
	side_list.visible = false
	_layout_household()
	_layout()


# --------------------------------------------------------------- menu

func open_menu(title: String, actions: Array, screen_pos: Vector2) -> void:
	menu.open(title, actions, screen_pos / ui_scale)


func _on_menu_chosen(title: String, action: Dictionary) -> void:
	action_chosen.emit(title, action)
	if Game.has_signal("action_chosen"):
		Game.emit_signal("action_chosen", title, action)


# --------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	for key in _bubbles.keys():
		var b = _bubbles[key]
		if not is_instance_valid(b):
			_bubbles.erase(key)
			continue
		if not b.tick(delta):
			b.queue_free()
			_bubbles.erase(key)
			continue
		_position_bubble(b)
	_resolve_layout()
	_update_plumbob()
	if _dbg_frames >= 0:
		_dbg_frames += 1
		if _dbg_frames == 15:
			for m in Game.household:
				var a := find_actor(m.name)
				if a:
					print("HUDDBG ", m.name, " head ", _project(_anchor_point(a)), " feet ", _project(a.global_position))
				else:
					print("HUDDBG ", m.name, " no actor")
			for k in _bubbles:
				var bb = _bubbles[k]
				if is_instance_valid(bb):
					print("HUDDBG bubble ", bb.text, " rect ", Rect2(bb.position, bb.size), " tip ", bb.tip)
			print("HUDDBG heads ", _heads, " plumbob ", plumbob.tip)


var _dbg_frames := 0 if OS.get_environment("HUD_DEBUG") != "" else -1
var plumbob_fallback := Vector2.INF


func _update_plumbob() -> void:
	var a := _selected_actor()
	var tip := Vector2.INF
	if a:
		var hm := _head_metrics(a)
		if hm != Vector3.INF:
			# no bubble: float the gem in the gap over the head
			tip = Vector2(hm.x, hm.y - 8.0)
			var b = _main_bubble_for(a)
			if b != null and b.plumb_side != 0:
				var r: Rect2 = b.pb_rect if b.pb_rect.size.x > 0.0 else _pb_rect(b.target, b.size, b.plumb_side)
				tip = Vector2(r.get_center().x, r.end.y)
			elif b != null:
				tip = Vector2(b.tip.x, b.target.y - 4.0)
	else:
		tip = plumbob_fallback
	plumbob.active = tip != Vector2.INF
	plumbob.tip = tip if plumbob.active else Vector2.ZERO


func _main_bubble_for(a: Node3D):
	var b = _bubbles.get(str(a.get_instance_id()) + "|main")
	if b != null and is_instance_valid(b) and b.visible:
		return b
	return null


# --------------------------------------------------------------- presets

func apply_preset(preset_name: String, p: Dictionary) -> void:
	clear_bubbles()
	menu.close()
	Game.selected = int(p.get("selected", 0))
	var spec: Dictionary = HudPresets.get_spec(preset_name)
	clock.set_show_season(spec.get("show_season", true))
	plumbob_fallback = spec.get("plumbob", Vector2.INF)
	if spec.has("needs"):
		var nd: Dictionary = spec.needs
		for m in Game.household:
			if nd.has(m.name):
				for k in nd[m.name]:
					m.needs[k] = nd[m.name][k]
	if _needs.size() == Game.household.size():
		for i in _needs.size():
			_needs[i].setup(Game.household[i])
		_layout_household()
	else:
		_rebuild_household()
	for bdata in spec.get("bubbles", []):
		var d: Dictionary = bdata.duplicate()
		d["ttl"] = -1.0
		var who: String = d.get("who", "")
		var actor := find_actor(who)
		show_bubble(actor, d)
	if spec.has("list"):
		show_side_list(spec.list.title, spec.list.icon, spec.list.items)
	else:
		hide_side_list()
	if spec.has("menu"):
		var mn: Dictionary = spec.menu
		open_menu(mn.title, mn.actions, mn.at)
	_layout()
