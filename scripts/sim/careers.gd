extends RefCounted
## Sims 3 careers (and school for children): pure rules + data.
## A member's career lives in Game.household[i].career:
##   {track: String, level: int (1..10), perf: float (0..100),
##    tendency: "hard" | "normal" | "easy", last_day: int (day of the last
##    shift worked or missed), trend: float (last shift's change), shifts: int}
## An empty dictionary means unemployed. Work state (rabbit hole) lives in
## Game.household[i].work: {state: "" | "going" | "away", until, start, late}.
## SimAgent drives the shift (walk to the door, carpool, away, come home);
## this file says when shifts are, what they pay and how performance moves.

## days: weekday indices (0 = Mon). start: hour the shift starts. hours: length.
## skill: the skill that matters. req[k]: skill level needed to be promoted
## INTO level k+1 (req[0] unused). wage[k]: $ per hour at level k+1.
const TRACKS := {
	"business": {
		"name": "Business", "icon": "chart", "skill": "Logic", "kinds": ["adult"],
		"days": [0, 1, 2, 3, 4], "start": 9, "hours": 8,
		"titles": ["Mailroom Technician", "Office Assistant", "Sales Rep", "Team Leader", "Manager",
			"Regional Manager", "Vice President", "Executive VP", "CFO", "CEO"],
		"wage": [14, 18, 23, 29, 36, 45, 56, 70, 86, 105],
		"req": [0, 0, 1, 2, 3, 4, 5, 6, 8, 9],
	},
	"culinary": {
		"name": "Culinary", "icon": "cook", "skill": "Cooking", "kinds": ["adult"],
		"days": [1, 2, 3, 4, 5], "start": 15, "hours": 7,
		"titles": ["Dishwasher", "Line Cook", "Prep Cook", "Sous Chef", "Pastry Chef",
			"Head Chef", "Restaurateur", "Celebrity Chef", "TV Chef", "Culinary Legend"],
		"wage": [12, 16, 21, 27, 34, 43, 54, 67, 82, 100],
		"req": [0, 0, 1, 2, 3, 4, 5, 6, 8, 9],
	},
	"journalism": {
		"name": "Journalism", "icon": "pencil", "skill": "Writing", "kinds": ["adult"],
		"days": [0, 1, 2, 3, 4], "start": 10, "hours": 7,
		"titles": ["Paper Delivery", "Copy Editor", "Staff Writer", "Columnist", "Reporter",
			"Senior Reporter", "Features Editor", "Managing Editor", "Editor in Chief", "Publisher"],
		"wage": [13, 17, 22, 28, 35, 44, 55, 68, 84, 102],
		"req": [0, 0, 1, 2, 3, 4, 5, 6, 8, 9],
	},
	"music": {
		"name": "Music", "icon": "music", "skill": "Music", "kinds": ["adult"],
		"days": [2, 3, 4, 5, 6], "start": 17, "hours": 6,
		"titles": ["Roadie", "Ticket Seller", "Stagehand", "Session Musician", "Backup Player",
			"Band Member", "Lead Guitarist", "Headliner", "Rock Star", "Living Legend"],
		"wage": [12, 17, 23, 30, 38, 48, 60, 75, 92, 112],
		"req": [0, 0, 1, 2, 3, 4, 5, 6, 8, 9],
	},
	# Works from the home computer (no commute): a forced "Work" action.
	"freelance": {
		"name": "Freelance Dev", "icon": "laptop", "skill": "Logic", "kinds": ["adult"], "home": true,
		"days": [0, 1, 2, 3, 4], "start": 10, "hours": 6,
		"titles": ["Junior Freelancer", "Web Developer", "App Developer", "Senior Developer", "Tech Lead",
			"Software Architect", "Indie Studio Owner", "Startup Founder", "Tech Mogul", "Silicon Legend"],
		"wage": [13, 17, 22, 28, 35, 44, 55, 68, 84, 102],
		"req": [0, 0, 1, 2, 3, 4, 5, 6, 8, 9],
	},
	# Children are enrolled in school automatically; no pay, a grade instead.
	"school": {
		"name": "School", "icon": "book", "skill": "", "kinds": ["child"],
		"days": [0, 1, 2, 3, 4], "start": 8, "hours": 6, "school": true,
		"titles": ["Elementary"], "wage": [0], "req": [0],
	},
}
## Tracks offered by "Find a Job" (in this order).
const JOB_TRACKS := ["business", "freelance", "culinary", "journalism", "music"]
## The sim leaves this many minutes before the shift (walk to the door + carpool).
const LEAVE_BEFORE := 30.0
## Arriving later than this after the start counts as a missed shift.
const MISS_AFTER := 120.0
## Home workers head for the computer this many minutes before the start.
const HOME_LEAD := 10.0
const TENDENCIES := ["hard", "normal", "easy"]
const TENDENCY_LABEL := {"hard": "Work Hard", "normal": "Normal", "easy": "Take It Easy"}
const TENDENCY_PERF := {"hard": 12.0, "normal": 7.0, "easy": 2.0}
const PROMOTE_AT := 100.0
const DEMOTE_AT := 0.0
const PERF_AFTER_PROMO := 35.0
const PERF_AFTER_DEMO := 45.0
const GRADES := [[20.0, "F"], [40.0, "D"], [60.0, "C"], [80.0, "B"], [95.0, "A"], [101.0, "A+"]]


