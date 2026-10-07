extends RefCounted
## The hero produce display (left mid-ground of ref5): three tall tiers of
## sloped, angled-forward crates rising towards a back board, heaped with
## LARGE voxel produce (tomatoes, peppers, bananas, carrots, apples, greens)
## and fronted by chalkboard price tags.
##
## Built in local space (front-left corner at the origin, facing +z, tiers
## rising towards -z) then placed and yawed towards the main aisle.
## Wood is on the U grid (one mesh, casts shadows), produce on a coarser
## PB grid (one mesh) so each item is big and cheap.

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")

const U := 0.0625
const PB := 0.048

const T := 12           # tier depth (cells)
const W := 46           # stand width (cells)
const RISE := 5         # slope rise per tier (cells)
const STEP := 7         # front-lip height step between tiers (cells)

const NAMES := {"broccoli": "Broccoli", "lettuce": "Lettuce", "apple": "Apples", "greens": "Greens", "tomato": "Tomatoes",
	"pepper_red": "Peppers", "carrot": "Carrots", "banana": "Bananas", "pepper_mix": "Peppers", "orange": "Oranges",
	"green_apple": "Green Apples", "lemon": "Lemons", "grapes": "Grapes"}
const PRICES := {"broccoli": 1.8, "lettuce": 1.5, "apple": 0.8, "greens": 1.5, "tomato": 1.2,
	"pepper_red": 2.3, "carrot": 0.9, "banana": 0.6, "pepper_mix": 2.3, "orange": 1.1, "green_apple": 0.9,
	"lemon": 0.7, "grapes": 2.5}


## Bin floor height (cells, top voxel y) of tier t at depth cell k (0 = front).
static func floor_y(t: int, k: int) -> int:
	return 6 + t * STEP + (k * RISE) / (T - 1)


