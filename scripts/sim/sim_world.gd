extends Node
## The gameplay layer (added by main.gd in live play). Owns:
##   * touch input: tap a household sim to select it, tap an object for its
##     action menu, tap the floor to "Go Here", long-press a household sim for
##     socials (Chat / Hug / Pet...)
##   * one SimAgent per household member (queue, walking, actions, autonomy)
##   * the NavGrid of the current location
##   * Build / Buy / Decorate (build_mode.gd) and travel (Manage -> map menu)
## It talks to the HUD only through Game signals (menu_requested,
## bubble_requested, action_chosen, notify, ...).

const SimAgent := preload("res://scripts/sim/sim_agent.gd")
const SimActions := preload("res://scripts/sim/sim_actions.gd")
const NavConfig := preload("res://scripts/sim/nav_config.gd")
const BuildMode := preload("res://scripts/sim/build_mode.gd")
const ShotPresets := preload("res://scripts/core/shot_presets.gd")

const TAP_SLOP := 14.0         # px a finger may move and still count as a tap
const LONG_PRESS := 0.5        # s
const SHAREABLE := ["Stage", "Fountain", "Dinner Table", "Fire Pit", "Fall Treats", "Festival Game",
	"Handmade Crafts", "Shopping Cart", "Sofa", "TV", "Toy Box", "Ball", "Art Supplies", "Neighbor", "Cashier"]
const TRAVEL_ICONS := {"home": "home", "backyard": "burger", "festival": "pumpkin", "market": "cart"}

var main: Node
var location: Node3D
var loc_name := ""
var camera_rig: Node3D
var hud: Node
var nav: NavGrid
var agents: Array = []           # SimAgent, index-aligned with Game.household (null if absent)
var interactables: Array = []    # Interactable nodes in the location
var build: Node
var _users := {}                 # Interactable -> Array[agent]
var _menu_ctx: Dictionary = {}
var _menu_open_at_press := false
var _touch_down := false
var _touch_index := -1
var _touch_pos := Vector2.ZERO
var _touch_t := 0.0
var _touch_moved := false
var _touch_long_done := false
var _touches := 0
var _select_by_tap := false
var _frames := 0
## Counters for tests / debugging.
var stats := {"taps": 0, "menus": 0, "orders": 0, "done": 0, "autonomous": 0}


func _ready() -> void:
	name = "Sim"
	build = BuildMode.new()
	build.name = "BuildMode"
	build.world = self
	add_child(build)
	Game.live = true
	Game.action_chosen.connect(_on_action_chosen)
	Game.mode_changed.connect(_on_mode)
	Game.selected_changed.connect(_on_selected)
	Game.furniture_changed.connect(refresh_interactables)


# =================================================================== binding

## Called by main.gd after a location has been built.
func bind_location(loc: Node3D, p_name: String) -> void:
	build.on_location_changed()
	location = loc
	loc_name = p_name
	camera_rig = main.camera_rig if main else null
	hud = main.hud if main else null
	_users.clear()
	_menu_ctx = {}
	for a in agents:
		if a:
			a.queue.clear()
	agents.clear()
	var t0 := Time.get_ticks_msec()
	nav = NavGrid.for_location(location, NavConfig.get_config(p_name, location))
	if OS.has_environment("VIMS_STATS") or OS.has_environment("VIMS_PLAYTEST"):
		print("SIM_NAV %s %dx%d levels=%d build_ms=%d (bind %d ms)" % [p_name, nav.w, nav.h, nav.level_y.size(), nav.build_ms, Time.get_ticks_msec() - t0])
	for i in Game.household.size():
		var m: Dictionary = Game.household[i]
		var a := find_actor(m.name, m.get("look", ""))
		if a == null:
			agents.append(null)
			continue
		var ag = SimAgent.new()
		ag.setup(self, i, a)
		agents.append(ag)
	_init_tasks()
	refresh_interactables()
	build.spawn_saved()
	_adopt_staged()


