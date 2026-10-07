extends RefCounted
## Hi-res voxel heads for SimActor (round 15).
##
## Heads are modelled at 1/32 m voxels (twice the 1/16 m world grid and 1.6x
## finer than the 0.05 m body voxels), so a face gets ~16 cells across: eyes
## become a white sclera + 2x2 pupil with a catchlight, brows, a proud nose,
## a mouth and blush all as separate flat, low-noise colour blocks that stay
## readable at phone size (critics r12-r14: faces turned to mush).
##
## Head local coords (head voxels): x 0..W-1, z 0..F (+z = face), rows 0..1
## are the neck, the skull spans rows B..T. Facial features are painted onto
## whatever voxel is frontmost in their column.

const HVS := 0.03125
const B := 2

## Skull size per body type (W, H rows, D).
const DIMS := {"adult": Vector3i(16, 16, 16), "child": Vector3i(20, 18, 18)}


class Ctx:
	var L: Dictionary
	var vb: VoxelBuilder
	var eyes: VoxelBuilder
	var W := 16
	var H := 16
	var D := 16
	var T := 17
	var F := 15
	var child := false
	var girl := false
	var man := false
	var skin := Color.WHITE
	var hair := Color.BLACK
	var E := 8        # bottom eye row
	var eh := 2       # pupil rows
	var ew := 2       # pupil width
	var exs: Array[int] = []   # first pupil column of each eye
	var sclera := true
	var M := 4        # mouth row
	var N := 6        # nose (tip) row
	var BR := 11      # brow row
	var C := 13       # hat cuff row (first hat row)
	var skull := {}
	var hat := ""


static func sh(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1))


static func hh(p: Vector3i, s := 0) -> float:
	return VoxelBuilder.hash3(p + Vector3i(s * 131, s * 71, s * 37))


static func in_skull(c: Ctx, x: int, y: int, z: int, grow := 0.0, top_grow := 0.0, crown := 0.3) -> bool:
	if y < B or y > c.T + ceili(top_grow) or z < -ceili(grow) or z > c.F + ceili(grow):
		return false
	if x < -ceili(grow) or x >= c.W + ceili(grow):
		return false
	var dx := absf(x - (c.W - 1) * 0.5) / (c.W * 0.5 + 0.1 + grow)
	var dz := absf(z - c.F * 0.5) / ((c.F + 1) * 0.5 + 0.35 + grow)
	var top := float(c.T) + top_grow
	var top0 := top - c.H * crown
	var bot0 := float(B) + c.H * (0.24 if c.child else 0.17)
	var dy := 0.0
	if y > top0:
		dy = (y - top0) / (top + 0.7 - top0)
	elif y < bot0:
		dy = (bot0 - y) / (bot0 - B + 0.8)
	return pow(dx, 3.2) + pow(dz, 3.2) + pow(dy, 2.4) <= 1.0


static func front_z(vb: VoxelBuilder, x: int, y: int, from_z: int) -> int:
	for z in range(from_z, -6, -1):
		if vb.has(Vector3i(x, y, z)):
			return z
	return -100


static func paint(c: Ctx, x: int, y: int, col: Color, proud := 0) -> void:
	var z := front_z(c.vb, x, y, c.F + 4)
	if z < -50:
		return
	if proud > 0:
		for k in proud:
			c.vb.set_v(Vector3i(x, y, z + 1 + k), col)
	else:
		c.vb.set_v(Vector3i(x, y, z), col)


## Builds the head. Returns {head, eyes, ear (VoxelBuilder or null),
## ear_origin, ear_pos (head voxels, left ear), W, D, top (highest row)}.
static func build(L: Dictionary) -> Dictionary:
	var c := Ctx.new()
	c.L = L
	c.child = L.get("body", "") == "child"
	c.girl = L.get("lashes", false)
	c.man = not c.child and not c.girl
	var dim: Vector3i = DIMS["child" if c.child else "adult"]
	c.W = dim.x
	c.H = dim.y
	c.D = dim.z
	c.T = B + c.H - 1
	c.F = c.D - 1
	c.skin = L.skin
	c.hair = L.get("hair", Color(0.3, 0.2, 0.1))
	c.hat = L.get("hat", "")
	c.vb = VoxelBuilder.new()
	c.vb.jitter = 0.008
	c.eyes = VoxelBuilder.new()
	c.eyes.jitter = 0.0
	if c.child:
		c.M = B + 3
		c.N = B + 4
		c.E = B + 5
		c.eh = 4
		c.ew = 3
		c.exs = [5, c.W - 8]
		c.sclera = false
		c.BR = c.E + c.eh + 1
		c.C = c.BR + 1
	else:
		c.M = B + 2
		c.N = B + 4
		c.E = B + 6
		c.eh = 3 if c.girl else 2
		c.ew = 2
		c.exs = [4, c.W - 6]
		c.sclera = true
		c.BR = c.E + c.eh + 1
		c.C = c.BR + 2

	_skull(c)
	_ears(c)
	_face(c)
	var beard: String = L.get("beard", "")
	if beard != "":
		_beard(c, beard)
	_hair(c)
	var out := {"head": c.vb, "eyes": c.eyes, "W": c.W, "D": c.D, "H": c.H, "B": B}
	if c.hat != "":
		_hat(c, out)
	if L.get("glasses", false):
		_glasses(c)
	var top := 0
	for p: Vector3i in c.vb.vox:
		top = maxi(top, p.y)
	out["top"] = top
	return out


