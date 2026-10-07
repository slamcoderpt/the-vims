extends RefCounted
## Runtime brain of one household member in the current location: an action
## queue, walking along NavGrid paths, performing actions (pose + progress
## bubble), applying needs / skills / money / tasks, and autonomy (free will)
## when idle. Owned and ticked by SimWorld.
##
## Order dictionary:
##   action: Dictionary (Interactable action format), target: Interactable or null,
##   point: Vector3 (for "Go Here"), other: agent (household social), auto: bool

const SimActions := preload("res://scripts/sim/sim_actions.gd")
const Careers := preload("res://scripts/sim/careers.gd")
const Traits := preload("res://scripts/sim/traits.gd")

## Idle in-game minutes before free will kicks in.
const AUTONOMY_AFTER := 8.0
const SKILL_CHIP_EVERY := 15.0   # in-game minutes between "+ Skill" chips
const MAX_QUEUE := 5
## Faster free will when a need is getting low.
const AUTONOMY_URGENT_AFTER := 1.5
## How often (in-game minutes) needs are checked for moodlets / consequences.
const NEED_CHECK_EVERY := 2.0
## Walking robustness: within ARRIVE_TOL (m, same storey) of the spot counts as
## there; progress is checked every STUCK_CHECK walk-seconds and a sim that
## gained less than STUCK_MIN metres repaths (up to MAX_REPATHS), then gives up
## on that target and free will picks the next best one.
const ARRIVE_TOL := 0.3
const WALK_BOOST := 1.4
const STUCK_CHECK := 1.5
const STUCK_MIN := 0.25
const MAX_REPATHS := 2
## In-game minutes an unreachable object is skipped by free will.
const UNREACHABLE_FOR := 180.0

## Need -> [mild moodlet, strong moodlet]: [id, label, icon, mood delta, below].
## Strong ones last until the need recovers past RECOVER.
const NEED_MOODLETS := {
	"hunger": [["hungry", "Hungry", "need_hunger", -12.0, 0.25], ["starving", "Starving", "need_hunger", -35.0, 0.08]],
	"energy": [["tired", "Tired", "need_energy", -12.0, 0.25], ["exhausted", "Exhausted", "need_energy", -30.0, 0.08]],
	"fun": [["bored", "Bored", "need_fun", -10.0, 0.25], ["very_bored", "Very Bored", "need_fun", -25.0, 0.08]],
	"hygiene": [["smelly", "Smelly", "need_hygiene", -10.0, 0.25], ["disgusting", "Disgusting", "need_hygiene", -25.0, 0.08]],
	"social": [["lonely", "Lonely", "need_social", -10.0, 0.25], ["very_lonely", "Very Lonely", "need_social", -25.0, 0.08]],
	"bladder": [["gotta_go", "Gotta Go", "need_bladder", -12.0, 0.25], ["desperate", "Desperate", "need_bladder", -30.0, 0.08]],
}
const RECOVER := 0.3
const WARN_BELOW := 0.15
## Spoken when a player order is refused because of a critical need.
const REFUSE_TEXT := {"hunger": "Too hungry...", "energy": "Too tired...", "fun": "So bored...",
	"hygiene": "I need a wash!", "social": "So lonely...", "bladder": "Gotta go!"}
const WARN_TEXT := {"hunger": "%s is hungry", "energy": "%s is exhausted", "fun": "%s is bored",
	"hygiene": "%s needs a wash", "social": "%s is lonely", "bladder": "%s needs the toilet"}
const PASS_OUT := {"id": "pass_out", "label": "Passed Out", "icon": "zzz", "minutes": 90.0, "pose": "sleep",
	"needs": {"energy": 0.35}}

var index := -1
var member: Dictionary
var actor: Node3D
var world   # SimWorld
var kind := "adult"

var queue: Array = []
var order: Dictionary = {}
## "idle" | "walk" | "wait" | "act"
var phase := "idle"
var path := PackedVector3Array()
var path_i := 0
var seg_from := Vector3.ZERO
var spot := Vector3.ZERO
var face_point := Vector3.INF
var elapsed := 0.0
var idle_minutes := 0.0
var walk_real := 0.0
var wait_minutes := 0.0
var base_speed := 1.3
var autonomy := true
var completed := 0
var last_done := ""
var _shown_prog := -1
var _skill_t := 0.0
var _thought_t := 4.0
var _reserved: Node = null
var _social_partner = null
var _need_acc := 0.0
var _warned := {}
var _force_cool := 0.0
## Money from the last paid action (mood scales pay).
var last_pay := 0
var refused := 0
var forced := 0
## Walking diagnostics (playtest) and route-failure memory.
var path_len := 0.0
var repaths := 0
var route_fails := 0
var fallbacks := 0
var unreachable := {}        # Interactable -> in-game minute until which it's skipped
var _stuck_t := 0.0
var _stuck_rem := INF
var _stuck_n := 0
var _other_at := Vector3.INF
var _repath_cool := 0.0


func setup(p_world, i: int, p_actor: Node3D) -> void:
	world = p_world
	index = i
	member = Game.household[i]
	actor = p_actor
	kind = member.get("kind", "adult")
	if actor.has_method("kind"):
		kind = actor.kind()
	base_speed = actor.get("walk_speed") if actor.get("walk_speed") != null else 1.3
	if base_speed <= 0.0:
		base_speed = 1.3
	# A brisk Sims walk: crossing the house shouldn't eat an hour of the day.
	base_speed *= WALK_BOOST


func display_name() -> String:
	return member.get("name", "?")


func is_busy() -> bool:
	return phase != "idle" or not queue.is_empty()


# =================================================================== commands

## Player (or autonomy) asks for something. Player orders replace autonomous
## ones and the current action; up to MAX_QUEUE player orders queue behind.
## Sims 3 style: player orders queue up behind each other (up to MAX_QUEUE)
## and push out anything free will had planned; with replace the queue is
## cleared first. Returns false when the sim refuses (critical need, passed out).
func command(o: Dictionary, replace := false) -> bool:
	var a: Dictionary = o.get("action", {})
	var auto: bool = o.get("auto", false)
	if phase == "away":
		if not auto:
			Game.notify.emit("%s is at %s until %s" % [display_name(), "school" if Careers.is_school(member.get("career", {})) else "work",
				Game.when_text(float(member.work.until)).substr(5)], "laptop")
		return false
	if not auto:
		var why := refuse_reason(a)
		if why != "":
			refused += 1
			_say(why, "dots")
			Game.show_bubble(actor, {"kind": "thought", "icon": SimActions.need_icon(_critical_need(), kind), "id": "thought", "ttl": 2.5})
			Game.notify.emit("%s won't %s: %s" % [display_name(), str(a.get("label", "do that")).to_lower(), why.trim_suffix("...").trim_suffix("!").to_lower()], "dots")
			return false
		# Player orders replace autonomous plans.
		for k in range(queue.size() - 1, -1, -1):
			if queue[k].get("auto", false):
				queue.remove_at(k)
		if replace:
			queue.clear()
		if phase != "idle" and (replace or order.get("auto", false)) and not order.get("forced", false):
			queue.append(o)
			cancel_current()   # starts the next one
			_sync_queue()
			return true
	if queue.size() >= MAX_QUEUE:
		queue.pop_back()
	queue.append(o)
	if phase == "idle":
		_next()
	else:
		_sync_queue()
	return true


