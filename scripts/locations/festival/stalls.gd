extends RefCounted
## Market stalls: "FALL TREATS" food stall, festival game booth, handmade
## crafts table, striped side stalls and chalkboard A-frame signs.
## Authored in 1/16 m cells, each model centred on its footprint, front +Z.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

const WOOD := Color("a5693a")
const WOOD_D := Color("7a4a28")
const WOOD_L := Color("c98d55")
const CREAM := Color("f6efe0")
const RED := Color("d43a2c")
const BLUE := Color("3f6fc4")

var treats: Node3D
var game: Node3D
var crafts: Node3D
var glow_points: Array = []   # [pos, size, color] for halos
var vendor_spot := Vector3.ZERO   # world, behind the FALL TREATS counter
var _off := Vector3.ZERO           # cell offset of the last placed model


func _lp(cell: Vector3) -> Vector3:
	return (cell - _off) * U


func build(parent: Node3D) -> void:
	# Layout (round 5): FALL TREATS on the left edge, game booth just right
	# of the central walkway, crafts table bottom-right, striped side stalls
	# receding along the right side. The walkway from the camera to the
	# fountain (x -1.5..1.5) stays open cobblestone.
	treats = _place(parent, "TreatsStall", _treats_stall(), Vector3(-4.9, 0, -2.0), 28.0)
	var sc := Vector3(TW * 0.5 + 4.5, (SIGN_Y0 + SIGN_Y1) * 0.5 - 0.3, TD + 1.06)
	_sign(treats, "FALL TREATS", _lp(sc), 0.0031, 0.0)
	vendor_spot = treats.transform * _lp(Vector3(16.0, 0.0, TD - 14.0))
	game = _place(parent, "GameStall", _game_stall(), Vector3(2.6, 0, -3.4), -14.0)
	crafts = _place(parent, "CraftsStall", _crafts_table(), Vector3(5.8, 0, 1.6), -30.0)
	_place(parent, "RedStall", _side_stall(RED, CREAM, 0), Vector3(8.4, 0, -7.6), -42.0)
	_place(parent, "BlueStall", _side_stall(BLUE, CREAM, 1), Vector3(11.6, 0, -12.0), -55.0)
	# Chalkboards.
	var menu := _chalkboard(parent, Vector3(-4.3, 0, 2.0), 20.0, 1.25)
	K.label(menu, "Apple Cider\n· Pumpkin Pie\n· Pretzels\nCandy Apples", Vector3(-0.12, 1.2, 0.13), 0.0021, Color("f4f1e6"), 0.0, Color(0, 0, 0, 0), 64, HORIZONTAL_ALIGNMENT_LEFT)
	var hm := _chalkboard(parent, Vector3(4.45, 0, 3.5), -22.0, 1.0, "fox")
	K.label(hm, "HANDMADE", Vector3(0, 1.18, 0.13), 0.0025, Color("f4f1e6"))
	var gm := _chalkboard(parent, Vector3(3.9, 0, -2.2), -20.0, 0.6)
	K.label(gm, "3 TRIES", Vector3(-0.02, 0.62, 0.13), 0.0015, Color("f8e9a0"))


func _place(parent: Node3D, nm: String, vb: VoxelBuilder, pos: Vector3, rot: float) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	n.rotation.y = deg_to_rad(rot)
	parent.add_child(n)
	var size := _extent(vb)
	_off = Vector3(size.x * 0.5, 0, size.z * 0.5)
	K.inst(n, vb, U, Vector3.ZERO, 0.0, true, _off)
	# Record glow voxels for halos (world space).
	var xf := n.transform
	for p: Vector3i in vb.glow:
		if K.hs(p.x, p.y, p.z) < 0.12:
			var lp := (Vector3(p) + Vector3(0.5, 0.5, 0.5) - Vector3(size.x * 0.5, 0, size.z * 0.5)) * U
			glow_points.append([xf * lp, 0.5, Color(1.0, 0.7, 0.35, 1.0)])
	return n


