extends RefCounted
## Festival townsfolk looks (r14 critic: crowd heads read as blobs).
## Every villager uses the same rig + proportions as the household (built by
## the shared sim_rig_builder), but only with CLEAN hair shapes (short, long,
## bun, ponytail, bald + cap) - no noisy curly/messy caps - and autumn
## outfits: plaid flannels, striped sweaters, cardigans, hoodies, vests,
## flat caps. Registered into the rig cache under "fest_*" names so
## SimActor.create("fest_...") works without touching sim_looks.gd.

const RigBuilder := preload("res://scripts/world/actors/sim_rig_builder.gd")

const LOOKS := {
	"fest_plaid_green": {  # bearded man, green flannel, short brown hair
		"body": "big", "skin": Color(0.95, 0.74, 0.6),
		"hair": Color(0.36, 0.22, 0.12), "hair_style": "short", "beard": "short",
		"beard_color": Color(0.32, 0.19, 0.1), "brow": Color(0.25, 0.14, 0.07),
		"top": "plaid", "top_color": Color(0.22, 0.48, 0.3), "top_color2": Color(0.08, 0.16, 0.1),
		"tee": Color(0.94, 0.9, 0.8), "sleeves": "long", "untucked": true,
		"bottom": "jeans", "bottom_color": Color(0.24, 0.32, 0.5),
		"shoes": Color(0.36, 0.22, 0.12), "shoe_style": "boot",
	},
	"fest_mustard_cardigan": {  # woman, auburn ponytail, mustard cardigan
		"body": "slim", "skin": Color(0.98, 0.8, 0.68), "lashes": true,
		"hair": Color(0.56, 0.24, 0.12), "hair_style": "ponytail",
		"top": "cardigan", "top_color": Color(0.88, 0.62, 0.18), "tee": Color(0.97, 0.94, 0.86), "sleeves": "long",
		"bottom": "skirt", "bottom_color": Color(0.4, 0.22, 0.18),
		"socks": Color(0.3, 0.22, 0.2), "shoes": Color(0.3, 0.18, 0.12), "shoe_style": "boot",
	},
	"fest_striped_teen": {  # teen, red cap, cream/rust striped sweater
		"body": "slim", "skin": Color(0.8, 0.58, 0.42),
		"hair": Color(0.16, 0.1, 0.07), "hair_style": "short",
		"hat": "cap", "hat_color": Color(0.8, 0.2, 0.16),
		"top": "striped", "top_color": Color(0.96, 0.92, 0.84), "top_color2": Color(0.78, 0.36, 0.18), "sleeves": "long",
		"bottom": "jeans", "bottom_color": Color(0.26, 0.34, 0.54),
		"shoes": Color(0.95, 0.95, 0.93), "shoe_style": "sneaker",
	},
	"fest_teal_bun": {  # woman, dark bun, teal hoodie
		"body": "slim", "skin": Color(0.56, 0.36, 0.23), "lashes": true,
		"hair": Color(0.1, 0.07, 0.06), "hair_style": "bun",
		"top": "hoodie", "top_color": Color(0.2, 0.52, 0.56), "sleeves": "long",
		"bottom": "pants", "bottom_color": Color(0.24, 0.22, 0.3),
		"shoes": Color(0.92, 0.9, 0.86), "shoe_style": "sneaker",
	},
	"fest_grandpa": {  # flat cap, glasses, white moustache, tweed vest
		"body": "big", "skin": Color(0.92, 0.72, 0.6), "elderly": true,
		"hair": Color(0.9, 0.9, 0.88), "hair_style": "bald", "beard": "moustache", "glasses": true,
		"brow": Color(0.86, 0.86, 0.84),
		"hat": "flat_cap", "hat_color": Color(0.48, 0.36, 0.24),
		"top": "vest", "top_color": Color(0.46, 0.32, 0.2), "tee": Color(0.66, 0.78, 0.92), "sleeves": "long",
		"bottom": "pants", "bottom_color": Color(0.42, 0.42, 0.46), "belt": true,
		"shoes": Color(0.25, 0.16, 0.1), "shoe_style": "boot",
	},
	"fest_grandma": {  # grey bun, glasses, rust cardigan, plaid skirt
		"body": "slim", "skin": Color(0.95, 0.78, 0.66), "lashes": true, "elderly": true,
		"hair": Color(0.66, 0.64, 0.62), "hair_style": "bun", "glasses": true,
		"top": "cardigan", "top_color": Color(0.7, 0.3, 0.2), "tee": Color(0.97, 0.94, 0.86), "sleeves": "long",
		"bottom": "skirt", "bottom_color": Color(0.36, 0.3, 0.4),
		"socks": Color(0.86, 0.82, 0.78), "shoes": Color(0.36, 0.22, 0.14), "shoe_style": "boot",
	},
	"fest_blue_plaid": {  # dark-skinned man, blue flannel, short beard
		"body": "big", "skin": Color(0.45, 0.29, 0.19),
		"hair": Color(0.08, 0.06, 0.05), "hair_style": "short", "beard": "short",
		"top": "plaid", "top_color": Color(0.24, 0.38, 0.66), "top_color2": Color(0.08, 0.12, 0.24),
		"tee": Color(0.92, 0.9, 0.86), "sleeves": "long", "untucked": true,
		"bottom": "pants", "bottom_color": Color(0.5, 0.42, 0.3),
		"shoes": Color(0.3, 0.18, 0.1), "shoe_style": "boot",
	},
	"fest_long_woman": {  # woman, long brown hair, cream sweater, jeans
		"body": "slim", "skin": Color(0.9, 0.68, 0.52), "lashes": true,
		"hair": Color(0.3, 0.17, 0.09), "hair_style": "long",
		"top": "plain", "top_color": Color(0.95, 0.9, 0.8), "collar": Color(0.86, 0.4, 0.2), "sleeves": "long",
		"bottom": "jeans", "bottom_color": Color(0.3, 0.4, 0.62), "belt": true,
		"shoes": Color(0.42, 0.26, 0.14), "shoe_style": "boot",
	},
	"fest_guitarist": {  # stage musician: brown hair, beard, tan flannel
		"body": "big", "skin": Color(0.95, 0.74, 0.6),
		"hair": Color(0.4, 0.24, 0.12), "hair_style": "shaggy", "beard": "short",
		"beard_color": Color(0.34, 0.2, 0.1),
		"top": "plaid", "top_color": Color(0.82, 0.62, 0.36), "top_color2": Color(0.42, 0.26, 0.12),
		"tee": Color(0.2, 0.2, 0.22), "sleeves": "long", "untucked": true,
		"bottom": "jeans", "bottom_color": Color(0.22, 0.28, 0.46),
		"shoes": Color(0.3, 0.18, 0.1), "shoe_style": "boot",
	},
	"fest_vendor": {  # treats vendor: green flat cap, green apron (ref2)
		"body": "big", "skin": Color(0.96, 0.78, 0.66),
		"hair": Color(0.88, 0.88, 0.86), "hair_style": "short", "beard": "moustache",
		"brow": Color(0.8, 0.8, 0.78),
		"hat": "flat_cap", "hat_color": Color(0.24, 0.42, 0.26),
		"top": "plain", "top_color": Color(0.96, 0.95, 0.92), "sleeves": "long",
		"apron": true, "apron_color": Color(0.2, 0.44, 0.26),
		"bottom": "pants", "bottom_color": Color(0.3, 0.3, 0.34),
		"shoes": Color(0.25, 0.16, 0.1), "shoe_style": "boot",
	},
	"fest_kid_boy": {  # boy, short brown hair, orange hoodie
		"body": "child", "skin": Color(0.97, 0.79, 0.65),
		"hair": Color(0.42, 0.26, 0.14), "hair_style": "short",
		"top": "hoodie", "top_color": Color(0.92, 0.5, 0.18), "sleeves": "long",
		"bottom": "jeans", "bottom_color": Color(0.3, 0.4, 0.62),
		"shoes": Color(0.25, 0.45, 0.85), "shoe_style": "sneaker", "shoe_accent": Color(1, 1, 1),
	},
	"fest_kid_girl": {  # girl, long dark hair, red/cream striped top
		"body": "child", "skin": Color(0.8, 0.58, 0.42), "lashes": true,
		"hair": Color(0.16, 0.1, 0.07), "hair_style": "long",
		"top": "striped", "top_color": Color(0.97, 0.94, 0.88), "top_color2": Color(0.82, 0.24, 0.2), "sleeves": "short",
		"bottom": "skirt", "bottom_color": Color(0.36, 0.3, 0.52),
		"socks": Color(0.98, 0.98, 0.98), "shoes": Color(0.82, 0.24, 0.2), "shoe_style": "sneaker",
	},
}


static func register() -> void:
	for k: String in LOOKS:
		if RigBuilder._cache.has(k):
			continue
		var r: Dictionary = RigBuilder._build_human(LOOKS[k])
		(r.mesh as ArrayMesh).surface_set_material(0, RigBuilder.character_material(false))
		RigBuilder._cache[k] = r
