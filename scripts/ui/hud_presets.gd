extends RefCounted
## HUD state for each screenshot preset (bubbles, chips, menus, needs) so the
## render reads like the matching reference. Bubbles anchor to actors found by
## `who` (household name or NPC key passed to location.get_actor); when the
## actor is missing they fall back to `at`, the bubble's top-left position in
## the reference image (1672x941).

const BLUE := Color("4a9cf0")
const GREEN := Color("55c449")

const SPECS := {
	"home_day": {
		"show_season": false,
		"plumbob": Vector2(655, 240),
		"needs": {
			"Jack": {"fun": 0.82, "hunger": 0.38, "hygiene": 0.55, "energy": 0.45, "social": 0.3},
			"Lily": {"fun": 0.72, "hunger": 0.5, "hygiene": 0.58, "energy": 0.62},
			"Maya": {"fun": 0.72, "hunger": 0.62, "energy": 0.55},
			"Biscuit": {"fun": 0.8, "hunger": 0.45},
		},
		"bubbles": [
			{"who": "Jack", "kind": "action", "text": "Work", "icon": "laptop", "progress": 0.32, "color": BLUE, "at": Vector2(487, 193), "selected_side": true},
			{"who": "Lily", "kind": "action", "text": "Paint", "icon": "palette", "progress": 0.48, "color": GREEN, "at": Vector2(962, 143)},
			{"who": "Lily", "kind": "skill", "text": "Creativity", "icon": "bulb", "at": Vector2(1082, 213)},
			{"who": "Biscuit", "kind": "action", "text": "Play", "icon": "paw", "progress": 0.6, "color": GREEN, "at": Vector2(738, 503)},
			{"who": "Maya", "kind": "action", "text": "Practice", "icon": "music", "progress": 0.55, "color": BLUE, "at": Vector2(1205, 465)},
			{"who": "Maya", "kind": "skill", "text": "Music", "icon": "arrow_up", "at": Vector2(1325, 537)},
		],
	},
	"home_night": {
		"bubbles": [
			{"who": "Jack", "kind": "action", "text": "Read Story", "icon": "book_open", "at": Vector2(545, 307), "selected_side": true},
			{"who": "Maya", "kind": "action", "text": "Brush Teeth", "icon": "brush", "at": Vector2(1414, 450)},
			{"who": "Biscuit", "kind": "emote", "icon": "zzz", "at": Vector2(866, 650)},
		],
	},
	"festival": {
		"show_season": true,
		"bubbles": [
			{"who": "Jack", "kind": "action", "text": "Buy Snack", "icon": "cart", "at": Vector2(352, 405), "selected_side": true},
			{"who": "Lily", "kind": "action", "text": "Play Game", "icon": "target", "at": Vector2(830, 437)},
			{"who": "Maya", "kind": "speech", "text": "I got a prize!", "icon": "gift", "at": Vector2(1272, 535)},
		],
	},
	"bbq": {
		"plumbob": Vector2(412, 330),
		"bubbles": [
			{"who": "Jack", "kind": "speech", "text": "Smells great!", "icon": "burger", "at": Vector2(443, 313)},
			{"who": "neighbor_1", "kind": "speech", "text": "So nice to be here!", "icon": "smile", "at": Vector2(941, 241)},
			{"who": "neighbor_2", "kind": "speech", "text": "Great food!", "icon": "burger", "at": Vector2(1150, 273)},
			{"who": "Lily", "kind": "emote", "icon": "heart", "at": Vector2(680, 495)},
			{"who": "neighbor_3", "kind": "emote", "icon": "heart", "at": Vector2(822, 432)},
			{"who": "neighbor_4", "kind": "emote", "icon": "heart", "at": Vector2(1048, 468)},
			{"who": "Biscuit", "kind": "emote", "icon": "paw", "at": Vector2(1238, 670)},
			{"who": "neighbor_5", "kind": "emote", "icon": "dots", "at": Vector2(1500, 470)},
		],
		"menu": {
			"title": "Grill", "at": Vector2(355, 573),
			"actions": [
				{"id": "cook", "label": "Cook Food", "icon": "cook"},
				{"id": "serve", "label": "Serve Food", "icon": "plate"},
				{"id": "invite", "label": "Invite to Eat", "icon": "people"},
				{"id": "give", "label": "Give Food", "icon": "gift"},
			],
		},
	},
	"market": {
		"plumbob": Vector2(738, 340),
		"bubbles": [
			{"who": "Lily", "kind": "action", "text": "Buy", "sub": "$ 1.20", "icon": "cart", "at": Vector2(358, 400)},
			{"who": "Maya", "kind": "action", "text": "Compare", "icon": "scale", "at": Vector2(868, 462)},
			{"who": "cashier", "kind": "action", "text": "Chat", "icon": "chat", "at": Vector2(1325, 428)},
		],
		"list": {
			"title": "Shopping List", "icon": "cart",
			"items": [
				{"title": "Milk", "icon": "milk", "done": true, "count": "1/1"},
				{"title": "Bread", "icon": "bread", "done": true, "count": "1/1"},
				{"title": "Carrots", "icon": "carrot", "count": "0/3"},
				{"title": "Apples", "icon": "apple", "count": "0/4"},
				{"title": "Cereal", "icon": "cereal", "count": "0/1"},
				{"title": "Bananas", "icon": "banana", "count": "0/4"},
			],
		},
	},
}


static func get_spec(preset_name: String) -> Dictionary:
	return SPECS.get(preset_name, {})
