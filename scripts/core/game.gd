extends Node
## Global simulation state: clock, speed, money, household, tasks, location.
## Everything visual reads from here; nothing here knows about nodes.

signal time_changed(day: int, minutes: float)
signal speed_changed(speed: int)
signal money_changed(money: int)
signal tasks_changed
signal household_changed
signal location_changed(location: String)
signal selected_changed(index: int)
signal mode_changed(mode: String)
## World-anchored UI bubbles. data keys: text, icon, progress (0..1 or -1),
## kind ("action" | "speech" | "thought" | "skill" | "emote"), id (to update/replace).
signal bubble_requested(anchor: Node3D, data: Dictionary)
signal bubble_cleared(anchor: Node3D, id: String)
## Object action menu (pie menu) for a tapped interactable.
signal menu_requested(title: String, actions: Array, screen_pos: Vector2)
## Emitted by the HUD when a row of the action menu is picked (hud.gd forwards it).
signal action_chosen(title: String, action: Dictionary)
## Close any open action menu (HUD may listen; gameplay emits it on mode switches).
signal menu_closed
## A household member's skill went up. level is the new whole level (1..10).
signal skill_changed(index: int, skill: String, level: int)
## Needs were changed by gameplay (actions); the clock also refreshes need bars.
signal needs_changed(index: int)
## Short toast/notification line ("Not enough money", "Bought Armchair").
signal notify(text: String, icon: String)
## A placed (bought) object was added / moved / sold in the current location.
signal furniture_changed
## Overall mood of member index changed (value -100..100, see mood_band()).
signal mood_changed(index: int, mood: float)
## A moodlet was added / removed / expired for member index.
signal moodlets_changed(index: int)
## The visible action queue of member index changed (see queue_view()).
signal queue_changed(index: int)
## UI asks gameplay to cancel slot `slot` of member index's action queue
## (slot 0 = the action in progress).
signal queue_cancel_requested(index: int, slot: int)
## Friendship between two people (household names or townie names) changed.
## value -100..100; see rel_level().
signal relationship_changed(a: String, b: String, value: float)
## Two people reached a new relationship level ("Friend", "Good Friend"...).
signal relationship_level_changed(a: String, b: String, level: String)
## A member's wishes (Sims 3 wishes / promises) or lifetime happiness changed.
signal wishes_changed(index: int)

const DAY_NAMES := ["Mon.", "Tue.", "Wed.", "Thu.", "Fri.", "Sat.", "Sun."]
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
## Real seconds per in-game minute at speed 1.
const SECONDS_PER_MINUTE := 0.5
const SPEED_MULT := [0.0, 1.0, 3.0, 8.0]

## 0 = paused, 1 = play, 2 = fast, 3 = ultra
var speed := 1:
	set(v):
		speed = clampi(v, 0, 3)
		speed_changed.emit(speed)
var day := 0          # 0 = Monday
var minutes := 8 * 60.0  # minutes since midnight
var season := 0
var money := 12450:
	set(v):
		money = v
		money_changed.emit(money)
var location := "home"
var selected := 0:
	set(v):
		selected = v
		selected_changed.emit(selected)
## "live", "build", "buy", "decorate", "manage"
var mode := "live":
	set(v):
		mode = v
		mode_changed.emit(mode)

## Household members. needs: 0..1. kind: "adult" | "child" | "dog".
var household: Array[Dictionary] = []
## Tasks: {id, title, icon, done}
var tasks: Array[Dictionary] = []
## When true the clock is frozen by a screenshot preset.
var frozen := false
## True while the sim layer runs (live play / playtest); false for screenshot presets.
var live := false
## Need decay per in-game hour (default for unknown needs: NEED_DECAY_DEFAULT).
const NEED_DECAY := {"hunger": 0.055, "energy": 0.04, "fun": 0.05, "hygiene": 0.035, "social": 0.04, "bladder": 0.08}
const NEED_DECAY_DEFAULT := 0.04
## Skill XP: in-game hours of practice for level 0->1; each level needs
## SKILL_LEVEL_GROWTH more (level 9->10 takes ~5.5x as long as 0->1).
const SKILL_HOURS_PER_LEVEL := 3.0
const SKILL_LEVEL_GROWTH := 0.5
## Skill names shown in the skills panel (order) and their icons.
const SKILL_ICONS := {"Logic": "chart", "Creativity": "palette", "Music": "music", "Cooking": "cook",
	"Writing": "pencil", "Fitness": "ball", "Charisma": "chat", "Fetch": "ball"}
