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
## Skill XP needed per level (in-game hours of practice per level grows a bit).
const SKILL_HOURS_PER_LEVEL := 1.0
const LOCATIONS := ["home", "backyard", "festival", "market"]
const LOCATION_NAMES := {"home": "Home", "backyard": "Backyard BBQ", "festival": "Autumn Festival", "market": "Grocery Market"}
## Per-location task lists (kept when you travel away and back).
var location_tasks := {}
## Bought furniture per location: Array of {uid, item, pos: Vector3, rot: int}.
var placed := {}
var _uid := 0


func _ready() -> void:
	_default_household()


func _default_household() -> void:
	household = [
		{"name": "Jack", "kind": "adult", "look": "dad",
		 "needs": {"fun": 0.85, "hunger": 0.45, "hygiene": 0.6, "energy": 0.55, "social": 0.35},
		 "skills": {}},
		{"name": "Lily", "kind": "child", "look": "bunny_girl",
		 "needs": {"fun": 0.75, "hunger": 0.5, "hygiene": 0.55, "energy": 0.6},
		 "skills": {}},
		{"name": "Maya", "kind": "child", "look": "cat_girl",
		 "needs": {"fun": 0.7, "hunger": 0.75, "energy": 0.4},
		 "skills": {}},
		{"name": "Biscuit", "kind": "dog", "look": "beagle",
		 "needs": {"fun": 0.75, "hunger": 0.4},
		 "skills": {}},
	]
	household_changed.emit()


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


## Practise a skill for `hours` in-game hours. Emits skill_changed on level up.
func add_skill_xp(i: int, skill: String, hours: float) -> void:
	if i < 0 or i >= household.size() or skill == "":
		return
	var sk: Dictionary = household[i].skills
	var before: float = sk.get(skill, 0.0)
	var lvl := floorf(before)
	var gain := hours / (SKILL_HOURS_PER_LEVEL * (1.0 + lvl * 0.35))
	var after := minf(10.0, before + gain)
	sk[skill] = after
	if floorf(after) > lvl:
		skill_changed.emit(i, skill, int(floorf(after)))


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
	time_changed.emit(day, minutes)


## In-game minutes that pass this frame (0 when paused / frozen). The sim layer
## uses this so everything follows pause / play / fast.
func game_minutes(delta: float) -> float:
	if frozen or speed == 0:
		return 0.0
	return delta / SECONDS_PER_MINUTE * SPEED_MULT[speed]
