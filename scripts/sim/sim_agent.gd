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
const MAX_QUEUE := 5
## Faster free will when a need is getting low.
const AUTONOMY_URGENT_AFTER := 1.5
## How often (in-game minutes) needs are checked for moodlets / consequences.
const NEED_CHECK_EVERY := 2.0

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
## Sims 3 style: player orders queue up behind each other (up to MAX_QUEUE)
## and push out anything free will had planned; with replace the queue is
## cleared first. Returns false when the sim refuses (critical need, passed out).
func command(o: Dictionary, replace := false) -> bool:
	var a: Dictionary = o.get("action", {})
	var auto: bool = o.get("auto", false)
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
	if phase == "idle":
		return
	_end(false)


func cancel_all() -> void:
	queue.clear()
	cancel_current()
	_sync_queue()


## Cancel one slot of the queue strip (0 = the action in progress).
func cancel_slot(slot: int) -> void:
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
	if dm > 0.0:
		_need_acc += dm
		_force_cool = maxf(0.0, _force_cool - dm)
		if _need_acc >= NEED_CHECK_EVERY:
			_need_acc = 0.0
			check_needs()
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
		# A good mood makes practice count for more (0.6x .. 1.4x).
		var lvl: int = Game.add_skill_xp(index, a.skill, step / 60.0 * Game.mood_mult(index))
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
	if m > 0:
		# Mood scales pay: a happy sim works better.
		m = roundi(m * Game.mood_mult(index))
	last_pay = m
	if m != 0:
		if OS.has_environment("VIMS_PLAYTEST"):
			print("  money: %s %s %+d (%s)" % [display_name(), a.get("id", ""), m, "auto" if order.get("auto", false) else "player"])
		if Game.add_money(m):
			_say(("+$%d" if m > 0 else "-$%d") % absi(m), "money")
		else:
			_say("Can't afford it", "money")
	# (A dog playing on its own doesn't tick "Play with Dog".)
	if a.has("task") and not (kind == "dog" and "Dog" in str(a.task)):
		if Game.complete_task_title(a.task):
			Game.add_moodlet(index, "accomplished", "Accomplished", "trophy", 10.0, 4.0, "Finished \"%s\"" % a.task)
			Game.notify.emit("Task done: %s" % a.task, "trophy")
	_positive_moodlets(a, m)
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
		var olab := "Played Together" if (kind == "dog" or other.kind == "dog") else "Good Conversation"
		Game.add_moodlet(other.index, "good_social", olab, "heart", 8.0, 3.0, "With %s" % display_name())
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