## Mood bands (value -100..100): >= MOOD_GOOD green, <= MOOD_BAD red, else yellow.
const MOOD_GOOD := 12.0
const MOOD_BAD := -12.0
const MOOD_COLORS := {"good": Color("4fd34a"), "okay": Color("f2c230"), "bad": Color("ee4a3c")}
const MOOD_WORDS := {"good": "Happy", "okay": "Fine", "bad": "Upset"}
const LOCATIONS := ["home", "backyard", "festival", "market"]
const LOCATION_NAMES := {"home": "Home", "backyard": "Backyard BBQ", "festival": "Autumn Festival", "market": "Grocery Market"}
## Per-location task lists (kept when you travel away and back).
var location_tasks := {}
## Bought furniture per location: Array of {uid, item, pos: Vector3, rot: int}.
var placed := {}
var _uid := 0
var _mood_acc := 0.0

## Townies: non-household people the locations stage, keyed by their look.
## They keep their name (and your relationship with them) from lot to lot.
const TOWNIES := {
	"npc_0": {"name": "Rosie Maple", "kind": "adult", "trait": "Friendly"},
	"npc_1": {"name": "Marcus Bell", "kind": "adult", "trait": "Good Sense of Humor"},
	"npc_2": {"name": "June Harlow", "kind": "adult", "trait": "Neighborly"},
	"npc_3": {"name": "Omar Reed", "kind": "adult", "trait": "Charismatic"},
	"npc_4": {"name": "Toby Finch", "kind": "child", "trait": "Artistic"},
	"npc_5": {"name": "Hana Sato", "kind": "adult", "trait": "Bookworm"},
	"npc_6": {"name": "Walter Moss", "kind": "adult", "trait": "Grumpy"},
	"npc_7": {"name": "Kai Ortiz", "kind": "child", "trait": "Athletic"},
}
## Relationship levels (friendship value -100..100), lowest first: [max, label].
const REL_LEVELS := [[-60.0, "Enemy"], [-20.0, "Disliked"], [25.0, "Acquaintance"],
	[55.0, "Friend"], [80.0, "Good Friend"], [101.0, "Best Friend"]]
## "a|b" (sorted names) -> {value: float, met: float (total_minutes), last: float}
var relationships := {}


func _ready() -> void:
	_default_household()


func _default_household() -> void:
	household = [
		{"name": "Jack", "kind": "adult", "look": "dad",
		 "needs": {"fun": 0.85, "hunger": 0.45, "hygiene": 0.6, "energy": 0.55, "social": 0.35},
		 "skills": {"Logic": 3.4, "Cooking": 2.15, "Writing": 1.3}},
		{"name": "Lily", "kind": "child", "look": "bunny_girl",
		 "needs": {"fun": 0.75, "hunger": 0.5, "hygiene": 0.55, "energy": 0.6},
		 "skills": {"Creativity": 2.6, "Logic": 0.45}},
		{"name": "Maya", "kind": "child", "look": "cat_girl",
		 "needs": {"fun": 0.7, "hunger": 0.75, "energy": 0.4},
		 "skills": {"Creativity": 0.7}},
		{"name": "Biscuit", "kind": "dog", "look": "beagle",
		 "needs": {"fun": 0.75, "hunger": 0.4},
		 "skills": {"Fetch": 1.2}},
	]
	for i in household.size():
		_ensure_member(household[i])
		_recompute_mood(i, false)
	# Family starts close; the dog adores everyone.
	_seed_rel("Jack", "Lily", 72.0)
	_seed_rel("Jack", "Maya", 66.0)
	_seed_rel("Lily", "Maya", 48.0)
	_seed_rel("Jack", "Biscuit", 58.0)
	_seed_rel("Lily", "Biscuit", 84.0)
	_seed_rel("Maya", "Biscuit", 52.0)
	# Jack already knows the grocer a little.
	_seed_rel("Jack", "Omar Reed", 28.0)
	household_changed.emit()


