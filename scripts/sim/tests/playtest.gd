extends Node
## Automated end-to-end playtest of the core loop (run: tools/playtest.sh).
## Drives the game through real input events (touches pushed into the
## viewport, HUD menu rows tapped) and checks the simulation state.
## Prints "STEP <name>: PASS|FAIL <detail>" per step and "RESULT PASS|FAIL".
## Screenshots go to <shots>/playtest_NN_<name>.png.

var main: Node
var args := {}
var sim: Node
var hud: Node
var results: Array = []
var shot_dir := "res://shots"
var _shot_n := 0
var _menus: Array = []      # [title, actions]
var _bubbles: Array = []    # data dicts
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	sim = main.sim
	hud = main.hud
	shot_dir = args.get("shots", "res://shots")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	Game.menu_requested.connect(func(t, a, _p): _menus.append([t, a]))
	Game.bubble_requested.connect(func(_an, d): _bubbles.append(d))
	await _frames(4)
	await _run()
	var fails := 0
	for r in results:
		if not r[1]:
			fails += 1
	print("RESULT %s  (%d/%d steps passed, %.1f s)" % ["PASS" if fails == 0 else "FAIL", results.size() - fails, results.size(), (Time.get_ticks_msec() - _t0) / 1000.0])
	get_tree().quit(0 if fails == 0 else 1)


## Sections can be picked with --only=boot,loop,money,autonomy,clock,gohere,build,travel
func _run() -> void:
	var only: Array = []
	if args.has("only"):
		only = (args.only as String).split(",")
	for sec in ["boot", "loop", "money", "autonomy", "clock", "gohere", "build", "travel"]:
		if only.is_empty() or sec in only or sec == "boot":
			await call("_s_" + sec)


func _s_boot() -> void:
	var n_agents := 0
	for a in sim.agents:
		if a:
			n_agents += 1
	_step("boot", n_agents == 4 and sim.nav != null and sim.interactables.size() > 5,
		"agents=%d interactables=%d nav=%s levels=%d" % [n_agents, sim.interactables.size(), str(sim.nav != null), sim.nav.level_y.size() if sim.nav else 0])
	Game.speed = 1


func _s_loop() -> void:
	var lily = _agent("Lily")
	Game.selected = 0
	await _frames(2)
	var lp: Vector3 = (lily.actor.global_position + lily.actor.head_top()) * 0.5
	await _tap_world(lp)
	await _frames(3)
	var plumbob_on: bool = hud != null and hud.get("plumbob") != null and hud.plumbob.active
	_step("select_sim", Game.selected == lily.index, "selected=%d lily=%d plumbob=%s" % [Game.selected, lily.index, str(plumbob_on)])
	await _shot("select")

	# ---------------------------------------------------------------- object menu
	var piano = _find_it("Piano")
	_menus.clear()
	if piano:
		await _tap_world(_it_center(piano))
		await _frames(3)
	var got_menu: bool = not _menus.is_empty() and _menus[-1][0] == "Piano"
	_step("tap_object_menu", got_menu, "menus=%s" % str(_menus.map(func(m): return m[0])))
	await _shot("menu")

	# ---------------------------------------------------------------- choose action
	var fun0: float = lily.member.needs.fun
	var music0: float = Game.skill_level(lily.index, "Music")
	await _choose("Practice")
	await _frames(2)
	_step("choose_action", lily.phase == "walk" and lily.current_label() == "Practice", "phase=%s action=%s path=%d" % [lily.phase, lily.current_label(), lily.path.size()])

	# ---------------------------------------------------------------- walk
	var start: Vector3 = lily.actor.global_position
	Game.speed = 2
	await _wait(1.2)
	await _shot("walk")
	var ok_walk := await _until(func(): return lily.phase == "act", 40.0)
	var moved: float = start.distance_to(lily.actor.global_position)
	_step("sim_walks", ok_walk and moved > 0.5, "moved=%.2f m via %d waypoints, phase=%s" % [moved, lily.path.size(), lily.phase])
	_step("action_pose", lily.actor.pose == "sit_type", "pose=%s seat=%.2f" % [lily.actor.pose, lily.actor.seat_height])

	# ---------------------------------------------------------------- need / skill
	Game.speed = 3
	await _until(func(): return lily.elapsed > 25.0 or lily.phase != "act", 20.0)
	await _shot("acting")
	var fun1: float = lily.member.needs.fun
	_step("need_rises", fun1 > fun0, "fun %.3f -> %.3f" % [fun0, fun1])
	await _until(func(): return lily.phase != "act", 30.0)
	var music1: float = Game.skill_level(lily.index, "Music")
	var chips := _bubbles.filter(func(d): return d.get("kind", "") == "skill" and "Music" in str(d.get("text", "")))
	_step("skill_rises", music1 > music0 and chips.size() > 0, "Music %.3f -> %.3f, chips=%d" % [music0, music1, chips.size()])
	_step("task_completes", _task_done("Build Skill"), "Build Skill done=%s" % str(_task_done("Build Skill")))



