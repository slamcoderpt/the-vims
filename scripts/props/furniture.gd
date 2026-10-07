extends RefCounted
## Furniture models. Every `m_<name>(vb, v)` writes one model into `vb` in
## 1/16 m cells with its footprint starting at (0,0,0) and its FRONT facing +Z
## (the side a sim uses it from / looks at it from). `v` picks a variant.
## Use through PropLib (scripts/props/prop_lib.gd), not directly.

const V := preload("res://scripts/props/vox_util.gd")

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const WOOD_L := Color("d1a06a")
const WOOD_R := Color("94592f")  # reddish
const PAINT_W := Color("f2ece2")
const DARK := Color("3b3e47")
const METAL := Color("b9bcc4")


# ------------------------------------------------------------------ desks

static func m_desk(vb: VoxelBuilder, v: int) -> void:
	if v == 1:
		# Kid's desk (1.0 x 0.56 m, 0.62 m high), white with wood top.
		V.b(vb, 0, 9, 0, 16, 1, 9, V.wood(WOOD_L, 0, 3))
		V.b(vb, 0, 0, 0, 1, 9, 1, PAINT_W); V.b(vb, 15, 0, 0, 1, 9, 1, PAINT_W)
		V.b(vb, 0, 0, 8, 1, 9, 1, PAINT_W); V.b(vb, 15, 0, 8, 1, 9, 1, PAINT_W)
		V.b(vb, 9, 6, 1, 6, 3, 8, PAINT_W)
		V.b(vb, 10, 7, 9, 4, 1, 1, Color("e8a0b4"))
		V.b(vb, 1, 7, 0, 14, 2, 1, PAINT_W)
		return
	# Work desk 1.75 x 0.75 m, 0.75 m high, two drawer pedestals.
	var top := V.wood(WOOD, 0, 3)
	V.b(vb, 0, 11, 0, 28, 1, 12, top)
	V.b(vb, 0, 10, 11, 28, 1, 1, V.shade(WOOD_D, 1.05))
	for px: int in [0, 20]:
		V.b(vb, px, 0, 0, 8, 10, 11, V.wood(WOOD_D, 1, 3, 0.05))
		for k in 3:
			var y0 := 1 + k * 3
			V.b(vb, px, y0, 11, 8, 3, 1, V.shade(WOOD, 1.0 - k * 0.03))
			V.b(vb, px, y0 + 2, 11, 8, 1, 1, V.shade(WOOD_D, 0.85))
			V.p(vb, px + 3, y0 + 1, 12, Color("e6d3a0")); V.p(vb, px + 4, y0 + 1, 12, Color("e6d3a0"))
	V.b(vb, 8, 4, 0, 12, 6, 1, WOOD_D)


static func m_office_chair(vb: VoxelBuilder, v: int) -> void:
	var cush := Color("e46d78") if v == 1 else Color("4b505c")
	var bh := 6 if v == 2 else 10   # v2: low back (never hides a seated sim's head)
	var frame := DARK
	# Star base + wheels.
	V.b(vb, 4, 1, 0, 1, 1, 9, frame); V.b(vb, 0, 1, 4, 9, 1, 1, frame)
	for q in [Vector2i(4, 0), Vector2i(4, 8), Vector2i(0, 4), Vector2i(8, 4)]:
		V.p(vb, q.x, 0, q.y, Color("222428"))
	V.b(vb, 4, 2, 4, 1, 3, 1, METAL)
	# Seat (top at y=7 -> 0.44 m).
	V.b(vb, 0, 5, 1, 9, 2, 8, V.noisy(cush, 0.05))
	V.b(vb, 1, 4, 2, 7, 1, 6, frame)
	# Back.
	V.b(vb, 1, 7, 0, 7, bh, 2, V.noisy(cush, 0.05))
	V.b(vb, 2, 7 + bh - 1, 0, 5, 1, 2, V.noisy(cush, 0.05))
	V.b(vb, 4, 6, 0, 1, 2, 1, frame)
	# Arm rests.
	for ax: int in [0, 8]:
		V.b(vb, ax, 7, 3, 1, 2, 1, frame)
		V.b(vb, ax, 9, 2, 1, 1, 5, frame)


static func m_chair(vb: VoxelBuilder, v: int) -> void:
	# Wooden chair, seat top at y=7.
	var c: Color = [WOOD, PAINT_W, Color("e9a3b8"), Color("7f97d6")][v % 4]
	var seat := V.wood(c, 0, 2) if v == 0 else V.noisy(c, 0.04)
	for q in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 7), Vector2i(7, 7)]:
		V.b(vb, q.x, 0, q.y, 1, 6, 1, V.shade(c, 0.85))
	V.b(vb, 0, 6, 0, 8, 1, 8, seat)
	V.b(vb, 0, 7, 0, 1, 8, 1, V.shade(c, 0.85)); V.b(vb, 7, 7, 0, 1, 8, 1, V.shade(c, 0.85))
	V.b(vb, 1, 11, 0, 6, 3, 1, seat)
	V.b(vb, 1, 8, 0, 6, 1, 1, seat)


static func m_stool(vb: VoxelBuilder, v: int) -> void:
	# Kid's stool, seat top at y=6 (0.375 m).
	var c: Color = [WOOD_L, Color("f0b8c8"), Color("9db6e8")][v % 3]
	V.b(vb, 0, 5, 0, 6, 1, 6, V.wood(c, 0, 2))
	V.b(vb, 1, 4, 1, 4, 1, 4, V.shade(c, 0.8))
	for q in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)]:
		V.b(vb, q.x, 0, q.y, 1, 5, 1, V.shade(WOOD, 0.9))
	V.b(vb, 1, 2, 0, 4, 1, 1, WOOD_D); V.b(vb, 1, 2, 5, 4, 1, 1, WOOD_D)


# ------------------------------------------------------------------ storage