## Mood / queue fields every member dictionary carries.
func _ensure_member(m: Dictionary) -> void:
	if not m.has("moodlets"):
		m["moodlets"] = []
	if not m.has("mood"):
		m["mood"] = 0.0
	if not m.has("queue_view"):
		m["queue_view"] = []
	if not m.has("skills"):
		m["skills"] = {}
	if not m.has("wishes"):
		m["wishes"] = []
	if not m.has("lth"):
		m["lth"] = 0


func set_tasks(list: Array) -> void:
	tasks.clear()
	for i in list.size():
		var t: Dictionary = list[i]
		tasks.append({"id": t.get("id", str(i)), "title": t.title, "icon": t.get("icon", ""), "done": t.get("done", false)})
	tasks_changed.emit()


func complete_task(id: String) -> void:
	for t in tasks:
		if t.id == id and not t.done:
			t.done = true
			tasks_changed.emit()
			return


## Tick off a task by its title (case-insensitive). Returns true if one changed.
func complete_task_title(title: String) -> bool:
	var want := title.strip_edges().to_lower()
	for t in tasks:
		if str(t.title).to_lower() == want and not t.done:
			t.done = true
			tasks_changed.emit()
			return true
	return false


func has_open_task(title: String) -> bool:
	var want := title.strip_edges().to_lower()
	for t in tasks:
		if str(t.title).to_lower() == want and not t.done:
			return true
	return false


## Add (or with a negative amount, spend) money. Returns false when it can't be afforded.
func add_money(amount: int) -> bool:
	if amount < 0 and money + amount < 0:
		return false
	money += amount
	return true


func can_afford(cost: int) -> bool:
	return money >= cost


func member_index(member_name: String) -> int:
	for i in household.size():
		if household[i].name == member_name:
			return i
	return -1


## Change one need of member i by delta (clamped 0..1). Unknown needs are ignored.
func change_need(i: int, need: String, delta: float) -> void:
	if i < 0 or i >= household.size():
		return
	var n: Dictionary = household[i].needs
	if not n.has(need):
		return
	n[need] = clampf(n[need] + delta, 0.0, 1.0)


## Skill level as a float (whole part = level shown to the player).
func skill_level(i: int, skill: String) -> float:
	if i < 0 or i >= household.size():
		return 0.0
	return float(household[i].skills.get(skill, 0.0))


## Practise a skill for `hours` in-game hours (callers scale by mood_mult()).
## Emits skill_changed and returns the new level on a level up, else 0.
func add_skill_xp(i: int, skill: String, hours: float) -> int:
	if i < 0 or i >= household.size() or skill == "":
		return 0
	var sk: Dictionary = household[i].skills
	var before: float = sk.get(skill, 0.0)
	var lvl := floorf(before)
	if lvl >= 10.0:
		return 0
	var gain := hours / skill_hours_for_level(int(lvl))
	# Never jump more than one level in one call.
	var after := minf(minf(10.0, lvl + 1.0), before + gain)
	sk[skill] = after
	if floorf(after) > lvl:
		skill_changed.emit(i, skill, int(floorf(after)))
		return int(floorf(after))
	return 0


## In-game hours of practice needed to go from `level` to level + 1.
func skill_hours_for_level(level: int) -> float:
	return SKILL_HOURS_PER_LEVEL * (1.0 + level * SKILL_LEVEL_GROWTH)


## [{name, level (int), frac (0..1 toward next), icon}] sorted by level.
func skills_list(i: int) -> Array:
	var out: Array = []
	if i < 0 or i >= household.size():
		return out
	var sk: Dictionary = household[i].skills
	for k in sk:
		var v: float = sk[k]
		out.append({"name": k, "level": int(floorf(v)), "frac": v - floorf(v), "icon": SKILL_ICONS.get(k, "star")})
	out.sort_custom(func(a, b): return a.level + a.frac > b.level + b.frac)
	return out


# =================================================================== mood

## Absolute in-game minutes since Monday 00:00 of week 0 (for moodlet expiry).
func total_minutes() -> float:
	return day * 1440.0 + minutes


