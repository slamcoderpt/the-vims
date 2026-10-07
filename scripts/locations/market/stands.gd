extends RefCounted
## Market fixtures placed in the world: produce racks / crates (with heaped
## voxel fruit & veg and price tags), chalkboard, fridges, gondola aisles,
## bakery corner, checkout counter. Attaches Interactables.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")

const U := 0.0625
const P := 0.03125


static func u(m: float) -> int:
	return int(round(m / U))


static func build(root: Node3D, halo_pts: Array) -> void:
	var fix := VoxelBuilder.new()     # wooden produce fixtures (U)
	fix.jitter = 0.0
	var prod := VoxelBuilder.new()    # produce (P)
	prod.jitter = 0.05
	_produce_wall(root, fix, prod)
	_produce_island(root, fix, prod)
	_produce_table(root, fix, prod)
	Kit.add(root, fix, U, "ProduceFixtures", true, null, Vector3.ZERO, Vector3.ZERO, true)
	Kit.add(root, prod, P, "Produce", false)
	_chalkboard(root)
	_fridges(root, halo_pts)
	_aisles(root)
	_checkout(root, halo_pts)
	_foreground(root)


static func _act(id: String, label: String, icon: String, minutes: float, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "icon": icon, "minutes": minutes, "needs": {}, "pose": "idle"}
	d.merge(extra, true)
	return d


static func _produce_actions(item: String, price: float) -> Array:
	return [
		_act("buy", "Buy", "cart", 2.0, {"money": -int(ceil(price)), "price": price, "item": item, "task": "Buy Groceries"}),
		_act("compare", "Compare", "scale", 3.0, {"item": item}),
	]


## A crate of produce: wooden box in `fix` (U) and heaped items in `prod` (P).
## at: min corner (metres, y = crate bottom). size in metres.
static func _crate(fix: VoxelBuilder, prod: VoxelBuilder, at: Vector3, size: Vector3, kind: String, seed: int, layers := 3, col := Fx.WOOD, fine := true) -> void:
	var o := Vector3i(u(at.x), u(at.y), u(at.z))
	var w := u(size.x)
	var d := u(size.z)
	var hh := u(size.y)
	Fx.crate(fix, o, w, d, hh, col)
	if not fine:
		# coarse produce on the U grid, straight into the fixture builder
		fix.box(o + Vector3i(1, 1, 1), Vector3i(w - 2, hh - 2, d - 2), Kit.shade(_kind_col(kind), 0.6))
		Produce.mini_heap(fix, kind, o + Vector3i(1, hh - 1, 1), Vector3i(w - 2, 4, d - 2), layers, seed)
		return
	# produce interior (P grid = 2x U grid), starting a bit below the rim
	var po := Vector3i(o.x * 2 + 2, o.y * 2 + hh * 2 - 4, o.z * 2 + 2)
	var ps := Vector3i(w * 2 - 4, 8, d * 2 - 4)
	# fill below the heap so the crate looks full
	prod.box(Vector3i(po.x, o.y * 2 + 2, po.z), Vector3i(ps.x, hh * 2 - 6, ps.z), Kit.shade(_kind_col(kind), 0.55))
	Produce.heap(prod, kind, po, ps, layers, seed)


static func _kind_col(kind: String) -> Color:
	match kind:
		"tomato", "apple", "pepper_red": return Color("b52620")
		"orange", "carrot": return Color("d56a12")
		"lemon", "banana": return Color("d6b02c")
		"greens", "lettuce", "broccoli", "green_apple": return Color("2f6e26")
		"grapes", "eggplant": return Color("4b2463")
	return Color("6a4a2a")


## Small dark price tag with white text, facing +z rotated by rot_y.
static func _tag(root: Node3D, pos: Vector3, text: String, rot_y := 0.0) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	for x in 10:
		for y in 5:
			var edge := x == 0 or y == 0 or x == 9 or y == 4
			vb.set_v(Vector3i(x, y, 0), Color("8a5a31") if edge else Color("2c2420"))
	var mi := Kit.add(root, vb, 0.066, "Tag", false, null, pos, Vector3(5, 2.5, 0.5))
	mi.rotation.y = deg_to_rad(rot_y)
	mi.rotation.x = deg_to_rad(-12)
	var l := Kit.label(mi, text, Vector3(0, 0.0, 0.04), 0.00095, Color("fdf7e8"), 0.0, 128)
	l.scale = Vector3(1, 1.1, 1)