func find_actor(member_name: String, look: String) -> Node3D:
	if location == null:
		return null
	if location.has_method("get_actor"):
		for k in [member_name, look]:
			var a = location.get_actor(k)
			if a is Node3D:
				return a
	for n in location.find_children("*", "Node3D", true, false):
		if n is SimActor and (n.name == member_name or n.get("look") == look):
			return n
	return null


func is_household_actor(n: Node) -> bool:
	for a in agents:
		if a and a.actor == n:
			return true
	return false


func agent_of_actor(n: Node):
	for a in agents:
		if a and a.actor == n:
			return a
	return null


func selected_agent():
	if Game.selected >= 0 and Game.selected < agents.size():
		return agents[Game.selected]
	return null


func refresh_interactables() -> void:
	interactables.clear()
	if location == null or not is_instance_valid(location):
		return
	for n in location.find_children("*", "", true, false):
		if n is Interactable and n.is_inside_tree() and not n.is_queued_for_deletion():
			interactables.append(n)


func _init_tasks() -> void:
	if Game.location_tasks.has(loc_name):
		Game.tasks = Game.location_tasks[loc_name].duplicate(true)
		Game.tasks_changed.emit()
		return
	# Use the screenshot preset tasks of this location (all still to do),
	# picking the one closest to the current time of day.
	var best: Dictionary = {}
	var bd := INF
	for k in ShotPresets.PRESETS:
		var p: Dictionary = ShotPresets.PRESETS[k]
		if p.location != loc_name:
			continue
		var d := absf(float(p.get("hour", 12)) - Game.hour())
		if d < bd:
			bd = d
			best = p
	var list: Array = []
	for t in best.get("tasks", []):
		list.append({"title": t.title, "icon": t.get("icon", ""), "done": false})
	Game.set_tasks(list)


