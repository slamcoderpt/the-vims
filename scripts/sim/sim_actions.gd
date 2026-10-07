extends RefCounted
## Action rules shared by the player menu and autonomy: who may do what, extra
## actions the sim layer adds to existing objects (dog eats from the bowl, ...),
## household socials and how autonomy scores an action.

## Extra actions keyed by Interactable title (added after the location's own).
const EXTRAS := {
	"Dog Bowl": [
		{"id": "eat_bowl", "label": "Eat", "icon": "bone", "minutes": 10.0, "pose": "idle",
		 "needs": {"hunger": 0.7}, "who": ["dog"]},
	],
	"Dog Bed": [],
	"Fridge": [
		{"id": "bake_cake", "label": "Bake Birthday Cake", "icon": "cake", "minutes": 30.0, "pose": "idle", "anim": "cook",
		 "money": -25, "needs": {"fun": 0.05}, "skill": "Cooking", "who": ["adult"]},
		{"id": "dog_beg", "label": "Beg for Treats", "icon": "bone", "minutes": 5.0, "pose": "sit",
		 "needs": {"hunger": 0.15, "fun": 0.05}, "who": ["dog"]},
	],
	"Ball": [
		{"id": "chase_ball", "label": "Chase Ball", "icon": "ball", "minutes": 20.0, "pose": "play",
		 "needs": {"fun": 0.35}, "who": ["dog"]},
	],
	"Shopping Cart": [
		{"id": "buy_groceries", "label": "Buy Groceries", "icon": "cart", "minutes": 20.0, "pose": "stand_type",
		 "money": -38, "needs": {"fun": 0.05}, "task": "Buy Groceries", "who": ["adult", "child"]},
	],
	"Cashier": [
		{"id": "pay", "label": "Pay at Checkout", "icon": "register", "minutes": 8.0, "pose": "talk",
		 "money": -52, "needs": {"social": 0.05}, "task": "Pay at Checkout", "who": ["adult"]},
	],
	"Fountain": [
		{"id": "drink_fountain", "label": "Sniff Around", "icon": "paw", "minutes": 10.0, "pose": "idle",
		 "needs": {"fun": 0.2}, "who": ["dog"]},
	],
	"Fire Pit": [
		{"id": "dog_nap_pit", "label": "Nap by the Fire", "icon": "zzz", "minutes": 30.0, "pose": "sleep",
		 "needs": {"fun": 0.05}, "who": ["dog"]},
	],
	"Stove": [
		{"id": "bake_cake", "label": "Bake Birthday Cake", "icon": "cake", "minutes": 30.0, "pose": "idle", "anim": "cook",
		 "money": -25, "needs": {"fun": 0.05}, "skill": "Cooking", "who": ["adult"]},
	],
	"Grill": [
		{"id": "dog_beg_grill", "label": "Beg for Scraps", "icon": "bone", "minutes": 8.0, "pose": "sit",
		 "needs": {"hunger": 0.3}, "who": ["dog"]},
	],
}

