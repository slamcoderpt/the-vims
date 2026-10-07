extends RefCounted
## Market building shell: tile floor, walls, daylight windows, wooden ceiling
## and beams, pendant lamps (+ lights and halos), hanging signs, greenery.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")

const C := 0.125
const U := 0.0625
const X0 := -6.75
const X1 := 7.75
const Z0 := -8.75
const ZF := 6.6
const H := 5.0

const WALL := Color("dcc29a")
const PLASTER := Color("efe4cd")
const WAINSCOT := Color("a87449")
const CEIL := Color("c9a77c")
const BEAM := Color("7a5232")


static func cc(m: float) -> int:
	return int(round(m / C))


static func build(root: Node3D, halo_pts: Array) -> void:
	Kit.tile_floor(root, Vector2(X1 - X0, ZF - Z0), Vector3((X0 + X1) * 0.5, 0.0, (Z0 + ZF) * 0.5))
	_walls(root)
	_ceiling(root, halo_pts)
	_signs(root)
	_greenery(root)


# ------------------------------------------------------------------ walls

static func _walls(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var x0 := cc(X0) - 1
	var x1 := cc(X1)
	var z0 := cc(Z0) - 1
	var zf := cc(ZF)
	var hh := cc(H)
	var wall_fn := func(p: Vector3i) -> Color:
		if p.y < 9:
			# horizontal wood planks + top rail
			if p.y == 8:
				return Kit.shade(WAINSCOT, 0.78)
			return Kit.shade(WAINSCOT, 0.9 + 0.16 * Kit.h(Vector3i(p.y / 2, p.x / 40, p.z / 40), 2))
		if p.y > hh - 4:
			return Kit.shade(Color("b07a4a"), 0.9 + 0.15 * Kit.h(Vector3i(p.y, 0, 0), 3))
		if p.y == 21 or p.y == 22:
			return Color("6f8f5a")
		# warm honey-wood vertical planks (2 cells wide) above the green rail
		# horizontal shiplap boards; colour changes every ~2 m along the wall
		# so the mesher can merge long runs (cheap on mobile).
		var k := (p.x + p.z) / 16
		var f := 0.88 + 0.2 * Kit.h(Vector3i(k, p.y / 2, 3), 2)
		if p.y % 2 == 0:
			f *= 0.92
		# back wall above the fridges: bright cream plaster (daylight wall)
		if p.z <= z0:
			# vertical warm-wood boards (2 cells wide) with dark seams
			return Kit.shade(PLASTER, 0.94 + 0.08 * Kit.h(Vector3i(p.x / 6, p.y / 3, 1), 2))
		return Kit.shade(WALL, f)
	# Sims-style cutaway: the far walls (left + back) stand full height; the
	# camera-facing walls (right wall towards the front, front wall) are cut
	# down to the wainscot rail so the store reads from the high 3/4 camera.
	var low := 9
	var zr := cc(-6.0)
	vb.box(Vector3i(x0, 0, z0), Vector3i(1, hh, zf - z0 + 1), wall_fn)
	vb.box(Vector3i(x1, 0, z0), Vector3i(1, hh, zr - z0), wall_fn)
	vb.box(Vector3i(x1, 0, zr), Vector3i(1, low, zf - zr + 1), wall_fn)
	vb.box(Vector3i(x0, 0, z0), Vector3i(x1 - x0 + 1, hh, 1), wall_fn)
	# front wall with the entrance gap (automatic doors' track on the floor)
	var gx0 := cc(-1.4)
	var gx1 := cc(1.6)
	vb.box(Vector3i(x0, 0, zf), Vector3i(gx0 - x0, low, 1), wall_fn)
	vb.box(Vector3i(gx1, 0, zf), Vector3i(x1 - gx1 + 1, low, 1), wall_fn)
	vb.box(Vector3i(gx0, 0, zf), Vector3i(gx1 - gx0, 1, 1), Color("8a8f96"))
	# cut-wall caps: dark walnut tops like the home cutaway
	vb.box(Vector3i(x1, low, zr), Vector3i(1, 1, zf - zr + 1), Kit.shade(WAINSCOT, 0.6))
	vb.box(Vector3i(x0, low, zf), Vector3i(gx0 - x0, 1, 1), Kit.shade(WAINSCOT, 0.6))
	vb.box(Vector3i(gx1, low, zf), Vector3i(x1 - gx1 + 1, 1, 1), Kit.shade(WAINSCOT, 0.6))
	# Big daylight windows: a continuous band across the back wall above the
	# fridge row, plus clerestory windows high on both side walls towards the
	# back, so the deep end of the store is the brightest part of the frame.
	var win := VoxelBuilder.new()
	win.jitter = 0.0
	var night := Game.is_night()
	var y0 := cc(3.05)
	var wh := cc(1.5)
	# back wall: panes 1.25 m wide between mullion posts
	var bx := cc(X0 + 0.35)
	while bx + cc(1.25) <= cc(X1 - 0.3):
		_window(vb, win, func(i: int, y: int) -> Vector3i: return Vector3i(bx + i, y, z0), Vector3i(0, 0, -1), cc(1.25), y0, wh, night, bx)
		bx += cc(1.25) + 1
	# side walls (towards the back of the store, above the racks / gondolas)
	for wz: float in [-8.1, -5.7, -3.3]:
		var a := cc(wz)
		_window(vb, win, func(i: int, y: int) -> Vector3i: return Vector3i(x0, y, a + i), Vector3i(-1, 0, 0), cc(2.2), cc(2.75), cc(1.6), night, a + 7)
		if wz < -8.0:
			_window(vb, win, func(i: int, y: int) -> Vector3i: return Vector3i(x1, y, a + i), Vector3i(1, 0, 0), cc(2.2), cc(3.0), cc(1.4), night, a + 3)
	Kit.add(root, vb, C, "Walls", false, null, Vector3.ZERO, Vector3.ZERO, true)
	Kit.add(root, win, C, "Windows", false, Kit.glow_mat("sky"))
	# Left-wall top band under the FRESH sign gets a slatted wood finish (part of walls).


## Cut a window of w x wh cells into wall builder `vb` (cells from `at(i, y)`)
## and put the daylight view (sky, tree tops, a far rooftop) in `win`, one
## cell outside along `out`. Mullions / sill stay in the wall builder.
static func _window(vb: VoxelBuilder, win: VoxelBuilder, at: Callable, out: Vector3i, w: int, y0: int, wh: int, night: bool, seed: int) -> void:
	for i in w:
		for y in wh:
			var p: Vector3i = at.call(i, y0 + y)
			var mull := i == 0 or i == w - 1 or y == 0 or y == wh - 1 or i == w / 2 or y == wh / 2
			vb.clear_box(p, Vector3i.ONE)
			if mull:
				vb.set_v(p, Color("f4efe6") if y != 0 else Color("e9dfcf"))
				continue
			var t := float(y) / wh
			var sky := Color(0.36, 0.62, 0.92).lerp(Color(0.72, 0.86, 0.98), 1.0 - t)
			var g := float(i + seed)
			var tree_h := 3.0 + 2.5 * sin(g * 0.55) + 1.6 * sin(g * 1.7)
			if float(y) < tree_h:
				sky = Color(0.3, 0.56, 0.26) if (i + y) % 3 != 0 else Color(0.44, 0.68, 0.32)
			if night:
				sky = Color(0.08, 0.1, 0.22).lerp(Color(0.16, 0.18, 0.34), 1.0 - t) if float(y) >= tree_h else Color(0.05, 0.08, 0.1)
			win.set_v(p + out, sky, true)
	for i in w:
		var s: Vector3i = at.call(i, y0 - 1)
		vb.set_v(s - out, Color("efe6d6"))


# ------------------------------------------------------------------ ceiling + lamps

static func _ceiling(root: Node3D, halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var x0 := cc(X0) - 1
	var x1 := cc(X1) + 1
	var z0 := cc(Z0) - 1
	var zf := cc(ZF)
	var hh := cc(H)
	# Cutaway: no ceiling slab. Only open timber beams across the back half
	# (they read against the back wall) carrying the pendant cords.
	for bz in [-2.3, -5.2, -7.9]:
		vb.box(Vector3i(x0, hh - 2, cc(bz)), Vector3i(x1 - x0, 2, 2), BEAM)
	Kit.add(root, vb, C, "Ceiling", false, null, Vector3.ZERO, Vector3.ZERO, true, false)
	# Pendant lamps at U: rows across the store, hanging lower towards the
	# back so they read in the eye-level camera, each with a warm omni light
	# and a soft light pool on the glossy floor.
	var lamps := VoxelBuilder.new()
	lamps.jitter = 0.0
	var pools := []
	var rows := [[-2.3, 3.4, [-4.4, -0.85, 0.95, 4.75, 6.6], true], [-5.2, 3.6, [-5.0, 1.0, 6.4], true],
		[-7.9, 3.8, [0.6, 5.6], false]]
	for r: Array in rows:
		for x: float in r[2]:
			var p := Vector3(x, r[1], r[0])
			if is_equal_approx(x, 0.95):
				p.y = 2.95   # hangs low so it clears the Dairy / Snacks signs
			var cord := int((H - 0.25 - p.y) / U) - 7
			Fx.pendant(lamps, Vector3i(int(round(p.x / U)), int(round(p.y / U)), int(round(p.z / U))), cord)
			# warm bloom around the bulb: a wide soft amber glow + a hot core
			halo_pts.append([p + Vector3(0.03, 0.02, 0.03), 1.9, Color(1.0, 0.7, 0.38, 1.0)])
			halo_pts.append([p + Vector3(0.03, 0.0, 0.03), 0.7, Color(1.0, 0.92, 0.72, 1.0)])
			if r[3] == true:
				# warm cone straight down: a pool on the tiles / crates below
				Kit.spot(root, p + Vector3(0, -0.05, 0), Color(1.0, 0.8, 0.55), 3.4, 5.5, 36.0)
			elif r[3] == false:
				Kit.light(root, p + Vector3(0, -0.4, 0), Color(1.0, 0.86, 0.66), 1.1, 4.0)
			pools.append([Vector3(x, 0.012, r[0] + 0.25), Vector2(3.4, 3.4), Color(1.0, 0.68, 0.36, 0.62 if r[3] == true else 0.4)])
	Kit.add(root, lamps, U, "Pendants", false, Kit.glow_mat("warm"), Vector3.ZERO, Vector3.ZERO, true, false)
	# Cool spill from the fridge bank + its reflection streak on the tiles.
	for fx: float in [-4.6, -1.4, 1.8, 5.0]:
		Kit.light(root, Vector3(fx, 1.4, -7.45), Color(0.78, 0.88, 1.0), 1.15, 5.0)
	pools.append([Vector3(-1.0, 0.014, -7.6), Vector2(11.0, 2.6), Color(0.6, 0.8, 1.0, 0.6)])
	pools.append([Vector3(5.2, 0.014, -7.6), Vector2(4.6, 2.2), Color(0.6, 0.8, 1.0, 0.5)])
	# Spill pools in the front walkway (from the pendants above the camera).
	for wp: Vector3 in [Vector3(-1.0, 0.012, 0.9), Vector3(1.3, 0.012, 0.6), Vector3(0.2, 0.012, 2.4)]:
		pools.append([wp, Vector2(3.0, 3.0), Color(1.0, 0.7, 0.4, 0.38)])
	root.add_child(Kit.pools(pools))


# ------------------------------------------------------------------ signs

static func _board(root: Node3D, nm: String, center: Vector3, rot_y: float, w: float, h: float, face: Color, frame: Color, chains := true, chain_top := -1.0) -> MeshInstance3D:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var W := int(round(w / U))
	var Hh := int(round(h / U))
	for x in W:
		for y in Hh:
			var edge := x < 2 or y < 2 or x >= W - 2 or y >= Hh - 2
			var p := Vector3i(x, y, 0)
			if edge:
				vb.set_v(p, Kit.vary(frame, p, 0.08, 2))
				vb.set_v(p + Vector3i(0, 0, 1), Kit.vary(Kit.shade(frame, 1.08), p, 0.08, 3))
			else:
				vb.set_v(p, Kit.vary(face, p, 0.035, 1))
	if chains:
		var top := int(round(((H - 0.25 if chain_top < 0.0 else chain_top) - (center.y + h * 0.5)) / U))
		for cx in [6, W - 7]:
			for y in top:
				vb.set_v(Vector3i(cx, Hh + y, 0), Color("2a2624") if y % 2 == 0 else Color("4a4440"))
	var mi := Kit.add(root, vb, U, nm, false, null, center, Vector3(W * 0.5, Hh * 0.5, 0.5), false, false)
	mi.rotation.y = deg_to_rad(rot_y)
	return mi


## Fit text inside w x h (metres) on a board; stretch > 1 makes it taller.
static func _text(board: Node3D, text: String, at: Vector3, w: float, h: float, col: Color, stretch := 1.0, fs := 128) -> Label3D:
	var f := Kit.font()
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var px := minf(w / maxf(sz.x, 1.0), h / maxf(sz.y * 0.72 * stretch, 1.0))
	var l := Kit.label(board, text, at, px, col, 0.0, fs)
	l.scale = Vector3(1.0, stretch, 1.0)
	return l


static func _signs(root: Node3D) -> void:
	var z := 0.105
	# FRESH & LOCAL (big green, over the produce side, angled towards the aisle)
	var fresh := _board(root, "SignFresh", Vector3(-3.3, 3.2, -5.4), 14.0, 3.7, 1.04, Color("2f7f3b"), Color("8a5a31"))
	_text(fresh, "FRESH & LOCAL", Vector3(-0.3, 0.0, z), 2.7, 0.64, Color("fbf6e6"), 1.3)
	var lv := VoxelBuilder.new()
	Fx.leaf_icon(lv, Vector3i(0, 0, 0), Color("8fd14f"), Color("3d8a2a"))
	Kit.add(fresh, lv, U * 1.3, "Leaf", false, null, Vector3(1.4, -0.02, 0.11), Vector3(3.5, 4, 0))
	# Produce
	var prod := _board(root, "SignProduce", Vector3(-4.3, 2.75, -2.6), 24.0, 1.3, 0.4, Color("3a2a20"), Color("7a5130"), true, 3.6)
	_text(prod, "Produce", Vector3(0, 0.0, z), 0.95, 0.24, Color("f6efe0"))
	# MARKET (over the grocery aisles, right)
	var mk := _board(root, "SignMarket", Vector3(3.2, 3.15, -6.6), -8.0, 2.9, 0.84, Color("34302d"), Color("8a5a31"))
	_text(mk, "MARKET", Vector3(0.1, 0.0, z), 1.6, 0.46, Color("f4eedf"), 1.25)
	var cv := VoxelBuilder.new()
	Fx.cart_icon(cv, Vector3i(0, 0, 0), Color("f4eedf"))
	Kit.add(mk, cv, U * 0.8, "CartIcon", false, null, Vector3(-1.05, 0.0, 0.11), Vector3(5.5, 4.5, 0))
	var lv2 := VoxelBuilder.new()
	Fx.leaf_icon(lv2, Vector3i(0, 0, 0), Color("6cbf45"), Color("2f7a2a"))
	Kit.add(mk, lv2, U * 0.75, "Leaf", false, null, Vector3(1.15, 0.0, 0.11), Vector3(3.5, 4, 0))
	# Aisle signs hanging over the aisles, deeper in the store.
	# Hanging aisle signs in a row across the store (like ref5): Dairy in
	# front of the milk fridges, Snacks over the cereal end caps, Beverages
	# over the drinks aisle, Bakery angled over the bread shelves.
	var aisles := [["Dairy", Vector3(-0.75, 2.42, -6.4), 0.0, 1.5], ["Snacks", Vector3(1.95, 2.5, -4.3), -4.0, 1.55],
		["Beverages", Vector3(3.72, 2.32, -5.8), -6.0, 1.6], ["Bakery", Vector3(6.35, 2.25, -1.0), -18.0, 1.2]]
	for a in aisles:
		var bh := 0.5 if a[3] < 2.0 else 0.56
		var b := _board(root, "Sign" + a[0], a[1], a[2], a[3], bh, Color("3b2a1f"), Color("7a5130"), true, a[1].y + 0.75)
		_text(b, a[0], Vector3(0, 0.0, z), a[3] - 0.26, bh - 0.16, Color("f6efe0"))


# ------------------------------------------------------------------ greenery

static func _greenery(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.06
	# Hanging ivy along the top of the left wall and from the front beam.
	var strands := []
	for i in 5:
		strands.append(Vector3(X0 + 0.15, H - 0.2, -8.0 + i * 1.7))
	for i in strands.size():
		var s: Vector3 = strands[i]
		var base := Vector3i(int(round(s.x / U)), int(round(s.y / U)), int(round(s.z / U)))
		var ln := 8 + int(Kit.h(base, 3) * 18.0)
		var dx := 0
		for y in ln:
			if Kit.h(base + Vector3i(0, y, 0), 5) > 0.75:
				dx += 1 if Kit.h(base, y) > 0.5 else -1
				dx = clampi(dx, -2, 2)
			var p := base + Vector3i(0, -y, dx)
			var col := Color("3f8a2e") if Kit.h(p, 6) > 0.4 else Color("6cb83f")
			vb.set_v(p, col)
			if y % 2 == 0:
				vb.set_v(p + Vector3i(1, 0, 0), Kit.shade(col, 1.1))
			if y % 3 == 1:
				vb.set_v(p + Vector3i(0, 0, 1), Kit.shade(col, 0.9))
	# Hanging planters with trailing ivy (top of frame, like the reference).
	for hp: Vector3 in [Vector3(-5.2, 3.4, -0.6), Vector3(-4.9, 3.2, -4.4),
			Vector3(-5.0, 3.3, -7.4)]:
		var o := Vector3i(int(round(hp.x / U)), int(round(hp.y / U)), int(round(hp.z / U)))
		for x in range(-3, 4):
			for z in range(-3, 4):
				if absi(x) + absi(z) > 4:
					continue
				for y in 3:
					vb.set_v(o + Vector3i(x, y, z), Kit.vary(Color("b5703f"), o + Vector3i(x, y, z), 0.08))
				# leafy dome
				var hh := 3 - (absi(x) + absi(z)) / 2
				for y in hh:
					var p := o + Vector3i(x, 3 + y, z)
					vb.set_v(p, Color("4f9e34") if Kit.h(p, 2) > 0.4 else Color("74c044"))
		# chains
		var top := int((H - 0.2 - hp.y) / U) - 3
		for y in top:
			vb.set_v(o + Vector3i(0, 6 + y, 0), Color("2a2624"))
		# trailing strands
		for k in 6:
			var a := float(k) / 6.0 * TAU
			var sx := int(round(cos(a) * 3.5))
			var sz := int(round(sin(a) * 3.5))
			var ln := 6 + int(Kit.h(o + Vector3i(k, 0, 0), 4) * 16.0)
			for y in ln:
				var p := o + Vector3i(sx + (y / 7) * signi(sx), 2 - y, sz)
				vb.set_v(p, Color("3f8a2e") if Kit.h(p, 6) > 0.45 else Color("6cb83f"))
				if y % 3 == 0:
					vb.set_v(p + Vector3i(0, 0, 1), Color("5aa83a"))
	Kit.add(root, vb, U, "Ivy", false, null, Vector3.ZERO, Vector3.ZERO, false, false)
