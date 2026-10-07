
extends RefCounted
## Use via: const PropLib := preload("res://scripts/props/prop_lib.gd")
## Shared voxel prop library (owned by the home builder; every location may use it).
##
## Models live in furniture.gd / decor.gd / outdoor.gd as `m_<name>(vb, variant)`.
## Furniture + decor are authored in 1/16 m cells (PropLib.U); outdoor models
## declare their own cell size (scale_of(name)).  Every model's footprint starts
## at (0,0,0) and its front faces +Z; wall-mounted models have their back at z=0.
##
## Typical use (cheap: merge many props into ONE builder per room/group):
##     var vb := VoxelBuilder.new()
##     PropLib.place(vb, "desk", Vector3i(10, 0, 4), 0)      # rot: 0 +Z, 1 +X, 2 -Z, 3 -X
##     PropLib.place(vb, "plant", Vector3i(40, 0, 2), 0, 1)  # variant 1
##     add_child(vb.build_instance(PropLib.FU))   # furniture display cell (1.25 x U)
## Or a single cached mesh instance (shared ArrayMesh, centred on its footprint):
##     var mi := PropLib.instance("tree", 3)
## Names: see PropLib.names().
## Procedural helpers: rug(), railing(), window_frame(), string_lights(), add_light().

const U := 0.0625
## Display cell size for furniture + decor: models are authored in 1/16 m cells
## and shown at 1.12x (0.07 m cells): close to real-world size (desk top
## 0.84 m, chair seat 0.49 m, door-height shelves) so a 1.75 m adult reads at
## the right scale, a touch chunky for the voxel look. Outdoor models keep
## their own SCALE; detail.gd models are authored in half cells (FU * 0.5).
const FU := 0.07
const Furn := preload("res://scripts/props/furniture.gd")
const Decor := preload("res://scripts/props/decor.gd")
const Outdoor := preload("res://scripts/props/outdoor.gd")
const Detail := preload("res://scripts/props/detail.gd")
const VU := preload("res://scripts/props/vox_util.gd")
const Mesher := preload("res://scripts/props/mesher.gd")

static var _index := {}     # name -> script
static var _models := {}    # "name#v" -> VoxelBuilder (normalised, min corner at 0)
static var _sizes := {}     # "name#v" -> Vector3i
static var _meshes := {}    # "name#v" -> ArrayMesh
static var _glass_mat: StandardMaterial3D
static var _lit_window_mat: ShaderMaterial
static var _night_ext_mat: StandardMaterial3D


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for lib in [Furn, Decor, Outdoor, Detail]:
		for m in lib.get_script_method_list():
			var n: String = m.name
			if n.begins_with("m_"):
				_index[n.substr(2)] = lib


static func names() -> Array:
	_ensure_index()
	return _index.keys()


static func has_model(name: String) -> bool:
	_ensure_index()
	return _index.has(name)


## Cell size (metres) a model is authored in.
static func scale_of(name: String) -> float:
	if name.ends_with("_hd"):
		return FU * 0.5
	return Outdoor.SCALE.get(name, FU)


## The cached, normalised model builder (do not modify it).
static func model(name: String, v := 0) -> VoxelBuilder:
	var key := "%s#%d" % [name, v]
	if _models.has(key):
		return _models[key]
	_ensure_index()
	var raw := VoxelBuilder.new()
	if _index.has(name):
		_index[name].call("m_" + name, raw, v)
	else:
		push_warning("PropLib: unknown model '%s'" % name)
		raw.box(Vector3i.ZERO, Vector3i(4, 4, 4), Color.MAGENTA)
	var mn := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var mx := -mn
	for p: Vector3i in raw.vox:
		mn = Vector3i(mini(mn.x, p.x), mini(mn.y, p.y), mini(mn.z, p.z))
		mx = Vector3i(maxi(mx.x, p.x), maxi(mx.y, p.y), maxi(mx.z, p.z))
	var out := VoxelBuilder.new()
	if raw.vox.is_empty():
		mn = Vector3i.ZERO
		mx = Vector3i.ZERO
	for p: Vector3i in raw.vox:
		out.vox[p - mn] = raw.vox[p]
		if raw.glow.has(p):
			out.glow[p - mn] = true
	_models[key] = out
	_sizes[key] = mx - mn + Vector3i.ONE
	return out


## Model size in cells (unrotated).
static func size_of(name: String, v := 0) -> Vector3i:
	model(name, v)
	return _sizes["%s#%d" % [name, v]]


