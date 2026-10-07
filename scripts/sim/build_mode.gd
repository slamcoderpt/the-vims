extends Node
## Build / Buy / Decorate modes (touch first).
##   Buy, Decorate, Build: the catalogue opens in the action menu by category
##     (Seating, Surfaces... / Plants, Lighting, Rugs / Walls, Floor Tiles,
##     Garden); pick an item and a ghost appears on the floor grid in the
##     middle of the screen. Drag the ghost (or tap the floor) to move it; tap
##     the ghost for Place / Rotate / Cancel.
##   Build > Walls is a wall tool (Sims 3): drag a finger across the floor to
##     lay a straight run of wall sections (each 1 m, snapped to the grid,
##     paid per section); a tap still moves the single ghost.
##   Any mode: tap a bought item for Move / Rotate / Sell. Walls block paths;
##     floor tiles and rugs are walked over.
## The clock pauses while a build mode is open (as in The Sims).
## Bought objects persist per location in Game.placed and are Interactables
## with their catalogue actions, registered as NavGrid obstacles.

const Catalog := preload("res://scripts/sim/catalog.gd")
const PropLib := preload("res://scripts/props/prop_lib.gd")
const SELL_BACK := 0.85

var world   # SimWorld
var mode := ""
var ghost: Node3D
var ghost_mesh: MeshInstance3D
var ghost_item: Dictionary = {}
var ghost_rot := 0
var ghost_pos := Vector3.ZERO
var ghost_valid := false
var moving_uid := -1
var _moving_entry: Dictionary = {}
var dragging := false
var nodes := {}   # uid -> Node3D
var grid: MeshInstance3D
var _saved_speed := 1
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _last_menu_pos := Vector2(170, 260)
## Wall tool drag: where the finger went down (INF = none), whether it has
## become a run, and the sections the run would build [{pos, rot, ok}].
var _run_start := Vector3.INF
var _run_active := false
var run_segs: Array = []
var _run_pool: Array = []   # Node3D previews, reused
const RUN_MAX := 24
const RUN_START_M := 0.35


func _ready() -> void:
	_mat_ok = _ghost_mat(Color(0.55, 1.0, 0.6, 0.62))
	_mat_bad = _ghost_mat(Color(1.0, 0.4, 0.35, 0.62))


static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


# =================================================================== mode

func is_active() -> bool:
	return mode != ""


func enter(m: String) -> void:
	if mode == "":
		_saved_speed = Game.speed if Game.speed > 0 else 1
		Game.speed = 0
	mode = m
	_show_grid(true)
	open_catalog()
	if m == "build":
		Game.notify.emit("Walls, floors and garden · tap a bought item to move or sell it", "hammer")


func exit() -> void:
	if mode == "":
		return
	cancel_ghost()
	mode = ""
	dragging = false
	_lock_camera(false)
	_show_grid(false)
	Game.speed = _saved_speed


func open_catalog(at := Vector2.INF, sub := "") -> void:
	var cat := mode if mode in ["buy", "decorate", "build"] else "buy"
	var title: String = {"buy": "Buy", "decorate": "Decorate", "build": "Build"}[cat]
	var pos := at if at != Vector2.INF else Vector2(170, 260)
	_last_menu_pos = pos
	if sub == "":
		world.open_menu(title, Catalog.category_rows(cat), {"type": "catalog"}, pos)
	else:
		for c in Catalog.CATEGORIES.get(cat, []):
			if c[0] == sub:
				title = c[1]
		world.open_menu(title, Catalog.menu_rows(cat, sub), {"type": "catalog"}, pos)


# =================================================================== input (from SimWorld)

func tap(screen: Vector2) -> void:
	if ghost:
		var gp := _ghost_screen()
		if gp != Vector2.INF and gp.distance_to(screen) < _ghost_radius_px():
			_open_ghost_menu(screen)
			return
		var g: Dictionary = world.ground_point(screen)
		if not g.is_empty():
			_move_ghost(g.pos)
		return
	var it = world.pick_interactable(screen)
	if it != null and it.has_meta("placed_uid"):
		_open_placed_menu(it.get_meta("placed_uid"), screen)
		return
	if it != null:
		Game.notify.emit("Built-in items can't be moved", "hammer")
		world.say_selected("Only bought items can move", "hammer")
		return
	var fl := _floor_item_at(screen)
	if fl >= 0:
		_open_placed_menu(fl, screen)
		return
	open_catalog(screen)