static func track(c: Dictionary) -> Dictionary:
	return TRACKS.get(str(c.get("track", "")), {})


static func is_school(c: Dictionary) -> bool:
	return track(c).get("school", false)


static func new_career(track_id: String) -> Dictionary:
	return {"track": track_id, "level": 1, "perf": 50.0 if track_id == "school" else 40.0, "tendency": "normal",
		"last_day": -1, "trend": 0.0, "shifts": 0}


static func title(c: Dictionary) -> String:
	var t := track(c)
	if t.is_empty():
		return "Unemployed"
	var titles: Array = t.titles
	return titles[clampi(int(c.get("level", 1)) - 1, 0, titles.size() - 1)]


static func wage(c: Dictionary) -> int:
	var t := track(c)
	if t.is_empty():
		return 0
	var w: Array = t.wage
	return int(w[clampi(int(c.get("level", 1)) - 1, 0, w.size() - 1)])


static func hours(c: Dictionary) -> int:
	return int(track(c).get("hours", 0))


static func paycheck(c: Dictionary) -> int:
	return wage(c) * hours(c)


static func works_on(c: Dictionary, weekday: int) -> bool:
	var t := track(c)
	return not t.is_empty() and weekday % 7 in t.days


## Shift start / end of a given day, in absolute minutes (Game.total_minutes()).
static func shift_start(c: Dictionary, day: int) -> float:
	return day * 1440.0 + float(track(c).get("start", 9)) * 60.0


static func shift_end(c: Dictionary, day: int) -> float:
	return shift_start(c, day) + hours(c) * 60.0


## Skill level needed for the next promotion (0 = none, -1 = top level).
static func next_req(c: Dictionary) -> int:
	var t := track(c)
	if t.is_empty() or is_school(c):
		return 0
	var lv := int(c.get("level", 1))
	if lv >= (t.req as Array).size():
		return -1
	return int(t.req[lv])


static func grade(perf: float) -> String:
	for g in GRADES:
		if perf < g[0]:
			return g[1]
	return "A+"


## "Mon–Fri 9 AM–5 PM"
static func schedule_text(c: Dictionary) -> String:
	var t := track(c)
	if t.is_empty():
		return ""
	var days: Array = t.days
	var names := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	var d := "%s–%s" % [names[days[0]], names[days[-1]]]
	return "%s %s–%s" % [d, _hour_text(int(t.start)), _hour_text(int(t.start) + int(t.hours))]


## "9a–5p"
static func _short_hours(c: Dictionary) -> String:
	var t := track(c)
	var a := int(t.start)
	var b := (a + int(t.hours)) % 24
	return "%d%s–%d%s" % [12 if a % 12 == 0 else a % 12, "a" if a < 12 else "p", 12 if b % 12 == 0 else b % 12, "a" if b < 12 else "p"]


