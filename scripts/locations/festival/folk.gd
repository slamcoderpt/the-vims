extends RefCounted
## Background townsfolk: chunky chibi voxel people baked into ONE static mesh
## (1 draw call for the whole far crowd). Used past the fountain where the
## camera never gets close; the near crowd uses animated SimActors.
## 1/16 m cells. Each figure faces one of 8 directions (snapped per axis).

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

const SKIN := [Color("f2c7a0"), Color("e0a87c"), Color("c68a5e"), Color("9a6440"), Color("f6d2b0"), Color("7a4a2e")]
const HAIR := [Color("3a2416"), Color("5a3a20"), Color("1e1612"), Color("8a5a2a"), Color("c88a3a"), Color("6a6460"), Color("2a1a10")]
const SHIRT := [Color("e8e2d4"), Color("3a6aa8"), Color("c8402a"), Color("e8a030"), Color("4e7a3a"), Color("8a4a8a"),
	Color("f2d24a"), Color("2e4a6a"), Color("d86a8a"), Color("b85a2a"), Color("6aa0c8"), Color("f0f0ea")]
const PANTS := [Color("2e4a7a"), Color("3a3a42"), Color("5a3a24"), Color("6a6a3a"), Color("24304a"), Color("8a7a5a")]
const HATS := [Color("c8402a"), Color("f2ead8"), Color("6a4a2a"), Color("2e5a3a"), Color("e8a030"), Color("4a6aa8")]

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


