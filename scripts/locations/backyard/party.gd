extends RefCounted
## The party set: long dinner table (red gingham cloth, food, drinks, candle
## jars) with wooden chairs, the gas grill with smoke, a prep table, stone fire
## pit, outdoor lounge sofa, lanterns and the string lights on posts.

const V := preload("res://scripts/locations/backyard/vox.gd")
const F := 16

const WOOD := Color("b07a46")
const WOOD_D := Color("7d4f2b")
const WOOD_L := Color("c99462")
const IRON := Color("2b2b31")
const BULB := Color("ffd889")

## World placement of the main pieces.
const TABLE_POS := Vector3(0.9, 0.0, 0.5)
const TABLE_ROT := 0.30
const GRILL_POS := Vector3(-2.9, 0.0, 0.0)
const GRILL_ROT := 2.3
const PIT_POS := Vector3(4.1, 0.0, 2.4)

## Seats in table-local cells: Vector3(x, z, unused) — facing is derived in _facing().
const SEATS := {
	"far_l": Vector3(-17, -15, 0.0),
	"far_m": Vector3(1, -15, 0.0),
	"far_r": Vector3(19, -15, 0.0),
	"near_l": Vector3(-8, 15, PI),
	"near_m": Vector3(10, 15, PI),
	"near_r": Vector3(25, 15, PI),
	"end_l": Vector3(-36, 0, PI * 0.5),
	"end_r": Vector3(36, 0, -PI * 0.5),
}

var root: Node3D
var table_node: Node3D
var grill_node: Node3D
var pit_light: OmniLight3D
var coal_light: OmniLight3D
var smoke: CPUParticles3D
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
	_sofa(yard, 100, 28)
	_side_table(yard, 96, 8)
	for lp in [Vector3i(-66, 0, 14), Vector3i(24, 0, -38), Vector3i(122, 0, -10), Vector3i(-88, 0, -58), Vector3i(150, 0, 50)]:
		_lantern(yard, lp.x, lp.y, lp.z, 1.0)
	_posts(yard)
	# Planters around the lounge and the patio.
	for pp in [Vector3i(94, 0, -10), Vector3i(92, 0, 66), Vector3i(-50, 0, -60), Vector3i(-96, 0, -20), Vector3i(60, 0, -30)]:
		V.flower_pot(yard, pp.x, pp.y, pp.z, pp.x * 3 + pp.z, true)
	V.inst(yard, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "YardProps")
	var lights := VoxelBuilder.new()
	lights.jitter = 0.02
	_string_lights(lights)
	V.inst(lights, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, false, true, "StringLights")
	# Light sources.
	pit_light = V.omni(root, PIT_POS + Vector3(0, 0.75, 0), Color(1.0, 0.55, 0.22), 2.6, 5.5)
	V.omni(root, Vector3(-3.9, 0.7, 1.1), Color(1.0, 0.7, 0.4), 1.2, 3.5)
	V.omni(root, Vector3(-1.0, 2.6, -1.0), Color(1.0, 0.78, 0.5), 1.1, 6.5)
	V.omni(root, Vector3(3.6, 2.6, 0.2), Color(1.0, 0.78, 0.5), 0.9, 6.0)


func world_seat(key: String) -> Transform3D:
	var s: Vector3 = SEATS[key]
	var tb := Transform3D(Basis(Vector3.UP, TABLE_ROT), TABLE_POS)
	var p := tb * Vector3(s.x / F, 0.0, s.y / F)
	return Transform3D(Basis(Vector3.UP, TABLE_ROT + _facing(s)), p)


func _facing(s: Vector3) -> float:
	# Face the table centre line.
	if absf(s.x) > 30.0:
		return PI * 0.5 if s.x < 0 else -PI * 0.5
	return 0.0 if s.y < 0 else PI


func grill_front() -> Vector3:
	return GRILL_POS + Basis(Vector3.UP, GRILL_ROT) * Vector3(0, 0, 0.62)