## Actions a skill level unlocks on an object (Sims 3: skills open new
## interactions that earn money or fix needs better). req: [skill, level];
## money_per_level adds pay per whole skill level; moodlet: on completion
## [id, label, icon, delta, hours]. An empty pose copies the object's first one.
const SKILL_UNLOCKS := {
	"Piano": [{"id": "tips", "label": "Play for Tips", "icon": "money", "minutes": 30.0, "pose": "",
		"needs": {"fun": 0.1, "social": 0.05}, "skill": "Music", "req": ["Music", 3], "money": 15, "money_per_level": 8, "who": ["adult", "child"]}],
	"Guitar": [{"id": "busk", "label": "Busk for Tips", "icon": "money", "minutes": 30.0, "pose": "",
		"needs": {"fun": 0.1}, "skill": "Music", "req": ["Music", 3], "money": 12, "money_per_level": 7, "who": ["adult", "child"]}],
	"Easel": [{"id": "masterpiece", "label": "Paint Masterpiece", "icon": "palette", "minutes": 90.0, "pose": "",
		"needs": {"fun": 0.25}, "skill": "Creativity", "req": ["Creativity", 3], "money": 40, "money_per_level": 25,
		"moodlet": ["inspired", "Inspired", "bulb", 10.0, 4.0]}],
	"Computer": [{"id": "freelance", "label": "Freelance Coding", "icon": "laptop", "minutes": 60.0, "pose": "",
		"needs": {"fun": -0.05}, "skill": "Logic", "req": ["Logic", 4], "money": 50, "money_per_level": 20, "who": ["adult"]},
		{"id": "write_blog", "label": "Write Blog Post", "icon": "pencil", "minutes": 45.0, "pose": "",
		"needs": {"fun": 0.05}, "skill": "Writing", "req": ["Writing", 1], "money": 20, "money_per_level": 15, "who": ["adult"]}],
	"Stove": [{"id": "gourmet", "label": "Cook Gourmet Meal", "icon": "cook", "minutes": 60.0, "pose": "",
		"needs": {"hunger": 1.0}, "skill": "Cooking", "req": ["Cooking", 3], "who": ["adult"],
		"moodlet": ["gourmet", "Gourmet Meal", "cook", 16.0, 5.0]}],
	"Grill": [{"id": "gourmet_grill", "label": "Grill Gourmet Burgers", "icon": "burger", "minutes": 50.0, "pose": "",
		"needs": {"hunger": 0.9, "fun": 0.1}, "skill": "Cooking", "req": ["Cooking", 3], "who": ["adult"],
		"moodlet": ["gourmet", "Gourmet Meal", "cook", 16.0, 5.0]}],
}

## Location actions the sim layer replaces (by Interactable title): the old
## on-demand "Work" shift and flat "Pay Bills" gave way to careers
## (careers.gd) and real bills (Game.bills, SimWorld.career_rows).
const REPLACED := {"Computer": ["work", "bills"]}

## Side effects on OTHER household members when an action completes.
## action id -> {kind: need delta}
const EFFECT_ON_KIND := {
	"feed_dog": {"dog": {"hunger": 0.6}},
	"pet": {"dog": {"fun": 0.2}},
	"fetch": {"dog": {"fun": 0.3}},
}

## Poses the dog can show; others fall back to these.
const DOG_POSES := ["idle", "walk", "sit", "lie", "sleep", "play", "talk"]


static func allowed(a: Dictionary, kind: String) -> bool:
	if kind == "baby":
		return a.get("who", []) is Array and "baby" in a.get("who", [])
	var who = a.get("who", null)
	if who is Array and not (who as Array).is_empty():
		return kind in who
	# Unrestricted actions: dogs only get ones whose pose a dog can do and that
	# aren't obviously human (money, skills, typing...).
	if kind == "dog":
		var pose: String = a.get("pose", "idle")
		if a.has("skill") or int(a.get("money", 0)) != 0:
			return false
		return pose in ["sleep", "lie", "sit", "play", "idle"] and a.get("id", "") in ["nap", "nap_sofa", "relax", "warm", "watch_show", "fetch", "play_toys"]
	return true


## Actions on an Interactable that member (Game.household dict) may do.
static func actions_for(it: Node, member: Dictionary) -> Array:
	var out: Array = []
	var kind: String = member.get("kind", "adult")
	var src: Array = it.get("actions") if it.get("actions") is Array else []
	var gone: Array = REPLACED.get(str(it.get("title")), [])
	for a in src:
		if a is Dictionary and allowed(a, kind) and not str(a.get("id", "")) in gone:
			out.append(a)
	for a in EXTRAS.get(str(it.get("title")), []):
		if allowed(a, kind):
			out.append(a)
	var skills: Dictionary = member.get("skills", {})
	for u in SKILL_UNLOCKS.get(str(it.get("title")), []):
		if not allowed(u, kind):
			continue
		var a: Dictionary = u.duplicate(true)
		if a.pose == "":
			a.pose = src[0].get("pose", "idle") if not src.is_empty() and src[0] is Dictionary else "idle"
		var need_lv: int = int(a.req[1])
		if floorf(float(skills.get(a.req[0], 0.0))) >= need_lv:
			out.append(a)
		elif float(skills.get(a.req[0], 0.0)) >= need_lv - 2:
			# Close to it: a teaser row the player can't pick yet.
			out.append({"id": "locked_" + str(a.id), "label": "%s (%s %d)" % [a.label, a.req[0], need_lv], "icon": "dots",
				"locked": true, "lock_msg": "Reach %s level %d to unlock %s" % [a.req[0], need_lv, a.label]})
	return out


