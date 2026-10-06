extends RefCounted
## Square furniture: lamp posts with maple banners, tiered fountain, string
## lights + bunting criss-crossing the square, flower barrels, ground lanterns,
## picnic tables, pumpkin piles and hay bales.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

## [x, z, banner]
const LAMPS := [
	[-1.6, -4.0, true],
	[1.7, -7.0, true],
	[-6.4, -5.6, false],
	[6.6, -15.0, false],
	[-4.2, -13.5, false],
]
const FOUNTAIN := Vector3(0.0, 0, -8.6)
const LAMP_TOP := 4.2
const SU := 0.06  # string-light cell size

var glow_points: Array = []
var lamp_heads: Array = []


func build(parent: Node3D) -> void:
	_lamps(parent)
	_fountain(parent)
	_strings(parent)
	_props(parent)


# ------------------------------------------------------------------ lamps

func _lamp_model(banner: bool) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var iron := Color("26231f")
	var iron2 := Color("3a3530")
	# Base.
	K.box(vb, -3, 0, -3, 6, 2, 6, iron2)
	K.box(vb, -2, 2, -2, 4, 6, 4, iron)
	K.box(vb, -3, 8, -3, 6, 1, 6, iron2)
	# Pole with collars.
	K.box(vb, -1, 9, -1, 2, 54, 2, iron)
	for y in [24, 44]:
		K.box(vb, -2, y, -2, 4, 1, 4, iron2)
	# Lantern head.
	var hy := 63
	K.box(vb, -3, hy, -3, 6, 1, 6, iron)
	K.box(vb, -4, hy + 9, -4, 8, 1, 8, iron)
	K.box(vb, -3, hy + 10, -3, 6, 1, 6, iron)
	K.box(vb, -2, hy + 11, -2, 4, 1, 4, iron)
	K.box(vb, -1, hy + 12, -1, 2, 2, 2, iron2)
	for c in [Vector2i(-3, -3), Vector2i(2, -3), Vector2i(-3, 2), Vector2i(2, 2)]:
		K.box(vb, c.x, hy + 1, c.y, 1, 8, 1, iron)
	K.box(vb, -2, hy + 1, -2, 4, 8, 4, Color("ffcf6a"), true)
	for c in [Vector2i(-3, -2), Vector2i(-3, 1), Vector2i(2, -2), Vector2i(2, 1), Vector2i(-2, -3), Vector2i(1, -3), Vector2i(-2, 2), Vector2i(1, 2)]:
		K.box(vb, c.x, hy + 2, c.y, 1, 6, 1, Color("ffe08a"), true)
	if banner:
		# Bracket arms and two vertical banners either side.
		for side in [-1, 1]:
			for i in 7:
				vb.set_v(Vector3i(side * (2 + i), 58, 0), iron)
				vb.set_v(Vector3i(side * (2 + i), 34, 0), iron)
			var bx0 := 3 if side > 0 else -11
			for x in range(bx0, bx0 + 8):
				for y in range(33, 58):
					var c := Color("f0b440")
					if x == bx0 or x == bx0 + 7:
						c = Color("d8822a")
					vb.set_v(Vector3i(x, y, 0), c)
			# Fringe.
			for x in range(bx0, bx0 + 8):
				if posmod(x, 2) == 0:
					vb.set_v(Vector3i(x, 32, 0), Color("f2b33a"))
			K.maple(vb, bx0 + 1 - 1 + 1, 46, 1, Color("c8381a"))
			K.maple(vb, bx0 + 1, 46, -1, Color("c8381a"))
			# Small second leaf lower down, like the reference banners.
			for k in 3:
				vb.set_v(Vector3i(bx0 + 2 + k, 38 + k, 1), Color("c8381a"))
				vb.set_v(Vector3i(bx0 + 2 + k, 38 + k, -1), Color("c8381a"))
				vb.set_v(Vector3i(bx0 + 3 + k, 37 + k, 1), Color("d8582a"))
				vb.set_v(Vector3i(bx0 + 3 + k, 37 + k, -1), Color("d8582a"))
	return vb


