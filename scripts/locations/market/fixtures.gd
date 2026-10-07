extends RefCounted
## Store fixtures modelled in local space (U = 1/16 m grid, facing +Z) and
## stamped into the shared builders with quarter-turn rotations:
## gondola shelves with packaged goods, fridge cases, produce crates and
## tiered produce racks, the checkout counter, pendant lamps, a shopping cart.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")

const U := 0.0625

const WOOD := Color("b97a45")
const WOOD_L := Color("d49a5e")
const WOOD_D := Color("7a4a26")
const CREAM := Color("f2e6cf")
const CHAR := Color("2e2a28")

const BOX_COLS := [Color("e8402f"), Color("f6c22c"), Color("2f7fd8"), Color("f08a24"), Color("43a447"),
	Color("8e4fc2"), Color("ef6aa0"), Color("27b3c4"), Color("d8332f"), Color("fbe36a")]


static func c(m: float) -> int:
	return int(round(m / U))


## Rotate a local cell by q quarter turns (+Z -> +X per turn).
static func rot(p: Vector3i, q: int) -> Vector3i:
	match ((q % 4) + 4) % 4:
		1: return Vector3i(p.z, p.y, -p.x)
		2: return Vector3i(-p.x, p.y, -p.z)
		3: return Vector3i(-p.z, p.y, p.x)
	return p


static func put(dst: VoxelBuilder, src: VoxelBuilder, at: Vector3i, q := 0) -> void:
	for p: Vector3i in src.vox:
		dst.set_v(at + rot(p, q), src.vox[p], src.glow.has(p))


# ------------------------------------------------------------------ goods

## One packaged product facing +z, standing at o (legacy entry point).
static func product(vb: VoxelBuilder, o: Vector3i, kind: String, col: Color, col2: Color, max_h: int) -> int:
	return good(vb, o, kind, col, col2, max_h, 0, 0)


const INK := Color("2a1d14")
const PAPER := Color("fdf8ec")
const MASCOT := [Color("f3b25a"), Color("fde46a"), Color("fbfbf6"), Color("c97a35"), Color("f6d7a8")]


