extends RefCounted
## Market building shell: tile floor, walls, daylight windows, wooden ceiling
## and beams, pendant lamps (+ lights and halos), hanging signs, greenery.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")

const C := 0.125
const U := 0.0625
const X0 := -6.75
const X1 := 7.75
const Z0 := -11.75
const ZF := 17.0
const H := 5.0

const WALL := Color("dcb88e")
const PLASTER := Color("f2ebde")
const WAINSCOT := Color("b07a4a")
const CEIL := Color("7b5232")
const BEAM := Color("5e3c22")


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
			return Kit.shade(Color("8a5a34"), 0.9 + 0.15 * Kit.h(Vector3i(p.y, 0, 0), 3))
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
			return Kit.shade(PLASTER, 0.97 + 0.04 * Kit.h(Vector3i(p.x / 8, p.y / 4, 1), 2))
		return Kit.shade(WALL, f)
	# left / right / back
	vb.box(Vector3i(x0, 0, z0), Vector3i(1, hh, zf - z0), wall_fn)
	vb.box(Vector3i(x1, 0, z0), Vector3i(1, hh, zf - z0), wall_fn)
	vb.box(Vector3i(x0, 0, z0), Vector3i(x1 - x0 + 1, hh, 1), wall_fn)
	# back-wall windows (daylight) above the fridges
	var win := VoxelBuilder.new()
	win.jitter = 0.0
	var night := Game.is_night()
	for wx in [-4.4, -1.5, 1.4, 4.3]:
		var a := cc(wx - 1.1)
		var w := cc(2.2)
		var y0 := cc(2.95)
		var wh := cc(1.45)
		vb.clear_box(Vector3i(a, y0, z0), Vector3i(w, wh, 1))
		for x in w:
			for y in wh:
				var mull := x == 0 or x == w - 1 or y == 0 or y == wh - 1 or x == w / 2 or y == wh / 2
				var p := Vector3i(a + x, y0 + y, z0)
				if mull:
					vb.set_v(p, Color("3c3f45"))
				else:
					var t := float(y) / wh
					var sky := Color(0.55, 0.76, 0.95).lerp(Color(0.9, 0.95, 0.98), 1.0 - t)
					# tree canopy outside along the bottom of the window
					var tree_h := 4.0 + 3.0 * sin(float(a + x) * 0.7) + 2.0 * sin(float(a + x) * 1.9)
					if float(y) < tree_h:
						sky = Color(0.42, 0.66, 0.36) if (x + y) % 3 != 0 else Color(0.52, 0.74, 0.4)
					if night:
						sky = Color(0.08, 0.1, 0.22).lerp(Color(0.16, 0.18, 0.34), 1.0 - t) if float(y) >= tree_h else Color(0.05, 0.08, 0.1)
					win.set_v(p + Vector3i(0, 0, -1), sky, true)
				# sill
			vb.set_v(Vector3i(a + x, y0 - 1, z0 + 1), Color("e9dfcf"))
	Kit.add(root, vb, C, "Walls", false, null, Vector3.ZERO, Vector3.ZERO, true)
	Kit.add(root, win, C, "Windows", false, Kit.glow_mat("sky"))
	# Left-wall top band under the FRESH sign gets a slatted wood finish (part of walls).


# ------------------------------------------------------------------ ceiling + lamps