## Bookshelves. v0 tall 1.0 m, v1 low, v2 narrow tall, v3 cube storage with
## baskets, v4 tall corner shelf with globe + trophy (ref1).
static func m_bookshelf(vb: VoxelBuilder, v: int) -> void:
	var w := 16
	var h := 30
	var d := 6
	var shelves := [1, 7, 13, 19, 24]
	match v:
		1:
			h = 12; shelves = [1, 6]
		2:
			w = 10
		3:
			w = 18; h = 18; shelves = [1, 9]
	var wc := V.wood(WOOD_R if v != 3 else PAINT_W, 1, 2, 0.05)
	V.b(vb, 0, 0, 0, 1, h, d, wc)
	V.b(vb, w - 1, 0, 0, 1, h, d, wc)
	V.b(vb, 0, h - 1, 0, w, 1, d, wc)
	V.b(vb, 1, 0, 0, w - 2, h - 1, 1, V.shade(WOOD_D if v != 3 else Color("e5ddd0"), 0.85))
	for i in shelves.size():
		var sy: int = shelves[i]
		V.b(vb, 1, sy - 1, 0, w - 2, 1, d, wc)
		var top: int = shelves[i + 1] - 1 if i + 1 < shelves.size() else h - 1
		var ch := top - sy
		var inner := w - 2
		if v == 3:
			# Cube storage: two baskets per row.
			var bc: Array = [Color("e8c27a"), Color("9ec3e6"), Color("f2a3b7"), Color("bcd98f")]
			for k in 2:
				var bx := 1 + k * (inner / 2)
				V.b(vb, bx + 1, sy, 1, inner / 2 - 2, ch - 2, d - 1, V.noisy(bc[(i * 2 + k) % 4], 0.08))
				V.b(vb, bx + 3, sy + ch - 4, d, 2, 1, 1, V.shade(bc[(i * 2 + k) % 4], 0.7))
			V.b(vb, 1 + inner / 2 - 1, sy, 0, 1, ch, d, wc)
			continue
		var kind: int = int(V.hs(i, v, w) * 4.0) if v != 4 else [0, 3, 1, 2, 4][i]
		if v == 1 and i == 1:
			kind = 1
		match kind:
			0:
				V.books(vb, 1, sy, 1, inner, ch - 1, d - 2, i * 13 + v)
			1:
				V.books(vb, 1, sy, 1, inner - 6, ch - 1, d - 2, i * 7 + v)
				_pot_plant(vb, w - 6, sy, 1, mini(ch, 6), i)
			2:
				V.books(vb, 1, sy, 1, inner - 7, ch - 1, d - 2, i * 5 + v)
				V.b(vb, w - 7, sy, 1, 6, mini(ch - 1, 4), d - 2, V.noisy(Color("e9e2d4"), 0.04))
				V.b(vb, w - 5, sy + 2, d - 1, 2, 1, 1, Color("b9ae9a"))
			3:
				# Globe + a couple of books.
				V.books(vb, 1, sy, 1, 6, ch - 1, d - 2, i * 3 + v)
				V.b(vb, w - 6, sy, 2, 3, 1, 3, WOOD_D)
				V.b(vb, w - 5, sy + 1, 3, 1, 1, 1, Color("c9a54a"))
				V.blob(vb, Vector3(w - 4.5, sy + 3.6, 3.5), Vector3(2.2, 2.2, 2.2), V.mix([Color("3d7fc4"), Color("3d7fc4"), Color("5b9b48"), Color("4a8cd0")], 3), 0.0, 0.0)
			4:
				# Trophy + boxes.
				V.b(vb, 2, sy, 1, 6, 3, d - 2, V.noisy(Color("d8cbb2"), 0.05))
				V.b(vb, w - 6, sy, 2, 3, 1, 2, WOOD_D)
				V.b(vb, w - 5, sy + 1, 2, 1, 2, 2, Color("e2b33c"))
				V.b(vb, w - 6, sy + 3, 2, 3, 2, 2, Color("f0c44a"))
	if v == 4 or v == 0:
		# Top dressing.
		V.books(vb, 2, h, 1, 4, 3, 3, 99 + v)
		_pot_plant(vb, w - 7, h, 1, 6, v + 4)


static func _pot_plant(vb: VoxelBuilder, x: int, y: int, z: int, h: int, seed: int) -> void:
	var pot: Color = [Color("c8643c"), Color("e8e2d6"), Color("d97b4f"), Color("6f8fae")][seed % 4]
	V.b(vb, x + 1, y, z + 1, 3, 2, 3, V.noisy(pot, 0.05))
	V.b(vb, x, y + 1, z, 5, 1, 5, V.shade(pot, 1.08))
	V.blob(vb, Vector3(x + 2.5, y + 2.0 + h * 0.3, z + 2.5), Vector3(2.8, maxf(1.6, h * 0.45), 2.8), V.leaves(seed), 0.0, 0.5, seed)


static func m_filing_cabinet(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 7, 12, 9, V.noisy(Color("c7c9cc"), 0.03))
	for k in 3:
		V.b(vb, 0, 3 + k * 4, 9, 7, 1, 1, Color("9a9da3"))
		V.b(vb, 2, 1 + k * 4, 9, 3, 1, 1, Color("6f7279"))
	V.b(vb, 0, 0, 9, 7, 1, 1, Color("8d9097"))


static func m_dresser(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [WOOD, PAINT_W, Color("f3c9d4"), Color("a9bce8")][v % 4]
	V.b(vb, 0, 1, 0, 16, 12, 8, V.noisy(c, 0.04))
	V.b(vb, 0, 13, 0, 16, 1, 8, V.wood(WOOD_L if v != 0 else WOOD, 0, 2))
	for k in 3:
		V.b(vb, 1, 2 + k * 4, 8, 14, 3, 1, V.shade(c, 1.06))
		V.p(vb, 5, 3 + k * 4, 9, Color("d8b46a")); V.p(vb, 10, 3 + k * 4, 9, Color("d8b46a"))
	for q in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 7), Vector2i(15, 7)]:
		V.p(vb, q.x, 0, q.y, WOOD_D)


