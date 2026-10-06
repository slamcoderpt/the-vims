extends RefCounted
## Backyard landscape: lawn, pavers, flower beds, picket fences, trees,
## hedges and the silhouetted neighbour houses against the sunset.

const V := preload("res://scripts/locations/backyard/vox.gd")

const M := 8    # cells per metre at 0.125
const F := 16   # cells per metre at 0.0625

const GRASS := [Color("5f9e3a"), Color("6aab40"), Color("579436"), Color("74b347"), Color("4f8a33"), Color("66a63c")]
const PURPLES := [Color("8a5cc8"), Color("a37de0"), Color("6e47aa"), Color("b896ee"), Color("7d52bd")]
const PINKS := [Color("ee7fb4"), Color("f59cc6"), Color("d95c98"), Color("ffb6d4")]
const WHITES := [Color("fbf7f0"), Color("f1ece6"), Color("fffdf8")]
const YELLOWS := [Color("f7cf3e"), Color("ffdf63"), Color("f0b62c")]
const REDS := [Color("e2513f"), Color("f07a3a")]
const PICKET := Color("f4efe6")

## Rects (metres): x0, z0, x1, z1
const BEDS := [
	[-12.8, -6.35, 1.4, -5.3, 1.0],    # along back fence
	[-9.0, -5.3, -5.6, -3.6, 0.9],     # back-left corner behind grill
	[4.8, -2.55, 12.8, -1.85, 1.1],    # in front of the deck (right of steps)
	[0.2, -2.55, 2.3, -1.85, 1.0],     # in front of the deck (left of steps)
	[8.8, -1.6, 13.5, 0.2, 0.9],       # behind the lounge
	[9.2, 3.8, 14.0, 6.5, 1.0],        # right foreground
	[-10.0, 3.7, 0.6, 4.75, 1.15],     # along the front fence
	[0.6, 5.0, 6.5, 6.6, 1.0],         # centre foreground
	[-13.0, -3.0, -10.5, 3.7, 0.9],    # left edge
]

var root: Node3D
var _rng := RandomNumberGenerator.new()


func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Garden"
	parent.add_child(root)
	_rng.seed = 4242
	_lawn()
	_beds()
	_fences()
	_trees()
	_neighbours()


func _in_rect(x: float, z: float, r: Array) -> bool:
	return x >= r[0] and x < r[2] and z >= r[1] and z < r[3]


func _in_bed(x: float, z: float) -> bool:
	for r in BEDS:
		if _in_rect(x, z, r):
			return true
	return false


func _paver(x: float, z: float) -> int:
	# 0 = none, 1 = stone, 2 = gap
	# Patio under the grill.
	if x > -5.6 and x < -1.6 and z > -2.4 and z < 1.6:
		var u := fposmod(x * 2.0 + (0.5 if posmod(int(floor(z * 2.0)), 2) == 1 else 0.0), 1.0)
		var v := fposmod(z * 2.0, 1.0)
		return 2 if (u < 0.14 or v < 0.14) else 1
	# Stepping stones from the deck steps to the front.
	var path_pts := [Vector2(3.4, -1.8), Vector2(3.0, -0.9), Vector2(2.7, 0.0), Vector2(2.9, 1.0), Vector2(2.5, 2.0), Vector2(2.2, 3.0)]
	for pp in path_pts:
		if absf(x - pp.x) < 0.38 and absf(z - pp.y) < 0.3:
			return 1
	return 0


