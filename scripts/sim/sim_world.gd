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
const SimOverlay := preload("res://scripts/sim/ui/sim_overlay.gd")
const Wishes := preload("res://scripts/sim/wishes.gd")
const Careers := preload("res://scripts/sim/careers.gd")
const Traits := preload("res://scripts/sim/traits.gd")
const Carpool := preload("res://scripts/sim/carpool.gd")
## Where sims leave the lot for work / school (walk here, then the carpool):
## the front door at home, the street side elsewhere.
const EXITS := {"home": Vector3(1.0, 0.0, 4.3), "backyard": Vector3(0.0, 0.0, 8.0),
	"festival": Vector3(0.0, 0.0, 9.0), "market": Vector3(0.0, 0.0, 6.0)}
## Where the carpool stops, relative to the exit (street side).
const CURB := {"home": Vector3(0.0, 0.0, 4.4), "backyard": Vector3(0.0, 0.0, 1.6),
	"festival": Vector3(0.0, 0.0, 1.6), "market": Vector3(0.0, 0.0, 1.6)}
## The home mailbox (bills arrive here).
const MAILBOX := {"home": Vector3(2.4, 0.0, 7.5)}
## In-game minutes between wish top-ups.
const WISH_EVERY := 60.0

const TAP_SLOP := 14.0         # px a finger may move and still count as a tap
const LONG_PRESS := 0.5        # s
const SHAREABLE := ["Stage", "Fountain", "Dinner Table", "Dining Table", "Fire Pit", "Fall Treats", "Festival Game",
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
## Gameplay HUD additions (queue strip, mood + moodlets, skills panel).
var overlay: CanvasLayer
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
## Townies socialized with on this lot this visit (for "Meet N Neighbors").
var met_here := {}
## A cooked family meal waiting on a table (Sims 3 "Call to Meal"):
## {table, node, plates: Array, servings, quality, cook, expires}.
var meal: Dictionary = {}
var _wish_acc := 0.0
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
	Game.furniture_changed.connect(_on_furniture_changed)
	Game.queue_cancel_requested.connect(_on_queue_cancel)
	Game.relationship_level_changed.connect(_on_rel_level)
	Game.skill_changed.connect(_on_skill)
	Game.bills_changed.connect(_update_mail_flag)
	overlay = SimOverlay.new()
	overlay.name = "SimOverlay"
	overlay.hud = main.hud if main else null
	add_child(overlay)


## Bought / moved / sold furniture: new objects to use, and routes that
## failed before may work now.
func _on_furniture_changed() -> void:
	refresh_interactables()
	for a in agents:
		if a:
			a.unreachable.clear()


func _on_queue_cancel(i: int, slot: int) -> void:
	if i >= 0 and i < agents.size() and agents[i] != null:
		agents[i].cancel_slot(slot)


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
	meal = {}
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
	_add_mailbox()
	met_here.clear()
	_setup_townies()
	refresh_interactables()
	build.spawn_saved()
	_adopt_staged()
	# Mid-shift travel: whoever is at work stays out of sight until they're done.
	for ag in agents:
		if ag == null:
			continue
		var w: Dictionary = ag.member.get("work", {})
		if str(w.get("state", "")) == "away":
			ag.set_away()
		elif str(w.get("state", "")) == "going":
			w.state = ""
	roll_wishes()


func roll_wishes() -> void:
	_wish_acc = 0.0
	for ag in agents:
		if ag:
			Wishes.roll(self, ag)


func _on_skill(i: int, skill: String, level: int) -> void:
	if i >= 0 and i < agents.size() and agents[i] != null:
		Wishes.on_skill(agents[i], skill, level)


## Give every non-household person on the lot a townie identity (name,
## persistent relationship) and make sure each one can be tapped.
func _setup_townies() -> void:
	for n in location.find_children("*", "Node3D", true, false):
		if not n is SimActor or is_household_actor(n):
			continue
		var info := Game.townie_by_look(str(n.get("look")))
		if info.is_empty():
			continue
		n.set_meta("townie", info.name)
		var has_it := false
		for c in n.get_children():
			if c is Interactable:
				has_it = true
		if not has_it:
			Interactable.attach(n, "Neighbor", [], Vector3(0.6, 1.7, 0.6), Vector3(0, 0.85, 0), Vector3(0, 0, 0.9))


## Townie name of an Interactable that sits on a townie ("" otherwise).
func townie_of(it) -> String:
	# Untyped on purpose: callers may hold an Interactable that was freed
	# (sold furniture, a lot being rebuilt); a typed Node parameter would fail
	# before this check could run.
	if it == null or not is_instance_valid(it):
		return ""
	var p: Node = (it as Node).get_parent()
	if p != null and p.has_meta("townie"):
		return str(p.get_meta("townie"))
	return ""


func townie_info(tname: String) -> Dictionary:
	for k in Game.TOWNIES:
		if Game.TOWNIES[k].name == tname:
			return Game.TOWNIES[k]
	return {}


## Menu rows for a townie: the lot's own non-chat actions (Pay at Checkout,
## Ask About Deals...) plus socials tiered by friendship. The lot's chat task
## ("Meet 3 Neighbors") rides on every social.
func townie_rows(ag, it: Interactable) -> Array:
	var tname := townie_of(it)
	var info := townie_info(tname)
	var task := ""
	var rows: Array = []
	for a in actions_for(it, ag.member):
		if a.get("id", "") in ["chat", "wave"]:
			task = str(a.get("task", task))
			continue
		rows.append(a)
	var me: String = ag.display_name()
	var soc := SimActions.socials_by_rel(ag.kind, info.get("kind", "adult"), tname, Game.has_met(me, tname), Game.rel(me, tname), true)
	for a in soc:
		if task != "" and not a.has("task") and not a.get("locked", false):
			a["task"] = task
		a["townie"] = tname
	return soc + rows


func _on_rel_level(a: String, b: String, level: String) -> void:
	if Game.mode != "live" and not Game.live:
		return
	var up := Game.rel(a, b) > 0.0
	var tier := Game.rel_tier(Game.rel(a, b))
	var text := "%s and %s are now %s" % [a, b, level + "s" if not level.ends_with("s") else level]
	if level == "Acquaintance":
		text = "%s met %s" % [a, b]
	Game.notify.emit(text, "heart" if up else "dots")
	for nm in [a, b]:
		var i := Game.member_index(nm)
		if i < 0:
			continue
		var other: String = b if nm == a else a
		if i < agents.size() and agents[i] != null:
			Wishes.on_rel(agents[i], other)
		if tier >= 1:
			Game.add_moodlet(i, "new_friend", "Made a Friend" if tier == 1 else ("Close Friends" if tier == 2 else "Best Friends!"), "heart", 10.0 + tier * 4.0, 8.0, "With %s" % other)
		elif tier <= -1:
			Game.add_moodlet(i, "argued", "Had an Argument", "dots", -12.0, 6.0, "With %s" % other)


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
				if a.get("pose", "") != pose or int(a.get("money", 0)) < 0:
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
	for ag in agents:
		if ag:
			ag._sync_queue()
			ag.check_needs()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# =================================================================== per frame

func _process(delta: float) -> void:
	_frames += 1
	if location == null or not is_instance_valid(location):
		return
	var dm := Game.game_minutes(delta)
	if not meal.is_empty() and dm > 0.0 and Game.total_minutes() > float(meal.expires):
		Game.notify.emit("The family meal went cold", "plate")
		clear_meal()
	_wish_acc += dm
	if _wish_acc >= WISH_EVERY:
		roll_wishes()
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
					if _menu_open_at_press and not build.is_active():
						_menu_open_at_press = false
					elif not _over_hud(e.position):
						_menu_open_at_press = false
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
	if overlay and overlay.has_method("hit") and overlay.hit(p):
		return true
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
		var acts := SimActions.socials_for(sel, ag, true)
		var lvl := Game.rel_level(Game.rel(sel.display_name(), ag.display_name()))
		open_menu("%s · %s" % [ag.display_name(), lvl], acts, {"type": "social", "other": ag}, screen)
	elif ag != null:
		_open_self_menu(ag, screen)


func _open_self_menu(ag, screen: Vector2) -> void:
	# Tapping the selected sim: socials with family members + cancel.
	var rows: Array = []
	for other in agents:
		if other == null or other == ag or other.phase == "away":
			continue
		var acts := SimActions.socials_for(ag, other)
		if not acts.is_empty():
			var a: Dictionary = acts[0].duplicate()
			a["other_index"] = other.index
			if not other.display_name() in str(a.label):
				a.label = "%s with %s" % [a.label, other.display_name()]
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
	# Collect the first few objects along the ray (skipping hidden ones and
	# colliders on household members). Overlapping boxes (an armchair beside a
	# bed) are told apart by how close their centre is to the finger on screen.
	var hits: Array = []
	var first_d := INF
	for _i in 6:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		exclude.append(hit.rid)
		var c = hit.collider
		if not (c is Interactable and c.is_visible_in_tree() and not is_household_actor(c.get_parent()) and location.is_ancestor_of(c)):
			continue
		var d: float = from.distance_to(hit.position)
		if hits.is_empty():
			first_d = d
		elif d - first_d > 1.5:
			break
		hits.append(c)
	if hits.is_empty():
		return null
	if build.is_active():
		for c in hits:
			if c.has_meta("placed_uid"):
				return c
	var best = hits[0]
	var bd := INF
	for c in hits:
		var cp: Vector3 = c.global_transform * c.look_at_spot
		if cam.is_position_behind(cp):
			continue
		var sd := cam.unproject_position(cp).distance_to(screen)
		if sd < bd:
			bd = sd
			best = c
	return best


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
	# Floors above the one the camera looks at are hidden (Sims floor view):
	# a tap goes through them.
	var view_top: int = nav.level_y.size() - 1
	if camera_rig and "target" in camera_rig:
		view_top = nav.level_of(camera_rig.target - Vector3(0, 0.8, 0))
	for li in order:
		if li > view_top:
			continue
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
	var tn := townie_of(it)
	if tn != "":
		var lvl := Game.rel_level(Game.rel(sel.display_name(), tn)) if Game.has_met(sel.display_name(), tn) else "Stranger"
		# First name only: the menu card is narrow.
		open_menu("%s · %s" % [tn.get_slice(" ", 0), lvl], townie_rows(sel, it), {"type": "object", "target": it}, screen)
		return
	var acts := actions_for(it, sel.member)
	if acts.is_empty():
		Game.show_bubble(sel.actor, {"kind": "thought", "icon": "dots", "id": "say", "ttl": 1.6})
		Game.notify.emit("%s can't use the %s" % [sel.display_name(), it.title], "dots")
		return
	open_menu(it.title, acts, {"type": "object", "target": it}, screen)


func _on_action_chosen(title: String, action: Dictionary) -> void:
	var ctx := _menu_ctx
	_menu_ctx = {}
	var t: String = ctx.get("type", "")
	if action.get("locked", false):
		var who: String = str(ctx.get("title", "them")).get_slice(" · ", 0)
		var msg: String = action.get("lock_msg", "Become %s with %s to unlock %s" % [action.get("need_tier", "closer"), who, action.get("unlock_label", "that")])
		Game.notify.emit(msg, "star" if action.has("lock_msg") else "heart")
		say_selected("Not yet!", "dots")
		return
	if t == "" and title == "Travel":
		t = "travel"
	if t == "object" and action.get("id", "") == "find_job":
		# Second step: the job listings (Sims 3 newspaper / computer).
		var it = ctx.get("target")
		var sel0 = selected_agent()
		if sel0 != null:
			# Deferred: the HUD closes its menu right after reporting the pick.
			open_menu.call_deferred("Job Listings", Careers.job_rows(sel0.member), {"type": "jobs", "target": it}, Vector2(520, 300))
		return
	if t == "chance":
		var ag_c = ctx.get("agent")
		if ag_c != null:
			ag_c.resolve_chance(action.get("id", "") == "chance_yes")
		return
	if t == "jobs":
		var sel1 = selected_agent()
		var it1 = ctx.get("target")
		if sel1 != null and it1 != null and is_instance_valid(it1):
			var tr: Dictionary = Careers.TRACKS.get(str(action.get("track", "")), {})
			var apply := {"id": "apply_job", "label": "Apply: %s" % tr.get("name", "Job"), "icon": tr.get("icon", "laptop"),
				"minutes": 20.0, "pose": "type", "track": action.get("track", ""), "who": ["adult"]}
			if sel1.command({"action": apply, "target": it1}):
				stats.orders += 1
		return
	match t:
		"object":
			var sel = selected_agent()
			var it = ctx.get("target")
			if sel != null and it != null and is_instance_valid(it):
				if sel.command({"action": action, "target": it}):
					stats.orders += 1
		"social":
			var sel = selected_agent()
			var other = ctx.get("other")
			if sel != null and other != null:
				if sel.command({"action": action, "other": other}):
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
			if action.get("id", "") == "save_game":
				if Game.save_game():
					Game.notify.emit("Game saved · %s" % Game.clock_text(), "star")
			elif dest != "":
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
	rows.append({"id": "save_game", "label": "Save Game", "icon": "star"})
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
	if Game.autosave:
		Game.save_game()


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
	if a.get("id", "") == "go_here" or o.get("work", false):
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
	var pose: String = a.get("pose", "")
	var seated := (pose.begins_with("sit") and pose != "sit_floor") or pose in ["type", "read"]
	if seated and ag.kind != "dog" and nav and nav.seat_height(spot) < 0.3:
		# Sitting at something that isn't itself a seat (a dinner table, a
		# fire pit): take the nearest free chair around it.
		var chair := _free_seat_near(ag, center, maxf(_box_half(it).x, _box_half(it).z) + 1.2)
		if chair != Vector3.INF:
			return {"spot": chair, "face": center}
	var lying: bool = pose in ["lie", "sleep"] and ag.kind != "dog"
	if nav and not seated and not lying and nav.in_bounds(spot):
		# Use spots inside furniture (the fridge's own footprint, behind a
		# counter): stand on the reachable floor cell in front of it instead.
		var li := nav.level_of(spot)
		var sc := nav.cell_of(spot)
		var reg := nav.entry_region(ag.actor.global_position, li)
		if not nav.is_walkable(li, sc) or (reg >= 0 and nav.region_of(li, sc) != reg):
			var st := nav.stand_spot(ag.actor.global_position, spot)
			if st != Vector3.INF:
				spot = st
				face = center
	if _flat(face, spot) < 0.3:
		face = _open_face(it, spot, a)
	return {"spot": spot, "face": face}


## Centre of the nearest chair-height seat cell within r of c that nobody is
## sitting on, or Vector3.INF.
func _free_seat_near(ag, c: Vector3, r: float) -> Vector3:
	var li := nav.level_of(c)
	var cc := nav.cell_of(c)
	var rc := int(ceil(r / nav.cs))
	var taken: Array[Vector3] = []
	for n in location.find_children("*", "Node3D", true, false):
		if n is SimActor and n != ag.actor:
			taken.append(n.global_position)
	for other in agents:
		if other and other != ag and other.phase in ["walk", "act", "wait"]:
			taken.append(other.spot)
	var best := Vector3.INF
	var bd := INF
	for dz in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var q := cc + Vector2i(dx, dz)
			if q.x < 0 or q.y < 0 or q.x >= nav.w or q.y >= nav.h:
				continue
			var i := q.y * nav.w + q.x
			var st: float = nav.seats[li][i]
			var fy: float = nav.floors[li][i]
			if st == INF or fy == INF or st - fy < 0.3 or st - fy > 0.6:
				continue
			var p := nav.center_of(li, q)
			if _flat(p, c) > r:
				continue
			var free := true
			for t in taken:
				if _flat(t, p) < 0.45:
					free = false
					break
			if not free:
				continue
			var d := _flat(p, ag.actor.global_position) + _flat(p, c) * 0.5
			if d < bd:
				bd = d
				best = p
	return best


func _box_half(it: Node) -> Vector3:
	for c in it.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			return (c.shape as BoxShape3D).size * 0.5
	return Vector3(0.3, 0.5, 0.3)


## The floor point nearest p that a sim can stand on.
func _open_spot(p: Vector3) -> Vector3:
	if nav == null:
		return p
	if not nav.in_bounds(p):
		# Never send anyone off the walkable lot (a dog by the fence...).
		var m := nav.cs * 0.5
		p.x = clampf(p.x, nav.ox + m, nav.ox + nav.w * nav.cs - m)
		p.z = clampf(p.z, nav.oz + m, nav.oz + nav.h * nav.cs - m)
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
	var cands: Array = []   # [score, order]
	var p: Vector3 = ag.actor.global_position
	for it in interactables:
		if not is_instance_valid(it) or ag.is_unreachable(it):
			continue
		# Something in use is still an option when a need is urgent (the sim
		# waits its turn, as in the Sims); otherwise free will looks elsewhere.
		var u = user_of(it)
		var busy_pen := 0.0
		if u != null and u != ag and not shareable(it):
			busy_pen = 0.4
		var wp: Vector3 = it.world_use_spot() if it.use_spot != Vector3.ZERO else it.global_position
		var dist := _flat(wp, p) + absf(wp.y - p.y) * 3.0
		var best_s := 0.1
		var best_a: Dictionary = {}
		var acts: Array = townie_rows(ag, it) if townie_of(it) != "" else actions_for(it, ag.member)
		for a in acts:
			if a.get("mean", false) or a.get("locked", false):
				continue
			var cost := -int(a.get("money", 0))
			if cost > 0:
				# Free will never spends money unless a need is desperate and this fixes it.
				if not Game.can_afford(cost) or not _desperate_fix(ag, a):
					continue
			var s := SimActions.score(a, ag.member, dist) + randf() * 0.05 - busy_pen + Wishes.bias(ag, a)
			s += Traits.bias(ag.member, a, a.has("rel"), false)
			if not meal.is_empty():
				if a.get("id", "") == "meal":
					s += 0.15   # food's on the table: eat it before it goes cold
				elif is_meal_cook(it, a) and float(a.get("needs", {}).get("hunger", 0.0)) > 0.0:
					s -= 0.6
			if s > best_s:
				best_s = s
				best_a = a
		if not best_a.is_empty():
			cands.append([best_s, {"action": best_a, "target": it}])
	# Socials with idle family members (and townies the location staged).
	if ag.member.needs.has("social") or ag.kind == "dog":
		for other in agents:
			if other == null or other == ag or other.phase != "idle":
				continue
			for a in SimActions.socials_for(ag, other):
				if a.get("mean", false):
					continue
				var s := SimActions.score(a, ag.member, _flat(other.actor.global_position, p)) + randf() * 0.04
				s += SimActions.social_bias(ag.index, other.index)
				s += Traits.bias(ag.member, a, true, true)
				if s > 0.1:
					cands.append([s, {"action": a, "other": other}])
	var best := _first_reachable(ag, cands)
	if best.is_empty():
		# Nothing worth doing: potter about (dogs trot after the selected sim).
		var target := p
		var sel = selected_agent()
		if ag.kind == "dog" and sel != null and sel != ag:
			target = sel.actor.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		else:
			target = p + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		if nav and nav.in_bounds(target):
			# Snap the stroll to a floor cell this sim can actually walk to.
			var li := nav.level_of(p)
			var c := nav.approach_cell(li, nav.cell_of(Vector3(target.x, p.y, target.z)), nav.entry_region(p, li), 24)
			if c.x >= 0:
				target = nav.center_of(li, c)
		if nav and nav.in_bounds(target) and _flat(target, p) > 0.6:
			target.y = p.y
			best = {"action": {"id": "go_here", "label": "Wander", "minutes": 0.0}, "point": target}
	if not best.is_empty():
		stats.autonomous += 1
	return best


## Highest-scoring candidate whose spot the grid can actually reach (checked
## for the best few only; unreachable objects are remembered by the agent).
func _first_reachable(ag, cands: Array) -> Dictionary:
	cands.sort_custom(func(x, y): return x[0] > y[0])
	var checked := 0
	for c in cands:
		var o: Dictionary = c[1]
		if nav == null or checked >= 6:
			return o
		checked += 1
		var r := approach(ag, o)
		if r.is_empty():
			continue
		nav.find_path(ag.actor.global_position, r.spot, true)
		if nav.last_ok:
			return o
		if o.get("target") != null:
			ag.unreachable[o.target] = Game.total_minutes() + ag.UNREACHABLE_FOR
		stats["unreachable"] = int(stats.get("unreachable", 0)) + 1
	return {}


## Best way to fix one need right now (used when a need hits zero). Money is
## allowed when affordable; distance matters less than in normal free will.
## Objects in use still count (the sim queues up and waits its turn).
func choose_for_need(ag, need: String) -> Dictionary:
	var cands: Array = []
	var p: Vector3 = ag.actor.global_position
	for it in interactables:
		if not is_instance_valid(it) or ag.is_unreachable(it):
			continue
		var u = user_of(it)
		var busy_pen := 0.3 if (u != null and u != ag and not shareable(it)) else 0.0
		var wp: Vector3 = it.world_use_spot() if it.use_spot != Vector3.ZERO else it.global_position
		var dist := _flat(wp, p) + absf(wp.y - p.y) * 3.0
		for a in actions_for(it, ag.member):
			var gain := float(a.get("needs", {}).get(need, 0.0))
			if gain <= 0.0:
				continue
			var cost := -int(a.get("money", 0))
			if cost > 0 and not Game.can_afford(cost):
				continue
			var s := gain * 2.0 - dist * 0.02 - float(a.get("minutes", 30.0)) / 600.0 - busy_pen
			cands.append([s, {"action": a, "target": it}])
	return _first_reachable(ag, cands)


func _desperate_fix(ag, a: Dictionary) -> bool:
	var low: String = ag.lowest_need()
	return low != "" and ag.member.needs[low] < 0.2 and float(a.get("needs", {}).get(low, 0.0)) >= 0.15


func on_action_done(ag, o: Dictionary) -> void:
	stats.done += 1
	var a: Dictionary = o.get("action", {})
	var it = o.get("target")
	if a.get("id", "") == "meal":
		eat_serving()
	elif is_meal_cook(it, a):
		serve_meal(ag, a)
	match a.get("id", ""):
		"apply_job":
			if Game.join_career(ag.index, str(a.get("track", ""))):
				var c: Dictionary = ag.member.career
				Game.notify.emit("%s got a job: %s · $%d/h · %s" % [ag.display_name(), Careers.title(c), Careers.wage(c), Careers.schedule_text(c)], "laptop")
				Game.add_moodlet(ag.index, "new_job", "New Job", "laptop", 10.0, 8.0, Careers.title(c))
				ag._say("I got the job!", "star")
				Wishes.on_career(ag, "job")
		"quit_job":
			var tn: String = str(Careers.track(ag.member.get("career", {})).get("name", "the"))
			Game.quit_career(ag.index)
			Game.notify.emit("%s quit the %s career" % [ag.display_name(), tn], "laptop")
	Wishes.on_action(ag, a, int(ag.last_pay))


# =================================================================== family meals

const MEAL_COOKS := ["Fridge", "Stove", "Grill"]
const MEAL_TABLES := ["Dining Table", "Dinner Table"]
const MEAL_SPOILS := 8 * 60.0


## Object actions for a member, plus "Eat Family Meal" on the table that has one.
func actions_for(it: Node, member: Dictionary) -> Array:
	var out := SimActions.actions_for(it, member)
	out.append_array(career_rows(it, member))
	if not meal.is_empty() and it == meal.get("table") and member.get("kind", "adult") != "dog" and int(meal.servings) > 0:
		out.push_front(meal_action())
	return out


func meal_action() -> Dictionary:
	var q: float = meal.get("quality", 0.0)
	var a := {"id": "meal", "label": "Eat %s (%d left)" % [meal.get("dish", "Meal"), int(meal.get("servings", 0))], "icon": "plate",
		"minutes": 25.0, "pose": "sit", "needs": {"hunger": 0.75, "social": 0.1, "fun": 0.03}}
	if q >= 3.0:
		a["moodlet"] = ["great_meal", "Delicious Family Meal", "cook", 10.0 + q * 2.0, 5.0]
	return a


## A cooking action that makes a meal for the whole family.
func is_meal_cook(it, a: Dictionary) -> bool:
	if it == null or not is_instance_valid(it) or a.get("skill", "") != "Cooking":
		return false
	return str(it.title) in MEAL_COOKS


## The cook finished: plates go on the nearest table and hungry family come to eat.
func serve_meal(cook, a: Dictionary) -> void:
	var table = _meal_table(cook)
	if table == null:
		return
	var humans: Array = agents.filter(func(x): return x != null and x.kind != "dog")
	var cook_ate := float(a.get("needs", {}).get("hunger", 0.0)) >= 0.5
	var n := clampi(humans.size() - (1 if cook_ate else 0), 1, 4)
	var q: float = Game.skill_level(cook.index, "Cooking")
	if not meal.is_empty() and meal.get("table") == table:
		# More food for the table: top up the servings already out.
		var add := mini(n, 4 - int(meal.servings))
		if add > 0:
			_spawn_plates(table, add)
			meal.servings = int(meal.servings) + add
		meal.expires = Game.total_minutes() + MEAL_SPOILS
		_call_to_meal(cook if cook_ate else null, humans, table)
		return
	clear_meal()
	var dishes := ["Mac & Cheese", "Veggie Stew", "Spaghetti", "Pancakes", "Roast Chicken", "Gourmet Lasagna"]
	if str(table.title) == "Dinner Table" or str(a.get("label", "")).contains("Burger") or str(a.get("label", "")).contains("Grill"):
		dishes = ["Hot Dogs", "Burgers", "Burgers", "BBQ Ribs", "BBQ Ribs", "Gourmet Burgers"]
	var dish: String = dishes[clampi(int(q), 0, dishes.size() - 1)]
	meal = {"table": table, "servings": n, "quality": q, "cook": cook.display_name(), "dish": dish,
		"expires": Game.total_minutes() + MEAL_SPOILS, "plates": [], "node": null}
	_spawn_plates(table, n)
	Game.notify.emit("%s served %s: %d serving%s on the %s" % [cook.display_name(), dish, n, "" if n == 1 else "s", str(table.title).to_lower()], "plate")
	cook._say("Dinner's ready!", "plate")
	stats["meals"] = int(stats.get("meals", 0)) + 1
	_call_to_meal(cook if cook_ate else null, humans, table)


## Call to meal: hungry family drop what free will had them doing.
func _call_to_meal(skip, humans: Array, table) -> void:
	for ag in humans:
		if ag == skip:
			continue
		if float(ag.member.needs.get("hunger", 1.0)) > 0.7:
			continue
		if ag.order.get("action", {}).get("id", "") == "meal" or ag.queue.any(func(q2): return q2.get("action", {}).get("id", "") == "meal"):
			continue   # already on the way
		if ag.phase != "idle" and (not ag.order.get("auto", false) or ag.order.get("forced", false)):
			continue
		if ag.queue.any(func(q2): return not q2.get("auto", false)):
			continue
		var o := {"action": meal_action(), "target": table, "auto": true}
		if ag.phase == "idle":
			ag.command(o)
		else:
			ag.queue.push_front(o)
			ag.cancel_current()
		if OS.has_environment("VIMS_PLAYTEST"):
			print("  call to meal: %s -> %s (%s)" % [ag.display_name(), ag.current_label(), ag.phase])


func _meal_table(cook) -> Node:
	var best = null
	var bd := INF
	var p: Vector3 = cook.actor.global_position
	for it in interactables:
		if not is_instance_valid(it) or not str(it.title) in MEAL_TABLES:
			continue
		var c: Vector3 = it.global_transform * it.look_at_spot
		var d := _flat(c, p) + absf(c.y - p.y) * 3.0
		if d < bd:
			bd = d
			best = it
	return best


func eat_serving() -> void:
	if meal.is_empty():
		return
	meal.servings = int(meal.servings) - 1
	var plates: Array = meal.plates
	if not plates.is_empty():
		var pl = plates.pop_back()
		if is_instance_valid(pl):
			pl.queue_free()
	if int(meal.servings) <= 0:
		clear_meal()


func clear_meal() -> void:
	if meal.is_empty():
		return
	var nd = meal.get("node")
	if nd != null and is_instance_valid(nd):
		nd.queue_free()
	meal = {}


static var _plate_mesh: ArrayMesh
static var _food_meshes: Array = []


func _spawn_plates(table: Node, n: int) -> void:
	if location == null:
		return
	if _plate_mesh == null:
		var vb := VoxelBuilder.new()
		vb.jitter = 0.03
		var white := Color("f4efe6")
		for x in 7:
			for z in 7:
				var dx := absf(x - 3.0)
				var dz := absf(z - 3.0)
				if dx + dz > 5.0:
					continue
				vb.set_v(Vector3i(x, 0, z), white)
				if dx + dz >= 4.0 or maxf(dx, dz) >= 3.0:
					vb.set_v(Vector3i(x, 1, z), white.darkened(0.04))
		_plate_mesh = vb.build(0.035, Vector3(3.5, 0, 3.5))
		for cols in [[Color("e9b23a"), Color("f2cf5b"), Color("5ea544")], [Color("b5512e"), Color("d9793c"), Color("6fb34f")], [Color("8a4a2a"), Color("c7843e"), Color("e8d27a")]]:
			var fb := VoxelBuilder.new()
			fb.jitter = 0.08
			for x in range(2, 5):
				for z in range(2, 5):
					fb.set_v(Vector3i(x, 1, z), cols[(x + z) % 2])
			fb.set_v(Vector3i(3, 2, 3), cols[1])
			fb.set_v(Vector3i(2, 2, 3), cols[2])
			fb.set_v(Vector3i(4, 1, 2), cols[2])
			_food_meshes.append(fb.build(0.035, Vector3(3.5, 0, 3.5)))
	var root: Node3D = meal.get("node")
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "FamilyMeal"
		location.add_child(root)
		meal.node = root
	var half := _box_half(table)
	var c: Vector3 = table.global_transform * table.look_at_spot
	var top := c.y + half.y + 0.005
	var bx: Vector3 = table.global_transform.basis.x.normalized()
	var bz: Vector3 = table.global_transform.basis.z.normalized()
	var long_ax := bx if half.x >= half.z else bz
	var short_ax := bz if half.x >= half.z else bx
	var ll := maxf(half.x, half.z)
	var sl := minf(half.x, half.z)
	var plates: Array = meal.get("plates", [])
	var first := plates.size()
	n += first
	for k in range(first, n):
		# Four place settings: two along each long side.
		var t := (-0.25 if (k % 4) < 2 else 0.25)
		var side := 1.0 if k % 2 == 0 else -1.0
		var pos := c + long_ax * t * ll * 1.3 + short_ax * side * sl * 0.5
		pos.y = top
		var pl := Node3D.new()
		root.add_child(pl)
		pl.global_position = pos
		var mi := MeshInstance3D.new()
		mi.mesh = _plate_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pl.add_child(mi)
		var fi := MeshInstance3D.new()
		fi.mesh = _food_meshes[int(meal.get("quality", 0.0)) % _food_meshes.size()]
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pl.add_child(fi)
		plates.append(pl)
	meal.plates = plates


# =================================================================== careers, bills, carpool

## Job / bill rows the sim layer adds to objects: Find a Job / Quit Job on
## the computer, Pay Bills on the computer and the mailbox.
func career_rows(it: Node, member: Dictionary) -> Array:
	var out: Array = []
	var title := str(it.get("title"))
	var kind: String = member.get("kind", "adult")
	if kind != "adult":
		return out
	if title == "Computer":
		var c: Dictionary = member.get("career", {})
		if c.is_empty():
			out.push_front({"id": "find_job", "label": "Find a Job", "icon": "laptop", "minutes": 0.0, "pose": "type"})
		else:
			out.append({"id": "find_job", "label": "Change Jobs", "icon": "laptop", "minutes": 0.0, "pose": "type"})
			out.append({"id": "quit_job", "label": "Quit Job", "icon": "dots", "minutes": 5.0, "pose": "type", "who": ["adult"]})
		if Game.has_bills():
			out.append({"id": "bills", "label": "Pay Bills Online ($%d)" % Game.bills_due_total(), "icon": "bill", "minutes": 15.0,
				"pose": "type", "money": -Game.bills_due_total(), "task": "Pay Bills", "who": ["adult"]})
	elif title == "Mailbox":
		if Game.has_bills():
			out.append({"id": "bills", "label": "Pay Bills ($%d)" % Game.bills_due_total(), "icon": "bill", "minutes": 8.0,
				"pose": "idle", "money": -Game.bills_due_total(), "task": "Pay Bills", "who": ["adult"]})
	return out


## The home mailbox becomes tappable (it's part of the lot's merged mesh).
func _add_mailbox() -> void:
	if not MAILBOX.has(loc_name) or location == null:
		return
	var p: Vector3 = MAILBOX[loc_name]
	var holder := Node3D.new()
	holder.name = "MailboxSpot"
	location.add_child(holder)
	holder.position = p
	var spot := Vector3(0, 0, -0.55)
	if nav:
		# Stand on the nearest reachable floor on the house side.
		var c := nav.nearest_open(0, nav.cell_of(p + spot), 10)
		if c.x >= 0:
			spot = nav.center_of(0, c) - p
	var it := Interactable.attach(holder, "Mailbox", [
		{"id": "check_mail", "label": "Check Mail", "icon": "email", "minutes": 4.0, "pose": "idle", "needs": {"fun": 0.02}, "who": ["adult", "child"]},
	], Vector3(0.5, 1.25, 0.6), Vector3(0.19, 0.62, 0.25), spot)
	it.name = "Mailbox"
	# Red flag up while bills wait in the mailbox.
	var vb := VoxelBuilder.new()
	vb.box(Vector3i(0, 0, 0), Vector3i(1, 5, 1), Color("3a3f4a"))
	vb.box(Vector3i(0, 3, 1), Vector3i(1, 2, 3), Color("e2412f"))
	_mail_flag = MeshInstance3D.new()
	_mail_flag.name = "MailFlag"
	_mail_flag.mesh = vb.build(0.0625)
	_mail_flag.position = Vector3(0.38, 0.86, 0.1)
	holder.add_child(_mail_flag)
	_update_mail_flag()


var _mail_flag: MeshInstance3D


func _update_mail_flag() -> void:
	if _mail_flag != null and is_instance_valid(_mail_flag):
		_mail_flag.visible = Game.has_bills()


## Floor spot to leave the lot from (front door / street side), reachable
## from `from` if possible.
func exit_spot(from: Vector3) -> Vector3:
	var p: Vector3 = EXITS.get(loc_name, Vector3(0, 0, 6))
	if nav == null:
		return p
	if not nav.in_bounds(p):
		var m := nav.cs * 0.5
		p.x = clampf(p.x, nav.ox + m, nav.ox + nav.w * nav.cs - m)
		p.z = clampf(p.z, nav.oz + m, nav.oz + nav.h * nav.cs - m)
	var c := nav.approach_cell(0, nav.cell_of(p), -1, 96)
	if c.x < 0:
		c = nav.nearest_open(0, nav.cell_of(p), 40)
	if c.x < 0:
		return from
	return nav.center_of(0, c)


## A carpool (or school bus) pulls up at the curb by `at`, waits and leaves.
func carpool(at: Vector3, kind: String, wait: float) -> void:
	if location == null:
		return
	var car = Carpool.new()
	car.kind = kind
	var curb: Vector3 = at + CURB.get(loc_name, Vector3(0, 0, 1.6))
	curb.y = 0.0
	car.stop = curb
	car.dir = Vector3(1, 0, 0)
	car.wait = wait
	location.add_child(car)
	stats["carpools"] = int(stats.get("carpools", 0)) + 1


func on_shift_done(ag, pay: int) -> void:
	if pay > 0:
		Wishes.on_action(ag, {"id": "work_shift"}, pay)
	if Careers.is_school(ag.member.get("career", {})) and Careers.grade(float(ag.member.career.perf)) in ["A", "A+"]:
		Wishes.on_career(ag, "grade")


## A chance card as a two-row menu (title: who and where).
func open_chance(ag, card: Dictionary) -> void:
	var rows := [{"id": "chance_yes", "label": card.yes_label, "icon": card.get("icon", "laptop")},
		{"id": "chance_no", "label": card.no_label, "icon": "dots"}]
	var vs: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1672, 941)
	open_menu.call_deferred("%s at Work" % ag.display_name(), rows, {"type": "chance", "agent": ag}, vs * Vector2(0.42, 0.3))


## The computer a home worker uses (null when this lot has none).
func home_desk(_ag) -> Node:
	for it in interactables:
		if is_instance_valid(it) and str(it.title) == "Computer" and townie_of(it) == "":
			return it
	return null


func on_promotion(ag) -> void:
	Wishes.on_career(ag, "promo")