static func m_nightstand(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [WOOD, PAINT_W, Color("f3c9d4"), Color("a9bce8")][v % 4]
	V.b(vb, 0, 1, 0, 8, 8, 8, V.noisy(c, 0.04))
	V.b(vb, 0, 9, 0, 8, 1, 8, V.wood(WOOD_L, 0, 2))
	V.b(vb, 1, 5, 8, 6, 3, 1, V.shade(c, 1.06))
	V.p(vb, 4, 6, 9, Color("d8b46a"))
	V.b(vb, 0, 0, 0, 1, 1, 1, WOOD_D); V.b(vb, 7, 0, 0, 1, 1, 1, WOOD_D)
	V.b(vb, 0, 0, 7, 1, 1, 1, WOOD_D); V.b(vb, 7, 0, 7, 1, 1, 1, WOOD_D)


# ------------------------------------------------------------------ beds / sofas

## Single bed 1.12 x 2.12 m, mattress top at y=8 (0.5 m). Head at z=0.
## v0 pink gingham (bunny girl), v1 navy star quilt (cat girl), v2 parents' double.
static func m_bed(vb: VoxelBuilder, v: int) -> void:
	if v == 3:
		_bunny_canopy_bed(vb)
		return
	var w := 18 if v != 2 else 28
	var l := 28 if v != 2 else 34
	v = v % 3
	var frame: Color = [Color("f3a9c0"), WOOD, WOOD_R][v]
	var fr := V.noisy(frame, 0.04) if v == 0 else V.wood(frame, 2, 2)
	# Legs & rails.
	V.b(vb, 0, 0, 0, w, 5, 2, fr)
	V.b(vb, 0, 0, l - 2, w, 5, 2, fr)
	V.b(vb, 0, 2, 2, 1, 3, l - 4, fr)
	V.b(vb, w - 1, 2, 2, 1, 3, l - 4, fr)
	# Headboard (rounded) and footboard.
	V.b(vb, 0, 5, 0, w, 12, 2, fr)
	V.b(vb, 1, 17, 0, w - 2, 1, 2, fr)
	V.b(vb, 3, 18, 0, w - 6, 1, 2, fr)
	V.b(vb, 0, 5, l - 2, w, 4, 2, fr)
	if v == 0:
		# Bunny ears on the headboard (ref3).
		for ex: int in [3, w - 6]:
			V.b(vb, ex, 19, 0, 3, 6, 2, fr)
			V.b(vb, ex + 1, 25, 0, 1, 1, 2, fr)
			V.b(vb, ex + 1, 20, 2, 1, 4, 1, Color("fbe3ea"))
	if v == 1:
		# Star on the headboard.
		for q in [Vector2i(8, 19), Vector2i(9, 19), Vector2i(8, 20), Vector2i(9, 20), Vector2i(7, 19), Vector2i(10, 19), Vector2i(8, 21), Vector2i(9, 21)]:
			V.p(vb, q.x, q.y, 0, Color("f7d454"))
	if v == 0:
		# Heart cut-out on the headboard.
		for q in [Vector2i(7, 13), Vector2i(8, 12), Vector2i(9, 12), Vector2i(10, 13), Vector2i(8, 14), Vector2i(9, 14), Vector2i(7, 14), Vector2i(10, 14), Vector2i(8, 13), Vector2i(9, 13)]:
			V.p(vb, q.x, q.y, 2, Color("ffffff"))
	if v == 1:
		for k in range(1, w - 1, 3):
			V.b(vb, k, 9, l - 2, 1, 2, 2, fr)
		V.b(vb, 0, 11, l - 2, w, 1, 2, fr)
	# Mattress.
	V.b(vb, 1, 5, 2, w - 2, 3, l - 4, V.noisy(Color("f6f3ee"), 0.03))
	# Quilt (top + draped sides).
	var quilt: Callable
	match v:
		0:
			quilt = V.plaid(Color("f7b6c8"), Color("ef8fab"), Color("e36f92"), 2)
		1:
			var navy := Color("34468f")
			quilt = func(q: Vector3i) -> Color:
				var hh := VoxelBuilder.hash3(q * 3 + Vector3i(1, 2, 3))
				if hh > 0.93:
					return Color("f7d454")
				return V.shade(navy, 0.95 + VoxelBuilder.hash3(q) * 0.1) if posmod(q.x + q.z, 6) != 0 else Color("4c5fb0")
		_:
			quilt = V.plaid(Color("e8e0cf"), Color("c96a55"), Color("a24c3d"), 4)
	var qz := 10 if l < 30 else 12
	V.b(vb, 0, 8, qz, w, 1, l - 2 - qz, quilt)
	V.b(vb, 0, 4, qz, 1, 4, l - 2 - qz, quilt)
	V.b(vb, w - 1, 4, qz, 1, 4, l - 2 - qz, quilt)
	# Folded sheet band.
	V.b(vb, 0, 8, qz - 2, w, 1, 2, Color("fbfbf8") if v != 1 else Color("f2f0ea"))
	# Pillow(s).
	if v == 2:
		V.b(vb, 2, 8, 3, 11, 2, 6, Color("fbfaf6")); V.b(vb, 15, 8, 3, 11, 2, 6, Color("fbfaf6"))
	else:
		V.b(vb, 2, 8, 3, w - 4, 2, 6, Color("fdfcf9"))
		V.b(vb, 3, 10, 4, w - 6, 1, 4, Color("fdfcf9"))


## Raised pink bunny bed with a tall headboard, canopy crown + sheer drapes
## at the head end, two pillows, plaid quilt and a frilled bed skirt (ref3).
## 18 x 40 x 28 cells; mattress top at y = 10 (lie height 10 cells).
static func _bunny_canopy_bed(vb: VoxelBuilder) -> void:
	var w := 18
	var l := 28
	var pink := Color("f29ab6")
	var pink_l := Color("f9c6d5")
	var fr := V.noisy(pink, 0.035)
	var white := Color("fdfbf8")
	# Turned legs + side rails (raised bed).
	for q in [Vector2i(0, 0), Vector2i(w - 2, 0), Vector2i(0, l - 2), Vector2i(w - 2, l - 2)]:
		V.b(vb, q.x, 0, q.y, 2, 4, 2, V.shade(pink, 0.82))
	V.b(vb, 0, 4, 1, 1, 3, l - 2, fr)
	V.b(vb, w - 1, 4, 1, 1, 3, l - 2, fr)
	# Frilled skirt under the quilt (scalloped hem).
	for z in range(2, l - 2):
		for x: int in [0, w - 1]:
			var hem := 3 if posmod(z, 3) == 1 else 4
			V.b(vb, x, hem, z, 1, 7 - hem, 1, V.shade(pink_l, 1.0 if posmod(z, 3) != 0 else 0.92))
	# Mattress.
	V.b(vb, 1, 6, 2, w - 2, 4, l - 4, V.noisy(white, 0.02))
	# Tall headboard with a rounded crest, tufted panel and a heart.
	V.b(vb, 0, 4, 0, w, 16, 2, fr)
	V.b(vb, 1, 20, 0, w - 2, 1, 2, fr)
	V.b(vb, 3, 21, 0, w - 6, 1, 2, fr)
	for x in range(2, w - 2):
		for y in range(11, 19):
			if posmod(x + y, 3) == 0:
				V.p(vb, x, y, 2, V.shade(pink_l, 1.04))
			else:
				V.p(vb, x, y, 2, pink_l)
	for q in [Vector2i(7, 15), Vector2i(8, 16), Vector2i(9, 16), Vector2i(10, 15), Vector2i(7, 16), Vector2i(10, 16), Vector2i(8, 15), Vector2i(9, 15), Vector2i(8, 14), Vector2i(9, 14), Vector2i(9, 17), Vector2i(8, 17), Vector2i(7, 17), Vector2i(10, 17)]:
		if q.y == 17 and (q.x == 8 or q.x == 9):
			continue
		V.p(vb, q.x, q.y, 3, Color("e35d86"))
	# Bunny ears on the crest.
	for ex: int in [3, w - 6]:
		V.b(vb, ex, 22, 0, 3, 6, 2, fr)
		V.b(vb, ex + 1, 28, 0, 1, 1, 2, fr)
		V.b(vb, ex + 1, 23, 2, 1, 4, 1, Color("fde4ec"))
	# Canopy: two slim posts at the head corners, a scalloped crown and sheer
	# drapes tied back at the sides (they frame the sleeper, never cover her).
	var post := V.shade(pink, 0.9)
	V.b(vb, -1, 0, 0, 1, 31, 1, post)
	V.b(vb, w, 0, 0, 1, 31, 1, post)
	V.b(vb, -2, 31, -1, w + 4, 1, 6, fr)
	V.b(vb, -1, 32, 0, w + 2, 1, 4, V.shade(pink, 1.06))
	V.b(vb, 3, 33, 0, w - 6, 1, 2, V.shade(pink, 1.1))
	for x in range(-2, w + 2):
		if posmod(x, 3) != 2:
			V.p(vb, x, 30, 4, pink_l)
	V.b(vb, -2, 30, -1, 1, 1, 6, pink_l); V.b(vb, w + 1, 30, -1, 1, 1, 6, pink_l)
	var sheer := V.noisy(Color("fde9ef"), 0.03)
	for side: int in [-2, w + 1]:
		for y in range(12, 30):
			var depth := 4 if y > 25 else (2 if y < 18 else 3)
			V.b(vb, side, y, 0, 1, 1, depth, sheer)
		V.b(vb, side, 18, 0, 1, 1, 3, pink)
	# Pillows (two plump white ones + a pink heart cushion).
	V.b(vb, 2, 10, 2, 6, 3, 5, white); V.b(vb, 3, 13, 3, 4, 1, 3, white)
	V.b(vb, 10, 10, 2, 6, 3, 5, white); V.b(vb, 11, 13, 3, 4, 1, 3, white)
	# Quilt: pink gingham top, draped sides, white folded band.
	var quilt := V.plaid(Color("f7b2c6"), Color("ee8aa8"), Color("e06890"), 2)
	var qz := 10
	V.b(vb, 0, 10, qz, w, 1, l - 2 - qz, quilt)
	V.b(vb, 0, 6, qz, 1, 4, l - 2 - qz, quilt)
	V.b(vb, w - 1, 6, qz, 1, 4, l - 2 - qz, quilt)
	V.b(vb, 0, 6, l - 3, w, 4, 1, quilt)
	V.b(vb, 0, 10, qz - 2, w, 1, 2, white)
	# Footboard (low, scalloped).
	V.b(vb, 0, 4, l - 2, w, 6, 2, fr)
	for x in range(0, w):
		if posmod(x, 4) != 0:
			V.p(vb, x, 10, l - 1, fr.call(Vector3i(x, 10, l - 1)))
	V.b(vb, 6, 7, l - 1, 6, 2, 1, pink_l)


## Turned-down quilt to lay over a sim in bed (16 x 3 x 15), v as m_bed.
static func m_blanket(vb: VoxelBuilder, v: int) -> void:
	var quilt: Callable = V.plaid(Color("f7b6c8"), Color("ef8fab"), Color("e36f92"), 2) if v == 0 else V.noisy(Color("34468f"), 0.06)
	# Low mound (a small sim under it), folded white sheet band at the top.
	V.b(vb, 0, 0, 0, 16, 1, 15, quilt)
	V.b(vb, 2, 1, 2, 12, 1, 11, quilt)
	V.b(vb, 0, 1, 0, 16, 1, 2, Color("fbfbf8"))


static func m_sofa(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("8faa87"), Color("e2b456"), Color("8b9bbd"), Color("c97b5c")][v % 4]
	var fab := V.noisy(c, 0.05)
	V.b(vb, 1, 0, 1, 1, 2, 1, WOOD_D); V.b(vb, 32, 0, 1, 1, 2, 1, WOOD_D)
	V.b(vb, 1, 0, 12, 1, 2, 1, WOOD_D); V.b(vb, 32, 0, 12, 1, 2, 1, WOOD_D)
	V.b(vb, 0, 2, 0, 34, 3, 14, V.shade(c, 0.85))
	V.b(vb, 0, 2, 0, 34, 11, 4, fab)
	V.b(vb, 0, 2, 0, 4, 9, 14, fab); V.b(vb, 30, 2, 0, 4, 9, 14, fab)
	for k in 2:
		V.b(vb, 4 + k * 13, 5, 4, 13, 2, 10, V.noisy(V.shade(c, 1.06), 0.04))
		V.b(vb, 4 + k * 13, 7, 4, 13, 5, 2, V.noisy(V.shade(c, 1.03), 0.04))
	V.b(vb, 16, 5, 4, 1, 2, 10, V.shade(c, 0.8))
	# Throw pillows.
	V.b(vb, 5, 7, 5, 5, 5, 2, Color("f3e3c3"))
	V.b(vb, 24, 7, 5, 5, 5, 2, Color("e78a6f"))


static func m_armchair(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("c97b5c"), Color("8faa87"), Color("e2b456")][v % 3]
	var fab := V.noisy(c, 0.05)
	V.b(vb, 1, 0, 1, 1, 2, 1, WOOD_D); V.b(vb, 13, 0, 1, 1, 2, 1, WOOD_D)
	V.b(vb, 1, 0, 12, 1, 2, 1, WOOD_D); V.b(vb, 13, 0, 12, 1, 2, 1, WOOD_D)
	V.b(vb, 0, 2, 0, 15, 5, 14, fab)
	V.b(vb, 0, 7, 0, 15, 7, 4, fab)
	V.b(vb, 0, 7, 0, 3, 3, 14, fab); V.b(vb, 12, 7, 0, 3, 3, 14, fab)


# ------------------------------------------------------------------ tables

static func m_coffee_table(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 5, 0, 20, 1, 11, V.wood(WOOD, 0, 2))
	V.b(vb, 1, 2, 1, 18, 1, 9, V.wood(WOOD_D, 0, 2))
	for q in [Vector2i(0, 0), Vector2i(19, 0), Vector2i(0, 10), Vector2i(19, 10)]:
		V.b(vb, q.x, 0, q.y, 1, 5, 1, WOOD_D)
	# Magazines + mug.
	V.b(vb, 3, 6, 3, 5, 1, 4, Color("e86f5a")); V.b(vb, 4, 7, 3, 5, 1, 4, Color("f2e5c4"))
	V.b(vb, 14, 6, 5, 2, 2, 2, Color("f5f2ea"))


static func m_dining_table(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 11, 0, 26, 1, 14, V.wood(WOOD, 0, 3))
	for q in [Vector2i(1, 1), Vector2i(24, 1), Vector2i(1, 12), Vector2i(24, 12)]:
		V.b(vb, q.x, 0, q.y, 1, 11, 1, WOOD_D)
	V.b(vb, 1, 9, 1, 24, 2, 1, WOOD_D); V.b(vb, 1, 9, 12, 24, 2, 1, WOOD_D)
	# Fruit bowl.
	V.b(vb, 10, 12, 5, 6, 1, 4, Color("f1ede4"))
	V.b(vb, 11, 13, 5, 2, 2, 2, Color("e0442f")); V.b(vb, 13, 13, 6, 2, 2, 2, Color("f0b532")); V.b(vb, 12, 13, 7, 2, 1, 2, Color("8fc44a"))


## Small side table; v1 = art supplies table (paint jars, brushes), v2 round white.
static func m_side_table(vb: VoxelBuilder, v: int) -> void:
	var c := WOOD if v != 2 else PAINT_W
	V.b(vb, 0, 10, 0, 10, 1, 9, V.wood(c, 0, 2))
	for q in [Vector2i(0, 0), Vector2i(9, 0), Vector2i(0, 8), Vector2i(9, 8)]:
		V.b(vb, q.x, 0, q.y, 1, 10, 1, V.shade(c, 0.8))
	V.b(vb, 1, 4, 1, 8, 1, 7, V.wood(V.shade(c, 0.9), 0, 2))
	if v == 1:
		var jars := [Color("e8413a"), Color("3a7fe0"), Color("f2c53a"), Color("53b34a"), Color("ea7bc0")]
		for k in jars.size():
			V.b(vb, 1 + (k % 3) * 3, 11, 1 + (k / 3) * 3, 2, 2, 2, Color("e9f2f5"))
			V.b(vb, 1 + (k % 3) * 3, 13, 1 + (k / 3) * 3, 2, 1, 2, jars[k])
		# Brush cup.
		V.b(vb, 7, 11, 5, 2, 3, 2, Color("6a8fc0"))
		V.p(vb, 7, 14, 5, Color("c98a4a")); V.p(vb, 8, 15, 6, Color("c98a4a")); V.p(vb, 7, 16, 6, Color("2b2b2b"))
		# Stacked art supplies below.
		V.b(vb, 1, 5, 1, 7, 2, 6, Color("f2e8d0")); V.b(vb, 2, 7, 2, 5, 1, 4, Color("e8607a"))


# ------------------------------------------------------------------ music / art

static func m_piano(vb: VoxelBuilder, _v: int) -> void:
	# Digital piano on an X stand (ref1), keys along X, player at +Z. The white
	# key bed runs the full front so it reads as a keyboard from above.
	var blk := Color("2a2b31")
	for side in [2, 24]:
		for k in 11:
			var dz := int(round(k * 5.0 / 10.0))
			V.p(vb, side, k, dz, blk); V.p(vb, side + 1, k, dz, blk)
			V.p(vb, side, k, 5 - dz, blk); V.p(vb, side + 1, k, 5 - dz, blk)
	V.b(vb, 0, 11, 0, 28, 2, 4, V.noisy(blk, 0.04))
	V.b(vb, 0, 11, 4, 28, 1, 5, blk)
	V.b(vb, 0, 11, 0, 1, 3, 9, blk); V.b(vb, 27, 11, 0, 1, 3, 9, blk)
	# White keys (with gaps), then short black keys at the back of the key bed.
	for x in range(1, 27):
		V.b(vb, x, 12, 4, 1, 1, 5, Color("fbfaf6") if x % 2 == 0 else Color("ecE8e0"))
	for x in range(1, 27):
		var m := x % 7
		if m == 1 or m == 2 or m == 4 or m == 5 or m == 6:
			V.b(vb, x, 13, 4, 1, 1, 2, Color("16161a"))
	V.b(vb, 3, 13, 1, 3, 1, 1, Color("4fd07a"), true)
	V.b(vb, 22, 13, 1, 3, 1, 1, Color("e05050"), true)
	# Sheet music stand.
	V.b(vb, 8, 13, 1, 12, 8, 1, Color("f8f6f0"))
	for k in 3:
		V.b(vb, 9, 16 + k * 2, 2, 10, 1, 1, Color("8e8a86"))
	V.b(vb, 8, 13, 2, 12, 1, 1, blk)


static func m_piano_bench(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 5, 0, 12, 2, 6, V.noisy(Color("2d2e35"), 0.05))
	for q in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 5), Vector2i(11, 5)]:
		V.b(vb, q.x, 0, q.y, 1, 5, 1, Color("26262b"))