## Tiered socials (Sims 3 style): what you can do with someone depends on
## how well you know them. tier = Game.rel_tier(friendship): -2 Enemy,
## -1 Disliked, 0 Acquaintance, 1 Friend, 2 Good Friend, 3 Best Friend.
##   min / max: tier range it shows in; stranger: only before you've met;
##   rel: friendship change on success; needs: actor; social: target's needs;
##   kinds: actor kinds allowed; tkinds: target kinds; mean: lowers friendship.
const SOCIALS := [
	{"id": "s_introduce", "label": "Introduce Yourself", "icon": "wave", "minutes": 6.0, "pose": "wave",
	 "stranger": true, "rel": 10.0, "needs": {"social": 0.15}, "social": {"social": 0.1}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_chat", "label": "Chat", "icon": "chat", "minutes": 15.0, "pose": "talk", "min": -2,
	 "rel": 6.0, "needs": {"social": 0.3, "fun": 0.05}, "social": {"social": 0.25}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_joke", "label": "Tell a Joke", "icon": "laugh", "minutes": 6.0, "pose": "talk", "min": -1,
	 "rel": 7.0, "needs": {"social": 0.12, "fun": 0.15}, "social": {"fun": 0.15, "social": 0.1}, "skill": "Charisma", "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_day", "label": "Ask About Their Day", "icon": "chat", "minutes": 10.0, "pose": "talk", "min": 0,
	 "rel": 5.0, "needs": {"social": 0.22}, "social": {"social": 0.2}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_compliment", "label": "Compliment", "icon": "star", "minutes": 5.0, "pose": "talk", "min": 1,
	 "rel": 9.0, "needs": {"social": 0.15}, "social": {"social": 0.15, "fun": 0.05}, "skill": "Charisma", "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_hobbies", "label": "Talk About Hobbies", "icon": "bulb", "minutes": 20.0, "pose": "talk", "min": 1,
	 "rel": 11.0, "needs": {"social": 0.3, "fun": 0.12}, "social": {"social": 0.25, "fun": 0.1}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_highfive", "label": "High Five", "icon": "wave", "minutes": 2.0, "pose": "wave", "min": 1,
	 "rel": 5.0, "needs": {"fun": 0.1, "social": 0.08}, "social": {"fun": 0.1}, "kinds": ["child"], "tkinds": ["adult", "child"]},
	{"id": "s_hug", "label": "Hug", "icon": "heart", "minutes": 4.0, "pose": "talk", "min": 2,
	 "rel": 8.0, "needs": {"social": 0.2}, "social": {"social": 0.2}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_deep", "label": "Deep Conversation", "icon": "chat", "minutes": 30.0, "pose": "talk", "min": 2,
	 "rel": 14.0, "needs": {"social": 0.45}, "social": {"social": 0.4}, "skill": "Charisma", "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_handshake", "label": "Secret Handshake", "icon": "star", "minutes": 3.0, "pose": "wave", "min": 3,
	 "rel": 4.0, "needs": {"fun": 0.2, "social": 0.15}, "social": {"fun": 0.2, "social": 0.15}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	# --- romance (adults with non-family adults; rom_min: romance needed)
	{"id": "s_flirt", "label": "Flirt", "icon": "heart", "minutes": 8.0, "pose": "talk", "min": 0, "romantic": true, "rom_min": 0.0,
	 "rel": 3.0, "rom": 16.0, "needs": {"social": 0.15, "fun": 0.08}, "social": {"social": 0.1}, "skill": "Charisma", "kinds": ["adult"], "tkinds": ["adult"]},
	{"id": "s_kiss", "label": "Kiss", "icon": "heart", "minutes": 5.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 35.0,
	 "rel": 5.0, "rom": 14.0, "needs": {"social": 0.2, "fun": 0.15}, "social": {"social": 0.2, "fun": 0.1}, "kinds": ["adult"], "tkinds": ["adult"]},
	{"id": "s_steady", "label": "Ask to Go Steady", "icon": "heart", "minutes": 6.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 60.0,
	 "req_status": [""], "anim": "hug",
	 "rel": 8.0, "rom": 10.0, "status": "Dating", "needs": {"social": 0.2}, "social": {"social": 0.2}, "kinds": ["adult"], "tkinds": ["adult"]},
	# Sims 3 romance ladder past going steady: propose (accepted when the
	# romance meter is high: accept_rom), a private wedding, moving in
	# (townies only), trying for a baby (household partners only).
	{"id": "s_propose", "label": "Propose Engagement", "icon": "heart", "minutes": 8.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 75.0,
	 "req_status": ["Dating"], "accept_rom": 80.0, "anim": "propose",
	 "rel": 10.0, "rom": 8.0, "status": "Engaged", "needs": {"social": 0.25, "fun": 0.1}, "social": {"social": 0.2}, "kinds": ["adult"], "tkinds": ["adult"],
	 "moodlet": ["engaged", "Just Engaged!", "heart", 30.0, 24.0]},
	{"id": "s_wed", "label": "Have Private Wedding", "icon": "heart", "minutes": 20.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 80.0,
	 "req_status": ["Engaged"], "anim": "kiss",
	 "rel": 10.0, "rom": 8.0, "status": "Married", "needs": {"social": 0.3, "fun": 0.2}, "social": {"social": 0.3, "fun": 0.2}, "kinds": ["adult"], "tkinds": ["adult"],
	 "moodlet": ["newlywed", "Newlywed", "heart", 35.0, 48.0]},
	{"id": "s_move_in", "label": "Ask to Move In", "icon": "home", "minutes": 8.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 50.0,
	 "req_status": ["Dating", "Engaged", "Married"], "townie_only": true, "anim": "hug",
	 "rel": 6.0, "rom": 4.0, "needs": {"social": 0.2}, "social": {"social": 0.2}, "kinds": ["adult"], "tkinds": ["adult"]},
	{"id": "s_try_baby", "label": "Try for Baby", "icon": "heart", "minutes": 30.0, "pose": "talk", "min": 1, "romantic": true, "rom_min": 60.0,
	 "req_status": ["Dating", "Engaged", "Married"], "household_only": true, "baby": true, "anim": "kiss",
	 "rel": 6.0, "rom": 10.0, "needs": {"social": 0.35, "fun": 0.35, "energy": -0.1}, "social": {"social": 0.35, "fun": 0.35}, "kinds": ["adult"], "tkinds": ["adult"]},
	{"id": "s_makeup", "label": "Apologize", "icon": "heart", "minutes": 8.0, "pose": "talk", "max": -1,
	 "rel": 16.0, "needs": {"social": 0.1}, "social": {"social": 0.05}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	{"id": "s_tease", "label": "Tease", "icon": "laugh", "minutes": 4.0, "pose": "talk", "min": -2, "mean": true,
	 "rel": -12.0, "needs": {"fun": 0.12}, "social": {"social": -0.05, "fun": -0.1}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
	# --- pets
	{"id": "s_pet", "label": "Pet %s", "icon": "paw", "minutes": 8.0, "pose": "talk", "min": -2,
	 "rel": 6.0, "needs": {"social": 0.1, "fun": 0.1}, "social": {"fun": 0.25}, "task": "Play with Dog", "kinds": ["adult", "child"], "tkinds": ["dog"]},
	{"id": "s_fetch", "label": "Play Fetch", "icon": "ball", "minutes": 20.0, "pose": "wave", "min": 0,
	 "rel": 9.0, "needs": {"fun": 0.25}, "social": {"fun": 0.4}, "task": "Play with Dog", "kinds": ["adult", "child"], "tkinds": ["dog"]},
	{"id": "s_trick", "label": "Teach a Trick", "icon": "star", "minutes": 25.0, "pose": "wave", "min": 1,
	 "rel": 8.0, "needs": {"fun": 0.15}, "social": {"fun": 0.2}, "task": "Play with Dog", "kinds": ["adult", "child"], "tkinds": ["dog"], "pet_skill": "Fetch"},
	{"id": "s_play", "label": "Play with %s", "icon": "paw", "minutes": 15.0, "pose": "play", "min": -2,
	 "rel": 7.0, "needs": {"fun": 0.3}, "social": {"fun": 0.2, "social": 0.15}, "kinds": ["dog"], "tkinds": ["adult", "child", "dog"]},
	{"id": "s_greet", "label": "Greet %s", "icon": "heart", "minutes": 5.0, "pose": "talk", "min": -2,
	 "rel": 4.0, "needs": {"fun": 0.1}, "social": {"social": 0.1}, "kinds": ["dog"], "tkinds": ["adult", "child", "dog"]},
]
const TIER_NAMES := {-2: "Enemies", -1: "Disliked", 0: "Acquaintances", 1: "Friends", 2: "Good Friends", 3: "Best Friends"}


## Socials actor (kind) can do with target right now, given their friendship.
## with_locked adds a teaser row for the next tier ("locked": true).
## rom: {} for family (no romance), else {"romance": 0..100, "status": ""}.
static func socials_by_rel(actor_kind: String, target_kind: String, target_name: String, met: bool, value: float, with_locked := false, rom = null) -> Array:
	var out: Array = []
	var tier := Game.rel_tier(value)
	var locked: Dictionary = {}
	var rom_locked: Dictionary = {}
	for d: Dictionary in SOCIALS:
		if not actor_kind in d.kinds or not target_kind in d.tkinds:
			continue
		if d.get("romantic", false):
			if not (rom is Dictionary) or not met or tier < int(d.get("min", 0)):
				continue
			if d.has("status") and str(rom.get("status", "")) == str(d.status):
				continue
			if d.has("req_status") and not str(rom.get("status", "")) in d.req_status:
				continue
			if d.get("townie_only", false) and rom.get("family", false):
				continue
			if d.get("household_only", false) and not rom.get("family", false):
				continue
			if d.get("baby", false) and not rom.get("can_baby", false):
				continue
			if float(rom.get("romance", 0.0)) < float(d.get("rom_min", 0.0)):
				if with_locked and rom_locked.is_empty():
					rom_locked = {"id": "locked_" + str(d.id), "label": "%s (Romance %d)" % [d.label, int(d.rom_min)], "icon": "dots",
						"locked": true, "need_tier": "more romance", "unlock_label": d.label,
						"lock_msg": "Flirt with %s to build romance and unlock %s" % [target_name, d.label]}
				continue
			out.append(d.duplicate(true))
			continue
		var a := d.duplicate(true)
		a.label = (a.label as String) % target_name if "%s" in a.label else a.label
		if d.get("stranger", false):
			if not met:
				out.append(a)
			continue
		if not met and target_kind != "dog" and actor_kind != "dog":
			# Strangers: only an introduction (and a wave) until you've met.
			continue
		var mn: int = d.get("min", -2)
		var mx: int = d.get("max", 3)
		if tier > mx:
			continue
		if tier < mn:
			if with_locked and (locked.is_empty() or mn < int(locked.get("min", 9))):
				locked = a
			continue
		out.append(a)
	if actor_kind == "adult" and target_kind == "child" and met:
		out.append({"id": "s_homework", "label": "Help with Homework", "icon": "book", "minutes": 30.0, "pose": "talk",
			"needs": {"social": 0.15}, "social": {"social": 0.1}, "skill": "Logic", "task": "Do Homework", "rel": 6.0})
	if not met and actor_kind != "dog" and target_kind != "dog":
		out.append({"id": "s_wave", "label": "Wave", "icon": "wave", "minutes": 2.0, "pose": "wave",
			"needs": {"social": 0.05}, "rel": 2.0})
	if not rom_locked.is_empty():
		out.append(rom_locked)
	if with_locked and not locked.is_empty():
		var tn: String = TIER_NAMES.get(int(locked.get("min", 0)), "closer")
		out.append({"id": "locked_" + str(locked.id), "label": "%s (%s)" % [locked.label, tn], "icon": "dots",
			"locked": true, "need_tier": tn, "unlock_label": locked.label})
	return out


## Household social menu / autonomy list between two agents.
static func socials_for(ag, other, with_locked := false) -> Array:
	var a_name: String = ag.display_name()
	var b_name: String = other.display_name()
	var rom = null
	if Game.can_romance(a_name, b_name):
		rom = rom_info(a_name, b_name, true)
	var out := socials_by_rel(ag.kind, other.kind, b_name, Game.has_met(a_name, b_name), Game.rel(a_name, b_name), with_locked, rom)
	if other.kind == "baby" and ag.kind != "dog":
		out.append_array(BABY_SOCIALS.filter(func(d): return ag.kind in d.kinds).map(func(d): return _named(d, b_name)))
	return out


## Romance context for socials_by_rel (null when these two can't romance).
static func rom_info(a_name: String, b_name: String, family: bool) -> Dictionary:
	return {"romance": Game.romance(a_name, b_name), "status": Game.rel_status(a_name, b_name), "family": family,
		"can_baby": family and Game.baby_carrier(a_name, b_name) != ""}


static func _named(d: Dictionary, n: String) -> Dictionary:
	var a := d.duplicate(true)
	if "%s" in str(a.label):
		a.label = str(a.label) % n
	return a


## Socials with a baby (in the crib): the crib's own actions do the care.
const BABY_SOCIALS := [
	{"id": "b_coo", "label": "Coo at %s", "icon": "heart", "minutes": 6.0, "pose": "talk", "anim": "rock_baby",
	 "rel": 6.0, "needs": {"fun": 0.08, "social": 0.08}, "social": {"social": 0.3, "fun": 0.2}, "kinds": ["adult", "child"]},
]


## Legacy helper (pre-relationship): socials as between acquaintances.
static func socials(actor_kind: String, target_kind: String, target_name: String) -> Array:
	return socials_by_rel(actor_kind, target_kind, target_name, true, 20.0)


## Free will prefers people it likes (and avoids enemies).
static func social_bias(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= Game.household.size() or j >= Game.household.size():
		return 0.0
	return Game.rel(Game.household[i].name, Game.household[j].name) / 100.0 * 0.06


## Autonomy score of an action for a member (higher = more wanted).
## Uses (1 - need)^2 urgency so the lowest need dominates.
static func score(a: Dictionary, member: Dictionary, dist: float) -> float:
	var needs: Dictionary = member.get("needs", {})
	var s := 0.0
	var eff: Dictionary = a.get("needs", {})
	for k in eff:
		if not needs.has(k):
			continue
		var gain: float = eff[k]
		var v: float = needs[k]
		var urg := pow(1.0 - v, 2.0) * 2.0 + 0.05
		if gain > 0.0:
			s += minf(gain, 1.0 - v + 0.1) * urg
		else:
			s += gain * 0.5
	# Long actions only when they're really needed.
	var mins: float = a.get("minutes", 30.0)
	if mins > 120.0:
		s -= 0.15
	if int(a.get("money", 0)) < 0:
		s -= 0.3
	if a.has("skill"):
		s += 0.04
	if a.has("task") and Game.has_open_task(a.task):
		s += 0.06
	if a.has("baby_fx"):
		# Caring for the baby: as urgent as the baby's lowest matching need.
		s += baby_urgency(a.baby_fx) * 1.6
		if a.has("money"):
			s += 0.3
	s -= dist * 0.012
	return s


## Thought icon for a need.
static func need_icon(need: String, kind := "adult") -> String:
	match need:
		"hunger": return "bone" if kind == "dog" else "need_hunger"
		"energy": return "need_energy"
		"fun": return "need_fun"
		"hygiene": return "need_hygiene"
		"social": return "need_social"
		"bladder": return "need_bladder"
	return "star"


## How badly the household's babies need what `fx` ({need: gain}) gives.
static func baby_urgency(fx: Dictionary) -> float:
	var best := 0.0
	for m in Game.household:
		if m.get("kind", "") != "baby":
			continue
		for k in fx:
			var v: float = float(m.needs.get(k, 1.0))
			best = maxf(best, pow(1.0 - v, 2.0) * minf(1.0, float(fx[k])))
	return best


## Apply a crib action's effect to every baby in the household.
static func apply_baby_fx(fx: Dictionary) -> void:
	for i in Game.household.size():
		if Game.household[i].get("kind", "") != "baby":
			continue
		for k in fx:
			Game.change_need(i, k, float(fx[k]))
		Game.needs_changed.emit(i)