## A packaged product, front face at z = o.z + d - 1 (facing +z), standing at
## o. `big` = 1 makes the chunky end-cap version. Returns the width used.
## Every kind has a readable silhouette and a front "label" (logo band,
## mascot face, product window) so a shelf reads as individual packages.
static func good(vb: VoxelBuilder, o: Vector3i, kind: String, col: Color, col2: Color, max_h: int, big: int, v: int) -> int:
	var side := Kit.shade(col, 0.78)
	match kind:
		"cereal":
			var w := 7 if big else 5
			var hh := mini(max_h, (10 if big else 7) - (v % 2))
			var d := 3 if big else 2
			for x in w:
				for y in hh:
					for z in d:
						var cc := side if z < d - 1 else col
						if z == d - 1:
							if y >= hh - 2:
								# logo band with "lettering"
								cc = col2
								if y == hh - 2 and x >= 1 and x <= w - 2 and (x + v) % 2 == 0:
									cc = PAPER
							elif y == 0:
								cc = Kit.shade(col, 0.82)
							elif x == 0:
								cc = Kit.shade(col, 0.86)
						vb.set_v(o + Vector3i(x, y, z), cc)
			# mascot face (big round head, two eyes, smile) on the front
			var m: Color = MASCOT[v % MASCOT.size()]
			var fz := o.z + d
			var my := 1 if not big else 2
			var mh := hh - 3 - my
			var mw := w - 2
			for x in mw:
				for y in mh:
					var corner := (x == 0 or x == mw - 1) and (y == 0 or y == mh - 1)
					if not corner:
						vb.set_v(Vector3i(o.x + 1 + x, o.y + my + y, fz - 1), m)
			var ey := o.y + my + mh - 2
			vb.set_v(Vector3i(o.x + 2, ey, fz - 1), INK)
			vb.set_v(Vector3i(o.x + w - 3, ey, fz - 1), INK)
			if big:
				# ears + a raised snout
				vb.set_v(Vector3i(o.x + 1, o.y + my + mh, fz - 1), Kit.shade(m, 0.8))
				vb.set_v(Vector3i(o.x + w - 2, o.y + my + mh, fz - 1), Kit.shade(m, 0.8))
				vb.set_v(Vector3i(o.x + 3, ey - 2, fz), Color("fbe4c4"))
				vb.set_v(Vector3i(o.x + 3, ey - 1, fz), INK)
			else:
				vb.set_v(Vector3i(o.x + 2, ey - 1 - (1 if mh > 3 else 0), fz - 1), Color("d8504a"))
			return w
		"box":
			# cracker / snack box: wide or tall, product window + top stripe
			var wide := v % 3 == 0
			var w := (8 if big else 6) if wide else (5 if big else 4)
			var hh := mini(max_h, (6 if big else 4) if wide else (8 if big else 6))
			var d := 3 if big else 2
			for x in w:
				for y in hh:
					for z in d:
						var cc := side if z < d - 1 else col
						if z == d - 1:
							if y == hh - 1:
								cc = Kit.shade(col2, 1.05)
							elif y >= 1 and y <= hh - 3 and x >= 1 and x <= w - 2:
								cc = PAPER if (y == 1 or x == 1 or x == w - 2) else col2
							elif x == 0:
								cc = Kit.shade(col, 0.86)
						vb.set_v(o + Vector3i(x, y, z), cc)
			return w
		"bag":
			# chip bag: crimped lighter top, bulging middle, round chip window
			var w := 5 if big else 4
			var hh := mini(max_h, 8 if big else 6)
			for x in w:
				for y in hh:
					var top := y == hh - 1
					var cc := Kit.shade(col, 1.18) if top else col
					if not top and y >= 1 and y <= hh - 3 and x >= 1 and x <= w - 2:
						cc = Color("f6c450") if (y + x) % 3 != 0 else Color("e8a13a")
					if y == hh - 2:
						cc = col2
					vb.set_v(o + Vector3i(x, y, 0), Kit.shade(col, 0.85))
					if not top:
						vb.set_v(o + Vector3i(x, y, 1), cc)
					else:
						vb.set_v(o + Vector3i(x, y, 0), cc)
					if y >= 1 and y < hh - 2 and x > 0 and x < w - 1:
						vb.set_v(o + Vector3i(x, y, 2), cc)
			return w
		"can":
			# stacked cans / pyramid: silver rims, coloured label
			var n := 2 if big else 2
			var rows := mini(3, max_h / 3)
			for r in rows:
				var nn := n if r < rows - 1 or v % 2 == 0 else 1
				for k in nn:
					for y in 3:
						var c2 := Color("cfd4d8") if y == 2 else (col2 if y == 1 else col)
						for z in 2:
							for x in 2:
								vb.set_v(o + Vector3i(k * 2 + x + (1 if nn == 1 else 0), r * 3 + y, z), c2 if z == 1 else Kit.shade(c2, 0.85))
			return n * 2
		"bottle":
			# bottle: body, label band, shoulder, neck, cap
			var hh := mini(max_h, 7)
			var bw := 3 if big else 2
			for y in hh:
				for x in bw:
					for z in 2:
						var cc := col
						if y == 2 or y == 3:
							cc = PAPER if y == 2 else col2
						if y >= hh - 2:
							if x != bw / 2:
								continue
							cc = Kit.shade(col, 1.15) if y == hh - 2 else col2
						if z == 0:
							cc = Kit.shade(cc, 0.85)
						vb.set_v(o + Vector3i(x, y, z), cc)
			return bw
		"jar":
			var hh := mini(max_h, 4)
			for x in 3:
				for y in hh:
					for z in 2:
						var cc := col
						if y == hh - 1:
							cc = col2
						elif y == 1 and z == 1:
							cc = PAPER
						vb.set_v(o + Vector3i(x, y, z), cc)
			return 3
	return 1


