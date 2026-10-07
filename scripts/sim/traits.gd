extends RefCounted
## Sims 3 traits: each member has a few; they bend free will, skill gain,
## need decay, friendships and job performance, so every sim plays
## differently. Pure data + lookups (members carry "traits": Array[String]).
##
##   bias:  {key: score} free-will bonus; key is an action id, "skill:<Skill>",
##          "pose:<pose>", "social" (any social) or "family" (socials with family)
##   skill: {Skill: multiplier} on practice
##   decay: {need: multiplier} on need decay
##   rel:   multiplier on friendship gains ("family_rel" for family only)
##   work:  performance bonus per shift

const TRAITS := {
	"Workaholic": {"icon": "laptop", "desc": "Better at work, loves the computer",
		"bias": {"skill:Logic": 0.05, "emails": 0.06, "freelance": 0.05}, "work": 4.0},
	"Natural Cook": {"icon": "cook", "desc": "Learns Cooking 50% faster",
		"bias": {"skill:Cooking": 0.07}, "skill": {"Cooking": 1.5}},
	"Family-Oriented": {"icon": "heart", "desc": "Seeks out the family, bonds faster",
		"bias": {"family": 0.07}, "family_rel": 1.3},
	"Artistic": {"icon": "palette", "desc": "Learns Creativity 50% faster",
		"bias": {"skill:Creativity": 0.07}, "skill": {"Creativity": 1.5}},
	"Friendly": {"icon": "chat", "desc": "Makes friends easily",
		"bias": {"social": 0.05}, "rel": 1.25, "decay": {"social": 1.2}},
	"Virtuoso": {"icon": "music", "desc": "Learns Music 50% faster",
		"bias": {"skill:Music": 0.07}, "skill": {"Music": 1.5}},
	"Couch Potato": {"icon": "tv", "desc": "Loves TV and games, tires slowly",
		"bias": {"watch": 0.08, "watch_show": 0.08, "games": 0.07, "relax": 0.05}, "decay": {"energy": 0.85}},
	"Hyper": {"icon": "ball", "desc": "Always wants to play",
		"bias": {"pose:play": 0.06, "chase_ball": 0.05}, "decay": {"fun": 1.3, "energy": 1.1}},
	"Loyal": {"icon": "paw", "desc": "Sticks close to the family",
		"bias": {"family": 0.08}, "family_rel": 1.3},
	"Bookworm": {"icon": "book", "desc": "Loves to read, learns Writing faster",
		"bias": {"read_book": 0.08, "homework": 0.04}, "skill": {"Writing": 1.5}},
}
## Starting traits by look.
const DEFAULT := {
	"dad": ["Workaholic", "Natural Cook", "Family-Oriented"],
	"bunny_girl": ["Artistic", "Friendly"],
	"cat_girl": ["Virtuoso", "Couch Potato"],
	"beagle": ["Hyper", "Loyal"],
}


static func of(member: Dictionary) -> Array:
	return member.get("traits", [])


static func has(member: Dictionary, t: String) -> bool:
	return t in of(member)


## Free-will bonus for an action (social: it's a social, family: with family).
static func bias(member: Dictionary, a: Dictionary, social := false, family := false) -> float:
	var b := 0.0
	var id: String = a.get("id", "")
	var sk: String = "skill:" + str(a.get("skill", "-"))
	var ps: String = "pose:" + str(a.get("pose", "-"))
	for t in of(member):
		var bi: Dictionary = TRAITS.get(t, {}).get("bias", {})
		if bi.is_empty():
			continue
		b += float(bi.get(id, 0.0)) + float(bi.get(sk, 0.0)) + float(bi.get(ps, 0.0))
		if social:
			b += float(bi.get("social", 0.0))
			if family:
				b += float(bi.get("family", 0.0))
	return b


static func skill_mult(member: Dictionary, skill: String) -> float:
	var m := 1.0
	for t in of(member):
		m *= float(TRAITS.get(t, {}).get("skill", {}).get(skill, 1.0))
	return m


## {need: multiplier} for every need a trait changes.
static func decay_table(member: Dictionary) -> Dictionary:
	var d := {}
	for t in of(member):
		var td: Dictionary = TRAITS.get(t, {}).get("decay", {})
		for k in td:
			d[k] = float(d.get(k, 1.0)) * float(td[k])
	return d


static func rel_mult(member: Dictionary, family: bool) -> float:
	var m := 1.0
	for t in of(member):
		var td: Dictionary = TRAITS.get(t, {})
		m *= float(td.get("rel", 1.0))
		if family:
			m *= float(td.get("family_rel", 1.0))
	return m


static func work_bonus(member: Dictionary) -> float:
	var b := 0.0
	for t in of(member):
		b += float(TRAITS.get(t, {}).get("work", 0.0))
	return b


static func icon(t: String) -> String:
	return TRAITS.get(t, {}).get("icon", "star")
