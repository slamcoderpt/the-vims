extends RefCounted
## Small helpers shared by the prop model files (scripts/props/*.gd).
## Everything is static; models write straight into a VoxelBuilder.


static func b(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int, c, glow := false) -> void:
	vb.box(Vector3i(x, y, z), Vector3i(w, h, d), c, glow)


static func p(vb: VoxelBuilder, x: int, y: int, z: int, c: Color, glow := false) -> void:
	vb.set_v(Vector3i(x, y, z), c, glow)


static func hs(x: int, y: int, z: int) -> float:
	return VoxelBuilder.hash3(Vector3i(x, y, z))


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), 1.0)


## Per-voxel brightness noise (amt 0..1).
static func noisy(c: Color, amt := 0.08, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		return shade(c, 1.0 + (VoxelBuilder.hash3(q + Vector3i(seed, seed * 3, seed * 7)) - 0.5) * 2.0 * amt)


## Random pick from a palette per voxel.
static func mix(cols: Array, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		var i := int(VoxelBuilder.hash3(q + Vector3i(seed, 17, seed)) * cols.size()) % cols.size()
		return cols[i]


## Wood with boards running along `axis` (0=x,1=y,2=z), `bw` cells per board.
static func wood(c: Color, axis := 0, bw := 3, amt := 0.07) -> Callable:
	return func(q: Vector3i) -> Color:
		var board: int
		var along: int
		match axis:
			0:
				board = floori(q.z / float(bw)) * 31 + floori(q.y / float(bw)) * 7; along = q.x
			1:
				board = floori(q.x / float(bw)) * 31 + floori(q.z / float(bw)) * 7; along = q.y
			_:
				board = floori(q.x / float(bw)) * 31 + floori(q.y / float(bw)) * 7; along = q.z
		var tone := (VoxelBuilder.hash3(Vector3i(board, 5, 11)) - 0.5) * 0.16
		var grain := (VoxelBuilder.hash3(Vector3i(board, along / 3, 3)) - 0.5) * amt
		return shade(c, 1.0 + tone + grain)


static func checker(a: Color, bcol: Color, s := 1) -> Callable:
	return func(q: Vector3i) -> Color:
		return a if (floori(q.x / float(s)) + floori(q.y / float(s)) + floori(q.z / float(s))) % 2 == 0 else bcol


## Gingham / plaid on the XZ plane (or XY when `vertical`).
static func plaid(base: Color, line: Color, cross: Color, s := 3, vertical := false) -> Callable:
	return func(q: Vector3i) -> Color:
		var u := q.x
		var v := q.y if vertical else q.z
		var a := posmod(u, s) == 0
		var bb := posmod(v, s) == 0
		if a and bb:
			return cross
		if a or bb:
			return line
		return base


## Filled vertical cylinder (centre cx,cz; radius r in cells).
static func cyl(vb: VoxelBuilder, cx: float, y: int, cz: float, r: float, h: int, c, glow := false) -> void:
	var ri := ceili(r)
	for x in range(floori(cx - ri), ceili(cx + ri) + 1):
		for z in range(floori(cz - ri), ceili(cz + ri) + 1):
			var dx := x + 0.5 - cx
			var dz := z + 0.5 - cz
			if dx * dx + dz * dz <= r * r:
				for yy in h:
					var q := Vector3i(x, y + yy, z)
					var col: Color = c.call(q) if c is Callable else c
					vb.set_v(q, col, glow)


## Blobby sphere/ellipsoid. `shell` > 0 only fills the outer `shell` cells.
static func blob(vb: VoxelBuilder, center: Vector3, rad: Vector3, c, shell := 0.0, rough := 0.25, seed := 0) -> void:
	for x in range(floori(center.x - rad.x - 1), ceili(center.x + rad.x + 1)):
		for y in range(floori(center.y - rad.y - 1), ceili(center.y + rad.y + 1)):
			for z in range(floori(center.z - rad.z - 1), ceili(center.z + rad.z + 1)):
				var d := Vector3((x + 0.5 - center.x) / rad.x, (y + 0.5 - center.y) / rad.y, (z + 0.5 - center.z) / rad.z)
				var l := d.length()
				var lim := 1.0 + (VoxelBuilder.hash3(Vector3i(x, y, z) + Vector3i(seed, 0, seed)) - 0.5) * rough
				if l > lim:
					continue
				if shell > 0.0 and l < lim - shell / maxf(rad.x, 1.0):
					continue
				var q := Vector3i(x, y, z)
				var col: Color = c.call(q) if c is Callable else c
				vb.set_v(q, col)


## A stack/row of books standing on a shelf along X from (x,y,z), `w` cells wide,
## max height `h`, depth `d`. Leaves random small gaps / leaning books.
static func books(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int, seed := 0) -> void:
	var cols := [Color("b8403a"), Color("2f5e8f"), Color("e0b44c"), Color("3f7f4f"), Color("7a4b8c"),
		Color("e88a3a"), Color("d9d2bf"), Color("365a5c"), Color("9c2f45"), Color("5d84b8"), Color("f0e2c0")]
	var i := 0
	var cx := x
	while cx < x + w:
		var r := hs(cx, seed, z)
		if r < 0.08 and cx > x and cx < x + w - 2:
			cx += 1  # gap
			continue
		var bh := maxi(2, h - int(hs(cx, seed + 3, z) * 3.0))
		var bw := 1 if hs(cx, seed + 9, z) < 0.75 else 2
		bw = mini(bw, x + w - cx)
		var c: Color = cols[int(hs(cx, seed + 5, z + i) * cols.size()) % cols.size()]
		b(vb, cx, y, z, bw, bh, d, c)
		# Spine band.
		if bh > 3:
			b(vb, cx, y + bh - 2, z + d - 1, bw, 1, 1, shade(c, 1.35))
		cx += bw
		i += 1


## Leafy foliage colour callable (greens with highlights).
static func leaves(seed := 0, tone := 0) -> Callable:
	var sets := [
		[Color("4f9a3c"), Color("5fae45"), Color("3d8030"), Color("72bf52"), Color("458c35")],
		[Color("3e7d3a"), Color("4c9446"), Color("2f6630"), Color("5aa64f"), Color("6bb85a")],
		[Color("6aa83f"), Color("7fbd4a"), Color("8ccc55"), Color("5b9636"), Color("a1d26a")],
	]
	var cols: Array = sets[tone % sets.size()]
	return func(q: Vector3i) -> Color:
		var hh := VoxelBuilder.hash3(q + Vector3i(seed, seed, 3))
		var c: Color = cols[int(hh * cols.size()) % cols.size()]
		# Lighter on top.
		return shade(c, 0.9 + clampf(float(q.y) * 0.006, 0.0, 0.2))
