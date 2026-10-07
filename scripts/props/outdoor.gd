extends RefCounted
## Outdoor models. NOTE: unlike furniture/decor (1/16 m cells) these are
## authored at the voxel size listed in SCALE (PropLib.scale_of(name) tells
## you); only stamp them into a builder that uses the same voxel size.
## Footprint from (0,0,0), front faces +Z.

const V := preload("res://scripts/props/vox_util.gd")

const SCALE := {
	"tree": 0.25, "pine": 0.25, "house": 0.25,
	"bush": 0.125, "street_lamp": 0.125, "hedge": 0.125, "mailbox": 0.125,
	"fence": 0.0625, "lantern": 0.0625, "flower_bed": 0.0625,
}

## Models meshed without jitter and with face merging (big flat surfaces).
const FLAT := {"house": true}

const SIDING := [Color("efe6d2"), Color("b9cdb4"), Color("a9bad0"), Color("f2dfa6"), Color("e7c3b0"), Color("d8d8dc")]
const ROOF := [Color("3b4566"), Color("6a4232"), Color("b8573a"), Color("4b5a47"), Color("5a3f5f"), Color("38506b")]


## Neighbour house, 8 x 6.5 m, two storeys + gable roof. v % 8 = style,
## v >= 8 = lit (night) windows.
static func m_house(vb: VoxelBuilder, v: int) -> void:
	var style := v % 8
	var lit := v >= 8
	var w := 32
	var d := 26
	var wh := 22
	var sid: Color = SIDING[style % SIDING.size()]
	var roof: Color = ROOF[style % ROOF.size()]
	var trim := Color("f7f4ee")
	# Foundation.
	V.b(vb, 0, 0, 0, w, 1, d, Color("8a8580"))
	# Walls with horizontal siding lines.
	var siding := func(q: Vector3i) -> Color:
		return V.shade(sid, 0.92 if q.y % 2 == 0 else 1.0)
	V.b(vb, 0, 1, 0, w, wh - 1, d, siding)
	# Corner trims.
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, d - 1), Vector2i(w - 1, d - 1)]:
		V.b(vb, c.x, 1, c.y, 1, wh - 1, 1, trim)
	V.b(vb, 0, 11, 0, w, 1, 1, trim); V.b(vb, 0, 11, d - 1, w, 1, 1, trim)
	# Windows on all four sides, two storeys: 4 x 5 panes with a cross
	# mullion, sill and (lit) a warm gradient so they read as windows from
	# far away, not as thin bars.
	var glass := Color("ffcf7a") if lit else Color("8fb8d8")
	var pane := func(q: Vector3i, top: int) -> Color:
		if not lit:
			return Color("8fb8d8").lerp(Color("d6ebf5"), clampf(float(q.y - top + 4) / 4.0, 0.0, 1.0))
		var t := clampf(float(top - q.y) / 4.0, 0.0, 1.0)
		return Color("ffe3a2").lerp(Color("ffb457"), t)
	for floor_i in 2:
		var wy := 4 + floor_i * 10
		for wx: int in [4, 13, 23]:
			if floor_i == 0 and wx == 13:
				continue
			for zz: int in [0, d - 1]:
				V.b(vb, wx - 1, wy - 1, zz, 6, 7, 1, trim)
				var on := not lit or V.hs(wx, wy, zz + v) > 0.12
				for xx in range(wx, wx + 4):
					for yy in range(wy, wy + 5):
						if on:
							V.p(vb, xx, yy, zz, pane.call(Vector3i(xx, yy, zz), wy + 4), lit)
						else:
							V.p(vb, xx, yy, zz, Color("3a4058"))
				V.b(vb, wx, wy + 2, zz, 4, 1, 1, trim)
				V.b(vb, wx + 2, wy, zz, 1, 5, 1, trim)
				var out := -1 if zz == 0 else 1
				V.b(vb, wx - 1, wy - 1, zz + out, 6, 1, 1, Color("d9d2c4"))
		for k in 2:
			var wz := 6 + k * 11
			for xx: int in [0, w - 1]:
				V.b(vb, xx, wy - 1, wz - 1, 1, 7, 6, trim)
				var on2 := not lit or V.hs(xx, wy, wz + v) > 0.2
				for zz2 in range(wz, wz + 4):
					for yy in range(wy, wy + 5):
						V.p(vb, xx, yy, zz2, pane.call(Vector3i(xx, yy, zz2), wy + 4) if on2 else Color("3a4058"), on2 and lit)
				V.b(vb, xx, wy + 2, wz, 1, 1, 4, trim)
				V.b(vb, xx, wy, wz + 2, 1, 5, 1, trim)
	# Front door + porch light.
	V.b(vb, 9, 1, d - 1, 4, 8, 1, Color("7a4a2a") if style % 2 == 0 else Color("2f5a7a"))
	V.p(vb, 12, 4, d, Color("d8b46a"))
	V.b(vb, 13, 7, d, 1, 1, 1, Color("ffd98a"), lit)
	V.b(vb, 7, 0, d, 8, 1, 3, Color("b8b2a8"))
	# Gable roof along X.
	var rh := 9
	for k in rh + 1:
		var z0 := -1 + k
		var z1 := d + 1 - k
		if z1 - z0 <= 0:
			break
		var rc := func(q: Vector3i) -> Color:
			return V.shade(roof, (0.9 if q.x % 2 == 0 else 1.0) * (1.0 + (VoxelBuilder.hash3(q) - 0.5) * 0.08))
		V.b(vb, -1, wh + k, z0, w + 2, 1, 1, rc)
		V.b(vb, -1, wh + k, z1 - 1, w + 2, 1, 1, rc)
		if k == rh or z1 - z0 <= 2:
			V.b(vb, -1, wh + k, z0, w + 2, 1, z1 - z0, rc)
		# Gable end walls + solid attic (keeps hidden faces culled).
		if z1 - z0 > 2:
			V.b(vb, 0, wh + k, z0 + 1, w, 1, z1 - z0 - 2, siding)
	# Attic window.
	V.b(vb, -0, wh + 3, d / 2 - 1, 1, 3, 2, glass, lit)
	V.b(vb, w - 1, wh + 3, d / 2 - 1, 1, 3, 2, glass, lit)
	# Chimney.
	V.b(vb, w - 8, wh + 4, 6, 3, 9, 3, V.noisy(Color("a0573f"), 0.1))


