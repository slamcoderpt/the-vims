extends RefCounted
## Square furniture: lamp posts with maple banners, tiered fountain, string
## lights + bunting criss-crossing the square, flower barrels, ground lanterns,
## picnic tables, pumpkin piles and hay bales.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

## [x, z, banner]
const LAMPS := [
	[-5.0, -8.6, true],    # 0 tall banner lamp left of the fountain (ref: centre-left)
	[6.6, -9.0, false],    # 1 right of the stage
	[-7.2, -3.4, false],   # 2 behind the FALL TREATS stall
	[5.4, -3.0, false],    # 3 right side, by the game booth / crafts table
	[-7.6, 0.9, false],    # 4 bottom-left, among the barrels
	[-0.9, -9.23, false],  # 5 right of the fountain (= z -7.2 after dz), beside the clock tower
]
const FOUNTAIN := Vector3(-2.4, 0, -6.7)  # = (-2.4, K.dz(-8.27)); r12 camera: upper centre-left
const FOUNTAIN_SCALE := 0.84  # r13: spout stays below the clock face
const LAMP_TOP := 4.2
const SU := 0.06  # string-light wire cell size
const BU := 0.08  # bulb cell size
const FV := 1.5 / 16.0  # foreground dressing cell size

var stage_pos := Vector3(7.4, 0, -14.6)  # set by festival.gd before build()
var glow_points: Array = []
var lamp_heads: Array = []
var _wires: Array = []   # Array of PackedVector3Array polylines (metres)
var _wire_pts := PackedVector3Array()


func build(parent: Node3D) -> void:
	_lamps(parent)
	_fountain(parent)
	_strings(parent)
	_props(parent)
	_foreground(parent)


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
					var c := K.shade(Color("f4b24a"), 0.95 + K.hs(x, y / 3, 4) * 0.08)
					if x == bx0 or x == bx0 + 7:
						c = Color("c8561e")
					vb.set_v(Vector3i(x, y, 0), c)
			# Fringe.
			for x in range(bx0, bx0 + 8):
				if posmod(x, 2) == 0:
					vb.set_v(Vector3i(x, 32, 0), Color("d8822a"))
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
		all.stamp(with_banner if l[2] else plain, Vector3i(roundi(l[0] * 16.0), 0, roundi(K.dz(l[1]) * 16.0)))
		var head := Vector3(roundi(l[0] * 16.0) * U, 67.5 * U, roundi(K.dz(l[1]) * 16.0) * U)
		lamp_heads.append(head)
		glow_points.append([head, 2.2, Color(1.0, 0.7, 0.34)])
		glow_points.append([head, 0.6, Color(1.0, 0.85, 0.6)])
		i += 1
	K.inst(parent, all, U, Vector3.ZERO, 0.0, true, Vector3.ZERO, "LampPosts")


# ------------------------------------------------------------------ fountain

