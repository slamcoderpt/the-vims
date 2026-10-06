extends RefCounted
## Music stage: plank deck, truss with string lights, maple-leaf backdrop
## banner, bunting, speakers, mic stand, hay bales and pumpkins out front.
## 1/16 m cells, front faces +Z.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0
const W := 96
const D := 44
const DECK := 10

var node: Node3D
var glow_points: Array = []
## Where the performer stands (world).
var performer_spot := Vector3.ZERO


func build(parent: Node3D, pos: Vector3, rot: float) -> void:
	node = Node3D.new()
	node.name = "Stage"
	node.position = pos
	node.rotation.y = deg_to_rad(rot)
	parent.add_child(node)
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	_deck(vb)
	_truss(vb)
	_backdrop(vb)
	_gear(vb)
	_front(vb)
	var origin := Vector3(W * 0.5, 0, D * 0.5)
	K.inst(node, vb, U, Vector3.ZERO, 0.0, true, origin)
	var xf := node.transform
	for p: Vector3i in vb.glow:
		if p.y > 60 and posmod(p.x, 2) == 0:
			glow_points.append([xf * ((Vector3(p) + Vector3(0.5, 0.5, 0.5) - origin) * U), 0.45, Color(1.0, 0.75, 0.4)])
	performer_spot = xf * Vector3(-0.2, DECK * U, 0.35)


func _deck(vb: VoxelBuilder) -> void:
	# Skirt (dark wood) + deck planks running along X.
	K.box(vb, 0, 0, 0, W, DECK - 1, D, func(q: Vector3i) -> Color:
		if q.z < D - 1 and q.x > 0 and q.x < W - 1:
			return Color("3a2a20")
		var f := 0.85 + K.hs(q.x / 3, 2, 9) * 0.2
		return K.shade(Color("6a4228"), f if posmod(q.x, 3) != 0 else f * 0.8))
	K.box(vb, -1, DECK - 1, 0, W + 2, 1, D + 1, K.wood(Color("b07a48"), 0, 3))
	# Front steps.
	K.box(vb, W / 2 - 10, 0, D, 20, 3, 4, K.wood(Color("9a6a40"), 0, 2))
	K.box(vb, W / 2 - 10, 3, D, 20, 3, 2, K.wood(Color("9a6a40"), 0, 2))
	K.box(vb, W / 2 - 10, 6, D - 2, 20, 3, 2, K.wood(Color("9a6a40"), 0, 2))


func _truss(vb: VoxelBuilder) -> void:
	var dark := Color("2e2a28")
	var top := 76
	for c in [Vector2i(0, 2), Vector2i(W - 3, 2), Vector2i(0, D - 3), Vector2i(W - 3, D - 3)]:
		K.box(vb, c.x, DECK, c.y, 3, top - DECK, 3, func(q: Vector3i) -> Color:
			return dark if posmod(q.y, 6) != 0 else Color("4a4440"))
	# Top beams (front + back + sides).
	K.box(vb, 0, top, D - 3, W, 3, 3, dark)
	K.box(vb, 0, top, 2, W, 3, 3, dark)
	K.box(vb, 0, top, 2, 3, 3, D - 2, dark)
	K.box(vb, W - 3, top, 2, 3, 3, D - 2, dark)
	# Zig-zag truss lacing on the front beam.
	for x in range(0, W, 2):
		vb.set_v(Vector3i(x, top - 1 - posmod(x / 2, 3), D - 2), Color("4a4440"))
	# String lights along the front + back beam, sagging between posts.
	for zz in [D - 1, 3]:
		var n := 12
		for i in n:
			var t := (i + 0.5) / n
			var x := int(t * W)
			var sag := int(sin(t * PI * 3.0) ** 2 * 3.0)
			vb.set_v(Vector3i(x, top - 2 - sag, zz), Color("3a3530"))
			vb.set_v(Vector3i(x, top - 3 - sag, zz), Color("ffd060"), true)
			vb.set_v(Vector3i(x, top - 4 - sag, zz), Color("ffb848"), true)
	# Bunting across the front beam.
	var cols := [Color("e2662a"), Color("f2b33a"), Color("c8401e"), Color("f6efe0"), Color("8a3a2a")]
	var i := 0
	for x0 in range(3, W - 6, 6):
		var c: Color = cols[i % cols.size()]
		for row in 6:
			var half := 2 - row / 2
			for dx in range(-half, half + 1):
				if half >= 0:
					vb.set_v(Vector3i(x0 + 2 + dx, top - 1 - row - 2, D), c)
		i += 1