func _extent(vb: VoxelBuilder) -> Vector3:
	var mx := Vector3i.ZERO
	for p: Vector3i in vb.vox:
		mx = Vector3i(maxi(mx.x, p.x), maxi(mx.y, p.y), maxi(mx.z, p.z))
	return Vector3(mx) + Vector3.ONE


func _sign(n: Node3D, text: String, pos: Vector3, px: float, rot: float) -> void:
	K.label(n, text, pos, px, Color("4e1c0a"), rot, Color(0, 0, 0, 0), 96)


# ------------------------------------------------------------------ pieces

func _post(vb: VoxelBuilder, x: int, z: int, h: int, c := WOOD_D) -> void:
	K.box(vb, x, 0, z, 2, h, 2, K.noisy(c, 0.06, x))


## Striped awning sloping from (back y=yb, z=z0) to (front y=yf, z=z1).
func _awning(vb: VoxelBuilder, x0: int, x1: int, z0: int, z1: int, yb: int, yf: int, a: Color, b: Color, sw := 4) -> void:
	for z in range(z0, z1 + 1):
		var t := float(z - z0) / maxf(z1 - z0, 1)
		var y := int(round(lerpf(yb, yf, t)))
		for x in range(x0, x1):
			var c := a if posmod((x - x0) / sw, 2) == 0 else b
			vb.set_v(Vector3i(x, y, z), c)
	# Scalloped valance hanging from the front edge.
	for x in range(x0, x1):
		var c := a if posmod((x - x0) / sw, 2) == 0 else b
		var k := posmod(x - x0, sw)
		var drop := 4 if (k == 1 or k == 2) else 3
		for d in drop:
			vb.set_v(Vector3i(x, yf - 1 - d, z1), c)
		vb.set_v(Vector3i(x, yf, z1 + 1), K.shade(c, 0.9))


func _apple(vb: VoxelBuilder, x: int, y: int, z: int, c := Color("c8281e")) -> void:
	K.box(vb, x, y, z, 2, 2, 2, K.noisy(c, 0.1, x + z))
	vb.set_v(Vector3i(x, y + 2, z), Color("5a3a1a"))


func _crate(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int, fill: Array) -> void:
	K.box(vb, x, y, z, w, h, d, K.wood(WOOD_L, 2, 2))
	K.box(vb, x + 1, y + h - 1, z + 1, w - 2, 1, d - 2, Color(0, 0, 0, 0))
	for i in w - 2:
		for j in d - 2:
			vb.set_v(Vector3i(x + 1 + i, y + h - 1, z + 1 + j), K.pick(fill, K.hs(i, j, x)))
			if K.hs(i, j, z) > 0.45:
				vb.set_v(Vector3i(x + 1 + i, y + h, z + 1 + j), K.shade(K.pick(fill, K.hs(j, i, x)), 1.08))


func _lantern(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	# Hanging iron lantern with a warm core: 4x6x4.
	var iron := Color("2c2622")
	K.box(vb, x, y, z, 4, 1, 4, iron)
	K.box(vb, x, y + 5, z, 4, 1, 4, iron)
	K.box(vb, x + 1, y + 6, z + 1, 2, 1, 2, iron)
	for c in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		K.box(vb, x + c.x, y + 1, z + c.y, 1, 4, 1, iron)
	K.box(vb, x + 1, y + 1, z + 1, 2, 4, 2, Color("ffb648"), true)
	for c in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 3), Vector2i(2, 3), Vector2i(0, 1), Vector2i(0, 2), Vector2i(3, 1), Vector2i(3, 2)]:
		K.box(vb, x + c.x, y + 1, z + c.y, 1, 4, 1, Color("ffd27a"), true)


# ------------------------------------------------------------------ FALL TREATS