func _fountain(parent: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var stone := func(q: Vector3i) -> Color:
		var row := q.y / 3
		var c := K.pick([Color("8c8c8e"), Color("7c7c80"), Color("9a9a9c"), Color("707074")], K.hs(q.x / 3, row, q.z / 3))
		if posmod(q.y, 3) == 0:
			c = K.shade(c, 0.88)
		return c
	var water := func(q: Vector3i) -> Color:
		return Color("7fb8d8") if posmod(q.x + q.z * 3, 7) != 0 else Color("a8d4ea")
	# Chunky tiered fountain: wide basin, thick pedestal, two bowls with
	# water spilling over their rims, a finial spout on top.
	K.cyl(vb, 0, 0, 0, 26.0, 2, stone)
	K.cyl(vb, 0, 2, 0, 25.0, 9, stone, false, 21.0)
	K.cyl(vb, 0, 11, 0, 25.5, 2, Color("b2b2b4"), false, 20.5)
	K.cyl(vb, 0, 2, 0, 21.0, 7, water)
	# Pedestal + lower bowl.
	K.cyl(vb, 0, 9, 0, 6.0, 4, stone)
	K.cyl(vb, 0, 13, 0, 4.5, 16, stone)
	K.cyl(vb, 0, 29, 0, 8.0, 2, stone)
	K.cyl(vb, 0, 31, 0, 14.0, 3, stone)
	K.cyl(vb, 0, 34, 0, 14.5, 2, Color("b2b2b4"), false, 12.0)
	K.cyl(vb, 0, 34, 0, 12.0, 1, water)
	# Upper stem + small bowl + finial.
	K.cyl(vb, 0, 35, 0, 3.0, 10, stone)
	K.cyl(vb, 0, 45, 0, 7.5, 2, stone)
	K.cyl(vb, 0, 47, 0, 8.0, 2, Color("b2b2b4"), false, 6.0)
	K.cyl(vb, 0, 47, 0, 6.0, 1, water)
	K.cyl(vb, 0, 48, 0, 2.0, 5, stone)
	K.cyl(vb, 0, 53, 0, 1.2, 3, Color("a8d4ea"))
	# Water spilling over the bowl rims: short glossy drips + splash rings.
	for k in 36:
		var ang := TAU * k / 36.0
		var x := int(round(cos(ang) * 14.8))
		var z := int(round(sin(ang) * 14.8))
		var n := 2 + int(K.hs(k, 1, 9) * 4.0)
		if k % 2 == 0:
			for y in range(34 - n, 34):
				vb.set_v(Vector3i(x, y, z), Color("9fcfe6") if posmod(y + k, 2) else Color("c8e6f4"))
		if k % 3 == 0:
			var x2 := int(round(cos(ang) * 15.5))
			var z2 := int(round(sin(ang) * 15.5))
			for y in range(14, 20 + int(K.hs(k, 2, 9) * 5.0)):
				if posmod(y + k, 3) != 0:
					vb.set_v(Vector3i(x2, y, z2), Color("cfe8f4"))
	for k in 20:
		var ang := TAU * (k + 0.5) / 20.0
		var x := int(round(cos(ang) * 8.4))
		var z := int(round(sin(ang) * 8.4))
		if k % 2 == 0:
			for y in range(44 - int(K.hs(k, 3, 9) * 3.0), 47):
				vb.set_v(Vector3i(x, y, z), Color("a8d4ea"))
	# Spout plume on top.
	for y in range(56, 61):
		vb.set_v(Vector3i(0, y, 0), Color("e8f6fc"))
	for d in [Vector3i(1, 59, 0), Vector3i(-1, 59, 0), Vector3i(0, 59, 1), Vector3i(0, 59, -1)]:
		vb.set_v(d, Color("d8eef8"))
		vb.set_v(d * Vector3i(2, 1, 2) + Vector3i(0, -2, 0), Color("cfe8f4"))
	K.pumpkin(vb, -22, 0, 18, 2.8, 2, 2)
	var fm := K.inst(parent, vb, U, FOUNTAIN, 0.0, true, Vector3.ZERO, "Fountain")
	fm.scale = Vector3.ONE * FOUNTAIN_SCALE


# ------------------------------------------------------------------ string lights

func _catenary(vb: VoxelBuilder, bv: VoxelBuilder, a: Vector3, b: Vector3, sag: float, bunting := false, bulbs := true) -> void:
	# a, b in metres. Thin wire + round-ish glowing bulbs every ~0.42 m
	# (bulbs live in their own coarser builder) + optional bunting flags.
	var ca := a / SU
	var cb := b / SU
	var n := maxi(int((cb - ca).length()), 2)
	var bulb_every := 6
	var flag_cols := [Color("e2662a"), Color("f6efe0"), Color("c8401e"), Color("7a4a2e"), Color("f2a33a")]
	_wire_pts = PackedVector3Array()
	_wires.append(_wire_pts)
	for i in n + 1:
		var t := float(i) / n
		var p := ca.lerp(cb, t)
		p.y -= sin(t * PI) * sag / SU
		var q := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		# Wire itself is a thin tube mesh (see _wire_mesh): far cheaper than
		# a chain of voxels.
		if i % 4 == 0 or i == n:
			_wire_pts.append((Vector3(q) + Vector3(0.5, 0.5, 0.5)) * SU)
		if bulbs and i % bulb_every == 3 and i > 2 and i < n - 2:
			vb.set_v(q + Vector3i(0, -1, 0), Color("2a2622"))
			var m := (Vector3(q) + Vector3(0.5, -1.0, 0.5)) * SU   # socket bottom (m)
			var bq := Vector3i(floori(m.x / BU - 1.0), floori(m.y / BU) - 2, floori(m.z / BU - 1.0))
			for bx in 2:
				for bz in 2:
					bv.set_v(bq + Vector3i(bx, 1, bz), Color("ffd27a"), true)
					bv.set_v(bq + Vector3i(bx, 0, bz), Color("ffc456"), true)
			glow_points.append([(Vector3(bq) + Vector3(1.0, 1.0, 1.0)) * BU, 0.85, Color(1.0, 0.74, 0.38)])
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
		L.append(Vector3(l[0], LAMP_TOP + 0.1, K.dz(l[1])))
	var stage_fl := stage_pos + Vector3(-2.7, 4.4, 0.3)   # stage truss front-left corner
	# Round 7: fewer, cleaner runs. Nothing crosses the walkway at head
	# height in front of the fountain / stage any more (the old web of
	# strings + oversized bulbs read as a yellow smear over the backdrop).
	var stage_fr := stage_pos + Vector3(2.0, 4.4, 0.0)    # front-right corner
	# r13: runs kept out of the clock-tower window (screen x 800-950,
	# y < 110) so the backdrop reads; garlands hang across the left of the
	# frame, from the banner lamp over to the stage, and down the right side.
	var low0 := Vector3(L[0].x, 2.75, L[0].z)
	var runs := [
		# [a, b, sag, bunting]
		[L[2], L[0], 0.45, false],
		[low0, stage_fl + Vector3(0, -1.45, 0), 0.35, true],
		[L[1], stage_fr, 0.3, false],
		[L[5], stage_fl, 0.3, false],
		[L[3], stage_fr, 0.45, false],
		[L[3], Vector3(9.4, 3.4, 0.6), 0.35, true],
		[L[4], L[2], 0.4, false],
		[L[2], Vector3(-11.0, 4.2, -5.2), 0.4, true],
		[L[0], Vector3(-9.6, 4.6, -8.4), 0.45, false],
	]
	var bv := VoxelBuilder.new()
	bv.jitter = 0.0
	for r: Array in runs:
		_catenary(vb, bv, r[0], r[1], r[2], r[3])
	K.inst(parent, vb, SU, Vector3.ZERO, 0.0, false, Vector3.ZERO, "StringLights")
	K.inst(parent, bv, BU, Vector3.ZERO, 0.0, false, Vector3.ZERO, "StringBulbs")
	_wire_mesh(parent)


## All string-light wires as one mesh of thin square tubes.
func _wire_mesh(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.02
	for pl: PackedVector3Array in _wires:
		for k in pl.size() - 1:
			var a := pl[k]
			var b := pl[k + 1]
			var d := (b - a).normalized()
			var u := d.cross(Vector3.UP).normalized() * hw
			var v := u.cross(d).normalized() * hw
			var sides := [[v, u], [u, -v], [-v, -u], [-u, v]]
			for sd: Array in sides:
				var o0: Vector3 = sd[0] + sd[1]
				var o1: Vector3 = sd[0] - sd[1]
				var nrm: Vector3 = (sd[0] as Vector3).normalized()
				st.set_normal(nrm)
				st.add_vertex(a + o0)
				st.add_vertex(b + o0)
				st.add_vertex(b + o1)
				st.add_vertex(a + o0)
				st.add_vertex(b + o1)
				st.add_vertex(a + o1)
	var mi := MeshInstance3D.new()
	mi.name = "StringWires"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a2622")
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ------------------------------------------------------------------ props

func _barrel_planter(vb: VoxelBuilder, cx: int, cz: int, r: float, pal: int, seed: int) -> void:
	K.cyl(vb, cx, 0, cz, r, 11, func(q: Vector3i) -> Color:
		if q.y == 2 or q.y == 8:
			return Color("2f2b28")
		var ang := atan2(q.z - cz, q.x - cx)
		var stave := int((ang + PI) / TAU * 14.0)
		return K.shade(Color("7a4a2a"), 0.85 + K.hs(stave, seed, 3) * 0.25))
	K.mums(vb, cx, 10, cz, r + 0.6, pal, seed)


func _ground_lantern(vb: VoxelBuilder, x: int, z: int, y0 := 0, cs := U) -> void:
	# Iron floor lantern with warm amber glass (reads lit in daylight).
	var iron := Color("2a2622")
	var y := y0
	K.box(vb, x - 3, y, z - 3, 6, 1, 6, iron)
	for c in [Vector2i(-3, -3), Vector2i(2, -3), Vector2i(-3, 2), Vector2i(2, 2)]:
		K.box(vb, x + c.x, y + 1, z + c.y, 1, 9, 1, iron)
	# Glass glows hottest round the flame (mid height), amber at the rims.
	var glass := func(q: Vector3i) -> Color:
		var t := clampf(1.0 - absf(float(q.y - y) - 4.5) / 4.5, 0.0, 1.0)
		var edge := absi(q.x - x) >= 2 or absi(q.z - z) >= 2
		return Color("ff9a38").lerp(Color("fff1b8"), t * (0.75 if edge else 1.0))
	K.box(vb, x - 2, y + 1, z - 2, 4, 9, 4, glass, true)
	K.box(vb, x - 3, y + 1, z - 2, 6, 9, 4, glass, true)
	K.box(vb, x - 2, y + 1, z - 3, 4, 9, 6, glass, true)
	K.box(vb, x - 3, y + 5, z - 3, 6, 1, 6, iron)
	K.box(vb, x - 4, y + 10, z - 4, 8, 1, 8, iron)
	K.box(vb, x - 3, y + 11, z - 3, 6, 1, 6, iron)
	K.box(vb, x - 1, y + 12, z - 1, 2, 2, 2, iron)
	K.box(vb, x - 1, y + 14, z, 2, 1, 1, iron)
	var gk := cs / U
	glow_points.append([Vector3(x, y + 6, z) * cs, 1.5 * gk, Color(1.0, 0.7, 0.35)])
	glow_points.append([Vector3(x, y + 5, z) * cs, 0.6 * gk, Color(1.0, 0.86, 0.6)])
	if cs > U:
		# Near-camera lanterns: an extra halo in front of the glass (the
		# centre one is depth-hidden inside it) so they read as lit.
		glow_points.append([Vector3(x, y + 5.5, z + 5) * cs, 1.9, Color(1.0, 0.62, 0.3)])


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
		[-0.4, -6.0, 2], [5.6, -6.4, 0], [7.4, -2.0, 2],
		[-2.7, -11.6, 1], [3.1, -12.2, 2],
	]
	var i := 0
	for b: Array in barrels:
		_barrel_planter(near, int(b[0] * C), int(K.dz(b[1]) * C), 5.0, b[2], i)
		i += 1
	# Ground lanterns (small, along the walkway edges).
	for l in [[-3.55, 0.35], [2.0, -1.3], [-2.0, -4.2], [1.9, -5.6], [-4.4, -9.4], [5.2, -9.6]]:
		_ground_lantern(near, int(l[0] * C), int(K.dz(l[1]) * C))
	# Picnic tables.
	_picnic_table(near, int(6.6 * C), int(K.dz(-7.0) * C))
	# Pumpkin piles + hay.
	var piles := [[-0.2, -5.4], [6.2, -5.0], [-4.3, -10.6], [6.0, -11.6]]
	var j := 0
	for p: Array in piles:
		var px := int(p[0] * C)
		var pz := int(K.dz(p[1]) * C)
		K.pumpkin(near, px, 0, pz, 4.0, j, j)
		K.pumpkin(near, px + 7, 0, pz + 3, 2.8, j + 1, j + 1)
		K.pumpkin(near, px - 4, 0, pz + 6, 2.4, j + 2, j + 3)
		j += 1
	K.hay(near, int(7.6 * C), 0, int(K.dz(-5.6) * C), 16, 9, 9)
	K.hay(near, int(-5.6 * C), 0, int(K.dz(-6.2) * C), 16, 9, 9)
	K.hay(near, int(-3.6 * C), 0, int(K.dz(-12.4) * C), 16, 9, 9)
	# r13: bottom-left corner cluster (below the HUD portraits): mum barrels,
	# cider barrels, a crate of apples, pumpkins, hay and a glowing lantern.
	for b: Array in [[-7.1, 1.7, 0, 6.5], [-6.0, 2.75, 2, 6.0], [-8.4, 0.3, 1, 6.0], [-4.9, 3.5, 1, 5.5]]:
		_barrel_planter(near, int(b[0] * C), int(b[1] * C), b[3], b[2], i)
		i += 1
	_cider_barrel(near, int(-8.0 * C), int(2.5 * C))
	_cider_barrel(near, int(-6.6 * C), int(0.4 * C))
	_crate_box(near, int(-5.9 * C), int(1.0 * C), 10, 7, 8)
	for k in 6:
		_apple_pile(near, int(-5.9 * C) + 2 + (k % 3) * 3, 7, int(1.0 * C) + 2 + (k / 3) * 3)
	K.hay(near, int(-9.2 * C), 0, int(1.6 * C), 16, 9, 9)
	K.pumpkin(near, int(-8.6 * C), 9, int(1.9 * C), 3.4, 21, 0)
	K.pumpkin(near, int(-5.3 * C), 0, int(2.0 * C), 3.6, 22, 1)
	K.pumpkin(near, int(-4.7 * C), 0, int(2.5 * C), 2.6, 23, 2)
	_ground_lantern(near, int(-6.3 * C), int(1.6 * C))
	_ground_lantern(near, int(1.45 * C), int(1.75 * C))
	# A bench by the fountain + mums along the walkway edges.
	_bench(near, int(-5.6 * C), int(-4.6 * C))
	_barrel_planter(near, int(0.9 * C), int(-2.2 * C), 5.0, 0, 41)
	_barrel_planter(near, int(-3.2 * C), int(-4.0 * C), 5.0, 2, 42)
	# (Round 11: dressing outside the preset frame (far left under the HUD,
	# below the frame bottom) was dropped to stay under the triangle budget.)
	# (Round 10: the round-9 pumpkin display / far-left hay sat outside the
	# tighter eye-level frame and were dropped to fund finer tree leaves.)
	K.inst(parent, near, U, Vector3.ZERO, 0.0, true, Vector3.ZERO, "SquareProps")


# ------------------------------------------------------------------ foreground

## Near-camera set dressing along the bottom edge of the festival shot
## (ref2: flower barrels with orange mums, glowing lanterns, pumpkins and
## hay in the near corners, softened by the tilt-shift band). Kept to the
## corners + a couple of lanterns so the walkway to the heroes stays open.
func _foreground(parent: Node3D) -> void:
	# Chunkier cells (1.5x) than the rest of the square: these sit closest to
	# the lens, so they read big and soft like the ref's corner dressing.
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var C := 1.0 / FV
	# r12 (standard game camera, frame bottom at z ~0.5 (right) .. 1.6
	# (left)): soft corner dressing along the bottom edge, below the heroes'
	# feet, leaving the walkway between Jack, Lily and Maya open.
	# Bottom-centre: mums + pumpkins between Biscuit and Maya.
	K.mums(vb, -0.45 * C, 0, 1.3 * C, 3.6, 1, 48)
	K.pumpkin(vb, int(0.3 * C), 0, int(1.2 * C), 2.4, 11, 2)
	K.pumpkin(vb, int(-1.0 * C), 0, int(1.55 * C), 1.8, 12, 0)
	K.pumpkin(vb, int(0.85 * C), 0, int(1.45 * C), 1.7, 10, 1)
	# Bottom-left (beside the menu board): hay bale with pumpkins + mums.
	K.hay(vb, int(-3.3 * C), 0, int(1.9 * C), 10, 6, 6)
	K.pumpkin(vb, int(-2.75 * C), 6, int(2.15 * C), 2.2, 3, 0)
	K.pumpkin(vb, int(-2.3 * C), 0, int(2.05 * C), 2.6, 4, 1)
	# Bottom-right: mums and pumpkins between Maya and the HANDMADE board.
	K.mums(vb, 2.55 * C, 0, 1.35 * C, 3.4, 0, 45)
	K.pumpkin(vb, int(2.1 * C), 0, int(1.5 * C), 2.0, 7, 2)
	K.inst(parent, vb, FV, Vector3.ZERO, 0.0, true, Vector3.ZERO, "Foreground")


func _apple_pile(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	var c := Color("c8281e") if posmod(x + z, 3) != 0 else Color("e8a030")
	K.box(vb, x, y, z, 2, 2, 2, K.noisy(c, 0.1, x * 7 + z))


func _bench(vb: VoxelBuilder, x: int, z: int) -> void:
	var w := Color("a8743e")
	var iron := Color("2a2622")
	K.box(vb, x, 7, z, 24, 1, 6, K.wood(w, 0, 2))
	K.box(vb, x, 8, z, 24, 6, 1, K.wood(w, 0, 2))
	for lx in [x + 1, x + 21]:
		K.box(vb, lx, 0, z, 2, 7, 1, iron)
		K.box(vb, lx, 0, z + 5, 2, 7, 1, iron)
		K.box(vb, lx, 7, z - 1, 2, 8, 1, iron)


func _crate_box(vb: VoxelBuilder, x: int, z: int, w: int, h: int, d: int) -> void:
	K.box(vb, x, 0, z, w, h, d, K.wood(Color("b07a44"), 2, 2))
	for yy in [0, h - 1]:
		K.box(vb, x, yy, z + d - 1, w, 1, 1, Color("7a4a28"))


func _cider_barrel(vb: VoxelBuilder, cx: int, cz: int) -> void:
	K.cyl(vb, cx, 0, cz, 5.5, 14, func(q: Vector3i) -> Color:
		if q.y == 2 or q.y == 11:
			return Color("2f2b28")
		var bulge := 0.85 + 0.1 * (1.0 - absf(q.y - 7.0) / 7.0)
		var ang := atan2(q.z - cz, q.x - cx)
		var stave := int((ang + PI) / TAU * 16.0)
		return K.shade(Color("8a5430"), bulge + K.hs(stave, cx, 5) * 0.2))
	K.cyl(vb, cx, 14, cz, 4.5, 1, Color("6a4026"))
