extends RefCounted
## Square furniture: lamp posts with maple banners, tiered fountain, string
## lights + bunting criss-crossing the square, flower barrels, ground lanterns,
## picnic tables, pumpkin piles and hay bales.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

## [x, z, banner]
const LAMPS := [
	[-2.3, -8.4, true],    # 0 tall lamp left of the walkway (ref: centre-left)
	[2.6, -10.6, true],    # 1 right of the fountain
	[-7.2, -3.4, false],   # 2 behind the FALL TREATS stall
	[5.6, -18.2, false],   # 3 behind the stage
	[-5.0, -15.5, false],  # 4 back left
	[5.4, -3.0, false],    # 5 right side, by the game booth
	[-4.4, -19.0, false],  # 6 far back by the town hall
]
const FOUNTAIN := Vector3(0.2, 0, -9.2)
const FOUNTAIN_SCALE := 1.3
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
	# Chunky tiered fountain: wide basin, thick pedestal, two bowls with
	# water spilling over their rims, a finial spout on top.
	K.cyl(vb, 0, 0, 0, 26.0, 2, stone)
	K.cyl(vb, 0, 2, 0, 25.0, 9, stone, false, 21.0)
	K.cyl(vb, 0, 11, 0, 25.5, 2, Color("b4afa4"), false, 20.5)
	K.cyl(vb, 0, 2, 0, 21.0, 7, water)
	# Pedestal + lower bowl.
	K.cyl(vb, 0, 9, 0, 6.0, 4, stone)
	K.cyl(vb, 0, 13, 0, 4.5, 16, stone)
	K.cyl(vb, 0, 29, 0, 8.0, 2, stone)
	K.cyl(vb, 0, 31, 0, 14.0, 3, stone)
	K.cyl(vb, 0, 34, 0, 14.5, 2, Color("b4afa4"), false, 12.0)
	K.cyl(vb, 0, 34, 0, 12.0, 1, water)
	# Upper stem + small bowl + finial.
	K.cyl(vb, 0, 35, 0, 3.0, 10, stone)
	K.cyl(vb, 0, 45, 0, 7.5, 2, stone)
	K.cyl(vb, 0, 47, 0, 8.0, 2, Color("b4afa4"), false, 6.0)
	K.cyl(vb, 0, 47, 0, 6.0, 1, water)
	K.cyl(vb, 0, 48, 0, 2.0, 5, stone)
	K.cyl(vb, 0, 53, 0, 1.2, 3, Color("a8d4ea"))
	# Water curtains falling from both bowls (sparse columns).
	for k in 28:
		var ang := TAU * k / 28.0
		var r1 := 14.6
		var x := int(round(cos(ang) * r1))
		var z := int(round(sin(ang) * r1))
		if k % 2 == 0:
			for y in range(11, 34):
				if posmod(y + k, 5) != 0:
					vb.set_v(Vector3i(x, y, z), Color("a8d4ea") if posmod(y, 3) else Color("cfe8f4"))
	for k in 16:
		var ang := TAU * (k + 0.5) / 16.0
		var x := int(round(cos(ang) * 8.4))
		var z := int(round(sin(ang) * 8.4))
		for y in range(36, 47):
			if posmod(y + k, 4) != 0:
				vb.set_v(Vector3i(x, y, z), Color("b8dcef"))
	K.pumpkin(vb, -22, 0, 18, 2.8, 2, 2)
	var fm := K.inst(parent, vb, U, FOUNTAIN, 0.0, true, Vector3.ZERO, "Fountain")
	fm.scale = Vector3.ONE * FOUNTAIN_SCALE


# ------------------------------------------------------------------ string lights