## Footprint size after a rotation (x/z swap on odd turns).
static func rotated_size(name: String, rot := 0, v := 0) -> Vector3i:
	var s := size_of(name, v)
	return Vector3i(s.z, s.y, s.x) if rot % 2 == 1 else s


## Stamp a model into `dst` with its (rotated) footprint min corner at `at`.
## rot = quarter turns: front faces 0:+Z 1:+X 2:-Z 3:-X.
## Returns the occupied box in cells as AABB(position, size).
static func place(dst: VoxelBuilder, name: String, at: Vector3i, rot := 0, v := 0) -> AABB:
	var m := model(name, v)
	var s := size_of(name, v)
	rot = posmod(rot, 4)
	for p: Vector3i in m.vox:
		var q: Vector3i
		match rot:
			0: q = p
			1: q = Vector3i(p.z, p.y, s.x - 1 - p.x)
			2: q = Vector3i(s.x - 1 - p.x, p.y, s.z - 1 - p.z)
			_: q = Vector3i(s.z - 1 - p.z, p.y, p.x)
		dst.set_v(at + q, m.vox[p], m.glow.has(p))
	var rs := rotated_size(name, rot, v)
	return AABB(Vector3(at), Vector3(rs))


## Place so that the footprint is centred on cell (cx, cz).
static func place_centered(dst: VoxelBuilder, name: String, cx: int, y: int, cz: int, rot := 0, v := 0) -> AABB:
	var rs := rotated_size(name, rot, v)
	return place(dst, name, Vector3i(cx - rs.x / 2, y, cz - rs.z / 2), rot, v)


## Cached ArrayMesh of a model, origin at the bottom-centre of its footprint.
static func mesh(name: String, v := 0) -> ArrayMesh:
	var key := "%s#%d" % [name, v]
	if _meshes.has(key):
		return _meshes[key]
	var m := model(name, v)
	var s := size_of(name, v)
	var flat: bool = Outdoor.FLAT.has(name)
	if flat:
		m.jitter = 0.0
	var am := Mesher.build(m, scale_of(name), Vector3(s.x * 0.5, 0, s.z * 0.5), true, flat)
	_meshes[key] = am
	return am


