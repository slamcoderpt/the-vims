extends RefCounted
## Autumn trees: visible trunk that forks into branches, each branch ending in
## a cluster of small leaf clumps (multi-tone orange / red / yellow with gaps
## between clumps so the canopy reads as a silhouette, not a solid wall).
## Merged per group into one mesh.

const K := preload("res://scripts/locations/festival/kit.gd")
const VS := [0.23, 0.23, 0.34]

## [x, z, height_m, crown_radius_m, palette (0 orange, 1 red, 2 yellow, 3 mixed), group]
const TREES := [
	# Left edge, behind the treats stall.
	[-9.8, -3.2, 3.6, 2.3, 0, 0],
	[-9.4, -9.6, 3.9, 2.2, 1, 0],
	[-12.8, -13.5, 4.2, 2.6, 2, 0],
	# Right edge, behind stalls / stage.
	[11.8, -5.4, 3.6, 2.2, 2, 1],
	[13.4, -10.4, 3.9, 2.3, 0, 1],
	[12.2, -17.2, 4.4, 2.5, 3, 1],
	# Back, framing the town hall.
	[-6.2, -18.6, 4.6, 2.4, 0, 2],
	[9.8, -20.5, 5.0, 2.8, 1, 2],
	[14.4, -15.0, 4.4, 2.6, 2, 2],
	[-10.4, -21.0, 4.8, 2.8, 3, 2],
	[3.6, -22.5, 4.2, 2.0, 2, 2],
	[-3.4, -23.0, 4.0, 1.9, 1, 2],
]


static func spots() -> Array:
	var out := []
	for t: Array in TREES:
		out.append(Vector2(t[0], t[1]))
	return out


func build(parent: Node3D) -> void:
	var groups := [VoxelBuilder.new(), VoxelBuilder.new(), VoxelBuilder.new()]
	var occs := [{}, {}, {}]
	for g: VoxelBuilder in groups:
		g.jitter = 0.05
	var i := 0
	for t: Array in TREES:
		var gi: int = t[5]
		_tree(groups[gi], occs[gi], VS[gi], t[0], t[1], t[2], t[3], t[4], i)
		i += 1
	var names := ["TreesLeft", "TreesRight", "TreesBack"]
	for gi in 3:
		K.inst(parent, groups[gi], VS[gi], Vector3.ZERO, 0.0, true, Vector3.ZERO, names[gi], occs[gi])


## Dominant palette + accent palettes for one tree.
func _palettes(p: int) -> Array:
	match p:
		0: return [K.ORANGE, K.ORANGE, K.YELLOW, K.RED]
		1: return [K.RED, K.RED, K.ORANGE, K.YELLOW]
		2: return [K.YELLOW, K.YELLOW, K.ORANGE, K.ORANGE]
	return [K.ORANGE, K.RED, K.YELLOW, K.ORANGE]


