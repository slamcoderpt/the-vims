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


## Social actions the selected member can do with another household member.
static func socials(actor_kind: String, target_kind: String, target_name: String) -> Array:
	var out: Array = []
	if actor_kind == "dog":
		out.append({"id": "s_play", "label": "Play with %s" % target_name, "icon": "paw", "minutes": 15.0, "pose": "play",
			"needs": {"fun": 0.3}, "social": {"fun": 0.2, "social": 0.15}})
		out.append({"id": "s_greet", "label": "Greet %s" % target_name, "icon": "heart", "minutes": 5.0, "pose": "talk",
			"needs": {"fun": 0.1}, "social": {"social": 0.1}})
		return out
	if target_kind == "dog":
		out.append({"id": "s_pet", "label": "Pet %s" % target_name, "icon": "paw", "minutes": 8.0, "pose": "talk",
			"needs": {"social": 0.1, "fun": 0.1}, "social": {"fun": 0.25}, "task": "Play with Dog"})
		out.append({"id": "s_fetch", "label": "Play Fetch", "icon": "ball", "minutes": 20.0, "pose": "wave",
			"needs": {"fun": 0.25}, "social": {"fun": 0.4}, "task": "Play with Dog"})
		return out
	out.append({"id": "s_chat", "label": "Chat", "icon": "chat", "minutes": 15.0, "pose": "talk",
		"needs": {"social": 0.3, "fun": 0.05}, "social": {"social": 0.25}})
	out.append({"id": "s_hug", "label": "Hug", "icon": "heart", "minutes": 4.0, "pose": "talk",
		"needs": {"social": 0.15}, "social": {"social": 0.15}})
	out.append({"id": "s_joke", "label": "Tell a Joke", "icon": "laugh", "minutes": 6.0, "pose": "talk",
		"needs": {"social": 0.12, "fun": 0.12}, "social": {"fun": 0.15, "social": 0.1}})
	if actor_kind == "adult" and target_kind == "child":
		out.append({"id": "s_homework", "label": "Help with Homework", "icon": "book", "minutes": 30.0, "pose": "talk",
			"needs": {"social": 0.15}, "social": {"social": 0.1}, "skill": "Logic", "task": "Do Homework"})
	return out


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