## Fill a shelf run [x0, x0+w) at height y (bottom), depth front cell zf.
## Brand blocks of 2-4 facings; each block has its own kind, colours, height
## variant and front offset, with the odd gap and a few products stacked or
## pushed back, so the shelf reads as real merchandise, not a pattern.
static func stock(vb: VoxelBuilder, x0: int, w: int, y: int, zf: int, max_h: int, seed: int, kinds: Array, big := 0, lod := false) -> void:
	var x := x0
	var g := 0
	var depth := 3 if big else 2
	while x < x0 + w - 2:
		var hv := Vector3i(g, y, seed)
		var kind: String = kinds[int(Kit.h(hv, 41) * kinds.size()) % kinds.size()]
		var col: Color = BOX_COLS[int(Kit.h(hv, 43) * BOX_COLS.size()) % BOX_COLS.size()]
		var col2: Color = BOX_COLS[int(Kit.h(hv, 47) * BOX_COLS.size()) % BOX_COLS.size()]
		if col2 == col:
			col2 = PAPER
		var v := int(Kit.h(hv, 59) * 7.0)
		var facings := 2 + int(Kit.h(hv, 53) * 3.0)
		var back := 1 if Kit.h(hv, 61) < 0.25 else 0
		var x_start := x
		for f in facings:
			var room := x0 + w - x
			if room < 4:
				break
			# odd sold-out gap
			if not big and Kit.h(Vector3i(g, f, seed), 67) < 0.06:
				x += 3
				continue
			if lod:
				# far / mostly hidden shelves: one two-tone block per facing
				var lw := 4 if kind in ["cereal", "box", "bag"] else 2
				if lw > room:
					break
				var lh := mini(max_h, 4 + v % 3)
				vb.box(Vector3i(x, y, zf - 1), Vector3i(lw, lh, 2), func(p: Vector3i) -> Color:
					return col2 if p.y == y + lh - 2 else col)
				x += lw + (1 if lw == 2 else 0)
				continue
			var tmp := VoxelBuilder.new()
			var used := good(tmp, Vector3i.ZERO, kind, col, col2, max_h, big, v)
			if used > room:
				break
			var zoff := zf - depth + 1 - back - (1 if Kit.h(Vector3i(g, f, seed), 71) < 0.15 else 0)
			for p: Vector3i in tmp.vox:
				vb.set_v(Vector3i(x, y, zoff) + p, tmp.vox[p])
			x += used + (1 if kind in ["bottle", "can", "jar"] else 0)
		x += 0 if big else 1
		if x == x_start:
			x += 1
		g += 1