static func _ceiling(root: Node3D, halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var x0 := cc(X0) - 1
	var x1 := cc(X1) + 1
	var z0 := cc(Z0) - 1
	var zf := cc(ZF)
	var hh := cc(H)
	vb.box(Vector3i(x0, hh, z0), Vector3i(x1 - x0, 1, zf - z0), func(p: Vector3i) -> Color:
		var k := p.z / 3
		return Kit.shade(CEIL, 0.85 + 0.25 * Kit.h(Vector3i(0, 0, k), 4)))
	# beams across x
	for bz in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
		vb.box(Vector3i(x0, hh - 3, cc(bz)), Vector3i(x1 - x0, 3, 2), BEAM)
	# two long beams along z
	for bx in [-2.25, 3.25]:
		vb.box(Vector3i(cc(bx), hh - 2, z0), Vector3i(2, 2, zf - z0), Color("6b4528"))
	Kit.add(root, vb, C, "Ceiling", false, null, Vector3.ZERO, Vector3.ZERO, true, false)
	# Pendant lamps at U: rows across the store, hanging lower towards the
	# back so they read in the eye-level camera, each with a warm omni light
	# and a soft light pool on the glossy floor.
	var lamps := VoxelBuilder.new()
	lamps.jitter = 0.02
	var pools := []
	var rows := [[3.4, 4.55, [-4.0, -1.3, 1.5, 4.4], true], [0.6, 4.4, [-4.3, -0.8, 1.3, 5.3], true],
		[-2.3, 3.75, [-4.4, -1.6, 1.2, 3.5, 6.0], true], [-5.2, 3.65, [-4.1, -1.5, 1.2, 3.5, 6.0], true],
		[-8.0, 3.55, [-4.0, -1.4, 1.2, 3.5, 6.0], false], [-10.5, 3.5, [-3.0, -0.2, 2.4, 5.0], false]]
	for r: Array in rows:
		for x: float in r[2]:
			var p := Vector3(x, r[1], r[0])
			var cord := int((H - 0.19 - p.y) / U) - 4
			Fx.pendant(lamps, Vector3i(int(round(p.x / U)), int(round(p.y / U)), int(round(p.z / U))), cord)
			halo_pts.append([p + Vector3(0.03, -0.1, 0.03), 1.7, Color(1.0, 0.7, 0.38, 1.0)])
			halo_pts.append([p + Vector3(0.03, -0.12, 0.03), 0.45, Color(1.0, 0.92, 0.75, 1.0)])
			if r[3] and absf(x - 3.5) > 0.1:
				Kit.light(root, p + Vector3(0, -0.35, 0), Color(1.0, 0.86, 0.66), 1.0, 4.4)
			pools.append([Vector3(x, 0.012, r[0]), Vector2(2.1, 2.1), Color(1.0, 0.8, 0.5, 0.4 if r[3] else 0.28)])
	Kit.add(root, lamps, U, "Pendants", false, Kit.glow_mat("warm"), Vector3.ZERO, Vector3.ZERO, false, false)
	# Cool spill from the fridge bank + its reflection streak on the tiles.
	Kit.light(root, Vector3(-2.8, 1.4, -10.3), Color(0.78, 0.9, 1.0), 1.6, 4.5)
	Kit.light(root, Vector3(0.4, 1.4, -10.3), Color(0.78, 0.9, 1.0), 1.6, 4.5)
	Kit.light(root, Vector3(3.6, 1.4, -10.3), Color(0.78, 0.9, 1.0), 1.6, 4.5)
	Kit.light(root, Vector3(6.4, 1.4, -10.3), Color(0.78, 0.9, 1.0), 1.2, 3.5)
	pools.append([Vector3(0.4, 0.014, -10.5), Vector2(10.5, 2.2), Color(0.6, 0.8, 1.0, 0.6)])
	pools.append([Vector3(5.6, 0.014, -10.5), Vector2(3.6, 1.8), Color(0.6, 0.8, 1.0, 0.5)])
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
	var fresh := _board(root, "SignFresh", Vector3(-2.6, 4.1, -1.2), 24.0, 4.0, 1.12, Color("2f7f3b"), Color("8a5a31"))
	_text(fresh, "FRESH & LOCAL", Vector3(-0.3, 0.0, z), 2.9, 0.68, Color("fbf6e6"), 1.3)
	var lv := VoxelBuilder.new()
	Fx.leaf_icon(lv, Vector3i(0, 0, 0), Color("8fd14f"), Color("3d8a2a"))
	Kit.add(fresh, lv, U * 1.3, "Leaf", false, null, Vector3(1.55, -0.02, 0.11), Vector3(3.5, 4, 0))
	# Produce
	var prod := _board(root, "SignProduce", Vector3(-4.2, 3.0, -2.4), 24.0, 1.3, 0.4, Color("3a2a20"), Color("7a5130"), true, 3.6)
	_text(prod, "Produce", Vector3(0, 0.0, z), 0.95, 0.24, Color("f6efe0"))
	# MARKET (over the grocery aisles, right)
	var mk := _board(root, "SignMarket", Vector3(3.5, 4.25, -2.0), -14.0, 3.1, 0.9, Color("34302d"), Color("8a5a31"))
	_text(mk, "MARKET", Vector3(0.1, 0.0, z), 1.6, 0.46, Color("f4eedf"), 1.25)
	var cv := VoxelBuilder.new()
	Fx.cart_icon(cv, Vector3i(0, 0, 0), Color("f4eedf"))
	Kit.add(mk, cv, U * 0.8, "CartIcon", false, null, Vector3(-1.05, 0.0, 0.11), Vector3(5.5, 4.5, 0))
	var lv2 := VoxelBuilder.new()
	Fx.leaf_icon(lv2, Vector3i(0, 0, 0), Color("6cbf45"), Color("2f7a2a"))
	Kit.add(mk, lv2, U * 0.75, "Leaf", false, null, Vector3(1.15, 0.0, 0.11), Vector3(3.5, 4, 0))
	# Aisle signs hanging over the aisles, deeper in the store.
	var aisles := [["Dairy", Vector3(-0.6, 2.95, -9.4), 0.0, 1.3], ["Snacks", Vector3(2.15, 3.05, -6.0), -4.0, 1.25],
		["Beverages", Vector3(4.3, 3.0, -9.0), -4.0, 1.95], ["Bakery", Vector3(5.9, 2.95, -2.2), -24.0, 1.25]]
	for a in aisles:
		var bh := 0.42 if a[3] < 1.3 else 0.5
		var b := _board(root, "Sign" + a[0], a[1], a[2], a[3], bh, Color("3b2a1f"), Color("7a5130"))
		_text(b, a[0], Vector3(0, 0.0, z), a[3] - 0.26, bh - 0.16, Color("f6efe0"))


# ------------------------------------------------------------------ greenery

static func _greenery(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.06
	# Hanging ivy along the top of the left wall and from the front beam.
	var strands := []
	for i in 10:
		strands.append(Vector3(X0 + 0.15, H - 0.2, -11.2 + i * 1.0))
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
	for hp: Vector3 in [Vector3(-5.2, 3.4, -0.6), Vector3(-4.9, 3.2, -4.4), Vector3(-5.4, 3.5, 2.4),
			Vector3(7.0, 3.45, 0.4), Vector3(-5.0, 3.3, -8.4), Vector3(6.9, 3.55, -5.4), Vector3(-2.6, 3.6, -9.6)]:
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
		for k in 9:
			var a := float(k) / 9.0 * TAU
			var sx := int(round(cos(a) * 3.5))
			var sz := int(round(sin(a) * 3.5))
			var ln := 6 + int(Kit.h(o + Vector3i(k, 0, 0), 4) * 16.0)
			for y in ln:
				var p := o + Vector3i(sx + (y / 7) * signi(sx), 2 - y, sz)
				vb.set_v(p, Color("3f8a2e") if Kit.h(p, 6) > 0.45 else Color("6cb83f"))
				if y % 3 == 0:
					vb.set_v(p + Vector3i(0, 0, 1), Color("5aa83a"))
	Kit.add(root, vb, U, "Ivy", false, null, Vector3.ZERO, Vector3.ZERO, false, false)