## Returns true if the press starts a ghost drag (camera won't pan).
func press(screen: Vector2) -> bool:
	if ghost == null:
		return false
	if is_wall_tool():
		var g: Dictionary = world.ground_point(screen)
		if not g.is_empty():
			_run_start = g.pos
			_run_active = false
			dragging = true
			_lock_camera(true)
			return true
	var gp := _ghost_screen()
	if gp != Vector2.INF and gp.distance_to(screen) < _ghost_radius_px():
		dragging = true
		_lock_camera(true)
		return true
	return false


func drag(screen: Vector2) -> void:
	if not dragging or ghost == null:
		return
	var g: Dictionary = world.ground_point(screen)
	if _run_start != Vector3.INF:
		if g.is_empty():
			return
		var d := Vector2(g.pos.x - _run_start.x, g.pos.z - _run_start.z).length()
		if not _run_active and d > RUN_START_M:
			_run_active = true
			ghost.visible = false
		if _run_active:
			update_run(g.pos)
		return
	if not g.is_empty():
		_move_ghost(g.pos)


func release() -> void:
	if _run_active:
		commit_run()
	_run_start = Vector3.INF
	_run_active = false
	if dragging:
		dragging = false
		_lock_camera(false)


# =================================================================== wall tool (drag to build)

func is_wall_tool() -> bool:
	return ghost != null and moving_uid < 0 and ghost_item.get("sub", "") == "walls"


## Lay out a straight run of wall sections from the press point to p (the
## longer axis wins, like the Sims wall tool), previewed green / red.
func update_run(p: Vector3) -> void:
	var s := _run_start
	s.x = roundf(s.x / 0.5) * 0.5
	s.z = roundf(s.z / 0.5) * 0.5
	var dx := p.x - s.x
	var dz := p.z - s.z
	var along_x := absf(dx) >= absf(dz)
	var ln := absf(dx) if along_x else absf(dz)
	var n := clampi(int(roundf(ln)), 1, RUN_MAX)
	var sg := signf(dx if along_x else dz)
	if sg == 0.0:
		sg = 1.0
	var rot := 0 if along_x else 1
	run_segs.clear()
	for k in n:
		var off := (k + 0.5) * sg
		var c := s + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		var q := _snap(ghost_item, rot, c)
		var box := _box(ghost_item, rot, q)
		run_segs.append({"pos": q, "rot": rot, "ok": _can_place(ghost_item, box) and not _covers_sim(box)})
	while _run_pool.size() < run_segs.size():
		var h := Node3D.new()
		h.name = "WallRun%d" % _run_pool.size()
		var mi: MeshInstance3D = ghost_mesh.duplicate()
		h.add_child(mi)
		world.location.add_child(h)
		_run_pool.append(h)
	for k in _run_pool.size():
		var h: Node3D = _run_pool[k]
		if k >= run_segs.size():
			h.visible = false
			continue
		var sgm: Dictionary = run_segs[k]
		h.visible = true
		h.global_position = sgm.pos + Vector3(0, 0.02, 0)
		h.rotation.y = sgm.rot * PI * 0.5
		(h.get_child(0) as MeshInstance3D).material_override = _mat_ok if sgm.ok else _mat_bad
	if grid:
		grid.global_position = Vector3(s.x, s.y + 0.015, s.z)


