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


## Sections can be picked with --only=boot,loop,money,unlocks,mood,queue,autonomy,clock,gohere,build,social,townies,travel
func _run() -> void:
	var only: Array = []
	if args.has("only"):
		only = (args.only as String).split(",")
	for sec in ["boot", "loop", "money", "unlocks", "mood", "queue", "autonomy", "meal", "wishes", "clock", "gohere", "build", "social", "townies", "travel", "save"]:
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
	var ok_walk := await _until_game(func(): return lily.phase == "act", 60.0)
	var moved: float = start.distance_to(lily.actor.global_position)
	_step("sim_walks", ok_walk and moved > 0.5, "moved=%.2f m via %d waypoints, phase=%s" % [moved, lily.path.size(), lily.phase])
	_step("action_pose", lily.actor.pose == "sit_type", "pose=%s seat=%.2f" % [lily.actor.pose, lily.actor.seat_height])

	# ---------------------------------------------------------------- need / skill
	Game.speed = 3
	await _until_game(func(): return lily.elapsed > 25.0 or lily.phase != "act", 60.0)
	await _shot("acting")
	var fun1: float = lily.member.needs.fun
	_step("need_rises", fun1 > fun0, "fun %.3f -> %.3f" % [fun0, fun1])
	await _until_game(func(): return lily.phase != "act", 90.0)
	var music1: float = Game.skill_level(lily.index, "Music")
	var chips := _bubbles.filter(func(d): return d.get("kind", "") == "skill" and "Music" in str(d.get("text", "")))
	_step("skill_rises", music1 > music0 and chips.size() > 0, "Music %.3f -> %.3f, chips=%d" % [music0, music1, chips.size()])
	_step("task_completes", _task_done("Build Skill"), "Build Skill done=%s" % str(_task_done("Build Skill")))
	_step("positive_moodlets", Game.has_moodlet(lily.index, "had_fun") and Game.has_moodlet(lily.index, "accomplished"),
		"Lily moodlets=%s mood=%.1f (%s)" % [str(Game.moodlets(lily.index).map(func(m): return m.label)), Game.mood(lily.index), Game.mood_band(lily.index)])
	_step("skill_pace", music1 - music0 < 0.5 and music1 - music0 > 0.05, "45 min of practice = %.2f of a level (x%.2f mood)" % [music1 - music0, Game.mood_mult(lily.index)])



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
	await _until_game(func(): return jack.last_done == "bills", 240.0)
	_step("money_spent", Game.money == money0 - 120 and _task_done("Pay Bills"), "money %d -> %d, Pay Bills done=%s" % [money0, Game.money, str(_task_done("Pay Bills"))])
	var money1 := Game.money
	_menus.clear()
	await _tap_world(_it_center(comp))
	await _frames(3)
	await _choose("Work")
	await _until_game(func(): return jack.last_done == "work", 400.0)
	_step("money_earned", Game.money == money1 + jack.last_pay and jack.last_pay >= 108 and jack.last_pay <= 252,
		"money %d -> %d (base pay 180, mood-scaled = %d, mood now %s), Logic=%.2f" % [money1, Game.money, jack.last_pay, Game.mood_word(jack.index), Game.skill_level(jack.index, "Logic")])




func _s_unlocks() -> void:
	var SA := preload("res://scripts/sim/sim_actions.gd")
	var lily = _agent("Lily")
	lily.cancel_all()
	Game.selected = lily.index
	for k in lily.member.needs:
		lily.member.needs[k] = maxf(lily.member.needs[k], 0.6)
	var piano = _find_it("Piano")
	var keep: float = lily.member.skills.get("Music", 0.0)
	lily.member.skills["Music"] = 1.5
	var before: Array = SA.actions_for(piano, lily.member).map(func(a): return a.label)
	lily.member.skills["Music"] = 3.2
	_menus.clear()
	await _tap_world(_it_center(piano))
	await _frames(3)
	var labels: Array = _menus[-1][1].map(func(a): return a.label) if not _menus.is_empty() else []
	_step("skill_unlocks", "Play for Tips (Music 3)" in before and "Play for Tips" in labels,
		"Music 1.5: %s -> Music 3.2: %s" % [str(before), str(labels)])
	await _shot("unlock_menu")
	var m0 := Game.money
	await _choose("Play for Tips")
	Game.speed = 3
	await _until_game(func(): return lily.last_done == "tips", 150.0)
	_step("unlock_earns", lily.last_done == "tips" and Game.money > m0 and lily.last_pay >= 20,
		"tips paid $%d (base 15 + 3 x 8, mood x%.2f), money %d -> %d" % [lily.last_pay, Game.mood_mult(lily.index), m0, Game.money])
	lily.member.skills["Music"] = maxf(keep, lily.member.skills.get("Music", 0.0) - 2.0)


