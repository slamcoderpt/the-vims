extends RefCounted
## High-detail ("micro voxel") props, authored in HALF furniture cells
## (PropLib.scale_of() returns FU * 0.5 for every model here). Use them for
## small hero props that the camera reads up close: desk gear, cork board,
## the office chair. Same conventions as furniture.gd: footprint from (0,0,0),
## front faces +Z, wall-mounted models have their back at z = 0.
## Use through PropLib (scripts/props/prop_lib.gd), not directly.

const V := preload("res://scripts/props/vox_util.gd")

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const BLK := Color("24252b")
const METAL := Color("b9bcc4")
const PINS := [Color("e2463a"), Color("3a7fe0"), Color("f2c53a"), Color("53b34a"), Color("f07ab0")]


# ------------------------------------------------------------------ wall

## Cork board with pinned notes, photos, a calendar and a red string (ref1).
## v0 1.4 x 0.9 m, v1 1.1 x 0.75 m.
static func m_corkboard_hd(vb: VoxelBuilder, v: int) -> void:
	var w := 40 if v == 0 else 32
	var h := 26 if v == 0 else 22
	var fr := V.wood(WOOD, 0, 2)
	V.b(vb, 0, 0, 0, w, h, 1, WOOD_D)
	V.b(vb, 0, 0, 1, w, 2, 1, fr); V.b(vb, 0, h - 2, 1, w, 2, 1, fr)
	V.b(vb, 0, 0, 1, 2, h, 1, fr); V.b(vb, w - 2, 0, 1, 2, h, 1, fr)
	# Cork: warm tan with darker flecks.
	var cork := func(q: Vector3i) -> Color:
		var hh := VoxelBuilder.hash3(q + Vector3i(3, 9, 1))
		if hh > 0.9:
			return Color("a8743f")
		if hh < 0.2:
			return Color("d9ad72")
		return Color("c99a60")
	V.b(vb, 2, 2, 1, w - 4, h - 4, 1, cork)
	# Items: [kind, x, y, w, h, colour]
	var items := [
		["note", 3, 15, 7, 7, Color("fff3a0")],
		["photo", 11, 16, 8, 7, Color("7fb6e8")],
		["cal", 21, 13, 10, 10, Color("ffffff")],
		["note", 32, 16, 6, 6, Color("ffc4d8")],
		["photo", 3, 4, 7, 9, Color("f2b880")],
		["note", 11, 6, 6, 7, Color("bfe3ff")],
		["photo", 18, 3, 8, 8, Color("9fd08a")],
		["note", 27, 4, 5, 6, Color("c8f0b8")],
		["note", 33, 5, 5, 8, Color("ffffff")],
	]
	if v == 1:
		items = [
			["note", 3, 12, 6, 7, Color("fff3a0")], ["photo", 10, 13, 8, 6, Color("7fb6e8")],
			["note", 20, 13, 5, 6, Color("ffc4d8")], ["photo", 26, 11, 5, 8, Color("f2b880")],
			["note", 3, 3, 7, 7, Color("bfe3ff")], ["cal", 12, 3, 9, 8, Color("ffffff")], ["note", 23, 3, 6, 6, Color("c8f0b8")],
		]
	var pin_pts: Array[Vector2i] = []
	for i in items.size():
		var it: Array = items[i]
		var x: int = it[1]
		var y: int = it[2]
		var iw: int = mini(it[3], w - 2 - x)
		var ih: int = mini(it[4], h - 2 - y)
		var c: Color = it[5]
		match it[0]:
			"note":
				V.b(vb, x, y, 2, iw, ih, 1, c)
				for ly in range(y + 1, y + ih - 2, 2):
					var lw := iw - 2 - int(V.hs(x, ly, i) * 2.0)
					V.b(vb, x + 1, ly, 2, maxi(1, lw), 1, 1, V.shade(c, 0.62))
				# Folded corner.
				V.p(vb, x + iw - 1, y, 2, V.shade(c, 0.8))
			"photo":
				V.b(vb, x, y, 2, iw, ih, 1, Color("fbfaf6"))
				for px in range(x + 1, x + iw - 1):
					for py in range(y + 2, y + ih - 1):
						var t := float(py - y - 2) / maxf(1.0, ih - 3.0)
						var pc: Color = c.lerp(Color("eef6ff"), t * 0.6)
						var hill := y + 2 + int(2.0 + sin(px * 0.9 + i) * 1.2)
						if py <= hill:
							pc = Color("5f9e48") if i % 2 == 0 else Color("c86a4a")
						if i % 3 == 1 and (px - x - iw / 2) * (px - x - iw / 2) + (py - y - ih / 2) * (py - y - ih / 2) <= 3:
							pc = Color("f2c6a0")   # a face
						V.p(vb, px, py, 2, pc)
			"cal":
				V.b(vb, x, y, 2, iw, ih, 1, c)
				V.b(vb, x, y + ih - 3, 2, iw, 3, 1, Color("e2463a"))
				V.b(vb, x + 2, y + ih - 2, 2, iw - 4, 1, 1, Color("ffffff"))
				for gx in range(x + 1, x + iw - 1, 2):
					for gy in range(y + 1, y + ih - 4, 2):
						V.p(vb, gx, gy, 2, Color("b9bcc4") if V.hs(gx, gy, 2) > 0.18 else Color("e2463a"))
		var pin := Vector2i(x + iw / 2, y + ih - 1)
		V.p(vb, pin.x, pin.y, 3, PINS[i % PINS.size()])
		pin_pts.append(pin)
	# Red string between a few pins (one voxel thick, on the pin layer).
	var path := [0, 4, 5, 2, 7] if v == 0 else [0, 5, 3]
	for k in path.size() - 1:
		var a: Vector2i = pin_pts[path[k]]
		var bp: Vector2i = pin_pts[path[k + 1]]
		var n := maxi(absi(bp.x - a.x), absi(bp.y - a.y))
		for s in range(1, n):
			var t := float(s) / n
			var q := Vector2i(roundi(lerpf(a.x, bp.x, t)), roundi(lerpf(a.y, bp.y, t)))
			if not vb.has(Vector3i(q.x, q.y, 3)):
				V.p(vb, q.x, q.y, 3, Color("d23a3a"))


