extends RefCounted
## Round 11 room dressing: big wall art, garlands, kids' furniture, bathroom
## bits. Same conventions as decor.gd: 1/16 m authoring cells (shown at
## PropLib.FU), footprint from (0,0,0), front faces +Z, wall-mounted models
## have their back at z = 0.

const V := preload("res://scripts/props/vox_util.gd")

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const CREAM := Color("fbf6ee")


# ------------------------------------------------------------------ wall art

## Large framed poster, back at z=0.
## v0 bunny portrait (pink, 14 x 17), v1 rocket + planets (navy, 13 x 18),
## v2 star map (wide, 20 x 12), v3 flower trio (cream, 18 x 10),
## v4 pixel landscape (wide, 20 x 13), v5 heart + rainbow (12 x 12).
static func m_poster(vb: VoxelBuilder, v: int) -> void:
	var sizes := [Vector2i(14, 17), Vector2i(13, 18), Vector2i(20, 12), Vector2i(18, 10), Vector2i(20, 13), Vector2i(12, 12)]
	var frames := [Color("fdf7f2"), Color("e8c66a"), Color("2c2c35"), Color("b07a46"), Color("5a3a22"), Color("f5f0e6")]
	var s: Vector2i = sizes[v % sizes.size()]
	var fc: Color = frames[v % frames.size()]
	V.b(vb, 0, 0, 0, s.x, s.y, 1, fc)
	for x in s.x:
		for y in s.y:
			var edge := x == 0 or y == 0 or x == s.x - 1 or y == s.y - 1
			V.p(vb, x, y, 1, V.shade(fc, 0.92) if edge else _poster_art(v % 6, x - 1, y - 1, s.x - 2, s.y - 2))


static func _poster_art(v: int, x: int, y: int, w: int, h: int) -> Color:
	match v:
		0:
			# Bunny face on a soft pink ground with little hearts.
			var bg := Color("f9c9d6") if (x + y) % 2 == 0 else Color("f6bccc")
			var cx := w / 2.0 - 0.5
			var hx := (x - cx) / 4.2
			var hy := (y - h * 0.36) / 3.6
			if hx * hx + hy * hy < 1.0:
				if y == int(h * 0.38) and absf(x - cx) > 1.0 and absf(x - cx) < 2.6:
					return Color("3a2a35")
				if y == int(h * 0.27) and absf(x - cx) < 0.8:
					return Color("f07a9a")
				return Color("ffffff")
			for ex: float in [cx - 2.2, cx + 2.2]:
				if absf(x - ex) < 1.1 and y > h * 0.55 and y < h - 1:
					return Color("ffffff") if absf(x - ex) > 0.4 else Color("f7a2bb")
			if V.hs(x, y, 41) > 0.93:
				return Color("ef6f93")
			return bg
		1:
			# Rocket climbing past a ringed planet and stars.
			var cx := w / 2.0 - 0.5
			if absf(x - cx) < 1.6 and y > 3 and y < h - 3:
				if y == h - 6:
					return Color("6ab0e8")
				return Color("eeeef2")
			if absf(x - cx) < 0.6 and y >= h - 3 and y < h - 1:
				return Color("e2463a")
			if absf(x - cx) < 3.0 and y == 4:
				return Color("e2463a")
			if absf(x - cx) < 1.2 and y < 3 and y >= 1:
				return Color("ffb43a") if y == 2 else Color("ffe27a")
			var px := x - w * 0.22
			var py := y - h * 0.78
			if px * px + py * py < 3.2:
				return Color("e88a3a")
			if absf(py) < 0.6 and absf(px) < 3.2:
				return Color("f6d27a")
			if V.hs(x, y, 13) > 0.9:
				return Color("ffe9a0")
			return Color("1f2a5e") if y > h / 2 else Color("26336e")
		2:
			# Star map: constellations on deep navy.
			if V.hs(x, y, 5) > 0.86:
				return Color("fff1b0")
			if (x + y * 2) % 7 == 0 and V.hs(x / 3, y / 3, 9) > 0.55:
				return Color("8ea2e0")
			return Color("1c2552") if (x + y) % 3 != 0 else Color("202a5a")
		3:
			# Three tulips.
			for k in 3:
				var fx := 2 + k * (w - 4) / 2
				if x == fx and y < h - 4:
					return Color("4f9a3c")
				if absf(x - fx) <= 1 and y >= h - 4 and y < h - 1:
					return [Color("f26d8f"), Color("f6c445"), Color("e86a5a")][k]
			return Color("fbf1df")
		4:
			# Pixel landscape: sky, hills, pines, lake.
			var t := float(y) / h
			if y < 2:
				return Color("5e9fd0") if V.hs(x, y, 3) > 0.3 else Color("78b4dc")
			var hill := 3.0 + 2.2 * sin(x * 0.55) + 1.2 * sin(x * 1.3 + 1.0)
			if y < hill:
				return Color("4e8a3f") if V.hs(x, y, 7) > 0.35 else Color("3e7434")
			if (x % 4 == 1) and y < hill + 3:
				return Color("2f5c34")
			var mx := absf(x - w * 0.62) * 0.9
			if y < h - 2 - mx:
				return Color("ffffff") if y > h - 4 - mx else Color("8d9cb8")
			return Color("bfe0f2").lerp(Color("fbe4c4"), t)
		_:
			# Heart with a rainbow arc.
			var cx := w / 2.0 - 0.5
			var r := Vector2(x - cx, y - 1.0).length()
			if r > 6.0 and r < 7.2:
				return Color("e2463a")
			if r > 7.2 and r < 8.4:
				return Color("f6c445")
			if r > 8.4 and r < 9.6:
				return Color("6ab0e8")
			var hx := absf(x - cx)
			if y > 2 and y < 6 and hx < 3.5 - (5 - y) * 0.6 + (1.0 if y >= 4 else 0.0) and not (y == 5 and hx < 0.6):
				return Color("f07a9a")
			return Color("fdf3f5")


