extends RefCounted
## Per-location navigation settings for NavGrid. A location may override (or
## extend) these by implementing nav_info() -> Dictionary with the same keys.
##   levels:    floor heights of each storey (m)
##   bounds:    Rect2 over x/z that sims may walk in
##   floor_tol: how far above a level a surface still counts as floor (decks, rugs)
##   links:     [{a: Vector3, b: Vector3}] straight walkable connections between
##              levels (stairs). Endpoints snap to the nearest open cell.
##   carve:     [{level, rect: Rect2 (xz)}] forced-walkable areas (doorways).

const CONFIGS := {
	"home": {
		"levels": [0.0, 3.0],
		"bounds": Rect2(-13.0, -9.0, 26.0, 20.0),
		"floor_tol": 0.2,
		# Stair well x 3..5.25, z 1.75..4.75 (steps x 3.1..4.4 going down towards +z):
		# top in the upstairs hall, bottom step steps off west into the kitchen.
		"links": [{"a": Vector3(3.75, 3.0, 1.2), "b": Vector3(2.55, 0.0, 4.45),
			"via": [Vector3(3.75, 3.0, 1.75), Vector3(3.75, 0.19, 4.62)]}],
		# Upstairs doorways (wall holes in home.gd) crowded by furniture:
		# office|hall (x=-1), pink|hall and blue|hall (z=0), hall|bath (x=5.5).
		"carve": [
			{"level": 1, "rect": Rect2(-2.6, 1.3, 2.35, 1.2)},
			{"level": 1, "rect": Rect2(2.4, -0.75, 0.7, 1.5)},
			{"level": 1, "rect": Rect2(4.3, -0.75, 0.8, 1.5)},
			{"level": 1, "rect": Rect2(5.2, 1.0, 0.35, 3.4)},
			{"level": 1, "rect": Rect2(5.2, 3.5, 1.1, 0.8)},
		],
	},
	"backyard": {
		"levels": [0.0],
		"bounds": Rect2(-10.0, -9.0, 22.0, 18.0),
		"floor_tol": 0.45,
	},
	"festival": {
		"levels": [0.0],
		"bounds": Rect2(-12.0, -16.0, 26.0, 26.0),
		"floor_tol": 0.3,
	},
	"market": {
		"levels": [0.0],
		"bounds": Rect2(-8.0, -12.0, 16.0, 19.0),
		"floor_tol": 0.2,
	},
}


static func get_config(loc_name: String, location: Node) -> Dictionary:
	var cfg: Dictionary = CONFIGS.get(loc_name, {"levels": [0.0], "bounds": Rect2(-16, -16, 32, 32)}).duplicate(true)
	if location and location.has_method("nav_info"):
		cfg.merge(location.nav_info(), true)
	cfg["key"] = loc_name
	return cfg