static func m_easel(vb: VoxelBuilder, v: int) -> void:
	# A-frame easel, canvas faces +Z.
	var w := V.wood(WOOD_L, 1, 2)
	V.b(vb, 1, 0, 3, 1, 26, 1, w); V.b(vb, 12, 0, 3, 1, 26, 1, w)
	V.b(vb, 6, 0, 0, 2, 24, 1, w)
	V.b(vb, 1, 26, 3, 12, 1, 1, w)
	V.b(vb, 0, 9, 3, 14, 1, 3, w)
	# Canvas.
	var cw := 12
	var chh := 14
	var cx := 1
	var cy := 10
	V.b(vb, cx, cy, 4, cw, chh, 1, Color("fbf8f0"))
	if v == 0:
		# A pink bunny with green grass & blue sky dabs.
		for x in cw:
			for y in chh:
				var q := Vector3i(cx + x, cy + y, 5)
				var col := Color(0, 0, 0, 0)
				if y < 3:
					col = Color("6fbf4f") if V.hs(x, y, 1) > 0.25 else Color("8fd162")
				elif y > 10 and V.hs(x, y, 2) > 0.4:
					col = Color("9fd0f0")
				var bx := x - 6
				var by := y - 6
				if bx * bx + by * by * 1.4 < 9.0:
					col = Color("f59ab8")
				if (x == 4 or x == 7) and y >= 8 and y <= 12:
					col = Color("f59ab8")
				if (x == 5 or x == 6) and y == 6:
					col = Color("2a2030")
				if x == 9 and y == 4:
					col = Color("f2c53a")
				if col.a > 0.0:
					V.p(vb, q.x, q.y, q.z, col)
	# Tray items.
	V.b(vb, 3, 10, 5, 2, 1, 1, Color("e8413a")); V.b(vb, 9, 10, 5, 2, 1, 1, Color("3a7fe0"))