func _lamps(parent: Node3D) -> void:
	var with_banner := _lamp_model(true)
	var plain := _lamp_model(false)
	var all := VoxelBuilder.new()
	all.jitter = 0.0
	var i := 0
	for l: Array in LAMPS:
		all.stamp(with_banner if l[2] else plain, Vector3i(roundi(l[0] * 16.0), 0, roundi(l[1] * 16.0)))
		var head := Vector3(roundi(l[0] * 16.0) * U, 67.5 * U, roundi(l[1] * 16.0) * U)
		lamp_heads.append(head)
		glow_points.append([head, 1.5, Color(1.0, 0.72, 0.36)])
		glow_points.append([head, 0.6, Color(1.0, 0.85, 0.6)])
		i += 1
	K.inst(parent, all, U, Vector3.ZERO, 0.0, true, Vector3.ZERO, "LampPosts")


# ------------------------------------------------------------------ fountain

func _fountain(parent: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var stone := func(q: Vector3i) -> Color:
		var row := q.y / 3
		var c := K.pick([Color("8a867e"), Color("7a766e"), Color("96928a"), Color("6e6a64")], K.hs(q.x / 3, row, q.z / 3))
		if posmod(q.y, 3) == 0:
			c = K.shade(c, 0.88)
		return c
	var water := func(q: Vector3i) -> Color:
		return Color("7fb8d8") if posmod(q.x + q.z * 3, 7) != 0 else Color("a8d4ea")
	# Chunky tiered fountain: wide basin, thick pedestal, two bowls.
	K.cyl(vb, 0, 0, 0, 26.0, 2, stone)
	K.cyl(vb, 0, 2, 0, 25.0, 9, stone, false, 21.0)
	K.cyl(vb, 0, 11, 0, 25.5, 2, Color("b4afa4"), false, 20.5)
	K.cyl(vb, 0, 2, 0, 21.0, 7, water)
	# Pedestal and middle bowl.
	K.cyl(vb, 0, 9, 0, 6.0, 4, stone)
	K.cyl(vb, 0, 13, 0, 4.5, 14, stone)
	K.cyl(vb, 0, 27, 0, 7.0, 2, stone)
	K.cyl(vb, 0, 29, 0, 12.5, 4, stone, false, 10.0)
	K.cyl(vb, 0, 29, 0, 10.0, 3, water)
	K.cyl(vb, 0, 33, 0, 12.8, 1, Color("b4afa4"), false, 10.5)
	# Upper column + top bowl + finial.
	K.cyl(vb, 0, 32, 0, 3.0, 10, stone)
	K.cyl(vb, 0, 42, 0, 7.0, 3, stone, false, 5.0)
	K.cyl(vb, 0, 42, 0, 5.0, 2, water)
	K.cyl(vb, 0, 45, 0, 2.0, 5, stone)
	K.cyl(vb, 0, 50, 0, 3.0, 2, Color("b4afa4"))
	K.cyl(vb, 0, 52, 0, 1.5, 2, Color("b4afa4"))
	# Water curtains falling from the bowl rims.
	for a in 16:
		var ang := TAU * a / 16.0
		for r in [12.0, 6.5]:
			var x := int(round(cos(ang) * r))
			var z := int(round(sin(ang) * r))
			var y0 := 29 if r > 8.0 else 42
			for y in range(8 if r > 8.0 else 33, y0):
				if K.hs(x, y, z) > 0.55 and posmod(a, 2) == 0:
					vb.set_v(Vector3i(x, y, z), Color("cfeaf6") if K.hs(z, y, x) > 0.5 else Color("a8d4ea"))
	# Spray on top.
	for y in 6:
		vb.set_v(Vector3i(0, 54 + y, 0), Color("e0f4fc"))
	vb.set_v(Vector3i(1, 58, 0), Color("e0f4fc"))
	vb.set_v(Vector3i(-1, 57, 0), Color("e0f4fc"))
	vb.set_v(Vector3i(0, 58, 1), Color("e0f4fc"))
	# Mums and pumpkins around the rim.
	for a in 6:
		var ang := TAU * a / 6.0 + 0.3
		var x := cos(ang) * 31.0
		var z := sin(ang) * 31.0
		if z > 8.0 and absf(x) < 14.0:
			continue
		K.mums(vb, x, 0, z, 4.0, a % 3, a)
	K.pumpkin(vb, 18, 0, 24, 3.4, 1, 0)
	K.pumpkin(vb, -22, 0, 18, 2.8, 2, 2)
	K.inst(parent, vb, U, FOUNTAIN, 0.0, true, Vector3.ZERO, "Fountain")


# ------------------------------------------------------------------ string lights

func _catenary(vb: VoxelBuilder, a: Vector3, b: Vector3, sag: float, bunting := false, bulbs := true) -> void:
	# a, b in metres. Wire + bulbs every ~0.45 m + optional bunting flags.
	var ca := a / SU
	var cb := b / SU
	var n := maxi(int((cb - ca).length()), 2)
	var wire := Color("3a3530")
	var bulb_every := 8
	var flag_cols := [Color("e2662a"), Color("f2b33a"), Color("c8401e"), Color("f6efe0"), Color("d8902a")]
	for i in n + 1:
		var t := float(i) / n
		var p := ca.lerp(cb, t)
		p.y -= sin(t * PI) * sag / SU
		var q := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		vb.set_v(q, wire)
		if bulbs and i % bulb_every == 3:
			vb.set_v(q + Vector3i(0, -1, 0), Color("2a2622"))
			vb.set_v(q + Vector3i(0, -2, 0), Color("ffd070"), true)
			vb.set_v(q + Vector3i(0, -3, 0), Color("ffc050"), true)
			glow_points.append([(Vector3(q) + Vector3(0.5, -2.0, 0.5)) * SU, 0.55, Color(1.0, 0.72, 0.36)])
		if bunting and i % 8 == 0 and i > 3 and i < n - 3:
			var c: Color = flag_cols[(i / 8) % flag_cols.size()]
			var dir := (cb - ca).normalized()
			for row in 5:
				var half := 2.6 - row * 0.6
				for k in range(-int(half), int(half) + 1):
					var fp := p + dir * k + Vector3(0, -1 - row, 0)
					vb.set_v(Vector3i(floori(fp.x), floori(fp.y), floori(fp.z)), c)


func _strings(parent: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var L := []
	for l: Array in LAMPS:
		L.append(Vector3(l[0], LAMP_TOP + 0.1, l[1]))
	var runs := [
		# [a, b, sag, bunting]
		[L[0], Vector3(-3.6, 2.9, 1.4), 0.35, false],
		[L[0], L[1], 0.5, false],
		[L[0], L[2], 0.45, false],
		[L[0], Vector3(5.6, 2.7, 0.0), 0.6, false],
		[L[1], Vector3(7.0, 2.7, -4.0), 0.4, false],
		[L[1], L[3], 0.4, true],
		[L[2], L[4], 0.5, false],
		[L[4], L[1], 0.6, false],
		[L[2], Vector3(-8.4, 4.4, -1.4), 0.4, false],
		[L[3], Vector3(10.0, 4.8, -6.0), 0.4, true],
		[Vector3(7.6, 4.4, -4.6), Vector3(11.5, 3.6, 1.0), 0.4, true],
		[Vector3(4.2, 3.3, -1.2), Vector3(9.6, 3.0, 1.8), 0.35, true],
		[Vector3(4.2, 3.3, -1.2), Vector3(6.9, 3.4, -4.2), 0.3, true],
	]
	for r: Array in runs:
		_catenary(vb, r[0], r[1], r[2], r[3])
	K.inst(parent, vb, SU, Vector3.ZERO, 0.0, false, Vector3.ZERO, "StringLights")


# ------------------------------------------------------------------ props

func _barrel_planter(vb: VoxelBuilder, cx: int, cz: int, r: float, pal: int, seed: int) -> void:
	K.cyl(vb, cx, 0, cz, r, 11, func(q: Vector3i) -> Color:
		if q.y == 2 or q.y == 8:
			return Color("2f2b28")
		var ang := atan2(q.z - cz, q.x - cx)
		var stave := int((ang + PI) / TAU * 14.0)
		return K.shade(Color("7a4a2a"), 0.85 + K.hs(stave, seed, 3) * 0.25))
	K.mums(vb, cx, 10, cz, r + 0.6, pal, seed)


func _ground_lantern(vb: VoxelBuilder, x: int, z: int) -> void:
	# Iron floor lantern with warm amber glass (reads lit in daylight).
	var iron := Color("2a2622")
	K.box(vb, x - 3, 0, z - 3, 6, 1, 6, iron)
	for c in [Vector2i(-3, -3), Vector2i(2, -3), Vector2i(-3, 2), Vector2i(2, 2)]:
		K.box(vb, x + c.x, 1, z + c.y, 1, 9, 1, iron)
	K.box(vb, x - 2, 1, z - 2, 4, 9, 4, Color("ffb850"), true)
	K.box(vb, x - 3, 1, z - 2, 6, 9, 4, Color("ffc868"), true)
	K.box(vb, x - 2, 1, z - 3, 4, 9, 6, Color("ffc060"), true)
	K.box(vb, x - 3, 5, z - 3, 6, 1, 6, iron)
	K.box(vb, x - 4, 10, z - 4, 8, 1, 8, iron)
	K.box(vb, x - 3, 11, z - 3, 6, 1, 6, iron)
	K.box(vb, x - 1, 12, z - 1, 2, 2, 2, iron)
	glow_points.append([Vector3(x, 6, z) * U, 1.0, Color(1.0, 0.7, 0.35)])


func _picnic_table(vb: VoxelBuilder, x: int, z: int) -> void:
	var w := Color("a8743e")
	K.box(vb, x, 11, z, 28, 1, 12, K.wood(w, 0, 3))
	for lx in [x + 2, x + 24]:
		K.box(vb, lx, 0, z + 2, 2, 11, 2, Color("7a4a28"))
		K.box(vb, lx, 0, z + 8, 2, 11, 2, Color("7a4a28"))
	for bz in [z - 6, z + 14]:
		K.box(vb, x, 7, bz, 28, 1, 4, K.wood(w, 0, 2))
		K.box(vb, x + 2, 0, bz + 1, 2, 7, 2, Color("7a4a28"))
		K.box(vb, x + 24, 0, bz + 1, 2, 7, 2, Color("7a4a28"))
	# Cups and a plate.
	K.box(vb, x + 6, 12, z + 4, 2, 3, 2, Color("f2ead8"))
	K.box(vb, x + 18, 12, z + 6, 2, 3, 2, Color("d84a2a"))
	K.cyl(vb, x + 12.5, 12, z + 6.0, 2.5, 1, Color("f6f2ea"))
	K.cyl(vb, x + 12.5, 13, z + 6.0, 1.5, 1, Color("c87a34"))


func _props(parent: Node3D) -> void:
	var near := VoxelBuilder.new()
	near.jitter = 0.0
	var C := 16
	# Flower barrels (foreground left / right, around the square).
	var barrels := [
		[-5.0, 3.9, 0], [-4.1, 4.9, 1], [-6.3, 1.4, 1],
		[-2.6, -4.6, 2], [2.2, -10.4, 0], [-4.0, -8.6, 1], [4.8, -6.4, 3], [8.0, -1.0, 2],
		[-3.0, 4.1, 0], [3.9, 4.5, 0],
	]
	var i := 0
	for b: Array in barrels:
		_barrel_planter(near, int(b[0] * C), int(b[1] * C), 5.0, b[2], i)
		i += 1
	# Ground lanterns.
	for l in [[-6.0, 4.6], [6.6, 1.6], [1.0, -4.6], [4.7, 2.5], [-4.7, 2.3]]:
		_ground_lantern(near, int(l[0] * C), int(l[1] * C))
	# Picnic tables.
	_picnic_table(near, int(2.4 * C), int(-3.2 * C))
	_picnic_table(near, int(-4.8 * C), int(-9.6 * C))
	# Pumpkin piles + hay.
	var piles := [[-2.0, 3.9], [0.4, -5.2], [3.8, -5.6], [-7.4, -1.0], [8.6, 2.4]]
	var j := 0
	for p: Array in piles:
		var px := int(p[0] * C)
		var pz := int(p[1] * C)
		K.pumpkin(near, px, 0, pz, 4.0, j, j)
		K.pumpkin(near, px + 7, 0, pz + 3, 2.8, j + 1, j + 1)
		K.pumpkin(near, px - 4, 0, pz + 6, 2.4, j + 2, j + 3)
		j += 1
	K.hay(near, int(-7.6 * C), 0, int(-2.6 * C), 16, 9, 9)
	K.hay(near, int(-7.4 * C), 9, int(-2.4 * C), 12, 8, 7)
	K.hay(near, int(7.4 * C), 0, int(-6.6 * C), 16, 9, 9)
	K.hay(near, int(-0.6 * C), 0, int(-10.6 * C), 16, 9, 9)
	K.inst(parent, near, U, Vector3.ZERO, 0.0, true, Vector3.ZERO, "SquareProps")