func _lawn() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var x0 := -14 * M
	var x1 := 15 * M
	var z0 := -7 * M
	var z1 := 8 * M
	for x in range(x0, x1):
		for z in range(z0, z1):
			var wx := (x + 0.5) / M
			var wz := (z + 0.5) / M
			var q := Vector3i(x, -1, z)
			var pv := _paver(wx, wz)
			var c: Color
			if _in_bed(wx, wz):
				c = V.shade(Color("5a3b26"), 0.85 + V.h1(q, 3) * 0.3)
				vb.set_v(q, c)
				vb.set_v(q + Vector3i(0, 1, 0), V.shade(Color("4a3020"), 0.8 + V.h1(q, 4) * 0.35))
				continue
			if pv == 1:
				c = V.shade(Color("a8a39c"), 0.8 + V.h1(Vector3i(int(wx * 2), 0, int(wz * 2)), 5) * 0.25 + V.h1(q, 6) * 0.08)
			elif pv == 2:
				c = V.shade(Color("6b7a45"), 0.9 + V.h1(q, 7) * 0.2)
			else:
				var patch := sin(wx * 0.9 + 1.3) * cos(wz * 1.1) * 0.06 + sin(wx * 2.7 + wz * 1.9) * 0.04
				c = V.shade(GRASS[int(V.h1(q, 1) * GRASS.size())], 1.0 + patch)
				# A few clover / daisy speckles.
				var r := V.h1(q, 9)
				if r < 0.006:
					c = Color("f6f2e8")
				elif r < 0.01:
					c = Color("e8d44d")
			vb.set_v(q, c)
	# Bed edging: stone border.
	for r in BEDS:
		var bx0 := int(floor(r[0] * M))
		var bx1 := int(ceil(r[2] * M))
		var bz0 := int(floor(r[1] * M))
		var bz1 := int(ceil(r[3] * M))
		for x in range(bx0, bx1):
			for z in range(bz0, bz1):
				if x == bx0 or x == bx1 - 1 or z == bz0 or z == bz1 - 1:
					var q := Vector3i(x, 0, z)
					vb.set_v(q, V.shade(Color("a69a8c"), 0.8 + V.h1(q, 11) * 0.35))
	V.inst(vb, root, V.SIZE_MID, Vector3.ZERO, 0.0, Vector3.ZERO, false, true, "Lawn")
	# Coarse ground beyond the fences (neighbour yards, street).
	var far := VoxelBuilder.new()
	for x in range(-44, 44):
		for z in range(-60, 30):
			var wx := x * 0.5
			var wz := z * 0.5
			if wx >= -14 and wx < 15 and wz >= -7 and wz < 8:
				continue
			var q := Vector3i(x, -1, z)
			far.set_v(q, V.shade(GRASS[int(V.h1(q, 2) * GRASS.size())], 0.8))
	V.inst(far, root, 0.5, Vector3(0, -0.02, 0), 0.0, Vector3.ZERO, false, true, "FarGround")


# ------------------------------------------------------------------ flowers

func _beds() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.06
	for r in BEDS:
		var area: float = (r[2] - r[0]) * (r[3] - r[1])
		var n := int(area * 14.0 * r[4])
		for i in n:
			var wx := _rng.randf_range(r[0] + 0.12, r[2] - 0.12)
			var wz := _rng.randf_range(r[1] + 0.12, r[3] - 0.12)
			_plant(vb, int(wx * F), 2, int(wz * F), _rng.randi())
	# Loose grass tufts on the lawn.
	for i in 900:
		var wx := _rng.randf_range(-13.5, 14.5)
		var wz := _rng.randf_range(-6.5, 7.5)
		if _in_bed(wx, wz) or _paver(wx, wz) != 0:
			continue
		var x := int(wx * F)
		var z := int(wz * F)
		var g: Color = GRASS[_rng.randi() % GRASS.size()]
		vb.set_v(Vector3i(x, 0, z), V.shade(g, 1.08))
		if _rng.randf() < 0.6:
			vb.set_v(Vector3i(x + 1, 0, z), V.shade(g, 0.95))
		if _rng.randf() < 0.5:
			vb.set_v(Vector3i(x, 1, z), V.shade(g, 1.15))
		if _rng.randf() < 0.08:
			vb.set_v(Vector3i(x, 1, z), WHITES[0])
	V.inst(vb, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "Flowers")


## One flowering plant: leafy mound + blooms, base at fine grid (x, y, z).
func _plant(vb: VoxelBuilder, x: int, y: int, z: int, seed: int) -> void:
	var r := float(seed % 1000) / 1000.0
	var kind := 0
	if r < 0.34:
		kind = 0          # lavender spikes
	elif r < 0.58:
		kind = 1          # pink daisies / cosmos
	elif r < 0.76:
		kind = 2          # white daisies
	elif r < 0.9:
		kind = 3          # yellow
	else:
		kind = 4          # pink pom-pom
	var rad := 2.0 + float((seed >> 3) % 100) / 100.0 * 1.8
	var h := 3.0 + float((seed >> 5) % 100) / 100.0 * 2.5
	V.blob(vb, Vector3(x, y, z), Vector3(rad, h, rad), V.leaves(seed % 97, (seed >> 7) % 2, y), 0.5, seed % 31, true)
	var top := y + int(h)
	match kind:
		0:
			var spikes := 3 + (seed >> 9) % 4
			for i in spikes:
				var sx := x + ((seed >> (i * 2)) % 5) - 2
				var sz := z + ((seed >> (i * 2 + 3)) % 5) - 2
				var sh := 4 + ((seed >> (i + 4)) % 4)
				var base := top - 1
				for k in sh:
					var c: Color = PURPLES[(seed + i + k) % PURPLES.size()]
					vb.set_v(Vector3i(sx, base + k, sz), V.shade(c, 0.85 + 0.05 * k))
		4:
			var cc: Color = PINKS[(seed >> 4) % PINKS.size()]
			V.blob(vb, Vector3(x + 0.5, top + 1.5, z + 0.5), Vector3(2.2, 1.8, 2.2), V.mix([cc, V.shade(cc, 1.15), V.shade(cc, 0.85)], seed % 13), 0.4, seed % 7)
		_:
			var pal: Array = PINKS if kind == 1 else (WHITES if kind == 2 else YELLOWS)
			var heads := 3 + (seed >> 6) % 4
			for i in heads:
				var hx := x + ((seed >> (i * 3)) % 7) - 3
				var hz := z + ((seed >> (i * 3 + 2)) % 7) - 3
				var hy := top + ((seed >> (i + 2)) % 3)
				var pc: Color = pal[(seed + i) % pal.size()]
				vb.set_v(Vector3i(hx, hy - 1, hz), Color("4c8a35"))
				vb.set_v(Vector3i(hx, hy, hz), Color("f2b630") if kind != 3 else Color("8a5a24"))
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					vb.set_v(Vector3i(hx, hy, hz) + d, pc)


