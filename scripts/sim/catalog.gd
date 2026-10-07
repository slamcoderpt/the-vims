extends RefCounted
## Buy / Build / Decorate catalogue (Sims 3 style categories). Models come
## from PropLib (scripts/props/*) or, for build items (walls, floor tiles,
## rugs), are generated here as voxels ("proc").
## anim: ActionAnims animation (scripts/world/actors/action_anims.gd) with its
##       own keyframed pose, hand props and effects; "use": "inside" anims
##       (shower, bath) step into the object.
## use: "front" = sim stands in front of the item (+Z side) facing it,
##      "seat"  = sim sits/lies on the item facing its front.
## walk: true = sims walk over it (floors, rugs): no nav obstacle, may sit
##       under furniture. grid: snap step in metres (walls/floors use 1 m).

const PropLib := preload("res://scripts/props/prop_lib.gd")

## Category rows per mode: [id, label, icon].
const CATEGORIES := {
	"buy": [["seating", "Seating", "sofa"], ["surfaces", "Surfaces", "coffee"], ["beds", "Beds", "bed"],
		["kitchen", "Appliances", "cook"], ["plumbing", "Plumbing", "bath"], ["fun", "Fun & Hobbies", "gamepad"],
		["storage", "Storage", "book"]],
	"decorate": [["plants", "Plants", "plant"], ["lighting", "Lighting", "lantern"], ["decor", "Decorations", "star"],
		["rugs", "Rugs", "home"]],
	"build": [["walls", "Walls", "hammer"], ["floors", "Floor Tiles", "home"], ["garden", "Garden", "sprout"]],
}

const _SIT := {"id": "relax", "label": "Relax", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"energy": 0.08, "fun": 0.06}}