## Build every placeable section of the run (paid per section; stops when
## the money runs out; skips sections that would trap someone).
func commit_run() -> int:
	var price: int = ghost_item.get("price", 0)
	var built := 0
	var trapped := ""
	var broke := false
	for sgm in run_segs:
		if not sgm.ok:
			continue
		var box := _box(ghost_item, sgm.rot, sgm.pos)
		var who := _blocks_route(box)
		if who != "":
			trapped = who
			continue
		if not Game.add_money(-price):
			broke = true
			break
		var entry := {"uid": Game.next_uid(), "item": ghost_item.id, "pos": sgm.pos, "rot": sgm.rot}
		_entries().append(entry)
		_spawn(entry)
		_push_sims(box)
		built += 1
	_clear_run()
	if ghost:
		ghost.visible = true
	if built > 0:
		Game.notify.emit("Built %d wall section%s · $%d" % [built, "" if built == 1 else "s", built * price], "hammer")
		Game.furniture_changed.emit()
	if broke:
		Game.notify.emit("Not enough money for the rest of the wall", "money")
	elif trapped != "":
		Game.notify.emit("Left a gap so %s isn't trapped" % trapped, "dots")
	elif built == 0:
		Game.notify.emit("Can't build a wall there", "dots")
	return built


func _clear_run() -> void:
	run_segs.clear()
	for h in _run_pool:
		if is_instance_valid(h):
			h.queue_free()
	_run_pool.clear()


func _lock_camera(v: bool) -> void:
	if world.camera_rig and "input_locked" in world.camera_rig:
		world.camera_rig.input_locked = v


# =================================================================== menu results

func on_menu(ctx: Dictionary, action: Dictionary) -> void:
	match ctx.get("type", ""):
		"catalog":
			# Deferred: the HUD hides its menu right after reporting the
			# chosen row, which would hide the next level straight away.
			if action.has("subcat"):
				open_catalog.call_deferred(_last_menu_pos, action.subcat)
			elif action.has("back"):
				open_catalog.call_deferred(_last_menu_pos)
			else:
				start_ghost(action.get("item", ""))
		"ghost":
			match action.get("id", ""):
				"place": place_ghost()
				"rotate": rotate_ghost()
				"cancel": cancel_ghost()
		"placed":
			var uid: int = action.get("uid", -1)
			match action.get("id", ""):
				"move": move_placed(uid)
				"rotate": rotate_placed(uid)
				"sell": sell_placed(uid)


func _open_ghost_menu(screen: Vector2) -> void:
	var price: int = ghost_item.get("price", 0)
	var place_label := "Place  $%d" % price if moving_uid < 0 else "Place Here"
	world.open_menu(ghost_item.get("label", "Item"), [
		{"id": "place", "label": place_label, "icon": "money" if moving_uid < 0 else "home"},
		{"id": "rotate", "label": "Rotate", "icon": "arrow_up"},
		{"id": "cancel", "label": "Cancel", "icon": "dots"},
	], {"type": "ghost"}, screen)


# =================================================================== ghost

func start_ghost(item_id: String, at := Vector3.INF) -> bool:
	var item := Catalog.get_item(item_id)
	if item.is_empty():
		return false
	cancel_ghost()
	ghost_item = item
	ghost_rot = 0
	ghost = Node3D.new()
	ghost.name = "Ghost"
	ghost_mesh = Catalog.instance(item, false)
	ghost_mesh.set_meta("nav_ignore", true)
	ghost.add_child(ghost_mesh)
	world.location.add_child(ghost)
	var p := at
	if p == Vector3.INF:
		var vs: Vector2 = world.get_viewport().get_visible_rect().size
		var g: Dictionary = world.ground_point(vs * Vector2(0.5, 0.55))
		p = g.get("pos", world.camera_rig.target if world.camera_rig else Vector3.ZERO)
	_move_ghost(p, true)
	if item.get("sub", "") == "walls":
		Game.notify.emit("Drag across the floor to build a wall · tap the ghost for options", "hammer")
	return true


func cancel_ghost() -> void:
	_clear_run()
	_run_start = Vector3.INF
	_run_active = false
	if ghost:
		ghost.queue_free()
		ghost = null
	if moving_uid >= 0:
		# Put the item back where it was.
		_spawn(_moving_entry)
		moving_uid = -1
		_moving_entry = {}
	ghost_item = {}
	dragging = false


