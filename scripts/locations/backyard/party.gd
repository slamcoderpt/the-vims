extends RefCounted
## The party set: long dinner table (red gingham cloth, food, drinks, candle
## jars) with wooden chairs, the gas grill with smoke, a prep table, stone fire
## pit, outdoor lounge sofa, lanterns and the string lights on posts.

const V := preload("res://scripts/locations/backyard/vox.gd")
const Halos := preload("res://scripts/locations/backyard/halos.gd")
const F := 16

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const WOOD_L := Color("c99462")
const IRON := Color("2b2b31")
const BULB := Color("ffd889")

## World placement of the main pieces.
const TABLE_POS := Vector3(0.75, 0.0, 0.75)
## Long axis runs across the picture with a gentle diagonal (ref4): the
## far side's diners face the camera in a row, the near side sit with their
## backs to us in the gaps between them, the left end is a little nearer.
const TABLE_ROT := 0.12
const GRILL_POS := Vector3(-3.3, 0.0, -1.25)
const GRILL_ROT := PI + 0.55
const PIT_POS := Vector3(3.5, 0.0, 2.45)
## Lanterns (fine cells: x, y, z of the base corner; 7x7 footprint).
const LANTERNS := [Vector3i(-66, 0, 14), Vector3i(24, 0, -38), Vector3i(122, 0, -10), Vector3i(-88, 0, -58), Vector3i(150, 0, 50),
		Vector3i(44, 6, -50), Vector3i(118, 6, -50), Vector3i(-50, 0, 44), Vector3i(70, 0, 68),
		Vector3i(-118, 0, 42), Vector3i(100, 0, 62), Vector3i(-140, 0, -20)]
## Lanterns that also get a real OmniLight (the rest only bake a pool on the lawn).
const LIT_LANTERNS := [0, 2, 7, 8, 10]


## Warm light pools on the ground (world x, z, radius m, strength) for the
## baked lawn glow: lanterns, fire pit, grill, table candles, deck spill.
static func light_pools() -> Array:
	var out := []
	for lp in LANTERNS:
		if lp.y == 0:
			out.append([(lp.x + 3.5) / F, (lp.z + 3.5) / F, 1.5, 0.85])
	out.append([PIT_POS.x, PIT_POS.z, 2.8, 1.25])
	out.append([GRILL_POS.x, GRILL_POS.z, 1.9, 0.7])
	out.append([TABLE_POS.x, TABLE_POS.z, 2.6, 0.55])
	out.append([6.5, -2.4, 4.2, 0.6])
	out.append([3.0, -2.2, 2.6, 0.45])
	# Under the string lights.
	for sp in [Vector3(-4.0, 0, -3.0), Vector3(-2.0, 0, -3.2), Vector3(-1.5, 0, -1.6), Vector3(3.6, 0, -1.8), Vector3(5.0, 0, -0.9)]:
		out.append([sp.x, sp.z, 2.0, 0.3])
	return out

## Table half-length / half-depth in fine cells (cloth edge): a 3.75 m x
## 1.4 m farmhouse table (~2.7:1), four chairs on the far side, three on
## the near side staggered into the gaps (so near heads never cover a far
## face) and one at each end.
const TL := 30
const TD := 11
## Seats in table-local cells: Vector3(x, z, unused) — facing is derived in _facing().
## "far" (-z) faces the camera, "near" (+z) has its back to it.
const SEATS := {
	"far_1": Vector3(-24, -16, 0.0),
	"far_2": Vector3(-8, -16, 0.0),
	"far_3": Vector3(8, -16, 0.0),
	"far_4": Vector3(24, -16, 0.0),
	"near_l": Vector3(-16, 16, PI),
	"near_m": Vector3(0, 16, PI),
	"near_r": Vector3(16, 16, PI),
	"end_l": Vector3(-37, 0, PI * 0.5),
	"end_r": Vector3(37, 0, -PI * 0.5),
}
## Seats with a thick booster cushion so seated kids sit up above the table
## edge (their faces would otherwise drop behind the food). Seat top in m.
const BOOSTED := {"far_1": Color("e88fb4"), "far_4": Color("a98fd8")}
const SEAT_Y := 0.4375
const BOOST_Y := 0.625


static func seat_height(key: String) -> float:
	return BOOST_Y if BOOSTED.has(key) else SEAT_Y

var root: Node3D
var table_node: Node3D
var grill_node: Node3D
var pit_light: OmniLight3D
var coal_light: OmniLight3D
var smoke: CPUParticles3D
var halos := Halos.new()
var _rng := RandomNumberGenerator.new()