func _person(kid: bool, seed: int) -> void:
	_seed = seed
	var skin: Color = K.pick(SKIN, _h(1))
	var hair: Color = K.pick(HAIR, _h(2))
	var shirt: Color = K.pick(SHIRT, _h(3))
	var pants: Color = K.pick(PANTS, _h(4))
	var shoe := Color("2a2420") if _h(5) < 0.6 else Color("6a3a20")
	var plaid := _h(6) < 0.2
	var leg := 5 if kid else 7
	var body := 6 if kid else 8
	var head := 8 if kid else 9
	var bw := 7 if kid else 8
	# Legs (or a skirt/dress).
	var dress := _h(7) < 0.25
	if dress:
		_b(-bw / 2 + 1, 0, -1, 2, 1, 3, shoe)
		_b(bw / 2 - 3, 0, -1, 2, 1, 3, shoe)
		_b(-bw / 2 + 1, 1, -1, 2, leg - 4, 2, skin)
		_b(bw / 2 - 3, 1, -1, 2, leg - 4, 2, skin)
		_b(-bw / 2, leg - 3, -2, bw, 3, 5, shirt)
	else:
		_b(-bw / 2, 0, -2, bw / 2 - 0, 1, 4, shoe)
		_b(0, 0, -2, bw / 2, 1, 4, shoe)
		_b(-bw / 2, 1, -2, bw / 2, leg - 1, 4, pants)
		_b(0, 1, -2, bw / 2, leg - 1, 4, func(q: Vector3i) -> Color: return K.shade(pants, 0.92))
	# Torso.
	var y0 := leg
	_b(-bw / 2, y0, -2, bw, body, 4, func(q: Vector3i) -> Color:
		if plaid:
			var dark := posmod(q.x, 3) == 0 or posmod(q.y, 3) == 0
			return K.shade(shirt, 0.65) if dark else shirt
		return shirt)
	# Belt.
	if not dress:
		_b(-bw / 2, y0, -2, bw, 1, 4, Color("3a2a1e"))
	# Arms (one maybe raised / holding something).
	var wave := _h(8) < 0.18
	_b(-bw / 2 - 2, y0 + 1, -1, 2, body - 1, 3, shirt)
	_b(-bw / 2 - 2, y0, -1, 2, 1, 3, skin)
	if wave:
		_b(bw / 2, y0 + body - 1, -1, 2, 5, 3, shirt)
		_b(bw / 2, y0 + body + 4, -1, 2, 2, 3, skin)
	else:
		_b(bw / 2, y0 + 1, -1, 2, body - 1, 3, shirt)
		_b(bw / 2, y0, -1, 2, 1, 3, skin)
		if _h(9) < 0.3:
			# Holding a cup / candy apple.
			_s(bw / 2 + 1, y0 + 1, 2, Color("f2ead8") if _h(10) < 0.5 else Color("c8141c"))
			_s(bw / 2 + 1, y0 + 2, 2, Color("f2ead8") if _h(10) < 0.5 else Color("c8141c"))
	# Head.
	var hy := y0 + body
	var hx := -head / 2
	_b(hx, hy, -head / 2, head, head, head - 1, skin)
	# Face (round 7 critic: clean flat skin, big friendly eyes, smile):
	# 2x2 dark eyes with a white catch-light, thick brows, a smile line.
	var fz := head / 2 - 1
	var ink := Color("1a1210")
	var ey := hy + 3
	var exl := hx + 1 if kid else hx + 2
	var exr := hx + head - 3 if kid else hx + head - 4
	for ex: int in [exl, exr]:
		_s(ex, ey, fz, ink)
		_s(ex + 1, ey, fz, ink)
		_s(ex, ey + 1, fz, ink)
		_s(ex + 1, ey + 1, fz, Color("fbf6ee"))
	var brow := K.shade(hair, 0.75)
	if not kid:
		_s(exl, ey + 3, fz, brow)
		_s(exl + 1, ey + 3, fz, brow)
		_s(exr, ey + 3, fz, brow)
		_s(exr + 1, ey + 3, fz, brow)
	# Smile: a dark line with upturned corners.
	var mc := Color("7a2a22")
	var mx := hx + head / 2
	_s(mx - 1, hy + 1, fz, mc)
	_s(mx, hy + 1, fz, mc)
	if head % 2 == 1:
		_s(mx + 1, hy + 1, fz, mc)
		_s(mx + 2, hy + 2, fz, mc)
	else:
		_s(mx + 1, hy + 2, fz, mc)
	_s(mx - 2, hy + 2, fz, mc)
	# Cheeks.
	_s(exl - 1 if kid else exl, hy + 2, fz, Color("f09a8a"))
	_s(exr + 2 if kid else exr + 1, hy + 2, fz, Color("f09a8a"))
	# Hair cap + back.
	var hair_style: int = int(_h(11) * 4)
	_b(hx - 0 , hy + head, -head / 2, head, 2, head - 1, hair)
	_b(hx, hy + head - 2, -head / 2, head, 2, 1, hair)
	_b(hx, hy + 2, -head / 2 - 1, head, head, 1, hair)
	# Fringe + side locks framing the face (clean, single colour).
	_b(hx, hy + head - 1, fz, head, 1, 1, hair)
	_b(hx, hy + 4, fz, 1, head - 4, 1, hair)
	_b(hx + head - 1, hy + 4, fz, 1, head - 4, 1, hair)
	_b(hx - 1, hy + 3, -head / 2, 1, head - 2, head - 3, hair)
	_b(hx + head, hy + 3, -head / 2, 1, head - 2, head - 3, hair)
	if hair_style == 1:
		# Long hair down the back.
		_b(hx, hy - 3, -head / 2 - 1, head, 5, 2, hair)
	elif hair_style == 2 and not kid:
		# Beard round the chin with the smile left open; moustache above.
		_b(hx, hy, fz, 1, 3, 1, hair)
		_b(hx + head - 1, hy, fz, 1, 3, 1, hair)
		_b(hx + 1, hy, fz, head - 2, 1, 1, hair)
		_b(hx + head / 2 - 1, hy + 2, fz, 3, 1, 1, K.shade(hair, 1.1))
	# Hat sometimes (beanie / cowboy / cap).
	var hat_roll := _h(12)
	if hat_roll < 0.3:
		var hc: Color = K.pick(HATS, _h(13))
		if hat_roll < 0.12:
			# Wide-brim hat.
			_b(hx - 2, hy + head + 1, -head / 2 - 2, head + 4, 1, head + 3, hc)
			_b(hx + 1, hy + head + 2, -head / 2 + 1, head - 2, 3, head - 3, K.shade(hc, 0.9))
		else:
			_b(hx, hy + head + 1, -head / 2, head, 3, head - 1, hc)
			_s(hx + head / 2, hy + head + 4, 0, K.shade(hc, 1.2))
