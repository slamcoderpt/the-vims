extends RefCounted
## Screenshot presets, one per reference image in refs/. Each preset stages a
## location, time of day and camera so our render can sit next to the reference.
## camera: target (Vector3), yaw/pitch in degrees, distance (m), fov (deg).

const PRESETS := {
	"home_day": {
		"ref": "refs/ref1_home_office_day.png",
		"location": "home", "day": 1, "hour": 14, "minute": 16, "season": 1,
		"camera": {"target": Vector3(-5.0, 3.6, -1.9), "yaw": 20.0, "pitch": 35.0, "distance": 8.6, "fov": 40.0},
		"tasks": [
			{"title": "Answer Emails", "icon": "laptop", "done": true},
			{"title": "Practice Creativity", "icon": "palette"},
			{"title": "Do Homework", "icon": "book"},
			{"title": "Build Skill", "icon": "chart"},
			{"title": "Pay Bills", "icon": "bill"},
			{"title": "Play with Dog", "icon": "paw"},
		],
	},
	"festival": {
		"ref": "refs/ref2_autumn_festival.png",
		"location": "festival", "day": 5, "hour": 16, "minute": 42, "season": 2,
		"camera": {"target": Vector3(-1.25, 0.9, -2.5), "yaw": 12.0, "pitch": 34.0, "distance": 10.5, "fov": 40.0},
		"tasks": [
			{"title": "Buy Festival Snack", "icon": "apple", "done": true},
			{"title": "Meet 3 Neighbors", "icon": "chat"},
			{"title": "Play Festival Game", "icon": "target"},
			{"title": "Take Family Photo", "icon": "camera"},
			{"title": "Win Prize", "icon": "trophy"},
			{"title": "Return Home", "icon": "home"},
		],
	},
	"home_night": {
		"ref": "refs/ref3_home_night_cutaway.png",
		"location": "home", "day": 0, "hour": 21, "minute": 18, "season": 1,
		"camera": {"target": Vector3(4.3, 3.4, -1.7), "yaw": 22.0, "pitch": 32.0, "distance": 17.0, "fov": 37.0},
		"tasks": [
			{"title": "Take Bath", "icon": "bath"},
			{"title": "Brush Teeth", "icon": "brush", "done": true},
			{"title": "Read Story", "icon": "book", "done": true},
			{"title": "Go to Sleep", "icon": "bed"},
			{"title": "Feed Dog", "icon": "paw"},
			{"title": "Tidy Toys", "icon": "toys"},
		],
	},
	"bbq": {
		"ref": "refs/ref4_backyard_bbq_sunset.png",
		"location": "backyard", "day": 0, "hour": 19, "minute": 36, "season": 1,
		"camera": {"target": Vector3(0.95, 1.2, -0.3), "yaw": -14.0, "pitch": 18.0, "distance": 8.4, "fov": 48.0},
		"tasks": [
			{"title": "Grill Dinner", "icon": "burger", "done": true},
			{"title": "Talk to Neighbors", "icon": "people"},
			{"title": "Make a New Friend", "icon": "heart"},
			{"title": "Serve Food", "icon": "plate"},
			{"title": "Take Photos", "icon": "camera"},
			{"title": "Clean Up After Party", "icon": "broom"},
		],
	},
	"market": {
		"ref": "refs/ref5_grocery_market.png",
		"location": "market", "day": 0, "hour": 8, "minute": 24, "season": 1,
		"camera": {"target": Vector3(0.3, 0.6, -1.7), "yaw": 15.0, "pitch": 35.0, "distance": 12.5, "fov": 40.0},
		"tasks": [
			{"title": "Buy Groceries", "icon": "cart", "done": true},
			{"title": "Meet a Neighbor", "icon": "people"},
			{"title": "Pay at Checkout", "icon": "register"},
			{"title": "Take Photos Around Town", "icon": "camera"},
			{"title": "Return Home", "icon": "home"},
		],
	},
}