func _s_money() -> void:
	var jack = _agent("Jack")
	Game.speed = 2
	await _tap_portrait(jack.index)
	await _frames(3)
	_step("select_portrait", Game.selected == jack.index, "selected=%d" % Game.selected)
	var money0 := Game.money
	var comp = _find_it("Computer")
	_menus.clear()
	await _tap_world(_it_center(comp))
	await _frames(3)
	await _choose("Pay Bills")
	Game.speed = 3
	await _until(func(): return jack.last_done == "bills", 90.0)
	_step("money_spent", Game.money == money0 - 120 and _task_done("Pay Bills"), "money %d -> %d, Pay Bills done=%s" % [money0, Game.money, str(_task_done("Pay Bills"))])
	var money1 := Game.money
	_menus.clear()
	await _tap_world(_it_center(comp))
	await _frames(3)
	await _choose("Work")
	await _until(func(): return jack.last_done == "work", 150.0)
	_step("money_earned", Game.money == money1 + 180, "money %d -> %d, Logic=%.2f" % [money1, Game.money, Game.skill_level(jack.index, "Logic")])



func _s_autonomy() -> void:
	var maya = _agent("Maya")
	maya.cancel_all()
	for k in maya.member.needs:
		maya.member.needs[k] = 0.95
	maya.member.needs.hunger = 0.05
	maya.idle_minutes = 0.0
	var y0: float = maya.actor.global_position.y
	var picked := await _until(func(): return maya.phase != "idle" and maya.order.get("action", {}).get("needs", {}).get("hunger", 0.0) > 0.0, 25.0)
	var act_name: String = maya.current_label()
	var tgt = maya.order.get("target")
	_step("autonomy_lowest_need", picked, "Maya hunger=0.05 -> chose '%s' on %s" % [act_name, str(tgt.title) if tgt else "-"])
	await _until(func(): return maya.phase == "act", 50.0)
	var y1: float = maya.actor.global_position.y
	await _focus(maya.actor.global_position)
	await _shot("autonomy")
	_step("autonomy_arrives", maya.phase == "act", "Maya phase=%s y %.2f -> %.2f (stairs %s)" % [maya.phase, y0, y1, "used" if absf(y1 - y0) > 1.5 else "not needed"])



func _s_clock() -> void:
	var maya = _agent("Maya")
	Game.speed = 0
	await _frames(2)
	var m0 := Game.minutes
	var e0: float = maya.elapsed
	await _wait(1.0)
	var paused_ok: bool = Game.minutes == m0 and maya.elapsed == e0
	Game.speed = 1
	await _wait(0.6)
	var m1 := Game.minutes
	Game.speed = 3
	await _wait(0.6)
	var fast_ok: bool = Game.minutes - m1 > (m1 - m0) * 2.0
	_step("clock_pause_play_fast", paused_ok and Game.minutes > m0 and fast_ok, "paused=%s play=+%.1f fast=+%.1f min" % [str(paused_ok), m1 - m0, Game.minutes - m1])
	Game.speed = 1



