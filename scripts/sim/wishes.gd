extends RefCounted
## Sims 3 wishes: each household member keeps up to SLOTS small wishes rolled
## from what they can do on this lot (practise a skill, use an object, make a
## friend, earn money, eat a family meal...). Fulfilling one gives lifetime
## happiness points (Game.lth) and a moodlet; the player can promise a couple
## (Game.toggle_promise) which pays 1.5x and nudges free will toward them.
## Pure rules: SimWorld calls roll() / on_action() / on_skill() / on_rel().

const SimActions := preload("res://scripts/sim/sim_actions.gd")
const LifeStages := preload("res://scripts/sim/life_stages.gd")

const SLOTS := 3
## Unpromised wishes are replaced after this many in-game minutes.
const STALE := 20 * 60.0
## Nicer wish texts for common actions (else "<Action> · <Object>").
const DO_LABELS := {
	"paint": "Paint a Picture", "practice": "Practise the Piano", "play_song": "Play a Song", "tips": "Play for Tips",
	"homework": "Do Homework", "read": "Read a Book", "play_toys": "Play with Toys", "play": "Play with Toys",
	"cook": "Cook a Meal", "cook_fridge": "Cook a Meal", "snack": "Grab a Snack", "eat": "Eat at the Table",
	"meal": "Eat a Family Meal", "sleep": "Get a Good Night's Sleep", "nap": "Take a Nap", "shower": "Take a Shower",
	"bath": "Take a Bath", "watch_show": "Watch TV", "games": "Play Video Games", "emails": "Answer Emails",
	"work": "Put in a Work Shift", "bills": "Pay the Bills", "feed_dog": "Feed Biscuit", "chase_ball": "Chase the Ball",
	"eat_bowl": "Eat Dinner", "dog_beg": "Beg for Treats", "masterpiece": "Paint a Masterpiece", "freelance": "Freelance Coding",
	"write_blog": "Write a Blog Post", "gourmet": "Cook a Gourmet Meal", "buy_groceries": "Buy Groceries",
	"pay": "Pay at the Checkout", "s_fetch": "Play Fetch", "s_play": "Play with the Kids", "relax": "Relax on the Sofa",
}
const TIER_GOAL := {1: "Friends", 2: "Good Friends", 3: "Best Friends"}
## Menu-only rows that never make a "do" wish.
const NO_WISH := ["find_job", "quit_job", "apply_job", "bills", "check_mail", "go_to_work"]
const Careers := preload("res://scripts/sim/careers.gd")
## Same as SimWorld.MEAL_TABLES / MEAL_COOKS.
const MEAL_TABLES := ["Dining Table", "Dinner Table"]
const MEAL_COOKS := ["Fridge", "Stove", "Grill"]


## Top up every member's wishes (drop stale unpromised ones first).
static func roll(world, ag) -> void:
	var list: Array = Game.wishes(ag.index)
	var now := Game.total_minutes()
	for k in range(list.size() - 1, -1, -1):
		var w: Dictionary = list[k]
		if not w.get("promised", false) and now - float(w.get("born", now)) > STALE:
			list.remove_at(k)
		elif w.kind == "do" and not _lot_has_action(world, ag, str(w.arg)) and not w.get("promised", false):
			list.remove_at(k)   # can't be done on this lot: make room
	var tries := 0
	while list.size() < SLOTS and tries < 12:
		tries += 1
		var w := _candidate(world, ag, list)
		if w.is_empty():
			continue
		w["born"] = now
		w["promised"] = false
		Game.add_wish(ag.index, w)
	Game.wishes_changed.emit(ag.index)