const ITEMS := [
	# ------------------------------------------------------------ Buy: seating
	{"id": "armchair", "label": "Armchair", "model": "armchair", "v": 1, "price": 350, "cat": "buy", "sub": "seating", "icon": "armchair", "use": "seat",
	 "actions": [
		{"id": "relax", "label": "Relax", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"energy": 0.1, "fun": 0.08}},
		{"id": "read_chair", "label": "Read a Book", "icon": "book_open", "minutes": 40.0, "pose": "sit_read", "needs": {"fun": 0.2}, "skill": "Logic", "who": ["adult", "child"]},
	]},
	{"id": "sofa", "label": "Sofa", "model": "sofa", "v": 1, "price": 650, "cat": "buy", "sub": "seating", "icon": "sofa", "use": "seat",
	 "actions": [
		{"id": "relax", "label": "Relax", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"energy": 0.12, "fun": 0.06}},
		{"id": "nap_sofa", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"energy": 0.35}},
	]},
	{"id": "chair", "label": "Dining Chair", "model": "chair", "v": 0, "price": 60, "cat": "buy", "sub": "seating", "icon": "armchair", "use": "seat",
	 "actions": [_SIT]},
	{"id": "office_chair", "label": "Desk Chair", "model": "office_chair", "v": 0, "price": 110, "cat": "buy", "sub": "seating", "icon": "armchair", "use": "seat",
	 "actions": [_SIT]},
	{"id": "beanbag", "label": "Beanbag", "model": "beanbag", "v": 0, "price": 75, "cat": "buy", "sub": "seating", "icon": "sofa", "use": "seat",
	 "actions": [{"id": "lounge", "label": "Lounge", "icon": "sofa", "minutes": 30.0, "pose": "sit", "needs": {"fun": 0.15, "energy": 0.05}}]},
	{"id": "pouf", "label": "Pouf", "model": "pouf", "v": 0, "price": 45, "cat": "buy", "sub": "seating", "icon": "sofa", "use": "seat",
	 "actions": [_SIT]},
	{"id": "stool", "label": "Stool", "model": "stool", "v": 0, "price": 30, "cat": "buy", "sub": "seating", "icon": "armchair", "use": "seat",
	 "actions": [_SIT]},
	# ------------------------------------------------------------ Buy: surfaces
	{"id": "coffee_table", "label": "Coffee Table", "model": "coffee_table", "v": 0, "price": 120, "cat": "buy", "sub": "surfaces", "icon": "coffee", "use": "front", "actions": []},
	{"id": "dining_table", "label": "Dining Table", "model": "dining_table", "v": 0, "price": 280, "cat": "buy", "sub": "surfaces", "icon": "plate", "use": "front",
	 "actions": [{"id": "eat", "label": "Eat", "icon": "plate", "minutes": 30.0, "pose": "sit", "anim": "eat", "needs": {"hunger": 0.3, "social": 0.05}}]},
	{"id": "desk", "label": "Writing Desk", "model": "desk", "v": 0, "price": 260, "cat": "buy", "sub": "surfaces", "icon": "pencil", "use": "front",
	 "actions": [
		{"id": "write", "label": "Write Novel", "icon": "pencil", "minutes": 60.0, "pose": "stand_type", "needs": {"fun": 0.08}, "skill": "Writing", "money": 60, "who": ["adult"]},
		{"id": "homework_desk", "label": "Do Homework", "icon": "book", "minutes": 45.0, "pose": "stand_read", "needs": {"fun": -0.03}, "skill": "Logic", "task": "Do Homework", "who": ["child"]},
	]},
	{"id": "side_table", "label": "Side Table", "model": "side_table", "v": 0, "price": 70, "cat": "buy", "sub": "surfaces", "icon": "coffee", "use": "front", "actions": []},
	{"id": "nightstand", "label": "Nightstand", "model": "nightstand", "v": 0, "price": 90, "cat": "buy", "sub": "surfaces", "icon": "lantern", "use": "front", "actions": []},
	{"id": "counter", "label": "Kitchen Counter", "model": "counter", "v": 0, "price": 220, "cat": "buy", "sub": "kitchen", "icon": "cook", "use": "front",
	 "actions": [{"id": "snack", "label": "Prepare Snack", "icon": "apple", "minutes": 10.0, "pose": "idle", "anim": "chop", "needs": {"hunger": 0.25}, "who": ["adult", "child"]}]},
	# ------------------------------------------------------------ Buy: beds
	{"id": "bed", "label": "Single Bed", "model": "bed", "v": 1, "price": 520, "cat": "buy", "sub": "beds", "icon": "bed", "use": "seat",
	 "actions": [
		{"id": "sleep", "label": "Sleep", "icon": "bed", "minutes": 480.0, "pose": "sleep", "needs": {"energy": 1.0}, "task": "Go to Sleep"},
		{"id": "nap", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"energy": 0.3}},
	]},
	{"id": "crib", "label": "Crib", "proc": "crib", "price": 250, "cat": "buy", "sub": "beds", "icon": "teddy", "use": "front",
	 "actions": [
		{"id": "feed_baby", "label": "Feed Baby", "icon": "milk", "minutes": 15.0, "pose": "idle", "anim": "feed_baby",
		 "needs": {"social": 0.05}, "baby_fx": {"hunger": 0.85}, "who": ["adult"]},
		{"id": "change_diaper", "label": "Change Diaper", "icon": "bath", "minutes": 10.0, "pose": "idle", "anim": "change_diaper",
		 "needs": {"hygiene": -0.03}, "baby_fx": {"hygiene": 0.9}, "who": ["adult"]},
		{"id": "rock_baby", "label": "Rock to Sleep", "icon": "zzz", "minutes": 20.0, "pose": "idle", "anim": "rock_baby",
		 "needs": {"social": 0.05}, "baby_fx": {"energy": 0.8}, "who": ["adult"]},
		{"id": "play_baby", "label": "Play with Baby", "icon": "teddy", "minutes": 15.0, "pose": "idle", "anim": "rock_baby",
		 "needs": {"fun": 0.15, "social": 0.08}, "baby_fx": {"fun": 0.6, "social": 0.6}, "who": ["adult", "child"]},
	]},
	{"id": "dog_bed", "label": "Dog Bed", "model": "dog_bed", "v": 0, "price": 70, "cat": "buy", "sub": "beds", "icon": "paw", "use": "seat",
	 "actions": [{"id": "nap", "label": "Nap", "icon": "zzz", "minutes": 60.0, "pose": "sleep", "needs": {"fun": 0.05, "energy": 0.3}, "who": ["dog"]}]},
	# ------------------------------------------------------------ Buy: appliances
	{"id": "fridge", "label": "Fridge", "model": "fridge", "v": 0, "price": 700, "cat": "buy", "sub": "kitchen", "icon": "milk", "use": "front",
	 "actions": [
		{"id": "grab_snack", "label": "Grab a Snack", "icon": "apple", "minutes": 8.0, "pose": "idle", "anim": "grab_snack", "needs": {"hunger": 0.3}},
		{"id": "cook_meal", "label": "Cook Meal", "icon": "cook", "minutes": 45.0, "pose": "idle", "anim": "cook", "needs": {"hunger": 0.75}, "skill": "Cooking", "who": ["adult"]},
	]},
	{"id": "stove", "label": "Stove", "model": "stove", "v": 0, "price": 450, "cat": "buy", "sub": "kitchen", "icon": "cook", "use": "front",
	 "actions": [{"id": "cook", "label": "Cook", "icon": "cook", "minutes": 45.0, "pose": "idle", "anim": "cook", "needs": {"hunger": 0.7}, "skill": "Cooking", "who": ["adult"]}]},
	{"id": "tv", "label": "TV Stand", "model": "tv", "v": 0, "price": 600, "cat": "buy", "sub": "fun", "icon": "tv", "use": "front",
	 "actions": [{"id": "watch", "label": "Watch TV", "icon": "tv", "minutes": 60.0, "pose": "idle", "anim": "watch_tv", "needs": {"fun": 0.25}}]},
	# ------------------------------------------------------------ Buy: plumbing
	{"id": "toilet", "label": "Toilet", "model": "toilet", "v": 0, "price": 300, "cat": "buy", "sub": "plumbing", "icon": "toilet", "use": "seat",
	 "actions": [{"id": "use_toilet", "label": "Use Toilet", "icon": "toilet", "minutes": 8.0, "pose": "sit", "anim": "toilet", "needs": {"bladder": 1.0}, "who": ["adult", "child"]}]},
	{"id": "bathtub", "label": "Bathtub", "model": "bathtub", "v": 0, "price": 800, "cat": "buy", "sub": "plumbing", "icon": "bath", "use": "seat",
	 "actions": [{"id": "bath", "label": "Take Bath", "icon": "bath", "minutes": 40.0, "pose": "sit", "anim": "bath", "needs": {"hygiene": 1.0, "fun": 0.1}}]},
	{"id": "shower", "label": "Shower", "model": "shower", "v": 0, "price": 650, "cat": "buy", "sub": "plumbing", "icon": "shower", "use": "front",
	 "actions": [{"id": "shower", "label": "Take Shower", "icon": "shower", "minutes": 20.0, "pose": "idle", "anim": "shower", "needs": {"hygiene": 0.9}, "who": ["adult", "child"]}]},
	{"id": "vanity", "label": "Vanity Sink", "model": "vanity", "v": 0, "price": 260, "cat": "buy", "sub": "plumbing", "icon": "tooth", "use": "front",
	 "actions": [{"id": "brush", "label": "Brush Teeth", "icon": "tooth", "minutes": 5.0, "pose": "brush_teeth", "needs": {"hygiene": 0.2}, "who": ["adult", "child"]}]},
	# ------------------------------------------------------------ Buy: fun & hobbies
	{"id": "piano", "label": "Piano", "model": "piano", "v": 0, "price": 1200, "cat": "buy", "sub": "fun", "icon": "piano", "use": "front",
	 "actions": [{"id": "practice", "label": "Practice", "icon": "music", "minutes": 45.0, "pose": "stand_type", "needs": {"fun": 0.15}, "skill": "Music", "task": "Build Skill", "who": ["adult", "child"]}]},
	{"id": "easel", "label": "Easel", "model": "easel", "v": 0, "price": 180, "cat": "buy", "sub": "fun", "icon": "palette", "use": "front",
	 "actions": [{"id": "paint", "label": "Paint", "icon": "palette", "minutes": 60.0, "pose": "paint", "needs": {"fun": 0.2}, "skill": "Creativity", "task": "Practice Creativity", "who": ["adult", "child"]}]},
	{"id": "guitar", "label": "Guitar", "model": "guitar", "v": 0, "price": 240, "cat": "buy", "sub": "fun", "icon": "guitar", "use": "front",
	 "actions": [{"id": "guitar", "label": "Play Guitar", "icon": "guitar", "minutes": 40.0, "pose": "idle", "anim": "guitar", "needs": {"fun": 0.25}, "skill": "Music", "who": ["adult", "child"]}]},
	{"id": "telescope", "label": "Telescope", "model": "telescope", "v": 0, "price": 380, "cat": "buy", "sub": "fun", "icon": "star", "use": "front",
	 "actions": [{"id": "stargaze", "label": "Stargaze", "icon": "star", "minutes": 40.0, "pose": "idle", "needs": {"fun": 0.2}, "skill": "Logic", "who": ["adult", "child"]}]},
	{"id": "toy_box", "label": "Toy Box", "model": "toy_box", "v": 0, "price": 90, "cat": "buy", "sub": "fun", "icon": "toys", "use": "front",
	 "actions": [{"id": "play_toys", "label": "Play", "icon": "toys", "minutes": 40.0, "pose": "play", "needs": {"fun": 0.3}, "who": ["child"]}]},
	{"id": "toy_blocks", "label": "Toy Blocks", "model": "toy_blocks", "v": 0, "price": 35, "cat": "buy", "sub": "fun", "icon": "toys", "use": "front",
	 "actions": [{"id": "build_blocks", "label": "Build a Tower", "icon": "toys", "minutes": 30.0, "pose": "sit_floor", "needs": {"fun": 0.25}, "skill": "Creativity", "who": ["child"]}]},
	{"id": "toy_robot", "label": "Toy Robot", "model": "toy_robot", "v": 0, "price": 55, "cat": "buy", "sub": "fun", "icon": "toys", "use": "front",
	 "actions": [{"id": "play_robot", "label": "Play with Robot", "icon": "toys", "minutes": 25.0, "pose": "play", "needs": {"fun": 0.3}, "skill": "Logic", "who": ["child"]}]},
	# ------------------------------------------------------------ Buy: storage
	{"id": "bookshelf", "label": "Bookshelf", "model": "bookshelf", "v": 0, "price": 240, "cat": "buy", "sub": "storage", "icon": "book", "use": "front",
	 "actions": [
		{"id": "study", "label": "Study", "icon": "book_open", "minutes": 45.0, "pose": "stand_read", "needs": {"fun": -0.02}, "skill": "Logic", "task": "Do Homework", "who": ["adult", "child"]},
		{"id": "browse_books", "label": "Browse Books", "icon": "book", "minutes": 15.0, "pose": "stand_read", "needs": {"fun": 0.12}, "who": ["adult", "child"]},
	]},
	{"id": "shelf_unit", "label": "Shelf Unit", "model": "shelf_unit", "v": 0, "price": 150, "cat": "buy", "sub": "storage", "icon": "book", "use": "front",
	 "actions": [{"id": "browse_books", "label": "Browse Books", "icon": "book", "minutes": 15.0, "pose": "stand_read", "needs": {"fun": 0.12}, "who": ["adult", "child"]}]},
	{"id": "dresser", "label": "Dresser", "model": "dresser", "v": 0, "price": 200, "cat": "buy", "sub": "storage", "icon": "home", "use": "front",
	 "actions": [{"id": "change", "label": "Change Outfit", "icon": "star", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.05, "hygiene": 0.05}, "who": ["adult", "child"]}]},
	{"id": "filing_cabinet", "label": "Filing Cabinet", "model": "filing_cabinet", "v": 0, "price": 95, "cat": "buy", "sub": "storage", "icon": "bill", "use": "front", "actions": []},
	# ------------------------------------------------------------ Decorate
	{"id": "plant_0", "label": "Leafy Plant", "model": "plant", "v": 0, "price": 25, "cat": "decorate", "sub": "plants", "icon": "plant", "use": "front", "actions": [
		{"id": "water", "label": "Water Plant", "icon": "plant", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.03}, "skill": "Gardening", "who": ["adult", "child"]},
	]},
	{"id": "plant_1", "label": "Fiddle Leaf Fig", "model": "plant", "v": 1, "price": 60, "cat": "decorate", "sub": "plants", "icon": "plant", "use": "front", "actions": [
		{"id": "water", "label": "Water Plant", "icon": "plant", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.03}, "skill": "Gardening", "who": ["adult", "child"]},
	]},
	{"id": "plant_2", "label": "Tall Monstera", "model": "plant", "v": 2, "price": 45, "cat": "decorate", "sub": "plants", "icon": "plant", "use": "front", "actions": [
		{"id": "water", "label": "Water Plant", "icon": "plant", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.03}, "skill": "Gardening", "who": ["adult", "child"]},
	]},
	{"id": "hanging_plant", "label": "Trailing Pothos", "model": "hanging_plant", "v": 0, "price": 40, "cat": "decorate", "sub": "plants", "icon": "plant", "use": "front", "actions": []},
	{"id": "lamp_floor", "label": "Floor Lamp", "model": "lamp_floor", "v": 0, "price": 85, "cat": "decorate", "sub": "lighting", "icon": "lantern", "use": "front", "light": true, "actions": []},
	{"id": "lamp_table", "label": "Table Lamp", "model": "lamp_table", "v": 0, "price": 40, "cat": "decorate", "sub": "lighting", "icon": "lantern", "use": "front", "light": true, "actions": []},
	{"id": "rocket_lamp", "label": "Rocket Night Light", "model": "rocket_lamp", "v": 0, "price": 30, "cat": "decorate", "sub": "lighting", "icon": "moon", "use": "front", "light": true, "actions": []},
	{"id": "lantern", "label": "Garden Lantern", "model": "lantern", "v": 0, "price": 35, "cat": "decorate", "sub": "lighting", "icon": "lantern", "use": "front", "light": true, "actions": []},
	{"id": "globe", "label": "Globe", "model": "globe", "v": 0, "price": 30, "cat": "decorate", "sub": "decor", "icon": "star", "use": "front", "actions": [
		{"id": "spin_globe", "label": "Spin Globe", "icon": "star", "minutes": 5.0, "pose": "idle", "needs": {"fun": 0.08}, "skill": "Logic", "who": ["adult", "child"]},
	]},
	{"id": "plush", "label": "Plush Toy", "model": "plush", "v": 0, "price": 20, "cat": "decorate", "sub": "decor", "icon": "teddy", "use": "front", "actions": [
		{"id": "cuddle", "label": "Cuddle", "icon": "heart", "minutes": 10.0, "pose": "talk", "needs": {"fun": 0.1, "social": 0.05}, "who": ["child"]},
	]},
	{"id": "soccer_ball", "label": "Soccer Ball", "model": "soccer_ball", "v": 0, "price": 15, "cat": "decorate", "sub": "decor", "icon": "ball", "use": "front", "actions": [
		{"id": "fetch", "label": "Play Fetch", "icon": "ball", "minutes": 20.0, "pose": "play", "needs": {"fun": 0.3}, "task": "Play with Dog"},
	]},
	{"id": "trophy", "label": "Trophy", "model": "trophy", "v": 0, "price": 50, "cat": "decorate", "sub": "decor", "icon": "trophy", "use": "front", "actions": []},
	{"id": "basket", "label": "Wicker Basket", "model": "basket", "v": 0, "price": 25, "cat": "decorate", "sub": "decor", "icon": "home", "use": "front", "actions": []},
	{"id": "rug_check", "label": "Blue Check Rug", "proc": "rug", "style": "check_blue", "w": 32, "d": 24, "price": 90, "cat": "decorate", "sub": "rugs", "icon": "home", "walk": true, "actions": []},
	{"id": "rug_kilim", "label": "Kilim Rug", "proc": "rug", "style": "red_kilim", "w": 32, "d": 20, "price": 120, "cat": "decorate", "sub": "rugs", "icon": "home", "walk": true, "actions": []},
	{"id": "rug_round", "label": "Round Rug", "proc": "rug", "style": "round_cream", "w": 26, "d": 26, "price": 80, "cat": "decorate", "sub": "rugs", "icon": "home", "walk": true, "actions": []},
	{"id": "rug_patch", "label": "Patchwork Rug", "proc": "rug", "style": "patch_pink", "w": 28, "d": 20, "price": 75, "cat": "decorate", "sub": "rugs", "icon": "home", "walk": true, "actions": []},
	# ------------------------------------------------------------ Build: walls, floors, garden
	{"id": "wall_cream", "label": "Wall · Cream Panel", "proc": "wall", "style": "cream", "price": 40, "cat": "build", "sub": "walls", "icon": "hammer", "grid": 0.5, "actions": []},
	{"id": "wall_blue", "label": "Wall · Blue Panel", "proc": "wall", "style": "blue", "price": 40, "cat": "build", "sub": "walls", "icon": "hammer", "grid": 0.5, "actions": []},
	{"id": "wall_brick", "label": "Wall · Brick", "proc": "wall", "style": "brick", "price": 55, "cat": "build", "sub": "walls", "icon": "hammer", "grid": 0.5, "actions": []},
	{"id": "wall_wood", "label": "Wall · Timber", "proc": "wall", "style": "wood", "price": 45, "cat": "build", "sub": "walls", "icon": "hammer", "grid": 0.5, "actions": []},
	{"id": "fence", "label": "Picket Fence", "model": "fence", "v": 0, "price": 25, "cat": "build", "sub": "walls", "icon": "hammer", "grid": 0.5, "actions": []},
	{"id": "floor_oak", "label": "Floor · Oak Planks", "proc": "floor", "style": "oak", "price": 10, "cat": "build", "sub": "floors", "icon": "home", "walk": true, "grid": 1.0, "actions": []},
	{"id": "floor_check", "label": "Floor · Checker Tile", "proc": "floor", "style": "check", "price": 12, "cat": "build", "sub": "floors", "icon": "home", "walk": true, "grid": 1.0, "actions": []},
	{"id": "floor_terra", "label": "Floor · Terracotta", "proc": "floor", "style": "terra", "price": 12, "cat": "build", "sub": "floors", "icon": "home", "walk": true, "grid": 1.0, "actions": []},
	{"id": "floor_blue", "label": "Floor · Blue Mosaic", "proc": "floor", "style": "mosaic", "price": 15, "cat": "build", "sub": "floors", "icon": "home", "walk": true, "grid": 1.0, "actions": []},
	{"id": "floor_grass", "label": "Floor · Lawn", "proc": "floor", "style": "grass", "price": 5, "cat": "build", "sub": "floors", "icon": "sprout", "walk": true, "grid": 1.0, "actions": []},
	{"id": "bush", "label": "Round Shrub", "model": "bush", "v": 0, "price": 45, "cat": "build", "sub": "garden", "icon": "leaf", "use": "front", "actions": [
		{"id": "prune", "label": "Prune", "icon": "leaf", "minutes": 15.0, "pose": "idle", "needs": {"fun": 0.08}, "skill": "Gardening", "who": ["adult", "child"]},
	]},
	{"id": "hedge", "label": "Hedge", "model": "hedge", "v": 0, "price": 60, "cat": "build", "sub": "garden", "icon": "leaf", "use": "front", "actions": []},
	{"id": "flower_bed", "label": "Flower Bed", "model": "flower_bed", "v": 0, "price": 70, "cat": "build", "sub": "garden", "icon": "blossom", "use": "front", "actions": [
		{"id": "tend", "label": "Tend Flowers", "icon": "blossom", "minutes": 30.0, "pose": "idle", "needs": {"fun": 0.15}, "skill": "Gardening", "who": ["adult", "child"]},
	]},
	# ------------------------------------------------------------ Life (not sold; placed by gameplay)
	{"id": "birthday_cake", "label": "Birthday Cake", "proc": "cake", "price": 0, "cat": "life", "sub": "life", "icon": "cake", "use": "front",
	 "actions": [{"id": "eat_cake", "label": "Have a Slice", "icon": "cake", "minutes": 10.0, "pose": "idle", "anim": "snack_eat", "needs": {"hunger": 0.3, "fun": 0.1}, "who": ["adult", "child"]}]},
	{"id": "grave", "label": "Grave", "proc": "grave", "price": 0, "cat": "life", "sub": "life", "icon": "dots", "use": "front",
	 "actions": [
		{"id": "mourn", "label": "Mourn", "icon": "dots", "minutes": 20.0, "pose": "idle", "anim": "mourn", "needs": {"social": 0.05}, "who": ["adult", "child"]},
		{"id": "flowers", "label": "Leave Flowers", "icon": "blossom", "minutes": 6.0, "pose": "idle", "anim": "mourn", "needs": {"fun": 0.02}, "who": ["adult", "child"]},
	]},
	{"id": "tree", "label": "Maple Tree", "model": "tree", "v": 0, "price": 180, "cat": "build", "sub": "garden", "icon": "leaf", "use": "front", "actions": []},
]