const TW := 50   # treats stall width (cells)
const TD := 24   # treats stall depth (cells)
const SIGN_Y0 := 51
const SIGN_Y1 := 63


func _candy_apple(vb: VoxelBuilder, x: int, y: int, z: int, c := Color("b8141c")) -> void:
	# Glossy 3x3x3 candy apple with a highlight and a stick poking up.
	K.box(vb, x, y, z, 3, 3, 3, K.noisy(c, 0.06, x * 3 + z))
	vb.set_v(Vector3i(x + 2, y + 2, z + 2), K.shade(c, 1.45))
	vb.set_v(Vector3i(x + 1, y + 3, z + 1), Color("c89a62"))
	vb.set_v(Vector3i(x + 1, y + 4, z + 1), Color("b8885a"))


func _pretzel(vb: VoxelBuilder, x: int, y: int, z: int) -> void:
	# Flat 5x4 knot lying in a tray, salt flecks on top.
	var rows := ["#####", "#.#.#", "##.##", ".###."]
	for r in rows.size():
		for i in 5:
			if rows[r][i] == "#":
				var c := Color("a8622a") if K.hs(x + i, r, z) > 0.4 else Color("8e4e20")
				vb.set_v(Vector3i(x + i, y, z + r), c)
				if K.hs(i, r, x + z) > 0.8:
					vb.set_v(Vector3i(x + i, y + 1, z + r), Color("f4f0e6"))
	vb.set_v(Vector3i(x + 1, y + 1, z + 1), Color("b8742e"))
	vb.set_v(Vector3i(x + 3, y + 1, z + 1), Color("b8742e"))


func _pie(vb: VoxelBuilder, cx: float, y: int, cz: float, r: float, fill: Color) -> void:
	K.cyl(vb, cx, y, cz, r + 0.4, 1, Color("e8e2d6"))          # plate
	K.cyl(vb, cx, y + 1, cz, r, 1, Color("c88a44"))             # crust rim
	K.cyl(vb, cx, y + 2, cz, r - 0.2, 1, Color("d89a50"))
	K.cyl(vb, cx, y + 2, cz, r - 1.1, 1, fill)                  # filling
	# Lattice strips.
	for k in [-1, 1]:
		vb.set_v(Vector3i(int(cx) + k, y + 3, int(cz)), Color("e8b468"))
		vb.set_v(Vector3i(int(cx), y + 3, int(cz) + k), Color("e8b468"))


func _tray(vb: VoxelBuilder, x: int, y: int, z: int, w: int, d: int, c := Color("c9a06a")) -> void:
	K.box(vb, x, y, z, w, 1, d, c)
	for i in w:
		vb.set_v(Vector3i(x + i, y + 1, z), K.shade(c, 0.85))
		vb.set_v(Vector3i(x + i, y + 1, z + d - 1), K.shade(c, 0.85))
	for j in d:
		vb.set_v(Vector3i(x, y + 1, z + j), K.shade(c, 0.85))
		vb.set_v(Vector3i(x + w - 1, y + 1, z + j), K.shade(c, 0.85))