## Stand-alone MeshInstance3D (shares the cached mesh). Prefer place() into a
## room builder for static scenery; use this for things that move or toggle.
static func instance(name: String, v := 0, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name.capitalize().replace(" ", "")
	mi.mesh = mesh(name, v)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if name == "shower_glass":
		mi.material_override = glass_material()
	return mi


static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.vertex_color_use_as_albedo = true
		_glass_mat.vertex_color_is_srgb = true
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.albedo_color = Color(0.92, 0.98, 1.0, 0.42)
		_glass_mat.roughness = 0.1
		_glass_mat.metallic_specular = 0.9
		# Faint cool self-light so the panes read light-blue even under warm lamps.
		_glass_mat.emission_enabled = true
		_glass_mat.emission = Color(0.42, 0.66, 0.82)
		_glass_mat.emission_energy_multiplier = 0.7
	return _glass_mat


## Bright warm glass for lit windows at night (vertex colour * boost, unshaded,
## so it blooms through the glow pass). Use as material_override.
static func lit_window_material(boost := 1.6) -> ShaderMaterial:
	if _lit_window_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, cull_back;
uniform float boost = 1.6;
void fragment() {
	// Vertex colours are sRGB; linearise so warm glass stays amber, not cream.
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * boost;
}
"""
		_lit_window_mat = ShaderMaterial.new()
		_lit_window_mat.shader = sh
	_lit_window_mat.set_shader_parameter("boost", boost)
	return _lit_window_mat


## Darker, cooler variant of the voxel material for exterior scenery at night
## (lawns, trees, neighbour houses). Emissive voxels (windows, lamps) keep a
## glow surface of their own: set this on surface 0 only
## (MeshInstance3D.set_surface_override_material) so the glow surface stays.
static func night_exterior_material() -> StandardMaterial3D:
	if _night_ext_mat == null:
		_night_ext_mat = VoxelBuilder.solid_material().duplicate()
		_night_ext_mat.albedo_color = Color(0.66, 0.72, 0.95)
	return _night_ext_mat


# ------------------------------------------------------------------ lights

## Warm point light registered with the lighting system (group "vims_lamps").
## lighting.gd scales its energy by time of day: full at night, `day_factor` by day.
static func add_light(parent: Node, pos: Vector3, color := Color(1.0, 0.72, 0.42), energy := 1.0, light_range := 3.5, day_factor := 0.25) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.1
	l.shadow_enabled = false
	l.light_specular = 0.15
	l.set_meta("base_energy", energy)
	l.set_meta("day_factor", day_factor)
	l.add_to_group("vims_lamps")
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ procedural

## Rug of w x d cells at `at` (1 cell thick). style: "patch_pink", "check_blue",
## "blue_braid", "star", "red_kilim", "sage", "round_blue".
static func rug(vb: VoxelBuilder, at: Vector3i, w: int, d: int, style := "check_blue") -> void:
	for x in w:
		for z in d:
			var c := Color(0, 0, 0, 0)
			var ex := mini(x, w - 1 - x)
			var ez := mini(z, d - 1 - z)
			var e := mini(ex, ez)
			var h := VoxelBuilder.hash3(Vector3i(x, 7, z) + at)
			match style:
				"patch_pink":
					var pal := [Color("ef9fb2"), Color("f7d3d6"), Color("e48aa0"), Color("fbe6dc"), Color("f2b7c4"), Color("f3cf9e")]
					c = pal[(int(x / 4) * 7 + int(z / 4) * 3) % pal.size()]
					if posmod(x, 4) == 0 or posmod(z, 4) == 0:
						c = Color("f7e6e0")
					if e == 0:
						c = Color("c35a74")
				"check_blue":
					c = Color("dfe6f2") if (int(x / 3) + int(z / 3)) % 2 == 0 else Color("a9b9d8")
					if e == 0:
						c = Color("6f86b8")
				"blue_braid":
					var r := e % 4
					c = [Color("4e6fb3"), Color("8fa6da"), Color("c9d4ee"), Color("6a86c4")][r]
					if h > 0.8:
						c = Color("e9eef8")
				"star":
					c = Color("3d4f99")
					if h > 0.92:
						c = Color("f7d454")
					if e < 2:
						c = Color("7f93d6")
				"red_kilim":
					var k := (absi(x - w / 2) + absi(z - d / 2)) % 6
					c = [Color("b8443a"), Color("e3a24a"), Color("f2e2c4"), Color("b8443a"), Color("5f7fa8"), Color("e8d0a8")][k]
					if e == 0:
						c = Color("7a2a26")
				"round_blue", "round_cream":
					var dx := (x + 0.5 - w * 0.5) / (w * 0.5)
					var dz := (z + 0.5 - d * 0.5) / (d * 0.5)
					var rr := dx * dx + dz * dz
					if rr > 1.0:
						continue
					var ring := int(sqrt(rr) * 5.0)
					if style == "round_blue":
						c = [Color("8fa6da"), Color("6f86c0"), Color("aebde6"), Color("5d74b0"), Color("4b5f9c")][ring % 5]
					else:
						c = [Color("efe2c8"), Color("e0cfae"), Color("f6ecd8"), Color("cdb894"), Color("b89f7a")][ring % 5]
				_:
					c = Color("b9c8a6") if e > 1 else Color("8ea07c")
			if c.a > 0.0:
				var f := 0.94 + h * 0.1
				vb.set_v(at + Vector3i(x, 0, z), Color(c.r * f, c.g * f, c.b * f))


## Wooden balcony railing along X (axis 0) or Z (axis 2): posts every 8 cells,
## balusters every 2, handrail on top. Height in cells (default 0.9 m).
static func railing(vb: VoxelBuilder, at: Vector3i, length: int, axis := 0, height := 14, wood := Color("9a6236")) -> void:
	var dir := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
	var side := Vector3i(0, 0, 1) if axis == 0 else Vector3i(1, 0, 0)
	for i in length:
		var p := at + dir * i
		var tone := VU.shade(wood, 0.95 + VoxelBuilder.hash3(p) * 0.1)
		if i % 8 == 0 or i == length - 1:
			for y in height + 1:
				vb.set_v(p + Vector3i(0, y, 0), VU.shade(wood, 0.85))
				vb.set_v(p + side + Vector3i(0, y, 0), VU.shade(wood, 0.85))
			vb.set_v(p + Vector3i(0, height + 1, 0), VU.shade(wood, 0.8))
			vb.set_v(p + side + Vector3i(0, height + 1, 0), VU.shade(wood, 0.8))
		elif i % 2 == 0:
			for y in range(1, height - 1):
				vb.set_v(p + Vector3i(0, y, 0), tone)
		vb.set_v(p, VU.shade(wood, 0.8))
		vb.set_v(p + side, VU.shade(wood, 0.8))
		vb.set_v(p + Vector3i(0, height - 1, 0), VU.shade(wood, 1.08))
		vb.set_v(p + side + Vector3i(0, height - 1, 0), VU.shade(wood, 1.08))
		vb.set_v(p + Vector3i(0, height, 0), VU.shade(wood, 1.12))
		vb.set_v(p + side + Vector3i(0, height, 0), VU.shade(wood, 1.12))


## Window frame filling a wall opening. The opening spans `w` cells along the
## wall (axis 0 = wall runs along X, 2 = along Z), `h` cells high, wall `t` cells
## thick, starting at `at` (min corner). `panes` = vertical mullions count.
## `inward` (+1/-1) is the room side, where the sill sticks out.
static func window_frame(vb: VoxelBuilder, at: Vector3i, w: int, h: int, t: int, axis := 0, panes := 2, inward := 1, frame := Color("f6f2ea"), sill := Color("c99360"), glass := Color(0, 0, 0, 0)) -> void:
	var along := Vector3i(1, 0, 0) if axis == 0 else Vector3i(0, 0, 1)
	var across := Vector3i(0, 0, 1) if axis == 0 else Vector3i(1, 0, 0)
	var mid := t / 2
	for i in w:
		for y in h:
			var edge := i == 0 or i == w - 1 or y == 0 or y == h - 1
			var mull := panes > 1 and (i * panes) % w < panes and i > 0 and i < w - 1
			var tran := y == int(h * 0.62)
			if edge:
				for k in t:
					vb.set_v(at + along * i + across * k + Vector3i(0, y, 0), frame)
			elif mull or tran:
				vb.set_v(at + along * i + across * mid + Vector3i(0, y, 0), frame)
			elif glass.a > 0.0:
				vb.set_v(at + along * i + across * mid + Vector3i(0, y, 0), glass, true)
	# Sill on the room side.
	var sx := at + across * (t if inward > 0 else -1)
	for i in range(-1, w + 1):
		vb.set_v(sx + along * i + Vector3i(0, -1, 0), sill)
		vb.set_v(sx + along * i + across * (1 if inward > 0 else -1) + Vector3i(0, -1, 0), sill)


## Fairy/star string lights along a sagging line from a to b (cells).
static func string_lights(vb: VoxelBuilder, a: Vector3i, b: Vector3i, bulbs := 8, sag := 3.0, star := false) -> void:
	var n := maxi(int(Vector3(b - a).length()), 2)
	for i in n + 1:
		var t := float(i) / n
		var p := Vector3(a).lerp(Vector3(b), t)
		p.y -= sin(t * PI) * sag
		var q := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
		vb.set_v(q, Color("3a3530"))
	for k in bulbs:
		var t := (k + 0.5) / bulbs
		var p := Vector3(a).lerp(Vector3(b), t)
		p.y -= sin(t * PI) * sag + 1.0
		var q := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
		var c := Color("ffd25a")
		vb.set_v(q, c, true)
		if star:
			vb.set_v(q + Vector3i(1, 0, 0), c, true); vb.set_v(q + Vector3i(-1, 0, 0), c, true)
			vb.set_v(q + Vector3i(0, 1, 0), c, true); vb.set_v(q + Vector3i(0, -1, 0), c, true)
		else:
			vb.set_v(q + Vector3i(0, -1, 0), c, true)


# ------------------------------------------------------------------ halos

static var _halo_mat: StandardMaterial3D

## Soft additive glow sprites for lamps / windows / string lights, all in ONE
## MultiMesh (one draw call). points: [{pos: Vector3, size: float, color: Color}].
## Fade the whole set with `mmi.set_instance_shader_parameter` is not needed:
## call set_halo_strength(mmi, k) (0..1) instead.
static func halos(points: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = points.size()
	for i in points.size():
		var d: Dictionary = points[i]
		var s: float = d.get("size", 0.8)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), d.pos))
		mm.set_instance_color(i, d.get("color", Color(1.0, 0.75, 0.4)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Halos"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = halo_material().duplicate()
	return mi


static func set_halo_strength(mi: MultiMeshInstance3D, k: float) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m:
		m.albedo_color = Color(k, k, k, 1.0)
	mi.visible = k > 0.01


static func halo_material() -> StandardMaterial3D:
	if _halo_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.12, Color(1, 1, 1, 0.85))
		g.add_point(0.35, Color(1, 1, 1, 0.38))
		g.add_point(0.65, Color(1, 1, 1, 0.1))
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
		_halo_mat.no_depth_test = false
		_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _halo_mat