## Pennant bunting garland, back at z=0; 44 cells long, flags hang below y=0.
## v0 pink / white / yellow (girl's room), v1 navy / yellow / white (stars).
static func m_bunting(vb: VoxelBuilder, v: int) -> void:
	var cols: Array = [Color("f28fb0"), Color("fbf6ee"), Color("f6c445"), Color("9fd6c8")] if v % 2 == 0 \
		else [Color("34468f"), Color("f6c445"), Color("fbf6ee"), Color("6ab0e8")]
	var n := 8
	for k in n:
		var x0 := k * 5 + 1
		var sag := int(round(2.5 * sin(PI * (k + 0.5) / n)))
		V.b(vb, x0 - 1, 6 - sag, 0, 5, 1, 1, Color("8a7a6a"))
		var c: Color = cols[k % cols.size()]
		for row in 4:
			var half := 2 - row / 2
			for dx in range(-half, half + 1):
				V.p(vb, x0 + 1 + dx, 5 - sag - row, 0, c)


## String of glowing star lights, back at z=0, 40 cells long.
static func m_star_lights(vb: VoxelBuilder, _v: int) -> void:
	for x in 40:
		var y := 8 - int(round(3.0 * sin(PI * x / 39.0)))
		V.p(vb, x, y, 0, Color("4a4038"))
		if x % 6 == 3:
			for d in [Vector2i(0, -1), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(0, -3)]:
				V.p(vb, x + d.x, y + d.y, 1, Color("ffe08a"), true)


## Wall-mounted towel bar with two hanging towels, back at z=0.
static func m_towels(vb: VoxelBuilder, v: int) -> void:
	var metal := Color("c9ccd2")
	V.b(vb, 0, 12, 0, 16, 1, 1, metal)
	V.b(vb, 0, 12, 1, 16, 1, 1, metal)
	var tc: Array = [[Color("f2b5c6"), Color("fbf6ee")], [Color("8fb4d8"), Color("f4f1ea")], [Color("f6d27a"), Color("9fd6c8")]][v % 3]
	for k in 2:
		var c: Color = tc[k]
		var x0 := 1 + k * 8
		V.b(vb, x0, 1 + k * 2, 2, 6, 12 - k * 2, 1, V.noisy(c, 0.04))
		V.b(vb, x0, 11, 1, 6, 2, 1, V.noisy(c, 0.04))
		V.b(vb, x0, 3 + k * 2, 2, 6, 1, 1, V.shade(c, 0.85))