static func m_guitar(vb: VoxelBuilder, _v: int) -> void:
	# Acoustic guitar standing on the floor, back against z=0.
	var body := Color("cf8238")
	V.b(vb, 0, 0, 0, 7, 4, 2, V.noisy(body, 0.04))
	V.b(vb, 1, 4, 0, 5, 1, 2, V.noisy(body, 0.04))
	V.b(vb, 1, 5, 0, 5, 3, 2, V.noisy(body, 0.04))
	V.b(vb, 0, 1, 0, 7, 2, 2, V.noisy(body, 0.04))
	V.b(vb, 2, 3, 2, 3, 3, 1, V.shade(body, 0.75))
	V.b(vb, 3, 4, 2, 1, 1, 1, Color("2a1a10"))
	V.b(vb, 2, 1, 2, 3, 1, 1, Color("3b2414"))
	V.b(vb, 3, 8, 1, 1, 12, 1, Color("5b3820"))
	V.b(vb, 2, 20, 1, 3, 3, 1, Color("3b2414"))
	V.b(vb, 3, 5, 2, 1, 15, 1, Color("e6e0d0"))


# ------------------------------------------------------------------ kitchen

static func m_counter(vb: VoxelBuilder, v: int) -> void:
	# Base cabinet 1.0 x 0.62 m, top at 0.9 m. v1 = with sink.
	var cab := Color("a9c4b0")
	V.b(vb, 0, 1, 0, 16, 13, 10, V.noisy(cab, 0.03))
	V.b(vb, 0, 0, 0, 16, 1, 9, Color("4b3a2c"))
	V.b(vb, 0, 14, 0, 16, 1, 11, V.noisy(Color("e9e5dc"), 0.04))
	for k in 2:
		V.b(vb, 1 + k * 7 + k, 2, 10, 7, 10, 1, V.shade(cab, 1.07))
		V.b(vb, 3 + k * 8 + (2 if k == 0 else 0), 9, 11, 1, 2, 1, Color("d8b46a"))
	if v == 1:
		V.b(vb, 3, 14, 2, 10, 1, 7, Color("9aa3ad"))
		V.b(vb, 4, 14, 3, 8, 1, 5, Color("6c7782"))
		V.b(vb, 7, 15, 1, 2, 4, 1, METAL); V.b(vb, 7, 18, 2, 2, 1, 2, METAL)
	elif v == 2:
		# Cutting board + bread.
		V.b(vb, 3, 15, 3, 7, 1, 5, WOOD_L)
		V.b(vb, 4, 16, 4, 4, 2, 3, Color("d9a35a"))
		V.b(vb, 12, 15, 2, 2, 4, 2, Color("e5e5e5")); V.b(vb, 12, 19, 2, 2, 1, 2, Color("c9a03a"))