static func _candidate(world, ag, have: Array) -> Dictionary:
	var ids := {}
	for w in have:
		ids[w.id] = true
	var opts: Array = []   # [weight, wish]
	var m: Dictionary = ag.member
	var human: bool = ag.kind != "dog"
	# --- skills the lot can teach
	if human:
		var taught := {}
		for it in world.interactables:
			if is_instance_valid(it) and world.townie_of(it) == "":
				for a in world.actions_for(it, m):
					if a.has("skill") and not a.get("locked", false):
						taught[a.skill] = true
		for sk in taught:
			var lv := int(floorf(float(m.skills.get(sk, 0.0)))) + 1
			if lv > 10:
				continue
			opts.append([3.0, {"id": "skill_%s_%d" % [sk, lv], "label": "Reach %s Level %d" % [sk, lv], "icon": Game.SKILL_ICONS.get(sk, "star"),
				"kind": "skill", "arg": sk, "n": lv, "reward": 300 + lv * 75}])
	# --- something to do here
	var seen := {}
	for it in world.interactables:
		if not is_instance_valid(it) or world.townie_of(it) != "":
			continue
		for a in world.actions_for(it, m):
			var id: String = a.get("id", "")
			if id == "" or id in NO_WISH or seen.has(id) or a.get("locked", false) or int(a.get("money", 0)) < 0 or id.begins_with("locked_"):
				continue
			seen[id] = true
			var lab: String = DO_LABELS.get(id, "%s · %s" % [a.get("label", id), it.title])
			if id == "meal":
				lab = DO_LABELS.meal
			var wt := 2.0 if DO_LABELS.has(id) else 0.8
			opts.append([wt, {"id": "do_" + id, "label": lab, "icon": a.get("icon", "star"), "kind": "do", "arg": id, "n": 1,
				"reward": 150 + int(clampf(float(a.get("minutes", 30.0)), 5.0, 120.0)) * 2}])
	if human and world.meal.is_empty() and _lot_has_table(world):
		opts.append([1.5, {"id": "do_meal", "label": DO_LABELS.meal, "icon": "plate", "kind": "do", "arg": "meal", "n": 1, "reward": 250}])
	# --- friendship
	var me: String = ag.display_name()
	for other in world.agents:
		if other == null or other == ag:
			continue
		var t := Game.rel_tier(Game.rel(me, other.display_name()))
		if t < 3 and t >= 0:
			var goal: String = TIER_GOAL[t + 1]
			opts.append([1.5, {"id": "rel_%s_%d" % [other.display_name(), t + 1], "label": "Become %s with %s" % [goal, other.display_name()],
				"icon": "heart", "kind": "rel", "arg": other.display_name(), "n": t + 1, "reward": 400 + t * 150}])
	if human:
		var strangers := 0
		for it in world.interactables:
			if not is_instance_valid(it):
				continue
			var tn: String = world.townie_of(it)
			if tn != "" and not Game.has_met(me, tn):
				strangers += 1
		if strangers > 0:
			opts.append([2.0, {"id": "meet_new", "label": "Meet Someone New", "icon": "people", "kind": "meet", "arg": "", "n": 1, "reward": 300}])
	# --- career / school
	var c: Dictionary = m.get("career", {})
	if ag.kind == "adult" and c.is_empty():
		opts.append([3.0, {"id": "find_job", "label": "Find a Job", "icon": "laptop", "kind": "job", "arg": "", "n": 1, "reward": 500}])
	elif ag.kind == "adult" and Careers.next_req(c) >= 0:
		opts.append([2.0, {"id": "promo_%d" % (int(c.level) + 1), "label": "Get Promoted to %s" % Careers.TRACKS[c.track].titles[mini(int(c.level), 9)],
			"icon": "trophy", "kind": "promo", "arg": "", "n": int(c.level) + 1, "reward": 600 + int(c.level) * 100}])
	elif ag.kind == "child" and Careers.is_school(c) and not Careers.grade(float(c.get("perf", 50.0))) in ["A", "A+"]:
		opts.append([1.5, {"id": "grade_a", "label": "Get an A at School", "icon": "book", "kind": "grade", "arg": "", "n": 1, "reward": 500}])
	# --- love and family (Sims 3 romance / family wishes)
	if ag.kind == "adult":
		var partner := Game.partner_of(me)
		if partner == "":
			for r in Game.rel_list(ag.index):
				if float(r.get("romance", 0.0)) >= Game.ROMANCE_CRUSH and str(r.get("status", "")) == "":
					opts.append([2.5, {"id": "do_s_steady", "label": "Go Steady with %s" % r.name, "icon": "heart", "kind": "do", "arg": "s_steady", "n": 1, "reward": 700}])
					break
		else:
			var st := Game.rel_status(me, partner)
			if st == "Dating":
				opts.append([2.5, {"id": "do_s_propose", "label": "Propose to %s" % partner, "icon": "heart", "kind": "do", "arg": "s_propose", "n": 1, "reward": 900}])
			elif st == "Engaged":
				opts.append([2.0, {"id": "do_s_wed", "label": "Marry %s" % partner, "icon": "heart", "kind": "do", "arg": "s_wed", "n": 1, "reward": 1000}])
			if not Game.is_family(partner):
				opts.append([2.0, {"id": "do_s_move_in", "label": "Move In with %s" % partner, "icon": "home", "kind": "do", "arg": "s_move_in", "n": 1, "reward": 800}])
			elif Game.baby_carrier(me, partner) != "" and st in ["Engaged", "Married"]:
				opts.append([1.8, {"id": "do_s_try_baby", "label": "Have a Baby", "icon": "teddy", "kind": "do", "arg": "s_try_baby", "n": 1, "reward": 1200}])
	if human and Game.days_to_birthday(ag.index) <= 1 and LifeStages.next_stage(str(m.get("life_stage", "")), ag.kind) != "":
		opts.append([2.5, {"id": "do_blow_candles", "label": "Have a Birthday Party", "icon": "cake", "kind": "do", "arg": "blow_candles", "n": 1, "reward": 600}])
	# --- money (grown-ups)
	if ag.kind == "adult":
		var amt: int = [150, 250, 400][randi() % 3]
		opts.append([1.2, {"id": "earn_%d" % amt, "label": "Earn $%d" % amt, "icon": "money", "kind": "earn", "arg": "", "n": amt, "have": 0, "reward": 200 + amt}])
	# weighted pick among the ones not already wished for
	var pool: Array = opts.filter(func(o): return not ids.has(o[1].id))
	if pool.is_empty():
		return {}
	var total := 0.0
	for o in pool:
		total += o[0]
	var r := randf() * total
	for o in pool:
		r -= o[0]
		if r <= 0.0:
			return o[1]
	return pool[-1][1]