func _s_mood() -> void:
	var maya = _agent("Maya")
	var jack = _agent("Jack")
	Game.speed = 1
	# --- low need -> negative moodlet + mood drops
	var mood0 := Game.mood(maya.index)
	maya.member.needs.hunger = 0.2
	maya.check_needs()
	Game.update_moods()
	_step("need_moodlet", Game.has_moodlet(maya.index, "hungry") and Game.mood(maya.index) < mood0,
		"Maya hunger=0.20 -> %s, mood %.1f -> %.1f" % [str(Game.moodlets(maya.index).map(func(m): return m.label)), mood0, Game.mood(maya.index)])
	maya.member.needs.hunger = 0.9
	maya.check_needs()
	_step("moodlet_clears", not Game.has_moodlet(maya.index, "hungry"), "fed -> hungry moodlet gone")

	# --- mood scales skill gain / pay
	var good := 0.0
	var bad := 0.0
	Game.add_moodlet(jack.index, "t_good", "Test Joy", "star", 60.0, 1.0)
	good = Game.mood_mult(jack.index)
	Game.remove_moodlet(jack.index, "t_good")
	Game.add_moodlet(jack.index, "t_bad", "Test Gloom", "star", -60.0, 1.0)
	bad = Game.mood_mult(jack.index)
	var band_bad := Game.mood_band(jack.index)
	Game.remove_moodlet(jack.index, "t_bad")
	_step("mood_scales_gain", good > 1.2 and bad < 0.8 and band_bad == "bad", "skill/pay x%.2f happy vs x%.2f upset" % [good, bad])

	# --- critical need -> refuses player orders that don't help
	jack.cancel_all()
	Game.selected = jack.index
	var comp = _find_it("Computer")
	var e0: float = jack.member.needs.energy
	jack.member.needs.energy = 0.05
	var ref0: int = jack.refused
	_menus.clear()
	await _tap_world(_it_center(comp))
	await _frames(3)
	await _choose("Work")
	await _frames(2)
	_step("refuses_when_exhausted", jack.refused == ref0 + 1 and jack.current_label() != "Work", "Jack energy=0.05 -> refused=%d, action='%s'" % [jack.refused - ref0, jack.current_label()])

	# --- energy 0 -> passes out on the spot with a strong negative moodlet
	# (free will would already have sent him to bed: switch it off for this check)
	jack.autonomy = false
	jack.cancel_all()
	jack._force_cool = 0.0
	jack.member.needs.energy = 0.0
	jack.check_needs()
	await _frames(3)
	var po: bool = jack.order.get("action", {}).get("id", "") == "pass_out" and jack.actor.pose == "sleep"
	await _focus(jack.actor.global_position)
	await _wait(0.4)
	await _shot("passed_out")
	_step("pass_out_at_zero", po and Game.has_moodlet(jack.index, "passed_out"),
		"order=%s pose=%s mood=%.1f (%s)" % [jack.order.get("action", {}).get("id", "-"), jack.actor.pose, Game.mood(jack.index), Game.mood_band(jack.index)])
	var pb_hue = hud.plumbob.material.get_shader_parameter("hue_shift") if hud and hud.plumbob.material else null
	_step("plumbob_mood_colour", pb_hue != null, "plumbob hue shift=%s for band %s" % [str(pb_hue), Game.mood_band(jack.index)])
	jack.cancel_all()
	jack.autonomy = true
	jack.member.needs.energy = e0
	Game.remove_moodlet(jack.index, "passed_out")
	Game.remove_moodlet(jack.index, "exhausted")

	# --- bladder 0 -> accident
	jack.member.needs["bladder"] = 0.0
	jack._force_cool = 0.0
	jack.check_needs()
	var acc: bool = Game.has_moodlet(jack.index, "embarrassed") and jack.member.needs.bladder > 0.9
	jack.member.needs.erase("bladder")
	Game.remove_moodlet(jack.index, "embarrassed")
	jack.member.needs.hygiene = 0.6
	_step("accident_at_zero", acc, "embarrassed moodlet=%s" % str(acc))

	# --- starving -> free will overrides the queue and goes to eat
	maya.cancel_all()
	maya.member.needs.hunger = 0.0
	maya._force_cool = 0.0
	maya.check_needs()
	await _frames(2)
	var eats: bool = maya.order.get("forced", false) and float(maya.order.get("action", {}).get("needs", {}).get("hunger", 0.0)) > 0.0
	_step("starving_forces_eat", eats and Game.has_moodlet(maya.index, "starving"), "Maya -> '%s' forced=%s" % [maya.current_label(), str(maya.order.get("forced", false))])
	maya.cancel_all()
	maya.member.needs.hunger = 0.8
	maya.check_needs()


