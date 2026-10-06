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


## Screen gap (px) between the head-top anchor and the bubble's tail tip.
const HEAD_GAP := 3.0
## Where a skill chip sits relative to the head (its top-left corner):
## right of the main bubble's tail, just under the bubble body.
const CHIP_OFS := Vector2(26, -10)


func _position_bubble(b) -> void:
	var tip := Vector2.INF
	b.tail_frac = b.base_tail_frac
	b.tail_lean = 0.0
	var a: Node3D = b.anchor
	if a != null and is_instance_valid(a) and a.is_inside_tree():
		var head := _project(_anchor_point(a))
		if head != Vector2.INF:
			if b.kind == "skill":
				tip = head + CHIP_OFS + Vector2(b.size.x * b.tail_frac - 7.0, b.size.y + 8.0)
			elif _is_selected_actor(a) or b.selected_side:
				# bubble sits up-left so the plumbob can float beside it over
				# the head; the tail leans right and touches just above the head
				b.tail_frac = 0.7
				b.tail_lean = 7.0
				tip = head + Vector2(-2, -HEAD_GAP)
			else:
				tip = head + Vector2(0, -HEAD_GAP)
			tip += b.offset
	else:
		var at = b.fallback_at
		var sp = b.fallback_screen
		if at is Vector2:
			tip = at + Vector2(b.size.x * b.tail_frac, b.size.y + WorldBubble.TAIL_H)
		elif sp is Vector2:
			tip = sp
	b.visible = tip != Vector2.INF
	if b.visible:
		b.tip = tip
		b.place()
		_keep_off_hud(b)
		b.queue_redraw()


## Slide a bubble right so it never sits on top of the portrait/needs column;
## the tail follows the anchor as far as the bubble's width allows.
func _keep_off_hud(b) -> void:
	var hr := _household_rect.grow(8.0)
	var r := Rect2(b.position, b.size)
	if hr.size.x <= 0.0 or not hr.intersects(r):
		return
	var nx := hr.end.x
	var tx: float = b.tip.x
	b.tail_frac = clampf((tx - nx) / b.size.x, 0.12, 0.5)
	b.position.x = nx
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
	_resolve_overlaps()
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


var _dbg_frames := 0 if OS.get_environment("HUD_DEBUG") != "" else -1
var plumbob_fallback := Vector2.INF


func _update_plumbob() -> void:
	var a := _selected_actor()
	var tip := Vector2.INF
	if a:
		var head := _project(_anchor_point(a))
		if head != Vector2.INF:
			tip = head + Vector2(0, -8)
			# beside the sim's own action bubble, level with its body
			var b = _main_bubble_for(a)
			if b != null:
				var cy: float = b.position.y + b.size.y * 0.5
				tip = Vector2(maxf(head.x, b.position.x + b.size.x + 15.0), cy + 34.0 * plumbob.gem_scale)
	else:
		tip = plumbob_fallback
	plumbob.active = tip != Vector2.INF
	plumbob.tip = tip if plumbob.active else Vector2.ZERO


## Space kept free right of the selected sim's bubble for the plumbob.
const PLUMBOB_RESERVE := 44.0
var _sort_buf: Array = []


## Push overlapping main bubbles apart horizontally (tails keep pointing at
## their sims); a sim's skill chip moves with its bubble.
func _resolve_overlaps() -> void:
	_sort_buf.clear()
	for key in _bubbles:
		var b = _bubbles[key]
		if is_instance_valid(b) and b.visible and b.kind != "skill":
			_sort_buf.append(b)
	if _sort_buf.size() < 2:
		return
	_sort_buf.sort_custom(func(x, y): return x.position.x < y.position.x)
	var sel := _selected_actor()
	for i in range(1, _sort_buf.size()):
		var b = _sort_buf[i]
		for j in i:
			var o = _sort_buf[j]
			var ow: float = o.size.x + (PLUMBOB_RESERVE if (sel != null and o.anchor == sel) else 0.0)
			var orect := Rect2(o.position, Vector2(ow, o.size.y + WorldBubble.TAIL_H)).grow(8.0)
			var br := Rect2(b.position, b.size + Vector2(0, WorldBubble.TAIL_H))
			if not orect.intersects(br):
				continue
			var dx: float = orect.end.x - b.position.x
			b.position.x += dx
			b.tail_frac = clampf(b.tail_frac - dx / b.size.x, 0.14, 0.86)
			b.tail_lean = 0.0
			b.queue_redraw()
			if b.anchor != null:
				var chip = _bubbles.get(str(b.anchor.get_instance_id()) + "|skill")
				if chip != null and is_instance_valid(chip):
					chip.position.x += dx


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
