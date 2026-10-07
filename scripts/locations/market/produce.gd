extends RefCounted
## Voxel fruit & veg stamped into a fine builder (P = 1/32 m grid), plus
## helpers that heap them into crates so they read as "overflowing".

const Kit := preload("res://scripts/locations/market/kit.gd")

const P := 0.03125

const RED := Color("e0352b")
const RED2 := Color("c4241e")
const LEAF := Color("3f8f2c")
const LEAF2 := Color("6cbb3a")
const ORANGE := Color("f58a1f")
const YELLOW := Color("f8d23a")
const STEM := Color("6b4a22")


static func c(m: float) -> int:
	return int(round(m / P))


## Rounded 3x3x3 ball (corners removed) with optional stem/leaf.
static func _ball(vb: VoxelBuilder, o: Vector3i, col: Color, s: int, stem := Color(0, 0, 0, 0), leaf := Color(0, 0, 0, 0), size := 3) -> void:
	var k := 0.94 + 0.12 * Kit.h(o, s)
	var base := Kit.shade(col, k)
	for x in size:
		for y in size:
			for z in size:
				var ex := x == 0 or x == size - 1
				var ey := y == 0 or y == size - 1
				var ez := z == 0 or z == size - 1
				if int(ex) + int(ey) + int(ez) >= 3:
					continue
				var p := o + Vector3i(x, y, z)
				var cc := base
				if y == size - 1:
					cc = Kit.shade(base, 1.08)
				elif y == 0:
					cc = Kit.shade(base, 0.85)
				vb.set_v(p, Kit.vary(cc, p, 0.05, s))
	var mid := size / 2
	if stem.a > 0.0:
		vb.set_v(o + Vector3i(mid, size, mid), stem)
	if leaf.a > 0.0:
		vb.set_v(o + Vector3i(mid, size, mid + (1 if Kit.h(o, 4) > 0.5 else -1)), leaf)


static func tomato(vb: VoxelBuilder, o: Vector3i) -> void:
	var col := RED if Kit.h(o, 11) > 0.25 else RED2
	_ball(vb, o, col, 1, LEAF, LEAF2, 4)


static func apple(vb: VoxelBuilder, o: Vector3i, green := false) -> void:
	var col := Color("cf2a2a") if not green else Color("8cc63f")
	_ball(vb, o, col, 2, STEM, LEAF if not green else Color(0, 0, 0, 0), 4)
	if not green:
		vb.set_v(o + Vector3i(0, 2, 1), Color("f0a33a"))
		vb.set_v(o + Vector3i(1, 3, 0), Color("f26a5a"))


static func orange(vb: VoxelBuilder, o: Vector3i) -> void:
	_ball(vb, o, ORANGE, 3, LEAF, Color(0, 0, 0, 0), 4)


static func lemon(vb: VoxelBuilder, o: Vector3i) -> void:
	_ball(vb, o, YELLOW, 4)


static func pepper(vb: VoxelBuilder, o: Vector3i, col: Color) -> void:
	for x in 3:
		for z in 3:
			for y in 4:
				if (x == 0 or x == 2) and (z == 0 or z == 2) and (y == 0 or y == 3):
					continue
				var p := o + Vector3i(x, y, z)
				var cc := col if (x + z) % 2 == 0 else Kit.shade(col, 0.88)
				vb.set_v(p, Kit.vary(cc, p, 0.05, 6))
	vb.set_v(o + Vector3i(1, 4, 1), Color("3e7a23"))