func rotate_ghost() -> void:
	if ghost == null:
		return
	ghost_rot = (ghost_rot + 1) % 4
	_move_ghost(ghost_pos)


func _footprint(item: Dictionary, rot: int) -> Vector3:
	var s: Vector3i = Catalog.rotated_size(item, rot)
	return Vector3(s) * Catalog.unit(item)


## World AABB of the footprint centred (x/z) on p, standing on p.y.
func _box(item: Dictionary, rot: int, p: Vector3) -> AABB:
	var fs := _footprint(item, rot)
	return AABB(Vector3(p.x - fs.x * 0.5, p.y, p.z - fs.z * 0.5), fs)


func _snap(item: Dictionary, rot: int, p: Vector3) -> Vector3:
	var fs := _footprint(item, rot)
	var cs: float = world.nav.cs if world.nav else 0.25
	cs = maxf(cs, float(item.get("grid", 0.0)))
	var mn := Vector2(p.x - fs.x * 0.5, p.z - fs.z * 0.5)
	mn = Vector2(roundf(mn.x / cs) * cs, roundf(mn.y / cs) * cs)
	var y := p.y
	if world.nav:
		y = world.nav.floor_y(Vector3(mn.x + fs.x * 0.5, p.y + 0.1, mn.y + fs.z * 0.5))
	return Vector3(mn.x + fs.x * 0.5, y, mn.y + fs.z * 0.5)


func _move_ghost(p: Vector3, find_free := false) -> void:
	if ghost == null:
		return
	var q := _snap(ghost_item, ghost_rot, p)
	ghost_valid = _can_place(ghost_item, _box(ghost_item, ghost_rot, q))
	if find_free and ghost_valid and not ghost_item.get("walk", false) and _covers_sim(_box(ghost_item, ghost_rot, q)):
		ghost_valid = false
	if not ghost_valid and find_free and world.nav:
		# Spiral out to the nearest free spot.
		var cs: float = world.nav.cs
		for r in range(1, 20):
			for k in 16:
				var a := TAU * k / 16.0
				var t := _snap(ghost_item, ghost_rot, p + Vector3(cos(a), 0, sin(a)) * r * cs)
				var tb := _box(ghost_item, ghost_rot, t)
				if _can_place(ghost_item, tb) and not _covers_sim(tb):
					q = t
					ghost_valid = true
					break
			if ghost_valid:
				break
	ghost_pos = q
	ghost.global_position = q + Vector3(0, 0.02 + _lift(ghost_item), 0)
	ghost.rotation.y = ghost_rot * PI * 0.5
	ghost_mesh.material_override = _mat_ok if ghost_valid else _mat_bad
	if grid:
		grid.global_position = Vector3(q.x, q.y + 0.015, q.z)


func _covers_sim(box: AABB) -> bool:
	var g := box.grow(0.25)
	for ag in world.agents:
		if ag and is_instance_valid(ag.actor):
			var p: Vector3 = ag.actor.global_position
			if p.x > g.position.x and p.x < g.end.x and p.z > g.position.z and p.z < g.end.z and absf(p.y - box.position.y) < 1.0:
				return true
	return false


## Sims standing where something was just placed step out of the way.
func _push_sims(box: AABB) -> void:
	var g := box.grow(0.1)
	for ag in world.agents:
		if ag == null or not is_instance_valid(ag.actor):
			continue
		var p: Vector3 = ag.actor.global_position
		if p.x > g.position.x and p.x < g.end.x and p.z > g.position.z and p.z < g.end.z and absf(p.y - box.position.y) < 1.0:
			if ag.phase == "act":
				ag.cancel_current()
			ag.actor.global_position = world._open_spot(p)