func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Party"
	parent.add_child(root)
	_rng.seed = 777
	_table()
	_grill()
	var yard := VoxelBuilder.new()
	yard.jitter = 0.05
	_prep_table(yard, -28, -40)
	_fire_pit(yard, int(PIT_POS.x * F), int(PIT_POS.z * F))
	_sofa(yard, 78, 28)
	_side_table(yard, 74, 58)
	for lp in LANTERNS:
		_lantern(yard, lp.x, lp.y, lp.z, 1.0)
		halos.add(Vector3((lp.x + 3.5) / F, (lp.y + 5.5) / F, (lp.z + 3.5) / F), 1.5, Color(1.0, 0.6, 0.24, 1.0))
	_posts(yard)
	# Planters around the lounge and the patio.
	for pp in [Vector3i(94, 0, -10), Vector3i(92, 0, 66), Vector3i(-50, 0, -60), Vector3i(-96, 0, -20), Vector3i(60, 0, -30)]:
		V.flower_pot(yard, pp.x, pp.y, pp.z, pp.x * 3 + pp.z, true)
	V.inst(yard, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "YardProps")
	var lights := VoxelBuilder.new()
	lights.jitter = 0.02
	_string_lights(lights)
	var lmi := V.inst(lights, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, false, true, "StringLights")
	lmi.set_surface_override_material(lmi.mesh.get_surface_count() - 1, V.glow_bulb())
	# Light sources.
	pit_light = V.omni(root, PIT_POS + Vector3(0, 0.75, 0), Color(1.0, 0.55, 0.22), 2.6, 5.5)
	# Glow sprites: fire pit, grill coals, table candles, house lamps + doors.
	halos.add(PIT_POS + Vector3(0, 0.6, 0), 1.9, Color(1.0, 0.45, 0.12, 0.85))
	var tb := Transform3D(Basis(Vector3.UP, TABLE_ROT), TABLE_POS)
	for cq in [Vector2(-11, -3), Vector2(12, -3), Vector2(21, 0)]:
		halos.add(tb * Vector3(cq.x / 16.0, 0.95, cq.y / 16.0), 0.55, Color(1.0, 0.65, 0.3, 0.9))
	for wx in [29.5 / 16.0, 193.5 / 16.0]:
		halos.add(Vector3(wx, 2.4, -5.9), 0.9, Color(1.0, 0.7, 0.35, 0.6))
	for dx in [3.4, 5.2, 7.0, 8.8, 10.6]:
		halos.add(Vector3(dx, 1.5, -5.7), 2.4, Color(1.0, 0.62, 0.3, 0.14))
	halos.build(root)
	for i in LIT_LANTERNS:
		var lp: Vector3i = LANTERNS[i]
		V.omni(root, Vector3((lp.x + 3.5) / F, (lp.y + 6.0) / F, (lp.z + 3.5) / F), Color(1.0, 0.66, 0.32), 1.1, 2.2)
	# Candle-warm key on the far-side diners' faces (from the camera side of
	# the table, above head height so it reads as the candle/string glow).
	for fx in [-1.0, 1.0]:
		V.omni(root, tb * Vector3(fx, 1.45, 0.75), Color(1.0, 0.76, 0.5), 0.75, 2.4)
	V.omni(root, GRILL_POS + Vector3(-0.9, 0.7, 1.1), Color(1.0, 0.7, 0.4), 1.2, 3.5)
	V.omni(root, Vector3(-1.0, 2.6, -1.0), Color(1.0, 0.78, 0.5), 1.1, 6.5)
	V.omni(root, Vector3(3.6, 2.6, 0.2), Color(1.0, 0.78, 0.5), 0.9, 6.0)


func world_seat(key: String) -> Transform3D:
	var s: Vector3 = SEATS[key]
	var tb := Transform3D(Basis(Vector3.UP, TABLE_ROT), TABLE_POS)
	var p := tb * Vector3(s.x / F, 0.0, s.y / F)
	return Transform3D(Basis(Vector3.UP, TABLE_ROT + _facing(s)), p)


func _facing(s: Vector3) -> float:
	# Face the table centre line.
	if absf(s.x) > TL:
		return PI * 0.5 if s.x < 0 else -PI * 0.5
	return 0.0 if s.y < 0 else PI


func grill_front() -> Vector3:
	return GRILL_POS + Basis(Vector3.UP, GRILL_ROT) * Vector3(0, 0, 0.62)


func process(t: float) -> void:
	if pit_light:
		pit_light.light_energy = 2.4 + sin(t * 11.0) * 0.25 + sin(t * 23.7) * 0.15
	if coal_light:
		coal_light.light_energy = 0.45 + sin(t * 9.0) * 0.06


# ------------------------------------------------------------------ table

func _gingham(u: int, v: int) -> Color:
	var a := posmod(floori(u / 2.0), 2) == 0
	var b := posmod(floori(v / 2.0), 2) == 0
	if a and b:
		return Color("c8262c")
	if a or b:
		return Color("e8767a")
	return Color("fbf3ec")


