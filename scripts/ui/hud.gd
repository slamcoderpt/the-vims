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
			ch = 88.0 if dog else maxf(92.0 if compact else 100.0, ph)
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


## Clear screen space (px) between the top of a sim's head and the tip of its
## bubble's tail: about half a head, never less than MIN_GAP.
const MIN_GAP := 40.0
const MAX_GAP := 54.0
## Space kept free right of the selected sim's bubble for the plumbob.
const PLUMBOB_RESERVE := 62.0
const BUBBLE_PAD := 8.0

## Per-frame scratch (reused, no allocations in the steady state).
var _heads: Array[Rect2] = []
var _head_actors: Array = []
var _mains: Array = []
var _chips: Array = []
var _hud_rects: Array[Rect2] = []
var _scene_actors: Array = []
var _head_hard: Array[bool] = []
var _n_hard := 0
var _scan_loc: Node
var _scan_t := 0.0


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
	return clampf(dy * 0.45, MIN_GAP, MAX_GAP)


## Desired placement of one bubble (before the overlap pass).
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
			if b.kind == "skill":
				b.target = tip + Vector2(24, -b.size.y)
			else:
				var frac := 0.72 if (_is_selected_actor(a) or b.selected_side) else 0.5
				b.target = tip - Vector2(b.size.x * frac, b.size.y + WorldBubble.TAIL_H)
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
		var w := maxf(hm.z * 0.95, 34.0)
		_heads.append(Rect2(hm.x - w * 0.5, hm.y - 6.0, w, hm.z * 1.15 + 6.0))
		# household + bubble owners are hard obstacles; extras are soft
		_head_hard.append(i < _n_hard)


func _rect_of(b) -> Rect2:
	return Rect2(b.target, b.size)


## Body + tail footprint of a main bubble (+ plumbob space if selected).
func _footprint(b, sel: Node3D) -> Rect2:
	var w: float = b.size.x + (PLUMBOB_RESERVE if (sel != null and b.anchor == sel) else 0.0)
	return Rect2(b.target, Vector2(w, b.size.y + WorldBubble.TAIL_H))


## Shift a bubble horizontally but keep its tail tip inside the body span.
func _shift_x(b, dx: float) -> float:
	if b.head == Vector2.INF:
		b.target.x += dx
		return dx
	var lo: float = b.tip.x - b.size.x + 22.0
	var hi: float = b.tip.x - 22.0
	var nx := clampf(b.target.x + dx, lo, hi)
	var done: float = nx - b.target.x
	b.target.x = nx
	return done


## Screen-space overlap pass: bubbles vs bubbles (+plumbob slot), vs sim
## heads and vs the fixed HUD cards; then chips beside their bubbles.
func _resolve_layout() -> void:
	var sel := _selected_actor()
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
	var vs: Vector2 = root.size
	# 1. bubbles never cover a head: lift above any head they touch
	for b in _mains:
		_lift_off_heads(b)
	# 2. bubbles vs bubbles: split horizontally, then lift the higher one
	for _pass in 4:
		var moved := false
		for i in _mains.size():
			for j in range(i + 1, _mains.size()):
				var p = _mains[i]
				var q = _mains[j]
				var pr := _footprint(p, sel).grow(BUBBLE_PAD * 0.5)
				var qr := _footprint(q, sel).grow(BUBBLE_PAD * 0.5)
				if not pr.intersects(qr):
					continue
				moved = true
				var left = p if pr.get_center().x <= qr.get_center().x else q
				var right = q if left == p else p
				var lr: Rect2 = pr if left == p else qr
				var rr: Rect2 = qr if left == p else pr
				var ox: float = lr.end.x - rr.position.x
				var a := _shift_x(left, -ox * 0.5)
				var c := _shift_x(right, ox * 0.5)
				var rest: float = ox + a - c
				if rest > 0.5:
					rest -= _shift_x(right, rest) 
					rest += _shift_x(left, -rest)
				if rest > 0.5:
					# no horizontal room: stack the upper bubble above the other
					var up = left if left.target.y <= right.target.y else right
					var dn = right if up == left else left
					up.target.y = dn.target.y - up.size.y - WorldBubble.TAIL_H - BUBBLE_PAD
		if not moved:
			break
	# 3. keep off fixed HUD cards and inside the screen
	for b in _mains:
		_keep_off_hud(b, vs)
	# 4. skill chips: below-right of their bubble, clear of faces/bubbles
	for ch in _chips:
		var mb = _main_bubble_for(ch.anchor) if ch.anchor != null and is_instance_valid(ch.anchor) else null
		if mb != null:
			ch.target = Vector2(mb.target.x + mb.size.x * 0.62, mb.target.y + mb.size.y + 12.0)
			# chip tail points down-left at the head
			ch.tip = ch.target + Vector2(4.0, ch.size.y + 9.0)
		for _k in 3:
			var cr := Rect2(ch.target, ch.size).grow(4.0)
			var hit := false
			for i in _heads.size():
				if _head_hard[i] and _heads[i].intersects(cr):
					ch.target.x = _heads[i].end.x + 6.0
					hit = true
			for ob in _mains:
				if ob == mb:
					continue
				var orr := Rect2(ob.target, ob.size + Vector2(0, WorldBubble.TAIL_H)).grow(4.0)
				if orr.intersects(Rect2(ch.target, ch.size)):
					ch.target.y = orr.end.y + 4.0
					hit = true
			for oc in _chips:
				if oc == ch:
					break
				var ocr := Rect2(oc.target, oc.size).grow(4.0)
				if ocr.intersects(Rect2(ch.target, ch.size)):
					ch.target.y = ocr.end.y + 2.0
					hit = true
			if not hit:
				break
		ch.tip = ch.target + Vector2(4.0, ch.size.y + 9.0)
		_keep_off_hud(ch, vs)
	for b in _mains:
		_apply(b)
	for ch in _chips:
		_apply(ch)