func _treats_stall() -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var W := TW
	var D := TD
	var cz := D - 10   # counter back edge
	# Floor boards.
	K.box(vb, 0, 0, 0, W, 1, D - 3, K.wood(WOOD_D, 0, 3))
	# Side half-walls (plank) so the stall reads as a booth.
	for sx in [1, W - 3]:
		K.box(vb, sx, 1, 2, 2, 14, cz - 2, K.wood(WOOD, 2, 3))
	# Counter: vertical plank front + chunky top with an overhanging lip.
	K.box(vb, 1, 0, cz, W - 2, 15, 7, func(q: Vector3i) -> Color:
		var plank := q.x / 3
		var f := 0.86 + K.hs(plank, 1, 2) * 0.24
		if posmod(q.x, 3) == 0:
			f *= 0.78
		if q.y == 7:
			f *= 0.8
		return K.shade(WOOD, f))
	K.box(vb, 0, 15, cz - 1, W, 2, 10, K.wood(WOOD_L, 0, 3))
	# Little bunting along the counter front.
	for x in range(1, W - 1):
		var c: Color = [Color("e2662a"), Color("f2b33a"), Color("c8401e")][(x / 5) % 3]
		var k := posmod(x, 5)
		var drop := 3 - absi(k - 2)
		for d in drop:
			vb.set_v(Vector3i(x, 14 - d, cz + 7), c)
	# Back wall with three shelves of jars, pies and apples.
	K.box(vb, 2, 0, 0, W - 4, 36, 2, K.wood(WOOD_D, 0, 4))
	for sy in [16, 23, 30]:
		K.box(vb, 2, sy, 2, W - 4, 1, 4, K.wood(WOOD_L, 0, 3))
		var x := 4
		while x < W - 6:
			var kind := int(K.hs(x, sy, 3) * 4)
			match kind:
				0, 1:
					var jc: Color = [Color("e8a030"), Color("c8501e"), Color("b02a20"), Color("f0c050")][int(K.hs(x, sy, 1) * 4)]
					K.box(vb, x, sy + 1, 3, 3, 4, 2, jc)
					K.box(vb, x, sy + 5, 3, 3, 1, 2, Color("f2ead8"))
					x += 4
				2:
					K.cyl(vb, x + 2.5, sy + 1, 4.0, 2.4, 1, Color("c98a4a"))
					K.cyl(vb, x + 2.5, sy + 2, 4.0, 1.8, 1, Color("e07a26"))
					x += 6
				_:
					_apple(vb, x, sy + 1, 3)
					_apple(vb, x + 2, sy + 1, 4, Color("e04a1e"))
					x += 5
	# Posts.
	for px in [0, W - 2]:
		_post(vb, px, 0, 79)
		_post(vb, px, D - 4, 72)
	# Striped awning high above the sign (sign sits fully clear below it,
	# above the selected sim's bubble).
	_awning(vb, -2, W + 2, -1, D + 3, 80, 72, RED, CREAM, 4)
	# Carved hanging sign below the awning, in front of the posts, on two
	# short chains (text = Label3D added in build()).
	var sz := D - 1
	K.box(vb, 2, SIGN_Y0, sz, W - 4, SIGN_Y1 - SIGN_Y0, 1, Color("4e2a14"))
	K.box(vb, 3, SIGN_Y0 + 1, sz + 1, W - 6, SIGN_Y1 - SIGN_Y0 - 2, 1, func(q: Vector3i) -> Color:
		var f := 0.94 + K.hs(q.x / 6, q.y, 4) * 0.1
		if posmod(q.y - SIGN_Y0, 3) == 0:
			f *= 0.95
		return K.shade(Color("e4b47a"), f))
	K.maple(vb, 5, SIGN_Y0 + 2, sz + 2, Color("c8301a"))
	vb.set_v(Vector3i(8, SIGN_Y0 + 1, sz + 2), Color("7a3a1a"))
	for cx in [8, W - 9]:
		for y in range(SIGN_Y1, 63):
			vb.set_v(Vector3i(cx, y, sz), Color("2c2622") if posmod(y, 2) == 0 else Color("4a423a"))
	# --- Food on the counter: two tiers so everything reads from the plaza.
	var top := 17
	# Back riser on the right half (the vendor stands behind the left half).
	K.box(vb, 27, top, cz - 1, 20, 4, 4, K.wood(WOOD_D, 0, 3))
	# Front tier: candy apple tray, pretzel tray, pies.
	_tray(vb, 3, top, cz + 2, 12, 7, Color("e8e2d4"))
	for i in 6:
		var ax := 4 + (i % 3) * 4 - (i / 3) * 2 + 1
		var az := cz + 2 + (i / 3) * 3
		_candy_apple(vb, ax, top + 1, az, Color("b8141c") if i % 3 != 1 else Color("c8261c"))
	_tray(vb, 16, top, cz + 1, 13, 8, Color("c9a06a"))
	for i in 4:
		_pretzel(vb, 17 + (i % 2) * 6, top + 1, cz + 2 + (i / 2) * 3)
	_pie(vb, 33.5, top, cz + 5.5, 3.4, Color("e07a24"))
	_pie(vb, 41.5, top, cz + 5.5, 3.4, Color("9a2a3a"))
	# Upper tier (on the riser): caramel apples + a crate of red apples.
	var ut := top + 4
	_tray(vb, 27, ut, cz - 1, 10, 4, Color("e8e2d4"))
	for i in 3:
		_candy_apple(vb, 28 + i * 3, ut + 1, cz, Color("c88a2a"))
	_crate(vb, 38, ut, cz - 1, 9, 4, 4, [Color("c8281e"), Color("d8361e"), Color("a81e18"), Color("e05a2a")])
	# Cider jugs + paper cups at the left end.
	for i in 2:
		K.box(vb, W - 5 - i * 3, top, cz, 2, 5, 2, Color("d08a2a"))
		vb.set_v(Vector3i(W - 5 - i * 3, top + 5, cz), Color("6a4a2a"))
	# Festoon bulbs under the awning's front edge.
	for x in range(3, W - 2, 6):
		vb.set_v(Vector3i(x, 69, D - 3), Color("2c2622"))
		vb.set_v(Vector3i(x, 68, D - 3), Color("ffd070"), true)
		vb.set_v(Vector3i(x, 67, D - 3), Color("ffc050"), true)
	for x in range(0, W):
		vb.set_v(Vector3i(x, 70, D - 3), Color("3a3530"))
	# Hanging lanterns on the outside of the front posts.
	_lantern(vb, -5, 26, D - 4)
	_lantern(vb, W + 1, 26, D - 4)
	for lx in [-4, W + 2]:
		for y in range(33, 37):
			vb.set_v(Vector3i(lx, y, D - 3), Color("2c2622"))
		K.box(vb, mini(lx, 0) if lx < 0 else W, 36, D - 3, 3 if lx < 0 else 2, 1, 1, Color("2c2622"))
	# Barrel of apples (left front) and hay with pumpkins (right).
	K.cyl(vb, -5.0, 0, D + 1.0, 4.6, 12, func(q: Vector3i) -> Color:
		if q.y == 2 or q.y == 9:
			return Color("3a3430")
		return K.shade(WOOD_D, 0.9 + K.hs(q.x, 0, q.z) * 0.2))
	for i in 9:
		_apple(vb, -8 + (i % 3) * 2, 12, D - 2 + (i / 3) * 2, Color("cc2a1e") if i % 2 else Color("e0a020"))
	K.hay(vb, W - 2, 0, D + 1, 12, 7, 7)
	K.pumpkin(vb, W + 2, 7, D + 4, 3.2, 1, 0)
	K.pumpkin(vb, W + 6, 0, D + 11, 3.8, 2, 2)
	K.pumpkin(vb, W - 4, 0, D + 11, 2.6, 3, 1)
	return vb