## Wooden bathroom vanity (the ref3 sink unit): two-door cabinet, white top,
## vessel basin with tap, toothbrush cup, soap, little plant. 22 x 14 x 10.
static func m_vanity_unit(vb: VoxelBuilder, _v: int) -> void:
	var wood := V.wood(Color("9a643a"), 1, 2)
	V.b(vb, 0, 0, 0, 22, 13, 10, wood)
	vb.clear_box(Vector3i(1, 0, 9), Vector3i(20, 1, 1))
	for k in 2:
		V.b(vb, 1 + k * 10, 2, 10, 9, 9, 1, V.wood(Color("b07a46"), 1, 3))
		V.p(vb, 9 + k * 3 - k * 2, 7, 11, Color("e8c66a"))
	V.b(vb, 0, 13, 0, 22, 1, 11, Color("f4f2ee"))
	# Vessel basin + tap.
	V.cyl(vb, 11, 14, 5.5, 4.0, 2, Color("ffffff"))
	V.cyl(vb, 11, 15, 5.5, 2.8, 1, Color("cfe4ee"))
	V.b(vb, 10, 14, 0, 2, 5, 1, Color("c9ccd2"))
	V.b(vb, 10, 18, 1, 2, 1, 2, Color("c9ccd2"))
	# Cup of toothbrushes, soap pump, plant.
	V.b(vb, 2, 14, 3, 2, 3, 2, Color("9fd0e8"))
	V.p(vb, 2, 17, 3, Color("f28fb0")); V.p(vb, 3, 17, 4, Color("6ab0e8")); V.p(vb, 2, 18, 3, Color("ffffff"))
	V.b(vb, 18, 14, 3, 2, 3, 2, Color("f6d27a")); V.p(vb, 18, 17, 3, Color("c9ccd2"))
	V.b(vb, 15, 14, 7, 3, 2, 3, Color("ede7db"))
	V.blob(vb, Vector3(16.5, 17.0, 8.5), Vector3(2.2, 1.6, 2.0), V.leaves(4, 0), 0.0, 0.3, 4)


## Bathroom wall cabinet / shelf with bottles and rolled towels, back at z=0.
static func m_bath_shelf(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 14, 1, 4, Color("f4f2ee"))
	V.b(vb, 0, 7, 0, 14, 1, 4, Color("f4f2ee"))
	var bc := [Color("f3f0e8"), Color("9fd0e8"), Color("f2c4a0"), Color("c8e6c0"), Color("f28fb0")]
	for k in 5:
		V.b(vb, 1 + k * 2 + (k / 3), 1, 1, 2, 3 + k % 2 * 2, 2, bc[k])
	for k in 3:
		var tc: Color = [Color("fbf6ee"), Color("8fb4d8"), Color("f2b5c6")][k]
		V.b(vb, 1 + k * 4, 8, 0, 4, 3, 4, V.noisy(tc, 0.04))


# ------------------------------------------------------------------ kids

## Pink dollhouse on legs: two floors, little lit windows, pitched roof. 16 x 22 x 8.
static func m_dollhouse(vb: VoxelBuilder, _v: int) -> void:
	var wall := V.noisy(Color("f9d3dd"), 0.03)
	V.b(vb, 0, 0, 0, 16, 2, 8, Color("fbf6ee"))
	V.b(vb, 1, 2, 0, 14, 12, 8, wall)
	# Open front: two rooms with tiny furniture.
	vb.clear_box(Vector3i(2, 3, 6), Vector3i(12, 4, 2))
	vb.clear_box(Vector3i(2, 8, 6), Vector3i(12, 5, 2))
	V.b(vb, 1, 7, 0, 14, 1, 8, Color("fbf6ee"))
	V.b(vb, 3, 3, 4, 3, 2, 2, Color("8fb4d8"))
	V.b(vb, 9, 3, 4, 4, 1, 2, Color("f6d27a"))
	V.b(vb, 3, 8, 4, 4, 2, 2, Color("f28fb0"))
	V.p(vb, 11, 9, 5, Color("ffe08a"), true)
	V.p(vb, 11, 10, 5, Color("ffe08a"), true)
	# Roof.
	for k in 9:
		V.b(vb, k, 14 + k, 0, 16 - 2 * k, 1, 8, Color("e36f92") if k % 2 == 0 else Color("ef8fab"))
	V.b(vb, 7, 17, 7, 2, 2, 1, Color("ffe08a"), true)