func _s_queue() -> void:
	var jack = _agent("Jack")
	var ov = sim.overlay
	jack.cancel_all()
	for k in jack.member.needs:
		jack.member.needs[k] = maxf(jack.member.needs[k], 0.6)
	Game.selected = jack.index
	Game.speed = 1
	await _frames(2)
	# Queue three orders through the real menu.
	var comp = _find_it("Computer")
	for lab in ["Answer Emails", "Play Games", "Work"]:
		_menus.clear()
		await _tap_world(_it_center(comp))
		await _frames(3)
		await _choose(lab)
		await _frames(2)
	await _wait(0.5)
	var v: Array = Game.queue_view(jack.index)
	_step("queue_strip", v.size() == 3 and v[0].current, "queue=%s" % str(v.map(func(q): return q.label)))
	await _shot("queue")
	# Tap the 3rd tile (Work) to cancel it.
	var hit_rect := Rect2()
	for h in ov._hits:
		if h[1] == "queue" and int(h[2]) == 2:
			hit_rect = h[0]
	if hit_rect.size != Vector2.ZERO:
		_touch(hit_rect.get_center())
	await _frames(3)
	v = Game.queue_view(jack.index)
	_step("queue_tap_cancel", v.size() == 2 and not v.any(func(q): return q.label == "Work"), "after tap: %s" % str(v.map(func(q): return q.label)))
	# Tap the current tile: it stops and the next one starts.
	for h in ov._hits:
		if h[1] == "queue" and int(h[2]) == 0:
			_touch((h[0] as Rect2).get_center())
	await _frames(3)
	v = Game.queue_view(jack.index)
	_step("queue_cancel_current", v.size() == 1 and v[0].label == "Play Games", "after tap: %s" % str(v.map(func(q): return q.label)))
	# Skills tab.
	for h in ov._hits:
		if h[1] == "skills":
			_touch((h[0] as Rect2).get_center())
	await _frames(3)
	_step("skills_panel", ov.panel.visible and ov.panel_tab == "skills" and Game.skills_list(jack.index).size() >= 2,
		"panel=%s tab=%s skills=%s" % [str(ov.panel.visible), ov.panel_tab, str(Game.skills_list(jack.index).map(func(s): return "%s %d" % [s.name, s.level]))])
	await _shot("skills")
	for h in ov._hits:
		if h[1] == "mood":
			_touch((h[0] as Rect2).get_center())
			break
	await _frames(3)
	_step("mood_panel", ov.panel.visible and ov.panel_tab == "mood", "moodlets=%s" % str(Game.moodlets(jack.index).map(func(m): return "%s %+d" % [m.label, m.delta])))
	await _shot("mood")
	ov.panel.visible = false
	jack.cancel_all()