func _s_gohere() -> void:
	var lily = _agent("Lily")
	Game.selected = lily.index
	await _focus(lily.actor.global_position)
	var li: int = sim.nav.level_of(lily.actor.global_position)
	var gc: Vector2i = sim.nav.nearest_open(li, sim.nav.cell_of(lily.actor.global_position + Vector3(1.2, 0, 1.0)))
	var gp: Vector3 = sim.nav.center_of(li, gc)
	await _tap_world(gp)
	await _frames(2)
	var go_ok: bool = lily.order.get("action", {}).get("id", "") == "go_here"
	await _until(func(): return lily.phase == "idle", 20.0)
	_step("go_here", go_ok and _flat(lily.actor.global_position, gp) < 0.4, "dist to target %.2f" % _flat(lily.actor.global_position, gp))



func _s_build() -> void:
	var lily = _agent("Lily")
	Game.selected = lily.index
	var money_b := Game.money
	_menus.clear()
	Game.mode = "buy"
	await _frames(3)
	var buy_menu: bool = not _menus.is_empty() and _menus[-1][0] == "Buy"
	var paused_in_buy := Game.speed == 0
	await _choose("Armchair")
	await _frames(2)
	var b = sim.build
	var has_ghost: bool = b.ghost != null
	if has_ghost and not b.ghost_valid:
		# Tap an open spot near the camera target.
		var tl: int = sim.nav.level_of(main.camera_rig.target - Vector3(0, 0.7, 0))
		var c: Vector2i = sim.nav.nearest_open(tl, sim.nav.cell_of(main.camera_rig.target))
		await _tap_world(sim.nav.center_of(tl, c))
	await _frames(2)
	if b.ghost:
		await _focus(b.ghost.global_position)
		print("  ghost at %s valid=%s visible=%s lily at %s" % [str(b.ghost.global_position), str(b.ghost_valid), str(b.ghost.is_visible_in_tree()), str(lily.actor.global_position)])
	await _shot("buy_ghost")
	_menus.clear()
	if has_ghost:
		await _tap_world(b.ghost.global_position + Vector3(0, 0.35, 0), false)
		await _frames(2)
	await _choose("Place")
	await _frames(2)
	var placed_ok: bool = b.placed_count() == 1 and Game.money == money_b - 350 and sim.nav.obstacles.size() == 1
	_step("buy_place", buy_menu and paused_in_buy and has_ghost and placed_ok,
		"menu=%s paused=%s ghost=%s placed=%d money %d -> %d obstacles=%d" % [str(buy_menu), str(paused_in_buy), str(has_ghost), b.placed_count(), money_b, Game.money, sim.nav.obstacles.size()])
	await _shot("placed")

	# ---------------------------------------------------------------- build: rotate
	Game.mode = "build"
	await _frames(2)
	var uid: int = Game.placed[Game.location][0].uid if b.placed_count() > 0 else -1
	var rot0: int = Game.placed[Game.location][0].rot if uid >= 0 else -1
	_menus.clear()
	if uid >= 0:
		await _tap_world(b.nodes[uid].global_position + Vector3(0, 0.45, 0), false)
		await _frames(2)
	await _choose("Rotate")
	await _frames(2)
	var rot1: int = Game.placed[Game.location][0].rot if b.placed_count() > 0 else -1
	_step("build_rotate", uid >= 0 and rot1 != rot0, "rot %d -> %d" % [rot0, rot1])

	# ---------------------------------------------------------------- use the bought item in live mode
	Game.mode = "live"
	await _frames(2)
	Game.speed = 2
	if uid >= 0:
		_menus.clear()
		await _tap_world(b.nodes[uid].global_position + Vector3(0, 0.45, 0), false)
		await _frames(2)
		await _choose("Relax")
		await _until(func(): return lily.phase == "act", 30.0)
	_step("use_bought_item", lily.phase == "act" and lily.current_label() == "Relax", "phase=%s action=%s pose=%s" % [lily.phase, lily.current_label(), lily.actor.pose])
	await _shot("use_bought")

	# ---------------------------------------------------------------- build: sell
	Game.mode = "build"
	await _frames(2)
	var money_s := Game.money
	_menus.clear()
	if uid >= 0 and b.nodes.has(uid):
		await _tap_world(b.nodes[uid].global_position + Vector3(0, 0.45, 0), false)
		await _frames(2)
	await _choose("Sell")
	await _frames(2)
	_step("build_sell", b.placed_count() == 0 and Game.money == money_s + int(350 * 0.85) and sim.nav.obstacles.is_empty() and lily.phase != "act",
		"money %d -> %d placed=%d lily=%s" % [money_s, Game.money, b.placed_count(), lily.phase])
	Game.mode = "live"
	await _frames(2)



