extends RefCounted
## Market fixtures placed in the world: produce racks / crates (with heaped
## voxel fruit & veg and price tags), chalkboard, fridges, gondola aisles,
## bakery corner, checkout counter. Attaches Interactables.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")
const Stand := preload("res://scripts/locations/market/produce_stand.gd")
const Floor := preload("res://scripts/locations/market/floor_displays.gd")

const U := 0.0625
const P := 0.03125
const G := 0.05


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
		fix.box(o + Vector3i(1, 1, 1), Vector3i(w - 2, hh - 2, d - 2), Kit.shade(_kind_col(kind), 0.42))
		Produce.mini_heap(fix, kind, o + Vector3i(1, hh - 1, 1), Vector3i(w - 2, 4, d - 2), layers, seed)
		return
	# produce interior (P grid = 2x U grid), starting a bit below the rim
	var po := Vector3i(o.x * 2 + 2, o.y * 2 + hh * 2 - 4, o.z * 2 + 2)
	var ps := Vector3i(w * 2 - 4, 8, d * 2 - 4)
	# fill below the heap so the crate looks full
	prod.box(Vector3i(po.x, o.y * 2 + 2, po.z), Vector3i(ps.x, hh * 2 - 5, ps.z), Kit.shade(_kind_col(kind), 0.62))
	Produce.heap2(prod, kind, po, ps, layers + 1, seed)


## Like _crate but the produce goes into `big` on the coarse G grid.
static func _crate_g(fix: VoxelBuilder, big: VoxelBuilder, at: Vector3, size: Vector3, kind: String, seed: int, layers := 2) -> void:
	var o := Vector3i(u(at.x), u(at.y), u(at.z))
	Fx.crate(fix, o, u(size.x), u(size.z), u(size.y), Fx.WOOD)
	var g0 := Vector3i(int(round((at.x + U) / G)), int(round((at.y + size.y - 0.08) / G)), int(round((at.z + U) / G)))
	var gs := Vector3i(int((size.x - 2 * U) / G), 6, int((size.z - 2 * U) / G))
	big.box(Vector3i(g0.x, int(round((at.y + U) / G)), g0.z), Vector3i(gs.x, g0.y - int(round((at.y + U) / G)), gs.z), Kit.shade(_kind_col(kind), 0.62))
	Produce.heap2(big, kind, g0, gs, layers, seed)


static func _kind_col(kind: String) -> Color:
	match kind:
		"tomato", "apple", "pepper_red": return Color("b52620")
		"orange", "carrot": return Color("d56a12")
		"lemon", "banana": return Color("d6b02c")
		"greens", "lettuce", "broccoli", "green_apple": return Color("2f6e26")
		"grapes", "eggplant": return Color("4b2463")
	return Color("6a4a2a")


## Big white price card with dark text, facing +z rotated by rot_y.
static func _tag(root: Node3D, pos: Vector3, text: String, rot_y := 0.0) -> void:
	Floor.card(root, pos, text, rot_y, -30.0, 0.38, 0.23)


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
	var z := -8.0
	var sec := 0
	var xw := -6.7
	while z < -1.5:
		var lenz := 1.45
		var ks: Array = kinds[sec % kinds.size()]
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
	Interactable.attach(root, "Produce Wall", _produce_actions("Apples", 0.8), Vector3(1.6, 1.4, 6.2), Vector3(-5.9, 0.7, -4.5), Vector3(-4.6, 0, -4.5))