func _lift_off_heads(b) -> void:
	# any head: slide sideways if the tail still reaches its sim; soft heads
	# (background NPCs) are ignored when that fails, hard ones lift below
	for i in _heads.size():
		var hr: Rect2 = _heads[i]
		var r := Rect2(b.target, b.size + Vector2(0, WorldBubble.TAIL_H)).grow(4.0)
		if not hr.intersects(r):
			continue
		var x0: float = b.target.x
		var go_r: float = hr.end.x - r.position.x
		var go_l: float = r.end.x - hr.position.x
		var want := go_r if go_r < go_l else -go_l
		if absf(_shift_x(b, want) - want) > 0.5:
			b.target.x = x0
	for _k in 3:
		var r := Rect2(b.target, b.size + Vector2(0, WorldBubble.TAIL_H)).grow(4.0)
		var hit := false
		for i in _heads.size():
			var hr: Rect2 = _heads[i]
			if not (_head_hard[i] and hr.intersects(r)):
				continue
			var ny: float = hr.position.y - b.size.y - WorldBubble.TAIL_H - 10.0
			if b.head != Vector2.INF and b.target.y - ny > maxf(70.0, b.head_px * 0.8):
				# lifting would detach the bubble from its sim: slide it off
				# the other face instead, letting the tail sit near the edge
				var go_r: float = hr.end.x + 4.0 - b.target.x
				var go_l: float = b.target.x + b.size.x - hr.position.x + 4.0
				var nx: float = b.target.x + (go_r if go_r < go_l else -go_l)
				b.target.x = clampf(nx, b.tip.x - b.size.x + 14.0, b.tip.x - 14.0)
			else:
				b.target.y = ny
			hit = true
		if not hit:
			return


## Nudge a bubble off the portrait column / clock / tasks / mode bar / money
## and inside the screen; the tail keeps pointing at the sim.
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
			var head := Vector2(hm.x, hm.y)
			# no bubble: float the gem in the head gap
			tip = head + Vector2(0, -10.0)
			var b = _main_bubble_for(a)
			if b != null:
				# in the reserved slot right of the sim's own bubble, its
				# bottom level with the bubble body's bottom (ref1)
				tip = Vector2(b.target.x + b.size.x + PLUMBOB_RESERVE * 0.5 + 2.0, b.target.y + b.size.y + 26.0 * plumbob.gem_scale)
				var gr := Rect2(tip.x - 18.0, tip.y - 70.0 * plumbob.gem_scale, 36.0, 66.0 * plumbob.gem_scale)
				var blocked := false
				for o in _mains:
					if o != b and Rect2(o.target, o.size).intersects(gr):
						blocked = true
				for i in _heads.size():
					if _head_hard[i] and _heads[i].intersects(gr):
						blocked = true
				if blocked:
					# fall back to sitting on top of the bubble, over its tail
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