func _s_travel() -> void:
	var jack = _agent("Jack")
	Game.speed = 1
	_menus.clear()
	Game.mode = "manage"
	await _frames(3)
	var travel_menu: bool = not _menus.is_empty() and _menus[-1][0] == "Travel"
	await _choose("Grocery Market")
	await _frames(6)
	var n_m := 0
	for a in sim.agents:
		if a:
			n_m += 1
	_step("travel_market", Game.location == "market" and sim.loc_name == "market" and n_m == 4 and travel_menu,
		"location=%s agents=%d tasks=%s" % [Game.location, n_m, str(Game.tasks.map(func(t): return t.title))])
	await _shot("market")

	# One action at the market: pay at the checkout.
	jack = _agent("Jack")
	jack.cancel_all()
	# Content family: nobody needs to spend money on their own during this check.
	for m in Game.household:
		for k in m.needs:
			m.needs[k] = maxf(m.needs[k], 0.8)
	Game.selected = jack.index
	var cashier = _find_it("Cashier")
	var money_m := Game.money
	if cashier:
		_menus.clear()
		await _tap_world(_it_center(cashier))
		await _frames(2)
		await _choose("Pay at Checkout")
		Game.speed = 3
		await _until(func(): return jack.last_done == "pay", 40.0)
	_step("market_checkout", Game.money == money_m - 52 and _task_done("Pay at Checkout"), "money %d -> %d task=%s" % [money_m, Game.money, str(_task_done("Pay at Checkout"))])
	await _shot("market_checkout")

	# ---------------------------------------------------------------- the other lots
	for dest in [["festival", "Autumn Festival"], ["backyard", "Backyard BBQ"]]:
		Game.speed = 1
		_menus.clear()
		Game.mode = "manage"
		await _frames(3)
		await _choose(dest[1])
		await _frames(6)
		var n := 0
		for a in sim.agents:
			if a:
				n += 1
		# Everyone can walk somewhere: path from Jack to a spot 2 m away.
		var j = _agent("Jack")
		var p0: Vector3 = j.actor.global_position
		var path: PackedVector3Array = sim.nav.find_path(p0, p0 + Vector3(2.0, 0, 1.5))
		_step("travel_" + dest[0], Game.location == dest[0] and n == 4 and path.size() >= 1,
			"location=%s agents=%d interactables=%d nav %dx%d path=%d" % [Game.location, n, sim.interactables.size(), sim.nav.w, sim.nav.h, path.size()])
		Game.speed = 3
		await _wait(3.0)
		await _shot(dest[0])

	# ---------------------------------------------------------------- travel home
	Game.speed = 1
	# Go back to the market first so "Return Home" can tick off there.
	_menus.clear()
	Game.mode = "manage"
	await _frames(3)
	await _choose("Grocery Market")
	await _frames(6)
	var kept_market := _task_done("Pay at Checkout")
	_menus.clear()
	Game.mode = "manage"
	await _frames(3)
	await _choose("Go Home")
	await _frames(6)
	var mk: Array = Game.location_tasks.get("market", [])
	var rh := false
	for t in mk:
		if t.title == "Return Home" and t.done:
			rh = true
	var loop_ran: bool = not args.has("only") or "loop" in str(args.only)
	var kept_home: bool = _task_done("Build Skill") or not loop_ran
	_step("travel_home", Game.location == "home" and sim.loc_name == "home" and rh and kept_home and kept_market,
		"location=%s market 'Return Home' done=%s, tasks kept: market=%s home=%s" % [Game.location, str(rh), str(kept_market), str(kept_home)])
	await _shot("home_again")