## Low kids' table with two stools and a tea set. 22 x 9 x 14.
static func m_play_table(vb: VoxelBuilder, v: int) -> void:
	var top: Color = [Color("fbf6ee"), Color("f6d27a")][v % 2]
	V.cyl(vb, 11, 6, 7, 6.0, 1, top)
	V.b(vb, 10, 0, 6, 2, 6, 2, Color("e6dccb"))
	V.b(vb, 8, 0, 4, 6, 1, 6, Color("e6dccb"))
	# Tea set.
	V.b(vb, 9, 7, 6, 3, 2, 3, Color("f7a9c0")); V.p(vb, 10, 9, 7, Color("f7a9c0")); V.p(vb, 12, 8, 7, Color("f7a9c0"))
	V.b(vb, 6, 7, 5, 2, 1, 2, Color("ffffff")); V.b(vb, 14, 7, 8, 2, 1, 2, Color("ffffff"))
	V.p(vb, 13, 7, 4, Color("e2463a"))
	# Stools.
	for sx in [0, 18]:
		V.cyl(vb, sx + 2, 0, 7, 2.2, 4, Color("9fd6c8") if sx == 0 else Color("f28fb0"))


## Low two-tier bookcase with picture books, bins and a plush on top. 22 x 13 x 7.
## v0 white + pink bins, v1 wood + blue bins.
static func m_low_shelf(vb: VoxelBuilder, v: int) -> void:
	var body := V.noisy(Color("f4efe6"), 0.03) if v % 2 == 0 else V.wood(WOOD, 0, 2)
	V.b(vb, 0, 0, 0, 22, 12, 7, body)
	vb.clear_box(Vector3i(1, 1, 1), Vector3i(20, 5, 6))
	vb.clear_box(Vector3i(1, 7, 1), Vector3i(20, 4, 6))
	var bin: Color = Color("f28fb0") if v % 2 == 0 else Color("6a86c8")
	V.b(vb, 2, 1, 2, 8, 4, 5, bin)
	V.b(vb, 2, 3, 6, 8, 1, 1, V.shade(bin, 1.15))
	V.b(vb, 12, 1, 2, 8, 4, 5, Color("f6d27a") if v % 2 == 0 else Color("9fd6c8"))
	V.books(vb, 1, 7, 1, 20, 4, 5, 33 + v)
	# On top: plush and a little lamp-like jar.
	if v % 2 == 0:
		V.b(vb, 3, 12, 2, 4, 3, 3, Color("ffffff")); V.b(vb, 3, 15, 2, 4, 3, 3, Color("ffffff"))
		V.b(vb, 3, 18, 3, 1, 3, 1, Color("ffffff")); V.b(vb, 6, 18, 3, 1, 3, 1, Color("ffffff"))
		V.p(vb, 4, 16, 5, Color("2a2030")); V.p(vb, 5, 16, 5, Color("2a2030"))
	else:
		V.b(vb, 3, 12, 2, 2, 7, 2, Color("eeeef2")); V.p(vb, 3, 19, 2, Color("e2463a")); V.p(vb, 4, 19, 3, Color("e2463a"))
		V.b(vb, 2, 12, 2, 1, 2, 1, Color("e2463a")); V.b(vb, 5, 12, 3, 1, 2, 1, Color("e2463a"))
	V.b(vb, 14, 12, 2, 5, 4, 4, Color("ede7db"))
	V.blob(vb, Vector3(16.5, 17.5, 4), Vector3(3.0, 2.0, 2.6), V.leaves(3, 0), 0.0, 0.35, 3)


## Standing toy rocket (blue room). 8 x 20 x 8.
static func m_toy_rocket(vb: VoxelBuilder, _v: int) -> void:
	V.cyl(vb, 4, 3, 4, 2.6, 12, Color("eeeef2"))
	V.cyl(vb, 4, 15, 4, 1.8, 2, Color("e2463a"))
	V.cyl(vb, 4, 17, 4, 0.9, 2, Color("e2463a"))
	V.b(vb, 3, 10, 6, 2, 2, 1, Color("6ab0e8"))
	for d: Vector2i in [Vector2i(0, 3), Vector2i(7, 3), Vector2i(3, 0), Vector2i(3, 7)]:
		V.b(vb, d.x, 0, d.y, 1 if d.x in [0, 7] else 2, 5, 2 if d.x in [0, 7] else 1, Color("e2463a"))
	V.b(vb, 3, 1, 3, 2, 2, 2, Color("ffb43a"), true)


