extends RefCounted
## Hi-res beagle puppy for SimActor (round 15).
##
## Built at 0.035 m voxels (about 2 voxels per old 0.07 m "dog unit"), so the
## dog is ~1.4x larger than the r14 pup and its face gets real detail: a 4-wide
## white blaze, 3x3 glossy eyes with a catchlight, brows, a big black nose with
## a highlight, a smiling mouth and tongue, long dark drop ears. Pattern blocks
## stay flat and low-noise so the tri-colour reads at phone size.
## Bone names / meta keys match the old builder; meta.u is the old dog unit
## (metres) that SimActor's dog poses use for their offsets.

const DV := 0.035
const U := 0.07

static func sh(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1))


static func hh(p: Vector3i, s := 0) -> float:
	return VoxelBuilder.hash3(p + Vector3i(s * 131, s * 71, s * 37))


static func in_rbox(p: Vector3i, size: Vector3, n: float, fat := 0.0) -> bool:
	var h := size * 0.5
	var d := (Vector3(p) + Vector3(0.5, 0.5, 0.5) - h).abs()
	var a := h + Vector3(fat, fat, fat)
	return pow(d.x / a.x, n) + pow(d.y / a.y, n) + pow(d.z / a.z, n) <= 1.0


static func fill(vb: VoxelBuilder, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c) -> void:
	if x1 < x0 or y1 < y0 or z1 < z0:
		return
	vb.box(Vector3i(x0, y0, z0), Vector3i(x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1), c)


static func front_z(vb: VoxelBuilder, x: int, y: int, from_z: int) -> int:
	for z in range(from_z, -4, -1):
		if vb.has(Vector3i(x, y, z)):
			return z
	return -100


