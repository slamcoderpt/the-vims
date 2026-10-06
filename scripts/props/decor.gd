extends RefCounted
## Decor / small prop models (plants, lamps, wall art, desk gear, toys, pet).
## Same conventions as furniture.gd: 1/16 m cells, footprint from (0,0,0),
## front faces +Z. Wall-mounted things have their back at z=0.

const V := preload("res://scripts/props/vox_util.gd")

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const POTS := [Color("c8643c"), Color("ede7db"), Color("d98a5a"), Color("7393b3"), Color("f0c6b0"), Color("5d6b74")]
const LAMP := Color("ffd27e")
const LAMP_HI := Color("fff0c8")


# ------------------------------------------------------------------ plants

## v0 small round bush pot, v1 tall floor plant (big leaves), v2 trailing pot
## (vines spill over the rim), v3 succulent, v4 snake plant, v5 fiddle-leaf tree,
## v6 flowering pot.
static func m_plant(vb: VoxelBuilder, v: int) -> void:
	var pot: Color = POTS[v % POTS.size()]
	match v:
		0:
			_pot(vb, 0, 0, 0, 6, 4, pot)
			V.blob(vb, Vector3(3, 6.5, 3), Vector3(4.0, 3.2, 4.0), V.leaves(v, 0), 0.0, 0.45, 3)
		1:
			_pot(vb, 0, 0, 0, 9, 7, Color("ede7db"))
			V.b(vb, 4, 7, 4, 1, 6, 1, Color("6b4a2a"))
			for k in 7:
				var a := k * 2.4
				var r := 3.0 + V.hs(k, 1, 1) * 2.0
				var cy := 11.0 + k * 1.8
				V.blob(vb, Vector3(4.5 + cos(a) * r, cy, 4.5 + sin(a) * r), Vector3(3.2, 1.6, 3.2), V.leaves(k, 1), 0.0, 0.4, k)
			V.blob(vb, Vector3(4.5, 24, 4.5), Vector3(3, 2.4, 3), V.leaves(9, 1), 0.0, 0.4, 9)
		2:
			_pot(vb, 0, 0, 0, 6, 4, pot)
			V.blob(vb, Vector3(3, 5.2, 3), Vector3(3.6, 2.0, 3.6), V.leaves(4, 2), 0.0, 0.4, 4)
			for k in 4:
				var vx: int = [-1, 6, 2, 4][k]
				var vz: int = [2, 3, 6, -1][k]
				var ln := 3 + int(V.hs(k, 2, 9) * 4)
				for y in ln:
					V.p(vb, vx, 4 - y, vz, V.leaves(k, 2).call(Vector3i(vx, y, vz)))
		3:
			_pot(vb, 0, 0, 0, 4, 3, pot)
			V.blob(vb, Vector3(2, 4, 2), Vector3(2.0, 1.4, 2.0), V.mix([Color("7fbf8a"), Color("9fd39a"), Color("5ea374")], 2), 0.0, 0.2, 1)
		4:
			_pot(vb, 0, 0, 0, 6, 5, pot)
			for k in 6:
				var lx := 1 + int(V.hs(k, 4, 1) * 4)
				var lz := 1 + int(V.hs(k, 5, 1) * 4)
				var lh := 6 + int(V.hs(k, 6, 1) * 7)
				V.b(vb, lx, 5, lz, 1, lh, 1, V.mix([Color("3f7f3a"), Color("5b9a45"), Color("c8c86a")], k))
		5:
			_pot(vb, 0, 0, 0, 8, 6, Color("c8643c"))
			V.b(vb, 4, 6, 4, 1, 12, 1, Color("6b4a2a"))
			V.blob(vb, Vector3(4.5, 21, 4.5), Vector3(5.0, 5.5, 5.0), V.leaves(7, 0), 0.0, 0.5, 7)
		6:
			_pot(vb, 0, 0, 0, 6, 4, pot)
			V.blob(vb, Vector3(3, 6, 3), Vector3(3.6, 2.6, 3.6), V.leaves(6, 2), 0.0, 0.4, 6)
			var fl := [Color("f26d8f"), Color("f7d154"), Color("ffffff"), Color("b07ae0")]
			for k in 6:
				var q := Vector3i(int(V.hs(k, 7, 2) * 6), 7 + int(V.hs(k, 8, 2) * 2), int(V.hs(k, 9, 2) * 6))
				V.p(vb, q.x, q.y, q.z, fl[k % fl.size()])


static func _pot(vb: VoxelBuilder, x: int, y: int, z: int, s: int, h: int, c: Color) -> void:
	V.b(vb, x + 1, y, z + 1, s - 2, 1, s - 2, V.shade(c, 0.9))
	V.b(vb, x, y + 1, z, s, h - 2, s, V.noisy(c, 0.05))
	V.b(vb, x, y + h - 1, z, s, 1, s, V.shade(c, 1.1))
	V.b(vb, x + 1, y + h - 1, z + 1, s - 2, 1, s - 2, Color("4a3020"))


