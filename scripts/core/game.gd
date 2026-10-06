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
			s.needs[k] = clampf(s.needs[k] - hours * 0.04, 0.0, 1.0)
	time_changed.emit(day, minutes)