func _s_autonomy() -> void:
	var maya = _agent("Maya")
	# --- every object on the lot can be reached from both storeys
	var nav: NavGrid = sim.nav
	var probes: Array = [Vector3(-2.85, 3.0, -0.1), Vector3(0.0, 0.0, 0.0)]
	var bad: Array = []
	var n_ok := 0
	for it in sim.interactables:
		if not is_instance_valid(it) or sim.townie_of(it) != "" or it.get_parent() is SimActor:
			continue
		var r: Dictionary = sim.approach(maya, {"action": {"id": "x", "pose": "idle"}, "target": it})
		if r.is_empty():
			continue
		var ok_all := true
		for pr in probes:
			nav.find_path(pr, r.spot, true)
			if not nav.last_ok:
				ok_all = false
		if ok_all:
			n_ok += 1
		else:
			bad.append(it.title)
	_step("nav_reach_all", bad.is_empty(), "%d objects reachable from both floors, unreachable=%s" % [n_ok, str(bad)])

	# --- hungry upstairs -> walks downstairs to the kitchen and eats
	maya.cancel_all()
	for k in maya.member.needs:
		maya.member.needs[k] = 0.95
	maya.member.needs.hunger = 0.05
	maya.idle_minutes = 0.0
	maya.actor.global_position = Vector3(-2.85, 3.0, -0.1)
	Game.speed = 3
	var y0: float = maya.actor.global_position.y
	var picked := await _until_game(func(): return maya.phase != "idle" and maya.order.get("action", {}).get("needs", {}).get("hunger", 0.0) > 0.0, 30.0)
	var act_name: String = maya.current_label()
	var tgt = maya.order.get("target")
	_step("autonomy_lowest_need", picked, "Maya hunger=0.05 -> chose '%s' on %s, route %.1f m" % [act_name, str(tgt.title) if tgt else "-", maya.path_len])
	var m0 := Game.total_minutes()
	await _until_game(func(): return maya.phase == "act" or maya.phase == "idle", 240.0)
	var y1: float = maya.actor.global_position.y
	await _focus(maya.actor.global_position)
	await _shot("autonomy")
	_step("autonomy_arrives", maya.phase == "act" and float(maya.order.get("action", {}).get("needs", {}).get("hunger", 0.0)) > 0.0,
		"Maya phase=%s '%s' after %.0f game min, y %.2f -> %.2f (stairs %s), repaths=%d route_fails=%d" % [maya.phase, maya.current_label(), Game.total_minutes() - m0, y0, y1, "used" if absf(y1 - y0) > 1.5 else "not needed", maya.repaths, maya.route_fails])
	var h0: float = maya.member.needs.hunger
	await _until_game(func(): return maya.phase != "act", 120.0)
	_step("autonomy_eats", maya.member.needs.hunger > h0 + 0.2, "hunger %.2f -> %.2f" % [h0, maya.member.needs.hunger])

	# --- the stairs are blocked -> no walking into walls: route fail, then
	# free will picks something it can reach; unblocked -> goes to eat.
	maya.cancel_all()
	maya.actor.global_position = Vector3(-2.85, 3.0, -0.1)
	var fails0: int = maya.route_fails
	var unr0: int = int(sim.stats.get("unreachable", 0))
	# Close the stairs (as if something were dropped on them).
	var saved_links: Array[Dictionary] = nav.links.duplicate()
	nav.links.clear()
	nav.find_path(maya.actor.global_position, Vector3(0, 0, -4.0), true)
	var blocked: bool = not nav.last_ok
	maya.unreachable.clear()
	maya.member.needs.hunger = 0.0
	maya._force_cool = 0.0
	maya.check_needs()   # starving: free will is forced to look for food
	maya.idle_minutes = 99.0
	await _until_game(func(): return false, 60.0)
	var stayed_up: bool = maya.actor.global_position.y > 2.0 and (maya.phase != "walk" or maya.spot.y > 2.0)
	var noticed: bool = maya.route_fails > fails0 or int(sim.stats.get("unreachable", 0)) > unr0
	_step("route_fail_fallback", blocked and stayed_up and noticed,
		"stairs blocked=%s -> Maya stays upstairs=%s, %s '%s', route fails +%d, skipped targets +%d" % [str(blocked), str(stayed_up), maya.phase, maya.current_label(), maya.route_fails - fails0, int(sim.stats.get("unreachable", 0)) - unr0])
	nav.links = saved_links
	sim._on_furniture_changed()
	maya.cancel_all()
	maya.member.needs.hunger = 0.05
	maya.idle_minutes = 99.0
	await _until_game(func(): return maya.phase == "act" and float(maya.order.get("action", {}).get("needs", {}).get("hunger", 0.0)) > 0.0, 240.0)
	_step("route_recovers", maya.phase == "act" and maya.actor.global_position.y < 1.0, "unblocked -> Maya %s '%s' at y %.2f" % [maya.phase, maya.current_label(), maya.actor.global_position.y])
	maya.cancel_all()
	maya.member.needs.hunger = 0.8
	maya.check_needs()

	# --- free will soak: everyone lives for a few game hours with no orders
	for m in Game.household:
		for k in m.needs:
			m.needs[k] = randf_range(0.25, 0.7)
	var stuck_max := 0.0
	var done0: int = sim.stats.done
	var walk_since := {}
	var t0 := Game.total_minutes()
	while Game.total_minutes() - t0 < 240.0:
		await get_tree().process_frame
		for a in sim.agents:
			if a == null:
				continue
			if a.phase == "walk":
				if not walk_since.has(a):
					walk_since[a] = Game.total_minutes()
				stuck_max = maxf(stuck_max, Game.total_minutes() - walk_since[a])
			else:
				walk_since.erase(a)
		if Time.get_ticks_msec() - _t0 > 900000:
			break
	var fb := 0
	for a in sim.agents:
		if a:
			fb += a.fallbacks
	_step("autonomy_soak", sim.stats.done - done0 >= 4 and stuck_max < 120.0,
		"%.0f game min: %d actions done, longest walk %.0f game min, give-ups %d, low needs %s" % [Game.total_minutes() - t0, sim.stats.done - done0, stuck_max, fb, _low_needs()])
	await _shot("autonomy_soak")