func place_ghost() -> bool:
	if ghost == null:
		return false
	if not ghost_valid:
		world.say_selected("Can't place it there", "dots")
		Game.notify.emit("Can't place it there", "dots")
		return false
	if not ghost_item.get("walk", false):
		var who := _blocks_route(_box(ghost_item, ghost_rot, ghost_pos))
		if who != "":
			world.say_selected("That blocks the way", "dots")
			Game.notify.emit("That would trap %s: leave a path" % who, "dots")
			return false
	var price: int = ghost_item.get("price", 0)
	var entry: Dictionary
	if moving_uid >= 0:
		entry = _moving_entry
		entry.pos = ghost_pos
		entry.rot = ghost_rot
		moving_uid = -1
		_moving_entry = {}
	else:
		if not Game.add_money(-price):
			world.say_selected("Not enough money", "money")
			Game.notify.emit("Not enough money", "money")
			return false
		entry = {"uid": Game.next_uid(), "item": ghost_item.id, "pos": ghost_pos, "rot": ghost_rot}
		_entries().append(entry)
		Game.notify.emit("Bought %s" % ghost_item.label, "money")
	ghost.queue_free()
	ghost = null
	ghost_item = {}
	_spawn(entry)
	if not Catalog.get_item(entry.item).get("walk", false):
		_push_sims(_box(Catalog.get_item(entry.item), entry.rot, entry.pos))
	Game.furniture_changed.emit()
	return true


func _open_placed_menu(uid: int, screen: Vector2) -> void:
	var e := _entry(uid)
	var item := Catalog.get_item(e.get("item", ""))
	world.open_menu(item.get("label", "Item"), [
		{"id": "move", "label": "Move", "icon": "hammer", "uid": uid},
		{"id": "rotate", "label": "Rotate", "icon": "arrow_up", "uid": uid},
		{"id": "sell", "label": "Sell  +$%d" % int(item.get("price", 0) * SELL_BACK), "icon": "money", "uid": uid},
	], {"type": "placed"}, screen)


## Floor tiles / rugs sit just above the floor so they never z-fight it.
static func _lift(item: Dictionary) -> float:
	match item.get("proc", ""):
		"floor": return 0.004
		"rug": return 0.03
	return 0.0


## Placement rule: furniture and walls need free floor (NavGrid); floor tiles
## need floor and no other tile in the same square; rugs go anywhere on floor.
## Would an object in `box` cut a household member off from the rest of the
## lot (the stairs, or the others on a one-storey lot)? Returns their name.
func _blocks_route(box: AABB) -> String:
	var nav = world.nav
	if nav == null:
		return ""
	var li: int = nav.level_of(box.position + Vector3(0, 0.05, 0))
	var hubs: Array = []
	for l in nav.links:
		if l.la == li:
			hubs.append(l.a)
		if l.lb == li:
			hubs.append(l.b)
	var on_level: Array = []
	for ag in world.agents:
		if ag and is_instance_valid(ag.actor) and nav.level_of(ag.actor.global_position) == li:
			on_level.append(ag)
	if hubs.is_empty():
		if on_level.size() < 2:
			return ""
		hubs.append(on_level[0].actor.global_position)
	var reach := func(ag) -> bool:
		for h in hubs:
			if ag.actor.global_position.distance_to(h) < 0.3:
				return true
			nav.find_path(ag.actor.global_position, h, true)
			if nav.last_ok:
				return true
		return false
	var before := {}
	for ag in on_level:
		before[ag] = reach.call(ag)
	const PROBE := -999
	nav.add_obstacle(PROBE, box)
	var trapped := ""
	for ag in on_level:
		if before[ag] and not reach.call(ag):
			trapped = ag.display_name()
			break
	nav.remove_obstacle(PROBE)
	return trapped


func _can_place(item: Dictionary, box: AABB) -> bool:
	if world.nav == null:
		return false
	if not item.get("walk", false):
		return world.nav.can_place(box, moving_uid)
	var li: int = world.nav.level_of(box.position + Vector3(0, 0.05, 0))
	for p: Vector3 in [box.get_center(), box.position + Vector3(0.05, 0, 0.05), box.end - Vector3(0.05, 0, 0.05)]:
		if not world.nav.in_bounds(p) or not world.nav.has_floor(li, world.nav.cell_of(p)):
			return false
		if absf(world.nav.floor_y(p, li) - box.position.y) > 0.3:
			return false
	if item.get("proc", "") == "floor":
		var c := box.get_center()
		for e in _entries():
			var other := Catalog.get_item(e.item)
			if other.get("proc", "") == "floor" and e.uid != moving_uid and Vector2(e.pos.x - c.x, e.pos.z - c.z).length() < 0.5 and absf(e.pos.y - box.position.y) < 0.5:
				return false
	return true