# ------------------------------------------------------------------ fences

func _fences() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	_fence_run(vb, -13.0, 1.4, -6.5, true)
	_fence_run(vb, -10.0, 0.4, 4.85, false)
	# Short side return at the left foreground.
	_fence_side(vb, -10.0, 4.85, 7.5)
	V.inst(vb, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "Fence")


func _picket_col(q: Vector3i) -> Color:
	return V.shade(PICKET, 0.93 + V.h1(q, 21) * 0.1)


## Picket fence along X at depth z (metres). Pickets 3 cells wide, 1 gap.
func _fence_run(vb: VoxelBuilder, x0: float, x1: float, z: float, rails_front: bool) -> void:
	var zi := int(z * F)
	var h := 15
	var xs := int(x0 * F)
	var xe := int(x1 * F)
	var rz := zi + (1 if rails_front else -1)
	# Rails.
	for x in range(xs, xe):
		for ry in [4, 11]:
			vb.set_v(Vector3i(x, ry, rz), V.shade(PICKET, 0.86))
			vb.set_v(Vector3i(x, ry + 1, rz), V.shade(PICKET, 0.9))
	# Posts every ~2 m.
	var x := xs
	var k := 0
	while x < xe:
		if k % 8 == 0:
			for yy in h + 2:
				for dx in 3:
					for dz in 2:
						vb.set_v(Vector3i(x + dx, yy, zi + dz - (0 if rails_front else 1)), V.shade(PICKET, 0.95 + 0.04 * dz))
			vb.set_v(Vector3i(x + 1, h + 2, zi), PICKET)
		else:
			var ph := h - (1 if k % 2 == 0 else 0)
			for yy in ph:
				for dx in 3:
					var q := Vector3i(x + dx, yy, zi)
					vb.set_v(q, _picket_col(q))
			vb.set_v(Vector3i(x + 1, ph, zi), _picket_col(Vector3i(x + 1, ph, zi)))
		x += 4
		k += 1


func _fence_side(vb: VoxelBuilder, x: float, z0: float, z1: float) -> void:
	var xi := int(x * F)
	var h := 15
	for z in range(int(z0 * F), int(z1 * F)):
		for ry in [4, 11]:
			vb.set_v(Vector3i(xi + 1, ry, z), V.shade(PICKET, 0.86))
	var z := int(z0 * F)
	while z < int(z1 * F):
		for yy in h:
			for dz in 3:
				var q := Vector3i(xi, yy, z + dz)
				vb.set_v(q, _picket_col(q))
		vb.set_v(Vector3i(xi, h, z + 1), PICKET)
		z += 4


# ------------------------------------------------------------------ trees

func _trees() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.07
	# Behind the back fence.
	_tree(vb, Vector3(-11.5, 0, -8.4), 3.2, 2.0, 0)
	_tree(vb, Vector3(-4.6, 0, -10.5), 3.6, 2.2, 1)
	_tree(vb, Vector3(-15.0, 0, -3.0), 4.0, 2.5, 1)
	_tree(vb, Vector3(15.5, 0, -4.0), 4.2, 2.5, 0)
	# Hedge along the back fence (outside).
	var x := -13.0
	while x < 1.0:
		var hr := _rng.randf_range(0.6, 0.95)
		V.blob(vb, Vector3(x * M, hr * M * 0.9, -7.2 * M), Vector3(hr * M, hr * M * 1.1, 0.7 * M), V.leaves(int(x * 10) & 63, 1, 0), 0.45, int(x * 7) & 31)
		x += _rng.randf_range(0.7, 1.1)
	# Shrubs inside the yard.
	for s in [Vector3(-8.6, 0, -4.4), Vector3(13.2, 0, -0.8), Vector3(-12.2, 0, 2.6), Vector3(12.4, 0, 5.0), Vector3(-11.6, 0, -1.6)]:
		var rr := _rng.randf_range(0.5, 0.75)
		V.blob(vb, Vector3(s.x * M, rr * M, s.z * M), Vector3(rr * M, rr * M * 1.05, rr * M), V.leaves(int(s.x * 3) & 63, 0, 0), 0.4, int(s.z * 5) & 31)
	V.inst(vb, root, V.SIZE_MID, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "Trees")