## Add (or refresh) a moodlet. delta: mood points (+/-), hours: how long it lasts
## (<= 0 = until removed). Returns true when it is new.
func add_moodlet(i: int, id: String, label: String, icon: String, delta: float, hours: float, desc := "") -> bool:
	if i < 0 or i >= household.size():
		return false
	_ensure_member(household[i])
	var list: Array = household[i].moodlets
	var until := total_minutes() + hours * 60.0 if hours > 0.0 else INF
	for ml in list:
		if ml.id == id:
			ml.expires = maxf(ml.expires, until)
			if absf(ml.delta - delta) > 0.01 or ml.label != label:
				ml.delta = delta
				ml.label = label
				ml.icon = icon
				_recompute_mood(i, true)
				moodlets_changed.emit(i)
			return false
	list.append({"id": id, "icon": icon, "label": label, "delta": delta, "expires": until,
		"desc": desc, "added": total_minutes()})
	_recompute_mood(i, true)
	moodlets_changed.emit(i)
	return true


func remove_moodlet(i: int, id: String) -> bool:
	if i < 0 or i >= household.size():
		return false
	var list: Array = household[i].get("moodlets", [])
	for k in list.size():
		if list[k].id == id:
			list.remove_at(k)
			_recompute_mood(i, true)
			moodlets_changed.emit(i)
			return true
	return false


func has_moodlet(i: int, id: String) -> bool:
	if i < 0 or i >= household.size():
		return false
	for ml in household[i].get("moodlets", []):
		if ml.id == id:
			return true
	return false


## Moodlets of member i, strongest first.
func moodlets(i: int) -> Array:
	if i < 0 or i >= household.size():
		return []
	var list: Array = household[i].get("moodlets", []).duplicate()
	list.sort_custom(func(a, b): return absf(a.delta) > absf(b.delta))
	return list


## Overall mood -100..100: the needs (average around the middle) plus moodlets.
func mood(i: int) -> float:
	if i < 0 or i >= household.size():
		return 0.0
	return float(household[i].get("mood", 0.0))


func mood_band(i: int) -> String:
	var m := mood(i)
	if m >= MOOD_GOOD:
		return "good"
	if m <= MOOD_BAD:
		return "bad"
	return "okay"


func mood_color(i: int) -> Color:
	return MOOD_COLORS[mood_band(i)]


func mood_word(i: int) -> String:
	var m := mood(i)
	if m >= 45.0:
		return "Very Happy"
	if m <= -45.0:
		return "Miserable"
	return MOOD_WORDS[mood_band(i)]


## Multiplier for skill gain and work pay: 0.6 (miserable) .. 1.4 (very happy).
func mood_mult(i: int) -> float:
	return clampf(1.0 + mood(i) / 125.0, 0.6, 1.4)


func _recompute_mood(i: int, emit: bool) -> void:
	var m: Dictionary = household[i]
	var needs: Dictionary = m.get("needs", {})
	var sum := 0.0
	for k in needs:
		sum += needs[k]
	var v := 0.0
	if not needs.is_empty():
		v = (sum / needs.size() - 0.5) * 50.0
	for ml in m.get("moodlets", []):
		v += ml.delta
	v = clampf(v, -100.0, 100.0)
	var old: float = m.get("mood", 0.0)
	m["mood"] = v
	if emit and (absf(old - v) >= 0.5 or _band(old) != _band(v)):
		mood_changed.emit(i, v)


static func _band(v: float) -> String:
	return "good" if v >= MOOD_GOOD else ("bad" if v <= MOOD_BAD else "okay")


## Drop expired moodlets and refresh every member's mood.
func update_moods() -> void:
	var now := total_minutes()
	for i in household.size():
		var list: Array = household[i].get("moodlets", [])
		var changed := false
		for k in range(list.size() - 1, -1, -1):
			if list[k].expires <= now:
				list.remove_at(k)
				changed = true
		_recompute_mood(i, true)
		if changed:
			moodlets_changed.emit(i)


# =================================================================== relationships

static func rel_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _seed_rel(a: String, b: String, v: float) -> void:
	relationships[rel_key(a, b)] = {"value": v, "met": 0.0, "last": 0.0}


## Have these two people met?
func has_met(a: String, b: String) -> bool:
	return relationships.has(rel_key(a, b))


## Friendship value -100..100 (0 for strangers).
func rel(a: String, b: String) -> float:
	var r = relationships.get(rel_key(a, b))
	return 0.0 if r == null else float(r.value)