## Carrot lying along +x (dir 0) or +z (dir 1), leaves at the start.
static func carrot(vb: VoxelBuilder, o: Vector3i, dir := 0) -> void:
	var ax := Vector3i(1, 0, 0) if dir == 0 else Vector3i(0, 0, 1)
	var side := Vector3i(0, 0, 1) if dir == 0 else Vector3i(1, 0, 0)
	for i in 7:
		var p := o + ax * i
		var cc := Kit.vary(ORANGE if i % 2 == 0 else Color("ec7a12"), p, 0.05, 2)
		vb.set_v(p, cc)
		if i < 5:
			vb.set_v(p + Vector3i(0, 1, 0), Kit.shade(cc, 1.06))
		if i < 3:
			vb.set_v(p + side, cc)
			vb.set_v(p + side + Vector3i(0, 1, 0), Kit.shade(cc, 1.06))
	# leafy top
	var t := o - ax
	vb.set_v(t + Vector3i(0, 1, 0), LEAF)
	vb.set_v(t - ax + Vector3i(0, 2, 0), LEAF2)
	vb.set_v(t - ax + side + Vector3i(0, 2, 0), LEAF)
	vb.set_v(t - ax * 2 + Vector3i(0, 3, 0), LEAF2)
	vb.set_v(t + side + Vector3i(0, 1, 0), LEAF2)


## Banana bunch: 4 fingers curving up at both ends, along +x.
static func bananas(vb: VoxelBuilder, o: Vector3i, fingers := 4) -> void:
	var curve := [3, 2, 1, 0, 0, 0, 1, 2]
	for f in fingers:
		for i in curve.size():
			var p := o + Vector3i(i, curve[i] + (f % 2), f)
			var cc := YELLOW if i > 0 and i < curve.size() - 1 else Color("a7a83a")
			if i == curve.size() - 1:
				cc = Color("c49a2c")
			vb.set_v(p, Kit.vary(cc, p, 0.05, 8))
			if i > 1 and i < curve.size() - 2:
				vb.set_v(p + Vector3i(0, 1, 0), Kit.vary(Color("fbe05a"), p, 0.04, 9))
	vb.set_v(o + Vector3i(-1, 4, fingers / 2), Color("6d8a2a"))


static func lettuce(vb: VoxelBuilder, o: Vector3i) -> void:
	for x in 5:
		for z in 5:
			for y in 4:
				var dx := absi(x - 2)
				var dz := absi(z - 2)
				if dx + dz + maxi(0, y - 1) > 4 or (y == 0 and dx + dz > 2):
					continue
				var p := o + Vector3i(x, y, z)
				var inner := dx + dz <= 1 and y >= 2
				var cc := Color("a7d94f") if inner else (LEAF2 if Kit.h(p, 3) > 0.4 else Color("4f9e2f"))
				vb.set_v(p, Kit.vary(cc, p, 0.07, 3))


static func broccoli(vb: VoxelBuilder, o: Vector3i) -> void:
	vb.set_v(o + Vector3i(2, 0, 2), Color("8fb85a"))
	vb.set_v(o + Vector3i(2, 1, 2), Color("8fb85a"))
	for x in 5:
		for z in 5:
			for y in 3:
				var dx := absi(x - 2)
				var dz := absi(z - 2)
				if dx + dz > 3 - (1 if y == 2 else 0) or (dx == 2 and dz == 2):
					continue
				var p := o + Vector3i(x, y + 2, z)
				if y == 2 and Kit.h(p, 5) < 0.35:
					continue
				var cc := Color("2f6e2a") if Kit.h(p, 6) > 0.45 else Color("3d8a33")
				vb.set_v(p, Kit.vary(cc, p, 0.08, 4))


static func grapes(vb: VoxelBuilder, o: Vector3i) -> void:
	for y in 4:
		var r := 2 - y / 2
		for x in range(-r, r + 1):
			for z in range(-1, 2):
				if Kit.h(o + Vector3i(x, y, z), 7) < 0.2:
					continue
				var p := o + Vector3i(x + 2, 3 - y, z + 1)
				vb.set_v(p, Kit.vary(Color("6b2f7a") if (x + y + z) % 2 == 0 else Color("85409a"), p, 0.06, 7))
	vb.set_v(o + Vector3i(2, 4, 1), STEM)


static func eggplant(vb: VoxelBuilder, o: Vector3i) -> void:
	for i in 5:
		for y in 2:
			for z in 2:
				var p := o + Vector3i(i, y, z)
				vb.set_v(p, Kit.vary(Color("4b2463"), p, 0.06, 2))
	vb.set_v(o + Vector3i(-1, 1, 0), Color("4c7a2a"))
	vb.set_v(o + Vector3i(-1, 1, 1), Color("4c7a2a"))