static func m_fridge(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("eae6dc")
	V.b(vb, 0, 0, 0, 13, 30, 11, V.noisy(c, 0.025))
	V.b(vb, 0, 19, 11, 13, 1, 1, Color("c9c4b8"))
	V.b(vb, 10, 21, 11, 1, 6, 1, METAL); V.b(vb, 10, 11, 11, 1, 6, 1, METAL)
	V.b(vb, 2, 23, 11, 3, 3, 1, Color("e96c5a")); V.b(vb, 5, 24, 11, 2, 2, 1, Color("6fb3e0"))
	V.b(vb, 3, 14, 11, 4, 4, 1, Color("fbf6e4"))
	V.b(vb, 4, 15, 12, 2, 2, 1, Color("f2b13a"))


static func m_stove(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 16, 14, 10, V.noisy(Color("eceae6"), 0.02))
	V.b(vb, 0, 14, 0, 16, 1, 10, Color("2b2c30"))
	for q in [Vector2i(3, 2), Vector2i(10, 2), Vector2i(3, 6), Vector2i(10, 6)]:
		V.b(vb, q.x, 15, q.y, 3, 1, 3, Color("4a4b52"))
	V.b(vb, 2, 3, 10, 12, 8, 1, Color("2e3036"))
	V.b(vb, 4, 5, 11, 8, 4, 1, Color("6a5848"), true)
	V.b(vb, 3, 12, 10, 10, 1, 1, METAL)
	V.b(vb, 0, 15, 0, 16, 4, 1, Color("d9d6d0"))
	for k in 4:
		V.p(vb, 3 + k * 3, 16, 1, Color("3a3b40"))
	# Pot on the hob.
	V.b(vb, 9, 16, 5, 5, 3, 4, Color("c94a3c")); V.b(vb, 10, 19, 6, 3, 1, 2, Color("8a2f26"))


static func m_dog_bowl(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 5, 1, 4, Color("d34a3e")); V.b(vb, 1, 1, 0, 3, 1, 4, Color("d34a3e"))
	V.b(vb, 0, 1, 0, 1, 1, 4, Color("d34a3e")); V.b(vb, 4, 1, 0, 1, 1, 4, Color("d34a3e"))
	V.b(vb, 1, 1, 1, 3, 1, 2, Color("9a6234"))
	V.b(vb, 6, 0, 0, 5, 2, 4, Color("3f7fc4")); V.b(vb, 7, 1, 1, 3, 1, 2, Color("9fd3f0"))


# ------------------------------------------------------------------ bathroom

static func m_toilet(vb: VoxelBuilder, _v: int) -> void:
	var w := Color("f7f7f5")
	V.b(vb, 1, 0, 3, 5, 6, 6, V.noisy(w, 0.02))
	V.b(vb, 0, 6, 3, 7, 1, 8, w)
	V.b(vb, 1, 6, 4, 5, 1, 6, Color("d8e6ee"))
	V.b(vb, 0, 6, 0, 7, 8, 3, V.noisy(w, 0.02))
	V.b(vb, 0, 14, 0, 7, 1, 3, Color("e9e9e6"))
	V.p(vb, 5, 13, 3, METAL)


static func m_bathtub(vb: VoxelBuilder, _v: int) -> void:
	# Compact tub (1.4 x 0.8 m authored), rim + water + a few foam bubbles,
	# tap at the x=0 end, pink towel folded on the far rim.
	var w := Color("f8f7f4")
	var L := 22
	var D := 13
	V.b(vb, 0, 1, 0, L, 8, D, V.noisy(w, 0.02))
	for q in [Vector2i(1, 1), Vector2i(L - 2, 1), Vector2i(1, D - 2), Vector2i(L - 2, D - 2)]:
		V.b(vb, q.x, 0, q.y, 1, 1, 1, Color("c9a35a"))
	vb.clear_box(Vector3i(2, 4, 2), Vector3i(L - 4, 5, D - 4))
	V.b(vb, 2, 4, 2, L - 4, 3, D - 4, V.noisy(Color("5aa8dc"), 0.06))
	for k in 9:
		var bx := 3 + int(V.hs(k, 1, 2) * (L - 7))
		var bz := 3 + int(V.hs(k, 3, 4) * (D - 6))
		V.p(vb, bx, 7, bz, Color("ffffff"))
	V.b(vb, 1, 9, 5, 2, 1, 2, METAL); V.b(vb, 1, 9, 5, 1, 4, 1, METAL)
	V.b(vb, L - 7, 9, 0, 6, 2, 3, Color("f2b5c6"))


static func m_shower(vb: VoxelBuilder, v: int) -> void:
	if v == 1:
		_shower_cubicle(vb)
		return
	# 1.0 x 1.0 m glass cubicle; back wall tiles at z=0 and x=0 are the room walls.
	var tray := Color("eef1f2")
	V.b(vb, 0, 0, 0, 16, 1, 16, tray)
	V.b(vb, 6, 1, 6, 4, 1, 4, Color("aab4bb"))
	var fr := Color("9aa6ae")
	V.b(vb, 15, 1, 0, 1, 34, 1, fr); V.b(vb, 15, 1, 15, 1, 34, 1, fr); V.b(vb, 0, 1, 15, 1, 34, 1, fr)
	V.b(vb, 0, 34, 15, 16, 1, 1, fr); V.b(vb, 15, 34, 0, 1, 1, 16, fr)
	V.b(vb, 6, 1, 15, 1, 33, 1, Color("c3d0d6"))
	V.b(vb, 1, 22, 1, 1, 9, 1, METAL); V.b(vb, 1, 30, 1, 4, 1, 1, METAL); V.b(vb, 4, 29, 1, 3, 1, 3, METAL)
	# Towel on the glass door.
	V.b(vb, 9, 22, 16, 5, 1, 1, METAL)
	V.b(vb, 9, 12, 16, 5, 10, 1, V.noisy(Color("f4f1ea"), 0.04))
	V.b(vb, 9, 13, 16, 5, 1, 1, Color("8fb4d8"))


## Corner shower cubicle (1.0 x 1.0 m tray, 2.3 m tall): tiled back + left
## walls of its own (stands in front of a low cut-away wall), bright chrome
## frame on the two glass sides, rain head, towel on a rail on the door.
static func _shower_cubicle(vb: VoxelBuilder) -> void:
	var chrome := Color("e4e9ee")
	var chrome_d := Color("aeb7bf")
	var H := 26
	V.b(vb, 0, 0, 0, 16, 1, 16, Color("f3f5f6"))
	V.b(vb, 1, 1, 1, 14, 1, 14, Color("e2e9ed"))
	V.b(vb, 7, 1, 7, 2, 1, 2, chrome_d)
	var tile := func(q: Vector3i) -> Color:
		var a := q.x + q.z
		var grout := posmod(q.y, 3) == 0 or posmod(a, 3) == 0
		var c := Color("a9d6ea") if posmod(floori(q.y / 3.0) + floori(a / 3.0), 2) == 0 else Color("8cc4de")
		return Color("f2f6f7") if grout else c
	V.b(vb, 0, 1, 0, 16, H, 1, tile)
	V.b(vb, 0, 1, 1, 1, H, 15, tile)
	V.b(vb, 0, H + 1, 0, 16, 1, 1, Color("f2f6f7")); V.b(vb, 0, H + 1, 0, 1, 1, 16, Color("f2f6f7"))
	# Chrome frame on the open edges.
	V.b(vb, 15, 1, 15, 1, H, 1, chrome)
	V.b(vb, 15, 1, 1, 1, H, 1, chrome_d)
	V.b(vb, 1, 1, 15, 1, H, 1, chrome_d)
	V.b(vb, 1, H, 15, 15, 1, 1, chrome); V.b(vb, 15, H, 1, 1, 1, 15, chrome)
	V.b(vb, 1, 1, 15, 15, 1, 1, chrome_d); V.b(vb, 15, 1, 1, 1, 1, 15, chrome_d)
	# Door hinge line + handle.
	V.b(vb, 8, 1, 15, 1, H - 1, 1, chrome_d)
	V.b(vb, 9, 11, 16, 1, 4, 1, chrome)
	# Rain head + mixer + niche with bottles.
	V.b(vb, 2, 16, 1, 1, 8, 1, chrome); V.b(vb, 2, 23, 1, 5, 1, 1, chrome)
	V.b(vb, 5, 22, 1, 4, 1, 4, chrome); V.b(vb, 6, 21, 2, 2, 1, 2, Color("cfdbe2"))
	V.b(vb, 2, 13, 1, 3, 2, 1, chrome)
	V.b(vb, 10, 12, 1, 4, 1, 2, Color("f2f6f7"))
	V.b(vb, 10, 13, 1, 1, 3, 1, Color("f28fb0")); V.b(vb, 12, 13, 1, 1, 2, 1, Color("7ec4e0"))
	# Towel rail on the door with a striped towel.
	V.b(vb, 2, 18, 16, 6, 1, 1, chrome)
	V.b(vb, 2, 8, 16, 6, 10, 1, V.noisy(Color("f7f4ee"), 0.03))
	V.b(vb, 2, 10, 16, 6, 1, 1, Color("8fb4d8")); V.b(vb, 2, 12, 16, 6, 1, 1, Color("8fb4d8"))


## Glass panes for the shower (build with a transparent material).
## v1 matches the cubicle: light-blue panes, a frosted band at mid height.
static func m_shower_glass(vb: VoxelBuilder, v: int) -> void:
	if v == 1:
		# Clear light-blue panes with two soft diagonal glints and a frosted
		# privacy band (reads as glass, not as a tiled grid).
		var gb := func(q: Vector3i) -> Color:
			if q.y >= 11 and q.y <= 14:
				return Color("e2f2f8")
			var d := posmod(q.x + q.z - q.y, 22)
			if d == 3 or d == 4 or d == 9:
				return Color("e8f7fc")
			return Color("a8d8ec")
		V.b(vb, 2, 2, 15, 13, 24, 1, gb)
		V.b(vb, 15, 2, 2, 1, 24, 13, gb)
		return
	var g := Color("bfe2ee")
	V.b(vb, 1, 1, 15, 14, 33, 1, g)
	V.b(vb, 15, 1, 1, 1, 33, 14, g)


static func m_vanity(vb: VoxelBuilder, v: int) -> void:
	if v == 1:
		_vanity_tall(vb)
		return
	V.b(vb, 0, 1, 0, 16, 12, 9, V.wood(WOOD, 1, 2))
	V.b(vb, 0, 0, 1, 16, 1, 7, WOOD_D)
	V.b(vb, 1, 2, 9, 7, 9, 1, V.shade(WOOD, 1.08)); V.b(vb, 8, 2, 9, 7, 9, 1, V.shade(WOOD, 1.04))
	V.p(vb, 6, 8, 10, Color("e8d9a8")); V.p(vb, 9, 8, 10, Color("e8d9a8"))
	V.b(vb, 0, 13, 0, 16, 1, 10, V.noisy(Color("f4f3f0"), 0.02))
	V.b(vb, 4, 13, 3, 8, 1, 5, Color("d7e3ea"))
	V.b(vb, 7, 14, 1, 2, 3, 1, METAL); V.b(vb, 7, 16, 2, 2, 1, 2, METAL)
	# Cup with toothbrushes + soap.
	V.b(vb, 1, 14, 2, 2, 3, 2, Color("8fc6e8")); V.p(vb, 1, 17, 2, Color("f06a8a")); V.p(vb, 2, 17, 3, Color("4fb0e8"))
	V.b(vb, 13, 14, 2, 2, 2, 2, Color("f5d2a8"))
	# Mirror above.
	V.b(vb, 2, 20, 0, 12, 14, 1, WOOD)
	V.b(vb, 3, 21, 0, 10, 12, 1, Color("cfe4ee"))
	V.b(vb, 4, 28, 0, 2, 3, 1, Color("eaf6fb"))


## Wooden vanity (1.0 m) with a white vessel basin, chrome tap and a tall
## framed mirror (ref3), back at z = 0.
static func _vanity_tall(vb: VoxelBuilder) -> void:
	var wc := Color("a86d3e")
	var wd := V.wood(wc, 1, 2)
	V.b(vb, 0, 1, 0, 16, 9, 9, wd)
	V.b(vb, 0, 0, 1, 16, 1, 7, WOOD_D)
	V.b(vb, 1, 2, 9, 7, 5, 1, V.shade(wc, 1.1)); V.b(vb, 8, 2, 9, 7, 5, 1, V.shade(wc, 1.05))
	V.b(vb, 1, 8, 9, 14, 2, 1, V.shade(wc, 1.12))
	V.b(vb, 6, 8, 10, 4, 1, 1, Color("e8d9a8"))
	V.p(vb, 6, 4, 10, Color("e8d9a8")); V.p(vb, 9, 4, 10, Color("e8d9a8"))
	# Counter top.
	V.b(vb, 0, 10, 0, 16, 1, 10, V.noisy(Color("efe9e0"), 0.03))
	# Vessel basin (white bowl standing on the counter).
	V.b(vb, 4, 11, 2, 8, 2, 6, Color("fbfbfa"))
	V.b(vb, 5, 12, 3, 6, 1, 4, Color("c8dfe9"))
	# Tall chrome tap.
	V.b(vb, 7, 11, 0, 2, 4, 1, Color("dfe4e9")); V.b(vb, 7, 14, 1, 2, 1, 2, Color("dfe4e9"))
	V.p(vb, 6, 13, 0, Color("c3ccd3")); V.p(vb, 9, 13, 0, Color("c3ccd3"))
	# Toothbrush cup, soap, a tiny plant.
	V.b(vb, 1, 11, 2, 2, 3, 2, Color("8fc6e8")); V.p(vb, 1, 14, 2, Color("f06a8a")); V.p(vb, 2, 14, 3, Color("4fb0e8"))
	V.b(vb, 13, 11, 3, 2, 1, 2, Color("f5d2a8"))
	V.b(vb, 13, 11, 6, 2, 2, 2, Color("d9774a")); V.b(vb, 13, 13, 6, 2, 2, 2, Color("5e9c45"))
	# Tall framed mirror (dark wood frame so it reads against a pale wall).
	V.b(vb, 1, 15, 0, 14, 19, 1, Color("6e4426"))
	V.b(vb, 1, 15, 1, 14, 1, 1, Color("6e4426")); V.b(vb, 1, 33, 1, 14, 1, 1, Color("7d4f2b"))
	V.b(vb, 1, 15, 1, 1, 19, 1, Color("7d4f2b")); V.b(vb, 14, 15, 1, 1, 19, 1, Color("7d4f2b"))
	for x in range(2, 14):
		for yy in range(16, 33):
			var t := float(yy - 16) / 17.0
			var c := Color("8fc3dc").lerp(Color("d4ecf6"), t)
			if (x + yy) % 9 == 0 or (x + yy) % 9 == 1:
				c = Color("f2fbff")
			V.p(vb, x, yy, 1, c)


static func m_towel_rack(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("f4f1ea"), Color("8fb4d8"), Color("f2b5c6")][v % 3]
	V.b(vb, 0, 14, 0, 8, 1, 2, METAL)
	V.b(vb, 1, 4, 1, 6, 10, 1, V.noisy(c, 0.04))
	V.b(vb, 1, 6, 1, 6, 1, 1, V.shade(c, 0.85))


static func m_bath_mat(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("7fa8d6"), Color("f2b5c6")][v % 2]
	V.b(vb, 0, 0, 0, 12, 1, 8, V.plaid(c, V.shade(c, 0.85), V.shade(c, 1.15), 2))


# ------------------------------------------------------------------ living

static func m_tv(vb: VoxelBuilder, _v: int) -> void:
	# Low TV unit with a flat screen, viewer at +Z.
	V.b(vb, 0, 0, 0, 28, 8, 8, V.wood(WOOD, 0, 3))
	V.b(vb, 1, 1, 8, 12, 6, 1, V.shade(WOOD, 1.08)); V.b(vb, 15, 1, 8, 12, 6, 1, V.shade(WOOD, 1.08))
	V.b(vb, 13, 9, 3, 2, 2, 2, Color("26262b"))
	V.b(vb, 4, 11, 3, 20, 12, 1, Color("1d1e23"))
	V.b(vb, 5, 12, 4, 18, 10, 1, Color("2b4a7a"), true)
	V.b(vb, 6, 13, 4, 7, 4, 1, Color("6aa0d8"), true)
	V.b(vb, 2, 8, 2, 3, 4, 3, Color("e8e2d6"))