## Gondola shelf, local facing +z, length `len` cells, depth 8. Charcoal
## metal uprights, a dark back panel (so the colourful packs pop), light
## shelf lips with price strips, and overstock cases heaped on the top.
## big = 1: chunky end-cap version (3 tall shelves of big packs).
static func gondola(length: int, seed: int, kinds: Array, double_sided := false, big := 0, lod := false) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var D := 9 if big else 8
	var levels := [2, 14, 26] if big else [2, 10, 18, 26, 34]
	var H := 37 if big else 42
	var max_h := 11 if big else 7
	var z0 := -D if double_sided else 0
	# back panel (slatwall lines; flat rows merge into long quads)
	vb.box(Vector3i(0, 0, 0), Vector3i(length, H, 1), func(p: Vector3i) -> Color:
		return Color("4d4944") if p.y % 4 == 1 else Color("45413d"))
	# uprights
	for x in [0, length - 1]:
		vb.box(Vector3i(x, 0, z0), Vector3i(1, H + 1, D - z0), Color("34322f"))
	# base plinth
	vb.box(Vector3i(0, 0, z0), Vector3i(length, 2, D - z0), Color("3b3835"))
	for li in levels.size():
		var y: int = levels[li]
		vb.box(Vector3i(1, y, z0 + 1), Vector3i(length - 2, 1, D - z0 - 1), Color("bfc3c6"))
		# price strip with yellow sale tags and white tickets
		vb.box(Vector3i(1, y, D - 1), Vector3i(length - 2, 1, 1), Color("f4f2ec"))
		for tx in range(3 + (seed + li) % 4, length - 3, 7):
			var tc := Color("f5d03b") if (tx / 7 + li + seed) % 3 == 0 else Color("ffffff")
			vb.set_v(Vector3i(tx, y, D), tc)
			vb.set_v(Vector3i(tx + 1, y, D), tc)
		stock(vb, 1, length - 2, y + 1, D - 1, max_h, seed * 7 + li, kinds, big, lod)
		if double_sided:
			var back := VoxelBuilder.new()
			stock(back, 1, length - 2, y + 1, D - 1, max_h, seed * 11 + li + 3, kinds, big)
			for p: Vector3i in back.vox:
				vb.set_v(Vector3i(length - 1 - p.x, p.y, -p.z), back.vox[p])
	# header cap
	vb.box(Vector3i(0, H, z0), Vector3i(length, 1, D - z0), Color("34322f"))
	# overstock heaped on top: cardboard cases and spare packs, uneven
	var ox := 1
	var k := 0
	while ox < length - 4:
		var r := Kit.h(Vector3i(ox, seed, 5), 9)
		var w := 4 + int(r * 5.0)
		w = mini(w, length - 1 - ox)
		var hh := 2 + int(Kit.h(Vector3i(ox, seed, 6), 9) * 4.0)
		if r < 0.45:
			var cb := Color("c99a62") if r < 0.25 else Color("b8864e")
			vb.box(Vector3i(ox, H + 1, 1), Vector3i(w, hh, D - 2), Kit.noise(cb, 0.05, ox))
			vb.box(Vector3i(ox, H + hh, D - 4), Vector3i(w, 1, 1), Color("e3c38f"))
		elif r < 0.85:
			var tmp := VoxelBuilder.new()
			var col: Color = BOX_COLS[(k * 3 + seed) % BOX_COLS.size()]
			var used := good(tmp, Vector3i.ZERO, kinds[k % kinds.size()], col, BOX_COLS[(k * 7 + seed + 2) % BOX_COLS.size()], 9, big, k + seed)
			for p: Vector3i in tmp.vox:
				vb.set_v(Vector3i(ox, H + 1, D - 4) + p, tmp.vox[p])
			w = used
		ox += w + (1 if Kit.h(Vector3i(ox, seed, 7), 9) > 0.5 else 2)
		k += 1
	return vb