func cancel_current() -> void:
	if phase == "idle" or phase == "away":
		return
	_end(false)


func cancel_all() -> void:
	queue.clear()
	cancel_current()
	_sync_queue()


## Cancel one slot of the queue strip (0 = the action in progress).
func cancel_slot(slot: int) -> void:
	if phase == "away":
		return
	var has_cur := not order.is_empty() and phase != "idle"
	if has_cur and slot == 0:
		if order.get("forced", false):
			_say("Can't stop now!", "dots")
			return
		cancel_current()
	else:
		var qi := slot - (1 if has_cur else 0)
		if qi >= 0 and qi < queue.size():
			queue.remove_at(qi)
	_sync_queue()


## Why this sim would refuse a player order right now ("" = it won't).
func refuse_reason(a: Dictionary) -> String:
	if order.get("forced", false) and phase == "act" and order.get("action", {}).get("id", "") == "pass_out":
		return "Zzz..."
	if a.get("id", "") in ["go_here", "cancel"]:
		return ""
	var crit := _critical_need()
	if crit == "":
		return ""
	var eff: Dictionary = a.get("needs", {})
	# Anything that helps any critical need is fine.
	for k in member.needs:
		if member.needs[k] < 0.08 and float(eff.get(k, 0.0)) > 0.0:
			return ""
		if member.needs[k] < 0.08 and k == "social" and a.has("social"):
			return ""
	return REFUSE_TEXT.get(crit, "I can't...")


func _critical_need() -> String:
	var best := ""
	var bv := 0.08
	for k in member.needs:
		if member.needs[k] < bv:
			bv = member.needs[k]
			best = k
	return best


## What the queue strip shows (slot 0 = current action).
func _sync_queue() -> void:
	var view: Array = []
	if phase == "away":
		var w: Dictionary = member.work
		var school := Careers.is_school(member.get("career", {}))
		var span := maxf(1.0, float(w.until) - float(w.start))
		view.append({"label": "At School" if school else "At Work", "icon": "book" if school else "laptop",
			"progress": clampf((Game.total_minutes() - float(w.start)) / span, 0.0, 1.0),
			"auto": false, "current": true, "forced": true})
		Game.set_queue_view(index, view)
		return
	if not order.is_empty() and phase != "idle":
		var a: Dictionary = order.get("action", {})
		view.append({"label": a.get("label", ""), "icon": _queue_icon(a), "progress": _progress(),
			"auto": order.get("auto", false), "current": true, "forced": order.get("forced", false)})
	for o in queue:
		var a: Dictionary = o.get("action", {})
		view.append({"label": a.get("label", ""), "icon": _queue_icon(a), "progress": 0.0,
			"auto": o.get("auto", false), "current": false, "forced": false})
	Game.set_queue_view(index, view)


static func _queue_icon(a: Dictionary) -> String:
	var ic: String = a.get("icon", "")
	if ic == "":
		return "home" if a.get("id", "") == "go_here" else "star"
	return ic


func _progress() -> float:
	if phase != "act":
		return 0.0
	return clampf(elapsed / maxf(1.0, order.get("action", {}).get("minutes", 30.0)), 0.0, 1.0)


func current_label() -> String:
	return order.get("action", {}).get("label", "") if not order.is_empty() else ""


func _next() -> void:
	order = {}
	phase = "idle"
	while not queue.is_empty():
		var o: Dictionary = queue.pop_front()
		if _start(o):
			_sync_queue()
			return
	idle_minutes = 0.0
	_sync_queue()


func _start(o: Dictionary) -> bool:
	var t = o.get("target")
	if t != null and not is_instance_valid(t):
		return false
	var other = o.get("other")
	if other != null and (other.actor == null or not is_instance_valid(other.actor)):
		return false
	order = o
	var a: Dictionary = o.get("action", {})
	var r: Dictionary = world.approach(self, o)
	if r.is_empty():
		order = {}
		return false
	spot = r.spot
	face_point = r.get("face", Vector3.INF)
	if not _plan_path():
		if o.get("work", false):
			_leave_for_work()
			return true
		_route_fail(o)
		order = {}
		return false
	walk_real = 0.0
	wait_minutes = 0.0
	elapsed = 0.0
	_shown_prog = -1
	_skill_t = 0.0
	_stuck_n = 0
	if other != null:
		_social_partner = other
		_other_at = other.actor.global_position
	else:
		_other_at = Vector3.INF
	phase = "walk"
	actor.set_pose("walk")
	if a.get("id", "") != "go_here":
		_bubble(0.0, true)
	return true


## Path from where the sim stands to `spot`. False when the grid says the spot
## cannot be reached from here (a closed-off room, a blocked doorway).
func _plan_path() -> bool:
	var from: Vector3 = actor.global_position
	if world.nav:
		path = world.nav.find_path(from, spot, true)
		if not world.nav.last_ok:
			return false
	else:
		path = PackedVector3Array([spot])
	path_i = 0
	seg_from = from
	path_len = NavGrid.path_length(from, path)
	_stuck_t = 0.0
	_stuck_rem = path_len
	return true


## The target can't be reached: remember it, show a route-fail thought and
## (for free will) pick the next best thing straight away.
func _route_fail(o: Dictionary) -> void:
	route_fails += 1
	# The same spot failing again and again: the sim stands somewhere the grid
	# can't leave (pushed into furniture, off the lot). Sims 3 "reset": pop
	# onto the nearest open floor.
	var here: Vector3 = actor.global_position
	if here.distance_to(_fail_at) < 0.2:
		_fail_streak += 1
	else:
		_fail_streak = 1
		_fail_at = here
	if _fail_streak >= 3:
		_fail_streak = 0
		unstick()
	var t = o.get("target")
	var what := "there"
	if t != null and is_instance_valid(t):
		unreachable[t] = Game.total_minutes() + UNREACHABLE_FOR
		what = "the %s" % str(t.title)
	elif o.get("other") != null:
		what = str(o.other.display_name())
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  route fail: %s -> %s (%s) from %s" % [display_name(), what, o.get("action", {}).get("label", ""), str(actor.global_position)])
	if o.get("auto", false) and o.get("action", {}).get("id", "") == "go_here":
		return   # an aimless wander that can't be walked: just pick another
	Game.show_bubble(actor, {"kind": "thought", "icon": "dots", "text": "?", "id": "thought", "ttl": 2.5})
	if not o.get("auto", false):
		Game.notify.emit("%s can't get to %s" % [display_name(), what], "dots")
	elif o.get("forced", false) or autonomy:
		# Free will: try the next best target now instead of idling.
		idle_minutes = AUTONOMY_AFTER
		_fallback_need = o.get("forced", false)


var _fallback_need := false
var _fail_at := Vector3.INF
var _fail_streak := 0
var resets := 0


