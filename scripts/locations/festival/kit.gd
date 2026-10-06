extends RefCounted
## Festival toolkit: fast static voxel mesher, shape helpers, palettes,
## pixel-art stamps (maple leaf, letters), Label3D signs, halo sprites.
## Use: const K := preload("res://scripts/locations/festival/kit.gd")

const N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const SHADE := [0.93, 0.9, 1.0, 0.7, 0.97, 0.86]
const AOV := [1.0, 0.8, 0.66, 0.52]

const FONT_PATH := "res://assets/fonts/Nunito.ttf"

## Autumn palettes.
const ORANGE := [Color("f08a24"), Color("e8731c"), Color("f59e2e"), Color("d9601a"), Color("fbb240"), Color("ee7f22")]
const RED := [Color("d2401f"), Color("bf3219"), Color("e05a28"), Color("a8281a"), Color("e8702e"), Color("c94420")]
const YELLOW := [Color("f7c23c"), Color("f2ad2a"), Color("fbd456"), Color("e99a22"), Color("f8cc48"), Color("f3b836")]
const LEAF_GROUND := [Color("e0662a"), Color("f0a030"), Color("c9401e"), Color("f5c040"), Color("b8541f"), Color("ea8a2c")]

const MAPLE := [
	"...#...",
	"..###..",
	"#.###.#",
	"#######",
	".#####.",
	"..###..",
	"...#...",
]

static var _halo_mat: StandardMaterial3D
static var _font: Font


# ------------------------------------------------------------------ colours

static func hs(x: int, y: int, z: int) -> float:
	return VoxelBuilder.hash3(Vector3i(x, y, z))


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


static func pick(cols: Array, h: float) -> Color:
	return cols[int(h * cols.size()) % cols.size()]