static func item(vb: VoxelBuilder, kind: String, o: Vector3i, rnd: float) -> Vector3i:
	## Stamps one item, returns its footprint (x, y, z) in cells.
	match kind:
		"tomato":
			tomato(vb, o); return Vector3i(5, 4, 5)
		"apple":
			apple(vb, o, rnd < 0.12); return Vector3i(5, 4, 5)
		"green_apple":
			apple(vb, o, true); return Vector3i(5, 4, 5)
		"orange":
			orange(vb, o); return Vector3i(5, 4, 5)
		"lemon":
			lemon(vb, o); return Vector3i(3, 3, 3)
		"pepper_red":
			pepper(vb, o, Color("d9261c")); return Vector3i(3, 4, 3)
		"pepper_mix":
			var cols := [Color("d9261c"), Color("f2c12e"), Color("3f9a2e"), Color("f07f1c")]
			pepper(vb, o, cols[int(rnd * 4.0) % 4]); return Vector3i(3, 4, 3)
		"carrot":
			carrot(vb, o + Vector3i(2, 0, 0), 0); return Vector3i(9, 2, 2)
		"banana":
			bananas(vb, o); return Vector3i(10, 4, 6)
		"lettuce":
			lettuce(vb, o); return Vector3i(5, 4, 5)
		"broccoli":
			broccoli(vb, o); return Vector3i(5, 5, 5)
		"greens":
			if rnd < 0.5:
				lettuce(vb, o)
			else:
				broccoli(vb, o)
			return Vector3i(5, 4, 5)
		"grapes":
			grapes(vb, o); return Vector3i(5, 4, 3)
		"eggplant":
			eggplant(vb, o + Vector3i(1, 0, 0)); return Vector3i(6, 2, 2)
	tomato(vb, o)
	return Vector3i(3, 3, 3)


## Heap items into a rectangular bin (cells). The heap is taller at the back
## (-z) and domes in the middle so it spills over the rim.
## from: min corner of the bin interior (cells), size: interior size.
static func heap(vb: VoxelBuilder, kind: String, from: Vector3i, size: Vector3i, layers := 3, seed := 0) -> void:
	var probe := VoxelBuilder.new()
	var fp := item(probe, kind, Vector3i.ZERO, 0.0)
	var step := Vector3i(fp.x, fp.y, fp.z)
	if kind == "carrot":
		step = Vector3i(10, 2, 3)
	elif kind == "banana":
		step = Vector3i(10, 3, 6)
	var nx := maxi(1, size.x / step.x)
	var nz := maxi(1, size.z / step.z)
	var ox := (size.x - nx * step.x) / 2
	var oz := (size.z - nz * step.z) / 2
	for L in layers:
		for ix in nx:
			for iz in nz:
				# Dome profile: taller at the back and in the middle.
				var u := (float(ix) + 0.5) / nx - 0.5
				var v := (float(iz) + 0.5) / nz
				var hgt := float(layers) * (1.0 - 0.9 * u * u * 2.0) * (1.0 - 0.45 * v) + 0.6
				if float(L) >= hgt:
					continue
				var key := Vector3i(ix, L, iz + seed * 31)
				var r := Kit.h(key, 17 + seed)
				var jx := int(r * 3.0) - 1 if L > 0 else 0
				var jz := int(Kit.h(key, 19) * 3.0) - 1 if L > 0 else 0
				var o := from + Vector3i(ox + ix * step.x + jx + (L % 2) * (step.x / 2 if L > 0 else 0), L * step.y, oz + iz * step.z + jz)
				if L > 0 and ix == nx - 1 and (L % 2) == 1:
					continue
				item(vb, kind, o, Kit.h(key, 23))


