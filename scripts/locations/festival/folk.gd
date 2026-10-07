extends RefCounted
## Background townsfolk: chunky chibi voxel people baked into ONE static mesh
## (1 draw call for the whole far crowd). Used past the fountain where the
## camera never gets close; the near crowd uses animated SimActors.
## 1/16 m cells. Each figure faces one of 8 directions (snapped per axis).

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

const SKIN := [Color("f2c7a0"), Color("e0a87c"), Color("c68a5e"), Color("9a6440"), Color("f6d2b0"), Color("7a4a2e")]
const HAIR := [Color("3a2416"), Color("5a3a20"), Color("1e1612"), Color("8a5a2a"), Color("a0602c"), Color("8e8a86"), Color("2a1a10"), Color("7a3a1a")]
const SHIRT := [Color("e8e2d4"), Color("3a6aa8"), Color("c8402a"), Color("e8a030"), Color("4e7a3a"), Color("8a4a8a"),
	Color("f2d24a"), Color("2e4a6a"), Color("d86a8a"), Color("b85a2a"), Color("6aa0c8"), Color("f0f0ea")]
const PANTS := [Color("2e4a7a"), Color("3a3a42"), Color("5a3a24"), Color("6a6a3a"), Color("24304a"), Color("8a7a5a")]
const HATS := [Color("c8402a"), Color("f2ead8"), Color("6a4a2a"), Color("2e5a3a"), Color("8a2a3a"), Color("4a6aa8")]

## [x, z, face_yaw_deg, size (1 adult, 0.8 child), seed]
var people: Array = []

var _vb: VoxelBuilder
var _o := Vector3i.ZERO
var _f := 0   # 0 +Z, 1 +X, 2 -Z, 3 -X
var _seed := 0


func _h(i: int) -> float:
	return K.hs(_seed, i, 77)


func add(x: float, z: float, yaw_deg: float, kid := false, seed := 0) -> void:
	people.append([x, z, yaw_deg, kid, seed])


## vs: cell size; 1.18/16 m puts adults at ~1.9 m, in scale with SimActors.
func build(parent: Node3D, vs := U * 1.18, nm := "FarFolk") -> MeshInstance3D:
	_vb = VoxelBuilder.new()
	_vb.jitter = 0.0
	for p: Array in people:
		_o = Vector3i(roundi(p[0] / vs), 0, roundi(p[1] / vs))
		_f = posmod(roundi(p[2] / 90.0), 4)
		_person(p[3], p[4])
	return K.inst(parent, _vb, vs, Vector3.ZERO, 0.0, true, Vector3.ZERO, nm)


## Set a voxel in figure-local coords (x right, y up, z towards the face).
func _s(x: int, y: int, z: int, c: Color, glow := false) -> void:
	var q: Vector3i
	match _f:
		0: q = Vector3i(x, y, z)
		1: q = Vector3i(z, y, -x)
		2: q = Vector3i(-x, y, -z)
		_: q = Vector3i(-z, y, x)
	_vb.set_v(_o + q, c, glow)


func _b(x: int, y: int, z: int, w: int, h: int, d: int, c) -> void:
	for i in w:
		for j in h:
			for k in d:
				var col: Color = c.call(Vector3i(x + i, y + j, z + k)) if c is Callable else c
				_s(x + i, y + j, z + k, col)