func _table() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var L := TL
	var D := TD
	# Chunky legs + apron (only the feet show under the cloth drape). Real
	# dining height: the cloth top sits at 0.75 m, so seated diners show
	# their chest and arms above the table.
	for q in [Vector2i(-L + 2, -D + 2), Vector2i(L - 4, -D + 2), Vector2i(-L + 2, D - 4), Vector2i(L - 4, D - 4)]:
		V.b(vb, q.x, 0, q.y, 2, 8, 2, WOOD_D)
		V.b(vb, q.x, 2, q.y, 2, 1, 2, V.shade(WOOD_D, 0.8))
	V.b(vb, -L + 1, 8, -D + 1, L * 2 - 2, 1, D * 2 - 2, V.wood(WOOD_D, 0, 2))
	V.b(vb, -L, 9, -D, L * 2, 2, D * 2, V.wood(WOOD_L, 0, 3))
	# Red gingham cloth over the whole top, draping down every side (ref4).
	var gc := func(q: Vector3i) -> Color:
		var c: Color = _gingham(q.x, q.z)
		return V.shade(c, 0.97 + V.h1(q, 6) * 0.05)
	V.b(vb, -L - 1, 11, -D - 1, L * 2 + 2, 1, D * 2 + 2, gc)
	for side in [-1, 1]:
		var zz := -D - 2 if side < 0 else D + 1
		V.b(vb, -L - 1, 7, zz, L * 2 + 2, 5, 1, func(q: Vector3i) -> Color:
			return V.shade(_gingham(q.x, q.y), 0.88 if q.y < 11 else 0.95))
		var xx := -L - 2 if side < 0 else L + 1
		V.b(vb, xx, 7, -D - 1, 1, 5, D * 2 + 2, func(q: Vector3i) -> Color:
			return V.shade(_gingham(q.z, q.y), 0.85 if q.y < 11 else 0.95))
	var y := 12
	# Place settings: a big white plate with one clear food item, a tall
	# amber drink beside it, folded napkin.
	var foods := [0, 3, 0, 2, 1, 0, 3, 2, 0]
	var fi := 0
	for key in SEATS:
		var s: Vector3 = SEATS[key]
		var px := int(s.x)
		var pz := int(s.y)
		if absf(s.x) > L:
			px = -L + 5 if s.x < 0 else L - 6
			pz = 0
		else:
			pz = -D + 4 if s.y < 0 else D - 5
		_plate(vb, px, y, pz, foods[fi % foods.size()])
		fi += 1
		var gx := px + 5
		var gz := pz + (-1 if s.y < 0 else 0)
		if absf(s.x) > L:
			gx = px
			gz = pz + 5
		_glass(vb, gx, y, gz)
		V.b(vb, px - 6, y, pz - 1, 2, 1, 3, Color("f6f3ee"))
	# A few big readable dishes down the middle (no confetti): salad bowl,
	# burger platter, drink pitchers, watermelon, corn, candle jars and a
	# low flower vase. Tall pieces sit in the gaps between far-side faces.
	_corn_platter(vb, -29, y, -3)
	_bowl_big(vb, -18, y, 1, Color("5fa83e"), [Color("e2513f"), Color("8fd05a"), Color("f2c22a"), Color("fbf3ec")])
	_candle(vb, -12, y, -4)
	_pitcher(vb, -16, y, -6)
	_burger_platter(vb, -3, y, 1)
	V.b(vb, -6, y, -5, 1, 4, 1, Color("d02a24")); V.p(vb, -6, y + 4, -5, Color("f2f2f2"))
	V.b(vb, -4, y, -5, 1, 4, 1, Color("f2c22a")); V.p(vb, -4, y + 4, -5, Color("f2f2f2"))
	_candle(vb, 12, y, -4)
	_melon(vb, 7, y, 1)
	# Low vase, lined up between diners (never in front of a face).
	V.b(vb, 1, y, -5, 3, 2, 3, Color("8fb7d9"))
	V.blob(vb, Vector3(2.5, y + 3, -3.5), Vector3(2.2, 1.4, 2.2), V.mix([Color("f59cc6"), Color("fbf7f0"), Color("ee7fb4"), Color("e2513f"), Color("5f9e3a")], 3), 0.4, 3)
	_pitcher(vb, 15, y, -6)
	_candle(vb, 20, y, -1)
	_bowl_big(vb, 24, y, 1, Color("e9c23a"), [Color("f4e04a"), Color("e8b53a"), Color("fff0a0")])
	# Chairs.
	for key in SEATS:
		var s: Vector3 = SEATS[key]
		_chair(vb, int(s.x), int(s.y), key)
	table_node = V.inst(vb, root, V.SIZE_FINE, TABLE_POS, TABLE_ROT, Vector3.ZERO, true, false, "DinnerTable")


func _bowl_big(vb: VoxelBuilder, x: int, y: int, z: int, food: Color, bits: Array) -> void:
	# Wide white serving bowl heaped with food (reads from across the yard).
	var white := Color("f1ede4")
	V.cyl(vb, x + 0.5, y, z + 0.5, 3.2, 1, white)
	V.cyl(vb, x + 0.5, y + 1, z + 0.5, 4.6, 2, white)
	V.cyl(vb, x + 0.5, y + 2, z + 0.5, 3.8, 1, V.mix([food, V.shade(food, 1.18), V.shade(food, 0.85)] + bits, x + 7))
	V.cyl(vb, x + 0.5, y + 3, z + 0.5, 2.6, 1, V.mix([food, V.shade(food, 1.18)] + bits, x + 3))
	V.p(vb, x, y + 4, z, bits[0])