## Coarse heap for far-away bins (U grid): 2x2x2 blobs with a stem/leaf
## pixel, staggered in layers. Cheap and reads fine through the tilt-shift.
static func mini_heap(vb: VoxelBuilder, kind: String, from: Vector3i, size: Vector3i, layers := 2, seed := 0) -> void:
	# 2x2x2 blobs on a 3-cell pitch so a dark gap separates every item (reads
	# as individual fruit from across the store instead of a colour strip).
	for L in layers:
		var off := (L % 2) * 1 + (L / 2) % 2
		for ix in range(0, size.x - off - 1, 3):
			for iz in range(0, size.z - off - 1, 3):
				var u := (float(ix) + 1.0) / size.x - 0.5
				if L > 0 and absf(u) > 0.44 - 0.12 * L:
					continue
				var o := from + Vector3i(ix + off, L * 2, iz + off)
				var r := Kit.h(o, 31 + seed)
				var col := _mini_col(kind, r)
				for dx in 2:
					for dy in 2:
						for dz in 2:
							var p := o + Vector3i(dx, dy, dz)
							var f := 1.08 if dy == 1 else 0.82
							if dx == 0 and dz == 1 and dy == 1:
								f = 1.25
							vb.set_v(p, Kit.vary(Kit.shade(col, f), p, 0.06, 5))
				if kind in ["tomato", "pepper_red", "pepper_mix", "orange", "carrot", "apple"] and r > 0.35:
					vb.set_v(o + Vector3i(int(r * 7.0) % 2, 2, 1), LEAF if kind != "apple" else STEM)


static func _mini_col(kind: String, r: float) -> Color:
	match kind:
		"tomato": return RED if r > 0.3 else RED2
		"apple": return Color("cf2a2a") if r > 0.15 else Color("8cc63f")
		"green_apple": return Color("8cc63f") if r > 0.2 else Color("a8d455")
		"orange": return ORANGE
		"lemon", "banana": return YELLOW if r > 0.2 else Color("e8c22a")
		"pepper_red": return Color("d9261c")
		"pepper_mix":
			var cols: Array[Color] = [Color("d9261c"), Color("f2c12e"), Color("3f9a2e"), Color("f07f1c")]
			return cols[int(r * 4.0) % 4]
		"carrot": return Color("ef7f16")
		"lettuce", "greens": return LEAF2 if r > 0.4 else Color("4f9e2f")
		"broccoli": return Color("2f6e2a") if r > 0.5 else Color("3d8a33")
		"grapes", "eggplant": return Color("6b2f7a") if r > 0.4 else Color("4b2463")
	return RED


# ================================================================== chunky heaps
# Bigger, rounder produce for crates seen from the eye-level camera: true
# voxel spheres with a lit top, a specular pixel and a dark base, packed in
# staggered layers that dome above the crate rim and spill over the front.

## Voxel sphere of diameter d at min corner o.
static func sphere(vb: VoxelBuilder, o: Vector3i, d: int, col: Color, s: int, squash := 1.0) -> void:
	var r := d * 0.5
	var k := 0.88 + 0.22 * Kit.h(o, s)
	var base := Kit.shade(col, k)
	var hy := int(ceil(d * squash))
	for x in d:
		for y in hy:
			for z in d:
				var dx := x + 0.5 - r
				var dy := (y + 0.5 - hy * 0.5) / squash
				var dz := z + 0.5 - r
				if dx * dx + dy * dy + dz * dz > r * r * 1.08:
					continue
				var p := o + Vector3i(x, y, z)
				var f := 0.78 + 0.32 * (float(y) / maxf(1.0, hy - 1))
				if dz > 0.0 and dy > 0.0 and dx < 0.0 and dx > -r * 0.8 and dy < r * 0.8:
					f += 0.08
				vb.set_v(p, Kit.vary(Kit.shade(base, f), p, 0.035, s))
	# specular glint on the upper-front-left
	vb.set_v(o + Vector3i(maxi(0, int(r) - 1), hy - 1, mini(d - 1, int(r) + 1)), Kit.shade(base, 1.45))


static func big_tomato(vb: VoxelBuilder, o: Vector3i, s: int) -> void:
	var col := RED if Kit.h(o, 11 + s) > 0.2 else Color("e8502c")
	sphere(vb, o, 5, col, s, 0.9)
	# star-shaped calyx
	var t := o + Vector3i(2, 4, 2)
	vb.set_v(t + Vector3i(0, 1, 0), LEAF)
	for dd: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		vb.set_v(t + dd, LEAF2 if Kit.h(o + dd, 3) > 0.5 else LEAF)