## `acc` is a sim_rig_builder Acc (vs must already be DV).
static func build(acc, L: Dictionary) -> Dictionary:
	var tan: Color = L.get("tan", Color(0.80, 0.47, 0.2))
	var saddle: Color = L.get("saddle", Color(0.42, 0.25, 0.13))
	var white: Color = L.get("white", Color(0.97, 0.95, 0.9))
	var earc: Color = L.get("ear", Color(0.6, 0.33, 0.14))
	var collar: Color = L.get("collar", Color(0.85, 0.18, 0.18))
	const LEG := 10
	const BW := 20
	const BH := 16
	const BL := 42
	const HW := 20
	const HH := 19
	const HD := 14
	const MZ := 6
	var head_j := Vector3(0, LEG + BH - 6, BL * 0.5 - 6.0)
	var h_origin := Vector3(HW * 0.5, 4.0, 2.0)
	var eye_d := Vector3(0, 6.0, HD - 3.0)
	acc.bone("root", "", Vector3.ZERO)
	acc.bone("body", "root", Vector3(0, LEG, 0))
	acc.bone("head", "body", head_j)
	acc.bone("eyes", "head", head_j + eye_d)
	var ear_d := Vector3(HW * 0.5 + 0.5, HH - 4.0 - h_origin.y, 5.0 - h_origin.z)
	acc.bone("ear_l", "head", head_j + ear_d)
	acc.bone("ear_r", "head", head_j + Vector3(-ear_d.x, ear_d.y, ear_d.z))
	acc.bone("tail", "body", Vector3(0, LEG + BH - 3, -BL * 0.5 + 2.0))
	acc.bone("leg_fl", "body", Vector3(5.0, LEG + 2, BL * 0.5 - 1.5))
	acc.bone("leg_fr", "body", Vector3(-5.0, LEG + 2, BL * 0.5 - 1.5))
	acc.bone("leg_bl", "body", Vector3(5.0, LEG + 2, -BL * 0.5 + 7.0))
	acc.bone("leg_br", "body", Vector3(-5.0, LEG + 2, -BL * 0.5 + 7.0))

	# ---- Body: x 0..BW-1, y 0..BH-1, z 0..BL-1 (front = +z).
	var body := VoxelBuilder.new()
	body.jitter = 0.008
	var cxm := (BW - 1) * 0.5
	var body_fn := func(p: Vector3i) -> Color:
		var c := tan
		var cx := absf(p.x - cxm)
		# Saddle: a dark blanket over the back and down the upper flanks,
		# its edge wandering in 5-voxel steps (a pattern, not a lid).
		var wob := int(hh(Vector3i(0, 0, p.z / 5), 30) * 3.0)
		var on_saddle := p.z >= 5 and p.z <= BL - 13 and p.y >= BH - 6 - wob + (2 if cx < 5.0 else 0)
		if p.y <= 2 or (p.z >= BL - 6 and p.y <= 10 and cx < 6.5):
			c = white
		elif (p.z == BL - 8 or p.z == BL - 7) and p.y >= 8:
			c = collar
		elif on_saddle:
			c = saddle
		return sh(c, 1.0 + (hh(p, 32) - 0.5) * 0.025)
	fill(body, 0, BW - 1, 0, BH - 1, 0, BL - 1, func(p: Vector3i) -> Color:
		if not in_rbox(p, Vector3(BW, BH, BL), 2.4, 0.9):
			return Color(0, 0, 0, 0)
		return body_fn.call(p))
	# Haunches: rounded tan thigh bumps on the flanks over the folded hind legs.
	for sx in [-1, BW]:
		fill(body, sx, sx, 2, 10, 2, 15, func(p: Vector3i) -> Color:
			if (p.y >= 9 or p.y <= 2) and (p.z <= 3 or p.z >= 14):
				return Color(0, 0, 0, 0)
			return sh(tan, 0.97 + (hh(p, 38) - 0.5) * 0.03))
	# Fluffy white chest bib under the chin + gold tag on the collar.
	fill(body, 6, BW - 7, 2, 10, BL, BL, func(p: Vector3i) -> Color:
		if (p.x == 6 or p.x == BW - 7) and p.y >= 9:
			return Color(0, 0, 0, 0)
		return sh(white, 0.99 + (hh(p, 39) - 0.5) * 0.02))
	fill(body, BW / 2 - 1, BW / 2, 7, 8, BL, BL + 1, Color(0.98, 0.82, 0.3))
	acc.part("body", body, Vector3(BW * 0.5, 0, BL * 0.5))

	# ---- Head: x 0..HW-1, y 0..HH-1, z 0..HD-1; muzzle in front (z >= HD).
	var head := VoxelBuilder.new()
	head.jitter = 0.006
	var hxm := (HW - 1) * 0.5   # 9.5: blaze columns 8..11
	var head_fn := func(p: Vector3i) -> Color:
		var ax := absf(float(p.x) - hxm)
		var c := tan
		if ax < 2.0 and p.y >= 6 and (p.z >= HD - 3 or p.y >= HH - 4):
			c = white   # blaze up the face and back over the crown
		elif ax < 3.0 and p.y >= 6 and p.y <= 9 and p.z >= HD - 2:
			c = white   # blaze flaring above the muzzle
		elif p.y <= 6 and p.z >= HD - 5 and ax < 7.0:
			c = white   # white cheeks / jaw around the muzzle
		elif p.y <= 1 and p.z >= 3:
			c = white
		elif p.y >= HH - 4 and ax >= 2.0:
			c = sh(tan, 0.88)  # crown a touch darker (no glare from above)
		elif p.z <= 2:
			c = sh(tan, 0.92)
		return sh(c, 1.0 + (hh(p, 33) - 0.5) * 0.02)
	fill(head, 0, HW - 1, 0, HH - 1, 0, HD - 1, func(p: Vector3i) -> Color:
		var fat := 0.9 if p.y < HH / 2 else 0.35
		if not in_rbox(p, Vector3(HW, HH, HD), 2.3, fat):
			return Color(0, 0, 0, 0)
		return head_fn.call(p))
	# Muzzle: white, 12 wide x 8 tall x MZ deep, rounded front edges.
	var fz := HD + MZ - 1
	fill(head, 4, HW - 5, 0, 7, HD, fz, func(p: Vector3i) -> Color:
		var q := Vector3i(p.x - 4, p.y, p.z - HD + 2)
		if not in_rbox(q, Vector3(HW - 8, 8, MZ + 2), 2.6, 0.5):
			return Color(0, 0, 0, 0)
		return sh(white, 1.0 - 0.015 * float(p.z - HD) + (hh(p, 34) - 0.5) * 0.02))
	fill(head, 6, HW - 7, 8, 8, HD, HD + 1, sh(white, 0.98))
	# Big glossy black nose on the top-front of the muzzle tip.
	var nose := Color(0.05, 0.035, 0.035)
	for x in range(7, HW - 7):
		for y in range(4, 8):
			if (x == 7 or x == HW - 8) and (y == 7 or y == 4):
				continue
			var z := front_z(head, x, y, fz + 1)
			if z < -50:
				continue
			head.set_v(Vector3i(x, y, z + (1 if y >= 5 else 0)), nose)
	head.set_v(Vector3i(8, 7, front_z(head, 8, 7, fz + 2)), Color(0.42, 0.4, 0.42))
	# Mouth: philtrum line down from the nose into a "w" smile, pink tongue.
	var lip := Color(0.22, 0.11, 0.1)
	for y in [2, 3]:
		for x in [9, 10]:
			var z := front_z(head, x, y, fz + 1)
			if z > -50:
				head.set_v(Vector3i(x, y, z), lip)
	for x in [6, 7, 8, 11, 12, 13]:
		var y := 2 if (x == 8 or x == 11 or x == 7 or x == 12) else 3
		var z := front_z(head, x, y, fz + 1)
		if z > -50:
			head.set_v(Vector3i(x, y, z), lip)
	for x in range(8, 12):
		for y in [0, 1]:
			var z := front_z(head, x, y, fz + 1)
			if z > -50:
				head.set_v(Vector3i(x, y, z + (1 if y == 0 else 0)), Color(0.93, 0.45, 0.52) if y == 1 else Color(0.86, 0.38, 0.45))
	# Eyes (own bone so they blink): 3x3 glossy black, a white catchlight top
	# left + a warm brown iris pixel bottom right; dark lid behind.
	var eyes := VoxelBuilder.new()
	eyes.jitter = 0.0
	var lid := Color(0.16, 0.09, 0.06)
	for ex: int in [3, HW - 6]:
		for dx in 3:
			for ey in [9, 10, 11]:
				var x := ex + dx
				if ey == 11 and dx != 1 and false:
					continue
				var z := front_z(head, x, ey, HD + 1)
				if z < -50:
					continue
				var p := Vector3i(x, ey, z)
				head.erase(p)
				head.set_v(p - Vector3i(0, 0, 1), lid if ey == 9 else sh(tan, 0.78))
				var c := Color(0.03, 0.02, 0.02)
				if ey == 11 and dx == 0:
					c = Color(1.0, 1.0, 0.98)
				elif ey == 9 and dx == 2:
					c = Color(0.32, 0.17, 0.08)
				eyes.set_v(p, c)
		# Brow tuft (darker tan) above each eye, the inner end raised.
		var inner := ex + 2 if ex < HW / 2 else ex
		var outer := ex if ex < HW / 2 else ex + 2
		for x in [ex, ex + 1, ex + 2]:
			var y := 14 if x == inner else 13
			var z := front_z(head, x, y, HD + 1)
			if z > -50:
				head.set_v(Vector3i(x, y, z), sh(tan, 0.66))
		var zo := front_z(head, outer, 13, HD + 1)
		if zo > -50:
			head.set_v(Vector3i(outer, 13, zo), sh(tan, 0.72))
	acc.part("head", head, h_origin)
	acc.part("eyes", eyes, h_origin + eye_d)

	# ---- Long floppy ears: 3 thick, ~9 deep, hanging from the crown corner
	# to below the jaw with a rounded tip; the lit top fold a little warmer.
	var ear := VoxelBuilder.new()
	ear.jitter = 0.006
	for y in range(-20, 3):
		var z0 := 0
		var z1 := 7
		if y <= -5:
			z0 = -1
			z1 = 8
		if y >= 1:
			z0 = 1
			z1 = 6
		if y <= -18:
			z0 = 1 + (-18 - y)
			z1 = 7 - (-18 - y)
		for z in range(z0, z1 + 1):
			for x in range(0, 3):
				if x == 2 and (y <= -14 or y >= 2):
					continue
				var c := earc
				if y >= 0:
					c = sh(earc, 1.14)
				elif y <= -16:
					c = sh(earc, 0.86)
				ear.set_v(Vector3i(x, y, z), sh(c, 1.0 + (hh(Vector3i(x, y / 2, z / 2), 36) - 0.5) * 0.04))
	acc.part("ear_l", ear, Vector3(0.5, 0.5, 4.0))
	var ear_r := VoxelBuilder.new()
	ear_r.jitter = 0.006
	for p: Vector3i in ear.vox:
		ear_r.set_v(Vector3i(2 - p.x, p.y, p.z), ear.vox[p])
	acc.part("ear_r", ear_r, Vector3(2.5, 0.5, 4.0))

	# ---- Tail: saddle base, tan shaft sweeping up and hooking forward, a
	# white tip.
	var tail := VoxelBuilder.new()
	tail.jitter = 0.006
	for y in range(0, 20):
		var c := white if y >= 14 else (saddle if y < 6 else tan)
		var zz := int(round(pow(y / 19.0, 1.6) * 11.0))
		var w := 3 if y < 16 else 2
		var x0 := 0 if w == 3 else 1
		fill(tail, x0, x0 + w - 1, y, y, zz, zz + 2, sh(c, 1.0 + (hh(Vector3i(0, y / 2, 0), 39) - 0.5) * 0.04))
	acc.part("tail", tail, Vector3(1.5, 0, 1.5))

	# ---- Legs: 5 x (LEG+3) x 5. Front legs white (they stretch forward as
	# paws), hind legs tan with white feet; a toe row on the front.
	for nm in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
		var leg := VoxelBuilder.new()
		leg.jitter = 0.006
		var front: bool = nm.begins_with("leg_f")
		fill(leg, 0, 4, 0, LEG + 2, 0, 4, func(p: Vector3i) -> Color:
			if (p.x == 0 or p.x == 4) and (p.z == 0 or p.z == 4):
				return Color(0, 0, 0, 0)
			var c := white
			if not front and p.y >= 3:
				c = tan
			elif front and p.y >= LEG:
				c = white.lerp(tan, 0.3)
			return sh(c, 1.0 + (hh(p, 37) - 0.5) * 0.03))
		fill(leg, 0, 4, 0, 1, 5, 5, sh(white, 0.97))
		for x in [1, 3]:
			leg.set_v(Vector3i(x, 1, 5), sh(white, 0.82))
		acc.part(nm, leg, Vector3(2.5, LEG + 2.5, 2.5))

	return {
		"species": "dog", "kind": "dog", "u": U,
		"height": (LEG + BH - 6 - 4 + HH) * DV,
		"head_h": (HH - 4) * DV,
		"leg": LEG * DV,
		"mouth": Vector3(0, 2.0 - h_origin.y, fz - h_origin.z) * DV,
		"paws": Vector3(0, 1.4, BL * 0.5 + 13.0) * DV,
		"paws_root": Vector3(0, 2.0, BL * 0.5 + 14.0) * DV,
	}