## Glowing dairy / drinks fridge bank, local facing +z. Tall (2.6 m) glass
## doors with a bright white back light, four shelves of goods and a stock
## overhang of cartons on top.
static func fridge(width: int, seed: int, stocked := true) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var H := 42
	var D := 12
	var CT := H - 4   # cavity top
	var frame := Color("c9ced3")
	vb.box(Vector3i(0, 0, 0), Vector3i(width, H, D), frame)
	# kick plate
	vb.box(Vector3i(0, 0, D - 1), Vector3i(width, 3, 1), Color("3b4048"))
	# cavity
	vb.clear_box(Vector3i(1, 3, 2), Vector3i(width - 2, CT - 3, D - 2))
	# glowing back + glowing ceiling strip inside
	vb.box(Vector3i(1, 3, 1), Vector3i(width - 2, CT - 3, 1), Color("e6f3ff"), true)
	vb.box(Vector3i(1, CT - 1, 2), Vector3i(width - 2, 1, D - 3), Color("f4fbff"), true)
	# top header light box + brand stripe
	vb.box(Vector3i(0, CT, D - 1), Vector3i(width, 3, 1), Color("f4fbff"), true)
	vb.box(Vector3i(0, H - 1, 0), Vector3i(width, 1, D), Color("2f6fb5"))
	var shelves := [3, 11, 19, 27]
	var milk_caps: Array[Color] = [Color("2e7de0"), Color("e0412e"), Color("37a64a"), Color("f2c12e")]
	var juice: Array[Color] = [Color("f7a21c"), Color("f5d33a"), Color("e8502f"), Color("8bd36b"), Color("c84fd0"), Color("2e7de0")]
	var drinks: Array[Color] = [Color("1f8fe8"), Color("3cc24a"), Color("ef4a3a"), Color("f5a82a"), Color("8a4be0"), Color("19c2c9"), Color("f25f9c")]
	var fz := D - 3   # front row of goods
	for si in shelves.size():
		var y: int = shelves[si]
		var top: int = (shelves[si + 1] if si + 1 < shelves.size() else CT - 1) - y - 1
		vb.box(Vector3i(1, y, 2), Vector3i(width - 2, 1, D - 3), Color("aab5bf"))
		vb.box(Vector3i(1, y, D - 2), Vector3i(width - 2, 1, 1), Color("f2f4f6"))
		if not stocked:
			# hidden behind the aisles: flat coloured rows (cheap)
			vb.box(Vector3i(2, y + 1, fz - 2), Vector3i(width - 4, mini(top - 2, 5), 3), func(p: Vector3i) -> Color:
				return drinks[(p.x / 3 + si) % drinks.size()] if p.y != y + 3 else Color("fdf6e0"))
			continue
		var x := 2
		var item := 0
		while x < width - 4:
			var r := Kit.h(Vector3i(x / 9, y, seed), 3)
			var kind: int = [0, 0, 1, 2, 2, 1, 0, 2][int(r * 8.0) % 8]
			if si == 0 and kind == 0:
				kind = 1
			var b := Vector3i(x, y + 1, fz)
			match kind:
				0: # milk jug: white, 3 wide, coloured cap + label band, handle
					var cap := milk_caps[(int(r * 31.0) + item / 3) % 4]
					var hh := mini(top - 1, 6)
					for dx in 3:
						for yy in hh:
							for zz in 3:
								var cc := Color("fbfbf6")
								if zz == 2 and (yy == 2 or yy == 3) and dx < 3:
									cc = cap if yy == 2 else Color("ffffff")
								if dx == 2 and zz < 2:
									cc = Color("e9e9e2")
								vb.set_v(b + Vector3i(dx, yy, zz - 2), cc)
					vb.set_v(b + Vector3i(0, hh, -1), cap)
					vb.set_v(b + Vector3i(1, hh, -1), cap)
					vb.set_v(b + Vector3i(2, hh - 1, -1), Color("e0e0d8"))
					x += 4
				1: # gable-top carton: coloured, white band, peaked top
					var col := juice[(int(r * 37.0) + item) % juice.size()]
					var hh := mini(top - 2, 5)
					for dx in 3:
						for yy in hh:
							for zz in 3:
								var cc := col
								if yy == hh - 2:
									cc = Color("ffffff")
								elif dx == 0:
									cc = Kit.shade(col, 0.82)
								vb.set_v(b + Vector3i(dx, yy, zz - 2), cc)
					for zz in 3:
						vb.set_v(b + Vector3i(1, hh, zz - 2), Kit.shade(col, 1.15))
					vb.set_v(b + Vector3i(1, hh + 1, -1), Kit.shade(col, 1.15))
					x += 4
				_: # bottle: 2 wide body, label, neck + cap
					var col := drinks[(int(r * 41.0) + item) % drinks.size()]
					var hh := mini(top - 3, 6)
					for dx in 2:
						for yy in hh:
							for zz in 2:
								var cc := col
								if yy == 2 or yy == 3:
									cc = Color("fdf6e0") if yy == 2 else Kit.shade(col, 1.25)
								elif dx == 1 and zz == 1:
									cc = Kit.shade(col, 1.35)
								vb.set_v(b + Vector3i(dx, yy, zz - 1), cc)
					vb.set_v(b + Vector3i(0, hh, 0), Kit.shade(col, 1.2))
					vb.set_v(b + Vector3i(0, hh + 1, 0), Kit.shade(col, 1.2))
					vb.set_v(b + Vector3i(0, hh + 2, 0), Color("ffffff"))
					x += 3
			item += 1
	# door frames (dark) + handles
	for x in range(0, width, 12):
		vb.box(Vector3i(x, 3, D - 1), Vector3i(1, CT - 3, 1), Color("4a5058"))
		if x + 10 < width:
			vb.box(Vector3i(x + 10, 12, D), Vector3i(1, 15, 1), Color("eef2f5"))
			vb.set_v(Vector3i(x + 10, 12, D - 1), Color("4a5058"))
	vb.box(Vector3i(width - 1, 3, D - 1), Vector3i(1, CT - 3, 1), Color("5d646c"))
	vb.box(Vector3i(0, CT - 1, D - 1), Vector3i(width, 1, 1), Color("5d646c"))
	vb.box(Vector3i(0, 3, D - 1), Vector3i(width, 1, 1), Color("5d646c"))
	# overstock: cardboard cases and shrink-wrapped bottle packs on top
	var ox := 1
	while ox < width - 6:
		var r := Kit.h(Vector3i(ox, seed, 5), 9)
		var w := 5 + int(r * 4.0)
		var hh := 3 + int(Kit.h(Vector3i(ox, seed, 6), 9) * 3.0)
		if r < 0.7:
			var cb := Color("c99a62") if r < 0.45 else Color("b8864e")
			vb.box(Vector3i(ox, H, 2), Vector3i(w, hh, 7), Kit.noise(cb, 0.05, ox))
			vb.box(Vector3i(ox + 1, H + hh - 2, 9), Vector3i(w - 2, 1, 1), Color("fbf3dc"))
		else:
			for k in w / 2:
				for y in 2:
					vb.box(Vector3i(ox + k * 2, H + y * 3, 3), Vector3i(2, 3, 5), drinks[(k + seed) % drinks.size()])
		ox += w + (1 if Kit.h(Vector3i(ox, seed, 7), 9) > 0.5 else 3)
	return vb