static func big_apple(vb: VoxelBuilder, o: Vector3i, s: int, green := false) -> void:
	var col := Color("d42a2a") if not green else Color("98cc45")
	if not green and Kit.h(o, 5 + s) < 0.3:
		col = Color("b81f2a")
	sphere(vb, o, 5, col, s)
	vb.set_v(o + Vector3i(2, 5, 2), STEM)
	if Kit.h(o, 9) > 0.45:
		vb.set_v(o + Vector3i(3, 5, 2), LEAF2)
	if not green:
		vb.set_v(o + Vector3i(0, 3, 3), Color("f2a03a"))


static func big_orange(vb: VoxelBuilder, o: Vector3i, s: int, lemon := false) -> void:
	sphere(vb, o, 5 if not lemon else 4, ORANGE if not lemon else YELLOW, s, 1.0 if not lemon else 0.85)
	vb.set_v(o + Vector3i(2, 5 if not lemon else 3, 2), LEAF if not lemon else Color("b0a83a"))


static func big_pepper(vb: VoxelBuilder, o: Vector3i, s: int, col: Color) -> void:
	for x in 4:
		for z in 4:
			for y in 5:
				var cx := x == 0 or x == 3
				var cz := z == 0 or z == 3
				if cx and cz:
					continue
				if (cx or cz) and y == 0:
					continue
				var p := o + Vector3i(x, y, z)
				var f := 0.82 + 0.06 * y
				if (x == 1 or x == 2) and (z == 1 or z == 2) and y == 4:
					f = 0.7
				if (x + z) % 3 == 0:
					f *= 0.9
				vb.set_v(p, Kit.vary(Kit.shade(col, f), p, 0.04, s))
	vb.set_v(o + Vector3i(1, 5, 2), Color("3e7a23"))
	vb.set_v(o + Vector3i(1, 6, 2), Color("4f8f2a"))
	vb.set_v(o + Vector3i(1, 3, 3), Kit.shade(col, 1.4))


static func big_lettuce(vb: VoxelBuilder, o: Vector3i, s: int, curly := false) -> void:
	var d := 8
	var r := 4.0
	for x in d:
		for z in d:
			for y in 6:
				var dx := x + 0.5 - r
				var dz := z + 0.5 - r
				var dy := (y + 0.5) * 1.15
				if dx * dx + dz * dz + (dy - 1.6) * (dy - 1.6) * 0.8 > r * r:
					continue
				var p := o + Vector3i(x, y, z)
				var rr := sqrt(dx * dx + dz * dz)
				var col: Color
				if rr < 1.6 and y >= 3:
					col = Color("b9e06a")
				elif Kit.h(p, 3 + s) > 0.55:
					col = Color("3b8a2a") if curly else LEAF2
				else:
					col = Color("2f7424") if curly else Color("5aa834")
				# frilly outer edge: drop some rim voxels
				if rr > 3.2 and Kit.h(p, 7 + s) < 0.3:
					continue
				vb.set_v(p, Kit.vary(Kit.shade(col, 0.82 + 0.05 * y), p, 0.07, s))


static func big_broccoli(vb: VoxelBuilder, o: Vector3i, s: int) -> void:
	for y in 3:
		vb.set_v(o + Vector3i(3, y, 3), Color("8fb85a"))
		vb.set_v(o + Vector3i(3, y, 2), Color("7aa64a"))
	# three florets clusters
	for c: Vector3i in [Vector3i(1, 3, 1), Vector3i(3, 4, 3), Vector3i(1, 3, 3), Vector3i(3, 3, 0), Vector3i(4, 3, 2)]:
		for x in 3:
			for y in 2:
				for z in 3:
					if (x == 0 or x == 2) and (z == 0 or z == 2) and y == 1:
						continue
					var p := o + c + Vector3i(x, y, z)
					var col := Color("2a6a26") if Kit.h(p, 6 + s) > 0.5 else Color("3f8f34")
					vb.set_v(p, Kit.vary(Kit.shade(col, 0.85 + 0.15 * y), p, 0.08, s))