## Round leafy tree ~5 m. v0 green, v1 dark green, v2 light, v3 autumn orange,
## v4 autumn red/yellow.
static func m_tree(vb: VoxelBuilder, v: int) -> void:
	var trunk := Color("6b4a30")
	V.b(vb, 6, 0, 6, 2, 8, 2, V.noisy(trunk, 0.08))
	V.b(vb, 7, 8, 6, 1, 3, 1, trunk)
	V.b(vb, 5, 0, 7, 1, 1, 1, trunk); V.b(vb, 8, 0, 6, 1, 1, 1, trunk)
	var leaf: Callable
	if v >= 3:
		var cols := [Color("e0812f"), Color("f0a03a"), Color("cf5a2a"), Color("f2c14a"), Color("b8442a")] if v == 3 else [Color("c9352f"), Color("e8642f"), Color("f2b03a"), Color("a8332a")]
		leaf = V.mix(cols, v)
	else:
		leaf = V.leaves(v * 5, v)
	var blobs := [Vector4(7, 13, 7, 5.2), Vector4(4.5, 11.5, 6.5, 3.6), Vector4(9.5, 11.5, 8, 3.6), Vector4(7, 16, 7.5, 3.6), Vector4(7.5, 11, 4, 3.2), Vector4(6.5, 11, 10, 3.2)]
	for i in blobs.size():
		var bl: Vector4 = blobs[i]
		V.blob(vb, Vector3(bl.x, bl.y, bl.z), Vector3(bl.w, bl.w * 0.85, bl.w), leaf, 0.0, 0.35, i + v * 7)


static func m_pine(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 4, 0, 4, 1, 4, 1, Color("5b3c26"))
	var leaf := V.mix([Color("2f6b45"), Color("3a7d4f"), Color("285c3b"), Color("468a5a")], v)
	for k in 7:
		var r := 4.6 - k * 0.6
		V.cyl(vb, 4.5, 3 + k * 2, 4.5, r, 2, leaf)
	V.b(vb, 4, 17, 4, 1, 2, 1, leaf)


static func m_bush(vb: VoxelBuilder, v: int) -> void:
	V.blob(vb, Vector3(4, 3, 3), Vector3(4.2, 3.2, 3.2), V.leaves(v, v % 3), 0.0, 0.45, v)
	if v % 2 == 1:
		var fl := [Color("f26d8f"), Color("f7d154"), Color("ffffff"), Color("b07ae0"), Color("ff8a5a")]
		for k in 10:
			var x := int(V.hs(k, v, 1) * 8)
			var z := int(V.hs(k, v, 2) * 6)
			var y := 3 + int(V.hs(k, v, 3) * 3)
			for yy in range(y, 0, -1):
				if vb.has(Vector3i(x, yy, z)):
					V.p(vb, x, yy + 1, z, fl[(k + v) % fl.size()])
					break