func _catenary(vb: VoxelBuilder, a: Vector3, b: Vector3, sag: float, bunting := false, bulbs := true) -> void:
	# a, b in metres. Wire + bulbs every ~0.45 m + optional bunting flags.
	var ca := a / SU
	var cb := b / SU
	var n := maxi(int((cb - ca).length()), 2)
	var wire := Color("3a3530")
	var bulb_every := 6
	var flag_cols := [Color("e2662a"), Color("f2b33a"), Color("c8401e"), Color("f6efe0"), Color("d8902a")]
	for i in n + 1:
		var t := float(i) / n
		var p := ca.lerp(cb, t)
		p.y -= sin(t * PI) * sag / SU
		var q := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		vb.set_v(q, wire)
		if bulbs and i % bulb_every == 3 and i > 2 and i < n - 2:
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
	var stage_fl := Vector3(4.1, 5.2, -14.2)   # stage truss front-left corner
	var runs := [
		# [a, b, sag, bunting]
		[L[0], L[1], 0.5, true],
		[L[0], L[5], 0.7, false],
		[L[2], L[0], 0.55, false],
		[L[2], Vector3(-3.9, 4.2, -0.4), 0.35, false],
		[L[1], stage_fl, 0.45, false],
		[L[5], L[1], 0.6, true],
		[L[5], Vector3(10.6, 3.6, -3.4), 0.4, false],
		[L[5], Vector3(8.6, 3.2, 1.8), 0.45, true],
		[L[4], L[0], 0.5, false],
		[L[4], L[1], 0.8, true],
		[L[4], L[6], 0.4, false],
		[L[3], Vector3(11.5, 4.6, -12.0), 0.4, true],
		[L[3], L[1], 0.6, false],
		[L[2], Vector3(-10.0, 4.4, -7.0), 0.4, false],
		[Vector3(-10.0, 4.4, -7.0), L[4], 0.5, true],
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
	K.box(vb, x - 2, 1, z - 2, 4, 9, 4, Color("ffa040"), true)
	K.box(vb, x - 3, 1, z - 2, 6, 9, 4, Color("ffb450"), true)
	K.box(vb, x - 2, 1, z - 3, 4, 9, 6, Color("ffa848"), true)
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
	# Flower barrels: foreground corners (framing, not blocking) + around the square.
	var barrels := [
		[-6.9, 2.6, 0], [-6.0, 3.5, 1], [-7.6, 0.4, 1],
		[-2.2, -6.2, 2], [2.0, -7.6, 0], [-3.2, -10.6, 1], [3.4, -12.6, 3], [7.4, -2.0, 2],
		[7.6, 3.4, 1], [2.6, 3.6, 0], [-1.8, -12.8, 2],
	]
	var i := 0
	for b: Array in barrels:
		_barrel_planter(near, int(b[0] * C), int(b[1] * C), 5.0, b[2], i)
		i += 1
	# Ground lanterns (small, along the walkway edges).
	for l in [[-7.0, 3.6], [-3.3, 2.9], [1.9, 3.1], [6.9, 0.2], [-2.0, -4.2], [1.9, -5.6], [-1.6, -11.6], [2.4, -11.6]]:
		_ground_lantern(near, int(l[0] * C), int(l[1] * C))
	# Picnic tables.
	_picnic_table(near, int(-5.0 * C), int(-8.0 * C))
	_picnic_table(near, int(3.9 * C), int(-7.2 * C))
	# Pumpkin piles + hay.
	var piles := [[-2.6, 3.4], [-1.4, -5.6], [1.6, -6.3], [-7.4, -1.8], [8.4, 0.2], [-1.9, -9.6], [6.0, -11.6]]
	var j := 0
	for p: Array in piles:
		var px := int(p[0] * C)
		var pz := int(p[1] * C)
		K.pumpkin(near, px, 0, pz, 4.0, j, j)
		K.pumpkin(near, px + 7, 0, pz + 3, 2.8, j + 1, j + 1)
		K.pumpkin(near, px - 4, 0, pz + 6, 2.4, j + 2, j + 3)
		j += 1
	K.hay(near, int(-7.9 * C), 0, int(-1.0 * C), 16, 9, 9)
	K.hay(near, int(-7.7 * C), 9, int(-0.8 * C), 12, 8, 7)
	K.hay(near, int(7.6 * C), 0, int(-5.6 * C), 16, 9, 9)
	K.hay(near, int(-2.6 * C), 0, int(-6.8 * C), 16, 9, 9)
	K.hay(near, int(1.4 * C), 0, int(-12.4 * C), 16, 9, 9)
	K.inst(parent, near, U, Vector3.ZERO, 0.0, true, Vector3.ZERO, "SquareProps")