func _s_meal() -> void:
	var jack = _agent("Jack")
	var lily = _agent("Lily")
	var maya = _agent("Maya")
	for a in sim.agents:
		if a:
			a.cancel_all()
			for k in a.member.needs:
				a.member.needs[k] = maxf(a.member.needs[k], 0.75)
	lily.member.needs.hunger = 0.35
	maya.member.needs.hunger = 0.9   # not hungry: keeps doing her own thing
	# Only Jack cooks: free will off until dinner is called.
	for a in [jack, lily, maya]:
		a.autonomy = false
	Game.selected = jack.index
	Game.speed = 1
	var stove = _find_it("Stove")
	# (Menus are covered by the loop section; order directly.)
	jack.command({"action": _action_of(stove, jack, "cook"), "target": stove})
	await _frames(2)
	print("  Jack after choosing Cook: %s '%s' spot=%s" % [jack.phase, jack.current_label(), str(jack.spot)])
	Game.speed = 3
	await _until_game(func(): return not sim.meal.is_empty(), 150.0)
	var served: bool = not sim.meal.is_empty()
	var n0: int = int(sim.meal.get("servings", 0))
	await _frames(3)
	var called: bool = lily.order.get("action", {}).get("id", "") == "meal" or lily.queue.any(func(q): return q.get("action", {}).get("id", "") == "meal")
	for a in [jack, lily, maya]:
		a.autonomy = true
	_step("cook_serves_meal", served and n0 >= 2 and sim.meal.plates.size() == n0,
		"Jack cooked -> %s, %d servings on the %s (Jack %s '%s' last=%s fails=%d refused=%d)" % [sim.meal.get("dish", "-"), n0, str(sim.meal.table.title) if served else "-",
		jack.phase, jack.current_label(), jack.last_done, jack.route_fails, jack.refused])
	_step("call_to_meal", called and maya.order.get("action", {}).get("id", "") != "meal",
		"hungry Lily -> '%s' (%s), full Maya -> '%s'" % [lily.current_label(), lily.phase, maya.current_label()])
	await _until_game(func(): return lily.phase == "act" and lily.current_label().begins_with("Eat"), 120.0)
	await _focus(_it_center(sim.meal.table) if not sim.meal.is_empty() else lily.actor.global_position)
	await _wait(0.3)
	await _shot("family_meal")
	var h0: float = lily.member.needs.hunger
	await _until_game(func(): return lily.phase != "act", 60.0)
	var left: int = int(sim.meal.get("servings", 0))
	_step("meal_eaten", lily.member.needs.hunger > h0 + 0.3 and left == n0 - 1 and Game.has_moodlet(lily.index, "good_meal"),
		"Lily hunger %.2f -> %.2f, servings %d -> %d" % [h0, lily.member.needs.hunger, n0, left])
	# Leftovers show up in the table's menu for everyone else.
	if not sim.meal.is_empty():
		var acts: Array = sim.actions_for(sim.meal.table, maya.member)
		_step("meal_in_menu", not acts.is_empty() and acts[0].id == "meal", "table menu: %s" % str(acts.map(func(a): return a.label)))
	sim.clear_meal()


func _s_wishes() -> void:
	var lily = _agent("Lily")
	var ov = sim.overlay
	_top_up()
	sim.roll_wishes()
	var counts: Array = []
	for a in sim.agents:
		if a:
			counts.append("%s %d" % [a.display_name(), Game.wishes(a.index).size()])
	var all3: bool = sim.agents.all(func(a): return a == null or Game.wishes(a.index).size() == 3)
	_step("wishes_rolled", all3, "%s; Lily wishes %s" % [str(counts), str(Game.wishes(lily.index).map(func(w): return w.label))])
	# A known wish: practise the piano. Promise it from the Wishes tab.
	var piano = _find_it("Piano")
	Game.remove_wish(lily.index, Game.wishes(lily.index)[0].id)
	Game.wishes(lily.index).push_front({"id": "do_practice", "label": "Practise the Piano", "icon": "music", "kind": "do", "arg": "practice",
		"n": 1, "reward": 250, "promised": false, "born": Game.total_minutes()})
	Game.selected = lily.index
	await _frames(4)
	for h in ov._hits:
		if h[1] == "wishes":
			_touch((h[0] as Rect2).get_center())
			break
	await _frames(4)
	for h in ov._hits:
		if h[1] == "wish" and int(h[2]) == 0:
			_touch((h[0] as Rect2).get_center())
			break
	await _frames(4)
	var promised: bool = Game.wishes(lily.index)[0].get("promised", false)
	_step("wish_promise_tap", ov.panel.visible and ov.panel_tab == "wishes" and promised and Game.has_moodlet(lily.index, "hopeful"),
		"tab=%s promised=%s" % [ov.panel_tab, str(promised)])
	await _shot("wishes")
	ov.panel.visible = false
	var lth0 := Game.lth(lily.index)
	lily.command({"action": _action_of(piano, lily, "practice"), "target": piano})
	Game.speed = 3
	await _until_game(func(): return lily.last_done == "practice" and lily.phase != "act", 150.0)
	var gone: bool = not Game.wishes(lily.index).any(func(w): return w.id == "do_practice")
	_step("wish_fulfilled", gone and Game.lth(lily.index) == lth0 + 375 and Game.has_moodlet(lily.index, "wish_do_practice"),
		"Lily LTH %d -> %d, wishes now %s" % [lth0, Game.lth(lily.index), str(Game.wishes(lily.index).map(func(w): return w.label))])


func _action_of(it, ag, id: String) -> Dictionary:
	for a in sim.actions_for(it, ag.member):
		if a.get("id", "") == id:
			return a
	return {}


func _low_needs() -> String:
	var out: Array = []
	for m in Game.household:
		var lo := 1.0
		var ln := ""
		for k in m.needs:
			if m.needs[k] < lo:
				lo = m.needs[k]
				ln = k
		out.append("%s %s %.2f" % [m.name, ln, lo])
	return ", ".join(out)