func _burger_platter(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	# Long wooden board with six burgers (two rows of three), life-size.
	V.b(vb, x - 6, y, z - 3, 13, 1, 7, V.wood(WOOD_L, 0, 1))
	V.b(vb, x - 6, y, z - 3, 13, 1, 1, V.shade(WOOD, 0.9))
	for r in 2:
		for i in 3:
			var bx := x - 5 + i * 4
			var bz := z - 2 + r * 3
			V.b(vb, bx, y + 1, bz, 3, 1, 2, Color("5a2e18"))
			V.p(vb, bx + 2, y + 1, bz + 1, Color("f2c22a")); V.p(vb, bx, y + 1, bz + 1, Color("6cb04a"))
			V.b(vb, bx, y + 2, bz, 3, 1, 2, Color("e9b15e"))


func _candle(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x, y, z, 2, 3, 2, Color("ffcf6e"), true)
	V.p(vb, x, y + 3, z, Color("fff1c4"), true)


func _pitcher(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x, y, z, 2, 4, 2, Color("f6dc6a"))
	V.b(vb, x, y + 4, z, 2, 1, 2, Color("e9f3f6"))
	V.b(vb, x - 1, y + 1, z, 1, 2, 1, Color("e9f3f6"))
	V.p(vb, x + 1, y + 3, z + 1, Color("fff6c0"))


func _melon(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x - 1, y, z - 1, 9, 1, 4, Color("f6f3ee"))
	for i in 3:
		V.b(vb, x + i * 3, y + 1, z, 2, 3, 1, Color("e64a4a"))
		V.b(vb, x + i * 3, y + 1, z + 1, 2, 1, 1, Color("3c8a3a"))
		V.p(vb, x + i * 3, y + 2, z, Color("2a2a2a"))


func _corn_platter(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x, y, z, 7, 1, 5, Color("f6f3ee"))
	for i in 3:
		V.b(vb, x + 1, y + 1, z + 1 + i, 5, 1, 1, Color("f3d24a") if i != 1 else Color("e8c23a"))
		V.p(vb, x + 6, y + 1, z + 1 + i, Color("6cb04a"))


func _veggie_platter(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x, y, z, 7, 1, 5, Color("f6f3ee"))
	V.b(vb, x + 1, y + 1, z + 1, 5, 1, 3, V.mix([Color("e2513f"), Color("6cb04a"), Color("f2c22a"), Color("8fd05a"), Color("f07a3a")], 9))
	V.p(vb, x + 2, y + 2, z + 2, Color("e2513f")); V.p(vb, x + 4, y + 2, z + 1, Color("8fd05a"))


func _bread(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x, y, z, 5, 2, 4, V.wood(Color("c9944e"), 0, 1))
	V.b(vb, x, y + 2, z, 5, 1, 4, V.mix([Color("e8b56a"), Color("d9a050"), Color("f3cf8a")], 4))
	V.b(vb, x + 1, y + 3, z + 1, 3, 1, 2, Color("e8b56a"))


func _glass(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	# Tumbler of iced tea with an ice top (~19 cm tall).
	V.b(vb, x, y, z, 2, 2, 2, func(q: Vector3i) -> Color: return Color("f0a43a").lerp(Color("f7c35a"), V.h1(q, 5)))
	V.b(vb, x, y + 2, z, 2, 1, 2, Color("fff4dc"))


func _plate(vb: VoxelBuilder, x: int, y: int, z: int, food: int) -> void:
	# Round-ish 6x6 plate with a rim and a low, life-size serving (kept flat
	# so it never covers the diner's face behind it).
	var white := Color("f6f3ee")
	V.b(vb, x - 3, y, z - 2, 6, 1, 4, white)
	V.b(vb, x - 2, y, z - 3, 4, 1, 6, white)
	V.p(vb, x - 3, y + 1, z - 2, Color("e6e0d6")); V.p(vb, x + 2, y + 1, z + 1, Color("e6e0d6"))
	match food:
		0:  # burger
			V.b(vb, x - 1, y + 1, z - 1, 3, 1, 3, Color("5a2e18"))
			V.p(vb, x + 1, y + 1, z + 1, Color("f2c22a")); V.p(vb, x - 1, y + 1, z + 1, Color("6cb04a"))
			V.b(vb, x - 1, y + 2, z - 1, 3, 1, 3, Color("e9b15e"))
			V.p(vb, x - 2, y + 1, z + 1, Color("e2513f"))
		1:  # corn cob + salad
			V.b(vb, x - 2, y + 1, z - 1, 4, 1, 1, Color("f3d24a"))
			V.p(vb, x + 2, y + 1, z - 1, Color("6cb04a"))
			V.b(vb, x - 1, y + 1, z + 1, 2, 1, 2, Color("6cb04a")); V.p(vb, x, y + 1, z + 1, Color("e2513f"))
		2:  # hot dog + tomato
			V.b(vb, x - 2, y + 1, z - 1, 4, 1, 2, Color("e0a456"))
			V.b(vb, x - 2, y + 1, z, 4, 1, 1, Color("a2412a"))
			V.p(vb, x - 1, y + 1, z, Color("f2c22a"))
			V.p(vb, x + 1, y + 1, z + 1, Color("e2513f"))
		_:  # salad heap
			V.b(vb, x - 2, y + 1, z - 1, 4, 1, 3, V.mix([Color("6cb04a"), Color("8fd05a"), Color("4f9a3a")], 6))
			V.p(vb, x - 1, y + 1, z, Color("e2513f")); V.p(vb, x + 1, y + 1, z, Color("f2c22a"))


func _bowl(vb: VoxelBuilder, x: int, y: int, z: int, food: Color, bits: Array) -> void:
	V.b(vb, x - 2, y, z - 2, 5, 1, 5, Color("f1ede4"))
	V.b(vb, x - 3, y + 1, z - 2, 7, 2, 5, Color("f1ede4"))
	V.b(vb, x - 2, y + 1, z - 3, 5, 2, 7, Color("f1ede4"))
	V.b(vb, x - 2, y + 2, z - 2, 5, 1, 5, V.mix([food, V.shade(food, 1.15)] + bits, x))


func _burger_board(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	V.b(vb, x - 4, y, z - 2, 9, 1, 5, V.wood(WOOD_L, 0, 1))
	for i in 3:
		var bx := x - 3 + i * 3
		V.b(vb, bx, y + 1, z - 1, 2, 1, 2, Color("e0a456"))
		V.b(vb, bx, y + 2, z - 1, 2, 1, 2, Color("6b3a1f"))
		V.p(vb, bx, y + 2, z + 1, Color("f2c22a"))
		V.b(vb, bx, y + 3, z - 1, 2, 1, 2, Color("e9b15e"))


func _chair(vb: VoxelBuilder, cx: int, cz: int, key: String) -> void:
	# Farmhouse chair: seat top at y = 7 (0.4375 m), slatted seat, back on
	# the side away from the table with a top rail and two vertical
	# spindles so it reads as a chair (not a block) around each diner.
	var c := WOOD
	var seat := V.wood(c, 0, 2)
	var x0 := cx - 4
	var z0 := cz - 4
	var dark := V.shade(WOOD_D, 0.85)
	for q in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 7), Vector2i(7, 7)]:
		V.b(vb, x0 + q.x, 0, z0 + q.y, 1, 6, 1, WOOD_D)
	# Stretchers between the legs.
	V.b(vb, x0, 2, z0 + 1, 1, 1, 6, dark); V.b(vb, x0 + 7, 2, z0 + 1, 1, 1, 6, dark)
	V.b(vb, x0 + 1, 6, z0, 6, 1, 8, dark)
	# Slatted seat: planks with a darker gap.
	for i in 8:
		V.b(vb, x0 + i, 6, z0, 1, 1, 8, seat if i % 3 != 2 else V.shade(WOOD_D, 1.05))
	if BOOSTED.has(key):
		var cc: Color = BOOSTED[key]
		V.b(vb, x0 + 1, 7, z0 + 1, 6, 3, 6, func(q: Vector3i) -> Color:
			return V.shade(cc, 0.92 + V.h1(q, 4) * 0.12) if q.y < 9 else V.shade(cc, 1.08))
	var back_axis_x := key.begins_with("end")
	var top := 17
	if back_axis_x:
		var bx := x0 if key == "end_l" else x0 + 7
		V.b(vb, bx, 7, z0, 1, top - 7, 1, dark); V.b(vb, bx, 7, z0 + 7, 1, top - 7, 1, dark)
		V.b(vb, bx, top - 2, z0, 1, 2, 8, seat)
		V.b(vb, bx, 9, z0 + 1, 1, 1, 6, seat)
		for sz in [2, 5]:
			V.b(vb, bx, 10, z0 + sz, 1, top - 12, 1, V.shade(WOOD, 0.92))
	else:
		var bz := z0 if cz < 0 else z0 + 7
		V.b(vb, x0, 7, bz, 1, top - 7, 1, dark); V.b(vb, x0 + 7, 7, bz, 1, top - 7, 1, dark)
		V.b(vb, x0, top - 2, bz, 8, 2, 1, seat)
		V.p(vb, x0, top, bz, dark); V.p(vb, x0 + 7, top, bz, dark)
		V.b(vb, x0 + 1, 9, bz, 6, 1, 1, seat)
		for sx in [2, 5]:
			V.b(vb, x0 + sx, 10, bz, 1, top - 12, 1, V.shade(WOOD, 0.92))


# ------------------------------------------------------------------ grill

func _grill() -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	var steel := Color("9aa0a8")
	# Cart legs + wheels.
	for q in [Vector2i(-9, -5), Vector2i(8, -5), Vector2i(-9, 3), Vector2i(8, 3)]:
		V.b(vb, q.x, 0, q.y, 1, 3, 1, IRON)
	# Cabinet.
	V.b(vb, -10, 2, -6, 20, 11, 10, V.noisy(IRON, 0.05))
	V.b(vb, -9, 4, 4, 8, 8, 1, Color("34353c")); V.b(vb, 1, 4, 4, 8, 8, 1, Color("34353c"))
	V.b(vb, -2, 8, 5, 1, 3, 1, steel); V.b(vb, 1, 8, 5, 1, 3, 1, steel)
	# Control panel + knobs.
	V.b(vb, -10, 13, 4, 20, 2, 1, Color("3a3b42"))
	for k in 4:
		V.p(vb, -7 + k * 4, 13, 5, Color("c9ccd2"))
	# Firebox.
	V.b(vb, -10, 13, -6, 20, 3, 10, IRON)
	# Glowing coals + grate.
	V.b(vb, -9, 15, -5, 18, 1, 8, func(q: Vector3i) -> Color:
		return Color("ff7a2a").lerp(Color("ffcf5a"), V.h1(q, 2)), true)
	for gz in [-5, -3, -1, 1]:
		V.b(vb, -9, 16, gz, 18, 1, 1, Color("45464c"))
	# Food on the grate: thick patties, sausages and corn cobs.
	for i in 4:
		var px := -8 + i * 4
		V.b(vb, px, 17, -4, 3, 1, 3, V.mix([Color("9a5a2e"), Color("8a4a26"), Color("a8663a")], i))
		V.b(vb, px, 17, -3, 3, 1, 1, Color("4a2414"))
		if i % 2 == 0:
			V.b(vb, px, 18, -4, 3, 1, 3, Color("f7cf3e"))
			V.p(vb, px + 2, 18, -2, Color("ffe07a"))
	for i in 3:
		V.b(vb, -7 + i * 3, 17, 1, 2, 2, 1, Color("a2512e"))
		V.b(vb, -7 + i * 3, 17, 2, 2, 1, 1, Color("8a4426"))
	for cx in [4, 6, 8]:
		V.b(vb, cx, 17, -1, 1, 2, 4, func(q: Vector3i) -> Color: return Color("f3d24a") if (q.z + q.y) % 2 == 0 else Color("e2b432"))
		V.p(vb, cx, 17, 3, Color("6cb04a"))
	# Open lid, flipped down over the back of the firebox (faces the camera,
	# so the grate and food stay visible).
	V.b(vb, -10, 7, -8, 20, 9, 2, V.noisy(IRON, 0.05))
	V.b(vb, -6, 9, -9, 12, 1, 1, steel)
	V.b(vb, -9, 11, -9, 18, 1, 1, V.shade(IRON, 1.3))
	V.p(vb, 0, 13, -9, Color("e8e8ea"))
	# Side shelves.
	V.b(vb, -17, 13, -5, 7, 1, 9, V.wood(WOOD, 0, 2))
	V.b(vb, 10, 13, -5, 7, 1, 9, V.wood(WOOD, 0, 2))
	# Plate of buns + tongs.
	V.b(vb, 11, 14, -3, 5, 1, 5, Color("f6f3ee"))
	for bq in [Vector2i(11, -3), Vector2i(13, -2), Vector2i(12, 0)]:
		V.b(vb, bq.x, 15, bq.y, 2, 1, 2, Color("e0a456"))
	V.b(vb, -16, 14, -3, 5, 1, 1, steel)
	V.b(vb, -16, 14, 0, 4, 2, 2, Color("d02a24"))
	grill_node = V.inst(vb, root, V.SIZE_FINE, GRILL_POS, GRILL_ROT, Vector3.ZERO, true, true, "Grill")
	# Real-world kettle-cart height (~0.9 m to the grate) so Jack's chest
	# and arms read above it.
	grill_node.scale = Vector3.ONE * 0.86
	coal_light = V.omni(grill_node, Vector3(0, 1.05, -0.35), Color(1.0, 0.62, 0.35), 0.45, 2.2)
	# Smoke.
	smoke = CPUParticles3D.new()
	smoke.name = "Smoke"
	# Rises off the right end of the grate (between Jack and the table) and
	# drifts back, so it never veils his face.
	smoke.position = Vector3(0.38, 1.15, -0.05)
	smoke.amount = 44
	smoke.lifetime = 4.0
	smoke.preprocess = 4.0
	smoke.local_coords = false
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(0.3, 0.02, 0.12)
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.03, 0.26, -0.1)
	smoke.initial_velocity_min = 0.25
	smoke.initial_velocity_max = 0.45
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 1.7
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.86, 0.84, 0.88, 0.78))
	grad.set_color(1, Color(0.66, 0.62, 0.74, 0.0))
	smoke.color_ramp = grad
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.2
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	bm.material = mat
	smoke.mesh = bm
	smoke.rotation = Vector3(0, 0, 0)
	grill_node.add_child(smoke)