# ---------------------------------------------------------------------------

static func _skull(c: Ctx) -> void:
	var skin := c.skin
	for x in range(0, c.W):
		for y in range(B, c.T + 1):
			for z in range(0, c.F + 1):
				if in_skull(c, x, y, z):
					var f := 1.0 + (hh(Vector3i(x, y, z), 2) - 0.5) * 0.015
					# Jaw and the underside of the chin a touch deeper.
					if y <= B:
						f *= 0.94
					c.vb.set_v(Vector3i(x, y, z), sh(skin, f))
					c.skull[Vector3i(x, y, z)] = true
	# Neck (two rows under the skull), a little shaded.
	var cx := c.W / 2
	for x in range(cx - 3, cx + 3):
		for y in range(0, B):
			for z in range(c.F / 2 - 3, c.F / 2 + 3):
				c.vb.set_v(Vector3i(x, y, z), sh(skin, 0.82))


static func _ears(c: Ctx) -> void:
	var ez := c.F / 2 - 1
	var col := sh(c.skin, 0.9)
	for x in [-1, c.W]:
		for y in range(c.E - 1, c.E + 2):
			for z in range(ez - 1, ez + 2):
				if (y == c.E + 1 or y == c.E - 1) and z == ez - 1:
					continue
				c.vb.set_v(Vector3i(x, y, z), col)
		c.vb.set_v(Vector3i(x, c.E, ez + 1), sh(c.skin, 0.8))