## Carrot pointing toward +z (tip at the front), leafy tuft at the back.
static func big_carrot(vb: VoxelBuilder, o: Vector3i, s: int, ln := 11) -> void:
	for i in ln:
		var thick := 2 if i < ln - 3 else 1
		var p0 := o + Vector3i(0, 0, i)
		var cc := ORANGE if (i + s) % 3 != 0 else Color("e8740f")
		for x in thick:
			for y in thick:
				var p := p0 + Vector3i(x, y, 0)
				vb.set_v(p, Kit.vary(Kit.shade(cc, 0.9 + 0.12 * y), p, 0.05, s))
	# leafy top at the back: a fan of bright green
	for k in 5:
		var lp := o + Vector3i(k % 2 - (1 if k == 4 else 0) + (k / 3), 1 + k / 2, -1 - k / 2)
		vb.set_v(lp, LEAF2 if k % 2 == 0 else LEAF)
		vb.set_v(lp + Vector3i(0, 1, -1), Color("7cc84a") if k % 2 == 0 else LEAF)
	vb.set_v(o + Vector3i(0, 4, -3), LEAF2)
	vb.set_v(o + Vector3i(1, 3, -2), Color("7cc84a"))


## Curved banana bunch along +x: n fingers side by side (z), each 2 thick.
static func big_bananas(vb: VoxelBuilder, o: Vector3i, s: int, n := 4) -> void:
	var curve := [4, 3, 2, 1, 1, 0, 0, 0, 1, 1, 2, 3]
	for f in n:
		var lift := 1 if f == 1 or f == n - 2 else 0
		for i in curve.size():
			var p := o + Vector3i(i, curve[i] + lift, f * 3)
			var cc := YELLOW
			if i == 0:
				cc = Color("9aa53a")
			elif i == 1:
				cc = Color("d9cf3a")
			elif i == curve.size() - 1:
				cc = Color("4a3a1c")
			elif (i + f) % 4 == 0 and Kit.h(o + Vector3i(i, 0, f), s) > 0.6:
				cc = Color("e2b52a")
			vb.set_v(p, Kit.vary(Kit.shade(cc, 0.86), p, 0.04, s))
			vb.set_v(p + Vector3i(0, 1, 0), Kit.vary(Kit.shade(cc, 1.06), p, 0.04, s + 1))
			if i > 1 and i < curve.size() - 1:
				vb.set_v(p + Vector3i(0, 0, 1), Kit.vary(Kit.shade(cc, 0.95), p, 0.04, s + 2))
				vb.set_v(p + Vector3i(0, 1, 1), Kit.vary(Kit.shade(cc, 1.12), p, 0.04, s + 3))
	# crown stem joining the fingers
	for z in n * 3 - 1:
		vb.set_v(o + Vector3i(-1, 5, z), Color("6d7a2a"))
	vb.set_v(o + Vector3i(-2, 6, n), Color("5a4a22"))


static func big_grapes(vb: VoxelBuilder, o: Vector3i, s: int) -> void:
	for y in 6:
		var r := 3 - y / 2
		for x in range(-r, r + 1):
			for z in range(-1, 2):
				if Kit.h(o + Vector3i(x, y, z), 7 + s) < 0.15:
					continue
				var p := o + Vector3i(x + 3, 5 - y, z + 1)
				var cc := Color("6b2f7a") if (x + y + z) % 2 == 0 else Color("8a46a0")
				vb.set_v(p, Kit.vary(Kit.shade(cc, 0.85 + 0.04 * (5 - y)), p, 0.06, s))
	vb.set_v(o + Vector3i(3, 6, 1), STEM)
	vb.set_v(o + Vector3i(4, 6, 1), LEAF2)


