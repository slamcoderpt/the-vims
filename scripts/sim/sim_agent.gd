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

## Idle in-game minutes before free will kicks in.
const AUTONOMY_AFTER := 8.0
const SKILL_CHIP_EVERY := 15.0   # in-game minutes between "+ Skill" chips
const MAX_QUEUE := 3

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


func display_name() -> String:
	return member.get("name", "?")


func is_busy() -> bool:
	return phase != "idle" or not queue.is_empty()


# =================================================================== commands

## Player (or autonomy) asks for something. Player orders replace autonomous
## ones and the current action; up to MAX_QUEUE player orders queue behind.
func command(o: Dictionary, replace := true) -> void:
	if replace:
		queue.clear()
		if phase != "idle":
			cancel_current()
	if queue.size() >= MAX_QUEUE:
		queue.pop_back()
	queue.append(o)
	if phase == "idle":
		_next()


func cancel_current() -> void:
	if phase == "idle":
		return
	_end(false)


func cancel_all() -> void:
	queue.clear()
	cancel_current()


func current_label() -> String:
	return order.get("action", {}).get("label", "") if not order.is_empty() else ""


func _next() -> void:
	order = {}
	phase = "idle"
	while not queue.is_empty():
		var o: Dictionary = queue.pop_front()
		if _start(o):
			return
	idle_minutes = 0.0


func _start(o: Dictionary) -> bool:
	var t = o.get("target")
	if t != null and not is_instance_valid(t):
		return false
	var other = o.get("other")
	order = o
	var a: Dictionary = o.get("action", {})
	var r: Dictionary = world.approach(self, o)
	if r.is_empty():
		order = {}
		return false
	spot = r.spot
	face_point = r.get("face", Vector3.INF)
	path = world.nav.find_path(actor.global_position, spot, true) if world.nav else PackedVector3Array([spot])
	path_i = 0
	seg_from = actor.global_position
	walk_real = 0.0
	wait_minutes = 0.0
	elapsed = 0.0
	_shown_prog = -1
	_skill_t = 0.0
	if other != null:
		_social_partner = other
	phase = "walk"
	actor.set_pose("walk")
	if a.get("id", "") != "go_here":
		_bubble(0.0, true)
	return true


# =================================================================== per frame

func tick(delta: float, dm: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
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
	if autonomy and idle_minutes >= AUTONOMY_AFTER and dm > 0.0:
		idle_minutes = 0.0
		var o: Dictionary = world.choose_autonomous(self)
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
	return [0.0, 1.0, 2.2, 3.5][Game.speed]


func _walk(delta: float) -> void:
	var mult := _speed_mult()
	var spd := base_speed * mult
	actor.set("walk_speed", maxf(spd, 0.0001) if mult > 0.0 else 0.0)
	if mult <= 0.0:
		return
	walk_real += delta * mult
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
	if path_i >= path.size():
		_arrive()
	elif walk_real > 90.0:
		# Give up on a path that never ends (shouldn't happen): hop there.
		actor.global_position = spot
		_arrive()


func _arrive() -> void:
	var a: Dictionary = order.get("action", {})
	actor.global_position = spot
	actor.set("walk_speed", base_speed)
	if a.get("id", "") == "go_here":
		actor.set_pose("idle")
		_end(true)
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
	if phase == "walk":
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
	var step := minf(dm, mins - elapsed)
	elapsed += step
	var eff: Dictionary = a.get("needs", {})
	for k in eff:
		Game.change_need(index, k, float(eff[k]) * step / mins)
	if a.has("skill"):
		Game.add_skill_xp(index, a.skill, step / 60.0)
		_skill_t += step
		if _skill_t >= SKILL_CHIP_EVERY:
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
	if m != 0:
		if Game.add_money(m):
			_say(("+$%d" if m > 0 else "-$%d") % absi(m), "money")
		else:
			_say("Can't afford it", "money")
	# (A dog playing on its own doesn't tick "Play with Dog".)
	if a.has("task") and not (kind == "dog" and "Dog" in str(a.task)):
		Game.complete_task_title(a.task)
	# Effects on other household members (feed the dog, pet the dog...).
	var fx: Dictionary = SimActions.EFFECT_ON_KIND.get(a.get("id", ""), {})
	for k in fx:
		for i in Game.household.size():
			if Game.household[i].get("kind", "") == k and i != index:
				for need in fx[k]:
					Game.change_need(i, need, fx[k][need])
	var other = order.get("other")
	if other != null and a.has("social"):
		for need in a.social:
			Game.change_need(other.index, need, a.social[need])
		if other.phase == "idle":
			other.actor.set_pose("idle")
			other.idle_minutes = 0.0
	completed += 1
	last_done = a.get("id", "")
	world.on_action_done(self, order)
	_end(true)


func _end(_ok: bool) -> void:
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


func _say(text: String, icon := "") -> void:
	Game.show_bubble(actor, {"kind": "speech", "text": text, "icon": icon, "id": "say", "ttl": 2.5})


static func skill_icon(skill: String) -> String:
	match skill:
		"Creativity": return "bulb"
		"Music": return "arrow_up"
		"Logic": return "chart"
		"Cooking": return "cook"
	return "arrow_up"