## The location stages its people (and staged bubbles) for its reference
## shot. Pick up those as real actions when the pose matches an object nearby;
## otherwise start idle.
func _adopt_staged() -> void:
	for ag in agents:
		if ag == null:
			continue
		Game.clear_bubble(ag.actor, "")
		var pose: String = ag.actor.get("pose")
		if pose == null or pose in ["idle", "walk"]:
			if pose == "walk":
				ag.actor.set_pose("idle")
			continue
		var best = null
		var best_a: Dictionary = {}
		var bd := 1.6
		for it in interactables:
			for a in SimActions.actions_for(it, ag.member):
				if a.get("pose", "") != pose:
					continue
				var d: float = _flat(it.world_use_spot(), ag.actor.global_position)
				if absf(it.world_use_spot().y - ag.actor.global_position.y) > 1.0:
					continue
				if d < bd:
					bd = d
					best = it
					best_a = a
		if best == null:
			continue
		ag.order = {"action": best_a, "target": best, "auto": true}
		ag.spot = ag.actor.global_position
		ag.phase = "act"
		ag.elapsed = float(best_a.get("minutes", 30.0)) * (0.2 + 0.1 * ag.index)
		reserve(best, ag)
		ag._reserved = best
		ag._bubble(ag.elapsed / maxf(1.0, best_a.get("minutes", 30.0)), true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# =================================================================== per frame

func _process(delta: float) -> void:
	_frames += 1
	if location == null or not is_instance_valid(location):
		return
	var dm := Game.game_minutes(delta)
	for ag in agents:
		if ag:
			ag.tick(delta, dm)
	if _touch_down and not _touch_moved and not _touch_long_done and _touches == 1:
		if Time.get_ticks_msec() / 1000.0 - _touch_t >= LONG_PRESS:
			_touch_long_done = true
			long_press(_touch_pos)


# =================================================================== input

func _input(e: InputEvent) -> void:
	# Remember whether a menu was open when this press began: the menu closes
	# itself on an outside press and that tap must not also act on the world.
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_menu_open_at_press = _menu_visible()


func _menu_visible() -> bool:
	if hud and "menu" in hud and hud.menu is CanvasItem:
		return hud.menu.visible
	return false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches += 1
			if _touches == 1:
				_touch_down = true
				_touch_index = e.index
				_touch_pos = e.position
				_touch_t = Time.get_ticks_msec() / 1000.0
				_touch_moved = false
				_touch_long_done = false
				if build.is_active() and build.press(e.position):
					get_viewport().set_input_as_handled()
			else:
				_touch_moved = true   # multi-touch gesture, not a tap
		else:
			_touches = maxi(0, _touches - 1)
			if e.index == _touch_index and _touch_down:
				_touch_down = false
				build.release()
				if not _touch_moved and not _touch_long_done:
					if _menu_open_at_press:
						_menu_open_at_press = false
					elif not _over_hud(e.position):
						tap(e.position)
	elif e is InputEventScreenDrag:
		if e.index == _touch_index and _touch_down:
			if e.position.distance_to(_touch_pos) > TAP_SLOP:
				_touch_moved = true
			if build.dragging:
				build.drag(e.position)
				get_viewport().set_input_as_handled()


## Is a (non click-through) HUD control under this point?
func _over_hud(p: Vector2) -> bool:
	if hud == null:
		return false
	var root = hud.get("root")
	if root == null:
		return false
	return _hit_control(root, p)


func _hit_control(c: Control, p: Vector2) -> bool:
	if not c.visible:
		return false
	if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(p):
		return true
	for ch in c.get_children():
		if ch is Control and _hit_control(ch, p):
			return true
	return false


## A tap on the 3D view (screen position in viewport pixels).
func tap(screen: Vector2) -> void:
	stats.taps += 1
	if build.is_active():
		build.tap(screen)
		return
	# 1) a household sim -> select
	var ag = pick_agent(screen)
	if ag != null:
		if ag.index != Game.selected:
			_select_by_tap = true
			Game.selected = ag.index
			_select_by_tap = false
			Game.show_bubble(ag.actor, {"kind": "emote", "icon": "smile", "id": "say", "ttl": 1.0})
		else:
			_open_self_menu(ag, screen)
		return
	# 2) an object / NPC -> its action menu
	var it = pick_interactable(screen)
	if it != null:
		open_object_menu(it, screen)
		return
	# 3) the floor -> Go Here
	var g := ground_point(screen)
	var sel = selected_agent()
	if not g.is_empty() and sel != null:
		sel.command({"action": {"id": "go_here", "label": "Go Here", "icon": "home", "minutes": 0.0}, "point": g.pos})
		stats.orders += 1


func long_press(screen: Vector2) -> void:
	if build.is_active() or _menu_visible():
		return
	var ag = pick_agent(screen)
	var sel = selected_agent()
	if ag != null and sel != null and ag != sel:
		var acts := SimActions.socials(sel.kind, ag.kind, ag.display_name())
		open_menu(ag.display_name(), acts, {"type": "social", "other": ag}, screen)
	elif ag != null:
		_open_self_menu(ag, screen)


func _open_self_menu(ag, screen: Vector2) -> void:
	# Tapping the selected sim: socials with family members + cancel.
	var rows: Array = []
	for other in agents:
		if other == null or other == ag:
			continue
		var acts := SimActions.socials(ag.kind, other.kind, other.display_name())
		if not acts.is_empty():
			var a: Dictionary = acts[0].duplicate()
			a["other_index"] = other.index
			rows.append(a)
	if ag.is_busy():
		rows.append({"id": "cancel", "label": "Stop %s" % ag.current_label(), "icon": "dots"})
	if rows.is_empty():
		return
	open_menu(ag.display_name(), rows, {"type": "self"}, screen)


## Household agent whose body is under the screen point (closest to camera).
func pick_agent(screen: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var best = null
	var bd := INF
	for ag in agents:
		if ag == null or not is_instance_valid(ag.actor) or not ag.actor.is_visible_in_tree():
			continue
		var base: Vector3 = ag.actor.global_position
		var top: Vector3 = ag.actor.head_top() if ag.actor.has_method("head_top") else base + Vector3(0, 1.7, 0)
		if cam.is_position_behind(base) or cam.is_position_behind(top):
			continue
		var a := cam.unproject_position(base)
		var b := cam.unproject_position(top)
		var mid := (base + top) * 0.5
		var r := cam.unproject_position(mid).distance_to(cam.unproject_position(mid + cam.global_transform.basis.x * 0.32))
		r = maxf(r, 22.0)
		var d := Geometry2D.get_closest_point_to_segment(screen, a, b).distance_to(screen)
		if d <= r:
			var cd := cam.global_position.distance_to(mid)
			if cd < bd:
				bd = cd
				best = ag
	return best


func pick_interactable(screen: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null or location == null:
		return null
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0)
	q.collide_with_areas = false
	var exclude: Array[RID] = []
	# Skip hidden objects (cut-away floors) and colliders of household members.
	for _i in 8:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		var c = hit.collider
		if c is Interactable and c.is_visible_in_tree() and not is_household_actor(c.get_parent()) and location.is_ancestor_of(c):
			return c
		exclude.append(hit.rid)
	return null


## Floor point under a screen position: {pos: Vector3, level: int} or {}.
## Tries the highest storey first (cutaway view), falling through holes.
func ground_point(screen: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return {}
	if nav == null:
		var t0 := -from.y / dir.y
		return {} if t0 < 0.0 else {"pos": from + dir * t0, "level": 0}
	var order: Array = range(nav.level_y.size())
	order.reverse()
	for li in order:
		var y: float = nav.level_y[li]
		var t := (y - from.y) / dir.y
		if t <= 0.0:
			continue
		var p := from + dir * t
		if not nav.in_bounds(p):
			continue
		var c := nav.cell_of(p)
		if nav.has_floor(li, c):
			p.y = nav.floor_y(p, li)
			return {"pos": p, "level": li}
	return {}


# =================================================================== menus

func open_menu(title: String, rows: Array, ctx: Dictionary, screen: Vector2) -> void:
	_menu_ctx = ctx
	_menu_ctx["title"] = title
	stats.menus += 1
	Game.menu_requested.emit(title, rows, screen + Vector2(24, -40))


func open_object_menu(it: Interactable, screen: Vector2) -> void:
	var sel = selected_agent()
	if sel == null:
		return
	var acts := SimActions.actions_for(it, sel.member)
	if acts.is_empty():
		Game.show_bubble(sel.actor, {"kind": "thought", "icon": "dots", "id": "say", "ttl": 1.6})
		Game.notify.emit("%s can't use the %s" % [sel.display_name(), it.title], "dots")
		return
	open_menu(it.title, acts, {"type": "object", "target": it}, screen)


func _on_action_chosen(title: String, action: Dictionary) -> void:
	var ctx := _menu_ctx
	_menu_ctx = {}
	var t: String = ctx.get("type", "")
	if t == "" and title == "Travel":
		t = "travel"
	match t:
		"object":
			var sel = selected_agent()
			var it = ctx.get("target")
			if sel != null and it != null and is_instance_valid(it):
				sel.command({"action": action, "target": it})
				stats.orders += 1
		"social":
			var sel = selected_agent()
			var other = ctx.get("other")
			if sel != null and other != null:
				sel.command({"action": action, "other": other})
				stats.orders += 1
		"self":
			var sel = selected_agent()
			if sel == null:
				return
			if action.get("id", "") == "cancel":
				sel.cancel_all()
			elif action.has("other_index"):
				var other = agents[int(action.other_index)]
				if other:
					sel.command({"action": action, "other": other})
					stats.orders += 1
		"travel":
			var dest: String = action.get("loc", "")
			if dest != "":
				travel(dest)
		"catalog", "ghost", "placed":
			build.on_menu(ctx, action)


func travel_menu(screen := Vector2(450, 520)) -> void:
	var rows: Array = []
	for l in Game.LOCATIONS:
		if l == Game.location:
			continue
		var label: String = "Go Home" if l == "home" else Game.LOCATION_NAMES[l]
		rows.append({"id": "go_" + l, "label": label, "icon": TRAVEL_ICONS.get(l, "house_white"), "loc": l})
	open_menu("Travel", rows, {"type": "travel"}, screen)


func travel(dest: String) -> void:
	if dest == Game.location:
		return
	if dest == "home":
		Game.complete_task_title("Return Home")
	# Drop every bubble anchored to this lot's people before they are freed.
	for ag in agents:
		if ag:
			ag.cancel_all()
			Game.clear_bubble(ag.actor, "")
	if location:
		for n in location.find_children("*", "Node3D", true, false):
			if n is SimActor:
				Game.clear_bubble(n, "")
	Game.travel(dest)


func _on_mode(m: String) -> void:
	match m:
		"live":
			build.exit()
		"build", "buy", "decorate":
			build.enter(m)
		"manage":
			build.exit()
			travel_menu()
			# Manage is a one-shot menu; the bar goes back to its normal state.
			(func(): if Game.mode == "manage": Game.mode = "live").call_deferred()


func _on_selected(i: int) -> void:
	if _select_by_tap or camera_rig == null or not camera_rig.has_method("glide_to"):
		return
	if i >= 0 and i < agents.size() and agents[i] != null:
		var p: Vector3 = agents[i].actor.global_position
		camera_rig.glide_to(Vector3(p.x, p.y + 0.8, p.z))


func say_selected(text: String, icon := "") -> void:
	var sel = selected_agent()
	if sel:
		sel._say(text, icon)


# =================================================================== object use

func user_of(it: Node):
	var u: Array = _users.get(it, [])
	return u[0] if not u.is_empty() else null


func shareable(it: Node) -> bool:
	var title: String = str(it.get("title"))
	return title in SHAREABLE or title.length() > 0 and it.get_parent() is SimActor


func reserve(it: Node, ag) -> void:
	if not _users.has(it):
		_users[it] = []
	if not ag in _users[it]:
		_users[it].append(ag)


func release(it: Node, ag) -> void:
	if _users.has(it):
		_users[it].erase(ag)
		if _users[it].is_empty():
			_users.erase(it)


func release_object(it: Node) -> void:
	if it == null:
		return
	for ag in agents:
		if ag and ag.order.get("target") == it:
			ag.cancel_all()
	_users.erase(it)


## Where an agent should stand for an order: {spot: Vector3, face: Vector3} or {}.
func approach(ag, o: Dictionary) -> Dictionary:
	var a: Dictionary = o.get("action", {})
	if a.get("id", "") == "go_here":
		return {"spot": _open_spot(o.point)}
	var other = o.get("other")
	if other != null:
		var tp: Vector3 = other.actor.global_position
		var d: Vector3 = ag.actor.global_position - tp
		d.y = 0.0
		if d.length() < 0.05:
			d = Vector3(0, 0, 1)
		var gap := 0.75 if (ag.kind == "dog" or other.kind == "dog") else 0.9
		var s := _open_spot(tp + d.normalized() * gap)
		return {"spot": s, "face": tp}
	var it = o.get("target")
	if it == null or not is_instance_valid(it):
		return {}
	var center: Vector3 = it.global_transform * it.look_at_spot
	var spot: Vector3
	var face := center
	if it.use_spot != Vector3.ZERO:
		spot = it.world_use_spot()
		var users: Array = _users.get(it, [])
		if shareable(it) and not users.is_empty() and not ag in users:
			# Stand next to whoever already uses it.
			var ang: float = 1.2 * users.size() + 0.4 * ag.index
			spot = _open_spot(spot + Vector3(cos(ang), 0, sin(ang)) * 0.7)
	else:
		var half := _box_half(it)
		var d: Vector3 = ag.actor.global_position - center
		d.y = 0.0
		if d.length() < 0.05:
			d = Vector3(0, 0, 1)
		spot = _open_spot(center + d.normalized() * (maxf(half.x, half.z) + 0.4))
	if _flat(face, spot) < 0.3:
		face = _open_face(it, spot, a)
	return {"spot": spot, "face": face}


func _box_half(it: Node) -> Vector3:
	for c in it.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			return (c.shape as BoxShape3D).size * 0.5
	return Vector3(0.3, 0.5, 0.3)


## The floor point nearest p that a sim can stand on.
func _open_spot(p: Vector3) -> Vector3:
	if nav == null or not nav.in_bounds(p):
		return p
	var li := nav.level_of(p)
	var c := nav.nearest_open(li, nav.cell_of(p), 16)
	if c.x < 0:
		return p
	if c == nav.cell_of(p):
		return Vector3(p.x, nav.floor_y(p, li), p.z)
	return nav.center_of(li, c)


## When an object's look-at point is where the sim stands (sofas, beds), face
## the most open direction; for lying down, face along the long axis to the
## foot end (the open one).
func _open_face(it: Node, spot: Vector3, a: Dictionary) -> Vector3:
	if nav == null:
		return spot + Vector3(0, 0, 1)
	var li := nav.level_of(spot)
	var dirs: Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var pose: String = a.get("pose", "")
	if pose in ["lie", "sleep"]:
		var half := _box_half(it)
		var bx: Vector3 = it.global_transform.basis.x
		var bz: Vector3 = it.global_transform.basis.z
		var long_ax := bz if half.z >= half.x else bx
		var ln := maxf(half.x, half.z)
		long_ax.y = 0
		long_ax = long_ax.normalized()
		var o1 := nav.openness(li, spot + long_ax * ln, long_ax, 1.0)
		var o2 := nav.openness(li, spot - long_ax * ln, -long_ax, 1.0)
		return spot + (long_ax if o1 >= o2 else -long_ax)
	var best: Vector3 = dirs[0]
	var bo := -1
	for d: Vector3 in dirs:
		var o := nav.openness(li, spot + d * 0.5, d, 1.25)
		if o > bo:
			bo = o
			best = d
	return spot + best


# =================================================================== autonomy

func choose_autonomous(ag) -> Dictionary:
	var best: Dictionary = {}
	var bs := 0.1
	var p: Vector3 = ag.actor.global_position
	for it in interactables:
		if not is_instance_valid(it):
			continue
		var u = user_of(it)
		if u != null and u != ag and not shareable(it):
			continue
		var wp: Vector3 = it.world_use_spot() if it.use_spot != Vector3.ZERO else it.global_position
		var dist := _flat(wp, p) + absf(wp.y - p.y) * 3.0
		for a in SimActions.actions_for(it, ag.member):
			var cost := -int(a.get("money", 0))
			if cost > 0:
				# Free will never spends money unless a need is desperate and this fixes it.
				if not Game.can_afford(cost) or not _desperate_fix(ag, a):
					continue
			var s := SimActions.score(a, ag.member, dist) + randf() * 0.05
			if s > bs:
				bs = s
				best = {"action": a, "target": it}
	# Socials with idle family members.
	if ag.member.needs.has("social") or ag.kind == "dog":
		for other in agents:
			if other == null or other == ag or other.phase != "idle":
				continue
			for a in SimActions.socials(ag.kind, other.kind, other.display_name()):
				var s := SimActions.score(a, ag.member, _flat(other.actor.global_position, p)) + randf() * 0.04
				if s > bs:
					bs = s
					best = {"action": a, "other": other}
	if best.is_empty():
		# Nothing worth doing: potter about (dogs trot after the selected sim).
		var target := p
		var sel = selected_agent()
		if ag.kind == "dog" and sel != null and sel != ag:
			target = sel.actor.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		else:
			target = p + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		if nav and nav.in_bounds(target) and _flat(target, p) > 0.6:
			target.y = p.y
			best = {"action": {"id": "go_here", "label": "Wander", "minutes": 0.0}, "point": target}
	if not best.is_empty():
		stats.autonomous += 1
	return best


func _desperate_fix(ag, a: Dictionary) -> bool:
	var low: String = ag.lowest_need()
	return low != "" and ag.member.needs[low] < 0.2 and float(a.get("needs", {}).get(low, 0.0)) > 0.0


func on_action_done(_ag, _o: Dictionary) -> void:
	stats.done += 1