# ------------------------------------------------------------------ GAME BOOTH

func _game_stall() -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var W := 26
	var D := 14
	# Red/white striped counter.
	K.box(vb, 0, 0, 6, W, 14, 8, func(q: Vector3i) -> Color:
		return K.shade(RED if posmod(q.x / 3, 2) == 0 else CREAM, 0.96 + K.hs(q.x, q.y, 1) * 0.06))
	K.box(vb, -1, 14, 5, W + 2, 1, 10, K.wood(WOOD_L, 0, 3))
	# Back board with shelves of bottles.
	K.box(vb, 0, 0, 0, W, 27, 2, Color("9a2a22"))
	for sy in [16, 21]:
		K.box(vb, 1, sy, 1, W - 2, 1, 4, K.wood(WOOD_L, 0, 3))
		for i in 6:
			var bc: Color = [Color("3f8fd8"), Color("4fb06a"), Color("e0a030"), Color("3f8fd8"), Color("d84a3a"), Color("4fb06a")][(i + sy) % 6]
			K.box(vb, 3 + i * 4, sy + 1, 2, 2, 3, 2, bc)
			vb.set_v(Vector3i(3 + i * 4, sy + 4, 2), Color("f2f2f2"))
	# Side posts, a low striped canopy and a round target sign on top.
	_post(vb, -1, 0, 30, Color("f2e6d0"))
	_post(vb, W - 1, 0, 30, Color("f2e6d0"))
	for x in range(-2, W + 2):
		for z in range(0, 10):
			vb.set_v(Vector3i(x, 30 + mini(z, 9 - z) / 3, z), RED if posmod(x / 3, 2) == 0 else CREAM)
	var tc := Vector2(W / 2.0, 35.0)
	for x in range(-4, 5):
		for y in range(-4, 5):
			var d := Vector2(x + 0.5, y + 0.5).length()
			if d > 4.3:
				continue
			var ring := int(d / 1.3)
			var c := RED if ring % 2 == 0 else CREAM
			vb.set_v(Vector3i(int(tc.x) + x, int(tc.y) + y, 7), c)
	K.box(vb, W / 2 - 1, 32, 6, 2, 2, 1, Color("5a3218"))
	# Rubber duck + prizes on the counter.
	K.box(vb, 4, 15, 9, 3, 2, 3, Color("f7d43a"))
	K.box(vb, 5, 17, 10, 2, 2, 2, Color("f7d43a"))
	vb.set_v(Vector3i(7, 17, 11), Color("f08a24"))
	vb.set_v(Vector3i(6, 18, 12), Color("2a2420"))
	# Hanging plush prizes on the posts.
	for side in [-3, W + 1]:
		K.box(vb, side, 20, 3, 2, 4, 3, Color("e88a3a"))
		K.box(vb, side, 24, 3, 2, 3, 3, Color("f2b060"))
	# Stack of rings / bean bags.
	for i in 3:
		K.box(vb, 18 + i * 2, 15, 9 + (i % 2), 2, 1, 2, [Color("3a7ad8"), Color("f2c03a"), Color("d83a3a")][i])
	# Pumpkins at the base.
	K.pumpkin(vb, W + 4, 0, 12, 3.4, 4, 0)
	K.pumpkin(vb, -4, 0, 13, 2.6, 5, 3)
	return vb


