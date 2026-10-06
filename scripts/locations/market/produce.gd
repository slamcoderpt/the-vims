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
	_ball(vb, o, col, 1, LEAF, LEAF2)


static func apple(vb: VoxelBuilder, o: Vector3i, green := false) -> void:
	var col := Color("cf2a2a") if not green else Color("8cc63f")
	_ball(vb, o, col, 2, STEM)
	if not green:
		vb.set_v(o + Vector3i(0, 1, 1), Color("f0a33a"))


static func orange(vb: VoxelBuilder, o: Vector3i) -> void:
	_ball(vb, o, ORANGE, 3, LEAF)


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
			tomato(vb, o); return Vector3i(3, 3, 3)
		"apple":
			apple(vb, o, rnd < 0.12); return Vector3i(3, 3, 3)
		"green_apple":
			apple(vb, o, true); return Vector3i(3, 3, 3)
		"orange":
			orange(vb, o); return Vector3i(3, 3, 3)
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
			bananas(vb, o); return Vector3i(8, 4, 4)
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
		step = Vector3i(9, 2, 2)
	elif kind == "banana":
		step = Vector3i(8, 3, 4)
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
	for L in layers:
		var off := L % 2
		for ix in range(0, size.x - off - 1, 2):
			for iz in range(0, size.z - off - 1, 2):
				var u := (float(ix) + 1.0) / size.x - 0.5
				if L > 0 and absf(u) > 0.42 - 0.1 * L:
					continue
				var o := from + Vector3i(ix + off, L * 2, iz + off)
				var r := Kit.h(o, 31 + seed)
				var col := _mini_col(kind, r)
				for dx in 2:
					for dy in 2:
						for dz in 2:
							var p := o + Vector3i(dx, dy, dz)
							vb.set_v(p, Kit.vary(col if dy == 1 else Kit.shade(col, 0.88), p, 0.06, 5))
				if kind in ["tomato", "pepper_red", "pepper_mix", "orange", "carrot"] and r > 0.4:
					vb.set_v(o + Vector3i(int(r * 7.0) % 2, 2, 1), LEAF)


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