func _backdrop(vb: VoxelBuilder) -> void:
	# Big fabric banner with a maple leaf between the back posts.
	var x0 := 10
	var x1 := W - 10
	for x in range(x0, x1):
		for y in range(DECK + 14, 70):
			var c := Color("f0a43a")
			var edge := x < x0 + 3 or x >= x1 - 3 or y >= 67
			if edge:
				c = Color("c8401e")
			elif (x / 6 + y / 6) % 2 == 0:
				c = Color("ec9a32")
			vb.set_v(Vector3i(x, y, 3), c)
	K.maple(vb, W / 2 - 14, 30, 4, Color("d0381e"), 4)
	# Scalloped bottom edge.
	for x in range(x0, x1):
		if posmod(x, 4) < 2:
			vb.set_v(Vector3i(x, DECK + 13, 3), Color("c8401e"))
	# Side drapes.
	for x in [3, W - 9]:
		K.box(vb, x, DECK, 3, 6, 64, 2, func(q: Vector3i) -> Color:
			return K.shade(Color("8a2a24"), 0.85 + 0.15 * float(posmod(q.x, 2))))


func _gear(vb: VoxelBuilder) -> void:
	# Speakers.
	for sx in [6, W - 16]:
		K.box(vb, sx, DECK, D - 14, 10, 16, 8, Color("24221f"))
		for c in [Vector3i(sx + 5, DECK + 4, D - 6), Vector3i(sx + 5, DECK + 11, D - 6)]:
			for x in range(-2, 3):
				for y in range(-2, 3):
					if x * x + y * y <= 5:
						vb.set_v(c + Vector3i(x, y, 0), Color("4a4642") if x * x + y * y > 1 else Color("6a6460"))
	# Small monitor wedge + amp.
	K.box(vb, W / 2 + 12, DECK, D - 10, 10, 6, 6, Color("2e2a28"))
	K.box(vb, W / 2 + 13, DECK + 1, D - 5, 8, 4, 1, Color("4a4642"))
	# Mic stand.
	K.box(vb, W / 2 - 8, DECK, D - 9, 3, 1, 3, Color("2a2826"))
	K.box(vb, W / 2 - 7, DECK + 1, D - 8, 1, 22, 1, Color("6a6a6a"))
	K.box(vb, W / 2 - 7, DECK + 23, D - 8, 1, 2, 2, Color("2a2826"))
	# Drum kit at the back.
	K.cyl(vb, W / 2 - 18.0, DECK, 14.0, 5.0, 8, func(q: Vector3i) -> Color:
		return Color("c8301e") if q.y < DECK + 6 else Color("f2eee6"))
	K.cyl(vb, W / 2 - 26.0, DECK, 12.0, 3.0, 9, Color("c8301e"))
	K.box(vb, W / 2 - 30, DECK + 14, 10, 6, 1, 6, Color("e0b040"))
	K.box(vb, W / 2 - 28, DECK, 12, 1, 14, 1, Color("8a8a8a"))


func _front(vb: VoxelBuilder) -> void:
	# Hay bales, pumpkins and a mum pot along the stage front.
	K.hay(vb, 2, 0, D + 3, 14, 8, 8)
	K.hay(vb, 4, 8, D + 4, 10, 7, 6)
	K.hay(vb, W - 18, 0, D + 3, 14, 8, 8)
	K.pumpkin(vb, 20, 0, D + 6, 3.6, 1, 0)
	K.pumpkin(vb, 26, 0, D + 9, 2.6, 2, 2)
	K.pumpkin(vb, W - 22, 0, D + 7, 3.0, 3, 1)
	K.pumpkin(vb, W - 4, 8, D + 7, 3.0, 4, 0)
	K.mums(vb, W / 2 + 18, 0, D + 6, 4.0, 0, 3)
	K.mums(vb, W / 2 - 20, 0, D + 6, 4.0, 1, 5)
