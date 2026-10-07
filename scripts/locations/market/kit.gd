extends RefCounted
## Market toolkit: a fast static voxel mesher with per-builder glow materials,
## Label3D signs, soft halo sprites, tiled floor texture and colour helpers.
## Self-contained so the market does not depend on other locations' files.

const FONT_PATH := "res://assets/fonts/Nunito.ttf"

const N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const SHADE := [0.93, 0.93, 1.0, 0.72, 0.97, 0.86]
const AOV := [1.0, 0.8, 0.66, 0.52]

static var _font: Font
static var _halo_mat: StandardMaterial3D
static var _glow_mats := {}
static var _solid: StandardMaterial3D


# ------------------------------------------------------------------ colours

static func h(p: Vector3i, s := 0) -> float:
	var k := (p.x * 73856093) ^ (p.y * 19349663) ^ (p.z * 83492791) ^ (s * 2654435761)
	k = (k ^ (k >> 13)) * 1274126177
	k = k ^ (k >> 16)
	return float(k & 0xffff) / 65535.0


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), 1.0)


static func vary(c: Color, p: Vector3i, amt := 0.08, s := 0) -> Color:
	return shade(c, 1.0 + (h(p, s) - 0.5) * 2.0 * amt)


## Wood grain colour function (planks along x).
static func wood(base: Color, plank := 3, along := 0) -> Callable:
	return func(p: Vector3i) -> Color:
		var row := p.y if along != 1 else p.x
		var k := int(floor(float(row) / plank))
		var f := 0.9 + 0.2 * h(Vector3i(k, 7, along), 3)
		return shade(base, f)


static func noise(base: Color, amt := 0.08, s := 1) -> Callable:
	return func(p: Vector3i) -> Color:
		return vary(base, p, amt, s)


# ------------------------------------------------------------------ mesher

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
		var b := v.size()
		v.append(p0); v.append(p1); v.append(p2); v.append(p3)
		n.append(nn); n.append(nn); n.append(nn); n.append(nn)
		c.append(c0); c.append(c1); c.append(c2); c.append(c3)
		if c0.get_luminance() + c2.get_luminance() < c1.get_luminance() + c3.get_luminance():
			i.append(b + 1); i.append(b + 3); i.append(b + 2)
			i.append(b + 1); i.append(b + 0); i.append(b + 3)
		else:
			i.append(b + 0); i.append(b + 2); i.append(b + 1)
			i.append(b + 0); i.append(b + 3); i.append(b + 2)


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


## Bake a builder. Glow voxels go to a second surface using `glow` (a material
## from glow_mat()).
static func mesh(vb: VoxelBuilder, vs: float, origin := Vector3.ZERO, glow: Material = null, skip_down := true, merge := false) -> ArrayMesh:
	var vox: Dictionary = vb.vox
	var gl: Dictionary = vb.glow
	var jit: float = vb.jitter
	var solid := Surf.new()
	var lit := Surf.new()
	var runs := {}
	for p: Vector3i in vox:
		var g := gl.has(p)
		var base: Color = vox[p]
		var j := (VoxelBuilder.hash3(p) - 0.5) * 2.0 * jit
		var pf := Vector3(p)
		for fi in 6:
			if skip_down and fi == 3:
				continue
			var n: Vector3i = N[fi]
			if vox.has(p + n):
				continue
			var cs: Array = CORNERS[fi]
			var sh: float = (SHADE[fi] if not g else 1.0) * (1.0 + j)
			var a0 := 1.0
			var a1 := 1.0
			var a2 := 1.0
			var a3 := 1.0
			if not g:
				a0 = _ao(vox, p, n, cs[0]); a1 = _ao(vox, p, n, cs[1]); a2 = _ao(vox, p, n, cs[2]); a3 = _ao(vox, p, n, cs[3])
			var c0 := Color(base.r * sh * a0, base.g * sh * a0, base.b * sh * a0)
			var c1 := Color(base.r * sh * a1, base.g * sh * a1, base.b * sh * a1)
			var c2 := Color(base.r * sh * a2, base.g * sh * a2, base.b * sh * a2)
			var c3 := Color(base.r * sh * a3, base.g * sh * a3, base.b * sh * a3)
			if merge:
				# Faces of +-X run along z; +-Y and +-Z run along x. Glow faces
				# (no AO, flat colour) merge too, into their own runs.
				var rc := p.z if fi < 2 else p.x
				var plane := p.x if fi < 2 else (p.y if fi < 4 else p.z)
				var row := p.y if (fi < 2 or fi >= 4) else p.z
				var key := Vector4i(fi, plane, row, 1 if g else 0)
				if not runs.has(key):
					runs[key] = []
				runs[key].append([rc, c0, c1, c2, c3, p])
				continue
			var s := lit if g else solid
			s.quad((pf + cs[0] - origin) * vs, (pf + cs[1] - origin) * vs, (pf + cs[2] - origin) * vs, (pf + cs[3] - origin) * vs,
				Vector3(n), c0, c1, c2, c3)
	for key: Vector4i in runs:
		var lst: Array = runs[key]
		var dst := lit if key.w == 1 else solid
		lst.sort_custom(func(a, b): return a[0] < b[0])
		var fi := key.x
		var cs: Array = CORNERS[fi]
		var k := 0
		while k < lst.size():
			var e: Array = lst[k]
			var m := k
			while m + 1 < lst.size():
				var f: Array = lst[m + 1]
				if f[0] != lst[m][0] + 1 or f[1] != e[1] or f[2] != e[2] or f[3] != e[3] or f[4] != e[4]:
					break
				m += 1
			var p0 := Vector3(e[5])
			var p1 := Vector3(lst[m][5])
			var q: Array[Vector3] = []
			for ci in 4:
				var ccn: Vector3 = cs[ci]
				var comp := ccn.z if fi < 2 else ccn.x
				q.append(((p1 if comp > 0.5 else p0) + ccn - origin) * vs)
			dst.quad(q[0], q[1], q[2], q[3], Vector3(N[fi]), e[1], e[2], e[3], e[4])
			k = m + 1
	var m := ArrayMesh.new()
	for pair in [[solid, solid_mat()], [lit, glow if glow != null else glow_mat("warm")]]:
		var s: Surf = pair[0]
		if s.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_INDEX] = s.i
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, pair[1])
	return m