# ------------------------------------------------------------------ yard props (world fine grid)

func _prep_table(vb: VoxelBuilder, x: int, z: int) -> void:
	# Wooden prep table with condiments, platter and a mini lantern.
	for q in [Vector2i(0, 0), Vector2i(18, 0), Vector2i(0, 8), Vector2i(18, 8)]:
		V.b(vb, x + q.x, 0, z + q.y, 1, 13, 1, WOOD_D)
	V.b(vb, x, 13, z, 19, 1, 9, V.wood(WOOD, 0, 2))
	V.b(vb, x + 1, 4, z + 1, 17, 1, 7, V.wood(WOOD_D, 0, 2))
	V.b(vb, x + 2, 5, z + 2, 5, 3, 4, Color("6f9fd0"))  # cooler
	V.b(vb, x + 2, 8, z + 2, 5, 1, 4, Color("f1ede4"))
	V.b(vb, x + 2, 14, z + 2, 1, 5, 1, Color("d02a24")); V.p(vb, x + 2, 19, z + 2, Color("f2f2f2"))
	V.b(vb, x + 4, 14, z + 2, 1, 5, 1, Color("f2c22a")); V.p(vb, x + 4, 19, z + 2, Color("f2f2f2"))
	V.b(vb, x + 3, 14, z + 4, 1, 4, 1, Color("5a8a3a"))
	V.b(vb, x + 7, 14, z + 2, 7, 1, 5, Color("f6f3ee"))
	for i in 3:
		V.b(vb, x + 8 + i * 2, 15, z + 3, 2, 1, 2, Color("6b3a1f"))
		V.p(vb, x + 8 + i * 2, 16, z + 3, Color("f2c22a"))
	V.b(vb, x + 15, 14, z + 5, 2, 3, 2, Color("ffcf6e"), true)