func _tree(vb: VoxelBuilder, base: Vector3, height: float, crown: float, tone: int) -> void:
	var bx := int(base.x * M)
	var bz := int(base.z * M)
	var trunk_h := int(height * M * 0.6)
	var bark := Color("6b4a32")
	for y in trunk_h:
		var lean := int(sin(y * 0.15 + base.x) * 1.0)
		V.b(vb, bx - 1 + lean, y, bz - 1, 3, 1, 3, V.noisy(bark, 0.12, y))
	# Crown of overlapping blobs.
	var cy := height * M
	var cr := crown * M
	var leaf := V.leaves(int(base.x * 13) & 127, tone, int(cy - cr))
	V.blob(vb, Vector3(bx, cy, bz), Vector3(cr, cr * 0.8, cr), leaf, 0.35, tone)
	for i in 5:
		var a := i * 1.256 + base.x
		var off := Vector3(cos(a) * cr * 0.6, _rng.randf_range(-0.2, 0.35) * cr, sin(a) * cr * 0.6)
		V.blob(vb, Vector3(bx, cy, bz) + off, Vector3.ONE * cr * _rng.randf_range(0.45, 0.65), leaf, 0.4, i + tone)


# ------------------------------------------------------------------ neighbours

func _neighbours() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	var walls := [Color("b8a9c9"), Color("c9b9b0"), Color("a9a8c8"), Color("d2c2b2"), Color("b3a0b8")]
	var roofs := [Color("5a4e6a"), Color("6a4f55"), Color("4c4a62"), Color("5f5160")]
	var houses := [
		[-16.0, -17.0, 8.0, 6.0, 5.0, 0],
		[-6.5, -18.0, 7.0, 6.0, 5.5, 1],
		[1.0, -21.0, 7.0, 6.0, 5.0, 2],
		[-24.0, -26.0, 7.0, 6.0, 4.5, 3],
		[-12.0, -32.0, 8.0, 6.0, 5.0, 4],
		[9.0, -30.0, 8.0, 6.0, 5.5, 0],
	]
	for hd in houses:
		_house(vb, hd, walls[hd[5] % walls.size()], roofs[hd[5] % roofs.size()])
	# Distant tree line.
	for i in 18:
		var tx := -34.0 + i * 3.9 + _rng.randf_range(-1.0, 1.0)
		var tz := -36.0 + _rng.randf_range(-3.0, 3.0)
		var r := _rng.randf_range(1.6, 2.6)
		V.blob(vb, Vector3(tx * 4, r * 4 * 1.4, tz * 4), Vector3(r * 4, r * 4 * 1.3, r * 4), V.leaves(i, 3, 0), 0.4, i)
		V.b(vb, int(tx * 4), 0, int(tz * 4), 1, 3, 1, Color("4a3a30"))
	V.inst(vb, root, V.SIZE_BIG, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, "Neighbours")


func _house(vb: VoxelBuilder, hd: Array, wall: Color, roof: Color) -> void:
	var s := 4  # cells per metre at 0.25
	var x0 := int(hd[0] * s)
	var z0 := int(hd[1] * s)
	var w := int(hd[2] * s)
	var d := int(hd[3] * s)
	var h := int(hd[4] * s)
	V.b(vb, x0, 0, z0, w, h, d, V.wood(wall, 0, 1, 0.06))
	# Gable roof along X.
	var half := d / 2 + 1
	for k in half + 1:
		V.b(vb, x0 - 1, h + k, z0 - 1 + k, w + 2, 1, d + 2 - 2 * k, V.noisy(roof, 0.08, k))
	# Chimney.
	V.b(vb, x0 + w - 5, h + 2, z0 + d / 2, 2, half + 1, 2, Color("8a6a62"))
	# Lit windows on the front (+z) face, two floors.
	var floors := 2 if h >= 18 else 1
	for f in floors:
		var wy := 3 + f * 9
		var n := w / 7
		for i in n:
			var wx := x0 + 2 + i * 7
			var lit := V.hs(wx, wy, z0) < 0.7
			var gc := Color("ffcf7a") if lit else Color("6a6a8a")
			V.b(vb, wx, wy, z0 + d, 3, 4, 1, gc, lit)
			V.b(vb, wx - 1, wy - 1, z0 + d, 5, 1, 1, Color("efe8e0"))
			if lit:
				V.b(vb, wx + 1, wy, z0 + d, 1, 4, 1, V.shade(gc, 0.8), true)