## A placed floor tile / rug under the screen point (uid) or -1.
func _floor_item_at(screen: Vector2) -> int:
	var g: Dictionary = world.ground_point(screen)
	if g.is_empty():
		return -1
	var p: Vector3 = g.pos
	var best := -1
	for e in _entries():
		var item := Catalog.get_item(e.item)
		if not item.get("walk", false):
			continue
		var b := _box(item, e.rot, e.pos)
		if p.x >= b.position.x and p.x <= b.end.x and p.z >= b.position.z and p.z <= b.end.z and absf(p.y - b.position.y) < 0.6:
			best = e.uid
			if item.get("proc", "") == "rug":
				return best   # rugs lie on top of tiles
	return best


# =================================================================== placed items

func _entries() -> Array:
	if not Game.placed.has(Game.location):
		Game.placed[Game.location] = []
	return Game.placed[Game.location]


func _entry(uid: int) -> Dictionary:
	for e in _entries():
		if e.uid == uid:
			return e
	return {}


func spawn_saved() -> void:
	nodes.clear()
	for e in _entries():
		_spawn(e)


func _spawn(e: Dictionary) -> void:
	var item := Catalog.get_item(e.item)
	if item.is_empty():
		return
	var n := Node3D.new()
	n.name = "Placed_%d" % e.uid
	world.location.add_child(n)
	n.global_position = e.pos + Vector3(0, _lift(item), 0)
	n.rotation.y = e.rot * PI * 0.5
	var mi := Catalog.instance(item)
	mi.set_meta("nav_ignore", true)
	n.add_child(mi)
	var raw: Vector3i = Catalog.size_of(item)
	var sz := Vector3(raw) * Catalog.unit(item)
	nodes[e.uid] = n
	if item.get("walk", false):
		# Floors / rugs: no collider in live mode (taps go to the floor);
		# build modes find them by footprint (_floor_item_at).
		return
	var use := Vector3(0, 0, sz.z * 0.5 + 0.4) if item.get("use", "front") == "front" else Vector3.ZERO
	var it := Interactable.attach(n, item.label, item.get("actions", []), Vector3(maxf(sz.x, 0.3), maxf(sz.y, 0.3), maxf(sz.z, 0.3)), Vector3(0, sz.y * 0.5, 0), use)
	if item.get("use", "") == "seat":
		it.look_at_spot = Vector3(0, 0, 2.0)
	it.set_meta("placed_uid", e.uid)
	it.name = "Interactable"
	if item.get("light", false):
		PropLib.add_light(n, Vector3(0, sz.y - 0.1, 0), Color(1.0, 0.72, 0.42), 1.0, 3.5, 0.3)
	if world.nav:
		world.nav.add_obstacle(e.uid, _box(item, e.rot, e.pos))
	world.refresh_interactables()


func _despawn(uid: int) -> void:
	if nodes.has(uid):
		var n: Node3D = nodes[uid]
		world.release_object(n.get_node_or_null("Interactable"))
		n.queue_free()
		nodes.erase(uid)
	if world.nav:
		world.nav.remove_obstacle(uid)
	world.refresh_interactables.call_deferred()