## Stamp one chunky item; returns its pitch (x, layer height, z) in cells.
static func big_item(vb: VoxelBuilder, kind: String, o: Vector3i, s: int, rnd: float) -> Vector3i:
	match kind:
		"tomato":
			big_tomato(vb, o, s); return Vector3i(5, 4, 5)
		"apple":
			big_apple(vb, o, s, rnd < 0.1); return Vector3i(5, 4, 5)
		"green_apple":
			big_apple(vb, o, s, true); return Vector3i(5, 4, 5)
		"orange":
			big_orange(vb, o, s); return Vector3i(5, 4, 5)
		"lemon":
			big_orange(vb, o, s, true); return Vector3i(4, 3, 4)
		"pepper_red":
			big_pepper(vb, o, s, Color("d9261c")); return Vector3i(4, 4, 4)
		"pepper_mix":
			var cols := [Color("d9261c"), Color("f2c12e"), Color("3f9a2e"), Color("f07f1c")]
			big_pepper(vb, o, s, cols[int(rnd * 4.0) % 4]); return Vector3i(4, 4, 4)
		"lettuce":
			big_lettuce(vb, o, s); return Vector3i(7, 4, 7)
		"greens":
			if rnd < 0.5:
				big_lettuce(vb, o, s, true)
			else:
				big_broccoli(vb, o, s)
			return Vector3i(7, 4, 7)
		"broccoli":
			big_broccoli(vb, o, s); return Vector3i(6, 4, 6)
		"grapes":
			big_grapes(vb, o, s); return Vector3i(7, 5, 4)
		"eggplant":
			eggplant(vb, o + Vector3i(1, 0, 0)); return Vector3i(7, 2, 3)
		"carrot":
			big_carrot(vb, o + Vector3i(0, 0, 3), s); return Vector3i(3, 2, 14)
		"banana":
			big_bananas(vb, o + Vector3i(2, 0, 0), s); return Vector3i(13, 3, 12)
	big_tomato(vb, o, s)
	return Vector3i(5, 4, 5)


## Heap chunky items into a bin interior (cells, P grid). Layers are
## staggered by half a pitch and shrink towards a dome, so the pile rises
## well above the rim; the front row hangs over the front lip (+z).
static func heap2(vb: VoxelBuilder, kind: String, from: Vector3i, size: Vector3i, layers := 3, seed := 0) -> void:
	var probe := VoxelBuilder.new()
	var pitch := big_item(probe, kind, Vector3i.ZERO, 0, 0.0)
	var nx := maxi(1, size.x / pitch.x)
	var nz := maxi(1, size.z / pitch.z)
	if kind == "banana" or kind == "carrot":
		layers = mini(layers, 2)
	for L in layers + 1:
		var cnx := nx - (L % 2)
		var cnz := nz - (L % 2)
		if cnx < 1 or cnz < 1:
			cnx = maxi(1, cnx)
			cnz = maxi(1, cnz)
			if L > 1 and nx * nz <= 2:
				continue
		var ox := (size.x - cnx * pitch.x) / 2
		var oz := (size.z - cnz * pitch.z) / 2
		for ix in cnx:
			for iz in cnz:
				var u := ((float(ix) + 0.5) / cnx - 0.5) * 2.0
				var v := ((float(iz) + 0.5) / cnz - 0.5) * 2.0
				# dome: higher layers keep only the middle; the back stays a bit higher
				var reach := 1.0 - float(L) / (layers + 0.6)
				if L > 0 and (absf(u) > reach + 0.15 or v > reach + 0.35):
					continue
				var key := Vector3i(ix, L, iz + seed * 31)
				var r := Kit.h(key, 17 + seed)
				var jx := int(r * 3.0) - 1
				if kind == "banana" and L % 2 == 1:
					jx += 3
				var jz := int(Kit.h(key, 19) * 3.0) - 1
				var jy := 1 if Kit.h(key, 29) > 0.7 else 0
				var o := from + Vector3i(ox + ix * pitch.x + jx, L * pitch.y + jy, oz + iz * pitch.z + jz)
				big_item(vb, kind, o, seed + ix * 3 + iz * 7 + L, Kit.h(key, 23))
	# spill: a few items tumbling over the front lip
	if kind in ["tomato", "apple", "orange", "green_apple", "pepper_mix", "pepper_red", "lemon"]:
		for i in maxi(1, nx / 2):
			if Kit.h(Vector3i(i, seed, 5), 41) < 0.45:
				continue
			var sx := from.x + int(Kit.h(Vector3i(i, seed, 1), 43) * (size.x - pitch.x))
			big_item(vb, kind, Vector3i(sx, from.y - 1, from.z + size.z - pitch.z / 2), seed + 90 + i, 0.5)


