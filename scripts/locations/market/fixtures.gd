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

## One packaged product facing +z, standing at o. Returns width used.
static func product(vb: VoxelBuilder, o: Vector3i, kind: String, col: Color, col2: Color, max_h: int) -> int:
	match kind:
		"cereal":
			# 4 wide box: coloured top band, white brand strip, mascot patch.
			var hh := mini(max_h, 7)
			for x in 4:
				for y in hh:
					for z in 2:
						var p := o + Vector3i(x, y, z)
						var cc := col
						if z == 1:
							if y == hh - 1:
								cc = Kit.shade(col2, 0.95)
							elif y == hh - 2:
								cc = Color("fdf8ec") if (x + y) % 3 != 0 else Kit.shade(col2, 1.1)
							elif y >= 1 and y <= 3 and (x == 1 or x == 2):
								cc = Color("f6d7a8") if y == 3 else (Color("fbf3e4") if y == 1 else col2)
							elif y == 0:
								cc = Kit.shade(col, 0.82)
							if x == 0:
								cc = Kit.shade(cc, 0.72)
						elif x == 0 or x == 3:
							cc = Kit.shade(col, 0.85)
						vb.set_v(p, cc)
			return 4
		"box":
			# snack / cracker box: 3 wide, 5 tall, white window + logo dot.
			var hh := mini(max_h, 5)
			for x in 3:
				for y in hh:
					for z in 2:
						var cc := col
						if z == 1:
							if y == hh - 1:
								cc = Kit.shade(col, 1.12)
							elif y == 2:
								cc = Color("fdf8ec") if x != 1 else col2
							elif y == 0:
								cc = Kit.shade(col, 0.8)
							if x == 0:
								cc = Kit.shade(cc, 0.8)
						else:
							cc = Kit.shade(col, 0.85)
						vb.set_v(o + Vector3i(x, y, z), cc)
			return 3
		"bag":
			var hh := mini(max_h, 5)
			for x in 3:
				for y in hh:
					var p := o + Vector3i(x, y, 0)
					var cc := col if y < hh - 1 else Kit.shade(col, 1.15)
					if y == 2 and x == 1:
						cc = col2
					vb.set_v(p, cc)
					if y < hh - 1:
						vb.set_v(p + Vector3i(0, 0, 1), Kit.shade(cc, 1.05) if y != 2 else Color("fff4d6"))
			return 3
		"can":
			for x in 2:
				for k in mini(2, max_h / 3):
					for y in 3:
						var p := o + Vector3i(x, y + k * 3, 1)
						vb.set_v(p, col2 if y == 1 else col)
						vb.set_v(p - Vector3i(0, 0, 1), col)
			return 2
		"bottle":
			var hh := mini(max_h, 6)
			for y in hh:
				var p := o + Vector3i(0, y, 1)
				var cc := col
				if y == hh - 1:
					cc = Color("f2f2f2")
				elif y == 2:
					cc = col2
				vb.set_v(p, cc)
				if y < hh - 2:
					vb.set_v(p + Vector3i(1, 0, 0), cc)
					vb.set_v(p + Vector3i(0, 0, -1), cc)
					vb.set_v(p + Vector3i(1, 0, -1), cc)
			return 2
		"jar":
			for x in 2:
				for y in 3:
					for z in 2:
						vb.set_v(o + Vector3i(x, y, z), col2 if y == 2 else col)
			return 2
	return 1


