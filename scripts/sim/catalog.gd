extends RefCounted
## Buy / Decorate catalogue. Models come from PropLib (scripts/props/*).
## use: "front" = sim stands in front of the item (+Z side) facing it,
##      "seat"  = sim sits/lies on the item facing its front.

const ITEMS := [
	# --- Buy: furniture
	{"id": "armchair", "label": "Armchair", "model": "armchair", "v": 1, "price": 350, "cat": "buy", "icon": "armchair", "use": "seat",
	 "actions": [
		{"id": "relax", "label": "Relax", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"energy": 0.1, "fun": 0.08}},
		{"id": "read_chair", "label": "Read a Book", "icon": "book_open", "minutes": 40.0, "pose": "sit_read", "needs": {"fun": 0.2}, "skill": "Logic", "who": ["adult", "child"]},
	]},
	{"id": "sofa", "label": "Sofa", "model": "sofa", "v": 1, "price": 650, "cat": "buy", "icon": "sofa", "use": "seat",
	 "actions": [
		{"id": "relax", "label": "Relax", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"energy": 0.12, "fun": 0.06}},
		{"id": "nap_sofa", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"energy": 0.35}},
	]},
	{"id": "bookshelf", "label": "Bookshelf", "model": "bookshelf", "v": 0, "price": 240, "cat": "buy", "icon": "book", "use": "front",
	 "actions": [
		{"id": "study", "label": "Study", "icon": "book_open", "minutes": 45.0, "pose": "stand_read", "needs": {"fun": -0.02}, "skill": "Logic", "task": "Do Homework", "who": ["adult", "child"]},
		{"id": "browse_books", "label": "Browse Books", "icon": "book", "minutes": 15.0, "pose": "stand_read", "needs": {"fun": 0.12}, "who": ["adult", "child"]},
	]},
	{"id": "easel", "label": "Easel", "model": "easel", "v": 0, "price": 180, "cat": "buy", "icon": "palette", "use": "front",
	 "actions": [
		{"id": "paint", "label": "Paint", "icon": "palette", "minutes": 60.0, "pose": "paint", "needs": {"fun": 0.2}, "skill": "Creativity", "task": "Practice Creativity", "who": ["adult", "child"]},
	]},
	{"id": "piano", "label": "Piano", "model": "piano", "v": 0, "price": 1200, "cat": "buy", "icon": "piano", "use": "front",
	 "actions": [
		{"id": "practice", "label": "Practice", "icon": "music", "minutes": 45.0, "pose": "stand_type", "needs": {"fun": 0.15}, "skill": "Music", "task": "Build Skill", "who": ["adult", "child"]},
	]},
	{"id": "tv", "label": "TV Stand", "model": "tv", "v": 0, "price": 600, "cat": "buy", "icon": "tv", "use": "front",
	 "actions": [
		{"id": "watch", "label": "Watch TV", "icon": "tv", "minutes": 60.0, "pose": "idle", "needs": {"fun": 0.25}},
	]},
	{"id": "bed", "label": "Single Bed", "model": "bed", "v": 1, "price": 520, "cat": "buy", "icon": "bed", "use": "seat",
	 "actions": [
		{"id": "sleep", "label": "Sleep", "icon": "bed", "minutes": 480.0, "pose": "sleep", "needs": {"energy": 1.0}, "task": "Go to Sleep"},
		{"id": "nap", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"energy": 0.3}},
	]},
	{"id": "toy_box", "label": "Toy Box", "model": "toy_box", "v": 0, "price": 90, "cat": "buy", "icon": "toys", "use": "front",
	 "actions": [
		{"id": "play_toys", "label": "Play", "icon": "toys", "minutes": 40.0, "pose": "play", "needs": {"fun": 0.3}, "who": ["child"]},
	]},
	{"id": "dog_bed", "label": "Dog Bed", "model": "dog_bed", "v": 0, "price": 70, "cat": "buy", "icon": "paw", "use": "seat",
	 "actions": [
		{"id": "nap", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"fun": 0.05}, "who": ["dog"]},
	]},
	{"id": "coffee_table", "label": "Coffee Table", "model": "coffee_table", "v": 0, "price": 120, "cat": "buy", "icon": "coffee", "use": "front", "actions": []},
	# --- Decorate
	{"id": "plant_0", "label": "Leafy Plant", "model": "plant", "v": 0, "price": 25, "cat": "decorate", "icon": "plant", "use": "front", "actions": [
		{"id": "water", "label": "Water Plant", "icon": "plant", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.03}, "who": ["adult", "child"]},
	]},
	{"id": "plant_2", "label": "Tall Monstera", "model": "plant", "v": 2, "price": 45, "cat": "decorate", "icon": "plant", "use": "front", "actions": [
		{"id": "water", "label": "Water Plant", "icon": "plant", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.03}, "who": ["adult", "child"]},
	]},
	{"id": "lamp_floor", "label": "Floor Lamp", "model": "lamp_floor", "v": 0, "price": 85, "cat": "decorate", "icon": "lantern", "use": "front", "light": true, "actions": []},
	{"id": "globe", "label": "Globe", "model": "globe", "v": 0, "price": 30, "cat": "decorate", "icon": "star", "use": "front", "actions": [
		{"id": "spin_globe", "label": "Spin Globe", "icon": "star", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.08}, "skill": "Logic", "who": ["adult", "child"]},
	]},
	{"id": "plush", "label": "Plush Toy", "model": "plush", "v": 0, "price": 20, "cat": "decorate", "icon": "teddy", "use": "front", "actions": [
		{"id": "cuddle", "label": "Cuddle", "icon": "heart", "minutes": 10.0, "pose": "talk", "needs": {"fun": 0.1, "social": 0.05}, "who": ["child"]},
	]},
	{"id": "soccer_ball", "label": "Soccer Ball", "model": "soccer_ball", "v": 0, "price": 15, "cat": "decorate", "icon": "ball", "use": "front", "actions": [
		{"id": "fetch", "label": "Play Fetch", "icon": "ball", "minutes": 20.0, "pose": "play", "needs": {"fun": 0.3}, "task": "Play with Dog"},
	]},
]


static func by_cat(cat: String) -> Array:
	var out: Array = []
	for it in ITEMS:
		if it.cat == cat:
			out.append(it)
	return out


static func get_item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


## Rows for the HUD action menu.
static func menu_rows(cat: String) -> Array:
	var rows: Array = []
	for it in by_cat(cat):
		rows.append({"id": "buy:" + it.id, "label": "%s  $%d" % [it.label, it.price], "icon": it.icon, "item": it.id})
	return rows