# ------------------------------------------------------------------ produce

## Tiered produce racks against the left wall, facing +x.
static func _produce_wall(root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var kinds := [
		["tomato", "pepper_mix", "lettuce"],
		["apple", "orange", "broccoli"],
		["banana", "lemon", "grapes"],
		["carrot", "green_apple", "tomato"],
		["eggplant", "apple", "lettuce"],
		["orange", "pepper_red", "broccoli"],
		["lemon", "tomato", "greens"],
		["tomato", "carrot", "lettuce"],
		["apple", "banana", "broccoli"],
	]
	var z := -11.1
	var sec := 0
	var xw := -6.7
	while z < -1.5 and sec < kinds.size():
		var lenz := 1.45
		var ks: Array = kinds[sec]
		# tiers: front low -> back high
		var tiers := [[xw + 1.55, 0.62, 0.5], [xw + 1.05, 0.95, 0.5], [xw + 0.55, 1.28, 0.5]]
		for t in 3:
			var tr: Array = tiers[t]
			var bx: float = tr[0]
			var top: float = tr[1]
			# support / riser
			fix.box(Vector3i(u(bx), 0, u(z)), Vector3i(u(tr[2]), u(top - 0.2), u(lenz)), Kit.wood(Fx.WOOD_D, 3))
			_crate(fix, prod, Vector3(bx, top - 0.22, z + 0.03), Vector3(0.5, 0.22, lenz - 0.06), ks[2 - t], sec * 3 + t, 2, Fx.WOOD, t == 0 and z > -4.5)
		# back board + top shelf with baskets
		fix.box(Vector3i(u(xw), 0, u(z)), Vector3i(u(0.55), u(2.1), u(lenz)), Kit.wood(Color("9a6438"), 2))
		fix.box(Vector3i(u(xw + 0.55), u(2.0), u(z)), Vector3i(u(0.35), 1, u(lenz)), Kit.wood(Fx.WOOD_L, 1, 1))
		for b in 3:
			var bz := z + 0.12 + b * 0.45
			_crate(fix, prod, Vector3(xw + 0.6, 2.06, bz), Vector3(0.3, 0.12, 0.38), ["apple", "lemon", "orange"][(sec + b) % 3], sec * 7 + b, 1, Color("c99a5c"), false)
		z += lenz + 0.05
		sec += 1
	Interactable.attach(root, "Produce Wall", _produce_actions("Apples", 0.8), Vector3(1.6, 1.4, 6.2), Vector3(-5.9, 0.7, -4.5), Vector3(-4.6, 0, -4.5))


## Foreground island of crates (tiered, spilling towards the camera).
static func _produce_island(root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var x0 := -3.4
	var wood := Kit.wood(Color("8f5a31"), 2)
	# rows: [base y, z, depth, crate h, [[kind, width]...]] back (high) -> front (low)
	var rows := [
		[0.78, -0.95, 0.85, 0.24, [["broccoli", 0.95], ["lettuce", 0.95], ["apple", 1.0]], 2],
		[0.5, -0.05, 0.9, 0.26, [["greens", 0.95], ["tomato", 0.95]], 3],
		[0.22, 0.9, 0.9, 0.28, [["carrot", 0.9], ["banana", 0.9]], 3],
	]
	var names := {"broccoli": "Broccoli", "lettuce": "Lettuce", "apple": "Apples", "greens": "Greens", "tomato": "Tomatoes",
		"pepper_red": "Peppers", "carrot": "Carrots", "banana": "Bananas", "pepper_mix": "Peppers"}
	var prices := {"broccoli": 1.8, "lettuce": 1.5, "apple": 0.8, "greens": 1.5, "tomato": 1.2,
		"pepper_red": 2.3, "carrot": 0.9, "banana": 0.6, "pepper_mix": 2.3}
	for ri in rows.size():
		var r: Array = rows[ri]
		var total := 0.0
		for e: Array in r[4]:
			total += e[1] + 0.02
		fix.box(Vector3i(u(x0), 0, u(r[1])), Vector3i(u(total), u(r[0]), u(r[2] + 0.05)), wood)
		var xs := x0 + 0.01
		for e: Array in r[4]:
			var w: float = e[1]
			var kind: String = e[0]
			_crate(fix, prod, Vector3(xs, r[0], r[1]), Vector3(w, r[3], r[2]), kind, 40 + ri * 5 + int(xs * 3.0), r[5])
			Interactable.attach(root, names[kind], _produce_actions(names[kind], prices[kind]), Vector3(w, 0.5, r[2]),
				Vector3(xs + w * 0.5, r[0] + 0.25, r[1] + r[2] * 0.5), Vector3(xs + w * 0.5, 0, 2.2))
			xs += w + 0.02
	_tag(root, Vector3(-2.95, 0.42, 1.83), "$0.90", 6.0)
	_tag(root, Vector3(-2.02, 0.42, 1.83), "$2.30", 6.0)
	_tag(root, Vector3(-1.98, 0.7, 0.88), "$1.20", 6.0)
	_tag(root, Vector3(-0.98, 0.98, -0.07), "$0.80", 6.0)
	# front-left extra crates on the floor (foreground spill)
	_crate(fix, prod, Vector3(-4.9, 0.0, 1.9), Vector3(1.0, 0.3, 0.8), "orange", 77, 3)
	_crate(fix, prod, Vector3(-4.75, 0.0, 0.9), Vector3(0.95, 0.5, 0.85), "pepper_mix", 78, 3)
	# near-camera crates (lower-left foreground, softened by the DOF)
	# Low foreground display (bottom-left of the shot, soft in the DOF).
	fix.box(Vector3i(u(-3.3), 0, u(3.75)), Vector3i(u(2.75), u(0.38), u(0.95)), wood)
	var fx := -3.28
	for e: Array in [["tomato", 0.88, 84], ["pepper_mix", 0.88, 85], ["banana", 0.92, 86]]:
		_crate(fix, prod, Vector3(fx, 0.38, 3.77), Vector3(e[1], 0.26, 0.9), e[0], e[2], 3)
		fx += e[1] + 0.02
	_tag(root, Vector3(-1.05, 0.36, 4.78), "$0.60", -4.0)


## Mid-store produce table (background left of the aisle).
static func _produce_table(_root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var x0 := -4.4
	var z0 := -7.6
	fix.box(Vector3i(u(x0), 0, u(z0)), Vector3i(u(2.2), u(0.62), u(1.6)), Kit.wood(Color("8f5a31"), 2))
	var ks := ["orange", "green_apple", "lemon", "grapes"]
	for i in 4:
		var cx := x0 + 0.05 + (i % 2) * 1.08
		var cz := z0 + 0.05 + (i / 2) * 0.78
		_crate(fix, prod, Vector3(cx, 0.62, cz), Vector3(1.04, 0.2, 0.74), ks[i], 60 + i, 2, Fx.WOOD, false)


static func _chalkboard(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var W := 14
	var Hh := 22
	for x in W:
		for y in Hh:
			var edge := x < 1 or x >= W - 1 or y < 1 or y >= Hh - 1
			vb.set_v(Vector3i(x, y + 6, 0), Kit.vary(Fx.WOOD, Vector3i(x, y, 0), 0.08) if edge else Kit.vary(Color("2b302d"), Vector3i(x, y, 0), 0.05))
	for y in 7:
		vb.set_v(Vector3i(1, y, -1), Fx.WOOD_D)
		vb.set_v(Vector3i(W - 2, y, -1), Fx.WOOD_D)
	var lv := VoxelBuilder.new()
	Fx.leaf_icon(lv, Vector3i(6, 7, 1), Color("6cbf45"), Color("2f7a2a"))
	for p: Vector3i in lv.vox:
		vb.set_v(p, lv.vox[p])
	var mi := Kit.add(root, vb, U, "Chalkboard", true, null, Vector3(-3.55, 0.0, -1.75), Vector3(W * 0.5, 0, 0))
	mi.rotation.y = deg_to_rad(32)
	mi.rotation.x = deg_to_rad(-8)
	var l := Kit.label(mi, "Local\nFresh\nToday!", Vector3(-0.04, 1.27, 0.075), 0.0024, Color("f4f1e6"), 0.0, 96)
	l.rotation.z = deg_to_rad(4)
	l.line_spacing = -18.0


# ------------------------------------------------------------------ fridges

static func _fridges(root: Node3D, halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var bank := Fx.fridge(u(6.4), 3)
	Fx.put(vb, bank, Vector3i(u(-4.4), 0, u(-11.7)))
	# second bank on the right of the back wall (beverages, behind the aisles)
	var bank2 := Fx.fridge(u(5.6), 9)
	Fx.put(vb, bank2, Vector3i(u(2.1), 0, u(-11.7)))
	Kit.add(root, vb, U, "Fridges", false, Kit.glow_mat("cool"), Vector3.ZERO, Vector3.ZERO, true)
	# Soft cool bloom along the lit header strips and inside the cases.
	for i in 16:
		var hx := -4.0 + i * 0.75
		halo_pts.append([Vector3(hx, 1.95, -10.9), 1.1, Color(0.55, 0.75, 1.0, 1.0)])
		halo_pts.append([Vector3(hx, 1.0, -11.1), 1.3, Color(0.45, 0.62, 0.9, 1.0)])
	Interactable.attach(root, "Dairy Fridge", [
		_act("buy", "Buy Milk", "milk", 2.0, {"money": -2, "item": "Milk"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(6.4, 2.1, 0.8), Vector3(-1.2, 1.05, -11.25), Vector3(-1.2, 0, -10.2))


# ------------------------------------------------------------------ aisles

static func _aisles(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var kinds_a := ["cereal", "cereal", "box", "bag", "can", "cereal"]
	var kinds_b := ["bottle", "bottle", "can", "jar", "box", "bag"]
	var kinds_c := ["bottle", "can", "bottle", "jar", "bottle"]
	# Gondola rows run along z (deep into the store) so the aisles recede
	# towards the back fridges; each is double-sided and faces the main aisle
	# (-x) and the next aisle (+x). End caps face the camera.
	var ga := Fx.gondola(u(7.2), 1, kinds_a, true)
	Fx.put(vb, ga, Vector3i(u(2.6), 0, u(-9.6)), 3)
	var gb := Fx.gondola(u(6.4), 2, kinds_b)
	Fx.put(vb, gb, Vector3i(u(5.5), 0, u(-9.6)), 3)
	var gc := Fx.gondola(u(5.4), 5, kinds_c)
	Fx.put(vb, gc, Vector3i(u(7.7), 0, u(-9.6)), 3)
	var e1 := Fx.gondola(u(1.0), 4, ["cereal", "box", "cereal"])
	Fx.put(vb, e1, Vector3i(u(2.1), 0, u(-2.4)), 0)
	var e2 := Fx.gondola(u(1.0), 6, ["can", "bottle", "jar"])
	Fx.put(vb, e2, Vector3i(u(4.5), 0, u(-3.2)), 0)
	# Low display of cereal boxes with a pot of flowers (centre-right).
	var d := Vector3i(u(1.75), 0, u(-0.35))
	vb.box(d, Vector3i(u(1.0), u(0.55), u(0.7)), Kit.wood(Fx.WOOD, 2))
	for i in 4:
		var col: Color = Fx.BOX_COLS[(i * 3 + 1) % Fx.BOX_COLS.size()]
		Fx.product(vb, d + Vector3i(i * 4, u(0.55), 8), "cereal", col, Fx.BOX_COLS[(i * 7 + 2) % 10], 7)
		Fx.product(vb, d + Vector3i(i * 4, u(0.55), 4), "cereal", Kit.shade(col, 0.85), Fx.BOX_COLS[(i * 5) % 10], 7)
	# Flower bucket on top.
	var fpos := d + Vector3i(6, u(0.55) + 6, 2)
	vb.box(fpos, Vector3i(4, 3, 4), Color("c96f3e"))
	for i in 22:
		var fp := fpos + Vector3i(int(Kit.h(Vector3i(i, 0, 0), 1) * 6.0) - 1, 3 + int(Kit.h(Vector3i(i, 1, 0), 2) * 4.0), int(Kit.h(Vector3i(i, 2, 0), 3) * 6.0) - 1)
		var fc: Color = [Color("f06a9a"), Color("f9a8c8"), Color("ffffff"), Color("f5d03b")][i % 4]
		vb.set_v(fp, fc)
		vb.set_v(fp - Vector3i(0, 1, 0), Color("3f8a2e"))
	# Bakery corner (right-front wall): bread shelves.
	var bk := Vector3i(u(6.6), 0, u(-3.4))
	vb.box(bk, Vector3i(u(1.1), u(1.5), u(2.4)), Kit.wood(Fx.WOOD_D, 3))
	for s in 3:
		var y := u(0.45 + s * 0.42)
		vb.box(bk + Vector3i(-2, y, 0), Vector3i(3, 1, u(2.4)), Kit.wood(Fx.WOOD_L, 1, 1))
		for b in 9:
			var bp := bk + Vector3i(-2 + (b % 2), y + 1, 1 + b * 4)
			var bc: Color = [Color("d39a52"), Color("b8763a"), Color("e4b56e")][(b + s) % 3]
			vb.box(bp, Vector3i(3, 2, 3), bc)
			vb.set_v(bp + Vector3i(1, 2, 1), Kit.shade(bc, 1.15))
	Kit.add(root, vb, U, "Aisles", false, null, Vector3.ZERO, Vector3.ZERO, true)
	Interactable.attach(root, "Cereal Shelf", [
		_act("buy", "Buy Cereal", "cereal", 2.0, {"money": -4, "item": "Cereal"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(0.6, 1.9, 7.2), Vector3(2.1, 0.95, -6.0), Vector3(1.6, 0, -6.0))


# ------------------------------------------------------------------ checkout

static func _checkout(root: Node3D, _halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.035
	var x0 := u(2.15)
	var z0 := u(1.2)
	var W := u(0.85)
	var L := u(4.2)
	var Hc := u(0.92)
	# body: wood front panels (facing -x)
	vb.box(Vector3i(x0, 0, z0), Vector3i(W, Hc, L), func(p: Vector3i) -> Color:
		if p.y < 2:
			return Color("3a2a1e")
		var k := p.z / 3
		return Kit.shade(Fx.WOOD, 0.9 + 0.16 * Kit.h(Vector3i(k, 0, 1), 7)))
	# panel trims
	for zz in range(z0, z0 + L, 12):
		vb.box(Vector3i(x0 - 1, 2, zz), Vector3i(1, Hc - 3, 1), Fx.WOOD_D)
	# counter top
	vb.box(Vector3i(x0 - 1, Hc, z0 - 1), Vector3i(W + 2, 1, L + 2), Color("e8ddc8"))
	var belt0 := z0 + u(0.9)
	var belt_len := L - u(0.9) - 2
	# conveyor belt with steel rails
	vb.box(Vector3i(x0 + 2, Hc + 1, belt0), Vector3i(W - 4, 1, belt_len), func(p: Vector3i) -> Color:
		return Color("2b2b2e") if p.z % 4 != 0 else Color("3b3b40"))
	vb.box(Vector3i(x0 + 1, Hc + 1, belt0), Vector3i(1, 2, belt_len), Color("9aa0a6"))
	vb.box(Vector3i(x0 + W - 2, Hc + 1, belt0), Vector3i(1, 2, belt_len), Color("9aa0a6"))
	# register: monitor on a post (screen faces the customer, -x)
	var r := Vector3i(x0 + 8, Hc + 1, z0 + 5)
	vb.box(r, Vector3i(2, 4, 2), Color("3a3a3e"))
	vb.box(r + Vector3i(-2, 4, -4), Vector3i(3, 8, 10), Color("2a2a2e"))
	vb.box(r + Vector3i(-3, 5, -3), Vector3i(1, 6, 8), Color("6fa8de"), true)
	vb.box(r + Vector3i(-3, 9, -2), Vector3i(1, 1, 5), Color("d6ecff"), true)
	vb.box(r + Vector3i(-3, 6, -2), Vector3i(1, 1, 3), Color("bfe0ff"), true)
	# cash drawer + keypad
	vb.box(Vector3i(x0 + 1, Hc + 1, z0 + 1), Vector3i(6, 2, 10), Color("4a4a50"))
	vb.box(Vector3i(x0 + 2, Hc + 3, z0 + 2), Vector3i(4, 1, 4), Color("3a3a3e"))
	for k in 6:
		vb.set_v(Vector3i(x0 + 2 + (k % 2) * 2, Hc + 4, z0 + 2 + k / 2), Color("e8e8ea"))
	# card reader
	vb.box(Vector3i(x0 + 1, Hc + 1, z0 + 12), Vector3i(2, 3, 2), Color("2a2a2e"))
	vb.set_v(Vector3i(x0 + 1, Hc + 3, z0 + 12), Color("6fd36f"), true)
	# groceries on the belt (far end = small z, near the register)
	var by := Hc + 2
	vb.box(Vector3i(x0 + 3, by, belt0 + 4), Vector3i(4, 5, 2), Color("f6c22c"))      # cereal
	vb.box(Vector3i(x0 + 3, by + 3, belt0 + 4), Vector3i(4, 1, 1), Color("e8402f"))
	vb.box(Vector3i(x0 + 2, by + 1, belt0 + 4), Vector3i(1, 2, 2), Color("ffffff"))
	vb.box(Vector3i(x0 + 8, by, belt0 + 8), Vector3i(4, 2, 3), Color("efe2c8"))      # eggs
	for e in 3:
		vb.set_v(Vector3i(x0 + 8 + e, by + 2, belt0 + 9), Color("fbf6ee"))
	vb.box(Vector3i(x0 + 3, by, belt0 + 13), Vector3i(2, 4, 2), Color("fbfbf7"))     # milk
	vb.box(Vector3i(x0 + 3, by + 2, belt0 + 13), Vector3i(2, 1, 2), Color("2e7de0"))
	vb.box(Vector3i(x0 + 3, by + 4, belt0 + 13), Vector3i(1, 1, 1), Color("2e7de0"))
	vb.box(Vector3i(x0 + 7, by, belt0 + 18), Vector3i(3, 3, 3), Color("e8402f"))     # red box
	vb.box(Vector3i(x0 + 7, by + 1, belt0 + 17), Vector3i(3, 1, 1), Color("fde46a"))
	var kb := Vector3i(x0 + 9, by, belt0 + 25)   # ketchup
	vb.box(kb, Vector3i(3, 7, 3), Color("d82a22"))
	vb.box(kb + Vector3i(1, 7, 1), Vector3i(1, 2, 1), Color("f2f2f2"))
	vb.box(kb + Vector3i(-1, 2, 0), Vector3i(1, 3, 3), Color("fbf3dc"))
	vb.box(Vector3i(x0 + 8, by, belt0 + 33), Vector3i(4, 3, 4), Color("f6c22c"))     # yellow box
	vb.box(Vector3i(x0 + 7, by + 1, belt0 + 33), Vector3i(1, 1, 4), Color("e8402f"))
	# green tote bags hanging on the front
	for i in 3:
		var tz := z0 + u(0.5) + i * u(1.0)
		for y in 7:
			for zz in 7:
				var p := Vector3i(x0 - 2, u(0.1) + y, tz + zz)
				vb.set_v(p, Kit.vary(Color("3c9a4a"), p, 0.05))
		# handles
		for zz in [1, 5]:
			vb.set_v(Vector3i(x0 - 2, u(0.1) + 7, tz + zz), Color("2e7a3a"))
			vb.set_v(Vector3i(x0 - 2, u(0.1) + 8, tz + zz), Color("2e7a3a"))
		vb.set_v(Vector3i(x0 - 2, u(0.1) + 9, tz + 2), Color("2e7a3a"))
		vb.set_v(Vector3i(x0 - 2, u(0.1) + 9, tz + 3), Color("2e7a3a"))
		vb.set_v(Vector3i(x0 - 2, u(0.1) + 9, tz + 4), Color("2e7a3a"))
		# leaf logo
		var lv := VoxelBuilder.new()
		Fx.leaf_icon(lv, Vector3i(0, 0, 0), Color("e8f5d8"), Color("3c9a4a"))
		for p: Vector3i in lv.vox:
			if p.x % 2 == 0 and p.y % 2 == 0:
				vb.set_v(Vector3i(x0 - 3, u(0.1) + 1 + p.y / 2, tz + 1 + p.x / 2), lv.vox[p])
	# back counter behind the cashier
	var bx := u(4.15)
	var bz := u(1.1)
	var bh := u(0.9)
	vb.box(Vector3i(bx, 0, bz), Vector3i(u(0.6), bh, u(2.2)), Kit.wood(Fx.WOOD_D, 2))
	vb.box(Vector3i(bx - 1, bh, bz - 1), Vector3i(u(0.6) + 1, 1, u(2.2) + 2), Color("e8ddc8"))
	var ty := bh + 1
	# paper grocery bags with bread and greens poking out
	for k in 2:
		var gb := Vector3i(bx + 2, ty, bz + 3 + k * 7)
		vb.box(gb, Vector3i(5, 6, 5), Kit.noise(Color("c99a62"), 0.06, k))
		vb.box(gb + Vector3i(1, 6, 1), Vector3i(2, 3, 2), Color("d39a52") if k == 0 else Color("4f9e34"))
		vb.box(gb + Vector3i(3, 6, 2), Vector3i(1, 2, 2), Color("43a447") if k == 0 else Color("f6c22c"))
	# potted flowers
	var fp := Vector3i(bx + 3, ty, bz + 18)
	vb.box(fp, Vector3i(4, 3, 4), Color("c96f3e"))
	for i in 14:
		var q := fp + Vector3i(int(Kit.h(Vector3i(i, 0, 9), 1) * 5.0) - 1, 3 + int(Kit.h(Vector3i(i, 1, 9), 2) * 3.0), int(Kit.h(Vector3i(i, 2, 9), 3) * 5.0) - 1)
		vb.set_v(q, [Color("f06a9a"), Color("f9a8c8"), Color("fdf6ea")][i % 3])
		vb.set_v(q - Vector3i(0, 1, 0), Color("3f8a2e"))
	# folded green totes + receipt roll + candy jars
	for k in 3:
		vb.box(Vector3i(bx + 2, ty + k, bz + 25), Vector3i(6, 1, 5), Color("3c9a4a") if k % 2 == 0 else Color("2e7a3a"))
	for k in 3:
		var jp := Vector3i(bx + 2 + (k % 2) * 3, ty, bz + 31)
		vb.box(jp, Vector3i(2, 3, 2), [Color("ef6aa0"), Color("f5d03b"), Color("27b3c4")][k])
		vb.set_v(jp + Vector3i(0, 3, 0), Color("d8dde2"))
	Kit.add(root, vb, U, "Checkout", true)
	# produce on the belt (fine grid)
	var pv := VoxelBuilder.new()
	pv.jitter = 0.05
	var py := (Hc + 2) * 2
	var b0 := z0 + u(0.9)
	Produce.bananas(pv, Vector3i((x0 + 2) * 2, py, (b0 + 22) * 2), 5)
	Produce.bananas(pv, Vector3i((x0 + 2) * 2 + 1, py + 2, (b0 + 22) * 2 + 1), 4)
	Produce.broccoli(pv, Vector3i((x0 + 3) * 2, py, (b0 + 15) * 2))
	Produce.lettuce(pv, Vector3i((x0 + 8) * 2, py, (b0 + 9) * 2))
	for t in 3:
		Produce.tomato(pv, Vector3i((x0 + 3) * 2 + t * 4, py, (b0 + 29) * 2 + (t % 2)))
	Produce.apple(pv, Vector3i((x0 + 3) * 2, py, (b0 + 34) * 2))
	Produce.apple(pv, Vector3i((x0 + 3) * 2 + 4, py, (b0 + 34) * 2 + 2))
	Kit.add(root, pv, P, "CheckoutProduce", false)
	Interactable.attach(root, "Checkout", [
		_act("pay", "Pay", "register", 3.0, {"task": "Pay at Checkout"}),
		_act("bag", "Bag Groceries", "bag", 2.0),
	], Vector3(0.85, 1.0, 4.2), Vector3(2.57, 0.5, 3.3), Vector3(1.75, 0, 2.6))


# ------------------------------------------------------------------ foreground dressing

## Fine-grid (P) props near the camera: a flower stand, a stack of shopping
## baskets and a basket of apples on the floor. One mesh.
static func _foreground(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	# Flower stand: low wooden crate with three buckets of flowers.
	var fo := Vector3i(int(round(-3.3 / P)), 0, int(round(2.6 / P)))
	Fx.crate(vb, fo, 30, 18, 10, Color("a8703f"))
	vb.box(fo + Vector3i(1, 1, 1), Vector3i(28, 8, 16), Color("6a4528"))
	var fcols := [[Color("f06a9a"), Color("f9a8c8")], [Color("fdf6ea"), Color("f5d03b")], [Color("ef5a5a"), Color("f7a14a")]]
	for b in 3:
		var bo := fo + Vector3i(3 + b * 9, 9, 4)
		var pail := Color("6f8f9a") if b != 1 else Color("c96f3e")
		for x in 7:
			for z in 9:
				for y in 6:
					var edge := x == 0 or x == 6 or z == 0 or z == 8
					if edge or y == 0:
						vb.set_v(bo + Vector3i(x, y, z), Kit.vary(pail, Vector3i(x, y, z), 0.06))
		# stems + blooms
		var cc: Array = fcols[b]
		for i in 26:
			var hx := 1 + int(Kit.h(Vector3i(i, b, 1), 2) * 5.0)
			var hz := 1 + int(Kit.h(Vector3i(i, b, 2), 3) * 7.0)
			var top := 7 + int(Kit.h(Vector3i(i, b, 3), 4) * 7.0)
			for y in range(5, top):
				vb.set_v(bo + Vector3i(hx, y, hz), Color("3f8a2e") if y % 3 else Color("5aa83a"))
			var col: Color = cc[i % 2]
			var bp := bo + Vector3i(hx, top, hz)
			vb.set_v(bp, col)
			for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				vb.set_v(bp + d, Kit.shade(col, 0.92))
			vb.set_v(bp + Vector3i(0, 1, 0), Color("f5d03b") if b != 1 else Color("e8902a"))
		# leaves spilling at the rim
		for i in 10:
			var lp := bo + Vector3i(int(Kit.h(Vector3i(i, b, 7), 1) * 7.0), 6, int(Kit.h(Vector3i(i, b, 8), 2) * 9.0))
			vb.set_v(lp, Color("4f9e34"))
	# Stack of red shopping baskets.
	var so := Vector3i(int(round(-4.3 / P)), 0, int(round(3.4 / P)))
	for k in 4:
		_basket(vb, so + Vector3i(0, k * 3, 0), Color("d8322c") if k % 2 == 0 else Color("c42a25"), k == 3)
	# A loose basket of apples next to the stack.
	var ao := so + Vector3i(17, 0, 2)
	_basket(vb, ao, Color("2f7fd8"), true)
	var pv := VoxelBuilder.new()
	for i in 7:
		var ap := ao + Vector3i(1 + (i % 3) * 4, 5, 1 + (i / 3) * 4) if i < 6 else ao + Vector3i(5, 8, 3)
		Produce.apple(pv, ap, i % 4 == 0)
	for p: Vector3i in pv.vox:
		vb.set_v(p, pv.vox[p])
	Kit.add(root, vb, P, "Foreground", false, null, Vector3.ZERO, Vector3.ZERO, false)


static func _basket(vb: VoxelBuilder, o: Vector3i, col: Color, handles: bool) -> void:
	var W := 14
	var D := 10
	var Hh := 8
	for x in W:
		for z in D:
			for y in Hh:
				var side := x == 0 or x == W - 1 or z == 0 or z == D - 1
				if y == 0 or (side and (y == Hh - 1 or y == 1 or (x + z + y) % 2 == 0)):
					vb.set_v(o + Vector3i(x, y, z), col if y != Hh - 1 else Kit.shade(col, 1.12))
	if handles:
		for x in [3, W - 4]:
			for y in 4:
				vb.set_v(o + Vector3i(x, Hh + y, 0), Color("2a2a2c"))
				vb.set_v(o + Vector3i(x, Hh + y, D - 1), Color("2a2a2c"))
			for z in D:
				vb.set_v(o + Vector3i(x, Hh + 4, z), Color("2a2a2c"))