func _tree(vb: VoxelBuilder, occ: Dictionary, vs: float, x: float, z: float, h: float, r: float, pal: int, seed: int) -> void:
	var cx := int(round(x / vs))
	var cz := int(round(z / vs))
	var th := int(h / vs)
	var rc := r / vs
	var bark := [Color("5e3b22"), Color("4f311c"), Color("6b452a"), Color("573620"), Color("47301f")]
	# Trunk (3x3 tapering to 2x2) with root flare, bark streaks.
	for y in th:
		var wdt := 3 if y < th * 0.6 else 2
		var off := 0 if wdt == 3 else (1 if K.hs(seed, 1, 1) > 0.5 else 0)
		for dx in wdt:
			for dz in wdt:
				var c: Color = K.pick(bark, K.hs(cx + dx, y / 2, cz + dz))
				vb.set_v(Vector3i(cx - 1 + dx + off, y, cz - 1 + dz), c)
	for o in [Vector3i(-2, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, -2), Vector3i(0, 0, 2), Vector3i(-2, 1, 0), Vector3i(1, 0, 2), Vector3i(2, 1, -1)]:
		vb.set_v(Vector3i(cx, 0, cz) + o, bark[1])
	# Branches fork from the upper trunk; each ends in a clump cluster.
	var cols_sets: Array = _palettes(pal)
	var top := Vector3(cx + 0.5, th, cz + 0.5)
	var nb := 5
	var ends := []
	for b in nb:
		var ang := TAU * b / nb + K.hs(seed, b, 3) * 0.9
		var start := Vector3(cx + 0.5, th * (0.62 + 0.3 * float(b) / nb), cz + 0.5)
		var reach := rc * (0.55 + 0.3 * K.hs(b, seed, 5))
		var end := start + Vector3(cos(ang) * reach, rc * (0.35 + 0.35 * K.hs(seed, b, 8)), sin(ang) * reach * 0.8)
		K.line(vb, start, end, bark[0])
		K.line(vb, start + Vector3(0, 1, 0), end, bark[2])
		ends.append(end)
	ends.append(top + Vector3(0, rc * 0.75, 0))
	ends.append(top + Vector3(rc * 0.25, rc * 1.05, -rc * 0.2))
	# Leaf clumps: 3-4 per branch end, plus a few filling the crown shell.
	var crown := top + Vector3(0, rc * 0.55, 0)
	var clumps := []
	var ci := 0
	for e: Vector3 in ends:
		var n := 3 if ci < nb else 2
		for k in n:
			var hh := K.hs(seed, ci, k)
			var o := Vector3(K.hs(ci, k, seed) - 0.5, (K.hs(k, seed, ci) - 0.3) * 0.7, K.hs(seed + 3, k, ci) - 0.5) * rc * 0.7
			var cr := rc * (0.32 + 0.16 * hh)
			clumps.append([e + o, cr, ci * 7 + k])
		ci += 1
	for k in 6:
		var a := TAU * k / 6.0 + K.hs(seed, k, 31)
		var p := crown + Vector3(cos(a) * rc * 0.6, (K.hs(k, 2, seed) - 0.2) * rc * 0.5, sin(a) * rc * 0.5)
		clumps.append([p, rc * (0.3 + 0.12 * K.hs(k, seed, 4)), 100 + k])
	var lo := top.y - rc * 0.3
	var hi := top.y + rc * 1.6
	for cl: Array in clumps:
		var center: Vector3 = cl[0]
		var cr: float = cl[1]
		var cid: int = cl[2]
		# Each clump gets one palette (mostly the dominant) and one base hue
		# so neighbouring clumps read as separate tufts.
		var ph := K.hs(seed, cid, 77)
		var cols: Array = cols_sets[0] if ph < 0.5 else cols_sets[1 + int(ph * 10.0) % 3]
		var base_idx := int(K.hs(cid, seed, 13) * cols.size())
		var rad := Vector3(cr, cr * 0.8, cr)
		K.blob(vb, center, rad, func(q: Vector3i) -> Color:
			var hq := VoxelBuilder.hash3(q + Vector3i(seed, 0, cid))
			var rel := (Vector3(q) + Vector3(0.5, 0.5, 0.5) - center) / rad
			var depth := rel.length()
			# Leafy texture: knock holes in the outer shell so the darker
			# inner layer shows through (reads as leaf clusters, not a cube).
			if depth > 0.78 and hq < 0.16 and rel.y > -0.5:
				return Color(0, 0, 0, 0)
			var c: Color = cols[(base_idx + (1 if hq > 0.82 else 0)) % cols.size()]
			var ky := clampf((q.y - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
			var side := clampf(-rel.x * 0.3 + rel.z * 0.5, -1.0, 1.0)
			var f := 0.8 + 0.14 * ky + 0.16 * clampf(rel.y, -1.0, 1.0) + 0.06 * side + (hq - 0.5) * 0.1
			if depth < 0.8:
				f *= 0.8
			c = K.shade(c, f)
			if hq > 0.975:
				c = Color("f9dc78")
			return c, 0.55, seed * 13 + cid, occ)