# ------------------------------------------------------------------ desk gear

## Flat-panel monitor on a stand. v0 big (0.66 m) with an email app, v1 the
## same panel showing code, v2 a small portrait-ish second screen.
static func m_monitor_hd(vb: VoxelBuilder, v: int) -> void:
	var w := 19 if v != 2 else 14
	var h := 12 if v != 2 else 10
	# Stand: foot plate, neck.
	V.b(vb, w / 2 - 3, 0, 0, 6, 1, 4, BLK)
	V.b(vb, w / 2 - 1, 1, 0, 2, 4, 1, Color("3a3c44"))
	# Panel: back shell, bezel.
	V.b(vb, 0, 4, 0, w, h, 1, Color("30323a"))
	V.b(vb, 0, 4, 1, w, h, 1, BLK)
	V.b(vb, w / 2 - 1, 4, 1, 2, 1, 1, Color("5a5d66"))
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			var c := _screen(v, x, y, w, h)
			V.p(vb, x, 4 + y, 2, c, true)


static func _screen(v: int, x: int, y: int, w: int, h: int) -> Color:
	var top := h - 2
	if v == 1:
		# Code editor: dark with coloured lines.
		if y == top:
			return Color("3b4252")
		if x < 4:
			return Color("2b303b") if y % 2 == 0 else Color("323846")
		if y % 2 == 1:
			var ln := 4 + int(V.hs(y, 3, v) * (w - 7))
			if x < ln and x > 4 + int(V.hs(y, 5, v) * 3.0):
				return [Color("8fd16a"), Color("6fb3ff"), Color("f2c66a"), Color("e98ab8")][int(V.hs(x / 3, y, 9) * 4.0)]
		return Color("1f232c")
	# Email / desktop app: blue frame, white window with a list.
	if y == top:
		return Color("2f6fd0")
	if y == 1:
		return Color("cfe0f6") if x % 3 != 0 else Color("2f6fd0")
	if x < 4:
		return Color("e1ebf8") if y % 2 == 0 else Color("cfdcef")
	if x == 4:
		return Color("b9c9e0")
	if y % 2 == 0:
		var lw := 6 + int(V.hs(y, 1, v) * (w - 12))
		if x > 5 and x < 5 + lw:
			return Color("8fa7c8") if x < 9 else Color("c4d2e6")
	if y == top - 2 and x > 5 and x < 9:
		return Color("3f86e6")
	return Color("f6f9fd")


