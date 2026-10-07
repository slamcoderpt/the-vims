extends RefCounted
## Autumn trees with full, round, puffy canopies (ref2): a short trunk that
## forks into a crown built from a core sphere plus a ring of lumpy lobes,
## leaf colour varying in small clusters (orange / red / yellow), lighter on
## top, darker underneath, with a few holes so the crown reads as foliage.
##
## Two layers for the standard high game camera (r13):
##  * near trees (real scale) framing the left of the square and behind the
##    stage, canopies filling the top corners;
##  * far trees (forced perspective, matching the scaled-down town hall
##    backdrop): their trunks stand below the plaza level so only the round
##    crowns show around the clock tower, like the reference skyline.
## Each layer is one merged mesh. Downward faces of the crowns are skipped
## (the camera is always above them).

const K := preload("res://scripts/locations/festival/kit.gd")

## [x, z (world, not depth-compressed), base_y, trunk_h, crown_r, palette, layer]
## palette: 0 orange, 1 red, 2 yellow, 3 mixed
const TREES := [
	# --- near (layer 0): left behind the FALL TREATS stall, top-left corner.
	[-9.6, -3.4, 0.0, 2.2, 2.3, 1, 0],
	[-8.4, -7.4, 0.0, 1.5, 2.0, 0, 0],
	[-11.6, -8.2, 0.0, 1.4, 1.9, 2, 0],
	# --- near (layer 0): behind the stage (top right).
	[4.6, -11.6, 0.0, 1.5, 2.0, 0, 0],
	[7.6, -10.2, 0.0, 1.6, 2.1, 1, 0],
	# --- far (layer 1, forced perspective): round crowns at the foot of the
	# scaled town-hall backdrop, either side of the clock tower.
	[-5.1, -10.9, -0.9, 1.3, 0.95, 3, 1],
	[-0.2, -11.5, -0.9, 1.3, 0.9, 2, 1],
	[-7.8, -10.9, -0.9, 1.5, 1.1, 1, 1],
]
const VS := [0.155, 0.13]  # near crowns finer (r13 critic: blocky blobs)
const NAMES := ["TreesNear", "TreesFar"]


static func spots() -> Array:
	var out := []
	for t: Array in TREES:
		if t[6] == 0:
			out.append(Vector2(t[0], t[1]))
	return out


func build(parent: Node3D) -> void:
	var groups := [VoxelBuilder.new(), VoxelBuilder.new()]
	var occs := [{}, {}]
	for g: VoxelBuilder in groups:
		g.jitter = 0.05
	var i := 0
	for t: Array in TREES:
		var li: int = t[6]
		_tree(groups[li], occs[li], VS[li], t[0], t[1], t[2], t[3], t[4], t[5], i * 17 + 3)
		i += 1
	for li in 2:
		var mi := MeshInstance3D.new()
		mi.name = NAMES[li]
		# floor_y huge: skip every downward face (never seen from above).
		mi.mesh = K.mesh(groups[li], VS[li], Vector3.ZERO, 100000, occs[li])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if li == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## Dominant palette + accent palettes for one tree.
func _palettes(p: int) -> Array:
	match p:
		0: return [K.ORANGE, K.ORANGE, K.YELLOW, K.RED]
		1: return [K.RED, K.RED, K.ORANGE, K.ORANGE]
		2: return [K.YELLOW, K.YELLOW, K.ORANGE, K.ORANGE]
	return [K.ORANGE, K.RED, K.YELLOW, K.ORANGE]


func _tree(vb: VoxelBuilder, occ: Dictionary, vs: float, x: float, z: float, y0: float, th_m: float, r: float, pal: int, seed: int) -> void:
	var cx := int(round(x / vs))
	var cz := int(round(z / vs))
	var by := int(round(y0 / vs))
	var th := int(th_m / vs)
	var rc := r / vs
	var bark := [Color("5e3b22"), Color("4f311c"), Color("6b452a"), Color("573620"), Color("47301f")]
	# Trunk 2x2 (3x3 at the base), root flare, bark streaks.
	var wdt := 2
	for y in range(by, by + th):
		var w := 3 if y < by + 3 else wdt
		for dx in w:
			for dz in w:
				var c: Color = K.pick(bark, K.hs(cx + dx, y / 2, cz + dz))
				vb.set_v(Vector3i(cx - w / 2 + dx, y, cz - w / 2 + dz), c)
	if y0 >= 0.0:
		for o in [Vector3i(-2, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, -2), Vector3i(0, 0, 2), Vector3i(-2, 1, 1), Vector3i(1, 0, 2)]:
			vb.set_v(Vector3i(cx, by, cz) + o, bark[1])
	var top := Vector3(cx + 0.5, by + th, cz + 0.5)
	var crown := top + Vector3(0, rc * 0.62, 0)
	# Branches forking up into the crown (visible through the gaps).
	for b in 4:
		var ang := TAU * b / 4.0 + K.hs(seed, b, 3)
		var start := top - Vector3(0, th * 0.2, 0)
		var end := crown + Vector3(cos(ang) * rc * 0.55, rc * 0.05, sin(ang) * rc * 0.55)
		K.line(vb, start, end, bark[0])
	var cols_sets: Array = _palettes(pal)
	var lo := crown.y - rc
	var hi := crown.y + rc
	var shader := func(q: Vector3i) -> Color:
		var hq := VoxelBuilder.hash3(q + Vector3i(seed, 7, seed))
		var rel := (Vector3(q) + Vector3(0.5, 0.5, 0.5) - crown) / rc
		# Leaf clusters: 3-cell patches share one palette + base hue.
		var cell := Vector3i(floori(q.x / 3.0), floori(q.y / 3.0), floori(q.z / 3.0))
		var ph := VoxelBuilder.hash3(cell + Vector3i(seed, 0, 0))
		var cols: Array = cols_sets[0] if ph < 0.55 else cols_sets[1 + int(ph * 17.0) % 3]
		var base_idx := int(VoxelBuilder.hash3(cell + Vector3i(0, seed, 5)) * cols.size())
		var c: Color = cols[(base_idx + (1 if hq > 0.8 else 0)) % cols.size()]
		var ky := clampf((q.y - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
		# Sun from the front-left: lighter on top and towards the camera.
		var side := clampf(-rel.x * 0.25 + rel.z * 0.45, -1.0, 1.0)
		var f := 0.72 + 0.3 * ky + 0.08 * side + (hq - 0.5) * 0.12
		c = K.shade(c, f)
		if hq > 0.985:
			c = Color("fbe08a")
		elif hq < 0.06:
			c = K.shade(c, 0.62)  # shadowed gaps between leaf clusters
		return c
	# Crown: squashed core sphere + ring of lumpy lobes + a top lobe.
	K.blob(vb, crown, Vector3(rc * 0.82, rc * 0.72, rc * 0.82), shader, 0.18, seed, occ)
	var nl := 7
	for k in nl:
		var a := TAU * k / nl + K.hs(seed, k, 11) * 0.6
		var lr := rc * (0.5 + 0.12 * K.hs(k, seed, 2))
		var off := Vector3(cos(a) * rc * 0.5, (K.hs(seed, k, 5) - 0.45) * rc * 0.4, sin(a) * rc * 0.45)
		K.blob(vb, crown + off, Vector3(lr, lr * 0.85, lr), shader, 0.3, seed + k, occ)
	K.blob(vb, crown + Vector3(rc * 0.1, rc * 0.45, -rc * 0.05), Vector3(rc * 0.55, rc * 0.45, rc * 0.55), shader, 0.3, seed + 31, occ)
