extends RefCounted
## Local voxel helpers for the backyard (kept here so the location does not
## depend on files other builders are still changing).

const SIZE_FINE := 0.0625
const SIZE_MID := 0.125
const SIZE_BIG := 0.25

static var _glow_hot: StandardMaterial3D
static var _glow_soft: StandardMaterial3D


static func hs(x: int, y: int, z: int) -> float:
	return VoxelBuilder.hash3(Vector3i(x, y, z))


static func h1(p: Vector3i, seed := 0) -> float:
	return VoxelBuilder.hash3(p + Vector3i(seed * 13, seed * 7, seed * 3))


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), 1.0)


static func b(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int, c, glow := false) -> void:
	vb.box(Vector3i(x, y, z), Vector3i(w, h, d), c, glow)


static func p(vb: VoxelBuilder, x: int, y: int, z: int, c: Color, glow := false) -> void:
	vb.set_v(Vector3i(x, y, z), c, glow)


static func noisy(c: Color, amt := 0.08, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		return shade(c, 1.0 + (h1(q, seed) - 0.5) * 2.0 * amt)


static func mix(cols: Array, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		return cols[int(h1(q, seed + 17) * cols.size()) % cols.size()]


## Planks running along `axis` (0=x, 1=y, 2=z), boards `bw` cells wide.
static func wood(c: Color, axis := 0, bw := 2, amt := 0.08) -> Callable:
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
		var tone := (VoxelBuilder.hash3(Vector3i(board, 5, 11)) - 0.5) * 0.18
		var grain := (VoxelBuilder.hash3(Vector3i(board, floori(along / 3.0), 3)) - 0.5) * amt
		return shade(c, 1.0 + tone + grain)


static func cyl(vb: VoxelBuilder, cx: float, y: int, cz: float, r: float, h: int, c, glow := false) -> void:
	var ri := ceili(r)
	for x in range(floori(cx - ri), ceili(cx + ri) + 1):
		for z in range(floori(cz - ri), ceili(cz + ri) + 1):
			var dx := x + 0.5 - cx
			var dz := z + 0.5 - cz
			if dx * dx + dz * dz <= r * r:
				for yy in h:
					var q := Vector3i(x, y + yy, z)
					vb.set_v(q, c.call(q) if c is Callable else c, glow)


static func blob(vb: VoxelBuilder, center: Vector3, rad: Vector3, c, rough := 0.25, seed := 0, only_empty := false) -> void:
	for x in range(floori(center.x - rad.x - 1), ceili(center.x + rad.x + 1)):
		for y in range(floori(center.y - rad.y - 1), ceili(center.y + rad.y + 1)):
			for z in range(floori(center.z - rad.z - 1), ceili(center.z + rad.z + 1)):
				var d := Vector3((x + 0.5 - center.x) / rad.x, (y + 0.5 - center.y) / rad.y, (z + 0.5 - center.z) / rad.z)
				var q := Vector3i(x, y, z)
				if d.length() > 1.0 + (h1(q, seed) - 0.5) * rough:
					continue
				if only_empty and vb.has(q):
					continue
				var col: Color = c.call(q) if c is Callable else c
				if col.a > 0.0:
					vb.set_v(q, col)


## Foliage palette callable: greens, lighter towards the top (sun-kissed).
static func leaves(seed := 0, tone := 0, top := 0.0) -> Callable:
	var sets := [
		[Color("4f9a3c"), Color("5fae45"), Color("3d8030"), Color("72bf52"), Color("458c35")],
		[Color("3e7d3a"), Color("4c9446"), Color("2f6630"), Color("5aa64f"), Color("6bb85a")],
		[Color("6aa83f"), Color("7fbd4a"), Color("8ccc55"), Color("5b9636"), Color("a1d26a")],
		[Color("2f5f34"), Color("3b7340"), Color("264f2c"), Color("487f45"), Color("335f36")],
		[Color("1f3a26"), Color("28462c"), Color("1b3322"), Color("31523a"), Color("243f2a")],
	]
	var cols: Array = sets[tone % sets.size()]
	return func(q: Vector3i) -> Color:
		var c: Color = cols[int(h1(q, seed) * cols.size()) % cols.size()]
		return shade(c, 0.88 + clampf((float(q.y) - top) * 0.02, 0.0, 0.25))


## Bake a builder into a MeshInstance3D under `parent`.
static func inst(vb: VoxelBuilder, parent: Node3D, size: float, pos := Vector3.ZERO, rot_y := 0.0,
		origin := Vector3.ZERO, shadows := true, hot_glow := true, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = vb.build(size, origin)
	mi.position = pos
	mi.rotation.y = rot_y
	if nm != "":
		mi.name = nm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Brighter emissive for lamps / bulbs so they bloom.
	if not vb.glow.is_empty():
		mi.set_surface_override_material(mi.mesh.get_surface_count() - 1, glow_hot() if hot_glow else glow_soft())
	parent.add_child(mi)
	return mi


static func glow_hot() -> StandardMaterial3D:
	if _glow_hot == null:
		_glow_hot = StandardMaterial3D.new()
		_glow_hot.vertex_color_use_as_albedo = true
		_glow_hot.vertex_color_is_srgb = true
		_glow_hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_hot.albedo_color = Color(2.1, 1.55, 0.95)
	return _glow_hot


static var _glow_bulb: StandardMaterial3D


## String-light bulbs: hot amber so they bloom warm instead of clipping white.
static func glow_bulb() -> StandardMaterial3D:
	if _glow_bulb == null:
		_glow_bulb = StandardMaterial3D.new()
		_glow_bulb.vertex_color_use_as_albedo = true
		_glow_bulb.vertex_color_is_srgb = true
		_glow_bulb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_bulb.albedo_color = Color(2.15, 1.45, 0.66)
	return _glow_bulb


static func glow_soft() -> StandardMaterial3D:
	if _glow_soft == null:
		_glow_soft = StandardMaterial3D.new()
		_glow_soft.vertex_color_use_as_albedo = true
		_glow_soft.vertex_color_is_srgb = true
		_glow_soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_soft.albedo_color = Color(1.25, 1.15, 1.0)
	return _glow_soft


static func omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	# Shared lighting scales lamps in this group by time of day.
	l.set_meta("base_energy", energy)
	l.set_meta("day_factor", 0.55)
	l.add_to_group("vims_lamps")
	parent.add_child(l)
	return l


## Terracotta / glazed pot with a bushy flowering plant (fine grid, base at y).
static func flower_pot(vb: VoxelBuilder, x: int, y: int, z: int, seed: int, big := false) -> void:
	var pot: Color = [Color("c8643c"), Color("ede7db"), Color("7393b3"), Color("d98a5a"), Color("b85a4a")][seed % 5]
	var r := 3.6 if big else 2.6
	var ph := 6 if big else 4
	cyl(vb, x, y, z, r, ph, noisy(pot, 0.05, seed))
	cyl(vb, x, y + ph, z, r + 0.6, 1, shade(pot, 1.08))
	var lr := r + 1.2
	blob(vb, Vector3(x, y + ph + 2.5, z), Vector3(lr, 3.2 if big else 2.4, lr), leaves(seed, seed % 2, y + ph), 0.3, seed)
	var fl: Array = [[Color("ee7fb4"), Color("f59cc6")], [Color("8a5cc8"), Color("a37de0")], [Color("fbf7f0"), Color("f2b630")], [Color("e2513f"), Color("f07a3a")]][(seed >> 2) % 4]
	var n := 9 if big else 6
	for i in n:
		var a := float(i) / n * TAU + seed
		var rr := lr * (0.45 + 0.4 * hs(i, seed, 1))
		var fx := x + int(round(cos(a) * rr))
		var fz := z + int(round(sin(a) * rr))
		var top := y + ph + 5 + (1 if big else 0)
		while vb.has(Vector3i(fx, top, fz)):
			top += 1
		vb.set_v(Vector3i(fx, top, fz), fl[i % 2])
		vb.set_v(Vector3i(fx + 1, top, fz), fl[(i + 1) % 2])