func _fire_pit(vb: VoxelBuilder, cx: int, cz: int) -> void:
	var r := 10
	for x in range(-r, r):
		for z in range(-r, r):
			var inner := absi(x + 0) < r - 3 and absi(z) < r - 3 and x > -r + 2 and z > -r + 2
			if inner:
				continue
			for y in 6:
				var q := Vector3i(cx + x, y, cz + z)
				var brick := Vector3i((x + (3 if y % 2 == 0 else 0)) / 4 + 50, y / 2, (z + (3 if y % 2 == 0 else 0)) / 4 + 50)
				var c := V.shade(Color("8e8a86"), 0.78 + V.h1(brick, 3) * 0.35)
				if (x + (3 if y % 2 == 0 else 0)) % 4 == 0 and V.h1(q, 4) < 0.5:
					c = V.shade(c, 0.85)
				vb.set_v(q, c)
			# Cap stones.
			vb.set_v(Vector3i(cx + x, 6, cz + z), V.shade(Color("b2aca4"), 0.9 + V.h1(Vector3i(x / 3, 6, z / 3), 5) * 0.2))
	# Logs.
	V.b(vb, cx - 5, 2, cz - 1, 10, 2, 2, Color("6b4228"))
	V.b(vb, cx - 1, 3, cz - 5, 2, 2, 10, Color("5a3620"))
	# Embers.
	V.b(vb, cx - 6, 1, cz - 6, 12, 1, 12, func(q: Vector3i) -> Color:
		return Color("ff6a1e").lerp(Color("2a1a14"), V.h1(q, 9) * 0.6), true)
	# Flames: a cluster of flickering tongues (hot core, orange skin, red tips).
	var tongues := [Vector3(0, 0, 0), Vector3(-2.5, 0, 1.5), Vector3(2.0, 0, -1.5), Vector3(1.5, 0, 2.5), Vector3(-2.0, 0, -2.0), Vector3(3.0, 0, 1.0)]
	for i in tongues.size():
		var tp: Vector3 = tongues[i]
		var th := 11 - i - (i % 2) * 2
		var r0 := 2.2 - i * 0.15
		for y in range(3, 3 + th):
			var f := float(y - 3) / th
			var rad := r0 * (1.0 - f * 0.85)
			var sway := sin(f * 3.0 + i) * 0.9 * f
			for x in range(-4, 5):
				for z in range(-4, 5):
					var dx := x + 0.5 - tp.x - sway
					var dz := z + 0.5 - tp.z
					var d := sqrt(dx * dx + dz * dz)
					var q := Vector3i(cx + x + int(tp.x), y, cz + z + int(tp.z))
					if d > rad + (V.h1(q, 12) - 0.5) * 0.8:
						continue
					var c := Color("ffb63a").lerp(Color("ff5a10"), clampf(d / maxf(rad, 0.3) * 1.1 + f * 0.9, 0.0, 1.0))
					if f > 0.4:
						c = c.lerp(Color("c8281a"), (f - 0.4) * 1.5)
					c = V.shade(c, 0.66)
					vb.set_v(q, c, true)
	# Sparks.
	for i in 3:
		vb.set_v(Vector3i(cx - 2 + i * 2, 15 + (i * 7) % 4, cz + (i * 5) % 5 - 2), Color("ffb04a"), true)