## Fill a shelf run [x0, x0+w) at height y (bottom), depth front cell zf.
static func stock(vb: VoxelBuilder, x0: int, w: int, y: int, zf: int, max_h: int, seed: int, kinds: Array) -> void:
	var x := x0
	var i := 0
	while x < x0 + w - 1:
		var r := Kit.h(Vector3i(x, y, seed), 41)
		var kind: String = kinds[int(r * kinds.size()) % kinds.size()]
		var col: Color = BOX_COLS[int(Kit.h(Vector3i(x, y, seed), 43) * BOX_COLS.size()) % BOX_COLS.size()]
		var col2: Color = BOX_COLS[int(Kit.h(Vector3i(x, y, seed), 47) * BOX_COLS.size()) % BOX_COLS.size()]
		var facings := 2 + int(Kit.h(Vector3i(x, y, seed), 53) * 3.0)
		for f in facings:
			if x >= x0 + w - 1:
				break
			var used := product(vb, Vector3i(x, y, zf - 1), kind, col, col2, max_h)
			x += used + (1 if kind == "cereal" or (f % 2 == 1) else 0)
		x += 0 if Kit.h(Vector3i(x, y, seed), 59) > 0.3 else 1
		i += 1


## Gondola shelf, local facing +z, length `len` cells, depth 8, height 30.
static func gondola(length: int, seed: int, kinds: Array, double_sided := false) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var D := 8
	var H := 34
	var z0 := -D if double_sided else 0
	# back panel
	vb.box(Vector3i(0, 0, 0), Vector3i(length, H, 1), Kit.wood(Color("6e4c32"), 2))
	# uprights
	for x in [0, length - 1]:
		vb.box(Vector3i(x, 0, z0), Vector3i(1, H + 1, D - z0), Kit.wood(WOOD_D, 2))
	# base plinth
	vb.box(Vector3i(0, 0, z0), Vector3i(length, 2, D - z0), Color("5b4636"))
	var levels := [2, 10, 18, 26]
	for li in levels.size():
		var y: int = levels[li]
		vb.box(Vector3i(1, y, z0 + 1), Vector3i(length - 2, 1, D - z0 - 1), Kit.wood(WOOD_L, 1, 1))
		# price strip
		vb.box(Vector3i(1, y, D - 1), Vector3i(length - 2, 1, 1), Color("fbf3dc"))
		for tx in range(4, length - 2, 12):
			vb.set_v(Vector3i(tx, y, D - 1), Color("f5d03b"))
			vb.set_v(Vector3i(tx + 1, y, D - 1), Color("f5d03b"))
		stock(vb, 1, length - 2, y + 1, D - 1, 7, seed * 7 + li, kinds)
		if double_sided:
			var back := VoxelBuilder.new()
			stock(back, 1, length - 2, y + 1, D - 1, 7, seed * 11 + li + 3, kinds)
			for p: Vector3i in back.vox:
				vb.set_v(Vector3i(length - 1 - p.x, p.y, -p.z), back.vox[p])
	# header
	vb.box(Vector3i(0, H, z0), Vector3i(length, 2, D - z0), Kit.wood(WOOD_D, 1))
	return vb