## Hero produce stand (tiered, angled crates) + floor crates around it.
static func _produce_island(root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	var wood := Kit.wood(Color("8f5a31"), 2)
	var stand := Stand.build(root, Vector3(-4.3, 0.0, 0.8), 18.0, [
		[["tomato", 3], ["pepper_mix", 3], ["banana", 2, 1.25]],
		[["carrot", 2], ["apple", 3], ["lettuce", 2]],
		[["broccoli", 2], ["orange", 3], ["greens", 2]],
	])
	_chalkboard(stand)
	# near-camera crates (lower-left foreground, softened by the DOF)
	# Low foreground display (bottom-left of the shot, soft in the DOF).
	fix.box(Vector3i(u(-3.1), 0, u(2.45)), Vector3i(u(2.75), u(0.38), u(0.95)), wood)
	# Near the lens the produce is stamped on a coarser grid (G) so each
	# tomato / carrot / banana reads as one big chunky item, not texture.
	var big := VoxelBuilder.new()
	big.jitter = 0.05
	var fx := -3.08
	for e: Array in [["tomato", 0.88, 84], ["carrot", 0.88, 85], ["banana", 0.92, 86]]:
		_crate_g(fix, big, Vector3(fx, 0.38, 2.47), Vector3(e[1], 0.26, 0.9), e[0], e[2], 2)
		fx += e[1] + 0.02
	Kit.add(root, big, G, "ProduceNear", false)
	_tag(root, Vector3(-2.65, 0.3, 3.42), "$1.20", 0.0)
	_tag(root, Vector3(-1.75, 0.3, 3.42), "$0.90", 0.0)
	_tag(root, Vector3(-0.85, 0.3, 3.42), "$0.60", 0.0)


## Mid-store produce table (background left of the aisle).
static func _produce_table(root: Node3D, fix: VoxelBuilder, prod: VoxelBuilder) -> void:
	for t: Vector2 in [Vector2(-4.3, -6.6)]:
		_table(fix, prod, t.x, t.y, int(t.y))
	# Mid-floor produce display tables (the open tile between the produce
	# stand, the aisles and the checkout): two-tier tables of tilted crates
	# heaped with chunky fruit & veg and big white price cards.
	Floor.table(root, Vector3(-1.6, 0, -1.45), 8.0, 25, [
		[["tomato", 3], ["carrot", 2], ["apple", 3]],
		[["banana", 2], ["lettuce", 2]],
	], "TableA")
	Floor.table(root, Vector3(0.4, 0, -2.05), 12.0, 26, [
		[["orange", 3], ["green_apple", 3], ["pepper_mix", 3]],
		[["broccoli", 2], ["lemon", 3], ["grapes", 2]],
	], "TableB")


static func _table(fix: VoxelBuilder, prod: VoxelBuilder, x0: float, z0: float, sd: int) -> void:
	fix.box(Vector3i(u(x0), 0, u(z0)), Vector3i(u(2.2), u(0.62), u(1.6)), Kit.wood(Color("8f5a31"), 2))
	var ks := ["orange", "green_apple", "lemon", "grapes"]
	for i in 4:
		var cx := x0 + 0.05 + (i % 2) * 1.08
		var cz := z0 + 0.05 + (i / 2) * 0.78
		_crate(fix, prod, Vector3(cx, 0.62, cz), Vector3(1.04, 0.2, 0.74), ks[(i - sd) % 4], 60 + i - sd, 2, Fx.WOOD, false)


static func _chalkboard(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var W := 14
	var Hh := 22
	for x in W:
		for y in Hh:
			var edge := x < 1 or x >= W - 1 or y < 1 or y >= Hh - 1
			vb.set_v(Vector3i(x, y + 10, 0), Kit.vary(Fx.WOOD, Vector3i(x, y, 0), 0.08) if edge else Kit.vary(Color("2b302d"), Vector3i(x, y, 0), 0.05))
	for y in 11:
		vb.set_v(Vector3i(1, y, -1), Fx.WOOD_D)
		vb.set_v(Vector3i(W - 2, y, -1), Fx.WOOD_D)
	var lv := VoxelBuilder.new()
	Fx.leaf_icon(lv, Vector3i(6, 11, 1), Color("6cbf45"), Color("2f7a2a"))
	for p: Vector3i in lv.vox:
		vb.set_v(p, lv.vox[p])
	# Mounted on the produce stand's back board, top right, above the tiers.
	var mi := Kit.add(root, vb, U, "Chalkboard", true, null,
		Vector3(8 * U, 0.95, -(3 * Stand.T + 1) * U + 0.24), Vector3(W * 0.5, 0, 0))
	var l := Kit.label(mi, "Local\nFresh\nToday!", Vector3(-0.04, 1.52, 0.075), 0.0024, Color("f4f1e6"), 0.0, 96)
	l.rotation.z = deg_to_rad(4)
	l.line_spacing = -18.0


# ------------------------------------------------------------------ fridges

static func _fridges(root: Node3D, halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var bank := Fx.fridge(u(6.4), 3)
	Fx.put(vb, bank, Vector3i(u(-4.4), 0, u(-8.7)))
	# second bank on the right of the back wall (beverages, behind the aisles)
	var bank2 := Fx.fridge(u(5.6), 9, true, false)
	Fx.put(vb, bank2, Vector3i(u(2.1), 0, u(-8.7)))
	Kit.add(root, vb, U, "Fridges", false, Kit.glow_mat("cool"), Vector3.ZERO, Vector3.ZERO, true)
	# Soft cool bloom along the lit header strips and inside the cases.
	for i in 16:
		var hx := -4.0 + i * 0.75
		halo_pts.append([Vector3(hx, 2.42, -7.9), 0.9, Color(0.45, 0.6, 0.85, 1.0)])
	Interactable.attach(root, "Dairy Fridge", [
		_act("buy", "Buy Milk", "milk", 2.0, {"money": -2, "item": "Milk"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(6.4, 2.1, 0.8), Vector3(-1.2, 1.05, -8.25), Vector3(-1.2, 0, -7.2))


# ------------------------------------------------------------------ aisles

static func _aisles(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.0
	var kinds_a := ["cereal", "box", "bag", "cereal", "box", "cereal"]
	var kinds_b := ["box", "cereal", "bag", "jar", "box", "can"]
	var kinds_c := ["bottle", "can", "bottle", "jar", "bottle"]
	# Gondola rows run along z (deep into the store) so the aisles recede
	# towards the back fridges; each is double-sided and faces the main aisle
	# (-x) and the next aisle (+x). End caps face the camera.
	# Long runs from just behind the end caps back to the fridge walkway,
	# split by a cross aisle so a second row of end caps reads mid-store.
	# (the run against the right wall is mostly hidden: cheap two-tone stock)
	# The two middle runs are double-sided: the camera sits right of the
	# main aisle, so it sees their +x faces stocked too.
	for seg: Array in [[2.6, -6.6, 3.3, 11, kinds_a, false, true], [5.5, -6.6, 3.3, 12, kinds_b, false, true],
			[7.7, -8.0, 4.2, 5, kinds_c, false, false]]:
		var g := Fx.gondola(u(seg[2]), seg[3], seg[4], seg[6], 0, seg[5])
		Fx.put(vb, g, Vector3i(u(seg[0]), 0, u(seg[1])), 3)
	# Camera-facing end caps on the fine P grid: real-size packs in many
	# distinct designs (cereal with bowl / mascot / swoosh fronts, crackers,
	# chips, sauces, juice, jars, pasta, soda) mixed per shelf.
	var ec := VoxelBuilder.new()
	ec.jitter = 0.0
	var mix_a := ["cereal_bowl", "cereal_bear", "cereal_swoosh", "crackers", "canister", "pasta", "juice"]
	var mix_b := ["cereal_swoosh", "cereal_bowl", "chips", "sauce", "cereal_bear", "jar", "crackers", "soda", "pasta", "juice"]
	var e1 := Fx.endcap(32, 4, mix_a)
	ec.stamp(e1, Vector3i(int(round(2.1 / P)), 0, int(round(-3.3 / P))))
	var e2 := Fx.endcap(60, 6, mix_b)
	ec.stamp(e2, Vector3i(int(round(4.1 / P)), 0, int(round(-3.3 / P))))
	# Low display table of cereal boxes with a pot of flowers (centre-right).
	var d := Vector3i(u(1.75), 0, u(-0.35))
	vb.box(d, Vector3i(u(1.0), u(0.55), u(0.7)), Kit.wood(Fx.WOOD, 2))
	var dp := Vector3i(d.x * 2, u(0.55) * 2, d.z * 2)
	var table_mix := ["cereal_bowl", "cereal_swoosh", "cereal_bear", "crackers"]
	var tx := 1
	var ti := 0
	while tx < 30:
		var tmp := VoxelBuilder.new()
		var sz := Fx.pack(tmp, Vector3i.ZERO, table_mix[ti % table_mix.size()], ti * 5 + 2, 11, ti)
		if tx + sz.x > 31:
			break
		for row in 2:
			ec.stamp(tmp, dp + Vector3i(tx, 0, 21 - sz.z * (row + 1) - row))
		tx += sz.x + 1
		ti += 1
	Kit.add(root, ec, P, "EndCaps", false, null, Vector3.ZERO, Vector3.ZERO, true)
	# Flower bucket on top.
	var fpos := d + Vector3i(6, u(0.55), 1)
	vb.box(fpos, Vector3i(4, 3, 4), Color("b55f33"))
	fpos += Vector3i(0, 3, 0)
	vb.box(fpos, Vector3i(4, 3, 4), Color("c96f3e"))
	for i in 22:
		var fp := fpos + Vector3i(int(Kit.h(Vector3i(i, 0, 0), 1) * 6.0) - 1, 3 + int(Kit.h(Vector3i(i, 1, 0), 2) * 4.0), int(Kit.h(Vector3i(i, 2, 0), 3) * 6.0) - 1)
		var fc: Color = [Color("f06a9a"), Color("f9a8c8"), Color("ffffff"), Color("f5d03b")][i % 4]
		vb.set_v(fp, fc)
		vb.set_v(fp - Vector3i(0, 1, 0), Color("3f8a2e"))
	# Bakery corner (right-front wall): open bread shelves with baskets of
	# chunky loaves, baguettes and boules, under a warm lamp.
	var bk := Vector3i(u(6.6), 0, u(-3.6))
	var bl := u(2.8)
	vb.box(bk, Vector3i(u(1.1), u(1.75), bl), Kit.wood(Fx.WOOD_D, 3))
	vb.box(bk + Vector3i(-3, u(1.75), -1), Vector3i(u(1.1) + 3, 2, bl + 2), Kit.wood(Color("6e4428"), 1))
	var crust: Array[Color] = [Color("c98a42"), Color("b06f32"), Color("dba65e"), Color("9c5f2a")]
	for sh in 3:
		var y := u(0.32 + sh * 0.48)
		vb.box(bk + Vector3i(-4, y, 0), Vector3i(5, 1, bl), Kit.wood(Fx.WOOD_L, 1, 1))
		var zc := 1
		var item := 0
		while zc < bl - 6:
			var kind := (item + sh * 2) % 3
			var cc: Color = crust[(item + sh) % 4]
			var bp := bk + Vector3i(-4, y + 1, zc)
			match kind:
				0: # wicker basket of baguettes leaning back
					vb.box(bp, Vector3i(4, 2, 6), Color("b98a4e"))
					for k in 3:
						for t in 6:
							vb.set_v(bp + Vector3i(1 + k, 2 + t, 1 + k * 2), Kit.shade(cc, 1.0 + 0.1 * (t % 2)))
							vb.set_v(bp + Vector3i(2 + k / 2, 2 + t, 1 + k * 2), Kit.shade(cc, 0.9))
					zc += 7
				1: # round boule with a scored top
					vb.box(bp + Vector3i(0, 0, 0), Vector3i(4, 3, 5), cc)
					vb.box(bp + Vector3i(1, 3, 1), Vector3i(2, 1, 3), Kit.shade(cc, 1.15))
					vb.set_v(bp + Vector3i(0, 2, 2), Color("f0d29a"))
					zc += 6
				_: # sandwich loaves, two side by side
					for k in 2:
						vb.box(bp + Vector3i(0, 0, k * 4), Vector3i(4, 3, 3), cc)
						vb.box(bp + Vector3i(0, 3, k * 4), Vector3i(4, 1, 3), Kit.shade(cc, 1.18))
					zc += 9
			item += 1
	Kit.add(root, vb, U, "Aisles", false, null, Vector3.ZERO, Vector3.ZERO, true)
	Interactable.attach(root, "Cereal Shelf", [
		_act("buy", "Buy Cereal", "cereal", 2.0, {"money": -4, "item": "Cereal"}),
		_act("compare", "Compare", "scale", 3.0),
	], Vector3(0.6, 1.9, 3.3), Vector3(2.1, 0.95, -5.0), Vector3(1.6, 0, -5.0))


# ------------------------------------------------------------------ checkout

static func _checkout(root: Node3D, _halo_pts: Array) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.035
	var x0 := u(2.9)
	var z0 := u(-0.1)
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
	var bx := u(5.0)
	var bz := u(-0.2)
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
	Produce.big_bananas(pv, Vector3i((x0 + 3) * 2, py, (b0 + 21) * 2), 3, 5)
	Produce.big_bananas(pv, Vector3i((x0 + 3) * 2 + 2, py + 3, (b0 + 21) * 2 + 2), 4, 4)
	Produce.big_broccoli(pv, Vector3i((x0 + 3) * 2, py, (b0 + 15) * 2), 2)
	Produce.big_lettuce(pv, Vector3i((x0 + 7) * 2, py, (b0 + 9) * 2), 3)
	for t in 3:
		Produce.big_tomato(pv, Vector3i((x0 + 3) * 2 + t * 5, py, (b0 + 29) * 2 + (t % 2) * 2), t + 5)
	Produce.big_apple(pv, Vector3i((x0 + 3) * 2, py, (b0 + 35) * 2), 1)
	Produce.big_apple(pv, Vector3i((x0 + 3) * 2 + 5, py, (b0 + 35) * 2 + 2), 2)
	Produce.big_apple(pv, Vector3i((x0 + 3) * 2 + 2, py + 4, (b0 + 35) * 2 + 1), 3, true)
	Kit.add(root, pv, P, "CheckoutProduce", false)
	Interactable.attach(root, "Checkout", [
		_act("pay", "Pay", "register", 3.0, {"task": "Pay at Checkout"}),
		_act("bag", "Bag Groceries", "bag", 2.0),
	], Vector3(0.85, 1.0, 4.2), Vector3(3.32, 0.5, 2.0), Vector3(2.45, 0, 1.3))


# ------------------------------------------------------------------ foreground dressing

## Fine-grid (P) props near the camera: a flower stand, a stack of shopping
## baskets and a basket of apples on the floor. One mesh.
static func _foreground(root: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	# Flower bucket stand (bottom right, by the checkout) and a pallet of
	# stacked boxed goods (bottom centre, soft in the tilt-shift band).
	Floor.flowers(vb, Vector3(1.75, 0, 2.45), 0)
	Floor.pallet(vb, Vector3(0.2, 0, 3.0), 3)
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