## Heap chunky items on a sloped bin floor (all args in cells of the target
## grid, floats ok). The bin front edge is at z = zf and it runs back to
## zf - d (towards -z) while its floor rises from yf (front) to yb (back).
## Layer 0 covers the whole floor; upper layers are staggered by half a pitch
## and dome in the middle so the bin reads as overflowing; the front row
## hangs over the lip.
static func slope_heap(vb: VoxelBuilder, kind: String, x0: float, w: float, zf: float, d: float, yf: float, yb: float, seed := 0, layers := 2) -> void:
	var probe := VoxelBuilder.new()
	var pitch := big_item(probe, kind, Vector3i.ZERO, 0, 0.0)
	var px := pitch.x
	var pz := pitch.z
	# round items pack a little tighter than their size so no dark bin
	# floor shows between them
	if pitch.x <= 7 and kind != "grapes":
		px -= 1
		pz -= 1
	if kind == "carrot":
		px = 3
		pz = pitch.z
	var nx := maxi(1, int(w) / px)
	var nz := maxi(1, int(d) / pz)
	if kind == "banana" or kind == "carrot":
		layers = mini(layers, 2)
	# under-fill in the produce's own (shadowed) colour along the sloped floor
	var fill := Kit.shade(_fill_col(kind), 0.55)
	for zi in int(d):
		var fr := float(zi) / maxf(d, 1.0)
		var fy0 := int(round(yf + (yb - yf) * fr)) - 1
		for xi in range(1, int(w) - 1):
			vb.set_v(Vector3i(int(round(x0)) + xi, fy0, int(round(zf)) - 1 - zi), fill)
			vb.set_v(Vector3i(int(round(x0)) + xi, fy0 + 1, int(round(zf)) - 1 - zi), Kit.shade(fill, 1.15))
	for L in layers:
		var odd := L % 2
		var cnx := maxi(1, nx - odd)
		var cnz := maxi(1, nz - odd)
		var ox := (w - cnx * px) * 0.5 + odd * px * 0.5
		for iz in cnz:
			for ix in cnx:
				var u := ((float(ix) + 0.5) / cnx - 0.5) * 2.0
				if L >= 2 and absf(u) > 0.75 - 0.2 * (L - 2):
					continue
				var zc := zf - (float(iz) + 0.5 + odd * 0.5) * pz
				var frac := clampf((zf - zc) / maxf(d, 1.0), 0.0, 1.0)
				var fy := yf + (yb - yf) * frac
				var key := Vector3i(ix, L, iz + seed * 31)
				var jx := int(Kit.h(key, 17 + seed) * 3.0) - 1
				var jz := int(Kit.h(key, 19) * 3.0) - 1
				var jy := 1 if Kit.h(key, 29) > 0.7 else 0
				var o := Vector3i(int(round(x0 + ox + ix * px)) + jx, int(round(fy)) - 1 + L * pitch.y + jy,
					int(round(zc - pz * 0.5)) + jz + (1 if iz == 0 and L == 0 else 0))
				big_item(vb, kind, o, seed + ix * 3 + iz * 7 + L * 11, Kit.h(key, 23))


static func _fill_col(kind: String) -> Color:
	match kind:
		"tomato", "apple", "pepper_red": return Color("b52620")
		"orange", "carrot": return Color("d56a12")
		"lemon", "banana": return Color("d6b02c")
		"greens", "lettuce", "broccoli", "green_apple": return Color("2f6e26")
		"grapes", "eggplant": return Color("4b2463")
		"pepper_mix": return Color("8a3a1a")
	return Color("6a4a2a")
