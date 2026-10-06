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
	fix.jitter = 0.04
	var prod := VoxelBuilder.new()    # produce (P)
	prod.jitter = 0.05
	_produce_wall(root, fix, prod)
	_produce_island(root, fix, prod)
	_produce_table(root, fix, prod)
	Kit.add(root, fix, U, "ProduceFixtures", true)
	Kit.add(root, prod, P, "Produce", true)
	_chalkboard(root)
	_fridges(root)
	_aisles(root)
	_checkout(root, halo_pts)


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
	for x in 8:
		for y in 4:
			var edge := x == 0 or y == 0 or x == 7 or y == 3
			vb.set_v(Vector3i(x, y, 0), Color("6b4a2c") if edge else Color("2c2420"))
	var mi := Kit.add(root, vb, 0.04, "Tag", false, null, pos, Vector3(4, 2, 0.5))
	mi.rotation.y = deg_to_rad(rot_y)
	mi.rotation.x = deg_to_rad(-12)
	var l := Kit.label(mi, text, Vector3(0, 0.0, 0.025), 0.0011, Color("fdf7e8"), 0.0, 128)
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
	]
	var z := -10.2
	var sec := 0
	var xw := -6.7
	while z < 0.6 and sec < kinds.size():
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
			_crate(fix, prod, Vector3(bx, top - 0.22, z + 0.03), Vector3(0.5, 0.22, lenz - 0.06), ks[2 - t], sec * 3 + t, 2, Fx.WOOD, false)
		# back board + top shelf with baskets
		fix.box(Vector3i(u(xw), 0, u(z)), Vector3i(u(0.55), u(2.1), u(lenz)), Kit.wood(Color("9a6438"), 2))
		fix.box(Vector3i(u(xw + 0.55), u(2.0), u(z)), Vector3i(u(0.35), 1, u(lenz)), Kit.wood(Fx.WOOD_L, 1, 1))
		for b in 3:
			var bz := z + 0.12 + b * 0.45
			_crate(fix, prod, Vector3(xw + 0.6, 2.06, bz), Vector3(0.3, 0.12, 0.38), ["apple", "lemon", "orange"][(sec + b) % 3], sec * 7 + b, 1, Color("c99a5c"), false)
		z += lenz + 0.05
		sec += 1
	Interactable.attach(root, "Produce Wall", _produce_actions("Apples", 0.8), Vector3(1.6, 1.4, 10.8), Vector3(-5.9, 0.7, -4.8), Vector3(-4.6, 0, -4.8))


