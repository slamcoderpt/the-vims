extends RefCounted
## Look definitions for SimActor. Each look is a plain dictionary read by
## sim_rig_builder.gd. Add new NPCs here.

const LOOKS := {
	"dad": {
		"body": "big", "skin": Color(0.98, 0.77, 0.63),
		# r12b: warm chestnut hair, a slightly deeper (still clearly lighter
		# than the face's shadow side) beard, so hair/beard/face separate.
		# r13: flat, low-noise blocks with strong value separation: a
		# chocolate hair cap, a slightly deeper beard mass, peach face band.
		"hair": Color(0.42, 0.23, 0.11), "hair_style": "shaggy", "beard": "full",
		"beard_color": Color(0.36, 0.19, 0.09),
		"brow": Color(0.24, 0.12, 0.06), "eye": Color(0.2, 0.12, 0.08),
		"top": "plaid", "top_color": Color(0.80, 0.13, 0.12), "top_color2": Color(0.16, 0.05, 0.06),
		"tee": Color(0.2, 0.2, 0.23), "sleeves": "long", "untucked": true,
		"bottom": "jeans", "bottom_color": Color(0.21, 0.31, 0.55),
		"shoes": Color(0.27, 0.16, 0.09), "shoe_style": "boot",
	},
	"bunny_girl": {
		"body": "child", "skin": Color(0.99, 0.80, 0.68), "lashes": true,
		"hair": Color(0.48, 0.27, 0.14), "hair_style": "long",
		"hat": "bunny", "hat_color": Color(0.99, 0.80, 0.86),
		"ear_color": Color(1.0, 0.90, 0.93), "ear_inner": Color(0.97, 0.56, 0.68),
		"top": "gingham", "top_color": Color(0.97, 0.62, 0.74), "top_color2": Color(1.0, 0.97, 0.97),
		"collar": Color(1.0, 1.0, 1.0), "sleeves": "short",
		"bottom": "overalls", "bottom_color": Color(0.47, 0.64, 0.88),
		"socks": Color(0.99, 0.99, 0.99), "shoes": Color(0.98, 0.72, 0.8), "shoe_style": "sneaker",
		"shoe_accent": Color(1, 1, 1),
	},
	"cat_girl": {
		"body": "child", "skin": Color(0.84, 0.61, 0.45), "lashes": true,
		"hair": Color(0.33, 0.19, 0.10), "hair_style": "long", "eye": Color(0.28, 0.16, 0.1),
		"hat": "cat", "hat_color": Color(0.62, 0.58, 0.90),
		"ear_color": Color(0.60, 0.55, 0.89), "ear_inner": Color(0.96, 0.7, 0.8),
		"top": "striped", "top_color": Color(0.22, 0.30, 0.58), "top_color2": Color(0.97, 0.97, 0.98),
		"sleeves": "short",
		"bottom": "overalls", "bottom_color": Color(0.32, 0.47, 0.78),
		"socks": Color(0.99, 0.99, 0.99), "shoes": Color(0.36, 0.52, 0.92), "shoe_style": "sneaker",
		"shoe_accent": Color(1, 1, 1),
	},
	"beagle": {
		"species": "dog",
		"tan": Color(0.90, 0.58, 0.28), "saddle": Color(0.24, 0.15, 0.10),
		"white": Color(1.0, 0.98, 0.94), "ear": Color(0.46, 0.23, 0.09),
		"collar": Color(0.86, 0.18, 0.18),
	},
	# --- Neighbours / townsfolk -------------------------------------------
	"npc_0": {  # ginger curly-haired woman, cream blouse
		"body": "slim", "skin": Color(0.98, 0.80, 0.68), "lashes": true,
		"hair": Color(0.84, 0.40, 0.16), "hair_style": "curly_long",
		"top": "plain", "top_color": Color(0.96, 0.89, 0.74), "collar": Color(1, 0.97, 0.9), "sleeves": "short",
		"bottom": "jeans", "bottom_color": Color(0.42, 0.56, 0.78), "belt": true,
		"shoes": Color(0.96, 0.96, 0.94), "shoe_style": "sneaker",
	},
	"npc_1": {  # dark-skinned man, short black hair + beard, green jacket
		"body": "big", "skin": Color(0.45, 0.29, 0.19),
		"hair": Color(0.09, 0.07, 0.06), "hair_style": "curly", "beard": "short",
		"top": "jacket", "top_color": Color(0.30, 0.43, 0.26), "tee": Color(0.95, 0.94, 0.9), "sleeves": "long",
		"bottom": "jeans", "bottom_color": Color(0.18, 0.24, 0.42),
		"shoes": Color(0.32, 0.2, 0.12), "shoe_style": "boot",
	},
	"npc_2": {  # elderly woman, grey curls, glasses, green cardigan
		"body": "slim", "skin": Color(0.94, 0.76, 0.64), "lashes": true, "elderly": true,
		"hair": Color(0.82, 0.82, 0.8), "hair_style": "curly", "glasses": true,
		"top": "cardigan", "top_color": Color(0.33, 0.50, 0.36), "tee": Color(0.96, 0.92, 0.82), "sleeves": "long",
		"bottom": "pants", "bottom_color": Color(0.70, 0.62, 0.46),
		"shoes": Color(0.4, 0.26, 0.16), "shoe_style": "boot",
	},
	"npc_3": {  # shopkeeper with green apron
		"body": "slim", "skin": Color(0.90, 0.66, 0.50), "lashes": true,
		"hair": Color(0.33, 0.18, 0.1), "hair_style": "long",
		"top": "plain", "top_color": Color(0.97, 0.96, 0.94), "sleeves": "short",
		"apron": true, "apron_color": Color(0.15, 0.45, 0.27),
		"bottom": "pants", "bottom_color": Color(0.22, 0.22, 0.27),
		"shoes": Color(0.2, 0.18, 0.18), "shoe_style": "boot",
	},
	"npc_4": {  # blond boy
		"body": "child", "skin": Color(0.97, 0.79, 0.65),
		"hair": Color(0.95, 0.78, 0.40), "hair_style": "messy",
		"top": "plain", "top_color": Color(0.30, 0.52, 0.88), "collar": Color(0.95, 0.95, 0.95), "sleeves": "short",
		"bottom": "shorts", "bottom_color": Color(0.76, 0.66, 0.46),
		"socks": Color(0.98, 0.98, 0.98), "shoes": Color(0.88, 0.25, 0.22), "shoe_style": "sneaker",
	},
	"npc_5": {  # woman with bun, mustard sweater
		"body": "slim", "skin": Color(0.56, 0.36, 0.23), "lashes": true,
		"hair": Color(0.11, 0.08, 0.07), "hair_style": "bun",
		"top": "plain", "top_color": Color(0.96, 0.74, 0.25), "sleeves": "long",
		"bottom": "pants", "bottom_color": Color(0.26, 0.23, 0.36),
		"shoes": Color(0.9, 0.88, 0.85), "shoe_style": "sneaker",
	},
	"npc_6": {  # elderly man, flat cap, glasses, white moustache, vest
		"body": "big", "skin": Color(0.91, 0.71, 0.59), "elderly": true,
		"hair": Color(0.9, 0.9, 0.88), "hair_style": "bald", "beard": "moustache", "glasses": true,
		"brow": Color(0.85, 0.85, 0.83),
		"hat": "flat_cap", "hat_color": Color(0.45, 0.35, 0.25),
		"top": "vest", "top_color": Color(0.42, 0.3, 0.2), "tee": Color(0.62, 0.74, 0.9), "sleeves": "long",
		"cuff": Color(0.62, 0.74, 0.9),
		"bottom": "pants", "bottom_color": Color(0.45, 0.45, 0.48), "belt": true,
		"shoes": Color(0.25, 0.16, 0.1), "shoe_style": "boot",
	},
	"npc_7": {  # teen in red cap and orange hoodie
		"body": "slim", "skin": Color(0.80, 0.58, 0.42),
		"hair": Color(0.2, 0.12, 0.08), "hair_style": "short",
		"hat": "cap", "hat_color": Color(0.85, 0.2, 0.2),
		"top": "hoodie", "top_color": Color(0.95, 0.55, 0.22), "sleeves": "long",
		"bottom": "jeans", "bottom_color": Color(0.25, 0.33, 0.55),
		"shoes": Color(0.15, 0.15, 0.18), "shoe_style": "sneaker",
	},
}


static func get_look(look_name: String) -> Dictionary:
	if LOOKS.has(look_name):
		return LOOKS[look_name]
	return LOOKS["npc_0"]


static func npc_looks() -> Array[String]:
	var out: Array[String] = []
	for k: String in LOOKS:
		if k.begins_with("npc_"):
			out.append(k)
	return out