func process(t: float) -> void:
	if pit_light:
		pit_light.light_energy = 2.4 + sin(t * 11.0) * 0.25 + sin(t * 23.7) * 0.15
	if coal_light:
		coal_light.light_energy = 1.0 + sin(t * 9.0) * 0.12


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
	# Legs + apron.
	for q in [Vector2i(-27, -9), Vector2i(25, -9), Vector2i(-27, 7), Vector2i(25, 7)]:
		V.b(vb, q.x, 0, q.y, 2, 11, 2, WOOD_D)
	V.b(vb, -28, 11, -10, 56, 1, 20, V.wood(WOOD, 0, 2))
	# Cloth: top + drape.
	V.b(vb, -29, 12, -11, 58, 1, 22, func(q: Vector3i) -> Color: return _gingham(q.x, q.z))
	V.b(vb, -29, 8, -11, 58, 4, 1, func(q: Vector3i) -> Color: return _gingham(q.x, q.y))
	V.b(vb, -29, 8, 10, 58, 4, 1, func(q: Vector3i) -> Color: return _gingham(q.x, q.y))
	V.b(vb, -29, 8, -11, 1, 4, 22, func(q: Vector3i) -> Color: return _gingham(q.z, q.y))
	V.b(vb, 28, 8, -11, 1, 4, 22, func(q: Vector3i) -> Color: return _gingham(q.z, q.y))
	var y := 13
	# Place settings.
	for key in SEATS:
		var s: Vector3 = SEATS[key]
		var px := int(s.x)
		var pz := int(s.y)
		if absf(s.x) > 30.0:
			px = -24 if s.x < 0 else 23
			pz = -2
		else:
			pz = -8 if s.y < 0 else 5
		_plate(vb, px, y, pz, int(V.hs(px, pz, 1) * 4.0))
		# Drink.
		var gx := px + 3
		var gz := pz + (2 if s.y < 0 else -1)
		V.b(vb, gx, y, gz, 2, 4, 2, Color("f0a43a"))
		V.b(vb, gx, y + 4, gz, 2, 1, 2, Color("fff4dc"))
	# Centre dishes.
	_bowl(vb, -10, y, -1, Color("6cb04a"), [Color("e2513f"), Color("f7d84a"), Color("8fd05a")])
	_burger_board(vb, 5, y, -2)
	_bowl(vb, 17, y, 0, Color("e9c23a"), [Color("f4e04a"), Color("e8b53a")])
	_burger_board(vb, -19, y, 1)
	# Corn platter.
	V.b(vb, 9, y, 2, 6, 1, 4, Color("f6f3ee"))
	for i in 3:
		V.b(vb, 10, y + 1, 2 + i, 4, 1, 1, Color("f3d24a") if i != 1 else Color("e8c23a"))
	# Watermelon slices.
	for i in 4:
		V.b(vb, -4 + i * 3, y, 2, 2, 2, 1, Color("e64a4a"))
		V.b(vb, -4 + i * 3, y, 3, 2, 1, 1, Color("3c8a3a"))
	# Ketchup + mustard.
	V.b(vb, -3, y, 1, 1, 4, 1, Color("d02a24")); V.p(vb, -3, y + 4, 1, Color("f2f2f2"))
	V.b(vb, -2, y, 1, 1, 4, 1, Color("f2c22a")); V.p(vb, -2, y + 4, 1, Color("f2f2f2"))
	# Candle jars (glow).
	for cx in [-14, 11, 23]:
		V.b(vb, cx, y, -1, 2, 2, 2, Color("ffcf6e"), true)
		V.p(vb, cx, y + 2, -1, Color("fff1c4"), true)
	# Flower vase.
	V.b(vb, -1, y, -3, 2, 4, 2, Color("8fb7d9"))
	V.blob(vb, Vector3(0, y + 6, -2), Vector3(2.4, 1.8, 2.4), V.mix([Color("f59cc6"), Color("fbf7f0"), Color("ee7fb4"), Color("5f9e3a")], 3), 0.4, 3)
	# Chairs.
	for key in SEATS:
		var s: Vector3 = SEATS[key]
		_chair(vb, int(s.x), int(s.y), key)
	table_node = V.inst(vb, root, V.SIZE_FINE, TABLE_POS, TABLE_ROT, Vector3.ZERO, true, false, "DinnerTable")