## Glowing dairy / drinks fridge bank, local facing +z.
static func fridge(width: int, seed: int) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var H := 34
	var D := 12
	var frame := Color("c9ced3")
	vb.box(Vector3i(0, 0, 0), Vector3i(width, H, D), frame)
	# kick plate
	vb.box(Vector3i(0, 0, D - 1), Vector3i(width, 3, 1), Color("3b4048"))
	# cavity
	vb.clear_box(Vector3i(1, 3, 2), Vector3i(width - 2, 26, D - 2))
	# glowing back
	vb.box(Vector3i(1, 3, 1), Vector3i(width - 2, 26, 1), Color("d8ecff"), true)
	# top header light box + brand stripe
	vb.box(Vector3i(0, 30, D - 1), Vector3i(width, 3, 1), Color("f4fbff"), true)
	vb.box(Vector3i(0, 33, 0), Vector3i(width, 1, D), Color("2f6fb5"))
	var shelves := [3, 11, 19]
	var milk_caps: Array[Color] = [Color("2e7de0"), Color("e0412e"), Color("37a64a"), Color("f2c12e")]
	var juice: Array[Color] = [Color("f7a21c"), Color("f5d33a"), Color("e8502f"), Color("8bd36b"), Color("c84fd0"), Color("2e7de0")]
	var drinks: Array[Color] = [Color("1f8fe8"), Color("3cc24a"), Color("ef4a3a"), Color("f5a82a"), Color("8a4be0"), Color("19c2c9"), Color("f25f9c")]
	var fz := D - 3   # front row of goods
	for si in shelves.size():
		var y: int = shelves[si]
		var top: int = (shelves[si + 1] if si + 1 < shelves.size() else 29) - y - 1
		vb.box(Vector3i(1, y, 2), Vector3i(width - 2, 1, D - 3), Color("aab5bf"))
		vb.box(Vector3i(1, y, D - 2), Vector3i(width - 2, 1, 1), Color("f2f4f6"))
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
		vb.box(Vector3i(x, 3, D - 1), Vector3i(1, 27, 1), Color("4a5058"))
		if x + 10 < width:
			vb.box(Vector3i(x + 10, 9, D), Vector3i(1, 13, 1), Color("eef2f5"))
			vb.set_v(Vector3i(x + 10, 9, D - 1), Color("4a5058"))
	vb.box(Vector3i(width - 1, 3, D - 1), Vector3i(1, 27, 1), Color("5d646c"))
	vb.box(Vector3i(0, 29, D - 1), Vector3i(width, 1, 1), Color("5d646c"))
	vb.box(Vector3i(0, 3, D - 1), Vector3i(width, 1, 1), Color("5d646c"))
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
	var shade_c := Color("23201e")
	var rim := Color("3a3532")
	# cone: wide at the bottom, narrow at the top
	for y in 4:
		var r := 4 - y
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				if x * x + z * z > r * r + r:
					continue
				var inner := x * x + z * z <= (r - 1) * (r - 1) + (r - 1)
				if y == 0 and inner:
					continue
				vb.set_v(o + Vector3i(x, y + 1, z), rim if y == 0 else shade_c)
	# glowing underside + hanging bulb
	for x in range(-3, 4):
		for z in range(-3, 4):
			if x * x + z * z <= 10:
				vb.set_v(o + Vector3i(x, 1, z), Color("fff3d6"), true)
	for x in range(-1, 1):
		for z in range(-1, 1):
			vb.set_v(o + Vector3i(x, 0, z), Color("ffe9b8"), true)
			vb.set_v(o + Vector3i(x, -1, z), Color("ffdf9a"), true)
	vb.set_v(o + Vector3i(0, 5, 0), shade_c)
	for y in cord:
		vb.set_v(o + Vector3i(0, 5 + y, 0), Color("1c1a19"))


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
	# contents: milk, bread, greens, carrots, banana, box
	var by := y0 + 1
	vb.box(Vector3i(2, by, 3), Vector3i(4, 9, 4), Color("fbfbf8"))
	vb.box(Vector3i(3, by + 9, 4), Vector3i(2, 1, 2), Color("2e7de0"))
	vb.box(Vector3i(2, by + 5, 7), Vector3i(4, 2, 1), Color("2e7de0"))
	vb.box(Vector3i(7, by, 2), Vector3i(8, 6, 5), Color("c98a43"))
	vb.box(Vector3i(7, by + 6, 3), Vector3i(8, 1, 3), Color("e2a95c"))
	var pv := VoxelBuilder.new()
	Produce.lettuce(pv, Vector3i(2, by + 2, 15))
	Produce.broccoli(pv, Vector3i(9, by + 3, 18))
	Produce.carrot(pv, Vector3i(3, by + 9, 11), 0)
	Produce.carrot(pv, Vector3i(4, by + 10, 9), 0)
	Produce.bananas(pv, Vector3i(7, by + 8, 10), 3)
	Produce.tomato(pv, Vector3i(11, by + 6, 13))
	Produce.apple(pv, Vector3i(12, by + 4, 20))
	for p: Vector3i in pv.vox:
		vb.set_v(p, pv.vox[p])
	vb.box(Vector3i(10, by, 8), Vector3i(5, 8, 3), Color("e8402f"))
	vb.box(Vector3i(10, by + 4, 10), Vector3i(5, 2, 1), Color("fdf3d4"))
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