## Foreground island of crates (tiered, spilling towards the camera).
static func _produce_island(root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var x0 := -3.4
	var wood := Kit.wood(Color("8f5a31"), 2)
	# rows: [base y, z, depth, crate h, [[kind, width]...]] back (high) -> front (low)
	var rows := [
		[0.78, -0.95, 0.85, 0.24, [["broccoli", 0.95], ["lettuce", 0.95], ["apple", 1.0]]],
		[0.5, -0.05, 0.9, 0.26, [["greens", 0.95], ["tomato", 0.95]]],
		[0.22, 0.9, 0.9, 0.28, [["carrot", 0.9], ["banana", 0.9]]],
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
			_crate(fix, prod, Vector3(xs, r[0], r[1]), Vector3(w, r[3], r[2]), kind, 40 + ri * 5 + int(xs * 3.0), 3)
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


## Mid-store produce table (background left of the aisle).
static func _produce_table(_root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var x0 := -4.6
	var z0 := -6.2
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
	Fx.leaf_icon(lv, Vector3i(5, 9, 1), Color("6cbf45"), Color("2f7a2a"))
	for p: Vector3i in lv.vox:
		vb.set_v(p, lv.vox[p])
	var mi := Kit.add(root, vb, U, "Chalkboard", true, null, Vector3(-3.0, 0.0, -2.5), Vector3(W * 0.5, 0, 0))
	mi.rotation.y = deg_to_rad(32)
	mi.rotation.x = deg_to_rad(-8)
	var l := Kit.label(mi, "Local\nFresh\nToday!", Vector3(0, 1.17, 0.04), 0.0024, Color("f4f1e6"), 0.0, 96)
	l.rotation.z = deg_to_rad(4)
	l.line_spacing = -18.0


# ------------------------------------------------------------------ fridges

static func _fridges(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.02
	var bank := Fx.fridge(u(6.4), 3)
	Fx.put(vb, bank, Vector3i(u(-1.9), 0, u(-11.15)))
	# second bank on the right of the back wall (beverages)
	var bank2 := Fx.fridge(u(2.6), 9)
	Fx.put(vb, bank2, Vector3i(u(4.7), 0, u(-11.15)))
	Kit.add(root, vb, U, "Fridges", false, Kit.glow_mat("cool"))
	Interactable.attach(root, "Dairy Fridge", [
		_act("buy", "Buy Milk", "milk", 2.0, {"money": -2, "item": "Milk"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(8.6, 2.1, 0.8), Vector3(-0.4, 1.05, -10.75), Vector3(-0.4, 0, -9.6))


# ------------------------------------------------------------------ aisles

static func _aisles(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var kinds_a := ["cereal", "cereal", "bag", "can", "jar"]
	var kinds_b := ["bottle", "bottle", "can", "cereal", "bag"]
	# Row 1: faces -x, runs along z from -9.4 to -2.2 at x = 2.25.
	var g1 := Fx.gondola(u(8.3), 1, kinds_a)
	Fx.put(vb, g1, Vector3i(u(3.5), 0, u(-9.3)), 3)
	# Row 2 (further right, partly visible above row 1).
	var g2 := Fx.gondola(u(7.6), 2, kinds_b)
	Fx.put(vb, g2, Vector3i(u(6.3), 0, u(-9.3)), 3)
	# End-cap facing the camera at the front of row 1.
	var e1 := Fx.gondola(u(1.1), 4, ["cereal", "bag"])
	Fx.put(vb, e1, Vector3i(u(2.45), 0, u(-1.0)), 0)
	# Low display of cereal boxes with a pot of flowers (centre-right).
	var d := Vector3i(u(1.75), 0, u(-0.35))
	vb.box(d, Vector3i(u(1.0), u(0.55), u(0.7)), Kit.wood(Fx.WOOD, 2))
	for i in 5:
		var col: Color = Fx.BOX_COLS[(i * 3 + 1) % Fx.BOX_COLS.size()]
		Fx.product(vb, d + Vector3i(1 + i * 3, u(0.55), 7), "cereal", col, Fx.BOX_COLS[(i * 7 + 2) % 10], 6)
		Fx.product(vb, d + Vector3i(1 + i * 3, u(0.55), 4), "cereal", Kit.shade(col, 0.85), Fx.BOX_COLS[(i * 5) % 10], 6)
	# Flower bucket on top.
	var fpos := d + Vector3i(6, u(0.55) + 6, 2)
	vb.box(fpos, Vector3i(4, 3, 4), Color("c96f3e"))
	for i in 22:
		var fp := fpos + Vector3i(int(Kit.h(Vector3i(i, 0, 0), 1) * 6.0) - 1, 3 + int(Kit.h(Vector3i(i, 1, 0), 2) * 4.0), int(Kit.h(Vector3i(i, 2, 0), 3) * 6.0) - 1)
		var fc: Color = [Color("f06a9a"), Color("f9a8c8"), Color("ffffff"), Color("f5d03b")][i % 4]
		vb.set_v(fp, fc)
		vb.set_v(fp - Vector3i(0, 1, 0), Color("3f8a2e"))
	# Bakery corner (right-front wall): bread shelves.
	var bk := Vector3i(u(6.6), 0, u(-3.6))
	vb.box(bk, Vector3i(u(1.1), u(1.5), u(2.4)), Kit.wood(Fx.WOOD_D, 3))
	for s in 3:
		var y := u(0.45 + s * 0.42)
		vb.box(bk + Vector3i(-2, y, 0), Vector3i(3, 1, u(2.4)), Kit.wood(Fx.WOOD_L, 1, 1))
		for b in 9:
			var bp := bk + Vector3i(-2 + (b % 2), y + 1, 1 + b * 4)
			var bc: Color = [Color("d39a52"), Color("b8763a"), Color("e4b56e")][(b + s) % 3]
			vb.box(bp, Vector3i(3, 2, 3), bc)
			vb.set_v(bp + Vector3i(1, 2, 1), Kit.shade(bc, 1.15))
	Kit.add(root, vb, U, "Aisles", true)
	Interactable.attach(root, "Cereal Shelf", [
		_act("buy", "Buy Cereal", "cereal", 2.0, {"money": -4, "item": "Cereal"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(0.6, 1.9, 8.3), Vector3(2.7, 0.95, -5.15), Vector3(2.0, 0, -5.2))


# ------------------------------------------------------------------ checkout

static func _checkout(root: Node3D, _halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.035
	var x0 := u(1.6)
	var z0 := u(0.45)
	var W := u(0.85)
	var L := u(4.3)
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
	var kb := Vector3i(x0 + 9, by, belt0 + 34)   # ketchup, near the camera
	vb.box(kb, Vector3i(3, 7, 3), Color("d82a22"))
	vb.box(kb + Vector3i(1, 7, 1), Vector3i(1, 2, 1), Color("f2f2f2"))
	vb.box(kb + Vector3i(-1, 2, 0), Vector3i(1, 3, 3), Color("fbf3dc"))
	vb.box(Vector3i(x0 + 8, by, belt0 + 40), Vector3i(4, 3, 4), Color("f6c22c"))     # yellow box
	vb.box(Vector3i(x0 + 7, by + 1, belt0 + 40), Vector3i(1, 1, 4), Color("e8402f"))
	# candy rack at the front end of the counter
	var cr := Vector3i(x0 + 1, 0, z0 + L)
	vb.box(cr, Vector3i(W - 2, u(1.1), 2), Color("6a4a30"))
	for sy in 4:
		for sx in range(1, W - 3, 2):
			vb.box(cr + Vector3i(sx, 3 + sy * 4, 2), Vector3i(2, 3, 1), Fx.BOX_COLS[(sx + sy * 3) % Fx.BOX_COLS.size()])
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
	vb.box(Vector3i(u(3.55), 0, u(-0.2)), Vector3i(u(0.6), u(0.9), u(2.2)), Kit.wood(Fx.WOOD_D, 2))
	Kit.add(root, vb, U, "Checkout", true)
	# produce on the belt (fine grid)
	var pv := VoxelBuilder.new()
	pv.jitter = 0.05
	var py := (Hc + 2) * 2
	var b0 := z0 + u(0.9)
	Produce.bananas(pv, Vector3i((x0 + 2) * 2, py, (b0 + 28) * 2), 4)
	Produce.bananas(pv, Vector3i((x0 + 2) * 2 + 1, py + 2, (b0 + 28) * 2 + 1), 3)
	Produce.broccoli(pv, Vector3i((x0 + 3) * 2, py, (b0 + 22) * 2))
	Produce.lettuce(pv, Vector3i((x0 + 8) * 2, py, (b0 + 24) * 2))
	for t in 3:
		Produce.tomato(pv, Vector3i((x0 + 3) * 2 + t * 3, py, (b0 + 37) * 2 + (t % 2)))
	Produce.apple(pv, Vector3i((x0 + 3) * 2, py, (b0 + 41) * 2))
	Produce.apple(pv, Vector3i((x0 + 3) * 2 + 3, py, (b0 + 41) * 2 + 2))
	Kit.add(root, pv, P, "CheckoutProduce", true)
	Interactable.attach(root, "Checkout", [
		_act("pay", "Pay", "register", 3.0, {"task": "Pay at Checkout"}),
		_act("bag", "Bag Groceries", "bag", 2.0),
	], Vector3(0.85, 1.0, 4.3), Vector3(2.02, 0.5, 2.6), Vector3(1.2, 0, 1.0))