func _plate(vb: VoxelBuilder, x: int, y: int, z: int, food: int) -> void:
	V.b(vb, x - 2, y, z - 1, 4, 1, 3, Color("f6f3ee"))
	V.b(vb, x - 1, y, z - 2, 2, 1, 5, Color("f6f3ee"))
	match food:
		0:  # burger
			V.b(vb, x - 1, y + 1, z - 1, 2, 1, 2, Color("6b3a1f"))
			V.p(vb, x - 1, y + 1, z + 1, Color("6cb04a"))
			V.b(vb, x - 1, y + 2, z - 1, 2, 1, 2, Color("e0a456"))
		1:  # corn + salad
			V.b(vb, x - 2, y + 1, z, 3, 1, 1, Color("f3d24a"))
			V.p(vb, x + 1, y + 1, z - 1, Color("6cb04a"))
		2:  # sausage + tomato
			V.b(vb, x - 1, y + 1, z - 1, 3, 1, 1, Color("9a4a2a"))
			V.p(vb, x, y + 1, z + 1, Color("e2513f"))
		_:  # salad
			V.p(vb, x - 1, y + 1, z, Color("6cb04a")); V.p(vb, x, y + 1, z - 1, Color("8fd05a")); V.p(vb, x, y + 1, z, Color("e2513f"))


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
	# Seat top at y = 7 (0.4375 m). Back on the side away from the table.
	var c := WOOD
	var seat := V.wood(c, 0, 2)
	var x0 := cx - 4
	var z0 := cz - 4
	for q in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 7), Vector2i(7, 7)]:
		V.b(vb, x0 + q.x, 0, z0 + q.y, 1, 6, 1, WOOD_D)
	V.b(vb, x0, 6, z0, 8, 1, 8, seat)
	var back_axis_x := key.begins_with("end")
	if back_axis_x:
		var bx := x0 if key == "end_l" else x0 + 7
		V.b(vb, bx, 7, z0, 1, 10, 1, WOOD_D); V.b(vb, bx, 7, z0 + 7, 1, 10, 1, WOOD_D)
		V.b(vb, bx, 15, z0, 1, 2, 8, seat)
		for k in 3:
			V.b(vb, bx, 8, z0 + 2 + k * 2, 1, 7, 1, seat)
	else:
		var bz := z0 if cz < 0 else z0 + 7
		V.b(vb, x0, 7, bz, 1, 10, 1, WOOD_D); V.b(vb, x0 + 7, 7, bz, 1, 10, 1, WOOD_D)
		V.b(vb, x0, 15, bz, 8, 2, 1, seat)
		for k in 3:
			V.b(vb, x0 + 2 + k * 2, 8, bz, 1, 7, 1, seat)


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
	# Food on the grate.
	for i in 4:
		var px := -8 + i * 4
		V.b(vb, px, 17, -4, 3, 1, 3, V.mix([Color("6b3a1f"), Color("5a2e18"), Color("7b4526")], i))
	for i in 3:
		V.b(vb, -7 + i * 3, 17, 1, 2, 1, 1, Color("a2512e"))
		V.b(vb, -7 + i * 3, 17, 2, 2, 1, 1, Color("8a4426"))
	V.b(vb, 6, 17, 0, 1, 1, 3, Color("f3d24a")); V.b(vb, 8, 17, 0, 1, 1, 3, Color("f3d24a"))
	V.p(vb, 6, 17, 3, Color("6cb04a")); V.p(vb, 8, 17, 3, Color("6cb04a"))
	# Open lid behind.
	V.b(vb, -10, 16, -7, 20, 11, 1, V.noisy(IRON, 0.05))
	V.b(vb, -9, 27, -7, 18, 1, 1, IRON)
	V.b(vb, -6, 22, -8, 12, 1, 1, steel)
	V.p(vb, 0, 25, -6, Color("e8e8ea"))
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
	coal_light = V.omni(grill_node, Vector3(0, 1.3, 0.1), Color(1.0, 0.55, 0.25), 1.0, 3.0)
	# Smoke.
	smoke = CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = Vector3(0, 1.15, -0.05)
	smoke.amount = 30
	smoke.lifetime = 3.2
	smoke.preprocess = 3.2
	smoke.local_coords = false
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(0.45, 0.02, 0.2)
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.12, 0.25, 0.0)
	smoke.initial_velocity_min = 0.25
	smoke.initial_velocity_max = 0.45
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.86, 0.88, 0.6))
	grad.set_color(1, Color(0.8, 0.75, 0.85, 0.0))
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
					var c := Color("ffc24a").lerp(Color("ff6a14"), clampf(d / maxf(rad, 0.3) * 0.9 + f * 0.7, 0.0, 1.0))
					if f > 0.5:
						c = c.lerp(Color("d8301a"), (f - 0.5) * 1.6)
					c = V.shade(c, 0.8)
					vb.set_v(q, c, true)
	# Sparks.
	for i in 6:
		vb.set_v(Vector3i(cx - 3 + i, 18 + (i * 7) % 5, cz + (i * 5) % 7 - 3), Color("ffcf5a"), true)