static func noisy(c: Color, amt := 0.08, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		return shade(c, 1.0 + (VoxelBuilder.hash3(q + Vector3i(seed, 11, seed)) - 0.5) * 2.0 * amt)


static func mix(cols: Array, seed := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		return pick(cols, VoxelBuilder.hash3(q + Vector3i(seed, 5, 17 * seed)))


## Planks running along `axis` (0 = x, 2 = z), `bw` cells wide.
static func wood(c: Color, axis := 0, bw := 3, amt := 0.06) -> Callable:
	return func(q: Vector3i) -> Color:
		var across := q.z if axis == 0 else q.x
		var along := q.x if axis == 0 else q.z
		var plank := floori(float(across) / bw)
		var f := 0.9 + VoxelBuilder.hash3(Vector3i(plank, q.y, 3)) * 0.2
		f += (VoxelBuilder.hash3(Vector3i(along / 3, plank, q.y)) - 0.5) * amt
		if posmod(across, bw) == 0:
			f *= 0.86
		return shade(c, f)


static func stripes(a: Color, b: Color, w := 3, axis := 0) -> Callable:
	return func(q: Vector3i) -> Color:
		var u := q.x if axis == 0 else q.z
		return a if posmod(floori(float(u) / w), 2) == 0 else b


# ------------------------------------------------------------------ shapes

static func box(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int, c, glow := false) -> void:
	vb.box(Vector3i(x, y, z), Vector3i(w, h, d), c, glow)


static func px(vb: VoxelBuilder, x: int, y: int, z: int, c: Color, glow := false) -> void:
	vb.set_v(Vector3i(x, y, z), c, glow)


## Vertical cylinder centred at (cx, cz) (cell units, may be fractional).
static func cyl(vb: VoxelBuilder, cx: float, y: int, cz: float, r: float, h: int, c, glow := false, inner := -1.0) -> void:
	var ri := ceili(r)
	for x in range(floori(cx - ri) - 1, ceili(cx + ri) + 1):
		for z in range(floori(cz - ri) - 1, ceili(cz + ri) + 1):
			var dx := x + 0.5 - cx
			var dz := z + 0.5 - cz
			var d2 := dx * dx + dz * dz
			if d2 > r * r:
				continue
			if inner > 0.0 and d2 < inner * inner:
				continue
			for yy in h:
				var q := Vector3i(x, y + yy, z)
				var col: Color = c.call(q) if c is Callable else c
				if col.a > 0.0:
					vb.set_v(q, col, glow)


## Rough ellipsoid blob.
## With `occ` (Dictionary) the blob interior is only recorded there (as hidden
## occupancy for K.mesh) instead of being filled with coloured voxels.
static func blob(vb: VoxelBuilder, center: Vector3, rad: Vector3, c, rough := 0.3, seed := 0, occ = null) -> void:
	for x in range(floori(center.x - rad.x - 1), ceili(center.x + rad.x + 1)):
		for y in range(floori(center.y - rad.y - 1), ceili(center.y + rad.y + 1)):
			for z in range(floori(center.z - rad.z - 1), ceili(center.z + rad.z + 1)):
				var d := Vector3((x + 0.5 - center.x) / rad.x, (y + 0.5 - center.y) / rad.y, (z + 0.5 - center.z) / rad.z)
				var l := d.length()
				var lim := 1.0 + (VoxelBuilder.hash3(Vector3i(x, y, z) + Vector3i(seed, 0, seed * 3)) - 0.5) * rough
				if l > lim:
					continue
				var q := Vector3i(x, y, z)
				if occ != null and l < lim - 2.2 / maxf(minf(rad.x, rad.y), 1.0):
					occ[q] = true
					continue
				var col: Color = c.call(q) if c is Callable else c
				if col.a > 0.0:
					vb.set_v(q, col)


## Line of voxels between two points (inclusive), thickness 1.
static func line(vb: VoxelBuilder, a: Vector3, b: Vector3, c, glow := false) -> void:
	var n := maxi(int(ceil((b - a).length() * 1.5)), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var q := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		var col: Color = c.call(q) if c is Callable else c
		vb.set_v(q, col, glow)


## Stamp a pixel-art pattern (rows top->bottom) on the XY plane at z.
## `cols` maps a char to a Color; '.' is empty.
static func pattern(vb: VoxelBuilder, rows: Array, x: int, y: int, z: int, cols: Dictionary, glow := false, scale := 1, plane := 0) -> void:
	var hgt := rows.size()
	for r in hgt:
		var row: String = rows[r]
		for i in row.length():
			var ch := row[i]
			if not cols.has(ch):
				continue
			for sx in scale:
				for sy in scale:
					var yy := y + (hgt - 1 - r) * scale + sy
					if plane == 0:
						vb.set_v(Vector3i(x + i * scale + sx, yy, z), cols[ch], glow)
					else:
						vb.set_v(Vector3i(x, yy, z + i * scale + sx), cols[ch], glow)


static func maple(vb: VoxelBuilder, x: int, y: int, z: int, c: Color, scale := 1, plane := 0) -> void:
	pattern(vb, MAPLE, x, y, z, {"#": c}, false, scale, plane)


## Pumpkin: squashed ribbed sphere with a stem.
static func pumpkin(vb: VoxelBuilder, cx: int, y: int, cz: int, r: float, seed := 0, tone := 0) -> void:
	var base: Color = [Color("ec7a1c"), Color("f08c26"), Color("e0661a"), Color("f2b03a")][tone % 4]
	var hgt := maxf(r * 0.8, 1.5)
	for x in range(floori(cx - r) - 1, ceili(cx + r) + 1):
		for z in range(floori(cz - r) - 1, ceili(cz + r) + 1):
			for yy in range(0, ceili(hgt * 2.0) + 1):
				var dx := (x + 0.5 - cx) / r
				var dz := (z + 0.5 - cz) / r
				var dy := (yy + 0.5 - hgt) / hgt
				if dx * dx + dz * dz + dy * dy > 1.0:
					continue
				var ang := atan2(dz, dx)
				var rib := 1.0 if cos(ang * 8.0) > -0.3 else 0.0
				vb.set_v(Vector3i(x, y + yy, z), shade(base, 0.84 + 0.16 * rib))
	var top := y + ceili(hgt * 2.0)
	vb.set_v(Vector3i(cx, top, cz), Color("5a7a2a"))
	vb.set_v(Vector3i(cx, top + 1, cz), Color("4a6324"))
	if r >= 3.0:
		vb.set_v(Vector3i(cx + 1, top + 1, cz), Color("6f8f32"))


## Hay bale (x,y,z = min corner).
static func hay(vb: VoxelBuilder, x: int, y: int, z: int, w: int, h: int, d: int) -> void:
	var cols := [Color("e8c25a"), Color("d9ae48"), Color("f0d06a"), Color("c99b3c")]
	box(vb, x, y, z, w, h, d, func(q: Vector3i) -> Color:
		var f := 1.0
		if posmod(q.x - x, maxi(w / 3, 2)) == 0 and q.x != x:
			f = 0.85
		var c: Color = pick(cols, hs((q.x - x) / 3, q.y, 1))
		return shade(c, f))
	# Twine bands.
	for bx in [x + w / 4, x + w - 1 - w / 4]:
		for yy in h:
			vb.set_v(Vector3i(bx, y + yy, z + d - 1), Color("8a5a2a"))
		for zz in d:
			vb.set_v(Vector3i(bx, y + h - 1, z + zz), Color("8a5a2a"))
	# Straws sticking out.
	for i in 6:
		var sx := x + int(hs(i, x, z) * w)
		var sz := z + int(hs(z, i, x) * d)
		vb.set_v(Vector3i(sx, y + h, sz), Color("f3d877"))


## Flowering mum cluster (bush of small flowers), radius r cells, at top y.
static func mums(vb: VoxelBuilder, cx: float, y: int, cz: float, r: float, palette := 0, seed := 0) -> void:
	var sets := [
		[Color("f08a1c"), Color("f5a524"), Color("e2661a"), Color("fbc542")],
		[Color("e04a2a"), Color("f07a2a"), Color("c8321e"), Color("f5a030")],
		[Color("f6c63a"), Color("fbd85a"), Color("eaa52a"), Color("f08a24")],
		[Color("c23a5a"), Color("e06a8a"), Color("a82a48"), Color("f2a0b0")],
	]
	var cols: Array = sets[palette % sets.size()]
	var leaf := [Color("4e7a2c"), Color("3e6a24"), Color("5f8c34")]
	blob(vb, Vector3(cx, y + r * 0.55, cz), Vector3(r, r * 0.75, r), func(q: Vector3i) -> Color:
		var h := hs(q.x + seed, q.y, q.z)
		if h < 0.18:
			return pick(leaf, hs(q.z, q.x, q.y))
		var c: Color = pick(cols, hs(q.x, q.y + seed, q.z))
		return shade(c, 0.95 + float(q.y - y) * 0.02), 0.45, seed)


# ------------------------------------------------------------------ meshing

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()


static func _ao(vox: Dictionary, p: Vector3i, n: Vector3i, corner: Vector3) -> float:
	var cx := int(corner.x * 2 - 1)
	var cy := int(corner.y * 2 - 1)
	var cz := int(corner.z * 2 - 1)
	var ax: Vector3i
	var bx: Vector3i
	if n.x != 0:
		ax = Vector3i(0, cy, 0); bx = Vector3i(0, 0, cz)
	elif n.y != 0:
		ax = Vector3i(cx, 0, 0); bx = Vector3i(0, 0, cz)
	else:
		ax = Vector3i(cx, 0, 0); bx = Vector3i(0, cy, 0)
	var o := p + n
	var s1 := vox.has(o + ax)
	var s2 := vox.has(o + bx)
	if s1 and s2:
		return AOV[3]
	return AOV[int(s1) + int(s2) + int(vox.has(o + ax + bx))]


## Bake a builder (skips downward faces at or below `floor_y`, never seen).
## `occ` optionally marks extra hidden cells (blob interiors) that occlude faces.
## Coplanar neighbouring faces with identical colours (flat areas built with
## jitter 0 / per-plank colours) are merged into strips.
static func mesh(vb: VoxelBuilder, vs: float, origin := Vector3.ZERO, floor_y := 0, occ := {}) -> ArrayMesh:
	var vox: Dictionary = vb.vox
	var use_occ := not occ.is_empty()
	var glow: Dictionary = vb.glow
	var jit: float = vb.jitter
	var solid := Surf.new()
	var lit := Surf.new()
	var runs := {}  # Vector4i(fi, plane, row, glow) -> Array of [run_coord, c0, c1, c2, c3, p]
	for p: Vector3i in vox:
		var g := glow.has(p)
		var base: Color = vox[p]
		var j := (VoxelBuilder.hash3(p) - 0.5) * 2.0 * jit
		for fi in 6:
			if fi == 3 and p.y <= floor_y:
				continue
			var n: Vector3i = N[fi]
			if vox.has(p + n) or (use_occ and occ.has(p + n)):
				continue
			var cs: Array = CORNERS[fi]
			var sh: float = (SHADE[fi] if not g else 1.0) * (1.0 + j)
			var a0 := 1.0
			var a1 := 1.0
			var a2 := 1.0
			var a3 := 1.0
			if not g:
				a0 = _ao(vox, p, n, cs[0]); a1 = _ao(vox, p, n, cs[1]); a2 = _ao(vox, p, n, cs[2]); a3 = _ao(vox, p, n, cs[3])
			var k0 := sh * a0
			var k1 := sh * a1
			var k2 := sh * a2
			var k3 := sh * a3
			var c0 := Color(base.r * k0, base.g * k0, base.b * k0)
			var c1 := Color(base.r * k1, base.g * k1, base.b * k1)
			var c2 := Color(base.r * k2, base.g * k2, base.b * k2)
			var c3 := Color(base.r * k3, base.g * k3, base.b * k3)
			# Run axis: +-X faces run along Z, all others along X.
			var rc := p.z if fi < 2 else p.x
			var plane := p.x if fi < 2 else (p.y if fi < 4 else p.z)
			var row := p.y if (fi < 2 or fi >= 4) else p.z
			var key := Vector4i(fi, plane, row, 1 if g else 0)
			var lst = runs.get(key)
			if lst == null:
				lst = []
				runs[key] = lst
			lst.append([rc, c0, c1, c2, c3, p])
	for key: Vector4i in runs:
		var lst: Array = runs[key]
		if lst.size() > 1:
			lst.sort_custom(func(a, b): return a[0] < b[0])
		var fi := key.x
		var s := lit if key.w == 1 else solid
		var nn := Vector3(N[fi])
		var cs: Array = CORNERS[fi]
		var k := 0
		var cnt := lst.size()
		while k < cnt:
			var e: Array = lst[k]
			var m := k
			while m + 1 < cnt:
				var f: Array = lst[m + 1]
				if f[0] != lst[m][0] + 1 or f[1] != e[1] or f[2] != e[2] or f[3] != e[3] or f[4] != e[4]:
					break
				m += 1
			var p0 := Vector3(e[5]) - origin
			var p1 := Vector3(lst[m][5]) - origin
			var b := s.v.size()
			for ci in 4:
				var cc: Vector3 = cs[ci]
				var comp := cc.z if fi < 2 else cc.x
				s.v.append(((p1 if comp > 0.5 else p0) + cc) * vs)
				s.n.append(nn)
			s.c.append(e[1]); s.c.append(e[2]); s.c.append(e[3]); s.c.append(e[4])
			var l0: float = (e[1] as Color).get_luminance() + (e[3] as Color).get_luminance()
			var l1: float = (e[2] as Color).get_luminance() + (e[4] as Color).get_luminance()
			if l0 < l1:
				s.i.append(b + 1); s.i.append(b + 3); s.i.append(b + 2)
				s.i.append(b + 1); s.i.append(b + 0); s.i.append(b + 3)
			else:
				s.i.append(b + 0); s.i.append(b + 2); s.i.append(b + 1)
				s.i.append(b + 0); s.i.append(b + 3); s.i.append(b + 2)
			k = m + 1
	var mm := ArrayMesh.new()
	for pair in [[solid, VoxelBuilder.solid_material()], [lit, glow_material()]]:
		var sf: Surf = pair[0]
		if sf.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = sf.v
		arr[Mesh.ARRAY_NORMAL] = sf.n
		arr[Mesh.ARRAY_COLOR] = sf.c
		arr[Mesh.ARRAY_INDEX] = sf.i
		mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mm.surface_set_material(mm.get_surface_count() - 1, pair[1])
	return mm


static var _glow_mat: StandardMaterial3D

## Brighter glow than the shared one: festival bulbs/lanterns must read as lit
## in daylight.
static func glow_material() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.vertex_color_use_as_albedo = true
		_glow_mat.vertex_color_is_srgb = true
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.albedo_color = Color(1.45, 1.32, 1.12)
	return _glow_mat


static func inst(parent: Node, vb: VoxelBuilder, vs: float, pos := Vector3.ZERO, rot_y := 0.0, shadows := true, origin := Vector3.ZERO, nm := "", occ := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(vb, vs, origin, 0, occ)
	mi.position = pos
	mi.rotation.y = deg_to_rad(rot_y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ text

static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			var base: Font = load(FONT_PATH)
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_embolden = 0.9
			_font = fv
		else:
			_font = ThemeDB.fallback_font
	return _font


## Flat text on a sign (faces +Z of the parent unless rotated).
static func label(parent: Node3D, text: String, pos: Vector3, px_size: float, col: Color, rot_y := 0.0, outline := Color(0, 0, 0, 0), font_size := 64, align := HORIZONTAL_ALIGNMENT_CENTER, rot_z := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = font_size
	l.pixel_size = px_size
	l.modulate = col
	l.position = pos
	l.rotation = Vector3(0, deg_to_rad(rot_y), deg_to_rad(rot_z))
	l.horizontal_alignment = align
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	l.line_spacing = -6.0
	if outline.a > 0.0:
		l.outline_modulate = outline
		l.outline_size = 10
	else:
		l.outline_size = 0
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ halos

## Soft additive glow sprites (one draw call). points: [[pos, size, color]].
static func halos(points: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = points.size()
	for i in points.size():
		var e: Array = points[i]
		var s: float = e[1]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), e[0]))
		mm.set_instance_color(i, e[2])
	var mi := MultiMeshInstance3D.new()
	mi.name = "Halos"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = halo_material()
	return mi


static func halo_material() -> StandardMaterial3D:
	if _halo_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.1, Color(1, 1, 1, 0.9))
		g.add_point(0.3, Color(1, 1, 1, 0.4))
		g.add_point(0.6, Color(1, 1, 1, 0.1))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_halo_mat.billboard_keep_scale = true
		_halo_mat.vertex_color_use_as_albedo = true
		_halo_mat.albedo_texture = tex
		_halo_mat.disable_fog = true
		_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _halo_mat


## Warm point light registered with lighting.gd (group "vims_lamps").
static func light(parent: Node, pos: Vector3, color := Color(1.0, 0.7, 0.4), energy := 1.0, rng := 3.5, day_factor := 0.6) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.light_specular = 0.1
	l.set_meta("base_energy", energy)
	l.set_meta("day_factor", day_factor)
	l.add_to_group("vims_lamps")
	parent.add_child(l)
	return l