## Move onto the nearest open floor cell of this storey (false if none).
func unstick() -> bool:
	var nav = world.nav
	if nav == null:
		return false
	var p: Vector3 = actor.global_position
	var li: int = nav.level_of(p)
	var c: Vector2i = nav.nearest_open(li, nav.cell_of(p), 40)
	if c.x < 0:
		return false
	var q: Vector3 = nav.center_of(li, c)
	resets += 1
	unreachable.clear()
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  reset: %s %s -> %s" % [display_name(), str(p), str(q)])
	actor.global_position = q
	Game.show_bubble(actor, {"kind": "emote", "icon": "dots", "id": "say", "ttl": 1.0})
	return true


func is_unreachable(t) -> bool:
	if not unreachable.has(t):
		return false
	if Game.total_minutes() > float(unreachable[t]):
		unreachable.erase(t)
		return false
	return true


# =================================================================== per frame

func tick(delta: float, dm: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if phase == "away":
		_tick_away(dm)
		return
	if dm > 0.0:
		_need_acc += dm
		_force_cool = maxf(0.0, _force_cool - dm)
		if _need_acc >= NEED_CHECK_EVERY:
			_need_acc = 0.0
			check_needs()
			check_career()
	match phase:
		"idle":
			_idle(delta, dm)
		"walk":
			_walk(delta)
		"wait":
			wait_minutes += dm
			var t = order.get("target")
			if t == null or not is_instance_valid(t) or world.user_of(t) == null or world.user_of(t) == self:
				_arrive()
			elif wait_minutes > 45.0:
				_say("Busy...", "dots")
				_end(false)
		"act":
			_act(dm)


func _idle(delta: float, dm: float) -> void:
	if actor.get("pose") == "walk":
		actor.set_pose("idle")
	idle_minutes += dm
	_thought_t -= delta * (1.0 if dm > 0.0 else 0.0)
	if _thought_t <= 0.0:
		_thought_t = 14.0
		var low := lowest_need()
		if low != "" and member.needs[low] < 0.25:
			Game.show_bubble(actor, {"kind": "thought", "icon": SimActions.need_icon(low, kind), "id": "thought", "ttl": 3.0})
	var wait := AUTONOMY_AFTER
	var low_need := lowest_need()
	if low_need != "" and member.needs[low_need] < 0.2:
		wait = AUTONOMY_URGENT_AFTER
	if autonomy and idle_minutes >= wait and dm > 0.0:
		idle_minutes = 0.0
		var o: Dictionary
		if _fallback_need:
			# A forced need-fix couldn't reach its target: next best fix.
			_fallback_need = false
			o = world.choose_for_need(self, lowest_need())
			if not o.is_empty():
				o["forced"] = true
		if o.is_empty():
			o = world.choose_autonomous(self)
		if not o.is_empty():
			o["auto"] = true
			command(o, false)


func lowest_need() -> String:
	var best := ""
	var bv := 2.0
	for k in member.needs:
		if member.needs[k] < bv:
			bv = member.needs[k]
			best = k
	return best


func _speed_mult() -> float:
	if Game.frozen or Game.speed == 0:
		return 0.0
	# Walking keeps up with the clock (Sims 3: fast-forward moves sims faster too).
	return [0.0, 1.0, 3.0, 6.0][Game.speed]


func _walk(delta: float) -> void:
	var mult := _speed_mult()
	var spd := base_speed * mult
	actor.set("walk_speed", maxf(spd, 0.0001) if mult > 0.0 else 0.0)
	if mult <= 0.0:
		return
	walk_real += delta * mult
	# A social partner who walked off: head for where they are now.
	var other = order.get("other")
	_repath_cool = maxf(0.0, _repath_cool - delta * mult)
	if other != null and is_instance_valid(other.actor) and _other_at != Vector3.INF and _repath_cool <= 0.0:
		if _flat(other.actor.global_position, _other_at) > 1.0 and _on_floor():
			var r: Dictionary = world.approach(self, order)
			if not r.is_empty():
				spot = r.spot
				face_point = r.get("face", Vector3.INF)
				_other_at = other.actor.global_position
				_repath_cool = 1.0
				if not _plan_path():
					_give_up()
					return
	var remaining := spd * delta
	var pos := actor.global_position
	while remaining > 0.0 and path_i < path.size():
		var tgt: Vector3 = path[path_i]
		var to := Vector2(tgt.x - pos.x, tgt.z - pos.z)
		var d := to.length()
		if d <= remaining:
			pos = tgt
			remaining -= d
			path_i += 1
			seg_from = tgt
		else:
			var dir := to / d
			pos.x += dir.x * remaining
			pos.z += dir.y * remaining
			var seg := Vector2(tgt.x - seg_from.x, tgt.z - seg_from.z).length()
			var k := 1.0 - (d - remaining) / maxf(seg, 0.001)
			pos.y = lerpf(seg_from.y, tgt.y, clampf(k, 0.0, 1.0))
			remaining = 0.0
			var want := atan2(dir.x, dir.y)
			actor.rotation.y = lerp_angle(actor.rotation.y, want, 1.0 - exp(-delta * 12.0 * mult))
	actor.global_position = pos
	# Tolerant arrival: close enough on the same storey (and not mid-stairs).
	var near := _flat(pos, spot) <= ARRIVE_TOL and absf(pos.y - spot.y) < 0.5
	if path_i >= path.size() or (near and path_i >= path.size() - 2):
		_arrive()
		return
	_check_stuck(delta * mult)


## Progress watchdog: the remaining route length must keep shrinking.
func _check_stuck(dt: float) -> void:
	_stuck_t += dt
	if _stuck_t < STUCK_CHECK:
		return
	_stuck_t = 0.0
	var rem := _remaining_len()
	if _stuck_rem - rem >= STUCK_MIN:
		_stuck_rem = rem
		return
	_stuck_n += 1
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  stuck: %s at %s (remaining %.2f m, try %d)" % [display_name(), str(actor.global_position), rem, _stuck_n])
	if _stuck_n > MAX_REPATHS:
		# Last resort: if the spot is close, just step onto it; else give up.
		if _flat(actor.global_position, spot) < 1.2 and absf(actor.global_position.y - spot.y) < 0.6:
			_arrive()
		else:
			_give_up()
		return
	repaths += 1
	if _on_floor():
		if not _plan_path():
			_give_up()
			return
	else:
		# Mid-stairs: skip ahead to the next waypoint instead of replanning.
		if path_i < path.size():
			actor.global_position = path[path_i]
			seg_from = path[path_i]
			path_i += 1
	_stuck_rem = _remaining_len()


func _remaining_len() -> float:
	if path_i >= path.size():
		return 0.0
	var d := actor.global_position.distance_to(path[path_i])
	for k in range(path_i, path.size() - 1):
		d += path[k].distance_to(path[k + 1])
	return d


## Standing on a storey (not on a stair segment between levels).
func _on_floor() -> bool:
	if world.nav == null:
		return true
	var p: Vector3 = actor.global_position
	return absf(p.y - world.nav.floor_y(p)) < 0.3


## Abandon the current walk: route-fail it and (for free will) move on.
func _give_up() -> void:
	if order.get("work", false):
		_leave_for_work()
		return
	var o := order
	fallbacks += 1
	_route_fail(o)
	_end(false)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _arrive() -> void:
	var a: Dictionary = order.get("action", {})
	actor.global_position = spot
	actor.set("walk_speed", base_speed)
	if a.get("id", "") == "go_here":
		actor.set_pose("idle")
		_end(true)
		return
	if order.get("work", false):
		_leave_for_work()
		return
	var t = order.get("target")
	if t != null and is_instance_valid(t):
		var u = world.user_of(t)
		if u != null and u != self and not world.shareable(t):
			if phase != "wait":
				phase = "wait"
				actor.set_pose("idle")
				_say("Waiting...", "dots")
			return
		world.reserve(t, self)
		_reserved = t
	if face_point != Vector3.INF:
		actor.face(face_point)
	_begin_act()


func _begin_act() -> void:
	var a: Dictionary = order.get("action", {})
	phase = "act"
	elapsed = 0.0
	var pose: String = a.get("pose", "idle")
	if kind == "dog" and not pose in SimActions.DOG_POSES:
		pose = "idle"
	var seated: bool = pose.begins_with("sit") and pose != "sit_floor" or pose in ["type", "read"]
	if kind != "dog" and world.nav:
		var sh: float = world.nav.seat_height(spot)
		if seated:
			actor.set("seat_height", sh if sh > 0.2 and sh < 0.75 else 0.45)
		elif pose in ["lie", "sleep"]:
			actor.set("lie_height", sh if sh > 0.2 and sh < 0.85 else 0.5)
	actor.set_pose(pose)
	var other = order.get("other")
	if other != null and other.actor and is_instance_valid(other.actor):
		other.join_social(self, a)
	var t = order.get("target")
	if t != null and is_instance_valid(t):
		var npc = t.get_parent()
		if npc is SimActor and not world.is_household_actor(npc):
			npc.face(actor.global_position)
			if a.get("pose", "") in ["talk", "wave", "sit_talk"]:
				npc.set_pose("talk")
	_bubble(0.0, true)


## Another household member started a social with us: stop and face them.
func join_social(from_agent, _a: Dictionary) -> void:
	if phase == "act" and order.get("other") == from_agent:
		return
	# Free will may drop what it was doing for a chat; something the player
	# asked for carries on (the other sim talks while we walk past).
	if phase == "walk" and order.get("auto", false) and not order.get("forced", false):
		cancel_current()
	if phase == "idle":
		actor.face(from_agent.actor.global_position)
		actor.set_pose("talk" if kind != "dog" else "play")
		idle_minutes = -30.0  # stay engaged instead of wandering off


func _act(dm: float) -> void:
	var a: Dictionary = order.get("action", {})
	var mins: float = maxf(1.0, a.get("minutes", 30.0))
	if dm <= 0.0:
		return
	if order.get("work_home", false):
		# A home shift ends with the clock, not after a fixed duration.
		dm = maxf(dm, (mins - (float(member.work.until) - Game.total_minutes())) - elapsed)
	var step := minf(dm, mins - elapsed)
	elapsed += step
	var eff: Dictionary = a.get("needs", {})
	for k in eff:
		Game.change_need(index, k, float(eff[k]) * step / mins)
	if a.has("skill"):
		# A good mood makes practice count for more (0.6x .. 1.4x).
		var lvl: int = Game.add_skill_xp(index, a.skill, step / 60.0 * Game.mood_mult(index) * Traits.skill_mult(member, a.skill))
		_skill_t += step
		if lvl > 0:
			_skill_t = 0.0
			Game.show_bubble(actor, {"kind": "skill", "text": "%s Lv %d!" % [a.skill, lvl], "icon": "star", "id": "skill", "ttl": 3.5})
			Game.add_moodlet(index, "learned", "Learned Something", "bulb", 12.0, 4.0, "Reached %s level %d" % [a.skill, lvl])
			Game.notify.emit("%s reached %s level %d" % [display_name(), a.skill, lvl], skill_icon(a.skill))
		elif _skill_t >= SKILL_CHIP_EVERY:
			_skill_t -= SKILL_CHIP_EVERY
			Game.show_bubble(actor, {"kind": "skill", "text": a.skill, "icon": skill_icon(a.skill), "id": "skill"})
	if elapsed >= mins - 0.0001:
		_bubble(1.0, true)
		_complete()
	else:
		_bubble(elapsed / mins)


func _complete() -> void:
	var a: Dictionary = order.get("action", {})
	var m := int(a.get("money", 0))
	if a.get("id", "") == "bills":
		m = -Game.bills_due_total()
	if a.get("id", "") in ["homework", "s_homework"]:
		member["homework_day"] = Game.day
	if a.get("id", "") == "s_homework" and order.get("other") != null:
		order.other.member["homework_day"] = Game.day
	if a.has("money_per_level") and a.has("skill"):
		m += int(floorf(Game.skill_level(index, a.skill))) * int(a.money_per_level)
	if m > 0:
		# Mood scales pay: a happy sim works better.
		m = roundi(m * Game.mood_mult(index))
	last_pay = m
	if m != 0:
		if OS.has_environment("VIMS_PLAYTEST"):
			print("  money: %s %s %+d (%s)" % [display_name(), a.get("id", ""), m, "auto" if order.get("auto", false) else "player"])
		if Game.add_money(m):
			_say(("+$%d" if m > 0 else "-$%d") % absi(m), "money")
			if a.get("id", "") == "bills":
				# add_money already took it: just clear the stack of bills.
				Game.bills.clear()
				for i in Game.household.size():
					Game.remove_moodlet(i, "overdue_bills")
				Game.bills_changed.emit()
		else:
			_say("Can't afford it", "money")
	# Relationships: socials change friendship (and may be rejected).
	var rejected := false
	if a.has("rel"):
		rejected = _apply_social(a)
	# (A dog playing on its own doesn't tick "Play with Dog".)
	if a.has("task") and not rejected and not (kind == "dog" and "Dog" in str(a.task)) and _meet_task_ok(str(a.task)):
		if Game.complete_task_title(a.task):
			Game.add_moodlet(index, "accomplished", "Accomplished", "trophy", 10.0, 4.0, "Finished \"%s\"" % a.task)
			Game.notify.emit("Task done: %s" % a.task, "trophy")
	if not rejected:
		_positive_moodlets(a, m)
		if a.has("moodlet"):
			var ml: Array = a.moodlet
			Game.add_moodlet(index, ml[0], ml[1], ml[2], ml[3], ml[4], a.get("label", ""))
	# Effects on other household members (feed the dog, pet the dog...).
	var fx: Dictionary = SimActions.EFFECT_ON_KIND.get(a.get("id", ""), {})
	for k in fx:
		for i in Game.household.size():
			if Game.household[i].get("kind", "") == k and i != index:
				for need in fx[k]:
					Game.change_need(i, need, fx[k][need])
	var other = order.get("other")
	if other != null and a.has("pet_skill") and not rejected:
		var lv: int = Game.add_skill_xp(other.index, a.pet_skill, float(a.get("minutes", 20.0)) / 60.0)
		if lv > 0:
			Game.notify.emit("%s reached %s level %d" % [other.display_name(), a.pet_skill, lv], "star")
	if other != null and a.has("social") and not rejected:
		for need in a.social:
			Game.change_need(other.index, need, a.social[need])
		var olab := "Played Together" if (kind == "dog" or other.kind == "dog") else "Good Conversation"
		Game.add_moodlet(other.index, "good_social", olab, "heart", 8.0, 3.0, "With %s" % display_name())
		if other.phase == "idle":
			other.actor.set_pose("idle")
			other.idle_minutes = 0.0
	completed += 1
	last_done = a.get("id", "")
	if order.get("work_home", false):
		member.work.state = ""
		_evaluate_shift(1.0)
	world.on_action_done(self, order)
	_end(true)


## Who this social is with: a household agent's name or a townie's name.
func _social_partner_name() -> String:
	var other = order.get("other")
	if other != null:
		return other.display_name()
	var a: Dictionary = order.get("action", {})
	if a.has("townie"):
		return str(a.townie)
	return world.townie_of(order.get("target"))


## Apply a social's friendship change. Returns true when it was rejected.
func _apply_social(a: Dictionary) -> bool:
	var partner := _social_partner_name()
	if partner == "":
		return false
	var me := display_name()
	var delta := float(a.get("rel", 0.0))
	var reject_p := 0.0
	var other = order.get("other")
	var info: Dictionary = world.townie_info(partner)
	if delta > 0.0 and not a.get("stranger", false):
		if other != null and Game.mood_band(other.index) == "bad":
			reject_p = 0.3
		elif info.get("trait", "") == "Grumpy":
			reject_p = 0.2
	if a.get("id", "") == "s_joke" and info.get("trait", "") == "Good Sense of Humor":
		delta *= 1.5
	if delta > 0.0:
		# A good mood makes you better company (x0.75 .. x1.25).
		delta *= clampf(0.75 + (Game.mood_mult(index) - 0.6) / 0.8 * 0.5, 0.75, 1.25)
		# Friendly / Family-Oriented / Loyal sims bond faster.
		delta *= Traits.rel_mult(member, other != null)
		# Sims 3 pacing: close friends gain slowly, and the same pair
		# chatting again straight away counts for less.
		delta *= clampf(1.0 - maxf(Game.rel(me, partner), 0.0) / 140.0, 0.3, 1.0)
		var rr = Game.relationships.get(Game.rel_key(me, partner))
		if rr != null and Game.total_minutes() - float(rr.last) < 60.0:
			delta *= 0.6
	if reject_p > 0.0 and randf() < reject_p:
		Game.change_rel(me, partner, -absf(delta) * 0.5)
		Game.add_moodlet(index, "rejected", "Rejected", "dots", -10.0, 2.0, "%s wasn't in the mood" % partner)
		_say("Hmph!", "dots")
		if OS.has_environment("VIMS_PLAYTEST"):
			print("  social rejected: %s -> %s (%s)" % [me, partner, a.get("label", "")])
		return true
	var v := Game.change_rel(me, partner, delta)
	if other == null:
		world.met_here[partner] = true
	Game.show_bubble(actor, {"kind": "emote", "icon": "heart" if delta > 0.0 else "dots", "id": "say", "ttl": 1.6})
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  social: %s -> %s %s %+.1f = %.1f (%s)" % [me, partner, a.get("label", ""), delta, v, Game.rel_level(v)])
	return false


## "Meet 3 Neighbors" needs three different townies on this lot.
func _meet_task_ok(task: String) -> bool:
	if not task.begins_with("Meet "):
		return true
	var w := task.get_slice(" ", 1)
	var need := 1 if w in ["a", "an"] else maxi(1, w.to_int())
	var have: int = world.met_here.size()
	if have < need and Game.has_open_task(task):
		Game.notify.emit("%s: %d of %d" % [task, have, need], "people")
	return have >= need


func _end(_ok: bool) -> void:
	if order.get("work", false) and phase != "away":
		member.work.state = ""
	if order.get("work_home", false) and str(member.work.get("state", "")) == "home":
		# Stopped before the shift was over (cancelled, passed out...).
		member.work.state = ""
		var span := maxf(1.0, float(member.work.until) - float(member.work.start))
		var frac := clampf(elapsed / span, 0.0, 1.0) if phase == "act" else 0.0
		if frac > 0.02:
			_evaluate_shift(frac)
		else:
			member.career.last_day = -1   # never sat down: try again
	if _reserved != null:
		world.release(_reserved, self)
		_reserved = null
	var t = order.get("target")
	if t != null and is_instance_valid(t):
		var npc = t.get_parent()
		if npc is SimActor and not world.is_household_actor(npc) and npc.pose == "talk":
			npc.set_pose("idle")
	var other = order.get("other")
	if other != null and other.phase == "idle" and is_instance_valid(other.actor):
		other.actor.set_pose("idle")
		other.idle_minutes = 0.0
	_social_partner = null
	Game.clear_bubble(actor, "action")
	actor.set("walk_speed", base_speed)
	if actor.get("pose") != "idle":
		actor.set_pose("idle")
	phase = "idle"
	order = {}
	idle_minutes = 0.0
	_next()


# =================================================================== bubbles

func _bubble(p: float, force := false) -> void:
	var a: Dictionary = order.get("action", {})
	if a.is_empty() or a.get("id", "") == "go_here":
		return
	var q := int(p * 100.0)
	if q == _shown_prog and not force:
		return
	_shown_prog = q
	Game.show_bubble(actor, {"kind": "action", "text": a.get("label", ""), "icon": a.get("icon", ""),
		"progress": p, "id": "action", "ttl": -1.0})
	var view: Array = Game.queue_view(index)
	if not view.is_empty() and view[0].get("current", false):
		view[0].progress = p


func _say(text: String, icon := "") -> void:
	Game.show_bubble(actor, {"kind": "speech", "text": text, "icon": icon, "id": "say", "ttl": 2.5})


static func skill_icon(skill: String) -> String:
	match skill:
		"Creativity": return "bulb"
		"Music": return "arrow_up"
		"Logic": return "chart"
		"Cooking": return "cook"
	return "arrow_up"


# =================================================================== mood / consequences

## Positive moodlets for a finished action.
func _positive_moodlets(a: Dictionary, money: int) -> void:
	var id: String = a.get("id", "")
	var eff: Dictionary = a.get("needs", {})
	if id == "pass_out":
		return
	if id == "sleep" and float(member.needs.get("energy", 0.0)) >= 0.8:
		Game.add_moodlet(index, "well_rested", "Well Rested", "need_energy", 15.0, 8.0, "A full night's sleep")
	elif float(eff.get("energy", 0.0)) >= 0.25:
		Game.add_moodlet(index, "refreshed", "Refreshed", "zzz", 6.0, 3.0, "A nice nap")
	var hunger := float(eff.get("hunger", 0.0))
	if hunger >= 0.5:
		if kind == "dog":
			Game.add_moodlet(index, "good_meal", "Tasty Kibble", "bone", 10.0, 4.0)
		elif a.has("skill") and "Cook" in str(a.skill):
			Game.add_moodlet(index, "good_meal", "Delicious Meal", "cook", 12.0, 4.0, "Home cooking")
		else:
			Game.add_moodlet(index, "good_meal", "Good Meal", "plate", 8.0, 4.0)
	if float(eff.get("fun", 0.0)) >= 0.15:
		Game.add_moodlet(index, "had_fun", "Had Fun", "need_fun", 10.0, 3.0, a.get("label", ""))
	if float(eff.get("hygiene", 0.0)) >= 0.5:
		Game.add_moodlet(index, "clean", "Squeaky Clean", "need_hygiene", 8.0, 4.0)
	if a.has("social"):
		var lab := "Played Together" if kind == "dog" else "Good Conversation"
		Game.add_moodlet(index, "good_social", lab, "heart", 10.0, 3.0)
	if money < 0 and id == "bills":
		Game.add_moodlet(index, "bills_paid", "Bills Paid", "bill", 6.0, 6.0, "One less worry")
	elif money > 0:
		Game.add_moodlet(index, "productive", "Productive", "work", 6.0, 4.0, "Earned $%d" % money)
	# Effects on the dog (fed / petted by family).
	if id in ["feed_dog", "pet", "s_pet", "fetch", "s_fetch"]:
		for i in Game.household.size():
			if Game.household[i].get("kind", "") == "dog" and i != index:
				if id == "feed_dog":
					Game.add_moodlet(i, "good_meal", "Tasty Kibble", "bone", 10.0, 4.0)
				else:
					Game.add_moodlet(i, "belly_rubs", "Belly Rubs", "paw", 12.0, 3.0, "Loved by %s" % display_name())


## Needs -> moodlets, warnings and (at zero) forced consequences.
func check_needs() -> void:
	var needs: Dictionary = member.needs
	for k in needs:
		var v: float = needs[k]
		var spec: Array = NEED_MOODLETS.get(k, [])
		if spec.size() == 2:
			var mild: Array = spec[0]
			var strong: Array = spec[1]
			var mild_icon: String = SimActions.need_icon(k, kind)
			if v < strong[4]:
				Game.remove_moodlet(index, mild[0])
				Game.add_moodlet(index, strong[0], strong[1], mild_icon, strong[3], 0.0)
			elif v < mild[4]:
				Game.remove_moodlet(index, strong[0])
				Game.add_moodlet(index, mild[0], mild[1], mild_icon, mild[3], 0.0)
			elif v > RECOVER:
				Game.remove_moodlet(index, strong[0])
				Game.remove_moodlet(index, mild[0])
		# Warning toast once per dip.
		if v < WARN_BELOW and not _warned.get(k, false):
			_warned[k] = true
			Game.notify.emit(WARN_TEXT.get(k, "%s needs attention") % display_name(), SimActions.need_icon(k, kind))
			Game.show_bubble(actor, {"kind": "thought", "icon": SimActions.need_icon(k, kind), "id": "thought", "ttl": 3.0})
		elif v > RECOVER:
			_warned[k] = false
	if _force_cool > 0.0:
		return
	# Consequences at zero.
	if needs.has("energy") and needs.energy <= 0.0 and kind != "dog" and not _doing_need("energy"):
		pass_out()
	elif needs.has("bladder") and needs.bladder <= 0.0:
		accident()
	elif needs.has("hunger") and needs.hunger <= 0.02 and not _doing_need("hunger") and phase != "walk":
		_force_need("hunger")
	elif kind == "dog" and needs.has("energy") and needs.energy <= 0.0 and not _doing_need("energy"):
		_force_need("energy")


func _doing_need(need: String) -> bool:
	return not order.is_empty() and float(order.get("action", {}).get("needs", {}).get(need, 0.0)) > 0.0


## Energy hit zero: drop everything and fall asleep on the spot.
func pass_out() -> void:
	forced += 1
	_force_cool = 60.0
	queue.clear()
	if phase != "idle":
		var keep := queue
		_end(false)
		queue = keep
	if _reserved != null:
		world.release(_reserved, self)
		_reserved = null
	order = {"action": PASS_OUT, "auto": true, "forced": true}
	spot = actor.global_position
	phase = "act"
	elapsed = 0.0
	_shown_prog = -1
	actor.set("lie_height", 0.06)
	actor.set_pose("sleep")
	Game.add_moodlet(index, "passed_out", "Passed Out", "zzz", -25.0, 6.0, "Collapsed from exhaustion")
	Game.notify.emit("%s passed out from exhaustion!" % display_name(), "zzz")
	_bubble(0.0, true)
	_sync_queue()


## Bladder hit zero: an accident (hygiene crash, embarrassment).
func accident() -> void:
	forced += 1
	_force_cool = 30.0
	cancel_all()
	Game.change_need(index, "bladder", 1.0)
	Game.remove_moodlet(index, "desperate")
	Game.remove_moodlet(index, "gotta_go")
	if member.needs.has("hygiene"):
		member.needs.hygiene = 0.02
	Game.add_moodlet(index, "embarrassed", "Embarrassed", "need_bladder", -30.0, 4.0, "Had an accident")
	_say("Oh no!", "need_bladder")
	Game.notify.emit("%s had an accident!" % display_name(), "need_bladder")
	Game.needs_changed.emit(index)


## Starving (or a dog out of energy): free will takes over whatever the
## player queued and fixes the need first.
func _force_need(need: String) -> void:
	var o: Dictionary = world.choose_for_need(self, need)
	if o.is_empty():
		return
	forced += 1
	_force_cool = 45.0
	o["auto"] = true
	o["forced"] = true
	var keep: Array = queue.filter(func(q): return not q.get("auto", false))
	queue.clear()
	if phase != "idle":
		_end(false)
	queue = keep
	queue.push_front(o)
	_say(REFUSE_TEXT.get(need, "..."), SimActions.need_icon(need, kind))
	Game.notify.emit(WARN_TEXT.get(need, "%s needs attention") % display_name() + "!", SimActions.need_icon(need, kind))
	if phase == "idle":
		_next()


# =================================================================== work / school (rabbit hole)

var _away_acc := 0.0
## Shifts finished / missed (playtest diagnostics).
var shifts_done := 0
var shifts_missed := 0


## Every few minutes: is it time to leave for work / school?
func check_career() -> void:
	var c: Dictionary = member.get("career", {})
	if c.is_empty() or not Game.work_enabled:
		return
	var w: Dictionary = member.work
	if w.state != "":
		return
	var d := Game.day
	if int(c.get("last_day", -1)) == d or not Careers.works_on(c, d):
		return
	var now := Game.total_minutes()
	var st := Careers.shift_start(c, d)
	var lead: float = Careers.HOME_LEAD if Careers.track(c).get("home", false) else Careers.LEAVE_BEFORE
	if now < st - lead or now >= Careers.shift_end(c, d):
		return
	if now > st + Careers.MISS_AFTER:
		miss_shift()
		return
	# Out cold: the carpool waits a little, then leaves without them.
	if order.get("action", {}).get("id", "") == "pass_out":
		return
	go_to_work()


## Forced "Go to Work": drop what we're doing (player orders wait for the
## evening), walk to the door / lot edge, get into the carpool.
func go_to_work() -> void:
	var c: Dictionary = member.career
	if Careers.track(c).get("home", false):
		_work_from_home()
		return
	var school := Careers.is_school(c)
	member.work.state = "going"
	var exit: Vector3 = world.exit_spot(actor.global_position)
	var a := {"id": "go_to_work", "label": "Go to School" if school else "Go to Work", "icon": "book" if school else "laptop",
		"minutes": 0.0, "pose": "idle"}
	var o := {"action": a, "point": exit, "auto": true, "forced": true, "work": true}
	forced += 1
	queue.clear()
	if phase != "idle":
		_end(false)
		member.work.state = "going"
	queue.clear()
	queue.push_front(o)
	_say("Off to school!" if school else "Off to work!", "book" if school else "laptop")
	Game.notify.emit(("The school bus is here for %s" if school else "The carpool is here for %s") % display_name(), "book" if school else "laptop")
	world.carpool(exit, "bus" if school else "car", 6.0)
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  work: %s leaves for %s (%s) at %s" % [display_name(), Careers.track(c).name, Game.clock_text(), str(exit)])
	if phase == "idle":
		_next()


## Into the carpool: hidden until the shift ends.
func _leave_for_work() -> void:
	var c: Dictionary = member.career
	var w: Dictionary = member.work
	var now := Game.total_minutes()
	var st := Careers.shift_start(c, Game.day)
	w.state = "away"
	_chance_rolled = false
	chance = {}
	w.start = now
	w.until = Careers.shift_end(c, Game.day)
	w.late = now > st + 5.0
	c.last_day = Game.day
	if _reserved != null:
		world.release(_reserved, self)
		_reserved = null
	Game.clear_bubble(actor, "")
	order = {}
	queue.clear()
	path = PackedVector3Array()
	phase = "away"
	_away_acc = 0.0
	actor.set("walk_speed", base_speed)
	actor.set_pose("idle")
	actor.visible = false
	var school := Careers.is_school(c)
	if w.late:
		Game.add_moodlet(index, "late_work", "Late for School" if school else "Late for Work", "dots", -8.0, 3.0, "Missed the start of the shift")
		Game.notify.emit("%s is late for %s!" % [display_name(), "school" if school else "work"], "dots")
	Game.career_changed.emit(index)
	_sync_queue()


## Hidden at work: count down, keep the queue strip's progress moving.
func _tick_away(dm: float) -> void:
	if dm <= 0.0:
		return
	# Lunch, coffee and the restroom at work: those needs don't drain.
	var hours := dm / 60.0
	for k in ["bladder", "hunger", "hygiene"]:
		if member.needs.has(k):
			var keep := 1.0 if k == "bladder" else 0.6
			Game.change_need(index, k, hours * float(Game.NEED_DECAY.get(k, 0.04)) * keep)
	_away_acc += dm
	if _away_acc >= 5.0:
		_away_acc = 0.0
		_sync_queue()
	var w: Dictionary = member.work
	if Game.total_minutes() >= float(w.until):
		if not chance.is_empty():
			resolve_chance(false)   # nobody answered: carry on as normal
		come_home()
		return
	# Halfway through a job shift: maybe a chance card.
	if not _chance_rolled and not Careers.is_school(member.career) and Game.chance_cards:
		var span := maxf(1.0, float(w.until) - float(w.start))
		if (Game.total_minutes() - float(w.start)) / span >= 0.5:
			_chance_rolled = true
			if randf() < Careers.CHANCE_P:
				offer_chance(Careers.CHANCES[randi() % Careers.CHANCES.size()])


## Restore the away state on a freshly built lot (traveling mid-shift).
func set_away() -> void:
	phase = "away"
	order = {}
	queue.clear()
	actor.visible = false
	_sync_queue()


## Shift over: dropped off at the door, paycheck, performance, promotion.
func come_home() -> void:
	var c: Dictionary = member.career
	var w: Dictionary = member.work
	var school := Careers.is_school(c)
	var drop: Vector3 = world.exit_spot(actor.global_position)
	actor.global_position = drop
	actor.visible = true
	actor.set_pose("idle")
	world.carpool(drop, "bus" if school else "car", 1.5)
	w.state = ""
	phase = "idle"
	order = {}
	idle_minutes = 0.0
	var sn: Dictionary = Careers.shift_needs(c)
	for k in sn:
		Game.change_need(index, k, float(sn[k]))
	_evaluate_shift(1.0)


## Paycheck, performance, notices and promotion after a shift (frac: the
## part of the shift actually worked; a home worker who stops early).
func _evaluate_shift(frac: float) -> void:
	var c: Dictionary = member.career
	var w: Dictionary = member.work
	var school := Careers.is_school(c)
	shifts_done += 1
	# Performance: tendency, mood, skill, lateness, traits, homework.
	var t: Dictionary = Careers.track(c)
	var sk := Game.skill_level(index, str(t.get("skill", ""))) if str(t.get("skill", "")) != "" else 0.0
	var hw := int(member.get("homework_day", -10)) >= Game.day - 1
	var d := Careers.perf_delta(c, Game.mood(index), sk, bool(w.late), Traits.work_bonus(member), hw)
	if frac < 0.95:
		d = d * frac - 10.0
		Game.add_moodlet(index, "left_early", "Left Work Early", "dots", -6.0, 3.0, "Only did %d%% of the shift" % roundi(frac * 100.0))
	c.perf = clampf(float(c.perf) + d, 0.0, 100.0)
	c.trend = d
	c.shifts = int(c.get("shifts", 0)) + 1
	var pay := roundi(Careers.paycheck(c) * clampf(frac, 0.0, 1.0))
	# Overtime from a chance card is paid by the hour.
	pay += roundi(Careers.wage(c) * last_overtime)
	last_overtime = 0.0
	last_pay = pay
	if pay > 0:
		Game.add_money(pay)
	var arrow := "▲" if d >= 0.0 else "▼"
	if school:
		var g := Careers.grade(float(c.perf))
		Game.notify.emit("%s is home from school · Grade %s %s" % [display_name(), g, arrow], "book")
		Game.show_bubble(actor, {"kind": "skill", "text": "Grade %s" % g, "icon": "book", "id": "skill", "ttl": 3.5})
		if g in ["A", "A+"]:
			Game.add_moodlet(index, "honor_roll", "Honor Roll", "trophy", 12.0, 12.0, "Grade %s at school" % g)
		elif g in ["D", "F"]:
			Game.add_moodlet(index, "bad_grades", "Bad Grades", "book", -10.0, 12.0, "Do homework to bring it up")
		if not hw:
			Game.notify.emit("%s has homework to do" % display_name(), "book")
	else:
		var home: bool = Careers.track(c).get("home", false)
		Game.notify.emit("%s %s · Paycheck +$%d · Performance %s%d" % [display_name(), "finished work" if home else "is home from work", pay, arrow, absi(roundi(d))], "money")
		Game.show_bubble(actor, {"kind": "skill", "text": "+$%d" % pay, "icon": "money", "id": "skill", "ttl": 3.5})
		match str(c.get("tendency", "normal")):
			"hard":
				if not Traits.has(member, "Workaholic"):
					Game.add_moodlet(index, "long_day", "Long Day at Work", "laptop", -10.0, 4.0, "Worked hard")
				else:
					Game.add_moodlet(index, "good_day", "Great Day at Work", "laptop", 10.0, 4.0, "Workaholics love working hard")
			"easy":
				Game.add_moodlet(index, "easy_day", "Easy Day at Work", "smile", 6.0, 4.0, "Took it easy")
		_review(c, sk)
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  work: %s home from %s, pay %d, perf %+.1f -> %.1f, level %d (%s)" % [display_name(), t.get("name", "?"), pay, d, float(c.perf), int(c.get("level", 0)), Game.clock_text()])
	world.on_shift_done(self, pay)
	Game.career_changed.emit(index)
	Game.needs_changed.emit(index)
	check_needs()
	_sync_queue()


## Promotion / demotion / firing after a shift.
func _review(c: Dictionary, sk: float) -> void:
	var t: Dictionary = Careers.track(c)
	if float(c.perf) >= Careers.PROMOTE_AT:
		var need := Careers.next_req(c)
		if need < 0:
			var bonus := Careers.paycheck(c)
			Game.add_money(bonus)
			c.perf = 80.0
			Game.notify.emit("%s got a top-of-the-career bonus: $%d" % [display_name(), bonus], "trophy")
		elif sk >= need:
			c.level = int(c.level) + 1
			c.perf = Careers.PERF_AFTER_PROMO
			var bonus := Careers.paycheck(c) / 2
			Game.add_money(bonus)
			Game.add_moodlet(index, "promoted", "Promoted!", "trophy", 25.0, 12.0, "Now %s" % Careers.title(c))
			Game.notify.emit("%s was promoted to %s! Bonus $%d" % [display_name(), Careers.title(c), bonus], "trophy")
			Game.show_bubble(actor, {"kind": "skill", "text": "Promoted!", "icon": "trophy", "id": "skill", "ttl": 4.0})
			world.on_promotion(self)
		else:
			c.perf = 99.0
			Game.notify.emit("%s needs %s level %d for a promotion" % [display_name(), t.get("skill", ""), need], "chart")
	elif float(c.perf) <= Careers.DEMOTE_AT:
		if int(c.level) > 1:
			c.level = int(c.level) - 1
			c.perf = Careers.PERF_AFTER_DEMO
			Game.add_moodlet(index, "demoted", "Demoted", "dots", -20.0, 12.0, "Now %s" % Careers.title(c))
			Game.notify.emit("%s was demoted to %s" % [display_name(), Careers.title(c)], "dots")
		else:
			member["career"] = {}
			Game.add_moodlet(index, "fired", "Fired!", "dots", -25.0, 24.0, "Lost the %s job" % t.get("name", ""))
			Game.notify.emit("%s was fired from the %s career!" % [display_name(), t.get("name", "")], "dots")


## Never made it to the shift (passed out, playing elsewhere...).
func miss_shift() -> void:
	var c: Dictionary = member.career
	var school := Careers.is_school(c)
	c.last_day = Game.day
	c.perf = maxf(0.0, float(c.perf) - 20.0)
	c.trend = -20.0
	shifts_missed += 1
	Game.notify.emit("%s missed %s! Performance -20" % [display_name(), "school" if school else "work"], "dots")
	Game.add_moodlet(index, "skipped", "Skipped School" if school else "Missed Work", "dots", -8.0, 6.0, "")
	if not school:
		_review(c, Game.skill_level(index, str(Careers.track(c).get("skill", ""))))
	Game.career_changed.emit(index)


## Home-office careers: at shift time the sim sits down at the computer for
## the rest of the shift (a forced "Work" action with a progress bubble).
func _work_from_home() -> void:
	var c: Dictionary = member.career
	var desk = world.home_desk(self)
	if desk == null:
		miss_shift()
		return
	var now := Game.total_minutes()
	var st := Careers.shift_start(c, Game.day)
	var en := Careers.shift_end(c, Game.day)
	var w: Dictionary = member.work
	w.state = "home"
	w.start = maxf(now, st)
	w.until = en
	w.late = now > st + 5.0
	c.last_day = Game.day
	var a := {"id": "work_home", "label": "Work", "icon": "laptop", "minutes": maxf(30.0, en - now), "pose": "type",
		"needs": {"fun": -0.15, "energy": -0.15}, "skill": str(Careers.track(c).get("skill", "Logic"))}
	var o := {"action": a, "target": desk, "auto": true, "forced": true, "work_home": true}
	forced += 1
	var keep: Array = queue.filter(func(q): return not q.get("auto", false))
	queue.clear()
	if phase != "idle":
		_end(false)
	queue = keep
	queue.push_front(o)
	_say("Time to work!", "laptop")
	Game.notify.emit("%s starts work at the computer" % display_name(), "laptop")
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  work: %s works from home (%s)" % [display_name(), Game.clock_text()])
	if phase == "idle":
		_next()


# =================================================================== chance cards

## The card on offer (empty = none) and whether this shift rolled for one.
var chance: Dictionary = {}
var _chance_rolled := false


func offer_chance(card: Dictionary) -> void:
	chance = card
	Game.notify.emit(str(card.text) % display_name(), str(card.get("icon", "laptop")))
	world.open_chance(self, card)
	if OS.has_environment("VIMS_PLAYTEST"):
		print("  chance: %s -> %s" % [display_name(), card.id])


## The player answered (yes) or not (no / unanswered).
func resolve_chance(yes: bool) -> void:
	if chance.is_empty():
		return
	var card := chance
	chance = {}
	var out: Dictionary = card.get("yes" if yes else "no", {})
	if yes and card.has("odds") and randf() >= float(card.odds):
		out = card.get("fail", out)
	var c: Dictionary = member.get("career", {})
	if c.is_empty():
		return
	c.perf = clampf(float(c.perf) + float(out.get("perf", 0.0)), 0.0, 100.0)
	if out.has("hours") and phase == "away":
		member.work.until = float(member.work.until) + float(out.hours) * 60.0
		last_overtime = float(out.hours)
	if out.has("social"):
		Game.change_need(index, "social", float(out.social))
	if out.has("mood"):
		var ml: Array = out.mood
		Game.add_moodlet(index, ml[0], ml[1], ml[2], ml[3], ml[4], str(card.text) % display_name())
	var p := float(out.get("perf", 0.0))
	if p != 0.0:
		Game.notify.emit("%s: performance %+d" % [display_name(), roundi(p)], "chart" if p > 0.0 else "dots")
	Game.career_changed.emit(index)
	_sync_queue()


var last_overtime := 0.0