static func _face(c: Ctx) -> void:
	var L := c.L
	var skin := c.skin
	var vb := c.vb
	var cxl := c.W / 2 - 1
	var cxr := c.W / 2
	var dark := Color(0.08, 0.05, 0.05)
	var iris: Color = L.get("eye", Color(0.33, 0.19, 0.1))
	var white := Color(1.0, 1.0, 0.98)
	var lash := Color(0.13, 0.07, 0.05)
	var lid := sh(skin, 0.84)
	var brow: Color = L.get("brow", sh(c.hair, 0.72))
	if L.get("elderly", false) and not L.has("brow"):
		brow = sh(c.hair, 0.8)
	# ---- Eyes: pupil block on the "eyes" bone (blinks), lid behind it.
	for ei in 2:
		var ex: int = c.exs[ei]
		var outer_dx := 0 if ei == 0 else c.ew - 1
		var inner_dx := c.ew - 1 - outer_dx
		for dx in c.ew:
			for dy in c.eh:
				var x := ex + dx
				var y := c.E + dy
				# Kids: rounded eye (top corners stay skin; girls get a dark
				# outer top corner as a lash flick).
				var z := front_z(vb, x, y, c.F + 2)
				if z < -50:
					continue
				var p := Vector3i(x, y, z)
				vb.erase(p)
				vb.set_v(p - Vector3i(0, 0, 1), lash if dy == c.eh - 1 else lid)
				var col := dark
				if c.child:
					# Big glossy kid eyes: a 1x2 catchlight high on the same
					# side of both eyes, warm iris at the bottom, dark lid line.
					if dx == 0 and (dy == c.eh - 2 or dy == c.eh - 3):
						col = white if dy == c.eh - 2 else Color(0.85, 0.85, 0.9)
					elif dy == 0 and dx >= 1:
						col = iris.lerp(dark, 0.15)
					elif dy == c.eh - 1:
						col = lash
				else:
					var hl_row := c.eh - 2 if c.girl else c.eh - 1
					if dx == inner_dx and dy == hl_row:
						col = white
					elif c.girl and dy == c.eh - 1:
						col = lash
					elif dy == 0:
						col = iris.lerp(dark, 0.35)
				c.eyes.set_v(p, col)
		# Sclera: one white column on the outer side (adults).
		if c.sclera:
			var sx := ex - 1 if ei == 0 else ex + c.ew
			for dy in mini(c.eh, 2):
				var y := c.E + dy
				var z := front_z(vb, sx, y, c.F + 2)
				if z < -50:
					continue
				var p := Vector3i(sx, y, z)
				vb.erase(p)
				vb.set_v(p - Vector3i(0, 0, 1), lid)
				c.eyes.set_v(p, Color(0.97, 0.95, 0.92))
		# Upper lash line (girls/women): over the eye + a flick outward.
		if c.girl:
			var fx := ex - 1 if ei == 0 else ex + c.ew
			if c.sclera:
				fx = ex - 2 if ei == 0 else ex + c.ew + 1
				var sx2 := ex - 1 if ei == 0 else ex + c.ew
				paint(c, sx2, c.E + c.eh - 1, lash)
			paint(c, fx, c.E + c.eh - 1, lash)
		elif c.man:
			# Upper lid crease over the eye.
			for dx in range(-1, c.ew + 1):
				var x := ex + dx
				if ei == 1 and dx == -1:
					continue
				if ei == 0 and dx == c.ew:
					continue
				paint(c, x, c.E + c.eh, sh(skin, 0.86))
	# ---- Brows.
	for ei in 2:
		var ex: int = c.exs[ei]
		if c.man:
			var x0 := ex - 2 if ei == 0 else ex
			for x in range(x0, x0 + 4):
				paint(c, x, c.BR, brow)
			# Inner half raised a voxel proud: brows cast a little shadow.
			var xi := ex if ei == 0 else ex
			paint(c, xi + (1 if ei == 0 else 0), c.BR, sh(brow, 1.08), 1)
		elif c.child:
			# Short soft brows (hair colour) over the eye centre.
			var bx := ex if ei == 0 else ex + 1
			paint(c, bx, c.BR, c.hair.lerp(brow, 0.5))
			paint(c, bx + 1, c.BR, c.hair.lerp(brow, 0.5))
		else:
			# Thin arched brows: outer end one row lower.
			var x0 := ex - 1 if ei == 0 else ex
			var bc := c.hair.lerp(brow, 0.6)
			for x in range(x0, x0 + 3):
				var outer := (ei == 0 and x == x0) or (ei == 1 and x == x0 + 2)
				paint(c, x, c.BR - (1 if outer else 0), bc)
	# ---- Blush.
	var blush := skin.lerp(Color(0.98, 0.42, 0.45), 0.42 if c.child else (0.3 if c.girl else 0.18))
	if c.child:
		for x in [c.exs[0] - 1, c.exs[0], c.exs[1] + 2, c.exs[1] + 3]:
			paint(c, x, c.N, blush)
			paint(c, x, c.N - 1, skin.lerp(blush, 0.5))
	elif c.girl:
		for x in [c.exs[0] - 1, c.exs[0], c.exs[1] + 1, c.exs[1] + 2]:
			paint(c, x, c.E - 1, blush)
	elif c.L.get("beard", "") == "":
		for x in [c.exs[0] - 1, c.exs[1] + 2]:
			paint(c, x, c.E - 1, blush)
	# ---- Nose.
	if c.child:
		var nc := skin.lerp(Color(0.85, 0.45, 0.4), 0.2)
		paint(c, cxl, c.N, nc, 1)
		paint(c, cxr, c.N, sh(nc, 0.95), 1)
	else:
		var nc := skin.lerp(Color(0.86, 0.46, 0.40), 0.18)
		# Bridge (row N+1) and a tip (row N) that stands two voxels proud on
		# men so it catches light and drops a small shadow.
		paint(c, cxl, c.N + 1, sh(nc, 1.02), 1)
		paint(c, cxr, c.N + 1, sh(nc, 0.97), 1)
		paint(c, cxl, c.N, sh(nc, 1.0), 2 if c.man else 1)
		paint(c, cxr, c.N, sh(nc, 0.94), 2 if c.man else 1)
	# ---- Mouth.
	if c.L.get("beard", "") == "full":
		return  # drawn inside the beard
	var mdark := Color(0.32, 0.11, 0.1)
	if c.child:
		# A small smile right under the nose: corners tucked up, a warm open
		# centre (no dark marks low on the chin that read as stubble).
		paint(c, cxl - 1, c.M, sh(mdark, 1.2))
		paint(c, cxr + 1, c.M, sh(mdark, 1.2))
		paint(c, cxl, c.M - 1, Color(0.66, 0.22, 0.22))
		paint(c, cxr, c.M - 1, Color(0.66, 0.22, 0.22))
	elif c.girl:
		var lip := Color(0.78, 0.3, 0.33)
		paint(c, cxl, c.M, lip)
		paint(c, cxr, c.M, lip)
		paint(c, cxl - 1, c.M + 1, sh(lip, 0.8))
		paint(c, cxr + 1, c.M + 1, sh(lip, 0.8))
		paint(c, cxl, c.M - 1, skin.lerp(lip, 0.35))
		paint(c, cxr, c.M - 1, skin.lerp(lip, 0.35))
	else:
		paint(c, cxl, c.M, mdark)
		paint(c, cxr, c.M, mdark)
		paint(c, cxl - 1, c.M + 1, sh(mdark, 1.3))
		paint(c, cxr + 1, c.M + 1, sh(mdark, 1.3))
		paint(c, cxl, c.M - 1, sh(skin, 0.9))
		paint(c, cxr, c.M - 1, sh(skin, 0.9))