static func build(root: Node3D, pos: Vector3, yaw_deg: float, layout: Array, priced_tiers := 1) -> Node3D:
	var node := Node3D.new()
	node.name = "ProduceStand"
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	root.add_child(node)
	var wood := VoxelBuilder.new()
	wood.jitter = 0.0
	var prod := VoxelBuilder.new()
	prod.jitter = 0.05
	var tiers := layout.size()
	var plank := Kit.wood(Color("9a643a"), 2)
	var dark := Color("4a2f1c")
	var lip_col := Color("c08550")
	var labels := []
	for t in tiers:
		var bins: Array = layout[t]
		var nb := bins.size()
		# divider x positions (cells): 0, ..., W-1
		var wsum := 0.0
		for e: Array in bins:
			wsum += float(e[2]) if e.size() > 2 else 1.0
		var xs: Array[int] = [0]
		var acc := 0.0
		for e: Array in bins:
			acc += float(e[2]) if e.size() > 2 else 1.0
			xs.append(int(round(acc / wsum * (W - 1))))
		for k in T:
			var z := -1 - (t * T + k)
			var fy := floor_y(t, k)
			# solid riser under the bin floor (planked front on the first row)
			wood.box(Vector3i(0, 0, z), Vector3i(W, fy, 1), plank if k > 0 else Kit.wood(Color("8a5530"), 2))
			# bin floor (dark, shows through gaps between fruit)
			wood.box(Vector3i(0, fy, z), Vector3i(W, 1, 1), dark)
			# side boards + dividers, 3 cells above the floor
			for xi in xs.size():
				var x: int = xs[xi]
				for y in 2:
					wood.set_v(Vector3i(x, fy + 1 + y, z), Kit.shade(lip_col, 0.86 if y == 1 else 1.0))
		# front lip: two planks across the whole tier front
		var f0 := floor_y(t, 0)
		wood.box(Vector3i(0, f0 + 1, -1), Vector3i(W, 1, 1), func(p: Vector3i) -> Color:
			return Kit.shade(lip_col, 0.92 + 0.14 * Kit.h(Vector3i(p.x / 9, p.y, t), 3)))
		wood.box(Vector3i(0, f0 - 1, 0), Vector3i(W, 1, 1), Kit.shade(lip_col, 0.8))
		for b in nb:
			var e: Array = bins[b]
			var kind: String = e[0]
			var xa: int = xs[b] + 1
			var xb: int = xs[b + 1]
			# produce, on the PB grid, following the slope
			var x0m := xa * U + 0.01
			var wm := (xb - xa) * U - 0.02
			var zf := -(t * T + 1) * U - 0.005
			var dm := T * U - 0.05
			var yfm := (f0 + 1) * U
			var ybm := (floor_y(t, T - 1) + 1) * U
			Produce.slope_heap(prod, kind, x0m / PB, wm / PB, zf / PB, dm / PB, yfm / PB, ybm / PB, 300 + t * 17 + b * 5, e[1] if e.size() > 1 else 2)
			# chalk price tag hanging off the lip
			if t < priced_tiers:
				var cx := (xa + xb) / 2
				var tw := 9
				var th := 5
				var ty := f0 - th if t == 0 else f0 - 2
				for x in tw:
					for y in th:
						var edge := x == 0 or y == 0 or x == tw - 1 or y == th - 1
						var p := Vector3i(cx - tw / 2 + x, ty + y, 0)
						wood.set_v(p, Kit.vary(Color("8a5a31"), p, 0.08, 2) if edge else Kit.vary(Color("26282a"), p, 0.04, 3))
				labels.append([Vector3((cx + 0.0) * U, (ty + th * 0.5) * U, U + 0.004), "$%.2f" % PRICES.get(kind, 1.0)])
			var nm: String = NAMES.get(kind, kind.capitalize())
			Interactable.attach(node, nm, _actions(nm, PRICES.get(kind, 1.0)),
				Vector3((xb - xa) * U, 0.45, T * U),
				Vector3((xa + xb) * 0.5 * U, (f0 + 4) * U, -(t * T + T * 0.5) * U),
				Vector3((xa + xb) * 0.5 * U, 0, 0.7))
	# back board + top shelf with a slatted header
	var zb := -1 - tiers * T
	var top := floor_y(tiers - 1, T - 1) + 14
	wood.box(Vector3i(0, 0, zb), Vector3i(W, top, 1), Kit.wood(Color("8a5530"), 2))
	wood.box(Vector3i(-1, top, zb - 1), Vector3i(W + 2, 2, 4), Kit.wood(Color("6e4428"), 1))
	# baskets of fruit along the top shelf (seen over the tiers)
	var kinds_top := ["apple", "lemon", "orange"]
	for b in 2:
		var bx := 17 + b * 15
		var bw := 14
		for x in bw:
			for z in 4:
				for y in 3:
					var edge := x == 0 or x == bw - 1 or z == 0 or z == 3
					if edge or y == 0:
						wood.set_v(Vector3i(bx + x, top + 2 + y, zb - 1 + z), Kit.shade(Color("c99a5c"), 0.9 if y == 1 else 1.0))
		Produce.slope_heap(prod, kinds_top[b], (bx + 1) * U / PB, (bw - 2) * U / PB, (zb + 3) * U / PB, 2.5 * U / PB,
			(top + 3) * U / PB, (top + 3) * U / PB, 500 + b, 2)
	# uprights at both ends
	for x in [-1, W]:
		wood.box(Vector3i(x, 0, zb), Vector3i(1, top + 2, tiers * T + 1), Kit.wood(Fx.WOOD_D, 2))
	Kit.add(node, wood, U, "StandWood", true, null, Vector3.ZERO, Vector3.ZERO, true)
	Kit.add(node, prod, PB, "StandProduce", false)
	# Chalk price text (one Label3D per tag).
	var f := Kit.font()
	for lb: Array in labels:
		var txt: String = lb[1]
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 128)
		var px := minf(0.44 / maxf(sz.x, 1.0), 0.2 / maxf(sz.y * 0.75, 1.0))
		Kit.label(node, txt, lb[0], px, Color("f7f3e6"), 0.0, 128)
	return node


static func _actions(item: String, price: float) -> Array:
	return [
		{"id": "buy", "label": "Buy", "icon": "cart", "minutes": 2.0, "needs": {}, "pose": "idle",
			"money": -int(ceil(price)), "price": price, "item": item, "task": "Buy Groceries"},
		{"id": "compare", "label": "Compare", "icon": "scale", "minutes": 3.0, "needs": {}, "pose": "idle", "item": item},
	]