func rotate_placed(uid: int) -> bool:
	var e := _entry(uid)
	if e.is_empty():
		return false
	var item := Catalog.get_item(e.item)
	var nr: int = (int(e.rot) + 1) % 4
	var p := _snap(item, nr, e.pos)
	world.nav.remove_obstacle(uid)
	if not _can_place(item, _box(item, nr, p)) and world.nav:
		# Turning a long piece next to a wall: nudge it a little (Sims 3 does
		# the same) before giving up.
		var cs: float = world.nav.cs
		var found := false
		for r in range(1, 4):
			for k in 8:
				var a := TAU * k / 8.0
				var t := _snap(item, nr, e.pos + Vector3(cos(a), 0, sin(a)) * r * cs)
				var tb := _box(item, nr, t)
				if _can_place(item, tb) and not _covers_sim(tb):
					p = t
					found = true
					break
			if found:
				break
	if not _can_place(item, _box(item, nr, p)):
		if not item.get("walk", false):
			world.nav.add_obstacle(uid, _box(item, e.rot, e.pos))
		world.say_selected("No room to turn it", "dots")
		return false
	_despawn(uid)
	e.rot = nr
	e.pos = p
	_spawn(e)
	Game.furniture_changed.emit()
	return true


func move_placed(uid: int) -> bool:
	var e := _entry(uid)
	if e.is_empty():
		return false
	_despawn(uid)
	var item := Catalog.get_item(e.item)
	_moving_entry = e
	moving_uid = uid
	ghost_item = item
	ghost_rot = e.rot
	ghost = Node3D.new()
	ghost.name = "Ghost"
	ghost_mesh = Catalog.instance(item, false)
	ghost.add_child(ghost_mesh)
	world.location.add_child(ghost)
	_move_ghost(e.pos)
	return true


func sell_placed(uid: int) -> bool:
	var e := _entry(uid)
	if e.is_empty():
		return false
	var item := Catalog.get_item(e.item)
	_despawn(uid)
	_entries().erase(e)
	var refund := int(item.get("price", 0) * SELL_BACK)
	Game.add_money(refund)
	Game.notify.emit("Sold %s  +$%d" % [item.label, refund], "money")
	Game.furniture_changed.emit()
	return true


func placed_count() -> int:
	return _entries().size()


# =================================================================== visuals

func _ghost_screen() -> Vector2:
	var cam: Camera3D = world.get_viewport().get_camera_3d()
	if cam == null or ghost == null:
		return Vector2.INF
	var c := ghost.global_position + Vector3(0, 0.35, 0)
	if cam.is_position_behind(c):
		return Vector2.INF
	return cam.unproject_position(c)


func _ghost_radius_px() -> float:
	var cam: Camera3D = world.get_viewport().get_camera_3d()
	if cam == null or ghost == null:
		return 60.0
	var fs := _footprint(ghost_item, ghost_rot)
	var r := maxf(fs.x, fs.z) * 0.6 + 0.2
	var c := ghost.global_position
	var a := cam.unproject_position(c)
	var b := cam.unproject_position(c + cam.global_transform.basis.x * r)
	return clampf(a.distance_to(b), 44.0, 220.0)


func _show_grid(v: bool) -> void:
	if v and grid == null:
		grid = MeshInstance3D.new()
		grid.name = "BuildGrid"
		grid.set_meta("nav_ignore", true)
		var pm := PlaneMesh.new()
		pm.size = Vector2(9, 9)
		grid.mesh = pm
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float cell = 0.25;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(wp.xz / cell - 0.5) - 0.5) / fwidth(wp.xz / cell);
	float line = 1.0 - smoothstep(0.6, 2.2, min(g.x, g.y));
	float fade = 1.0 - smoothstep(2.0, 4.4, length(UV - 0.5) * 9.0);
	ALBEDO = vec3(1.0, 0.98, 0.9);
	ALPHA = (line * 0.75 + 0.06) * fade;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = sh
		grid.material_override = mat
		grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if world.location:
			world.location.add_child(grid)
		var t: Vector3 = world.camera_rig.target if world.camera_rig else Vector3.ZERO
		var fy: float = world.nav.floor_y(t) if world.nav else 0.0
		grid.global_position = Vector3(t.x, fy + 0.015, t.z)
	if grid and not v:
		grid.queue_free()
		grid = null


func on_location_changed() -> void:
	ghost = null
	grid = null
	moving_uid = -1
	_moving_entry = {}
	nodes.clear()
	if mode != "":
		mode = ""
		Game.speed = _saved_speed