## Hanging ivy strand / wall vine, `v` = length variant. Hangs down from y top.
static func m_ivy(vb: VoxelBuilder, v: int) -> void:
	var ln := 14 + v * 6
	var lc := V.leaves(v + 11, 0)
	for y in ln:
		var x := int(round(sin(y * 0.55 + v) * 1.2)) + 2
		V.p(vb, x, ln - y, 0, lc.call(Vector3i(x, y, 0)))
		if V.hs(x, y, v) > 0.35:
			V.p(vb, x + (1 if y % 2 == 0 else -1), ln - y, 0, lc.call(Vector3i(x + 1, y, 1)))
		if V.hs(x, y, v + 5) > 0.6:
			V.p(vb, x, ln - y, 1, lc.call(Vector3i(x, y, 2)))
	V.b(vb, 1, ln, 0, 3, 1, 1, lc)


## Hanging basket plant (hook at the top), for ceilings / window frames.
static func m_hanging_plant(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 3, 14, 3, 1, 6, 1, Color("8a6a4a"))
	V.b(vb, 1, 10, 1, 5, 3, 5, V.noisy(Color("d9b98a"), 0.08))
	V.blob(vb, Vector3(3.5, 13, 3.5), Vector3(3.5, 1.6, 3.5), V.leaves(v, 0), 0.0, 0.4, v)
	for k in 5:
		var vx: int = [0, 6, 3, 1, 5][k]
		var vz: int = [3, 2, 0, 6, 6][k]
		var ln := 4 + int(V.hs(k, v, 3) * 6)
		for y in ln:
			V.p(vb, vx, 11 - y, vz, V.leaves(k + v, 0).call(Vector3i(vx, y, vz)))


# ------------------------------------------------------------------ lamps
# Glow voxels use the emissive surface. Add an OmniLight with PropLib.add_light.

static func m_lamp_table(vb: VoxelBuilder, v: int) -> void:
	var base: Color = [Color("e6dccb"), Color("f2b8c8"), Color("8fa8d8"), Color("c9a05a")][v % 4]
	V.b(vb, 1, 0, 1, 4, 1, 4, V.shade(base, 0.9))
	V.b(vb, 2, 1, 2, 2, 4, 2, base)
	V.b(vb, 0, 5, 0, 6, 3, 6, LAMP, true)
	V.b(vb, 0, 5, 0, 6, 1, 6, LAMP_HI, true)
	V.b(vb, 1, 8, 1, 4, 2, 4, LAMP, true)


static func m_lamp_floor(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 1, 0, 1, 4, 1, 4, Color("3a3a3f"))
	V.b(vb, 3, 1, 3, 1, 22, 1, Color("3a3a3f"))
	V.b(vb, 0, 23, 0, 7, 4, 7, LAMP, true)
	V.b(vb, 0, 23, 0, 7, 1, 7, LAMP_HI, true)
	V.b(vb, 1, 27, 1, 5, 2, 5, LAMP, true)


## Wall sconce / lantern, back on the wall at z=0.
static func m_sconce(vb: VoxelBuilder, v: int) -> void:
	var metal := Color("3c3633") if v == 0 else Color("c99a4a")
	V.b(vb, 1, 2, 0, 3, 5, 1, WOOD_D)
	V.b(vb, 2, 4, 1, 1, 1, 1, metal)
	V.b(vb, 0, 1, 2, 5, 1, 4, metal)
	V.b(vb, 0, 7, 2, 5, 1, 4, metal)
	V.b(vb, 1, 8, 3, 3, 1, 2, metal)
	V.b(vb, 1, 2, 3, 3, 5, 2, LAMP, true)
	for q in [Vector2i(0, 2), Vector2i(4, 2), Vector2i(0, 5), Vector2i(4, 5)]:
		V.b(vb, q.x, 2, q.y, 1, 5, 1, metal)