## Open wooden crate, local min corner at 0, w x d cells, h tall.
static func crate(vb: VoxelBuilder, o: Vector3i, w: int, d: int, h: int, col := WOOD) -> void:
	for x in w:
		for z in d:
			for y in h:
				var edge := x == 0 or z == 0 or x == w - 1 or z == d - 1
				if not edge and y > 0:
					continue
				var p := o + Vector3i(x, y, z)
				var cc := col
				if y % 2 == 1:
					cc = Kit.shade(col, 0.86)
				if (x == 0 or x == w - 1) and (z == 0 or z == d - 1):
					cc = Kit.shade(col, 0.75)
				vb.set_v(p, Kit.shade(cc, 0.94 + 0.12 * Kit.h(Vector3i(o.x, y, o.z), 1)))


## Pendant lamp (black cone shade, glowing rim + bulb). o = bottom centre cell.
static func pendant(vb: VoxelBuilder, o: Vector3i, cord: int) -> void:
	# Black industrial cone shade (wide bottom), warm-lit inner rim, a big
	# glowing bulb hanging below the rim so it reads from above and from the
	# side, and a brass cap + cord.
	var shade_c := Color("1d1a18")
	var rim := Color("2e2926")
	for y in 5:
		var r := 5 - y
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				var d := x * x + z * z
				if d > r * r + r:
					continue
				var inner := d <= (r - 1) * (r - 1) + (r - 1)
				if y < 2 and inner:
					continue
				vb.set_v(o + Vector3i(x, y + 2, z), rim if y == 0 else shade_c)
	# glowing inside of the shade (visible through the open bottom)
	for x in range(-4, 5):
		for z in range(-4, 5):
			if x * x + z * z <= 13:
				vb.set_v(o + Vector3i(x, 3, z), Color("fff0cc"), true)
	# inner rim ring lit warm (a thin bright line along the lower edge)
	for x in range(-4, 5):
		for z in range(-4, 5):
			var d := x * x + z * z
			if d <= 20 and d > 12:
				vb.set_v(o + Vector3i(x, 2, z), Color("ffd890"), true)
	# bulb: 3x3 glowing globe hanging just below the rim
	for x in range(-1, 2):
		for z in range(-1, 2):
			for y in range(0, 2):
				if absi(x) + absi(z) <= 1 or y == 1:
					vb.set_v(o + Vector3i(x, y, z), Color("fff6dc") if y == 1 else Color("ffe4a8"), true)
	vb.set_v(o + Vector3i(0, -1, 0), Color("ffe09a"), true)
	vb.set_v(o + Vector3i(0, 2, 0), Color("fff6dc"), true)
	# brass cap + cord
	vb.set_v(o + Vector3i(0, 7, 0), Color("b8893e"))
	vb.set_v(o + Vector3i(1, 7, 0), Color("a07432"))
	vb.set_v(o + Vector3i(0, 7, 1), Color("a07432"))
	for y in cord:
		vb.set_v(o + Vector3i(0, 8 + y, 0), Color("1c1a19"))