# ------------------------------------------------------------------ HANDMADE

func _plush(vb: VoxelBuilder, x: int, y: int, z: int, kind: int) -> void:
	match kind:
		0:  # fox
			var o := Color("e8782a")
			K.box(vb, x, y, z, 4, 4, 3, o)
			K.box(vb, x + 1, y, z + 3, 2, 3, 1, Color("f8efe0"))
			K.box(vb, x, y + 4, z, 4, 4, 4, o)
			K.box(vb, x + 1, y + 4, z + 4, 2, 2, 1, Color("f8efe0"))
			vb.set_v(Vector3i(x, y + 8, z + 1), o)
			vb.set_v(Vector3i(x + 3, y + 8, z + 1), o)
			vb.set_v(Vector3i(x + 1, y + 6, z + 4), Color("2a2020"))
			vb.set_v(Vector3i(x + 2, y + 6, z + 4), Color("2a2020"))
		1:  # bunny
			var w := Color("f4efe8")
			K.box(vb, x, y, z, 4, 4, 3, w)
			K.box(vb, x, y + 4, z, 4, 4, 4, w)
			K.box(vb, x, y + 8, z + 1, 1, 4, 1, w)
			K.box(vb, x + 3, y + 8, z + 1, 1, 4, 1, w)
			vb.set_v(Vector3i(x + 1, y + 6, z + 4), Color("2a2020"))
			vb.set_v(Vector3i(x + 2, y + 6, z + 4), Color("2a2020"))
			vb.set_v(Vector3i(x + 1, y + 5, z + 4), Color("f2a0b0"))
		_:  # bear
			var b := Color("9a6038")
			K.box(vb, x, y, z, 4, 4, 3, b)
			K.box(vb, x, y + 4, z, 4, 4, 4, b)
			vb.set_v(Vector3i(x, y + 8, z + 1), b)
			vb.set_v(Vector3i(x + 3, y + 8, z + 1), b)
			K.box(vb, x + 1, y + 4, z + 4, 2, 2, 1, Color("d8a878"))
			vb.set_v(Vector3i(x + 1, y + 6, z + 4), Color("2a2020"))
			vb.set_v(Vector3i(x + 2, y + 6, z + 4), Color("2a2020"))