## Change friendship by delta (meeting them if they hadn't). Emits
## relationship_changed and, on crossing a level, relationship_level_changed.
func change_rel(a: String, b: String, delta: float) -> float:
	if a == b or a == "" or b == "":
		return 0.0
	var k := rel_key(a, b)
	if not relationships.has(k):
		relationships[k] = {"value": 0.0, "met": total_minutes(), "last": total_minutes()}
	var r: Dictionary = relationships[k]
	var before: float = r.value
	r.value = clampf(before + delta, -100.0, 100.0)
	r.last = total_minutes()
	relationship_changed.emit(a, b, r.value)
	var l0 := rel_level(before)
	var l1 := rel_level(r.value)
	if l0 != l1:
		relationship_level_changed.emit(a, b, l1)
	return r.value


static func rel_level(v: float) -> String:
	for lv in REL_LEVELS:
		if v < lv[0]:
			return lv[1]
	return "Best Friend"


## -2 Enemy .. 0 Acquaintance .. 3 Best Friend.
static func rel_tier(v: float) -> int:
	for k in REL_LEVELS.size():
		if v < REL_LEVELS[k][0]:
			return k - 2
	return 3


## Is this name a household member?
func is_family(person: String) -> bool:
	return member_index(person) >= 0


func townie_by_look(look: String) -> Dictionary:
	return TOWNIES.get(look, {})


func townie_names() -> Array:
	var out: Array = []
	for k in TOWNIES:
		out.append(TOWNIES[k].name)
	return out


## Everyone member i knows: [{name, value, level, family: bool, kind, look}],
## family first, then by friendship.
func rel_list(i: int) -> Array:
	var out: Array = []
	if i < 0 or i >= household.size():
		return out
	var me: String = household[i].name
	for k in relationships:
		var parts: PackedStringArray = (k as String).split("|")
		if parts.size() != 2 or not me in parts:
			continue
		var other: String = parts[1] if parts[0] == me else parts[0]
		var v: float = relationships[k].value
		var fam := is_family(other)
		var kind := "adult"
		var look := ""
		if fam:
			var m: Dictionary = household[member_index(other)]
			kind = m.get("kind", "adult")
			look = m.get("look", "")
		else:
			for tk in TOWNIES:
				if TOWNIES[tk].name == other:
					kind = TOWNIES[tk].kind
					look = tk
		out.append({"name": other, "value": v, "level": rel_level(v), "family": fam, "kind": kind, "look": look})
	out.sort_custom(func(x, y): return x.family and not y.family or (x.family == y.family and x.value > y.value))
	return out


## Townies member i has met (for "Meet N Neighbors" tasks).
func townies_met(i: int) -> int:
	var n := 0
	for r in rel_list(i):
		if not r.family:
			n += 1
	return n


## Slow drift toward neutral for relationships nobody tends (per in-game day:
## -1.5 for friends you haven't seen in two days; family never drops below 30).
func _decay_relationships(days: float) -> void:
	var now := total_minutes()
	for k in relationships:
		var r: Dictionary = relationships[k]
		if now - float(r.last) < 2880.0:
			continue
		var parts: PackedStringArray = (k as String).split("|")
		var fam := is_family(parts[0]) and is_family(parts[1])
		var floor_v := 30.0 if fam else 0.0
		if r.value > floor_v:
			r.value = maxf(floor_v, r.value - 1.5 * days)


# =================================================================== action queue view

## What the selected sim's queue strip shows: [{label, icon, progress, auto,
## current}] -- slot 0 is the action in progress (if any).
func queue_view(i: int) -> Array:
	if i < 0 or i >= household.size():
		return []
	return household[i].get("queue_view", [])


func set_queue_view(i: int, view: Array) -> void:
	if i < 0 or i >= household.size():
		return
	household[i]["queue_view"] = view
	queue_changed.emit(i)


## UI: the player tapped slot `slot` of member i's queue strip.
func request_queue_cancel(i: int, slot: int) -> void:
	queue_cancel_requested.emit(i, slot)


## Go to another lot. main.gd rebuilds the world on location_changed.
func travel(loc: String) -> void:
	if not loc in LOCATIONS:
		push_warning("Game.travel: unknown location " + loc)
		return
	location_tasks[location] = tasks.duplicate(true)
	location = loc
	mode = "live"
	location_changed.emit(loc)


func next_uid() -> int:
	_uid += 1
	return _uid


func show_bubble(anchor: Node3D, data: Dictionary) -> void:
	bubble_requested.emit(anchor, data)