func _s_social() -> void:
	var jack = _agent("Jack")
	var lily = _agent("Lily")
	for a in [jack, lily]:
		a.cancel_all()
		a.autonomy = false
		for k in a.member.needs:
			a.member.needs[k] = maxf(a.member.needs[k], 0.6)
	Game.selected = jack.index
	Game.speed = 1
	await _focus(lily.actor.global_position)
	var r0 := Game.rel("Jack", "Lily")
	_menus.clear()
	var lp: Vector3 = (lily.actor.global_position + lily.actor.head_top()) * 0.5
	sim.long_press(_cam().unproject_position(lp))
	await _frames(3)
	var got: bool = not _menus.is_empty() and "Lily" in str(_menus[-1][0])
	var labels: Array = _menus[-1][1].map(func(a): return a.label) if got else []
	_step("social_menu_tiers", got and "Hug" in labels and "Deep Conversation" in labels and not "Introduce Yourself" in labels,
		"Jack->Lily (%s %.0f): %s" % [Game.rel_level(r0), r0, str(labels)])
	await _shot("social_menu")
	await _choose("Tell a Joke")
	Game.speed = 3
	await _until_game(func(): return jack.last_done == "s_joke" and jack.phase == "idle" or jack.phase == "idle" and jack.completed > 0 and jack.last_done == "s_joke", 90.0)
	var r1 := Game.rel("Jack", "Lily")
	_step("social_raises_rel", r1 > r0 or Game.has_moodlet(jack.index, "rejected"), "Jack-Lily %.1f -> %.1f (%s), Charisma %.2f" % [r0, r1, Game.rel_level(r1), Game.skill_level(jack.index, "Charisma")])
	# Relationships tab
	var ov = sim.overlay
	await _frames(3)
	for h in ov._hits:
		if h[1] == "rels":
			_touch((h[0] as Rect2).get_center())
			break
	await _frames(3)
	var rl: Array = Game.rel_list(jack.index)
	_step("relationships_panel", ov.panel.visible and ov.panel_tab == "rels" and rl.size() >= 3,
		"tab=%s rels=%s" % [ov.panel_tab, str(rl.map(func(x): return "%s %s %.0f" % [x.name, x.level, x.value]))])
	await _shot("relationships")
	ov.panel.visible = false
	# Level up: push close to the next level and do one more social.
	var before := Game.rel_level(Game.rel("Lily", "Maya"))
	Game.change_rel("Lily", "Maya", 79.5 - Game.rel("Lily", "Maya"))
	var lvl_seen := []
	var cb := func(a, b, l): lvl_seen.append(l)
	Game.relationship_level_changed.connect(cb)
	var maya = _agent("Maya")
	maya.cancel_all()
	maya.autonomy = false
	lily.command({"action": SimActions_hug(lily, maya), "other": maya})
	await _until_game(func(): return lily.phase == "idle", 90.0)
	Game.relationship_level_changed.disconnect(cb)
	_step("rel_level_up", "Best Friend" in lvl_seen and Game.has_moodlet(lily.index, "new_friend"), "Lily-Maya %s -> %s, events=%s" % [before, Game.rel_level(Game.rel("Lily", "Maya")), str(lvl_seen)])
	for a in [jack, lily, maya]:
		a.autonomy = true


func SimActions_hug(ag, other) -> Dictionary:
	for a in preload("res://scripts/sim/sim_actions.gd").socials_for(ag, other):
		if a.id == "s_hug":
			return a
	return {}