func _crafts_table() -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var W := 40
	var D := 16
	# Legs + top + gingham cloth hanging at the front.
	for c in [Vector2i(1, 1), Vector2i(W - 3, 1), Vector2i(1, D - 3), Vector2i(W - 3, D - 3)]:
		K.box(vb, c.x, 0, c.y, 2, 12, 2, WOOD_D)
	K.box(vb, 0, 12, 0, W, 1, D, K.wood(WOOD_L, 0, 3))
	K.box(vb, 0, 6, D, W, 6, 1, func(q: Vector3i) -> Color:
		var a := posmod(q.x / 2, 2) == 0
		var b := posmod(q.y / 2, 2) == 0
		return Color("e8eef8") if (a and b) else (Color("6f9ad8") if (a or b) else Color("9ab8e8")))
	# Plushies.
	var x := 2
	var i := 0
	while x < W - 5:
		_plush(vb, x, 13, 3 + (i % 2) * 6, i % 3)
		x += 5
		i += 1
	# Little gift boxes + yarn balls.
	K.box(vb, 3, 13, D - 4, 4, 3, 3, Color("8ac06a"))
	K.box(vb, 4, 16, D - 4, 2, 1, 3, Color("f2d04a"))
	K.cyl(vb, 30.5, 13, D - 3.5, 2.0, 3, Color("d85a8a"))
	K.cyl(vb, 35.5, 13, D - 3.5, 2.0, 3, Color("6aa8d8"))
	# Crates and a pumpkin beside the table.
	_crate(vb, W + 1, 0, 2, 9, 8, 8, [Color("f4efe8"), Color("e8782a"), Color("9a6038")])
	_crate(vb, W + 2, 8, 3, 7, 6, 6, [Color("f2b03a"), Color("e8e0d0")])
	K.pumpkin(vb, -4, 0, D + 2, 3.0, 9, 1)
	return vb


# ------------------------------------------------------------------ SIDE STALLS

func _side_stall(a: Color, b: Color, variant: int) -> VoxelBuilder:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var W := 38
	var D := 20
	K.box(vb, 1, 0, D - 8, W - 2, 14, 6, K.wood(WOOD if variant != 1 else Color("8a6a4a"), 2, 3))
	K.box(vb, 0, 14, D - 9, W, 1, 8, K.wood(WOOD_L, 0, 3))
	for px in [0, W - 2]:
		_post(vb, px, 1, 38)
		_post(vb, px, D - 3, 34)
	_awning(vb, -1, W + 1, 0, D + 2, 40, 34, a, b, 4)
	# Goods: produce baskets / jars / pumpkins depending on variant.
	var pal: Array = [[Color("e8782a"), Color("f2b03a"), Color("d84a1e")], [Color("8ac06a"), Color("d83a2a"), Color("f2d04a")], [Color("c8281e"), Color("f2a030"), Color("e8e0d0")]][variant % 3]
	for i in 4:
		_crate(vb, 2 + i * 9, 15, D - 9, 8, 3, 6, pal)
	K.box(vb, 2, 0, 1, W - 4, 26, 2, K.wood(WOOD_D, 0, 4))
	for i in 7:
		var jc: Color = pal[i % pal.size()]
		K.box(vb, 4 + i * 5, 20, 3, 3, 4, 2, jc)
	_lantern(vb, W - 3, 24, D - 1)
	K.pumpkin(vb, -3, 0, D + 3, 3.0, variant, variant)
	K.hay(vb, W - 4, 0, D + 1, 10, 6, 6)
	return vb