func _sofa(vb: VoxelBuilder, x: int, z: int) -> void:
	# Outdoor lounge: long section along Z facing -X, plus return along X at the front.
	var base := Color("8f8a84")
	var cush := Color("dcd6cc")
	var len := 44
	V.b(vb, x, 0, z - len / 2, 14, 5, len, V.noisy(base, 0.06))
	V.b(vb, x + 2, 5, z - len / 2 + 2, 12, 3, len - 4, V.noisy(cush, 0.04))
	V.b(vb, x + 9, 5, z - len / 2, 5, 13, len, V.noisy(base, 0.06))
	V.b(vb, x + 7, 8, z - len / 2 + 2, 3, 9, len - 4, V.noisy(cush, 0.04))
	V.b(vb, x, 5, z - len / 2, 14, 5, 2, V.noisy(base, 0.06))
	V.b(vb, x, 5, z + len / 2 - 2, 14, 5, 2, V.noisy(base, 0.06))
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


const POSTS := [Vector3(-5.6, 3.1, -3.6), Vector3(-0.6, 3.2, -3.4), Vector3(7.6, 3.0, -0.8)]
const PORCH_POSTS := [Vector3(1.69, 3.15, -2.69), Vector3(6.81, 3.15, -2.69), Vector3(12.81, 3.15, -2.69)]


func _posts(vb: VoxelBuilder) -> void:
	for p in POSTS:
		var x := int(p.x * F)
		var z := int(p.z * F)
		var h := int(p.y * F) + 1
		V.b(vb, x - 1, 0, z - 1, 3, h, 3, V.wood(Color("7a4c2c"), 1, 1))
		V.b(vb, x - 2, 0, z - 2, 5, 3, 5, Color("8e8a86"))
		V.b(vb, x - 1, h, z - 1, 3, 1, 3, Color("5a3620"))


func _strand(vb: VoxelBuilder, a: Vector3, b: Vector3, sag: float, spacing := 0.42) -> void:
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
			V.b(vb, q.x - 1, q.y - 4, q.z - 1, 3, 3, 3, BULB, true)
			V.b(vb, q.x, q.y - 5, q.z, 1, 1, 1, BULB, true)


func _string_lights(vb: VoxelBuilder) -> void:
	var p0: Vector3 = POSTS[0]
	var p1: Vector3 = POSTS[1]
	var p2: Vector3 = POSTS[2]
	_strand(vb, Vector3(-13.0, 3.0, -2.6), p0, 0.5)
	_strand(vb, p0, p1, 0.55)
	_strand(vb, p1, PORCH_POSTS[0], 0.35)
	_strand(vb, p1, p2, 0.9)
	_strand(vb, PORCH_POSTS[0], PORCH_POSTS[1], 0.35)
	_strand(vb, PORCH_POSTS[1], PORCH_POSTS[2], 0.4)