static func m_desk_lamp(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("2f6d6a")
	V.b(vb, 0, 0, 0, 4, 1, 3, c)
	V.b(vb, 1, 1, 1, 1, 5, 1, c)
	V.b(vb, 1, 6, 1, 1, 1, 3, c)
	V.b(vb, 0, 5, 3, 3, 2, 3, c)
	V.b(vb, 1, 4, 4, 1, 1, 1, LAMP, true)


static func m_candle(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 2, 2, 2, Color("f3ead6"))
	V.p(vb, 0, 2, 0, Color("ffcf6a"), true)


# ------------------------------------------------------------------ wall art

## Framed pictures, back at z=0. v0 mountain landscape (large), v1 small
## family photo, v2 bunny picture, v3 music note poster, v4 rocket poster,
## v5 flower, v6 tiny square, v7 ocean, v8 star map.
static func m_frame(vb: VoxelBuilder, v: int) -> void:
	var sizes := [Vector2i(16, 12), Vector2i(6, 7), Vector2i(8, 10), Vector2i(8, 11), Vector2i(9, 13), Vector2i(6, 6), Vector2i(5, 5), Vector2i(10, 7), Vector2i(8, 8)]
	var s: Vector2i = sizes[v % sizes.size()]
	var fc: Color = [Color("5a3a22"), Color("2c2c2f"), Color("f1e9dc"), Color("222226"), Color("2c2c35"), Color("b07a46"), Color("d8b26a"), Color("f1e9dc"), Color("2c2c35")][v % 9]
	V.b(vb, 0, 0, 0, s.x, s.y, 1, fc)
	for x in range(1, s.x - 1):
		for y in range(1, s.y - 1):
			V.p(vb, x, y, 1, _art(v, x - 1, y - 1, s.x - 2, s.y - 2))
	for x in s.x:
		V.p(vb, x, 0, 1, fc); V.p(vb, x, s.y - 1, 1, fc)
	for y in s.y:
		V.p(vb, 0, y, 1, fc); V.p(vb, s.x - 1, y, 1, fc)


static func _art(v: int, x: int, y: int, w: int, h: int) -> Color:
	match v % 9:
		0:
			# Mountain landscape with pines (ref1 painting).
			var sky := Color("9ccbea").lerp(Color("f6e3c0"), 1.0 - float(y) / h)
			var mx := absf(x - w * 0.55) * 1.1
			if y < 3:
				return Color("4e8a3f") if V.hs(x, y, 1) > 0.3 else Color("3e7434")
			if (x % 3 == 0) and y < 6 and y >= 3:
				return Color("2f5c34")
			if y < h - 1 - mx:
				return Color("ffffff") if y > h - 3 - mx else Color("7d8ea8")
			return sky
		1:
			if y < h / 2:
				return Color("e7c7a6") if absf(x - w / 2.0) < 2 else Color("b8d4e6")
			return Color("c94f4f") if absf(x - w / 2.0) < 2 else Color("b8d4e6")
		2:
			var bx := x - w / 2.0 + 0.5
			var by := y - h * 0.4
			if bx * bx + by * by < 5.0 or (absf(bx) > 0.6 and absf(bx) < 2.0 and y > h * 0.55):
				return Color("f7a9c0")
			return Color("fdf3f5")
		3:
			if (x == w / 2 and y > 2 and y < h - 1) or (y == h - 2 and x >= w / 2 and x < w / 2 + 3):
				return Color("f2f0ff")
			if (x == w / 2 - 1 or x == w / 2) and (y == 2 or y == 3):
				return Color("f2f0ff")
			return Color("db4f8a") if V.hs(x, y, 3) > 0.15 else Color("e86aa0")
		4:
			var cx := w / 2
			if absf(x - cx) <= 1 and y > 2 and y < h - 3:
				return Color("eeeef2") if y != h / 2 else Color("6ab0e8")
			if absf(x - cx) <= 2 and y == 3:
				return Color("e2463a")
			if absf(x - cx) == 0 and y >= h - 3 and y < h - 1:
				return Color("e2463a")
			if y < 2 and absf(x - cx) <= 1:
				return Color("f7b23a")
			return Color("ffe27a") if V.hs(x, y, 4) > 0.9 else Color("26306a")
		5:
			if absf(x - w / 2.0 + 0.5) < 1 and y < h / 2:
				return Color("4f9a3c")
			if y >= h / 2 and absf(x - w / 2.0 + 0.5) < 1.5:
				return Color("f26d8f")
			return Color("fbf1df")
		6:
			return Color("e9a23b") if (x + y) % 2 == 0 else Color("3f7fc4")
		7:
			if y < h / 3:
				return Color("2d6fa8") if V.hs(x, y, 7) > 0.2 else Color("e8f3fa")
			if y < h / 3 + 1:
				return Color("f2deb0")
			return Color("bfe0f4") if y > h - 3 else Color("f6d98f")
		_:
			return Color("ffe27a") if V.hs(x, y, 8) > 0.82 else Color("2a3570")


static func m_corkboard(vb: VoxelBuilder, v: int) -> void:
	var w := 22 if v == 0 else 28
	var h := 14 if v == 0 else 17
	V.b(vb, 0, 0, 0, w, h, 1, WOOD)
	V.b(vb, 1, 1, 1, w - 2, h - 2, 1, V.mix([Color("c99a60"), Color("c99a60"), Color("c99a60"), Color("bb8a52")], 4))
	var notes := [Color("fff6b0"), Color("bfe3ff"), Color("ffc4d8"), Color("ffffff"), Color("c8f0b8"), Color("ffd8a8")]
	var spots := [Vector4i(2, 8, 4, 4), Vector4i(7, 9, 3, 3), Vector4i(11, 7, 5, 5), Vector4i(17, 9, 3, 3),
		Vector4i(2, 2, 3, 4), Vector4i(6, 3, 4, 4), Vector4i(12, 2, 3, 3), Vector4i(16, 2, 4, 5)]
	if v == 1:
		spots.append_array([Vector4i(22, 10, 4, 5), Vector4i(23, 3, 3, 4), Vector4i(7, 13, 4, 2), Vector4i(16, 14, 6, 2)])
	for i in spots.size():
		var s: Vector4i = spots[i]
		var c: Color = notes[i % notes.size()]
		V.b(vb, s.x, s.y, 2, s.z, s.w, 1, c)
		if s.z > 3:
			V.b(vb, s.x + 1, s.y + s.w - 2, 2, s.z - 2, 1, 1, V.shade(c, 0.7))
		V.p(vb, s.x + s.z / 2, s.y + s.w - 1, 3, [Color("e2463a"), Color("3a7fe0"), Color("f2c53a")][i % 3])
	# Little photo + string.
	V.b(vb, 12, 8, 3, 3, 3, 1, Color("6aa0d8"))


static func m_wall_shelf(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 0, 0, 0, 14, 1, 4, V.wood(WOOD, 0, 2))
	V.p(vb, 1, -1, 0, WOOD_D); V.p(vb, 12, -1, 0, WOOD_D)
	match v % 3:
		0:
			V.books(vb, 1, 1, 0, 6, 4, 3, 21)
			V.b(vb, 9, 1, 1, 3, 2, 2, Color("ede7db"))
			V.blob(vb, Vector3(10.5, 4, 2), Vector3(2, 1.5, 2), V.leaves(3), 0.0, 0.3, 3)
		1:
			# Bunny plush + books.
			V.books(vb, 9, 1, 0, 4, 4, 3, 33)
			V.b(vb, 2, 1, 1, 4, 3, 3, Color("fbf3f5")); V.b(vb, 2, 4, 1, 1, 3, 1, Color("fbf3f5")); V.b(vb, 5, 4, 1, 1, 3, 1, Color("fbf3f5"))
			V.p(vb, 3, 2, 4, Color("2a2030")); V.p(vb, 4, 2, 4, Color("2a2030"))
		_:
			V.b(vb, 1, 1, 1, 2, 3, 2, Color("e7c46a")); V.b(vb, 4, 1, 1, 4, 3, 2, Color("6fa0d8"))
			V.books(vb, 9, 1, 0, 4, 3, 3, 47)


# ------------------------------------------------------------------ desk gear

static func m_monitor(vb: VoxelBuilder, v: int) -> void:
	# v0 big monitor 0.75 m wide, v1 small one. Screen faces +Z.
	var w := 13 if v == 0 else 9
	var h := 8 if v == 0 else 6
	var blk := Color("26272c")
	V.b(vb, w / 2 - 2, 0, 1, 4, 1, 3, blk)
	V.b(vb, w / 2 - 1, 1, 1, 2, 3, 1, blk)
	V.b(vb, 0, 3, 1, w, h, 1, blk)
	# Bright blue desktop with a white app window (reads as "screen" at phone size).
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			var c := Color("3f86e6")
			var win := x >= 2 and x <= w - 3 and y >= 1 and y <= h - 3
			if win:
				c = Color("f4f8fd")
				if y == h - 3:
					c = Color("1f5fb8")
				elif x == 2 and v == 0:
					c = Color("c9dcf3")
				elif y % 2 == 0 and x > 3 and x < w - 3 and V.hs(x, y, v) > 0.35:
					c = Color("9db8dc")
			V.p(vb, x, 3 + y, 2, c, true)


static func m_laptop(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("9aa0aa")
	V.b(vb, 0, 0, 2, 8, 1, 5, c)
	V.b(vb, 1, 1, 3, 6, 1, 3, Color("4a4e57"))
	V.b(vb, 0, 1, 1, 8, 5, 1, c)
	V.b(vb, 1, 2, 2, 6, 3, 1, Color("5d9be8"), true)
	V.b(vb, 2, 3, 2, 4, 1, 1, Color("f4f8fd"), true)


static func m_keyboard(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 8, 1, 3, Color("e4e6ea"))
	V.b(vb, 10, 0, 1, 2, 1, 2, Color("e4e6ea"))


static func m_printer(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("d9dade")
	V.b(vb, 0, 0, 0, 10, 4, 8, V.noisy(c, 0.03))
	V.b(vb, 0, 4, 0, 10, 2, 6, V.shade(c, 0.92))
	V.b(vb, 2, 6, 0, 6, 2, 1, Color("f6f6f2"))
	V.b(vb, 2, 3, 8, 6, 1, 2, Color("f6f6f2"))
	V.p(vb, 8, 4, 6, Color("5fd06f"), true)


static func m_mug(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("f5f2ea"), Color("e86f5a"), Color("6fa0d8")][v % 3]
	V.b(vb, 0, 0, 0, 2, 2, 2, c)
	V.p(vb, 2, 1, 0, c)


static func m_pencil_cup(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 2, 2, 2, Color("3f7fc4"))
	V.p(vb, 0, 2, 0, Color("f2c53a")); V.p(vb, 1, 3, 1, Color("e2463a")); V.p(vb, 1, 2, 0, Color("53b34a"))


static func m_book_stack(vb: VoxelBuilder, v: int) -> void:
	var cols := [Color("b8403a"), Color("2f5e8f"), Color("e0b44c"), Color("3f7f4f"), Color("f0e2c0")]
	for k in 2 + v % 3:
		V.b(vb, k % 2, k, 0, 5, 1, 4, cols[(k + v) % cols.size()])


static func m_globe(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 1, 0, 1, 3, 1, 3, WOOD_D)
	V.p(vb, 2, 1, 2, Color("c9a54a"))
	V.blob(vb, Vector3(2.5, 4.2, 2.5), Vector3(2.4, 2.4, 2.4), V.mix([Color("3d7fc4"), Color("3d7fc4"), Color("5b9b48"), Color("4a8cd0")], 3), 0.0, 0.0)


static func m_telescope(vb: VoxelBuilder, _v: int) -> void:
	var blk := Color("2a2b31")
	V.b(vb, 0, 0, 0, 1, 14, 1, blk); V.b(vb, 6, 0, 0, 1, 14, 1, blk); V.b(vb, 3, 0, 6, 1, 14, 1, blk)
	V.b(vb, 2, 13, 2, 3, 2, 3, blk)
	for k in 9:
		V.b(vb, 2 + k / 3, 15 + k / 2, 1 + k, 2, 2, 1, Color("e8eaf0") if k > 1 else blk)


# ------------------------------------------------------------------ kids / pet

static func m_dog_bed(vb: VoxelBuilder, _v: int) -> void:
	# Wooden crate bed with a bone on the front (ref1).
	var w := V.wood(Color("9a5f34"), 0, 2)
	V.b(vb, 0, 0, 0, 16, 1, 13, w)
	V.b(vb, 0, 1, 0, 16, 5, 1, w); V.b(vb, 0, 1, 12, 16, 5, 1, w)
	V.b(vb, 0, 1, 0, 1, 5, 13, w); V.b(vb, 15, 1, 0, 1, 5, 13, w)
	V.b(vb, 1, 1, 1, 14, 2, 11, V.noisy(Color("efe4cf"), 0.05))
	V.b(vb, 2, 3, 2, 12, 1, 9, V.noisy(Color("f6eedd"), 0.04))
	# Bone emblem.
	for q in [Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2),
			Vector2i(4, 1), Vector2i(4, 3), Vector2i(11, 1), Vector2i(11, 3)]:
		V.p(vb, q.x, q.y + 1, 13, Color("f3ead8"))


## Round dog cushion (ref3 hallway).
static func m_dog_cushion(vb: VoxelBuilder, _v: int) -> void:
	V.cyl(vb, 8, 0, 8, 8.0, 1, V.noisy(Color("6c7fa8"), 0.06))
	V.cyl(vb, 8, 1, 8, 8.0, 2, V.noisy(Color("8496c0"), 0.06))
	V.cyl(vb, 8, 2, 8, 6.0, 1, V.noisy(Color("b9c3dc"), 0.05))


static func m_toy_box(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("b48ad8")
	V.b(vb, 0, 0, 0, 16, 9, 12, V.noisy(c, 0.04))
	vb.clear_box(Vector3i(1, 4, 1), Vector3i(14, 5, 10))
	V.b(vb, 0, 9, 0, 16, 1, 1, V.shade(c, 1.12)); V.b(vb, 0, 9, 11, 16, 1, 1, V.shade(c, 1.12))
	var toy := [Color("e2463a"), Color("3a7fe0"), Color("f2c53a"), Color("53b34a"), Color("f07ab0"), Color("ff9a3a")]
	for k in 16:
		var x := 1 + int(V.hs(k, 1, 7) * 12)
		var z := 1 + int(V.hs(k, 2, 7) * 8)
		var y := 4 + int(V.hs(k, 3, 7) * 3)
		V.b(vb, x, y, z, 2, 2, 2, toy[k % toy.size()])
	# Bunny face on the front.
	var f := Color("fbf3f5")
	V.b(vb, 5, 2, 12, 6, 4, 1, f)
	V.b(vb, 5, 6, 12, 2, 3, 1, f); V.b(vb, 9, 6, 12, 2, 3, 1, f)
	V.p(vb, 6, 7, 13, Color("f7a9c0")); V.p(vb, 9, 7, 13, Color("f7a9c0"))
	V.p(vb, 6, 4, 13, Color("2a2030")); V.p(vb, 9, 4, 13, Color("2a2030"))
	V.p(vb, 7, 3, 13, Color("f7a9c0")); V.p(vb, 8, 3, 13, Color("f7a9c0"))


static func m_soccer_ball(vb: VoxelBuilder, _v: int) -> void:
	V.blob(vb, Vector3(3, 3, 3), Vector3(3.1, 3.1, 3.1), V.checker(Color("f8f8f6"), Color("1f1f24"), 2), 0.0, 0.0)


static func m_tennis_ball(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 2, 2, 2, Color("d7ee3a"))
	V.p(vb, 0, 1, 1, Color("f2f7d8"))


static func m_toy_blocks(vb: VoxelBuilder, v: int) -> void:
	var toy := [Color("e2463a"), Color("3a7fe0"), Color("f2c53a"), Color("53b34a"), Color("f07ab0"), Color("ff9a3a"), Color("f6f1e6")]
	var n := 8 + v * 3
	for k in n:
		var x := int(V.hs(k, 11, v) * 14)
		var z := int(V.hs(k, 12, v) * 12)
		var c: Color = toy[k % toy.size()]
		V.b(vb, x, 0, z, 2, 2, 2, c)
		if V.hs(k, 13, v) > 0.6:
			V.b(vb, x, 2, z, 2, 2, 2, toy[(k + 3) % toy.size()])


## Little robot / car toy the cat girl is building (ref1).
static func m_toy_robot(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 1, 0, 1, 1, 2, 1, Color("2a2b31")); V.b(vb, 3, 0, 1, 1, 2, 1, Color("2a2b31"))
	V.b(vb, 0, 2, 0, 5, 3, 3, Color("f2f2f0"))
	V.b(vb, 1, 5, 0, 3, 3, 3, Color("2a2b31"))
	V.p(vb, 1, 6, 3, Color("6ad0ff"), true); V.p(vb, 3, 6, 3, Color("6ad0ff"), true)
	V.p(vb, 2, 8, 1, Color("e2463a"))
	V.b(vb, 8, 0, 0, 5, 2, 3, Color("3a7fe0")); V.b(vb, 9, 2, 0, 3, 1, 3, Color("6ab0e8"))
	V.p(vb, 8, 0, 3, Color("222")); V.p(vb, 12, 0, 3, Color("222"))


static func m_plush(vb: VoxelBuilder, v: int) -> void:
	# v0 white bunny, v1 green dinosaur, v2 teddy.
	match v % 3:
		0:
			var f := Color("fbf3f5")
			V.b(vb, 0, 0, 0, 4, 3, 3, f); V.b(vb, 0, 3, 0, 4, 3, 3, f)
			V.b(vb, 0, 6, 1, 1, 3, 1, f); V.b(vb, 3, 6, 1, 1, 3, 1, f)
			V.p(vb, 0, 7, 2, Color("f7a9c0")); V.p(vb, 3, 7, 2, Color("f7a9c0"))
			V.p(vb, 1, 4, 3, Color("2a2030")); V.p(vb, 2, 4, 3, Color("2a2030"))
		1:
			var g := Color("4fae5a")
			V.b(vb, 0, 0, 0, 5, 4, 7, g); V.b(vb, 1, 4, 4, 3, 3, 4, g)
			V.b(vb, 2, 1, -2, 1, 2, 2, g)
			for k in 4:
				V.p(vb, 2, 4, 1 + k, Color("f2c53a"))
			V.p(vb, 1, 5, 8, Color("1a1a1a")); V.p(vb, 3, 5, 8, Color("1a1a1a"))
		_:
			var t := Color("b07a46")
			V.b(vb, 0, 0, 0, 4, 4, 3, t); V.b(vb, 0, 4, 0, 4, 3, 3, t)
			V.p(vb, 0, 7, 1, t); V.p(vb, 3, 7, 1, t)
			V.p(vb, 1, 5, 3, Color("1a1a1a")); V.p(vb, 2, 5, 3, Color("1a1a1a"))


## Curtain panel hanging from a rod, back at z=0. v = colour.
static func m_curtain(vb: VoxelBuilder, v: int) -> void:
	var base: Color = [Color("c9c3d6"), Color("f4c7d2"), Color("9fb1df"), Color("efe6d4")][v % 4]
	var line := V.shade(base, 0.82)
	for y in 38:
		for x in 5:
			var wave := 1 if (x + y / 9) % 2 == 0 else 0
			var c := base if (posmod(x, 3) != 0 and posmod(y, 4) != 0) else line
			V.p(vb, x, y, wave, V.shade(c, 0.95 + V.hs(x, y, 7) * 0.08))
	V.b(vb, 0, 38, 0, 5, 1, 2, Color("3a3a3f"))


static func m_rocket_lamp(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 1, 0, 1, 3, 4, 3, Color("eeeef2"))
	V.b(vb, 2, 4, 2, 1, 2, 1, Color("e2463a"))
	V.p(vb, 2, 2, 4, Color("6ab0e8"), true)
	V.b(vb, 0, 0, 2, 1, 2, 1, Color("e2463a")); V.b(vb, 4, 0, 2, 1, 2, 1, Color("e2463a"))


# ------------------------------------------------------------------ round 3 additions

## Wall mirror, back at z=0. v0 tall wood frame (vanity), v1 round, v2 wide.
static func m_mirror(vb: VoxelBuilder, v: int) -> void:
	var glass := Color("cfe4ee")
	match v % 3:
		1:
			for x in 11:
				for y in 11:
					var d := Vector2(x - 5.0, y - 5.0).length()
					if d <= 5.4:
						V.p(vb, x, y, 0, Color("d8b26a") if d > 4.3 else glass.lerp(Color("eef8fc"), 0.4 if x + y < 8 else 0.0))
		2:
			V.b(vb, 0, 0, 0, 18, 10, 1, WOOD)
			V.b(vb, 1, 1, 0, 16, 8, 1, glass)
			V.b(vb, 2, 5, 1, 3, 3, 1, Color("eaf6fb"))
			V.b(vb, 1, 1, 1, 16, 1, 1, V.shade(WOOD, 1.1))
		_:
			V.b(vb, 0, 0, 0, 10, 15, 1, WOOD)
			V.b(vb, 1, 1, 0, 8, 13, 1, glass)
			V.b(vb, 2, 9, 1, 2, 4, 1, Color("eaf6fb"))
			V.b(vb, 0, 15, 0, 10, 1, 2, V.shade(WOOD, 1.1))


## Woven laundry / storage basket with a towel or blanket spilling out.
static func m_basket(vb: VoxelBuilder, v: int) -> void:
	var weave := V.checker(Color("c99a5c"), Color("b4824a"), 1)
	V.b(vb, 0, 0, 0, 8, 7, 7, weave)
	vb.clear_box(Vector3i(1, 2, 1), Vector3i(6, 5, 5))
	var cloth: Color = [Color("f4f1ea"), Color("f2b5c6"), Color("8fb4d8"), Color("e9d6a8")][v % 4]
	V.b(vb, 1, 2, 1, 6, 5, 5, V.noisy(cloth, 0.05))
	V.b(vb, 2, 7, 2, 5, 1, 3, V.noisy(cloth, 0.05))
	V.b(vb, 5, 4, 7, 2, 3, 1, V.noisy(cloth, 0.05))
	V.b(vb, 0, 7, 0, 8, 1, 1, Color("8a5a36")); V.b(vb, 0, 7, 6, 8, 1, 1, Color("8a5a36"))


## Gold trophy cup.
static func m_trophy(vb: VoxelBuilder, _v: int) -> void:
	var g := Color("e8b83a")
	V.b(vb, 0, 0, 0, 4, 1, 3, WOOD_D)
	V.b(vb, 1, 1, 1, 2, 2, 1, V.shade(g, 0.85))
	V.b(vb, 0, 3, 0, 4, 3, 3, g)
	V.p(vb, -1, 4, 1, g); V.p(vb, 4, 4, 1, g)
	V.p(vb, 1, 5, 3, Color("fff2b0"))


## Round wall clock, back at z=0.
static func m_wall_clock(vb: VoxelBuilder, v: int) -> void:
	var rim: Color = [Color("2c2c2f"), Color("b07a46"), Color("f2b8c8")][v % 3]
	for x in 7:
		for y in 7:
			var d := Vector2(x - 3.0, y - 3.0).length()
			if d <= 3.5:
				V.p(vb, x, y, 0, rim if d > 2.6 else Color("fbf8f1"))
	V.p(vb, 3, 3, 1, Color("222")); V.p(vb, 3, 4, 1, Color("222")); V.p(vb, 4, 3, 1, Color("e2463a"))


## Kid's bean bag. v0 pink, v1 blue, v2 mustard.
static func m_beanbag(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("f2a3bd"), Color("7f97d6"), Color("e3b04a")][v % 3]
	V.blob(vb, Vector3(5.5, 3.0, 5.5), Vector3(5.6, 3.2, 5.6), V.noisy(c, 0.06), 0.0, 0.15, v)
	V.blob(vb, Vector3(5.5, 5.5, 2.8), Vector3(4.6, 3.4, 2.6), V.noisy(V.shade(c, 0.95), 0.06), 0.0, 0.15, v + 3)


## Floor cushion / pouf.
static func m_pouf(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("e8d6b8"), Color("c9a0c8"), Color("9fc3a8")][v % 3]
	V.cyl(vb, 4, 0, 4, 4.2, 4, V.noisy(c, 0.05))
	V.cyl(vb, 4, 4, 4, 3.4, 1, V.shade(c, 1.08))


## Stacked wall shelves with lots of stuff (2 tiers), back at z=0.
## v0 books+plush (pink room), v1 books+rocket+globe (blue room),
## v2 bathroom (bottles, rolled towels, plant), v3 office (binders, plant, photos).
static func m_shelf_unit(vb: VoxelBuilder, v: int) -> void:
	var wood := V.wood(WOOD if v != 0 else Color("f2ece2"), 0, 2)
	for tier in 2:
		var y := tier * 9
		V.b(vb, 0, y, 0, 18, 1, 5, wood)
		V.p(vb, 1, y - 1, 0, WOOD_D); V.p(vb, 16, y - 1, 0, WOOD_D)
		match v % 4:
			0:
				if tier == 0:
					V.books(vb, 1, y + 1, 0, 9, 6, 4, 61)
					_bunny(vb, 12, y + 1, 1, Color("fbf3f5"))
				else:
					_bunny(vb, 2, y + 1, 1, Color("f7c6d4"))
					V.b(vb, 8, y + 1, 1, 4, 4, 3, Color("f6e7a8")); V.b(vb, 9, y + 5, 2, 2, 1, 1, Color("f2c53a"))
					V.b(vb, 13, y + 1, 1, 4, 3, 3, Color("ede7db"))
					V.blob(vb, Vector3(15, y + 5, 2.5), Vector3(2.4, 1.8, 2.2), V.leaves(5, 2), 0.0, 0.3, 5)
			1:
				if tier == 0:
					V.books(vb, 1, y + 1, 0, 10, 6, 4, 77)
					V.b(vb, 13, y + 1, 1, 3, 1, 3, WOOD_D)
					V.blob(vb, Vector3(14.5, y + 4.2, 2.5), Vector3(2.2, 2.2, 2.2), V.mix([Color("3d7fc4"), Color("5b9b48"), Color("4a8cd0")], 3), 0.0, 0.0)
				else:
					V.b(vb, 2, y + 1, 1, 3, 7, 3, Color("eeeef2")); V.b(vb, 3, y + 8, 2, 1, 1, 1, Color("e2463a"))
					V.b(vb, 1, y + 1, 2, 1, 2, 1, Color("e2463a")); V.b(vb, 5, y + 1, 2, 1, 2, 1, Color("e2463a"))
					V.p(vb, 3, y + 5, 4, Color("6ab0e8"))
					V.books(vb, 8, y + 1, 0, 8, 5, 4, 91)
			2:
				if tier == 0:
					for k in 3:
						var tc: Color = [Color("f4f1ea"), Color("8fb4d8"), Color("f2b5c6")][k]
						V.b(vb, 1 + k * 5, y + 1, 0, 4, 3, 4, V.noisy(tc, 0.04))
						V.b(vb, 1 + k * 5, y + 2, 4, 4, 1, 1, V.shade(tc, 0.85))
				else:
					var bc := [Color("f3f0e8"), Color("9fd0e8"), Color("f2c4a0"), Color("c8e6c0")]
					for k in 4:
						V.b(vb, 1 + k * 3, y + 1, 1, 2, 3 + k % 2 * 2, 2, bc[k])
						V.p(vb, 1 + k * 3, y + 4 + k % 2 * 2, 1, Color("d8d8d8"))
					V.b(vb, 13, y + 1, 1, 4, 3, 3, Color("ede7db"))
					V.blob(vb, Vector3(15, y + 5, 2.5), Vector3(2.6, 2.0, 2.4), V.leaves(8, 0), 0.0, 0.3, 8)
			_:
				if tier == 0:
					for k in 5:
						V.b(vb, 1 + k * 2, y + 1, 0, 2, 6, 4, [Color("3f6fb0"), Color("e0b44c"), Color("b8403a"), Color("3f7f4f"), Color("f0e2c0")][k])
					V.b(vb, 13, y + 1, 1, 4, 3, 3, Color("c8643c"))
					V.blob(vb, Vector3(15, y + 5, 2.5), Vector3(2.4, 2.0, 2.2), V.leaves(2, 0), 0.0, 0.3, 2)
				else:
					V.b(vb, 2, y + 1, 1, 4, 5, 1, Color("2c2c2f")); V.b(vb, 3, y + 2, 2, 2, 3, 1, Color("8fc0e0"))
					V.b(vb, 8, y + 1, 1, 3, 4, 1, Color("f1e9dc")); V.b(vb, 9, y + 2, 2, 1, 2, 1, Color("e9a23b"))
					V.books(vb, 12, y + 1, 0, 5, 4, 4, 13)


static func _bunny(vb: VoxelBuilder, x: int, y: int, z: int, f: Color) -> void:
	V.b(vb, x, y, z, 4, 3, 3, f); V.b(vb, x, y + 3, z, 4, 3, 3, f)
	V.b(vb, x, y + 6, z + 1, 1, 3, 1, f); V.b(vb, x + 3, y + 6, z + 1, 1, 3, 1, f)
	V.p(vb, x, y + 7, z + 2, Color("f7a9c0")); V.p(vb, x + 3, y + 7, z + 2, Color("f7a9c0"))
	V.p(vb, x + 1, y + 4, z + 3, Color("2a2030")); V.p(vb, x + 2, y + 4, z + 3, Color("2a2030"))


## Small potted plant on a hanging wall bracket (adds green at eye level), back at z=0.
static func m_wall_planter(vb: VoxelBuilder, v: int) -> void:
	V.b(vb, 1, 0, 0, 1, 4, 1, Color("3a3530")); V.b(vb, 1, 3, 0, 1, 1, 3, Color("3a3530"))
	_pot(vb, 0, 0, 1, 5, 4, POTS[v % POTS.size()])
	V.blob(vb, Vector3(2.5, 5.0, 3.5), Vector3(3.0, 1.8, 3.0), V.leaves(v + 2, v % 3), 0.0, 0.4, v)
	for k in 3:
		var ln := 3 + int(V.hs(k, v, 5) * 4)
		for y in ln:
			V.p(vb, [0, 4, 2][k], 3 - y, [2, 3, 5][k], V.leaves(k, 0).call(Vector3i(k, y, v)))


## Bath step stool (white with a pink top) for kids at the sink.
static func m_step_stool(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 9, 5, 6, V.noisy(Color("f4f2ee"), 0.03))
	vb.clear_box(Vector3i(2, 0, 0), Vector3i(5, 3, 6))
	V.b(vb, 0, 5, 0, 9, 1, 6, Color("f2b5c6"))
