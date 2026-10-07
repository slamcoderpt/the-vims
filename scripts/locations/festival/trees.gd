extends RefCounted
## Autumn trees (orange / red / yellow crowns) merged per group into one mesh.
## Voxel size 0.15 m: chunky like the reference, cheap enough for phones.

const K := preload("res://scripts/locations/festival/kit.gd")
const VS := [0.24, 0.24, 0.34]

## [x, z, height_m, crown_radius_m, palette (0 orange, 1 red, 2 yellow, 3 mixed), group]
const TREES := [
	# Left edge, behind the treats stall.
	[-9.8, -3.2, 5.0, 2.4, 0, 0],
	[-9.4, -9.6, 5.2, 2.3, 1, 0],
	[-12.8, -13.5, 5.4, 2.8, 2, 0],
	# Right edge, behind stalls / stage.
	[11.8, -5.4, 5.0, 2.3, 2, 1],
	[13.4, -10.4, 5.2, 2.4, 0, 1],
	# Back, framing the town hall.
	[-3.4, -19.6, 6.0, 2.6, 0, 2],
	[9.8, -20.5, 6.4, 3.0, 1, 2],
	[14.4, -16.0, 5.6, 3.0, 2, 2],
	[-10.4, -21.0, 6.2, 3.0, 1, 2],
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
		g.jitter = 0.07
	var i := 0
	for t: Array in TREES:
		var gi: int = t[5]
		_tree(groups[gi], occs[gi], VS[gi], t[0], t[1], t[2], t[3], t[4], i)
		i += 1
	var names := ["TreesLeft", "TreesRight", "TreesBack"]
	for gi in 3:
		K.inst(parent, groups[gi], VS[gi], Vector3.ZERO, 0.0, true, Vector3.ZERO, names[gi], occs[gi])


func _palette(p: int) -> Array:
	match p:
		0: return K.ORANGE
		1: return K.RED
		2: return K.YELLOW
	return K.ORANGE + K.RED + K.YELLOW


func _tree(vb: VoxelBuilder, occ: Dictionary, vs: float, x: float, z: float, h: float, r: float, pal: int, seed: int) -> void:
	var cx := int(round(x / vs))
	var cz := int(round(z / vs))
	var th := int(h / vs)
	var rc := r / vs
	var bark := [Color("5e3b22"), Color("4f311c"), Color("6b452a"), Color("573620")]
	# Trunk (3x3 tapering to 2x2) with root flare.
	for y in th:
		var wdt := 3 if y < th * 0.55 else 2
		for dx in wdt:
			for dz in wdt:
				vb.set_v(Vector3i(cx - 1 + dx, y, cz - 1 + dz), K.pick(bark, K.hs(cx + dx, y, cz + dz)))
	for o in [Vector3i(-2, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, -2), Vector3i(0, 0, 2), Vector3i(-2, 1, 0), Vector3i(0, 0, 1)]:
		vb.set_v(Vector3i(cx, 0, cz) + o, bark[1])
	# Branches.
	var top := Vector3(cx, th, cz)
	var nb := 3
	var cols: Array = _palette(pal)
	var blobs := []
	blobs.append([top + Vector3(0, rc * 0.25, 0), Vector3(rc, rc * 0.85, rc)])
	for b in nb:
		var ang := TAU * b / nb + K.hs(seed, b, 3) * 1.2
		var start := Vector3(cx, th * (0.55 + 0.12 * b / nb), cz)
		var end := start + Vector3(cos(ang) * rc * 0.75, rc * 0.55, sin(ang) * rc * 0.75)
		K.line(vb, start, end, bark[0])
		K.line(vb, start + Vector3(1, 0, 0), end + Vector3(1, 0, 0), bark[2])
		var br := rc * (0.55 + 0.15 * K.hs(b, seed, 1))
		blobs.append([end + Vector3(0, br * 0.2, 0), Vector3(br, br * 0.75, br)])
	var lo := top.y - rc
	var hi := top.y + rc * 1.3
	for bi in blobs.size():
		var bl: Array = blobs[bi]
		K.blob(vb, bl[0], bl[1], func(q: Vector3i) -> Color:
			# Leaf clumps: colour picked per 2x2x2 cluster, small per-voxel jitter.
			var cq := Vector3i(floori(q.x / 2.0), floori(q.y / 2.0), floori(q.z / 2.0))
			var hh := VoxelBuilder.hash3(cq + Vector3i(seed * 7, 1, 3))
			var c: Color = K.pick(cols, hh)
			# Sun-lit crown top / sun side, deeper colour underneath.
			var k := clampf((q.y - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
			var side := clampf((float(q.x - cx) * -0.4 + float(q.z - cz) * 0.6) / maxf(rc, 1.0), -1.0, 1.0)
			c = K.shade(c, 0.86 + 0.26 * k + 0.08 * side + (VoxelBuilder.hash3(q) - 0.5) * 0.08)
			if hh > 0.95:
				c = Color("f7d46a")
			return c, 0.4, seed * 13 + bi, occ)