func _s_townies() -> void:
	Game.speed = 1
	_menus.clear()
	Game.mode = "manage"
	await _frames(3)
	await _choose("Autumn Festival")
	await _frames(6)
	var jack = _agent("Jack")
	Game.selected = jack.index
	for m in Game.household:
		for k in m.needs:
			m.needs[k] = maxf(m.needs[k], 0.7)
	jack.cancel_all()
	# nearest townie Jack hasn't met
	var best = null
	var bd := INF
	for it in sim.interactables:
		var tn: String = sim.townie_of(it)
		if tn == "" or Game.has_met("Jack", tn) or sim.townie_info(tn).get("trait", "") == "Grumpy":
			continue
		var d := _flat(it.global_position, jack.actor.global_position)
		if d < bd:
			bd = d
			best = it
	var tname: String = sim.townie_of(best) if best else ""
	_menus.clear()
	if best:
		await _tap_world(_it_center(best))
		await _frames(3)
		if _menus.is_empty() or not str(_menus[-1][0]).begins_with(tname.get_slice(" ", 0)):
			print("  (tap on %s hit something else: opening its menu directly)" % tname)
			sim.open_object_menu(best, _cam().unproject_position(_it_center(best)))
			await _frames(3)
	var labels: Array = _menus[-1][1].map(func(a): return a.label) if not _menus.is_empty() else []
	_step("townie_stranger_menu", tname != "" and "Introduce Yourself" in labels and not "Chat" in labels and str(_menus[-1][0]).begins_with(tname.get_slice(" ", 0)),
		"%s: %s" % [str(_menus[-1][0]) if not _menus.is_empty() else "-", str(labels)])
	await _shot("townie_menu")
	await _choose("Introduce Yourself")
	Game.speed = 2
	await _until_game(func(): return jack.phase == "idle" and jack.last_done == "s_introduce", 120.0)
	var met: bool = Game.has_met("Jack", tname)
	_menus.clear()
	# Tap the townie's head (Jack now stands in front of their body).
	var head: Vector3 = best.get_parent().head_top() - Vector3(0, 0.15, 0) if best.get_parent().has_method("head_top") else _it_center(best)
	await _tap_world(head)
	await _frames(3)
	if _menus.is_empty() or not str(_menus[-1][0]).begins_with(tname.get_slice(" ", 0)):
		print("  (tap on %s missed: opening its menu directly)" % tname)
		sim.open_object_menu(best, _cam().unproject_position(head))
		await _frames(3)
	labels = _menus[-1][1].map(func(a): return a.label) if not _menus.is_empty() else []
	_step("townie_meet_unlocks", met and "Chat" in labels and "Tell a Joke" in labels,
		"Jack-%s %.1f (%s), menu now %s, Meet 3 Neighbors done=%s (met here %d)" % [tname, Game.rel("Jack", tname), Game.rel_level(Game.rel("Jack", tname)), str(labels), str(_task_done("Meet 3 Neighbors")), sim.met_here.size()])
	await _choose("Chat")
	await _until_game(func(): return jack.phase == "idle" and jack.last_done == "s_chat", 120.0)
	_step("townie_rel_persists", Game.rel("Jack", tname) > 10.0 and not _task_done("Meet 3 Neighbors"), "Jack-%s %.1f, Meet 3 Neighbors done=%s" % [tname, Game.rel("Jack", tname), str(_task_done("Meet 3 Neighbors"))])
	await _shot("townie_chat")


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
	_top_up()
	Game.selected = lily.index
	await _focus(lily.actor.global_position)
	var nav: NavGrid = sim.nav
	var lp: Vector3 = lily.actor.global_position
	var li: int = nav.level_of(lp)
	var reg: int = nav.entry_region(lp, li)
	# An open floor cell 1.2..2.5 m away in the room Lily is in, whose screen
	# point is plain floor (not a sim or an object).
	var gp := Vector3.INF
	var cam := _cam()
	for r in [1.5, 2.0, 1.2, 2.5]:
		for k in 12:
			var ang: float = k * TAU / 12.0
			var c: Vector2i = nav.cell_of(lp + Vector3(cos(ang), 0, sin(ang)) * r)
			if not nav.is_open(li, c) or nav.region_of(li, c) != reg:
				continue
			var p: Vector3 = nav.center_of(li, c)
			var sp := cam.unproject_position(p)
			if not _screen_ok(sp) or sim.pick_agent(sp) != null or sim.pick_interactable(sp) != null:
				continue
			gp = p
			break
		if gp != Vector3.INF:
			break
	if gp == Vector3.INF:
		gp = nav.center_of(li, nav.nearest_open(li, nav.cell_of(lp + Vector3(1.2, 0, 1.0))))
	await _tap_world(gp)
	await _frames(2)
	var go_ok: bool = lily.order.get("action", {}).get("id", "") == "go_here"
	await _until_game(func(): return lily.phase == "idle", 60.0)
	_step("go_here", go_ok and _flat(lily.actor.global_position, gp) < 0.4,
		"tap -> %s, dist to target %.2f, phase=%s" % ["Go Here" if go_ok else "'%s'" % lily.current_label(), _flat(lily.actor.global_position, gp), lily.phase])


