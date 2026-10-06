extends RefCounted
## Backyard landscape: lawn, pavers, flower beds, picket fences, trees,
## hedges and the silhouetted neighbour houses against the sunset.

const V := preload("res://scripts/locations/backyard/vox.gd")
const FastBuilder := preload("res://scripts/locations/backyard/fast_builder.gd")

const M := 8    # cells per metre at 0.125
const F := 16   # cells per metre at 0.0625
const T := 4    # cells per metre at 0.25

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
	[-9.6, 0.6, -6.6, 3.1, 1.1],       # left planter by the grill patio
	[0.9, 4.25, 8.6, 5.6, 1.2],        # centre foreground (bottom of the bbq shot)
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
	# The flat lawn is one textured quad (1 texel = one 0.125 m "voxel" top),
	# which keeps the per-cell colour variation for ~2 triangles.
	var x0 := -14.0
	var z0 := -7.0
	var w := 29 * M
	var h := 15 * M
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for iz in h:
		for ix in w:
			var wx := x0 + (ix + 0.5) / M
			var wz := z0 + (iz + 0.5) / M
			var q := Vector3i(ix, 0, iz)
			var pv := _paver(wx, wz)
			var c: Color
			if _in_bed(wx, wz):
				c = V.shade(Color("4a3020"), 0.8 + V.h1(q, 4) * 0.35)
			elif pv == 1:
				c = V.shade(Color("b8a88e"), 0.78 + V.h1(Vector3i(int(wx * 2), 0, int(wz * 2)), 5) * 0.25 + V.h1(q, 6) * 0.08)
			elif pv == 2:
				c = V.shade(Color("6b7a45"), 0.9 + V.h1(q, 7) * 0.2)
			else:
				var patch := sin(wx * 0.9 + 1.3) * cos(wz * 1.1) * 0.06 + sin(wx * 2.7 + wz * 1.9) * 0.04
				c = V.shade(GRASS[int(V.h1(q, 1) * GRASS.size()) % GRASS.size()], (1.0 + patch) * (0.95 + V.h1(q, 2) * 0.1))
				var r := V.h1(q, 9)
				if r < 0.006:
					c = Color("f6f2e8")
				elif r < 0.01:
					c = Color("e8d44d")
			img.set_pixel(ix, iz, c)
	_ground_quad(img, Vector3(x0, 0.0, z0), Vector2(29, 15), "Lawn")
	# Coarse ground beyond the yard (neighbour lawns), 0.5 m texels.
	var fimg := Image.create(88, 80, false, Image.FORMAT_RGB8)
	for iz in 80:
		for ix in 88:
			var q := Vector3i(ix, 1, iz)
			fimg.set_pixel(ix, iz, V.shade(GRASS[int(V.h1(q, 2) * GRASS.size()) % GRASS.size()], 0.72 + V.h1(q, 3) * 0.12))
	# One mesh / one draw call for all the surrounding ground (texture repeats).
	_ground_quad(fimg, Vector3(-30.0, -0.02, -40.0), Vector2(60, 60), "OuterGround", Vector2(60.0 / 44.0, 60.0 / 40.0))
	# Bed edging: stone border (voxels, perimeter only).
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
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
	V.inst(vb, root, V.SIZE_MID, Vector3.ZERO, 0.0, Vector3.ZERO, false, true, "BedEdging")