# =================================================================== helpers

func _step(step_name: String, ok: bool, detail := "") -> void:
	results.append([step_name, ok])
	print("STEP %-22s %s  %s" % [step_name + ":", "PASS" if ok else "FAIL", detail])


func _agent(n: String):
	for a in sim.agents:
		if a and a.display_name() == n:
			return a
	return null


func _find_it(title: String):
	for it in sim.interactables:
		if is_instance_valid(it) and it.title == title:
			return it
	return null


func _it_center(it) -> Vector3:
	return it.global_transform * it.look_at_spot


func _task_done(title: String) -> bool:
	for t in Game.tasks:
		if t.title == title:
			return t.done
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, timeout_s: float) -> bool:
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return true


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


## Centre the camera on p (keeps the camera height relative to the floor).
func _focus(p: Vector3) -> void:
	var rig = main.camera_rig
	var dy: float = rig.target.y - (sim.nav.floor_y(rig.target) if sim.nav else 0.0)
	rig.apply({"target": Vector3(p.x, p.y + clampf(dy, 0.5, 1.5), p.z)})
	await _frames(2)


func _screen_ok(sp: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	return sp.x > 40 and sp.y > 40 and sp.x < vs.x - 40 and sp.y < vs.y - 40 and not sim._over_hud(sp)


## Tap the screen where world point p is (pans the camera there first when it
## is off-screen or under the HUD, like a player would).
func _tap_world(p: Vector3, allow_focus := true) -> void:
	var cam := _cam()
	var sp := cam.unproject_position(p)
	if allow_focus and (cam.is_position_behind(p) or not _screen_ok(sp)):
		await _focus(p)
		sp = _cam().unproject_position(p)
	_touch(sp)


func _touch(sp: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = sp
	down.pressed = true
	get_viewport().push_input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = sp
	up.pressed = false
	get_viewport().push_input(up)


func _tap_portrait(i: int) -> void:
	var ps = hud.get("_portraits") if hud else null
	if ps is Array and i < ps.size():
		_touch((ps[i] as Control).get_global_rect().get_center())
	else:
		Game.selected = i
	await _frames(2)


## Tap the HUD action-menu row whose label starts with `label`.
func _choose(label: String) -> void:
	await _frames(2)
	var menu = hud.get("menu") if hud else null
	if menu and menu.visible:
		var acts: Array = menu.actions
		var rows: Array = menu.get("_rows")
		for i in acts.size():
			var l: String = acts[i].get("label", "") if acts[i] is Dictionary else str(acts[i])
			if l.begins_with(label) and i < rows.size():
				await _frames(4)   # let the open tween finish
				_touch((rows[i] as Control).get_global_rect().get_center())
				await _frames(1)
				return
	# HUD has no menu (or it isn't open): answer like the HUD would.
	if not _menus.is_empty():
		var m: Array = _menus[-1]
		for a in m[1]:
			if str(a.get("label", "")).begins_with(label):
				print("  (menu row '%s' chosen directly: HUD menu not visible)" % label)
				Game.action_chosen.emit(m[0], a)
				return
	print("  (no menu row '%s')" % label)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/playtest_%02d_%s.png" % [shot_dir, _shot_n, tag]
	img.save_png(path)
	print("  shot ", path)
