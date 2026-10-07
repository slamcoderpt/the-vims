extends RefCounted
## Music stage: plank deck, truss with string lights, maple-leaf backdrop
## banner, bunting, speakers, mic stand, hay bales and pumpkins out front.
## 1/16 m cells, front faces +Z.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0
const W := 96
const D := 44
const DECK := 28
const SCALE := 0.82
## Five-lobed maple leaf with a stem (row 0 = top).
const MAPLE_BIG := [
	"......#......",
	".....###.....",
	"..#.#####.#..",
	"..#########..",
	"#.#########.#",
	"##.#######.##",
	".###########.",
	"..#########..",
	"...#######...",
	"....##.##....",
	"......#......",
	"......#......",
]

var node: Node3D
var glow_points: Array = []
## Where the performer stands (world).
var performer_spot := Vector3.ZERO


func build(parent: Node3D, pos: Vector3, rot: float) -> void:
	node = Node3D.new()
	node.name = "Stage"
	node.position = pos
	node.rotation.y = deg_to_rad(rot)
	# Slightly smaller than life so the roof stays in frame (critic r5).
	node.scale = Vector3.ONE * SCALE
	parent.add_child(node)
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	# Deck + skirt at 1/8 m cells (big flat areas; halves their triangle cost).
	var deck := VoxelBuilder.new()
	deck.jitter = 0.0
	_deck(deck)
	# Round 9: open truss (no roof) so the higher camera sees the maple
	# banner, bulbs and bunting like the ref instead of a dark plank lid.
	_steps(vb)
	_truss(vb)
	_backdrop(vb)
	_gear(vb)
	_front(vb)
	var origin := Vector3(W * 0.5, 0, D * 0.5)
	K.inst(node, vb, U, Vector3.ZERO, 0.0, true, origin)
	K.inst(node, deck, U * 2.0, Vector3.ZERO, 0.0, true, origin * 0.5, "Deck")
	var xf := node.transform
	for p: Vector3i in vb.glow:
		if p.y > 70 and posmod(p.x, 2) == 0:
			glow_points.append([xf * ((Vector3(p) + Vector3(0.5, 0.5, 0.5) - origin) * U), 0.45, Color(1.0, 0.75, 0.4)])
	performer_spot = xf * Vector3(-1.5, DECK * U, 0.6)
	_notes(node)
	# Stage wash: a warm key light in front of the performer so he reads
	# front-lit against the backdrop (round 3: guitarist was a dark blob).
	K.light(node, Vector3(-1.4, DECK * U + 1.8, 2.4), Color(1.0, 0.82, 0.6), 2.6, 3.6, 1.0)