static func add(parent: Node3D, vb: VoxelBuilder, vs: float, nm: String, shadows := true, glow: Material = null, pos := Vector3.ZERO, origin := Vector3.ZERO, merge := false, skip_down := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh(vb, vs, origin, glow, skip_down, merge)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func solid_mat() -> StandardMaterial3D:
	if _solid == null:
		_solid = StandardMaterial3D.new()
		_solid.vertex_color_use_as_albedo = true
		_solid.vertex_color_is_srgb = true
		_solid.roughness = 0.82
		_solid.metallic_specular = 0.3
	return _solid


## Unshaded glow material. kind: "warm" (lamps), "cool" (fridge light),
## "sky" (windows), "sign".
static func glow_mat(kind: String) -> StandardMaterial3D:
	if _glow_mats.has(kind):
		return _glow_mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	match kind:
		"warm":
			m.albedo_color = Color(2.4, 1.9, 1.25)
			m.emission = Color(1.0, 0.74, 0.4); m.emission_energy_multiplier = 2.6
		"cool":
			# HDR albedo so the fridge interiors cross the glow threshold.
			m.albedo_color = Color(1.2, 1.42, 1.8)
			m.emission = Color(0.7, 0.86, 1.0); m.emission_energy_multiplier = 0.7
		"sky":
			m.emission = Color(0.9, 0.95, 1.0); m.emission_energy_multiplier = 0.45
		_:
			m.emission = Color(1, 1, 1); m.emission_energy_multiplier = 0.15
	_glow_mats[kind] = m
	return m


# ------------------------------------------------------------------ text

static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			var fv := FontVariation.new()
			fv.base_font = load(FONT_PATH)
			fv.variation_embolden = 1.0
			_font = fv
		else:
			_font = ThemeDB.fallback_font
	return _font


static func label(parent: Node3D, text: String, pos: Vector3, px: float, col: Color, rot_y := 0.0, font_size := 96, outline := Color(0, 0, 0, 0), outline_size := 12, rot := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = col
	l.position = pos
	l.rotation = Vector3(deg_to_rad(rot.x), deg_to_rad(rot_y), deg_to_rad(rot.z))
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.line_spacing = -10.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if outline.a > 0.0:
		l.outline_modulate = outline
		l.outline_size = outline_size
	else:
		l.outline_size = 0
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ halos

## points: Array of [pos: Vector3, size: float, color: Color]. One draw call.
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
	mi.material_override = halo_mat()
	return mi


static func halo_mat() -> StandardMaterial3D:
	if _halo_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.1, Color(1, 1, 1, 0.85))
		g.add_point(0.3, Color(1, 1, 1, 0.35))
		g.add_point(0.6, Color(1, 1, 1, 0.08))
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
static func light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, day_factor := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_specular = 0.2
	l.set_meta("base_energy", energy)
	l.set_meta("day_factor", day_factor)
	l.add_to_group("vims_lamps")
	parent.add_child(l)
	return l


## Downward warm spot (a pendant's light cone): paints a pool on the floor /
## crates below. Registered with lighting.gd like Kit.light.
static func spot(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, angle := 38.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation = Vector3(-PI * 0.5, 0, 0)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.9
	l.spot_attenuation = 0.6
	l.shadow_enabled = false
	l.light_specular = 0.35
	l.set_meta("base_energy", energy)
	l.set_meta("day_factor", 1.0)
	l.add_to_group("vims_lamps")
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ floor

## Glossy cream tile floor, split into chunks so each chunk picks up its own
## nearby pendant lights (the Compatibility renderer caps lights per object).
## World-space UVs keep the tile grid continuous across chunks.
static func tile_floor(parent: Node3D, size: Vector2, center: Vector3, tile := 0.6, chunk := 4.0) -> Node3D:
	var px := 32
	var n := 8
	var img := Image.create(px * n, px * n, true, Image.FORMAT_RGB8)
	for ty in n:
		for tx in n:
			# warm cream tiles (two tones, faint per-tile variation) with
			# a clearly visible warm-grey grout line and a bevelled edge.
			var base := Color("d6b29a") if (tx + ty) % 2 == 0 else Color("c9a48c")
			var f := 0.95 + 0.08 * h(Vector3i(tx, ty, 5))
			for y in px:
				for x in px:
					var c := shade(base, f * (0.98 + 0.04 * h(Vector3i(tx * px + x, ty * px + y, 1))))
					if x < 2 or y < 2:
						c = Color("8f7a60")
					elif x < 3 or y < 3:
						c = shade(base, 0.86)
					elif x == px - 1 or y == px - 1:
						c = shade(base, 1.05)
					img.set_pixel(tx * px + x, ty * px + y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.3
	mat.metallic_specular = 0.45
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / (tile * n)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var root := Node3D.new()
	root.name = "TileFloor"
	parent.add_child(root)
	var nx := maxi(1, int(ceil(size.x / chunk)))
	var nz := maxi(1, int(ceil(size.y / chunk)))
	var cw := size.x / nx
	var cd := size.y / nz
	var pm := PlaneMesh.new()
	pm.size = Vector2(cw, cd)
	pm.subdivide_width = 3
	pm.subdivide_depth = 3
	for iz in nz:
		for ix in nx:
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.material_override = mat
			mi.position = center + Vector3(-size.x * 0.5 + cw * (ix + 0.5), 0, -size.y * 0.5 + cd * (iz + 0.5))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	return root


## Soft additive light pools lying flat (on the floor, under lamps, in front of
## fridges). points: Array of [pos: Vector3, size: Vector2 (x, z), color]. One draw call.
static func pools(points: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = points.size()
	for i in points.size():
		var e: Array = points[i]
		var sz: Vector2 = e[1]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sz.x, 1, sz.y)), e[0]))
		mm.set_instance_color(i, e[2])
	var mi := MultiMeshInstance3D.new()
	mi.name = "LightPools"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := halo_mat().duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


static var _blob_mat: StandardMaterial3D
static var _blob_mesh: QuadMesh

## Soft contact shadow (dark radial blob) lying on the floor under `parent`.
## Cheap stand-in for SSAO, which the Compatibility renderer lacks.
static func blob(parent: Node3D, size: float, strength := 0.5, offset := Vector3.ZERO) -> MeshInstance3D:
	if _blob_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.35, Color(0, 0, 0, 0.75))
		g.add_point(0.7, Color(0, 0, 0, 0.2))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.vertex_color_use_as_albedo = false
		_blob_mat.albedo_texture = tex
		_blob_mat.albedo_color = Color(0.18, 0.1, 0.05, 1.0)
		_blob_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_blob_mat.disable_fog = true
		_blob_mesh = QuadMesh.new()
		_blob_mesh.size = Vector2(1, 1)
		_blob_mesh.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.name = "Blob"
	mi.mesh = _blob_mesh
	var m := _blob_mat
	if strength != 0.5:
		m = _blob_mat.duplicate()
		m.albedo_color.a = strength * 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(size, 1, size)
	mi.position = Vector3(0, 0.02, 0) + offset
	parent.add_child(mi)
	return mi