func _sofa(vb: VoxelBuilder, x: int, z: int) -> void:
	# Outdoor lounge: long section along Z facing -X, plus return along X at the front.
	var base := Color("8f8a84")
	var cush := Color("dcd6cc")
	var len := 44
	V.b(vb, x, 0, z - len / 2, 14, 5, len, base)
	V.b(vb, x + 2, 5, z - len / 2 + 2, 12, 3, len - 4, cush)
	V.b(vb, x + 9, 5, z - len / 2, 5, 13, len, base)
	V.b(vb, x + 7, 8, z - len / 2 + 2, 3, 9, len - 4, cush)
	V.b(vb, x, 5, z - len / 2, 14, 5, 2, base)
	V.b(vb, x, 5, z + len / 2 - 2, 14, 5, 2, base)
	# Seam lines between cushions.
	for k in [1, 2]:
		V.b(vb, x + 2, 7, z - len / 2 + 2 + k * 13, 8, 1, 1, V.shade(cush, 0.8))
	# Throw pillows.
	V.b(vb, x + 5, 8, z - 16, 2, 6, 6, Color("6f86a8"))
	V.b(vb, x + 5, 8, z + 1, 2, 6, 6, Color("e2b456"))
	V.b(vb, x + 5, 8, z + 12, 2, 6, 6, Color("e78a6f"))
	# Folded blanket.
	V.b(vb, x + 1, 8, z + 16, 7, 1, 4, V.mix([Color("c8443c"), Color("f3e3c3")], 2))