## Little floating music notes beside the guitarist.
func _notes(n: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var note := ["..##", "..#.", "..#.", "###.", "###."]
	var dbl := ["#####", "#...#", "#...#", "#..##", "##.##", "##..."]
	K.pattern(vb, note, 0, 0, 0, {"#": Color("fffaf0")}, true)
	K.pattern(vb, dbl, 4, 7, 0, {"#": Color("fffaf0")}, true)
	var mi := K.inst(n, vb, 0.09, Vector3(-2.95, DECK * U + 1.5, 1.3), 0.0, false)
	mi.name = "MusicNotes"


func _deck(vb: VoxelBuilder) -> void:
	# Coarse cells (2x): skirt (dark wood) + deck planks running along X.
	var w := W / 2
	var d := D / 2
	var h := DECK / 2
	K.box(vb, 0, 0, 0, w, h - 1, d, func(q: Vector3i) -> Color:
		if q.z < d - 1 and q.x > 0 and q.x < w - 1:
			return Color("3a2a20")
		var f := 0.85 + K.hs(q.x / 2, 2, 9) * 0.2
		return K.shade(Color("6a4228"), f if posmod(q.x, 2) != 0 else f * 0.8))
	K.box(vb, 0, h - 1, 0, w, 1, d + 1, K.wood(Color("b07a48"), 0, 2))


## Pitched roof at 1/8 m cells (halves its triangle cost; it is a big flat
## surface so the coarser grid does not show).
func _roof(vb: VoxelBuilder) -> void:
	var top := 86 / 2
	var d := D / 2
	var w := W / 2
	for z in range(-1, d + 2):
		var t := float(z + 1) / float(d + 2)
		var y := top + 1 + int(round(lerpf(4.0, 0.0, t)))
		for x in range(-2, w + 2):
			var c := K.shade(Color("3a2e2a"), 0.86 + K.hs(x / 2, z, 5) * 0.22)
			if posmod(z, 2) == 0:
				c = K.shade(c, 0.82)
			vb.set_v(Vector3i(x, y, z), c)


func _steps(vb: VoxelBuilder) -> void:
	# Front steps.
	var rise := DECK / 6
	for st in 6:
		K.box(vb, W / 2 - 10, st * rise, D + 10 - st * 2, 20, rise, 2, K.wood(Color("9a6a40"), 0, 2))
		K.box(vb, W / 2 - 10, 0, D + 10 - st * 2, 20, st * rise, 2, Color("3a2a20"))


func _truss(vb: VoxelBuilder) -> void:
	var dark := Color("2e2a28")
	var top := 86
	for c in [Vector2i(0, 2), Vector2i(W - 3, 2), Vector2i(0, D - 3), Vector2i(W - 3, D - 3)]:
		K.box(vb, c.x, DECK, c.y, 3, top - DECK, 3, func(q: Vector3i) -> Color:
			return dark if posmod(q.y, 6) != 0 else Color("4a4440"))
	# Top beams (front + back + sides).
	K.box(vb, 0, top, D - 3, W, 3, 3, dark)
	K.box(vb, 0, top, 2, W, 3, 3, dark)
	K.box(vb, 0, top, 2, 3, 3, D - 2, dark)
	K.box(vb, W - 3, top, 2, 3, 3, D - 2, dark)
	for bx in [W / 3, 2 * W / 3]:
		K.box(vb, bx, top, 2, 2, 2, D - 2, dark)
	# Bulb strings zig-zagging across the open top (front to back).
	for k in 5:
		var x0 := 8 + k * (W - 16) / 4
		for zi in range(4, D - 3, 3):
			var sag := int(sin(float(zi) / float(D) * PI) * 3.0)
			vb.set_v(Vector3i(x0, top - 1 - sag, zi), Color("3a3530"))
			if zi % 6 == 1:
				vb.set_v(Vector3i(x0, top - 2 - sag, zi), Color("ffd060"), true)
	# Dark pitched roof over the truss (reads as a covered bandstand).
	# (Built at 2x cells in the deck builder: see _roof.)
	# Fascia board along the front edge, with a row of warm bulbs under it.
	K.box(vb, -3, top + 1, D + 2, W + 6, 3, 1, Color("5a2a22"))
	for x in range(-2, W + 3, 4):
		vb.set_v(Vector3i(x, top, D + 2), Color("ffd060"), true)
		vb.set_v(Vector3i(x, top - 1, D + 2), Color("ffb848"), true)
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
			K.box(vb, x, top - 4 - sag, zz, 2, 2, 1, Color("ffd060"), true)
			vb.set_v(Vector3i(x, top - 5 - sag, zz), Color("ffb848"), true)
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
	# Dark plank back wall with a cream banner + red maple leaf in the middle.
	K.box(vb, 3, DECK, 2, W - 6, 82 - DECK, 1, func(q: Vector3i) -> Color:
		var plank := q.x / 4
		var f := 0.85 + K.hs(plank, 3, 7) * 0.25
		if posmod(q.x, 4) == 0:
			f *= 0.75
		return K.shade(Color("3e2a1e"), f))
	# Banner across the top half only (critic r5: the stage read as a red/cream
	# blob); the lower wall stays dark so the guitarist pops against it.
	var bx0 := W / 2 - 4
	var bx1 := W / 2 + 36
	var by0 := 42
	var by1 := 71
	for x in range(bx0, bx1):
		for y in range(by0, by1):
			var c := K.shade(Color("f4dcae"), 0.95 + K.hs(x / 3, y / 3, 2) * 0.07)
			if x < bx0 + 2 or x >= bx1 - 2 or y >= by1 - 2:
				c = Color("8a2a1a")
			elif x < bx0 + 3 or x >= bx1 - 3 or y >= by1 - 3:
				c = Color("f6e2b0")
			vb.set_v(Vector3i(x, y, 3), c)
	# Pennant bottom edge.
	for x in range(bx0, bx1):
		var k := posmod(x - bx0, 8)
		var drop := 3 - absi(k - 4) if absi(k - 4) < 3 else 0
		for d in drop:
			vb.set_v(Vector3i(x, by0 - 1 - d, 3), Color("c8461e"))
	K.pattern(vb, MAPLE_BIG, W / 2 + 3, by0 + 3, 4, {"#": Color("c8301a")}, false, 2)
	# Triangle pennants either side of the banner (ref: bunting framing it).
	var pc := [Color("e2662a"), Color("f6efe0"), Color("c8401e"), Color("f2b33a")]
	var k := 0
	for x0 in range(6, W - 8, 7):
		if x0 + 6 >= bx0 and x0 <= bx1:
			continue
		for row in 6:
			var half := 3 - (row + 1) / 2
			for dx in range(-half, half + 1):
				vb.set_v(Vector3i(x0 + 3 + dx, 79 - row, 4), pc[k % pc.size()])
		k += 1
	# Warm uplight strip at the foot of the back wall (stage glow).
	for x in range(6, W - 6, 3):
		vb.set_v(Vector3i(x, DECK, 3), Color("ffcf70"), true)
	# Side drapes: deep wine, narrow.
	for x in [3, W - 7]:
		K.box(vb, x, DECK, 3, 4, 84 - DECK, 2, func(q: Vector3i) -> Color:
			return K.shade(Color("5a1e1e"), 0.8 + 0.2 * float(posmod(q.x, 2))))


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
	# Hay bales + pumpkins on the deck edge (ref: band among hay bales).
	K.hay(vb, W / 2 - 4, DECK, D - 9, 14, 8, 8)
	K.hay(vb, W - 30, DECK, D - 10, 12, 7, 8)
	K.pumpkin(vb, W / 2 + 2, DECK + 8, D - 5, 2.6, 6, 1)
	K.pumpkin(vb, W - 26, DECK, D - 1, 2.4, 7, 0)