## Green dino plush. 10 x 9 x 6.
static func m_dino(vb: VoxelBuilder, _v: int) -> void:
	var g := V.noisy(Color("72b85a"), 0.05)
	V.b(vb, 2, 0, 1, 5, 4, 4, g)
	V.b(vb, 5, 3, 1, 4, 4, 4, g)
	V.b(vb, 0, 1, 2, 2, 2, 2, g)
	for k in 3:
		V.p(vb, 3 + k * 2, 4 + (1 if k > 0 else 0), 3, Color("f6c445"))
	V.p(vb, 8, 6, 5, Color("2a2030")); V.p(vb, 8, 6, 1, Color("2a2030"))
	V.b(vb, 2, 0, 0, 1, 1, 1, g); V.b(vb, 2, 0, 5, 1, 1, 1, g)


## Planet mobile hanging from the ceiling (top at y = max): glowing sun and
## three planets on strings. 22 x 16 x 6.
static func m_planet_mobile(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 15, 3, 22, 1, 1, Color("c9a26a"))
	V.b(vb, 10, 16, 3, 1, 2, 1, Color("8a7a6a"))
	var balls := [[2, 9, 1.6, Color("e88a3a"), false], [8, 6, 2.2, Color("ffd45a"), true], [14, 10, 1.4, Color("6ab0e8"), false], [20, 8, 1.8, Color("e36f92"), false]]
	for b: Array in balls:
		var x: int = b[0]
		var y: int = b[1]
		V.b(vb, x, y + 1, 3, 1, 14 - y, 1, Color("8a7a6a"))
		var r: float = b[2]
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					if Vector3(dx, dy, dz).length() <= r:
						V.p(vb, x + dx, y + dy, 3 + dz, b[3], b[4])


## Kid's star rug edge bits: a little rocking horse (pink room floor). 14 x 12 x 6.
static func m_rocking_horse(vb: VoxelBuilder, _v: int) -> void:
	var body := V.noisy(Color("fbf6ee"), 0.03)
	for x in 14:
		var y := int(round(1.6 * pow((x - 6.5) / 6.5, 2) * 2.0))
		V.p(vb, x, y, 0, Color("e36f92")); V.p(vb, x, y, 5, Color("e36f92"))
	V.b(vb, 3, 2, 1, 1, 4, 1, WOOD); V.b(vb, 10, 2, 1, 1, 4, 1, WOOD)
	V.b(vb, 3, 2, 4, 1, 4, 1, WOOD); V.b(vb, 10, 2, 4, 1, 4, 1, WOOD)
	V.b(vb, 2, 6, 1, 10, 3, 4, body)
	V.b(vb, 10, 8, 1, 3, 4, 4, body)
	V.b(vb, 11, 11, 1, 3, 2, 4, body)
	V.b(vb, 9, 9, 1, 1, 4, 4, Color("f28fb0"))
	V.p(vb, 13, 12, 1, Color("2a2030")); V.p(vb, 13, 12, 4, Color("2a2030"))
	V.b(vb, 1, 7, 2, 1, 3, 2, Color("f28fb0"))
	V.b(vb, 5, 9, 1, 3, 1, 4, Color("e36f92"))


## Big arched vanity mirror in a wood frame, back at z=0. 16 x 19 cells.
static func m_vanity_mirror(vb: VoxelBuilder, _v: int) -> void:
	var fr := V.wood(Color("9a643a"), 1, 2)
	for x in 16:
		for y in 19:
			var ax := absf(x - 7.5)
			var top := 15.0 + sqrt(maxf(0.0, 64.0 - ax * ax)) * 0.5
			if y > top:
				continue
			var inner := ax < 6.6 and y >= 1 and y < top - 1.0
			if inner:
				var hl := (x + y) % 9 == 0 or (x + y) % 9 == 1
				V.p(vb, x, y, 0, Color("dff1f8") if hl else Color("9fc6da").lerp(Color("c9e3ee"), float(y) / 18.0))
			else:
				V.p(vb, x, y, 0, fr.call(Vector3i(x, y, 0)))
				V.p(vb, x, y, 1, fr.call(Vector3i(x, y, 1)))
