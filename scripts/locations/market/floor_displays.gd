extends RefCounted
## Mid-floor merchandising for the market (ref5 has no bare floor between
## the fixtures): two-tier produce display tables heaped with chunky voxel
## fruit & veg and big white price cards, a pallet of stacked boxed goods,
## and a flower bucket stand. Wood on the U grid, produce on the coarser PB
## grid (so every tomato / apple / carrot reads as one item from the high
## Sims camera), packaged goods on the P grid.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")
const Stand := preload("res://scripts/locations/market/produce_stand.gd")

const U := 0.0625
const P := 0.03125
const PB := 0.045

const T := 8        # tier depth (cells)
const RISE := 3     # slope rise across one tier (cells)
const STEP := 6     # front-lip height step between tiers (cells)
const F0 := 8       # tier-0 front floor height (cells, 0.5 m)

const CARD := Color("fdfbf4")
const CARD_EDGE := Color("2f7f3b")
const CARD_INK := Color("23302a")


static func floor_y(t: int, k: int) -> int:
	return F0 + t * STEP + (k * RISE) / (T - 1)


## Two-tier wooden produce table. Local space: front-left corner at origin,
## facing +z, tiers rising towards -z. layout: [tier][bin] = [kind, layers].
## Returns the node (placed at pos, yawed by yaw_deg).
static func table(root: Node3D, pos: Vector3, yaw_deg: float, width: int, layout: Array, nm := "DisplayTable") -> Node3D:
	var node := Node3D.new()
	node.name = nm
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(node)
	var wood := VoxelBuilder.new()
	wood.jitter = 0.0
	var prod := VoxelBuilder.new()
	prod.jitter = 0.05
	var plank := Kit.wood(Color("a06a3c"), 2)
	var dark := Color("4a2f1c")
	var lip := Color("c99258")
	var cards := []
	var tiers := layout.size()
	for t in tiers:
		var bins: Array = layout[t]
		var nb := bins.size()
		var xs: Array[int] = []
		for b in nb + 1:
			xs.append(int(round(float(b) / nb * (width - 1))))
		for k in T:
			var z := -1 - (t * T + k)
			var fy := floor_y(t, k)
			wood.box(Vector3i(0, 0, z), Vector3i(width, fy, 1), plank if k > 0 or t > 0 else Kit.wood(Color("8a5530"), 2))
			wood.box(Vector3i(0, fy, z), Vector3i(width, 1, 1), dark)
			for x: int in xs:
				for y in 3:
					wood.set_v(Vector3i(x, fy + 1 + y, z), Kit.shade(lip, 0.84 if y == 1 else 1.0))
		var f0 := floor_y(t, 0)
		# crate fronts: one board per bin with a dark gap between crates
		for b in nb:
			wood.box(Vector3i(xs[b], f0 + 1, -1 - t * T), Vector3i(xs[b + 1] - xs[b] + 1, 2, 1), func(p: Vector3i) -> Color:
				return Kit.shade(lip, (0.86 if p.y == f0 + 2 else 1.02) + 0.1 * Kit.h(Vector3i(b, t, 3), 5)))
		for b in nb:
			var e: Array = bins[b]
			var kind: String = e[0]
			var xa: int = xs[b] + 1
			var xb: int = xs[b + 1]
			var x0m := xa * U + 0.01
			var wm := (xb - xa) * U - 0.02
			var zf := -(t * T + 1) * U - 0.004
			var dm := T * U - 0.04
			var yfm := (f0 + 1) * U
			var ybm := (floor_y(t, T - 1) + 1) * U
			Produce.slope_heap(prod, kind, x0m / PB, wm / PB, zf / PB, dm / PB, yfm / PB, ybm / PB,
				700 + t * 13 + b * 7 + width, e[1] if e.size() > 1 else 2)
			var price: float = Stand.PRICES.get(kind, 1.0)
			var cx := (xa + xb) * 0.5 * U
			if t == 0:
				# big white card hanging on the table front, under the crate
				cards.append([Vector3(cx, (f0 - 3.5) * U, 0.0), price, false])
			else:
				# card on a stake, standing up out of the back crate
				cards.append([Vector3(cx + (xb - xa) * U * 0.28, (floor_y(t, 2) + 11) * U, -(t * T + 2) * U), price, true])
			var nmk: String = Stand.NAMES.get(kind, kind.capitalize())
			Interactable.attach(node, nmk, Stand._actions(nmk, price),
				Vector3((xb - xa) * U, 0.45, T * U),
				Vector3(cx, (f0 + 4) * U, -(t * T + T * 0.5) * U),
				Vector3(cx, 0, 0.7))
	# low back board + end posts
	var zb := -1 - tiers * T
	var top := floor_y(tiers - 1, T - 1) + 4
	wood.box(Vector3i(0, 0, zb), Vector3i(width, top, 1), Kit.wood(Color("8a5530"), 2))
	for x in [-1, width]:
		wood.box(Vector3i(x, 0, zb), Vector3i(1, top + 1, tiers * T + 1), Kit.wood(Fx.WOOD_D, 2))
	# kick shadow strip
	wood.box(Vector3i(0, 0, 0), Vector3i(width, 1, 1), Color("3a2a1e"))
	# stakes for the back-tier cards
	for c: Array in cards:
		if c[2]:
			var at: Vector3 = c[0]
			for y in range(2, 10):
				wood.set_v(Vector3i(int(round(at.x / U)), int(round(at.y / U)) - y, int(round(at.z / U)) - 1), Color("c9a06a"))
	Kit.add(node, wood, U, nm + "Wood", true, null, Vector3.ZERO, Vector3.ZERO, true)
	Kit.add(node, prod, PB, nm + "Produce", false)
	for c: Array in cards:
		card(node, c[0] + Vector3(0, 0, 0.03), "$%.2f" % c[1], 0.0, -32.0 if not c[2] else -22.0)
	return node