## Shopping cart (P = 1/32 grid), local facing +z (handle at -z).
static func cart() -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.02
	var wire := Color("8d939a")
	var wire2 := Color("6f757c")
	var W := 17
	var L := 26
	var y0 := 12
	var Hb := 13
	# basket walls as grid
	for x in W:
		for z in L:
			for y in Hb:
				var side := x == 0 or x == W - 1
				var end := z == 0 or z == L - 1
				var bottom := y == 0
				if not (side or end or bottom):
					continue
				var grid := false
				if side:
					grid = z % 3 == 0 or y % 3 == 0
				elif end:
					grid = x % 3 == 0 or y % 3 == 0
				else:
					grid = x % 3 == 0 or z % 3 == 0
				if y == Hb - 1:
					grid = true
				if grid:
					vb.set_v(Vector3i(x, y0 + y, z), wire if y < Hb - 1 else Color("b4b9bf"))
	# taper: front lower (no-op visual) ; chassis
	for z in range(-2, L):
		vb.set_v(Vector3i(1, 3, z), wire2)
		vb.set_v(Vector3i(W - 2, 3, z), wire2)
	for y in range(3, y0):
		vb.set_v(Vector3i(1, y, -1), wire2)
		vb.set_v(Vector3i(W - 2, y, -1), wire2)
		vb.set_v(Vector3i(1, y, L - 2), wire2)
		vb.set_v(Vector3i(W - 2, y, L - 2), wire2)
	# lower tray
	for x in range(2, W - 2, 2):
		for z in range(0, L - 2):
			vb.set_v(Vector3i(x, 4, z), wire2)
	# wheels
	for wx in [1, W - 2]:
		for wz in [-1, L - 2]:
			for dy in 3:
				for dz in 2:
					vb.set_v(Vector3i(wx, dy, wz + dz), Color("2a2a2c"))
	# handle (red) behind back wall
	for x in range(-1, W + 1):
		vb.set_v(Vector3i(x, y0 + Hb + 1, -3), Color("d8322c"))
		vb.set_v(Vector3i(x, y0 + Hb, -3), Color("c42a25"))
	for y in range(y0 + Hb - 3, y0 + Hb + 1):
		vb.set_v(Vector3i(0, y, -2), wire)
		vb.set_v(Vector3i(W - 1, y, -2), wire)
	# contents, heaped above the rim so the cart reads full from the side:
	# milk jug + cereal by the handle, bread, greens, bananas, tomatoes and
	# a juice carton up front; the dog sits in the middle.
	var by := y0 + 1
	# milk jug (white, blue cap + label)
	vb.box(Vector3i(2, by, 2), Vector3i(5, 13, 5), Color("fbfbf8"))
	vb.box(Vector3i(2, by + 6, 6), Vector3i(5, 3, 1), Color("2e7de0"))
	vb.box(Vector3i(3, by + 13, 3), Vector3i(3, 2, 3), Color("2e7de0"))
	# cereal box (red, yellow band) standing tall
	vb.box(Vector3i(8, by, 2), Vector3i(7, 15, 3), Color("e8402f"))
	vb.box(Vector3i(8, by + 12, 5), Vector3i(7, 2, 1), Color("f6c22c"))
	vb.box(Vector3i(9, by + 4, 5), Vector3i(5, 6, 1), Color("fdf3d4"))
	vb.box(Vector3i(10, by + 6, 6), Vector3i(3, 2, 1), Color("f3b25a"))
	# baguette poking up from the back corner
	vb.box(Vector3i(14, by + 4, 1), Vector3i(2, 16, 2), Color("d39a52"))
	vb.box(Vector3i(14, by + 19, 1), Vector3i(2, 1, 2), Color("e4b56e"))
	# front: kept low (under the rim) so Biscuit, sitting in the middle on a
	# heap of shopping, reads clearly: juice carton, greens, bananas, tomatoes
	vb.box(Vector3i(1, by, 8), Vector3i(15, 6, 16), Color("c98a43"))
	vb.box(Vector3i(11, by, 20), Vector3i(4, 9, 4), Color("f7a21c"))
	vb.box(Vector3i(11, by + 6, 24), Vector3i(4, 2, 1), Color("ffffff"))
	vb.box(Vector3i(12, by + 9, 21), Vector3i(2, 1, 2), Color("43a447"))
	var pv := VoxelBuilder.new()
	Produce.big_lettuce(pv, Vector3i(2, by + 5, 19), 3)
	Produce.big_bananas(pv, Vector3i(6, by + 6, 21), 4, 3)
	Produce.big_tomato(pv, Vector3i(9, by + 6, 17), 2)
	Produce.big_tomato(pv, Vector3i(2, by + 6, 15), 5)
	Produce.big_carrot(pv, Vector3i(12, by + 6, 15), 1, 7)
	Produce.big_apple(pv, Vector3i(6, by + 6, 17), 3)
	for p: Vector3i in pv.vox:
		vb.set_v(p, pv.vox[p])
	return vb


## Little voxel leaf icon (pixels on the XY plane, z = 0), ~7 x 8.
static func leaf_icon(vb: VoxelBuilder, o: Vector3i, col: Color, vein: Color, emissive := false) -> void:
	var rows := [
		"....##.",
		"..####.",
		".#####.",
		"####v#.",
		"###v##.",
		"##v##..",
		".v##...",
		"v......",
	]
	for r in rows.size():
		var s: String = rows[r]
		for i in s.length():
			var ch := s[i]
			if ch == ".":
				continue
			vb.set_v(o + Vector3i(i, rows.size() - 1 - r, 0), col if ch == "#" else vein, emissive)


static func cart_icon(vb: VoxelBuilder, o: Vector3i, col: Color) -> void:
	var rows := [
		"##.........",
		".#########.",
		".#.#.#.#.#.",
		".#########.",
		"..#.#.#.##.",
		"..#######..",
		"..#....#...",
		"..#######..",
		"...#...#...",
	]
	for r in rows.size():
		var s: String = rows[r]
		for i in s.length():
			if s[i] == "#":
				vb.set_v(o + Vector3i(i, rows.size() - 1 - r, 0), col)