func clear_bubble(anchor: Node3D, id := "") -> void:
	bubble_cleared.emit(anchor, id)


func set_time(d: int, h: int, m: int) -> void:
	day = d
	minutes = h * 60.0 + m
	time_changed.emit(day, minutes)


## 0..24 fractional hour, handy for lighting.
func hour() -> float:
	return minutes / 60.0


func clock_text() -> String:
	var h := int(minutes / 60.0) % 24
	var m := int(minutes) % 60
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%s %d:%02d %s" % [DAY_NAMES[day % 7], h12, m, ampm]


func is_night() -> bool:
	var h := hour()
	return h < 6.0 or h >= 19.5


func _process(delta: float) -> void:
	if frozen or speed == 0:
		return
	var dm: float = delta / SECONDS_PER_MINUTE * SPEED_MULT[speed]
	minutes += dm
	if minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
	# Needs decay (per in-game hour rates).
	var hours := dm / 60.0
	for s in household:
		for k in s.needs:
			s.needs[k] = clampf(s.needs[k] - hours * NEED_DECAY.get(k, NEED_DECAY_DEFAULT), 0.0, 1.0)
	_mood_acc += dm
	if _mood_acc >= 2.0:
		_mood_acc = 0.0
		update_moods()
		_decay_relationships(2.0 / 1440.0)
	time_changed.emit(day, minutes)


## In-game minutes that pass this frame (0 when paused / frozen). The sim layer
## uses this so everything follows pause / play / fast.
func game_minutes(delta: float) -> float:
	if frozen or speed == 0:
		return 0.0
	return delta / SECONDS_PER_MINUTE * SPEED_MULT[speed]


# =================================================================== wishes

## Promised wishes per member (Sims 3 lets you promise a few at a time).
const MAX_PROMISED := 2

## A member's wishes: [{id, label, icon, kind, arg, n, have, reward, promised, born}].
func wishes(i: int) -> Array:
	if i < 0 or i >= household.size():
		return []
	_ensure_member(household[i])
	return household[i].wishes


## Lifetime happiness points earned from fulfilled wishes.
func lth(i: int) -> int:
	if i < 0 or i >= household.size():
		return 0
	return int(household[i].get("lth", 0))


func add_wish(i: int, w: Dictionary) -> void:
	if i < 0 or i >= household.size():
		return
	_ensure_member(household[i])
	household[i].wishes.append(w)
	wishes_changed.emit(i)


func remove_wish(i: int, id: String) -> void:
	var list := wishes(i)
	for k in list.size():
		if list[k].id == id:
			list.remove_at(k)
			wishes_changed.emit(i)
			return


## Promise / un-promise a wish. Returns the new promised state.
func toggle_promise(i: int, id: String) -> bool:
	var list := wishes(i)
	var n := 0
	for w in list:
		if w.get("promised", false):
			n += 1
	for w in list:
		if w.id != id:
			continue
		if w.get("promised", false):
			w.promised = false
		elif n < MAX_PROMISED:
			w.promised = true
		else:
			notify.emit("Only %d promises at a time" % MAX_PROMISED, "star")
		if w.promised:
			add_moodlet(i, "hopeful", "Hopeful", "star", 5.0, 0.0, "Promised: %s" % w.label)
		elif not list.any(func(x): return x.get("promised", false)):
			remove_moodlet(i, "hopeful")
		wishes_changed.emit(i)
		return w.promised
	return false


## A wish came true: lifetime happiness + a moodlet. Returns the points.
func fulfil_wish(i: int, id: String) -> int:
	var list := wishes(i)
	for k in list.size():
		var w: Dictionary = list[k]
		if w.id != id:
			continue
		var pts := int(w.get("reward", 250))
		if w.get("promised", false):
			pts = int(pts * 1.5)
		household[i].lth = lth(i) + pts
		list.remove_at(k)
		var promised: bool = w.get("promised", false)
		add_moodlet(i, "wish_" + id, "Fulfilled a Wish" if not promised else "Promise Kept!", "star", 15.0 if promised else 8.0, 6.0, w.label)
		if not list.any(func(x): return x.get("promised", false)):
			remove_moodlet(i, "hopeful")
		notify.emit("%s's wish came true: %s  +%d" % [household[i].name, w.label, pts], "star")
		wishes_changed.emit(i)
		return pts
	return 0