static var _card_mat: StandardMaterial3D
static var _card_mesh: QuadMesh


## Big white price card (green rim, dark price) facing +z, tilted back by
## tilt_deg so it reads from the high camera. Bright even in shadow.
static func card(parent: Node3D, pos: Vector3, text: String, rot_y := 0.0, tilt_deg := -30.0, w := 0.42, h := 0.25) -> MeshInstance3D:
	if _card_mat == null:
		var img := Image.create(84, 50, false, Image.FORMAT_RGB8)
		img.fill(CARD)
		for x in 84:
			for y in 50:
				if x < 5 or y < 5 or x >= 79 or y >= 45:
					img.set_pixel(x, y, CARD_EDGE)
				elif x < 7 or y < 7 or x >= 77 or y >= 43:
					img.set_pixel(x, y, Color("e6eedf"))
		_card_mat = StandardMaterial3D.new()
		_card_mat.albedo_texture = ImageTexture.create_from_image(img)
		_card_mat.emission_enabled = true
		_card_mat.emission = Color(1, 0.98, 0.94)
		_card_mat.emission_energy_multiplier = 0.25
		_card_mat.emission_texture = _card_mat.albedo_texture
		_card_mat.roughness = 0.9
		_card_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_card_mesh = QuadMesh.new()
		_card_mesh.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.name = "PriceCard"
	mi.mesh = _card_mesh
	mi.material_override = _card_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(tilt_deg), deg_to_rad(rot_y), 0.0)
	mi.scale = Vector3(w, h, 1.0)
	parent.add_child(mi)
	var f := Kit.font()
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 128)
	var px := minf(w * 0.8 / maxf(sz.x, 1.0), h * 0.62 / maxf(sz.y * 0.75, 1.0))
	var l := Kit.label(parent, text, Vector3.ZERO, px, CARD_INK, 0.0, 128)
	l.reparent(mi, false)
	l.position = Vector3(0, -0.02, 0.01)
	l.scale = Vector3(1.0 / w, 1.0 / h, 1.0)
	return mi