static func _beard(c: Ctx, beard: String) -> void:
	var vb := c.vb
	var hair := c.hair
	var bc: Color = c.L.get("beard_color", sh(hair, 0.85))
	var cxl := c.W / 2 - 1
	var cxr := c.W / 2
	var W := c.W
	var F := c.F
	var bcell := func(p: Vector3i) -> Color:
		# Curly clumps: flat colour per 2x2 cell, lit on the clump tops.
		var cell := Vector3i(floori(p.x / 2.0), floori(p.y / 2.0), floori(p.z / 2.0))
		var f := 0.95 + 0.08 * hh(cell, 61) + (0.04 if posmod(p.y, 2) == 1 else -0.03)
		return sh(bc, f)
	if beard == "moustache":
		var mc := sh(bc, 1.0)
		for x in range(cxl - 3, cxr + 4):
			paint(c, x, c.M + 1, mc, 1)
		paint(c, cxl - 3, c.M, mc, 1)
		paint(c, cxr + 3, c.M, mc, 1)
		return
	var full := beard == "full"
	var zb := F - 7 if full else F - 6
	var bset := {}
	for p: Vector3i in c.skull:
		if p.z < zb:
			continue
		var side := p.x <= 2 or p.x >= W - 3
		var inb := false
		if p.y <= c.M + 1:
			inb = true
		elif p.y == c.M + 2 and (p.x <= cxl - 3 or p.x >= cxr + 3):
			inb = true
		elif side and p.y <= c.N + 1:
			inb = true
		elif (p.x <= 1 or p.x >= W - 2) and p.y <= c.E + 1 and p.z <= F - 3:
			inb = true   # sideburns up to the hair
		if inb:
			bset[p] = true
	for p: Vector3i in bset:
		vb.set_v(p, bcell.call(p))
	if full:
		# Volume: one voxel outward on the jaw/chin (front + sides) and two
		# on the chin, so it reads as a big soft beard mass.
		for p: Vector3i in bset:
			if p.y > c.M + 1:
				if p.x <= 1 or p.x >= W - 2:
					var q := p + Vector3i(-1 if p.x <= 1 else 1, 0, 0)
					if not vb.has(q):
						vb.set_v(q, bcell.call(q))
				continue
			for d: Vector3i in [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
				var q: Vector3i = p + d
				if vb.has(q):
					continue
				if d.z == 0 and p.z > F - 2:
					continue
				vb.set_v(q, bcell.call(q))
		# Chin mass hanging below the jaw.
		for x in range(2, W - 2):
			for z in range(F - 7, F + 2):
				var edge := (x == 2 or x == W - 3) and (z == F + 1)
				if edge:
					continue
				for y in range(0, B):
					if y == 0 and (x <= 3 or x >= W - 4 or z == F + 1):
						continue
					vb.set_v(Vector3i(x, y, z), bcell.call(Vector3i(x, y, z)))
		for x in range(cxl - 2, cxr + 3):
			for z in range(F - 4, F + 1):
				if (x == cxl - 2 or x == cxr + 2) and z == F:
					continue
				vb.set_v(Vector3i(x, -1, z), bcell.call(Vector3i(x, -1, z)))
		# Mouth: a warm smile showing through: teeth, dark corners, lip.
		var fz := c.F + 3
		for x in [cxl, cxr]:
			paint(c, x, c.M, Color(0.36, 0.12, 0.11))
		for x in [cxl - 1, cxr + 1]:
			paint(c, x, c.M, Color(0.3, 0.1, 0.09))
		# Moustache: lighter (sun-caught) band across the upper lip, ends
		# curling down past the mouth corners.
		var mus := sh(bc.lerp(hair, 0.5), 1.12)
		var mz := front_z(vb, cxl, c.M + 1, fz)
		for x in range(cxl - 3, cxr + 4):
			var z := maxi(mz, front_z(vb, x, c.M + 1, fz))
			vb.set_v(Vector3i(x, c.M + 1, z), sh(mus, 0.96 + 0.08 * hh(Vector3i(x, 0, 0), 63)))
		vb.set_v(Vector3i(cxl - 3, c.M, mz), sh(mus, 0.9))
		vb.set_v(Vector3i(cxr + 3, c.M, mz), sh(mus, 0.9))
	else:
		_fill(vb, 3, W - 4, B - 1, B - 1, F - 6, F, bcell)
		for x in [cxl, cxr]:
			paint(c, x, c.M, Color(0.4, 0.14, 0.13))
		for x in range(cxl - 2, cxr + 3):
			paint(c, x, c.M + 1, sh(bc, 0.9), 1)


static func _fill(vb: VoxelBuilder, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, col) -> void:
	if x1 < x0 or y1 < y0 or z1 < z0:
		return
	vb.box(Vector3i(x0, y0, z0), Vector3i(x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1), col)


# ---------------------------------------------------------------------------
# Hair

static func _hair_col(base: Color) -> Callable:
	return func(p: Vector3i) -> Color:
		var strand := hh(Vector3i(p.x * 2 + p.z, 0, p.z * 3 - p.x), 5)
		return sh(base, 0.92 + 0.12 * strand + 0.03 * hh(p, 9))


## Grows a shell of thickness `r` around the skull in the cells where
## `region(q)` is true; the skull surface inside the region is recoloured too.
static func _shell(c: Ctx, r: float, region: Callable, col: Callable, bump := 0.0) -> Dictionary:
	var added := {}
	var ri := ceili(r + 1.0)
	for p: Vector3i in c.skull:
		# Only surface skull voxels seed the shell.
		var surf := false
		for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not c.skull.has(p + d):
				surf = true
				break
		if not surf:
			continue
		if region.call(p):
			c.vb.set_v(p, sh(col.call(p), 0.85))
		for ox in range(-ri, ri + 1):
			for oy in range(0, ri + 1):
				for oz in range(-ri, ri + 1):
					var q := p + Vector3i(ox, oy, oz)
					if c.skull.has(q) or added.has(q):
						continue
					var ln := Vector3(ox, oy, oz).length()
					if ln > r + bump + 0.35:
						continue
					if ln > r + 0.35:
						# Extra curl volume only on the crown and upper sides.
						if bump <= 0.0 or q.y < c.T - 4:
							continue
						if ln > r + 0.35 + bump * hh(Vector3i(q.x / 2, q.y / 2, q.z / 2), 71):
							continue
					if not region.call(q):
						continue
					added[q] = true
	for q: Vector3i in added:
		c.vb.set_v(q, col.call(q))
	return added


static func _hair(c: Ctx) -> void:
	var style: String = c.L.get("hair_style", "short")
	var W := c.W
	var F := c.F
	var T := c.T
	var hcol := _hair_col(c.hair)
	var has_hat := c.hat != ""
	var ear_top := c.E + 2
	if style == "bald":
		var ring := func(q: Vector3i) -> bool:
			return q.y >= c.E - 1 and q.y <= c.E + 3 and q.z <= F / 2 and (q.x <= 1 or q.x >= W - 2 or q.z <= 1)
		_shell(c, 1.0, ring, hcol)
		return
	var hl := T - 3       # front hairline (forehead rows below stay skin)
	var nape := B + 3
	var r := 1.0
	var bump := 0.0
	var long := style == "long" or style == "curly_long"
	match style:
		"shaggy":
			r = 1.1
			bump = 0.75
			hl = c.BR + 3
		"curly":
			r = 1.2
			bump = 1.0
			hl = T - 2
		"afro":
			r = 2.6
			bump = 1.2
			hl = T - 2
		"messy", "short":
			hl = T - 2
		"bun", "ponytail":
			hl = T - 2
			nape = B + 1
		_:
			if long:
				nape = B
	if has_hat:
		hl = mini(hl, c.C)
	var region := func(q: Vector3i) -> bool:
		var zf := float(q.z) / float(F)
		if q.y >= hl:
			return true
		var side := q.x <= 0 or q.x >= W - 1
		if zf < 0.32:
			return q.y >= nape
		if side and zf < 0.72:
			return q.y >= (B + 3 if long else ear_top)
		return false
	var curl := hcol
	if style == "shaggy" or style == "curly" or style == "afro":
		var base := c.hair
		curl = func(p: Vector3i) -> Color:
			# Curls: flat shade per 2x2 clump, lit on the clump tops.
			var cell := Vector3i(floori((p.x + 8) / 2.0), floori(p.y / 2.0), floori((p.z + 8) / 2.0))
			var f := 0.9 + 0.14 * hh(cell, 54) + (0.08 if posmod(p.y, 2) == 1 else -0.02)
			return sh(base, f)
	var shell := _shell(c, r, region, curl, bump)
	var vb := c.vb
	match style:
		"shaggy":
			# Fringe: chunky locks dipping onto the forehead, swept to one side.
			for x in range(1, W - 1):
				var drop := 1 + int(hh(Vector3i(x, 0, 3), 55) * 2.0)
				if x < W / 2 - 2:
					drop += 1
				for k in drop:
					var y := hl - 1 - k
					if y <= c.BR:
						break
					var z := front_z(vb, x, y, F + 4)
					if z > -50:
						vb.set_v(Vector3i(x, y, z + 1), curl.call(Vector3i(x, y, z + 1)))
			# Volume on the crown: a couple of tufts.
			for p: Vector3i in shell.keys():
				if p.y >= T + 1 and hh(p, 57) > 0.82:
					vb.set_v(p + Vector3i(0, 1, 0), curl.call(p + Vector3i(0, 1, 0)))
		"short", "messy":
			for x in range(1, W - 1):
				var z := front_z(vb, x, hl - 1, F + 4)
				if style == "messy" and hh(Vector3i(x, 3, 1), 11) < 0.35:
					continue
				if z > -50:
					vb.set_v(Vector3i(x, hl - 1, z + 1), hcol.call(Vector3i(x, hl - 1, z + 1)))
			if style == "messy":
				for p: Vector3i in shell.keys():
					if p.y >= T + 1 and hh(p, 13) > 0.7:
						vb.set_v(p + Vector3i(0, 1, 0), hcol.call(p))
						if hh(p, 14) > 0.6:
							vb.set_v(p + Vector3i(0, 2, 0), hcol.call(p))
		"long", "curly_long", "bun", "ponytail":
			if long:
				_long_hair(c, hcol, style == "curly_long")
			if not has_hat:
				# Bangs: a soft fringe across the forehead, longer at the sides.
				for x in range(0, W):
					var drop := 1 + int(hh(Vector3i(x, 0, 0), 16) * 2.0)
					if x <= 1 or x >= W - 2:
						drop += 2
					for k in drop:
						var y := hl - 1 - k
						if y <= c.BR:
							break
						var z := front_z(vb, x, y, F + 4)
						if z > -50:
							vb.set_v(Vector3i(x, y, z + 1), hcol.call(Vector3i(x, y, z)))
			if style == "bun":
				var cx := W / 2
				for x in range(cx - 3, cx + 3):
					for y in range(T + 1, T + 6):
						for z in range(2, 8):
							var d := Vector3(x - cx + 0.5, y - T - 3.0, z - 4.5)
							if d.length() <= 3.0:
								vb.set_v(Vector3i(x, y, z), hcol.call(Vector3i(x, y, z)))
			elif style == "ponytail":
				var cx := W / 2
				_fill(vb, cx - 2, cx + 1, B - 4, T - 3, -3, -2, hcol)
				_fill(vb, cx - 2, cx + 1, T - 4, T - 3, -1, -1, Color(0.85, 0.2, 0.3))


## Long hair: side curtains framing the face, a back panel falling past the
## neck onto the upper back in wavy locks with ragged ends.
static func _long_hair(c: Ctx, hcol: Callable, curly: bool) -> void:
	var vb := c.vb
	var W := c.W
	var F := c.F
	var T := c.T
	var low := -10 if c.child else -12
	var lock := func(p: Vector3i) -> Color:
		var side := p.x < 0 or p.x >= W
		var u := p.z if side else p.x
		var wave := int(floor(sin(p.y * (1.1 if curly else 0.7)) * 1.3))
		var dk := posmod(u + wave, 4) == 0
		var lt := posmod(u + wave, 4) == 2
		var f := 0.9 if dk else (1.05 if lt else 1.0)
		if p.y < B:
			f *= 0.95
		return sh(hcol.call(p), f)
	var top := c.C if c.hat != "" else T - 3
	# Side curtains (outside the skull), 2 thick, from the temples down past
	# the jaw; the front edge frames the cheeks.
	for side in [-1, 1]:
		for t in 2:
			var x := (-1 - t) if side < 0 else (W + t)
			for z in range(-1, F + 1 - t):
				var zf := float(z) / F
				var y0 := low + 2 if zf < 0.5 else (B - 2 + int(zf * 3.0))
				if t == 1 and zf > 0.75:
					continue
				for y in range(y0, top + 1):
					vb.set_v(Vector3i(x, y, z), lock.call(Vector3i(x, y, z)))
					if t == 1 and y < top - 1 and zf < 0.6:
						var wv := int(floor(sin(y * (1.1 if curly else 0.6)) * 1.4))
						if posmod(z + wv, 3) == 0:
							var xo := x - 1 if side < 0 else x + 1
							vb.set_v(Vector3i(xo, y, z), sh(lock.call(Vector3i(xo, y, z)), 1.06))
	# Back panel: two voxels thick behind the skull, falling below the head.
	var cx := (W - 1) * 0.5
	for x in range(-2, W + 2):
		var lk := int(floor((x + 2) / 3.0))
		var taper := int(absf(x - cx) * 0.35)
		var end := low + taper + int(hh(Vector3i(lk, 0, 0), 15) * 3.0) + (1 if posmod(x + 2, 3) == 0 else 0)
		for y in range(end, top + 1):
			for z in range(-2, 0):
				if (x == -2 or x == W + 1) and z == -2:
					continue
				vb.set_v(Vector3i(x, y, z), lock.call(Vector3i(x, y, z)))
			# Wavy relief: every third column (drifting with height) stands a
			# voxel proud, so the hair reads as locks rather than a panel.
			var wv := int(floor(sin(y * (1.1 if curly else 0.6)) * 1.4))
			if posmod(x + wv, 3) == 0 and y < top - 1 and y > end and x > -2 and x < W + 1:
				vb.set_v(Vector3i(x, y, -3), sh(lock.call(Vector3i(x, y, -3)), 1.06))
		# Under the skull: hair hangs behind the neck.
		if x >= -1 and x <= W:
			for y in range(end + 1, B + 3):
				for z in range(0, 5):
					if not vb.has(Vector3i(x, y, z)) or y < B:
						vb.set_v(Vector3i(x, y, z), lock.call(Vector3i(x, y, z)))


# ---------------------------------------------------------------------------
# Hats

static func _hat(c: Ctx, out: Dictionary) -> void:
	var L := c.L
	var hat := c.hat
	var hc: Color = L.get("hat_color", Color(0.9, 0.7, 0.8))
	var vb := c.vb
	var W := c.W
	var F := c.F
	var T := c.T
	if hat == "bunny" or hat == "cat":
		# Snug, rounded knit beanie from just above the brows: the skull grown
		# by ~1.3 voxels on the sides and 3 rows on top, a thicker ribbed
		# turned-up cuff, a soft crown. The face stays clear below the cuff.
		var cuff_c: Color = L.get("cuff_color", sh(hc, 1.04))
		var C := c.C
		var g := 1.3
		var tg := 3.0
		# r15: a soft block (ref1): straight sides on one rounded-rect
		# footprint (the skull's widest section, grown), the top row inset by
		# one and the row under it by a half, so the crown has a single bevel
		# instead of stacked terraces.
		var mid := B + c.H / 2
		var top_y := T + 3
		var inside := func(x: int, y: int, z: int) -> bool:
			if y < C or y > top_y:
				return false
			var gg := g
			if y <= C + 1:
				gg = g + 0.7
			elif y == top_y:
				gg = g - 1.2
			elif y == top_y - 1:
				gg = g - 0.45
			return in_skull(c, x, mid, z, gg)
		# Clear hair/skull above the cuff that would poke through.
		var kill: Array[Vector3i] = []
		for p: Vector3i in vb.vox:
			if p.y >= C and not inside.call(p.x, p.y, p.z):
				# Keep the long hair hanging behind (below the cuff only).
				kill.append(p)
		for p in kill:
			vb.erase(p)
		var ri := ceili(g + 1.0)
		for y in range(C, T + 4 + 1):
			for x in range(-ri, W + ri):
				for z in range(-ri, F + ri + 1):
					if not inside.call(x, y, z):
						continue
					# Only the shell needs voxels.
					if inside.call(x + 1, y, z) and inside.call(x - 1, y, z) and inside.call(x, y + 1, z) and inside.call(x, y, z + 1) and inside.call(x, y, z - 1):
						continue
					var u := z if (x <= 1 or x >= W - 2) else x
					var p := Vector3i(x, y, z)
					if y <= C + 1:
						vb.set_v(p, sh(cuff_c, 0.9 if posmod(u, 2) == 0 else 1.03))
					else:
						var f := 0.97 if posmod(u, 2) == 0 else 1.02
						vb.set_v(p, sh(hc, f * (1.0 + (hh(p, 21) - 0.5) * 0.03)))
		if hat == "cat":
			# Stitched seam dots near the front corners (as on the ref hat).
			var st := sh(hc, 0.65)
			for x in [3, W - 4]:
				var z := front_z(vb, x, C + 4, F + 5)
				if z > -50:
					vb.set_v(Vector3i(x, C + 4, z), st)
		var top := 0
		for p: Vector3i in vb.vox:
			top = maxi(top, p.y)
		var outer: Color = L.get("ear_color", hc)
		var inner: Color = L.get("ear_inner", Color(0.95, 0.55, 0.65))
		var el := VoxelBuilder.new()
		el.jitter = 0.02
		if hat == "bunny":
			# Upright plush ears, 4 wide x 12 tall x 3 deep, pink inner panel
			# on the front, rounded tip, pinched base.
			var EH := 12
			for y in range(0, EH):
				for x in range(0, 4):
					for z in range(0, 3):
						if y == EH - 1 and (x == 0 or x == 3):
							continue
						if y == 0 and (x == 0 or x == 3) and z != 1:
							continue
						var col := outer
						if z == 2 and (x == 1 or x == 2) and y >= 2 and y <= EH - 3:
							col = inner
						el.set_v(Vector3i(x, y, z), sh(col, 1.0 + (hh(Vector3i(x, y, z), 22) - 0.5) * 0.04))
			out["ear_origin"] = Vector3(2.0, 0.5, 1.5)
			out["ear_pos"] = Vector3(W * 0.5 - 4.5, top - 1.5, F * 0.5 + 0.5)
		else:
			# Rounded cat/bear ears, 8 wide x 8 tall, pink inner panel.
			var rows := [[0, 7], [0, 7], [0, 7], [0, 7], [0, 7], [1, 6], [1, 6], [2, 5]]
			for y in rows.size():
				var x0: int = rows[y][0]
				var x1: int = rows[y][1]
				for x in range(x0, x1 + 1):
					for z in range(0, 3):
						var col := outer
						if z == 2 and y >= 1 and y <= 5 and x > x0 + (1 if y >= 5 else 0) and x < x1 - (1 if y >= 5 else 0):
							col = inner
						el.set_v(Vector3i(x, y, z), sh(col, 1.0 + (hh(Vector3i(x, y, z), 24) - 0.5) * 0.03))
			out["ear_origin"] = Vector3(4.0, 0.5, 1.5)
			out["ear_pos"] = Vector3(W * 0.5 - 4.0, top - 1.0, F * 0.5)
		out["ear"] = el
	elif hat == "cap" or hat == "flat_cap":
		var col := func(p: Vector3i) -> Color:
			return sh(hc, 1.0 + (hh(p, 23) - 0.5) * 0.05)
		var C2 := T - 3 if hat == "cap" else T - 2
		var tg := 2.0 if hat == "cap" else 1.0
		var inside := func(x: int, y: int, z: int) -> bool:
			return y >= C2 and in_skull(c, x, y, z, 1.0, tg)
		var kill: Array[Vector3i] = []
		for p: Vector3i in vb.vox:
			if p.y >= C2 and not inside.call(p.x, p.y, p.z):
				kill.append(p)
		for p in kill:
			vb.erase(p)
		for y in range(C2, T + 4):
			for x in range(-2, W + 2):
				for z in range(-2, F + 3):
					if inside.call(x, y, z):
						vb.set_v(Vector3i(x, y, z), col.call(Vector3i(x, y, z)))
		var brim := 5 if hat == "cap" else 3
		for x in range(2, W - 2):
			for z in range(F + 1, F + 1 + brim):
				if (x == 2 or x == W - 3) and z == F + brim:
					continue
				vb.set_v(Vector3i(x, C2, z), sh(hc, 0.82))
		if hat == "cap":
			vb.set_v(Vector3i(W / 2, T + 3, F / 2), sh(hc, 0.75))
			vb.set_v(Vector3i(W / 2 - 1, T + 3, F / 2), sh(hc, 0.75))


static func _glasses(c: Ctx) -> void:
	var gc := Color(0.5, 0.36, 0.22)
	var gz := c.F + 1
	for ei in 2:
		var ex: int = c.exs[ei]
		var x0 := ex - 2 if ei == 0 else ex - 1
		var x1 := ex + c.ew if ei == 0 else ex + c.ew + 1
		for x in range(x0, x1 + 1):
			c.vb.set_v(Vector3i(x, c.E + c.eh, gz), gc)
			c.vb.set_v(Vector3i(x, c.E - 1, gz), gc)
		for y in range(c.E, c.E + c.eh):
			c.vb.set_v(Vector3i(x0, y, gz), gc)
			c.vb.set_v(Vector3i(x1, y, gz), gc)
	for x in range(c.W / 2 - 1, c.W / 2 + 1):
		c.vb.set_v(Vector3i(x, c.E + c.eh - 1, gz), gc)
	for z in range(c.F - 6, c.F + 1):
		c.vb.set_v(Vector3i(-1, c.E + c.eh, z), gc)
		c.vb.set_v(Vector3i(c.W, c.E + c.eh, z), gc)