static func m_laptop_hd(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("aeb3bc")
	V.b(vb, 0, 0, 2, 13, 1, 8, c)
	# Keys.
	for x in range(1, 12):
		for z in range(3, 7):
			V.p(vb, x, 1, z, Color("4a4e57") if (x + z) % 2 == 0 else Color("3c4048"))
	V.b(vb, 4, 1, 8, 5, 1, 1, Color("8f949c"))
	# Screen (upright at the back).
	V.b(vb, 0, 1, 1, 13, 9, 1, c)
	for x in range(1, 12):
		for y in range(2, 9):
			var col := Color("5d9be8")
			if x > 1 and x < 11 and y > 2 and y < 8:
				col = Color("f4f8fd") if (y % 2 == 0 or x < 4) else Color("c8d8ee")
			V.p(vb, x, y, 2, col, true)


static func m_keyboard_hd(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 17, 1, 6, Color("d8dbe1"))
	for x in range(1, 16):
		for z in range(1, 5):
			if x == 1 or x % 1 == 0:
				V.p(vb, x, 1, z, Color("f4f5f8") if (x + z * 2) % 3 != 0 else Color("e6e8ec"))
	V.b(vb, 4, 1, 1, 9, 1, 1, Color("f4f5f8"))
	# Mouse + pad.
	V.b(vb, 19, 0, 0, 6, 1, 6, Color("3b5f8f"))
	V.b(vb, 21, 1, 2, 2, 1, 3, Color("f0f1f4"))


static func m_printer_hd(vb: VoxelBuilder, _v: int) -> void:
	var c := Color("d9dade")
	V.b(vb, 0, 0, 0, 18, 7, 13, V.noisy(c, 0.025))
	V.b(vb, 0, 7, 0, 18, 3, 10, V.shade(c, 0.94))
	V.b(vb, 1, 10, 1, 16, 1, 8, V.shade(c, 0.86))
	# Paper in the top feeder + output tray.
	V.b(vb, 3, 10, 0, 12, 4, 1, Color("fbfbf6"))
	V.b(vb, 3, 4, 13, 12, 1, 4, Color("fbfbf6"))
	V.b(vb, 2, 3, 13, 14, 1, 4, V.shade(c, 0.8))
	V.b(vb, 2, 2, 12, 14, 1, 1, Color("6b6e76"))
	# Panel.
	V.b(vb, 13, 7, 10, 4, 2, 1, Color("2d3038"))
	V.p(vb, 14, 8, 11, Color("5fd06f"), true)
	V.p(vb, 16, 8, 11, Color("6fb3ff"), true)


static func m_mug_hd(vb: VoxelBuilder, v: int) -> void:
	var c: Color = [Color("f5f2ea"), Color("e86f5a"), Color("6fa0d8"), Color("f2c53a")][v % 4]
	V.cyl(vb, 2.0, 0, 2.0, 2.0, 4, c)
	V.b(vb, 1, 3, 1, 2, 1, 2, Color("6b3e22"))
	V.b(vb, 4, 1, 1, 1, 1, 2, c); V.b(vb, 4, 3, 1, 1, 1, 2, c); V.b(vb, 5, 1, 1, 1, 3, 2, c)


static func m_pencil_cup_hd(vb: VoxelBuilder, _v: int) -> void:
	V.cyl(vb, 2.0, 0, 2.0, 2.0, 4, Color("3f7fc4"))
	var cols := [Color("f2c53a"), Color("e2463a"), Color("53b34a"), Color("7a4b8c"), Color("f07ab0")]
	for k in 5:
		var px: int = [1, 2, 3, 1, 2][k]
		var pz: int = [1, 2, 1, 2, 3][k]
		V.b(vb, px, 4, pz, 1, 2 + k % 3, 1, cols[k])


## Small succulent / leafy desk plant in a white pot.
static func m_desk_plant_hd(vb: VoxelBuilder, v: int) -> void:
	var pot: Color = [Color("f3efe6"), Color("d97b4f"), Color("7393b3")][v % 3]
	V.cyl(vb, 3.0, 0, 3.0, 2.6, 4, V.noisy(pot, 0.04))
	V.b(vb, 1, 3, 1, 4, 1, 4, Color("5b3a22"))
	V.blob(vb, Vector3(3.0, 6.5, 3.0), Vector3(3.4, 3.2, 3.4), V.leaves(v * 5 + 2, v), 0.0, 0.55, v + 7)


static func m_sticky_stack_hd(vb: VoxelBuilder, _v: int) -> void:
	V.b(vb, 0, 0, 0, 4, 2, 4, Color("fff3a0"))
	V.b(vb, 5, 0, 1, 3, 1, 5, Color("ffc4d8"))
	V.b(vb, 9, 0, 0, 1, 1, 6, Color("2f5e8f"))


# ------------------------------------------------------------------ seating

## Swivel office chair on a five-leg star base with casters (ref1).
## Seat top at 13 half cells; v0 tall mesh back, v1 mid back (never hides a
## seated sim's head from a high camera). Front faces +Z.
static func m_office_chair_hd(vb: VoxelBuilder, v: int) -> void:
	var cx := 9.0
	var cz := 9.0
	var frame := Color("2b2d33")
	var cush := Color("40444f")
	# Star base: five legs radiating from the centre, slightly raised.
	for k in 5:
		var a := deg_to_rad(90.0 + k * 72.0)
		var dir := Vector2(cos(a), sin(a))
		for s in range(1, 9):
			var x := floori(cx + dir.x * s)
			var z := floori(cz + dir.y * s)
			V.p(vb, x, 1, z, frame)
			if s > 6:
				V.p(vb, x, 2 if s == 7 else 1, z, frame)
		var ex := floori(cx + dir.x * 8.3)
		var ez := floori(cz + dir.y * 8.3)
		V.p(vb, ex, 0, ez, Color("15161a"))
	V.b(vb, 8, 1, 8, 2, 2, 2, frame)
	# Gas lift.
	V.b(vb, 8, 3, 8, 2, 6, 2, METAL)
	V.b(vb, 6, 9, 6, 6, 1, 6, frame)
	# Seat cushion (rounded corners).
	for x in range(2, 16):
		for z in range(2, 16):
			var corner := (x == 2 or x == 15) and (z == 2 or z == 15)
			if corner:
				continue
			V.p(vb, x, 10, z, V.shade(cush, 0.9))
			V.p(vb, x, 11, z, cush)
			if x > 2 and x < 15 and z > 3 and z < 15:
				V.p(vb, x, 12, z, V.shade(cush, 1.12 + (V.hs(x, 12, z) - 0.5) * 0.08))
	# Back: frame posts + mesh panel, curved slightly.
	var bh := 16 if v == 0 else 11
	V.b(vb, 8, 10, 1, 2, 4, 1, frame)
	for x in range(3, 15):
		var curve := 1 if (x < 5 or x > 12) else 0
		for y in range(14, 14 + bh):
			var edge := x == 3 or x == 14 or y == 14 or y == 13 + bh
			var c := frame if edge else (Color("4c5160") if (x + y) % 2 == 0 else Color("3a3e4a"))
			V.p(vb, x, y, 1 + curve, c)
	# Arm rests.
	for ax: int in [1, 16]:
		V.b(vb, ax, 12, 7, 1, 4, 1, frame)
		V.b(vb, ax, 16, 5, 1, 1, 7, Color("33363d"))