static var _proc_models := {}   # id -> VoxelBuilder
static var _proc_meshes := {}   # id -> ArrayMesh


static func by_cat(cat: String, sub := "") -> Array:
	var out: Array = []
	for it in ITEMS:
		if it.cat == cat and (sub == "" or it.get("sub", "") == sub):
			out.append(it)
	return out


static func get_item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


## Category rows for a mode's catalogue menu (Buy / Decorate / Build).
static func category_rows(cat: String) -> Array:
	var rows: Array = []
	for c in CATEGORIES.get(cat, []):
		var n := by_cat(cat, c[0]).size()
		if n == 0:
			continue
		rows.append({"id": "cat:" + c[0], "label": "%s  (%d)" % [c[1], n], "icon": c[2], "subcat": c[0]})
	return rows


## Item rows for the HUD action menu (optionally one sub-category).
static func menu_rows(cat: String, sub := "") -> Array:
	var rows: Array = []
	for it in by_cat(cat, sub):
		rows.append({"id": "buy:" + it.id, "label": "%s  $%d" % [it.label, it.price], "icon": it.icon, "item": it.id})
	if sub != "":
		rows.append({"id": "back", "label": "Back", "icon": "dots", "back": cat})
	return rows


# =================================================================== geometry

## Voxel size (m) an item is authored in.
static func unit(item: Dictionary) -> float:
	if item.has("proc"):
		return 0.0625
	return PropLib.scale_of(item.model)