# ------------------------------------------------------------------ CHALKBOARD

## A-frame chalkboard sign; returns the tilted pivot (labels go on it, +Z face).
func _chalkboard(parent: Node3D, pos: Vector3, rot: float, scale: float, doodle := "pumpkin") -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = deg_to_rad(rot)
	parent.add_child(root)
	var pivot := Node3D.new()
	pivot.rotation.x = deg_to_rad(-11.0)
	root.add_child(pivot)
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var w := int(18 * scale)
	var h := int(22 * scale)
	# Frame.
	K.box(vb, 0, 0, 0, w + 2, h + 2, 1, K.wood(WOOD, 0, 2))
	K.box(vb, 1, 1, 1, w, h, 1, func(q: Vector3i) -> Color:
		return K.shade(Color("2e3432"), 0.92 + K.hs(q.x, q.y, 2) * 0.16))
	if doodle == "fox":
		# Chalk fox face (ref2 HANDMADE board): orange head, white cheeks,
		# pointy ears, dark eyes + nose.
		var fo := Color("f08a3a")
		var fw := Color("f4f1e6")
		var fk := Color("1e2220")
		var fx := w / 2 - 4
		var rows := [
			"o......o",
			"oo....oo",
			"oooooooo",
			"okooooko",
			"wwooooww",
			".wwkkww.",
			"..wwww..",
		]
		for r in rows.size():
			var line: String = rows[r]
			for c in line.length():
				var ch := line[c]
				if ch == ".":
					continue
				var col := fo if ch == "o" else (fw if ch == "w" else fk)
				vb.set_v(Vector3i(fx + c + 1, 15 - r, 2), col)
		return _chalk_finish(parent, root, pivot, vb, w, h, scale)
	# Little chalk doodle: a pumpkin in the bottom corner.
	var dc := Color("f08a3a")
	for p in [Vector2i(w - 4, 2), Vector2i(w - 3, 2), Vector2i(w - 5, 3), Vector2i(w - 2, 3), Vector2i(w - 5, 4), Vector2i(w - 2, 4), Vector2i(w - 4, 5), Vector2i(w - 3, 5)]:
		vb.set_v(Vector3i(p.x - 1, p.y, 2), dc)
	vb.set_v(Vector3i(w - 4, 6, 2), Color("8ac06a"))
	return _chalk_finish(parent, root, pivot, vb, w, h, scale)


func _chalk_finish(_parent: Node3D, root: Node3D, pivot: Node3D, vb: VoxelBuilder, w: int, h: int, scale: float) -> Node3D:
	# Legs (back strut).
	var mi := K.inst(pivot, vb, U, Vector3(0, 0, 0), 0.0, true, Vector3((w + 2) * 0.5, -1.0, 0.5))
	mi.name = "Board"
	var legs := VoxelBuilder.new()
	K.box(legs, 0, 0, 0, 1, h, 1, WOOD_D)
	K.box(legs, w + 1, 0, 0, 1, h, 1, WOOD_D)
	var lm := K.inst(root, legs, U, Vector3(0, 0, -0.62 * scale), 0.0, true, Vector3((w + 2) * 0.5, 0, 0))
	lm.rotation.x = deg_to_rad(14.0)
	return pivot