func _s_build() -> void:
	var lily = _agent("Lily")
	_top_up()
	Game.selected = lily.index
	var money_b := Game.money
	_menus.clear()
	Game.mode = "buy"
	await _frames(3)
	var buy_menu: bool = not _menus.is_empty() and _menus[-1][0] == "Buy"
	var cats: Array = _menus[-1][1].map(func(a): return a.label) if buy_menu else []
	var paused_in_buy := Game.speed == 0
	await _choose("Seating")
	await _frames(2)
	var n_items := preload("res://scripts/sim/catalog.gd").ITEMS.size()
	_step("catalog_categories", buy_menu and cats.size() >= 6 and _menus[-1][0] == "Seating" and n_items >= 50,
		"%d items; Buy categories %s; Seating: %s" % [n_items, str(cats), str(_menus[-1][1].map(func(a): return a.label))])
	await _shot("catalog")
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
		await _until_game(func(): return lily.phase == "act", 90.0)
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

	# ---------------------------------------------------------------- build: a wall + floor tiles
	Game.mode = "build"
	await _frames(3)
	var build_cats: Array = _menus[-1][1].map(func(a): return a.label) if not _menus.is_empty() else []
	await _choose("Walls")
	await _frames(2)
	await _choose("Wall · Brick")
	await _frames(2)
	var wall_ok := false
	var money_w := Game.money
	var obst0: int = sim.nav.obstacles.size()
	if b.ghost:
		var tl: int = sim.nav.level_of(lily.actor.global_position)
		var c: Vector2i = sim.nav.nearest_open(tl, sim.nav.cell_of(lily.actor.global_position + Vector3(1.5, 0, 0)))
		await _tap_world(sim.nav.center_of(tl, c))
		await _frames(2)
		await _tap_world(b.ghost.global_position + Vector3(0, 0.5, 0), false)
		await _frames(2)
		if b.ghost and not b.ghost_valid:
			b._move_ghost(b.ghost.global_position, true)   # nudge to the nearest free spot
		await _choose("Place")
		await _frames(2)
		wall_ok = sim.nav.obstacles.size() == obst0 + 1 and Game.money == money_w - 55
	# a 2 x 1 strip of floor tiles
	var tiles := 0
	for k in 2:
		_menus.clear()
		b.open_catalog(Vector2(300, 300), "floors")
		await _frames(2)
		await _choose("Floor · Checker Tile")
		await _frames(2)
		if b.ghost:
			b._move_ghost(lily.actor.global_position + Vector3(-1.0 - k, 0, 1.0), true)
			if b.ghost_valid and b.place_ghost():
				tiles += 1
	await _frames(2)
	_step("build_wall_floor", wall_ok and tiles == 2 and "Walls  (5)" in build_cats,
		"Build categories %s, wall placed=%s (nav obstacles %d -> %d), floor tiles placed=%d" % [str(build_cats), str(wall_ok), obst0, sim.nav.obstacles.size(), tiles])
	await _focus(lily.actor.global_position)
	await _shot("build_wall_floor")
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
		await _until_game(func(): return jack.last_done == "pay", 120.0)
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


func _s_save() -> void:
	var path := "user://vims_playtest_save.txt"
	var lily = _agent("Lily")
	Game.add_moodlet(lily.index, "t_save", "Saved Joy", "star", 5.0, 0.0)
	var money0 := Game.money
	var music0 := Game.skill_level(lily.index, "Music")
	var rel0 := Game.rel("Jack", "Lily")
	var lth0 := Game.lth(lily.index)
	var nw0 := Game.wishes(lily.index).size()
	var day0 := Game.day
	var min0 := Game.minutes
	var ok_save := Game.save_game(path)
	# Mess everything up, then load.
	Game.money = 1
	lily.member.skills["Music"] = 9.0
	Game.change_rel("Jack", "Lily", -50.0)
	Game.minutes = 3.0
	var ok_load := Game.load_game(path)
	var ml: bool = Game.has_moodlet(lily.index, "t_save") and Game.moodlets(lily.index).any(func(m): return m.id == "t_save" and m.expires == INF)
	_step("save_load", ok_save and ok_load and Game.money == money0 and absf(Game.skill_level(lily.index, "Music") - music0) < 0.001
		and absf(Game.rel("Jack", "Lily") - rel0) < 0.01 and Game.lth(lily.index) == lth0 and Game.wishes(lily.index).size() == nw0
		and Game.day == day0 and absf(Game.minutes - min0) < 0.01 and ml,
		"saved + reloaded: money $%d, Music %.2f, Jack-Lily %.0f, LTH %d, %d wishes, moodlet kept=%s" % [Game.money, Game.skill_level(lily.index, "Music"), Game.rel("Jack", "Lily"), Game.lth(lily.index), Game.wishes(lily.index).size(), str(ml)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# The agents hold the old member dicts: rebind the lot like a real load does.
	main.load_location(Game.location)
	await _frames(3)


# =================================================================== helpers

## A content household (the soak leaves needs low; a starving sim would
## rightly ignore the next orders).
func _top_up() -> void:
	for a in sim.agents:
		if a:
			a.cancel_all()
			for k in a.member.needs:
				a.member.needs[k] = maxf(a.member.needs[k], 0.75)
			a.check_needs()

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


## Wait until cond is true or `game_min` in-game minutes have passed (the
## software renderer is slow, so real-time timeouts are unreliable); a hard
## real-time cap of 90 s keeps a broken run from hanging.
func _until_game(cond: Callable, game_min: float) -> bool:
	var m0 := Game.total_minutes()
	var t := Time.get_ticks_msec()
	while not cond.call():
		if Game.total_minutes() - m0 > game_min or Time.get_ticks_msec() - t > 90000:
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
	if DisplayServer.get_name() == "headless":
		return   # nothing is drawn (and frame_post_draw never fires)
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/playtest_%02d_%s.png" % [shot_dir, _shot_n, tag]
	img.save_png(path)
	print("  shot ", path)