func _ground_quad(img: Image, corner: Vector3, size: Vector2, nm: String, uv_scale := Vector2.ONE) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0, 0), Vector3(size.x, 0, 0), Vector3(size.x, 0, size.y), Vector3(0, 0, size.y)]
	var uvs := [Vector2(0, 0), Vector2(uv_scale.x, 0), uv_scale, Vector2(0, uv_scale.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(corner + pts[i])
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.roughness = 0.9
	mat.metallic_specular = 0.2
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ flowers

func _species(wx: float, wz: float) -> int:
	# Flowers grow in clumps: species picked per ~0.7 m patch.
	var r := V.hs(floori(wx / 0.7), 3, floori(wz / 0.7))
	if r < 0.36:
		return 0          # lavender spikes
	elif r < 0.6:
		return 1          # pink cosmos
	elif r < 0.78:
		return 2          # white daisies
	elif r < 0.92:
		return 3          # yellow
	return 4              # pink pom-pom


func _beds() -> void:
	# Foliage: bumpy heightfield at 0.125 (cheap: neighbours hide sides).
	var leaf := FastBuilder.new()
	leaf.jitter = 0.0
	leaf.skip_down_below = 0
	for r in BEDS:
		var bx0 := int(floor(r[0] * M)) + 1
		var bx1 := int(ceil(r[2] * M)) - 1
		var bz0 := int(floor(r[1] * M)) + 1
		var bz1 := int(ceil(r[3] * M)) - 1
		for x in range(bx0, bx1):
			for z in range(bz0, bz1):
				var n := sin(x * 0.7 + z * 0.3) * 0.5 + sin(z * 0.9 - x * 0.4) * 0.5
				var hh := 1 + int(clampf((n + 1.0) * 0.5 + V.hs(x, 7, z) * 0.9, 0.0, 1.99) * 1.5)
				for y in hh:
					var q := Vector3i(x, y, z)
					var tone := V.hs(x / 2, y, z / 2)
					var c: Color = [Color("3f7d34"), Color("4c9140"), Color("356b2e"), Color("5aa548"), Color("467f37")][int(tone * 5.0) % 5]
					leaf.set_v(q, V.shade(c, 0.85 + 0.12 * y))
	V.inst(leaf, root, V.SIZE_MID, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "BedFoliage")
	# Blooms at 0.0625 sitting on the foliage.
	var vb := VoxelBuilder.new()
	vb.jitter = 0.06
	for r in BEDS:
		var area: float = (r[2] - r[0]) * (r[3] - r[1])
		var n := int(area * 10.0 * r[4])
		for i in n:
			var wx := _rng.randf_range(r[0] + 0.15, r[2] - 0.15)
			var wz := _rng.randf_range(r[1] + 0.15, r[3] - 0.15)
			var cx := int(floor(wx * M))
			var cz := int(floor(wz * M))
			var top := 0
			while leaf.has(Vector3i(cx, top, cz)):
				top += 1
			_bloom(vb, int(wx * F), top * 2, int(wz * F), _species(wx, wz), _rng.randi())
	# Loose grass tufts on the lawn.
	for i in 450:
		var wx := _rng.randf_range(-12.5, 14.0)
		var wz := _rng.randf_range(-6.3, 6.0)
		if _in_bed(wx, wz) or _paver(wx, wz) != 0:
			continue
		var x := int(wx * F)
		var z := int(wz * F)
		var g: Color = GRASS[_rng.randi() % GRASS.size()]
		vb.set_v(Vector3i(x, 0, z), V.shade(g, 1.08))
		if _rng.randf() < 0.5:
			vb.set_v(Vector3i(x, 1, z), V.shade(g, 1.15))
		if _rng.randf() < 0.08:
			vb.set_v(Vector3i(x, 1, z), WHITES[0])
	V.inst(vb, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, false, true, "Flowers")


## One bloom group on top of the foliage at fine grid (x, y, z).
func _bloom(vb: VoxelBuilder, x: int, y: int, z: int, kind: int, seed: int) -> void:
	match kind:
		0:
			var spikes := 2 + (seed >> 9) % 3
			for i in spikes:
				var sx := x + ((seed >> (i * 2)) % 3) - 1
				var sz := z + ((seed >> (i * 2 + 3)) % 3) - 1
				var sh := 3 + ((seed >> (i + 4)) % 4)
				vb.set_v(Vector3i(sx, y, sz), Color("4c8a35"))
				for k in sh:
					var c: Color = PURPLES[(seed + i + k) % PURPLES.size()]
					vb.set_v(Vector3i(sx, y + 1 + k, sz), V.shade(c, 0.85 + 0.05 * k))
		4:
			var cc: Color = PINKS[(seed >> 4) % PINKS.size()]
			V.b(vb, x - 1, y + 1, z - 1, 3, 2, 3, V.mix([cc, V.shade(cc, 1.15), V.shade(cc, 0.85)], seed % 13))
			vb.set_v(Vector3i(x, y + 3, z), V.shade(cc, 1.1))
			vb.set_v(Vector3i(x, y, z), Color("4c8a35"))
		_:
			var pal: Array = PINKS if kind == 1 else (WHITES if kind == 2 else YELLOWS)
			var heads := 1 + (seed >> 6) % 2
			for i in heads:
				var hx := x + ((seed >> (i * 3)) % 5) - 2
				var hz := z + ((seed >> (i * 3 + 2)) % 5) - 2
				var hy := y + 1 + ((seed >> (i + 2)) % 2)
				var pc: Color = pal[(seed + i) % pal.size()]
				vb.set_v(Vector3i(hx, hy - 1, hz), Color("4c8a35"))
				vb.set_v(Vector3i(hx, hy, hz), Color("f2b630") if kind != 3 else Color("8a5a24"))
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					vb.set_v(Vector3i(hx, hy, hz) + d, pc)


# ------------------------------------------------------------------ fences

func _fences() -> void:
	var vb := FastBuilder.new()
	vb.jitter = 0.0
	vb.skip_down_below = 0
	_fence_run(vb, -13.0, 1.4, -6.5, true)
	_fence_run(vb, -10.0, 0.4, 4.85, false)
	# Short side return at the left foreground.
	_fence_side(vb, -10.0, 4.85, 7.5)
	V.inst(vb, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "Fence")


func _picket_col(q: Vector3i) -> Color:
	# One tone per picket (keeps faces mergeable), slight weathering near the ground.
	var c := V.shade(PICKET, 0.93 + V.hs(q.x / 4, q.z / 4, 21) * 0.08)
	return V.shade(c, 0.92) if q.y < 2 else c


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
	# Canopies at 0.25 m: chunky leaves, a fraction of the triangles.
	var vb := VoxelBuilder.new()
	vb.jitter = 0.08
	_tree(vb, Vector3(-10.5, 0, -8.6), 3.4, 1.9, 4)
	_tree(vb, Vector3(-17.0, 0, -9.0), 3.6, 2.2, 4)
	_tree(vb, Vector3(-15.0, 0, -3.0), 4.0, 2.5, 1)
	_tree(vb, Vector3(-5.5, 0, -10.0), 3.6, 1.9, 4)
	_tree(vb, Vector3(15.5, 0, -4.0), 4.2, 2.5, 0)
	# Hedge along the back fence (outside).
	var x := -13.0
	while x < 1.0:
		var hr := _rng.randf_range(0.6, 0.95)
		V.blob(vb, Vector3(x * T, hr * T * 0.9, -7.2 * T), Vector3(hr * T, hr * T * 1.1, 0.7 * T), V.leaves(int(x * 10) & 63, 1, 0), 0.3, int(x * 7) & 31)
		x += _rng.randf_range(0.8, 1.2)
	# Shrubs inside the yard.
	for sp in [Vector3(-8.6, 0, -4.4), Vector3(13.2, 0, -0.8), Vector3(-11.6, 0, -1.6), Vector3(-11.0, 0, 3.0)]:
		var rr := _rng.randf_range(0.55, 0.8)
		V.blob(vb, Vector3(sp.x * T, rr * T, sp.z * T), Vector3(rr * T, rr * T * 1.05, rr * T), V.leaves(int(sp.x * 3) & 63, 0, 0), 0.3, int(sp.z * 5) & 31)
	V.inst(vb, root, V.SIZE_BIG, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "Trees")


func _tree(vb: VoxelBuilder, base: Vector3, height: float, crown: float, tone: int) -> void:
	var bx := int(base.x * T)
	var bz := int(base.z * T)
	var trunk_h := int(height * T * 0.7)
	var bark := Color("6b4a32")
	for y in trunk_h:
		V.b(vb, bx, y, bz, 1, 1, 1, V.noisy(bark, 0.12, y))
	var cy := height * T
	var cr := crown * T
	var leaf := V.leaves(int(base.x * 13) & 127, tone, int(cy - cr))
	V.blob(vb, Vector3(bx + 0.5, cy, bz + 0.5), Vector3(cr, cr * 0.8, cr), leaf, 0.3, tone)
	for i in 4:
		var a := i * 1.57 + base.x
		var off := Vector3(cos(a) * cr * 0.55, _rng.randf_range(-0.2, 0.3) * cr, sin(a) * cr * 0.55)
		V.blob(vb, Vector3(bx + 0.5, cy, bz + 0.5) + off, Vector3.ONE * cr * _rng.randf_range(0.45, 0.6), leaf, 0.3, i + tone, true)


# ------------------------------------------------------------------ neighbours

func _neighbours() -> void:
	# A row of dusky neighbour houses along the horizon (silhouettes against
	# the sunset with warm lit windows), with dark tree clumps between them.
	var vb := FastBuilder.new()
	vb.jitter = 0.0
	vb.skip_down_below = 0
	vb.skip_normals = [Vector3i(0, 0, -1)]
	var walls := [Color("4c4664"), Color("57496a"), Color("454a68"), Color("5c4c66"), Color("4a4260")]
	var roofs := [Color("2a2438"), Color("32263a"), Color("262636"), Color("2e2434")]
	# x, z, width, depth, wall height (m), style
	var houses := [
		[-46.0, -40.0, 9.0, 7.0, 5.0, 0],
		[-34.0, -44.0, 8.0, 6.0, 3.5, 1],
		[-24.0, -40.0, 9.0, 7.0, 5.0, 2],
		[-13.0, -43.0, 7.0, 6.0, 3.5, 3],
		[-4.0, -40.0, 8.0, 7.0, 5.0, 4],
		[6.0, -45.0, 8.0, 6.0, 5.0, 1],
		[18.0, -42.0, 9.0, 7.0, 5.0, 2],
	]
	for hd in houses:
		_house(vb, hd, walls[hd[5] % walls.size()], roofs[hd[5] % roofs.size()])
	# No AO on the distant row: it is blurred anyway, and flat faces merge
	# into a handful of quads.
	var nmi := MeshInstance3D.new()
	nmi.name = "Neighbours"
	nmi.mesh = vb.build(V.SIZE_BIG, Vector3.ZERO, false)
	nmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not vb.glow.is_empty():
		nmi.set_surface_override_material(nmi.mesh.get_surface_count() - 1, V.glow_soft())
	root.add_child(nmi)
	# Dark tree clumps at 0.5 m: between and behind the houses.
	var tl := VoxelBuilder.new()
	tl.jitter = 0.06
	var dark := func(q: Vector3i) -> Color:
		var c: Color = [Color("27402e"), Color("2f4a34"), Color("223a2a"), Color("35503a")][int(V.h1(q, 7) * 4.0) % 4]
		return V.shade(c, 0.9 + clampf(float(q.y) * 0.015, 0.0, 0.25))
	for i in 18:
		var tx := -54.0 + i * 4.6 + _rng.randf_range(-1.2, 1.2)
		var tz := -50.0 + _rng.randf_range(-3.0, 2.0)
		var r := _rng.randf_range(1.6, 2.6)
		var hgt := _rng.randf_range(4.0, 7.5)
		# Trunk + layered crown (rounder tops read as deciduous silhouettes).
		V.b(tl, int(tx * 2), 0, int(tz * 2), 1, int(hgt * 2 * 0.6), 1, Color("2a2224"))
		V.blob(tl, Vector3(tx * 2, hgt * 2, tz * 2), Vector3(r * 2, r * 2 * 1.1, r * 2), dark, 0.32, i)
		V.blob(tl, Vector3(tx * 2 + r, hgt * 2 - r * 0.8, tz * 2), Vector3(r * 1.3, r * 1.2, r * 1.3), dark, 0.32, i + 40, true)
	# A couple of tall conifers for variety in the skyline.
	for cx in [-29.0, -8.5, 12.0]:
		var cz := -47.0
		for k in 10:
			var rr := maxf(0.5, 3.4 - k * 0.32)
			V.blob(tl, Vector3(cx * 2, 2.0 + k * 1.6, cz * 2), Vector3(rr, 1.0, rr), dark, 0.25, k)
	V.inst(tl, root, 0.5, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, "TreeLine")


func _house(vb: VoxelBuilder, hd: Array, wall: Color, roof: Color) -> void:
	var s := 4  # cells per metre at 0.25
	var x0 := int(hd[0] * s)
	var z0 := int(hd[1] * s)
	var w := int(hd[2] * s)
	var d := int(hd[3] * s)
	var h := int(hd[4] * s)
	var style: int = hd[5]
	# Flat-shaded walls (distant + blurred, so plain faces merge into few quads).
	V.b(vb, x0, 0, z0, w, h, d, wall)
	V.b(vb, x0, 0, z0 + d, w, 1, 1, V.shade(wall, 0.8))
	# Gable roof: along X for even styles, a front-facing gable for odd ones.
	if style % 2 == 0:
		var half := d / 2 + 1
		for k in half + 1:
			V.b(vb, x0 - 1, h + k, z0 - 1 + k, w + 2, 1, d + 2 - 2 * k, V.shade(roof, 0.94 + 0.03 * (k % 3)))
		V.b(vb, x0 + w - 6, h + 2, z0 + d / 2, 3, half + 2, 3, Color("4a3a40"))
	else:
		var half := w / 2 + 1
		for k in half + 1:
			V.b(vb, x0 - 1 + k, h + k, z0 - 1, w + 2 - 2 * k, 1, d + 2, V.shade(roof, 0.94 + 0.03 * (k % 3)))
			# Gable wall triangle on the front.
			if k > 0 and w - 2 * k + 2 > 0:
				V.b(vb, x0 + k - 1, h + k - 1, z0 + d - 1, w - 2 * k + 2, 1, 1, wall)
		# Attic window.
		V.b(vb, x0 + w / 2 - 1, h + 1, z0 + d, 2, 2, 1, Color("ffc76e"), true)
	# Lit windows on the front (+z) face.
	var floors := 2 if h >= 18 else 1
	for f in floors:
		var wy := 3 + f * 9
		var n := w / 7
		for i in n:
			var wx := x0 + 2 + i * 7
			var lit := V.hs(wx, wy, z0) < 0.75
			var gc := Color("ffc76e") if lit else Color("3a3850")
			V.b(vb, wx, wy, z0 + d, 3, 4, 1, gc, lit)
			V.b(vb, wx - 1, wy - 1, z0 + d, 5, 1, 1, V.shade(wall, 1.35))
			if lit:
				V.b(vb, wx + 1, wy, z0 + d, 1, 4, 1, V.shade(gc, 0.75), true)
	# Front door with a porch light.
	V.b(vb, x0 + w - 6, 0, z0 + d, 3, 6, 1, Color("2c2430"))
	V.b(vb, x0 + w - 7, 6, z0 + d, 1, 1, 1, Color("ffd38a"), true)