## Size in voxels (unrotated).
static func size_of(item: Dictionary) -> Vector3i:
	if item.has("proc"):
		var m := _proc(item)
		return _proc_size(item, m)
	return PropLib.size_of(item.model, item.get("v", 0))


static func rotated_size(item: Dictionary, rot: int) -> Vector3i:
	var s := size_of(item)
	return Vector3i(s.z, s.y, s.x) if rot % 2 == 1 else s


## A MeshInstance3D of the item centred on its footprint (shares meshes).
static func instance(item: Dictionary, shadows := true) -> MeshInstance3D:
	if not item.has("proc"):
		return PropLib.instance(item.model, item.get("v", 0), shadows)
	var mi := MeshInstance3D.new()
	mi.name = str(item.id).capitalize().replace(" ", "")
	if not _proc_meshes.has(item.id):
		var m := _proc(item)
		var s := _proc_size(item, m)
		_proc_meshes[item.id] = m.build(0.0625, Vector3(s.x * 0.5, 0, s.z * 0.5))
	mi.mesh = _proc_meshes[item.id]
	var flat: bool = item.proc in ["floor", "rug"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not flat else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _proc_size(item: Dictionary, _m: VoxelBuilder) -> Vector3i:
	match item.proc:
		"wall": return Vector3i(16, 18, 3)
		"floor": return Vector3i(16, 1, 16)
		"rug": return Vector3i(int(item.w), 1, int(item.d))
		"crib": return Vector3i(18, 15, 11)
		"cake": return Vector3i(9, 19, 9)
		"grave": return Vector3i(10, 14, 12)
	return Vector3i(4, 4, 4)


static func _proc(item: Dictionary) -> VoxelBuilder:
	if _proc_models.has(item.id):
		return _proc_models[item.id]
	var vb := VoxelBuilder.new()
	match item.proc:
		"rug":
			PropLib.rug(vb, Vector3i.ZERO, int(item.w), int(item.d), item.style)
		"wall":
			_wall(vb, item.style)
		"floor":
			_floor(vb, item.style)
		"crib":
			_crib(vb)
		"cake":
			_cake(vb)
		"grave":
			_grave(vb)
	_proc_models[item.id] = vb
	return vb


## A 1 m long cutaway-height wall section (1.1 m, like the "walls down" view
## of the reference shots): skirting, wainscot / brick courses and a cap.
static func _wall(vb: VoxelBuilder, style: String) -> void:
	var base: Color
	var alt: Color
	match style:
		"blue":
			base = Color("4f63a6"); alt = Color("5b70b4")
		"brick":
			base = Color("b65a3e"); alt = Color("9c4a33")
		"wood":
			base = Color("a86f42"); alt = Color("8f5c36")
		_:
			base = Color("f3e8d6"); alt = Color("e8dcc6")
	for x in 16:
		for y in 18:
			for z in 3:
				var h := VoxelBuilder.hash3(Vector3i(x, y, z))
				var c := base
				match style:
					"brick":
						var row := y / 2
						var off := 4 if row % 2 == 1 else 0
						c = Color("e9dccb") if (y % 2 == 1 or (x + off) % 8 == 0) else (base if h > 0.4 else alt)
					"wood":
						c = alt if x % 4 == 0 else base
					_:
						c = alt if (x % 8 == 0 or y == 9) else base
				if y == 0:
					c = Color("7a4e2e")
				elif y >= 16:
					c = Color("f6f1e7") if style != "wood" else Color("6e4528")
				var f := 0.95 + h * 0.08
				vb.set_v(Vector3i(x, y, z), Color(c.r * f, c.g * f, c.b * f))


## A 1 x 1 m floor tile.
static func _floor(vb: VoxelBuilder, style: String) -> void:
	for x in 16:
		for z in 16:
			var h := VoxelBuilder.hash3(Vector3i(x, 3, z))
			var c: Color
			match style:
				"check":
					c = Color("f1ece2") if (x / 4 + z / 4) % 2 == 0 else Color("3e4a5c")
				"terra":
					c = Color("c8704a") if (x % 8 != 0 and z % 8 != 0) else Color("e6cfb0")
					if h > 0.85:
						c = Color("b3603e")
				"mosaic":
					c = [Color("5d7fc0"), Color("8fb0e2"), Color("dfe9f6"), Color("4a68a6")][(x / 2 + (z / 2) * 3) % 4]
				"grass":
					c = Color("6fae4a") if h > 0.3 else Color("5f9c3e")
					if h > 0.93:
						c = Color("f0e070")
				_:
					var plank := z / 4
					c = Color("c48a52") if plank % 2 == 0 else Color("b57b46")
					if (x + plank * 5) % 16 == 0 or z % 4 == 3 and h > 0.6:
						c = Color("8f5a30")
			var f := 0.94 + h * 0.1
			vb.set_v(Vector3i(x, 0, z), Color(c.r * f, c.g * f, c.b * f))



static func _shade(c: Color, p: Vector3i, amt := 0.08) -> Color:
	var f := 1.0 - amt * 0.5 + VoxelBuilder.hash3(p) * amt
	return Color(c.r * f, c.g * f, c.b * f)


## A wooden crib (1.1 x 0.7 m): spindle sides, tall end boards with a heart
## cut-out, a white mattress with a pastel quilt and pillow, and a mobile.
static func _crib(vb: VoxelBuilder) -> void:
	var wood := Color("e9d3b0")
	var wood_dk := Color("c9a87c")
	var W := 18
	var D := 11
	for x in W:
		for z in D:
			var p := Vector3i(x, 0, z)
			var end := x == 0 or x == W - 1
			var side := z == 0 or z == D - 1
			if end:
				var top := 13 if x == 0 else 11
				for y in range(0, top + 1):
					# End boards: legs at the corners, a panel above the mattress.
					if (z == 0 or z == D - 1) or y >= 4:
						var heart := x == 0 and y >= 8 and y <= 10 and absi(z - 5) <= (2 if y > 8 else 1) and not (y == 10 and z == 5)
						if not heart:
							vb.set_v(Vector3i(x, y, z), _shade(wood if y < top else wood_dk, Vector3i(x, y, z)))
			elif side:
				vb.set_v(Vector3i(x, 4, z), _shade(wood_dk, p))      # bottom rail
				vb.set_v(Vector3i(x, 11, z), _shade(wood, p))        # top rail
				if x % 2 == 0:
					for y in range(5, 11):
						vb.set_v(Vector3i(x, y, z), _shade(wood, Vector3i(x, y, z), 0.05))
			else:
				vb.set_v(Vector3i(x, 4, z), _shade(wood_dk, p))      # base board
				vb.set_v(Vector3i(x, 5, z), _shade(Color("f7f5ef"), Vector3i(x, 5, z), 0.04))   # mattress
				# Quilt over the foot half, a pillow at the head.
				if x >= 8:
					var q := Color("a9d4f2") if (x / 2 + z / 2) % 2 == 0 else Color("fbe2a6")
					vb.set_v(Vector3i(x, 6, z), _shade(q, Vector3i(x, 6, z), 0.05))
				elif x >= 2 and x <= 4 and z >= 3 and z <= 7:
					vb.set_v(Vector3i(x, 6, z), Color("ffffff"))
	# Mobile on an arm over the head end.
	for y in range(12, 15):
		vb.set_v(Vector3i(1, y, 5), wood_dk)
	for x in range(1, 7):
		vb.set_v(Vector3i(x, 14, 5), wood_dk)
	var toys := [Color("f28b9b"), Color("8fd18a"), Color("f6d35b")]
	for k in 3:
		var tx := 3 + k * 2 - 1
		vb.set_v(Vector3i(tx, 13, 5 + (k - 1) * 2), toys[k])
		vb.set_v(Vector3i(tx, 12, 5 + (k - 1) * 2), toys[k].darkened(0.1))


## A birthday cake on a little round table, candles lit (glowing flames).
static func _cake(vb: VoxelBuilder) -> void:
	var c := Vector2(4, 4)
	var cloth := Color("fbf6ee")
	var leg := Color("8a5a36")
	for x in 9:
		for z in 9:
			var d := Vector2(x, z).distance_to(c)
			if d <= 4.3:
				vb.set_v(Vector3i(x, 11, z), _shade(cloth, Vector3i(x, 11, z), 0.04))
				if d > 3.6:
					vb.set_v(Vector3i(x, 10, z), _shade(Color("f4c6d3"), Vector3i(x, 10, z), 0.04))   # skirt
			if d <= 3.2:
				for y in range(12, 14):
					vb.set_v(Vector3i(x, y, z), _shade(Color("fde7c4"), Vector3i(x, y, z), 0.05))      # sponge
				vb.set_v(Vector3i(x, 14, z), _shade(Color("f7a3bb"), Vector3i(x, 14, z), 0.05))        # jam layer
				vb.set_v(Vector3i(x, 15, z), _shade(Color("fff6f8"), Vector3i(x, 15, z), 0.03))        # icing
				if d > 2.6 and (x + z) % 2 == 0:
					vb.set_v(Vector3i(x, 16, z), Color("f28bab"))   # piped rim
	for y in range(0, 11):
		vb.set_v(Vector3i(4, y, 4), leg)
	for x in range(2, 7):
		vb.set_v(Vector3i(x, 0, 4), leg)
	for z in range(2, 7):
		vb.set_v(Vector3i(4, 0, z), leg)
	var cols := [Color("7cc4f2"), Color("f6d35b"), Color("9be08a")]
	var spots := [Vector3i(3, 16, 4), Vector3i(5, 16, 3), Vector3i(5, 16, 5)]
	for k in 3:
		var sp: Vector3i = spots[k]
		vb.set_v(sp, cols[k])
		vb.set_v(sp + Vector3i(0, 1, 0), cols[k])
		vb.set_v(sp + Vector3i(0, 2, 0), Color(1.0, 0.75, 0.3), true)   # flame


## A rounded headstone with a carved cross, a grassy mound and flowers.
static func _grave(vb: VoxelBuilder) -> void:
	var stone := Color("a7aab0")
	for x in 10:
		for y in range(0, 14):
			var dx := x - 4.5
			var top := 10.0 + sqrt(maxf(0.0, 20.25 - dx * dx)) * 0.75
			if y > top:
				continue
			for z in range(0, 2):
				var c := _shade(stone, Vector3i(x, y, z), 0.12)
				# carved cross on the front face
				if z == 1 and ((x == 4 or x == 5) and y >= 5 and y <= 11 or (y == 9 and x >= 3 and x <= 6)):
					c = c.darkened(0.25)
				vb.set_v(Vector3i(x, y, z), c)
	for x in range(1, 9):
		for z in range(2, 12):
			var g := Color("6f9a46") if VoxelBuilder.hash3(Vector3i(x, 1, z)) > 0.3 else Color("5e8a3a")
			vb.set_v(Vector3i(x, 0, z), g)
			if x >= 2 and x <= 7 and z >= 3 and z <= 10:
				vb.set_v(Vector3i(x, 1, z), _shade(Color("7b5a3c"), Vector3i(x, 1, z), 0.1))
	var fl := [Color("f2d04b"), Color("f28bab"), Color("ffffff"), Color("b58bf2")]
	for k in 4:
		var fx := 2 + k
		vb.set_v(Vector3i(fx + (k % 2), 1, 2), Color("4f8a3a"))
		vb.set_v(Vector3i(fx + (k % 2), 2, 2), fl[k])