## r14 (critic: blob heads, messy hair, no face): same clean proportions as
## the SimActor villagers. Head is ~1/3 of the height, a chamfered 8-wide
## block with ONE flat hair colour in a distinct shape (short crop, long,
## bun, ponytail, or a hat), 1x2 dark eyes, pink cheeks, a small mouth.
## Autumn outfits: flannel plaid, striped sweaters, cardigans, hoodies,
## scarves; some hold a candy apple or a cider cup.
func _person(kid: bool, seed: int) -> void:
	_seed = seed
	var skin: Color = K.pick(SKIN, _h(1))
	var hair: Color = K.pick(HAIR, _h(2))
	var shirt: Color = K.pick(SHIRT, _h(3))
	var pants: Color = K.pick(PANTS, _h(4))
	var shoe := Color("2a2420") if _h(5) < 0.6 else Color("6a3a20")
	var outfit: int = int(_h(6) * 6.0)   # 0 plain 1 plaid 2 stripes 3 cardigan 4 hoodie 5 plaid
	var leg := 5 if kid else 9
	var body := 5 if kid else 7
	var hw := 8
	var hh := 8 if kid else 8
	var bw := 6 if kid else 8
	var hb := bw / 2
	var girl := _h(7) < 0.5
	var skirt := girl and _h(14) < 0.45
	var shirt2 := K.shade(shirt, 0.6) if outfit != 2 else Color("f4ecdc")
	# Legs / skirt.
	var lx0 := -hb + 1
	var lx1 := 0 if bw % 2 == 0 else 1
	var lwid := hb - 1
	_b(lx0, 0, -1, lwid, 1, 4, shoe)
	_b(lx1, 0, -1, lwid, 1, 4, shoe)
	if skirt:
		_b(lx0, 1, -1, lwid, leg - 4, 2, Color("e8dcc8") if _h(15) < 0.5 else skin)
		_b(lx1, 1, -1, lwid, leg - 4, 2, Color("e8dcc8") if _h(15) < 0.5 else skin)
		_b(-hb, leg - 3, -2, bw, 3, 4, pants)
		_b(-hb - 1 + 1, leg - 4, -2, bw, 1, 4, K.shade(pants, 0.85))
	else:
		_b(lx0, 1, -1, lwid, leg - 1, 3, pants)
		_b(lx1, 1, -1, lwid, leg - 1, 3, K.shade(pants, 0.9))
	# Torso.
	var y0 := leg
	var tcol := func(q: Vector3i) -> Color:
		match outfit:
			1, 5:
				return shirt2 if (posmod(q.x, 3) == 0 or posmod(q.y, 3) == 0) else shirt
			2:
				return shirt2 if posmod(q.y, 2) == 0 else shirt
			3:
				return Color("f4ecdc") if (q.z == 1 and (q.x == -1 or q.x == 0)) else shirt
		return shirt
	_b(-hb, y0, -2, bw, body, 4, tcol)
	if not skirt:
		_b(-hb, y0, -2, bw, 1, 4, Color("3a2a1e"))
	if outfit == 4:
		# Hood folded on the shoulders / back of the neck.
		_b(-hb + 1, y0 + body - 1, -3, bw - 2, 2, 1, K.shade(shirt, 0.85))
	# Scarf (autumn) on a third of the adults.
	var scarf := not kid and _h(16) < 0.35
	if scarf:
		var sc: Color = K.pick(HATS, _h(17))
		_b(-hb, y0 + body - 1, -2, bw, 1, 5, sc)
		_b(-hb + 1, y0 + body - 4, 2, 2, 3, 1, K.shade(sc, 0.9))
	# Arms: one raised to wave, or one bent forward holding a cup / apple.
	var arm_c := shirt if outfit != 3 else shirt
	var wave := _h(8) < 0.15
	var holds := not wave and _h(9) < 0.4
	_b(-hb - 2, y0 + 1, -1, 2, body - 1, 2, arm_c)
	_b(-hb - 2, y0, -1, 2, 1, 2, skin)
	if wave:
		_b(hb, y0 + body - 1, -1, 2, 4, 2, arm_c)
		_b(hb, y0 + body + 3, -1, 2, 2, 2, skin)
	elif holds:
		_b(hb, y0 + 2, -1, 2, body - 2, 2, arm_c)
		_b(hb, y0 + 2, 1, 2, 1, 2, arm_c)
		_b(hb, y0 + 2, 3, 2, 1, 1, skin)
		if _h(10) < 0.5:
			_b(hb, y0 + 3, 3, 2, 3, 2, Color("f4ecdc"))
			_b(hb, y0 + 4, 3, 2, 1, 2, Color("c8642a"))
		else:
			_s(hb, y0 + 3, 3, Color("e8d4a0"))
			_b(hb, y0 + 4, 3, 2, 2, 2, Color("c0141c"))
	else:
		_b(hb, y0 + 1, -1, 2, body - 1, 2, arm_c)
		_b(hb, y0, -1, 2, 1, 2, skin)
	# Head: chamfered block, x -4..3, z -3..3 (face at z = 3).
	var hy := y0 + body
	var hx := -hw / 2
	var fz := 3
	for x in hw:
		for y in hh:
			for z in range(-3, 4):
				var edge_x := x == 0 or x == hw - 1
				var edge_z := z == -3 or z == 3
				if edge_x and edge_z:
					continue
				if (y == hh - 1) and (edge_x or edge_z):
					continue
				_s(hx + x, hy + y, z, skin if y > 0 else K.shade(skin, 0.94))
	# Face.
	var ink := Color("1e1412")
	var exl := hx + 2
	var exr := hx + hw - 3
	_s(exl, hy + 3, fz, ink)
	_s(exl, hy + 4, fz, ink)
	_s(exr, hy + 3, fz, ink)
	_s(exr, hy + 4, fz, ink)
	if girl or kid:
		_s(exl - 1, hy + 4, fz, ink)
		_s(exr + 1, hy + 4, fz, ink)
	_s(exl - 1 if not (girl or kid) else exl - 1, hy + 2, fz, Color("f0948a"))
	_s(exr + 1, hy + 2, fz, Color("f0948a"))
	var mc := Color("8a3428")
	_s(hx + hw / 2 - 1, hy + 1, fz, mc)
	_s(hx + hw / 2, hy + 1, fz, mc)
	# Hair (one flat colour) or a hat.
	var style: int = int(_h(11) * 5.0)   # 0 short 1 long 2 bun 3 ponytail 4 hat
	if not girl and (style == 1 or style == 3):
		style = 0
	if girl and style == 0:
		style = 1
	var hat_roll := _h(12)
	var brow := K.shade(hair, 0.8)
	if not (girl or kid):
		_s(exl, hy + 5, fz, brow)
		_s(exr, hy + 5, fz, brow)
		if _h(13) < 0.3:
			# Short beard round the jaw, mouth left open.
			_b(hx + 1, hy, fz, hw - 2, 1, 1, hair)
			_s(hx + 1, hy + 1, fz, hair)
			_s(hx + hw - 2, hy + 1, fz, hair)
	# Crown + back + sides (short crop): flat single colour.
	_b(hx + 1, hy + hh, -2, hw - 2, 1, 5, hair)
	_b(hx, hy + hh - 2, -3, hw, 2, 7, func(q: Vector3i) -> Color:
		return hair)
	_b(hx, hy + 2, -4, hw, hh - 2, 1, hair)
	_b(hx - 1, hy + 3, -3, 1, hh - 4, 5, hair)
	_b(hx + hw, hy + 3, -3, 1, hh - 4, 5, hair)
	# Fringe row across the brow (leave the face open below it).
	_b(hx + 1, hy + hh - 2, fz, hw - 2, 1, 1, hair)
	match style:
		1:
			# Long hair: falls to the shoulders at the back and sides.
			_b(hx, hy - 3, -4, hw, 5, 2, hair)
			_b(hx - 1, hy - 2, -3, 1, 5, 4, hair)
			_b(hx + hw, hy - 2, -3, 1, 5, 4, hair)
		2:
			_b(hx + 2, hy + hh + 1, -2, 4, 2, 3, hair)
		3:
			_b(hx + 3, hy + hh - 3, -6, 2, 2, 2, hair)
			_b(hx + 3, hy + 1, -6, 2, 4, 2, K.shade(hair, 0.92))
	if hat_roll < 0.32 and style != 2:
		var hc: Color = K.pick(HATS, _h(13))
		if hat_roll < 0.0:  # (felt hats read as tan blobs from above)
			# Felt hat: thin brim + low crown.
			_b(hx - 1, hy + hh, -4, hw + 2, 1, 9, K.shade(hc, 0.85))
			_b(hx + 1, hy + hh + 1, -2, hw - 2, 2, 5, hc)
			_b(hx + 1, hy + hh + 1, -2, hw - 2, 1, 5, K.shade(hc, 0.6))
		elif hat_roll < 0.2:
			# Knit beanie: folded band + crown + pom.
			_b(hx, hy + hh - 1, -3, hw, 1, 7, K.shade(hc, 0.82))
			_b(hx + 1, hy + hh, -2, hw - 2, 2, 5, hc)
			_s(hx + hw / 2, hy + hh + 2, 0, Color("f4ecdc"))
		else:
			# Flat cap with a short brim.
			_b(hx, hy + hh, -3, hw, 1, 7, hc)
			_b(hx + 1, hy + hh, 4, hw - 2, 1, 1, K.shade(hc, 0.8))