static func _hour_text(h: int) -> String:
	h = h % 24
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d %s" % [h12, "AM" if h < 12 else "PM"]


## Menu rows for "Find a Job" (one per track the member can take).
static func job_rows(member: Dictionary) -> Array:
	var rows: Array = []
	var kind: String = member.get("kind", "adult")
	var cur: String = str(member.get("career", {}).get("track", ""))
	for id in JOB_TRACKS:
		var t: Dictionary = TRACKS[id]
		if not kind in t.kinds or id == cur:
			continue
		var c := new_career(id)
		# Short label (the menu card is narrow); "sub" carries the schedule
		# for a HUD that shows a second line.
		var where := " · works from home" if t.get("home", false) else ""
		rows.append({"id": "job_" + id, "label": "%s · $%d/h" % [t.name, wage(c)], "icon": t.icon, "track": id,
			"sub": schedule_text(c) + where, "hours": _short_hours(c)})
	return rows


## Performance change of one shift.
##   mood -100..100, skill: the member's level in the track's skill,
##   bonus: trait bonus, homework: did homework since the last school day.
static func perf_delta(c: Dictionary, mood: float, skill: float, late: bool, bonus: float, homework: bool) -> float:
	var d: float = TENDENCY_PERF.get(str(c.get("tendency", "normal")), 7.0)
	d += clampf(mood / 100.0, -1.0, 1.0) * 10.0
	if is_school(c):
		d += 10.0 if homework else -6.0
	else:
		var need := next_req(c)
		if need > 0:
			d += clampf((skill - need) * 2.0, -6.0, 6.0)
		else:
			d += clampf(skill * 0.5, 0.0, 4.0)
	if late:
		d -= 8.0
	return d + bonus


## Need changes from a shift (applied when the sim comes home).
static func shift_needs(c: Dictionary) -> Dictionary:
	var t: String = str(c.get("tendency", "normal"))
	var n := {"hunger": 0.25, "social": 0.3, "fun": -0.05, "energy": -0.05}
	if is_school(c):
		n = {"hunger": 0.25, "social": 0.35, "fun": 0.0, "energy": -0.05}
	match t:
		"hard":
			n.fun -= 0.1
			n.energy -= 0.1
		"easy":
			n.fun += 0.1
			n.energy += 0.05
	return n


# =================================================================== chance cards

## Sims 3 career "chance cards": once in a while, mid-shift, a choice pops up.
## yes / no: {perf, hours (extra shift hours), mood: [id, label, icon, delta, hours],
## odds (chance the yes-outcome succeeds; else fail)}.
const CHANCE_P := 0.35
const CHANCES := [
	{"id": "overtime", "text": "%s's boss asks for some overtime", "icon": "laptop",
	 "yes_label": "Stay Late (+2h)", "no_label": "Head Home on Time",
	 "yes": {"perf": 8.0, "hours": 2.0, "mood": ["overtime", "Overtime", "laptop", -5.0, 4.0]},
	 "no": {"perf": 0.0}},
	{"id": "pitch", "text": "%s could pitch an idea at the big meeting", "icon": "bulb",
	 "yes_label": "Pitch It!", "no_label": "Stay Quiet", "odds": 0.6,
	 "yes": {"perf": 12.0, "mood": ["nailed_it", "Nailed the Pitch", "bulb", 10.0, 6.0]},
	 "fail": {"perf": -6.0, "mood": ["flopped", "Pitch Flopped", "dots", -8.0, 4.0]},
	 "no": {"perf": 0.0}},
	{"id": "coworker", "text": "A coworker of %s's is swamped", "icon": "people",
	 "yes_label": "Lend a Hand", "no_label": "Mind Own Work",
	 "yes": {"perf": 4.0, "social": 0.15, "mood": ["helpful", "Helpful", "heart", 6.0, 4.0]},
	 "no": {"perf": -2.0}},
]