static func _lot_has_table(world) -> bool:
	for it in world.interactables:
		if is_instance_valid(it) and str(it.title) in MEAL_TABLES:
			for it2 in world.interactables:
				if is_instance_valid(it2) and str(it2.title) in MEAL_COOKS:
					return true
	return false


static func _lot_has_action(world, ag, id: String) -> bool:
	if id == "meal":
		return _lot_has_table(world)
	for it in world.interactables:
		if not is_instance_valid(it):
			continue
		for a in world.actions_for(it, ag.member):
			if a.get("id", "") == id:
				return true
	return false


# =================================================================== fulfilment

## An action finished (pay = money it earned).
static func on_action(ag, a: Dictionary, pay: int) -> void:
	var list: Array = Game.wishes(ag.index).duplicate()
	var id: String = a.get("id", "")
	for w in list:
		match w.kind:
			"do":
				if w.arg == id:
					_fulfil(ag, w)
			"meet":
				if id == "s_introduce":
					_fulfil(ag, w)
			"earn":
				if pay > 0:
					w.have = int(w.get("have", 0)) + pay
					if int(w.have) >= int(w.n):
						_fulfil(ag, w)
					else:
						Game.wishes_changed.emit(ag.index)


static func on_skill(ag, skill: String, level: int) -> void:
	for w in Game.wishes(ag.index).duplicate():
		if w.kind == "skill" and w.arg == skill and level >= int(w.n):
			_fulfil(ag, w)


static func on_rel(ag, other_name: String) -> void:
	var t := Game.rel_tier(Game.rel(ag.display_name(), other_name))
	for w in Game.wishes(ag.index).duplicate():
		if w.kind == "rel" and w.arg == other_name and t >= int(w.n):
			_fulfil(ag, w)


static func _fulfil(ag, w: Dictionary) -> void:
	var pts := Game.fulfil_wish(ag.index, w.id)
	if pts > 0 and ag.actor and is_instance_valid(ag.actor):
		Game.show_bubble(ag.actor, {"kind": "skill", "text": "Wish  +%d" % pts, "icon": "star", "id": "skill", "ttl": 3.5})
		if OS.has_environment("VIMS_PLAYTEST"):
			print("  wish: %s -> %s +%d (LTH %d)" % [ag.display_name(), w.label, pts, Game.lth(ag.index)])


## Free-will nudge toward wished-for actions (promised ones more).
static func bias(ag, a: Dictionary) -> float:
	var b := 0.0
	for w in Game.wishes(ag.index):
		var k: float = 2.0 if w.get("promised", false) else 1.0
		match w.kind:
			"do":
				if w.arg == a.get("id", ""):
					b += 0.06 * k
			"skill":
				if a.get("skill", "") == w.arg:
					b += 0.04 * k
			"earn":
				if int(a.get("money", 0)) > 0:
					b += 0.03 * k
	return b


## Career events: "job" (hired), "promo" (promoted), "grade" (A at school).
static func on_career(ag, event: String) -> void:
	for w in Game.wishes(ag.index).duplicate():
		if w.kind == event:
			_fulfil(ag, w)
