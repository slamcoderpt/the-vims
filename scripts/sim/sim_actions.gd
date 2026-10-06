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
	"Grill": [
		{"id": "dog_beg_grill", "label": "Beg for Scraps", "icon": "bone", "minutes": 8.0, "pose": "sit",
		 "needs": {"hunger": 0.3}, "who": ["dog"]},
	],
}

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
	for a in src:
		if a is Dictionary and allowed(a, kind):
			out.append(a)
	for a in EXTRAS.get(str(it.get("title")), []):
		if allowed(a, kind):
			out.append(a)
	return out


## Tiered socials (Sims 3 style): what you can do with someone depends on
## how well you know them. tier = Game.rel_tier(friendship): -2 Enemy,
## -1 Disliked, 0 Acquaintance, 1 Friend, 2 Good Friend, 3 Best Friend.
##   min / max: tier range it shows in; stranger: only before you've met;
##   rel: friendship change on success; needs: actor; social: target's needs;
##   kinds: actor kinds allowed; tkinds: target kinds; mean: lowers friendship.
const SOCIALS := [
	{"id": "s_introduce", "label": "Introduce Yourself", "icon": "wave", "minutes": 6.0, "pose": "wave",
	 "stranger": true, "rel": 14.0, "needs": {"social": 0.15}, "social": {"social": 0.1}, "kinds": ["adult", "child"], "tkinds": ["adult", "child"]},
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
static func socials_by_rel(actor_kind: String, target_kind: String, target_name: String, met: bool, value: float, with_locked := false) -> Array:
	var out: Array = []
	var tier := Game.rel_tier(value)
	var locked: Dictionary = {}
	for d: Dictionary in SOCIALS:
		if not actor_kind in d.kinds or not target_kind in d.tkinds:
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
	if with_locked and not locked.is_empty():
		var tn: String = TIER_NAMES.get(int(locked.get("min", 0)), "closer")
		out.append({"id": "locked_" + str(locked.id), "label": "%s (%s)" % [locked.label, tn], "icon": "dots",
			"locked": true, "need_tier": tn, "unlock_label": locked.label})
	return out


## Household social menu / autonomy list between two agents.
static func socials_for(ag, other, with_locked := false) -> Array:
	var a_name: String = ag.display_name()
	var b_name: String = other.display_name()
	return socials_by_rel(ag.kind, other.kind, b_name, Game.has_met(a_name, b_name), Game.rel(a_name, b_name), with_locked)


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