## Wooden pallet with a stepped stack of boxed goods (cereal, crackers,
## juice) facing +z, plus cardboard cases behind. P grid. at: min corner (m).
static func pallet(vb: VoxelBuilder, at: Vector3, seed: int) -> void:
	var o := Vector3i(int(round(at.x / P)), 0, int(round(at.z / P)))
	var W := 30
	var D := 24
	# pallet: slats + blocks
	for x in W:
		for z in D:
			if z % 4 != 3:
				vb.set_v(o + Vector3i(x, 3, z), Kit.vary(Color("c49a62"), o + Vector3i(x, 3, z), 0.06))
			if (x < 3 or x >= W - 3 or (x >= 13 and x < 17)) and (z < 3 or z >= D - 3 or (z >= 10 and z < 14)):
				for y in 3:
					vb.set_v(o + Vector3i(x, y, z), Color("a77c48"))
	# back: brown cardboard cases, two high
	var cx := 0
	var k := 0
	while cx < W - 6:
		var cw := 9 + (k % 2) * 3
		cw = mini(cw, W - cx)
		for lvl in 2 + (k % 2):
			var cb := Color("c99a62") if (k + lvl) % 2 == 0 else Color("b8864e")
			vb.box(o + Vector3i(cx, 4 + lvl * 8, 1), Vector3i(cw - 1, 8, 9), Kit.noise(cb, 0.05, k + lvl))
			vb.box(o + Vector3i(cx + 1, 4 + lvl * 8 + 5, 10), Vector3i(cw - 3, 1, 1), Color("fbf3dc"))
			vb.box(o + Vector3i(cx + 2, 4 + lvl * 8 + 2, 10), Vector3i(3, 2, 1), Fx.BOX_COLS[(k + lvl + seed) % Fx.BOX_COLS.size()])
		cx += cw
		k += 1
	# front: two rows of chunky retail packs, stepped
	var mix := ["cereal_bear", "cereal_bowl", "crackers", "cereal_swoosh", "juice", "pasta"]
	for row in 2:
		var x := 1
		var i := 0
		while x < W - 4:
			var tmp := VoxelBuilder.new()
			var sz := Fx.pack(tmp, Vector3i.ZERO, mix[(i + row * 2 + seed) % mix.size()], i * 5 + row * 3 + seed, 12, i + row)
			if x + sz.x > W:
				break
			var zz := D - 1 - sz.z - row * (sz.z + 1)
			var y0 := 4 + row * 2
			for p: Vector3i in tmp.vox:
				vb.set_v(o + Vector3i(x, y0, zz) + p, tmp.vox[p])
			# a second pack stacked on the back row
			if row == 1 and i % 2 == 0:
				for p: Vector3i in tmp.vox:
					vb.set_v(o + Vector3i(x, y0 + sz.y, zz) + p, tmp.vox[p])
			x += sz.x + 1
			i += 1


## Tiered flower bucket stand (P grid). at: min corner (metres).
static func flowers(vb: VoxelBuilder, at: Vector3, seed: int) -> void:
	var fo := Vector3i(int(round(at.x / P)), 0, int(round(at.z / P)))
	Fx.crate(vb, fo, 30, 18, 10, Color("a8703f"))
	vb.box(fo + Vector3i(1, 1, 1), Vector3i(28, 8, 16), Color("6a4528"))
	# raised back step
	vb.box(fo + Vector3i(0, 10, 0), Vector3i(30, 5, 8), Kit.wood(Color("8a5530"), 2))
	var fcols := [[Color("f06a9a"), Color("f9a8c8")], [Color("fdf6ea"), Color("f5d03b")], [Color("ef5a5a"), Color("f7a14a")],
		[Color("b58ee0"), Color("fdf6ea")], [Color("f5d03b"), Color("f7a14a")]]
	for b in 5:
		var back := b >= 3
		var bo := fo + Vector3i(2 + (b % 3) * 9 + (4 if back else 0), 15 if back else 9, 1 if back else 9)
		var pail := Color("8fa3ad") if (b + seed) % 2 == 0 else Color("c96f3e")
		for x in 7:
			for z in 7:
				for y in 6:
					var edge := x == 0 or x == 6 or z == 0 or z == 6
					if edge or y == 0:
						vb.set_v(bo + Vector3i(x, y, z), Kit.vary(pail, Vector3i(x, y, z), 0.06))
		var cc: Array = fcols[(b + seed) % fcols.size()]
		for i in 20:
			var key := Vector3i(i, b, seed)
			var hx := 1 + int(Kit.h(key, 2) * 5.0)
			var hz := 1 + int(Kit.h(key, 3) * 5.0)
			var top := 7 + int(Kit.h(key, 4) * 7.0)
			for y in range(5, top):
				vb.set_v(bo + Vector3i(hx, y, hz), Color("3f8a2e") if y % 3 else Color("5aa83a"))
			var col: Color = cc[i % 2]
			var bp := bo + Vector3i(hx, top, hz)
			vb.set_v(bp, col)
			for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				vb.set_v(bp + d, Kit.shade(col, 0.92))
			vb.set_v(bp + Vector3i(0, 1, 0), Color("f5d03b") if (b + seed) % 3 != 1 else Color("e8902a"))
		for i in 8:
			var lp := bo + Vector3i(int(Kit.h(Vector3i(i, b, 7), 1) * 7.0), 6, int(Kit.h(Vector3i(i, b, 8), 2) * 7.0))
			vb.set_v(lp, Color("4f9e34"))