func _side_table(vb: VoxelBuilder, x: int, z: int) -> void:
	V.cyl(vb, x, 0, z, 3.5, 8, V.wood(WOOD, 1, 2))
	V.b(vb, x - 2, 8, z - 1, 2, 3, 2, Color("f0a43a"))
	V.b(vb, x + 1, 8, z, 2, 3, 2, Color("e64a4a"))


func _lantern(vb: VoxelBuilder, x: int, y: int, z: int, _s: float) -> void:
	V.b(vb, x, y, z, 7, 1, 7, IRON)
	for q in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 6), Vector2i(6, 6)]:
		V.b(vb, x + q.x, y + 1, z + q.y, 1, 9, 1, IRON)
	V.b(vb, x + 1, y + 1, z + 1, 5, 9, 5, func(q: Vector3i) -> Color:
		var t := float(q.y - y) / 9.0
		return Color("ffb84a").lerp(Color("fff0b0"), 1.0 - absf(t - 0.4) * 1.6), true)
	V.b(vb, x, y + 10, z, 7, 1, 7, IRON)
	V.b(vb, x + 1, y + 11, z + 1, 5, 1, 5, IRON)
	V.b(vb, x + 2, y + 12, z + 2, 3, 1, 3, IRON)
	V.b(vb, x + 3, y + 13, z + 3, 1, 2, 1, IRON)


const POSTS := [Vector3(-5.6, 3.6, -3.6), Vector3(-0.6, 3.9, -3.4), Vector3(7.6, 3.8, -0.8)]
const PORCH_POSTS := [Vector3(1.69, 3.5, -2.6), Vector3(6.81, 3.5, -2.6), Vector3(12.81, 3.5, -2.6)]


func _posts(vb: VoxelBuilder) -> void:
	for p in POSTS:
		var x := int(p.x * F)
		var z := int(p.z * F)
		var h := int(p.y * F) + 1
		V.b(vb, x - 1, 0, z - 1, 3, h, 3, V.wood(Color("7a4c2c"), 1, 1))
		V.b(vb, x - 2, 0, z - 2, 5, 3, 5, Color("8e8a86"))
		V.b(vb, x - 1, h, z - 1, 3, 1, 3, Color("5a3620"))


func _strand(vb: VoxelBuilder, a: Vector3, b: Vector3, sag: float, spacing := 0.62) -> void:
	var length := a.distance_to(b)
	var steps := int(length * F * 1.6)
	var next_bulb := 0.2
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		var q := Vector3i(floori(p.x * F), floori(p.y * F), floori(p.z * F))
		vb.set_v(q, Color("2a2622"))
		if t * length >= next_bulb and t * length < length - 0.15:
			next_bulb += spacing
			vb.set_v(q + Vector3i(0, -1, 0), Color("3a3530"))
			# Pear-shaped Edison bulb under a dark socket: amber skin, hot
			# core, rounded tip (big enough to read as bulbs from the yard).
			V.b(vb, q.x, q.y - 2, q.z, 1, 1, 1, Color("2a2622"))
			V.b(vb, q.x - 1, q.y - 3, q.z - 1, 3, 1, 3, Color("3a3530"))
			V.b(vb, q.x - 1, q.y - 6, q.z - 1, 3, 3, 3, Color("ffc35a"), true)
			V.b(vb, q.x - 1, q.y - 5, q.z, 3, 1, 1, Color("fff0c0"), true)
			V.b(vb, q.x, q.y - 5, q.z - 1, 1, 1, 3, Color("fff0c0"), true)
			V.b(vb, q.x, q.y - 7, q.z, 1, 1, 1, Color("ffd27a"), true)
			halos.add(Vector3((q.x + 0.5) / F, (q.y - 4.5) / F, (q.z + 0.5) / F), 0.8, Color(1.0, 0.66, 0.28, 0.95))


func _string_lights(vb: VoxelBuilder) -> void:
	var p0: Vector3 = POSTS[0]
	var p1: Vector3 = POSTS[1]
	var p2: Vector3 = POSTS[2]
	_strand(vb, Vector3(-13.0, 3.2, -2.6), p0, 0.5)
	_strand(vb, p0, p1, 0.55)
	_strand(vb, p1, PORCH_POSTS[0], 0.25)
	_strand(vb, p1, p2, 0.6)
	_strand(vb, PORCH_POSTS[0], PORCH_POSTS[1], 0.1)
	_strand(vb, PORCH_POSTS[1], PORCH_POSTS[2], 0.1)