static func m_hedge(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 0, 0, 0, 16, 6, 5, V.leaves(v + 2, 1))
	for x in 16:
		if V.hs(x, 6, v) > 0.5:
			V.p(vb, x, 6, 1 + int(V.hs(x, 7, v) * 3), V.leaves(v, 1).call(Vector3i(x, 6, 0)))


## Classic black street lamp ~3.6 m with a glowing lantern head.
static func m_street_lamp(vb: VoxelBuilder, v: int) -> void:
	var blk := Color("23252b")
	if v == 1:
		# Chunky lantern-head post (ref3 neighbourhood): 5x5 glowing lantern
		# with a black cross frame, cap and finial, ~4 m tall.
		V.b(vb, 2, 0, 2, 5, 2, 5, blk)
		V.b(vb, 3, 2, 3, 3, 2, 3, Color("2c2f36"))
		V.b(vb, 4, 4, 4, 1, 22, 1, blk)
		V.b(vb, 3, 25, 3, 3, 1, 3, blk)
		V.b(vb, 1, 26, 1, 7, 1, 7, blk)
		V.b(vb, 2, 27, 2, 5, 6, 5, Color("ffd27a"), true)
		for c in [Vector2i(2, 2), Vector2i(6, 2), Vector2i(2, 6), Vector2i(6, 6)]:
			V.b(vb, c.x, 27, c.y, 1, 6, 1, blk)
		V.b(vb, 4, 27, 2, 1, 6, 1, Color("ffe6aa"), true)
		V.b(vb, 2, 30, 2, 5, 1, 5, Color("ffe9b0"), true)
		V.b(vb, 1, 33, 1, 7, 1, 7, blk)
		V.b(vb, 2, 34, 2, 5, 1, 5, blk)
		V.b(vb, 3, 35, 3, 3, 1, 3, blk)
		V.p(vb, 4, 36, 4, blk)
		return
	V.b(vb, 1, 0, 1, 3, 2, 3, blk)
	V.b(vb, 2, 2, 2, 1, 23, 1, blk)
	V.b(vb, 1, 24, 1, 3, 1, 3, blk)
	V.b(vb, 1, 25, 1, 3, 3, 3, Color("ffd98a"), true)
	V.b(vb, 0, 28, 0, 5, 1, 5, blk)
	V.b(vb, 1, 29, 1, 3, 1, 3, blk)
	V.p(vb, 2, 30, 2, blk)


static func m_mailbox(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 1, 0, 1, 1, 7, 1, Color("6b4a30"))
	V.b(vb, 0, 7, 0, 3, 2, 4, Color("2f5a7a") if v % 2 == 0 else Color("c94a3c"))


## White picket fence, 1 m segment along X (1/16 grid).
static func m_fence(vb: VoxelBuilder, _v: int) -> void:
	var w := Color("f4f1ea")
	for k in 4:
		V.b(vb, k * 4 + 1, 0, 0, 2, 11, 1, V.noisy(w, 0.03))
		V.p(vb, k * 4 + 1, 11, 0, w)
	V.b(vb, 0, 3, 1, 16, 1, 1, V.shade(w, 0.92))
	V.b(vb, 0, 8, 1, 16, 1, 1, V.shade(w, 0.92))


## Standing lantern (1/16 grid), glows.
static func m_lantern(vb: VoxelBuilder, _v: int) -> void:
	var blk := Color("2a2622")
	V.b(vb, 0, 0, 0, 5, 1, 5, blk)
	for c in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)]:
		V.b(vb, c.x, 1, c.y, 1, 6, 1, blk)
	V.b(vb, 1, 1, 1, 3, 6, 3, Color("ffcf6a"), true)
	V.b(vb, 0, 7, 0, 5, 1, 5, blk)
	V.b(vb, 1, 8, 1, 3, 1, 3, blk)
	V.p(vb, 2, 9, 2, blk)


static func m_flower_bed(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 0, 0, 0, 16, 2, 6, V.wood(Color("8a5a34"), 0, 2))
	V.b(vb, 1, 1, 1, 14, 1, 4, Color("4a3020"))
	var fl := [Color("f26d8f"), Color("f7d154"), Color("ffffff"), Color("b07ae0"), Color("ff8a5a")]
	for x in range(1, 15):
		for z in range(1, 5):
			if V.hs(x, z, v) > 0.45:
				V.p(vb, x, 2, z, V.leaves(v).call(Vector3i(x, 2, z)))
				if V.hs(x, z, v + 3) > 0.5:
					V.p(vb, x, 3, z, fl[int(V.hs(x, z, v + 9) * fl.size()) % fl.size()])
