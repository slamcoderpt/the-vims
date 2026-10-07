extends RefCounted
## Builds the voxel bodies used by SimActor.
##
## Every body part (head, torso, pelvis, upper/lower arms and legs, hat ears,
## eyes, dog tail ...) is modelled in its own VoxelBuilder around its own
## joint pivot. The parts are then merged into ONE rigidly skinned ArrayMesh
## (each vertex weighted 100% to its part's bone), so a whole character costs a
## single draw call while every limb still animates procedurally through a
## Skeleton3D. Results are cached per look, so many NPCs share one mesh.

const Looks := preload("res://scripts/world/actors/sim_looks.gd")

## Character voxel size (metres). Slightly finer than the 1/16 m world grid so
## faces get enough cells for readable eyes, blush and beards at phone size.
const VS := 0.05

const BODY := {
	# lw leg width, shin/thigh lengths, torso w/d/h, arm width, upper/fore arm, head w/h/d
	# r10: smaller heads (10^3 instead of 12x11x11) and a taller torso: the
	# head is still chibi (about 1/3.5 of the height) but no longer swallows
	# the body, so hair/hats never dominate the silhouette.
	"big": {"lw": 5, "shin": 6, "thigh": 6, "tw": 12, "td": 7, "th": 10, "aw": 3, "ua": 6, "fa": 6, "hw": 10, "hh": 10, "hd": 10},
	"slim": {"lw": 4, "shin": 6, "thigh": 6, "tw": 10, "td": 6, "th": 10, "aw": 3, "ua": 6, "fa": 6, "hw": 10, "hh": 10, "hd": 10},
	# Chibi child: head (with hat) ~38% of total height.
	"child": {"lw": 4, "shin": 5, "thigh": 4, "tw": 10, "td": 6, "th": 8, "aw": 3, "ua": 5, "fa": 5, "hw": 10, "hh": 10, "hd": 10},
}

static var _cache := {}
static var _char_mat: ShaderMaterial

const CHAR_SHADER := """
shader_type spatial;
// Character skin: vertex colours (sRGB) + a soft warm fresnel rim and a small
// self-lift so the sims pop against busy furniture (ref: warm rim light).
uniform vec3 rim_color : source_color = vec3(1.0, 0.80, 0.55);
uniform float rim_strength = 0.45;
uniform float lift = 0.07;
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = c;
	if (!OUTPUT_IS_SRGB) {
		lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	}
	ALBEDO = lin;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - ndv, 2.5);
	EMISSION = rim_color * f * rim_strength + lin * lift;
}
"""


const OUTLINE_SHADER := """
shader_type spatial;
// Thin warm-dark inverted-hull outline so the sims separate from furniture
// of the same hue (one extra cheap unshaded pass per character).
render_mode unshaded, cull_front, shadows_disabled;
uniform vec3 line_color : source_color = vec3(0.16, 0.09, 0.06);
uniform float width = 0.014;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = line_color;
}
"""


## Shared material for every character body. `outlined` adds the thin
## inverted-hull outline pass (household only: it costs one extra draw call
## and the mesh's triangles again, so crowds of NPCs skip it).
static func character_material(outlined := false) -> ShaderMaterial:
	if _char_mat == null:
		var sh := Shader.new()
		sh.code = CHAR_SHADER
		_char_mat = ShaderMaterial.new()
		_char_mat.shader = sh
		var osh := Shader.new()
		osh.code = OUTLINE_SHADER
		var om := ShaderMaterial.new()
		om.shader = osh
		_char_mat_outlined = _char_mat.duplicate()
		_char_mat_outlined.next_pass = om
	return _char_mat_outlined if outlined else _char_mat

static var _char_mat_outlined: ShaderMaterial
const OUTLINED_LOOKS := ["dad", "bunny_girl", "cat_girl", "beagle"]

static var _prop_cache := {}


## Returns {mesh, skin, names, parents, rests (local Vector3, metres), meta}.
static func get_rig(look: String) -> Dictionary:
	if _cache.has(look):
		return _cache[look]
	var L: Dictionary = Looks.get_look(look)
	var r: Dictionary
	if L.get("species", "human") == "dog":
		r = _build_dog(L)
	else:
		r = _build_human(L)
	(r.mesh as ArrayMesh).surface_set_material(0, character_material(look in OUTLINED_LOOKS))
	_cache[look] = r
	return r


# ---------------------------------------------------------------------------
# Skinned-mesh accumulator

class Acc:
	var vs := 0.05
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var names: Array[String] = []
	var parents := PackedInt32Array()
	var joints := PackedVector3Array()  # model space, metres

	func bone(bname: String, parent: String, joint_vox: Vector3) -> int:
		parents.append(names.find(parent) if parent != "" else -1)
		names.append(bname)
		joints.append(joint_vox * vs)
		return names.size() - 1

	func part(bone_name: String, vb: VoxelBuilder, origin: Vector3) -> void:
		if vb == null or vb.vox.is_empty():
			return
		var bi := names.find(bone_name)
		var j: Vector3 = joints[bi]
		var m := vb.build(vs, origin)
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for i in v.size():
				verts.append(v[i] + j)
				norms.append(n[i])
				cols.append(c[i])
				bones.append(bi)
				bones.append(0)
				bones.append(0)
				bones.append(0)
				weights.append(1.0)
				weights.append(0.0)
				weights.append(0.0)
				weights.append(0.0)

	func finish(meta: Dictionary) -> Dictionary:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		var mesh := st.commit()
		var skin := Skin.new()
		var rests := PackedVector3Array()
		for i in names.size():
			skin.add_named_bind(names[i], Transform3D(Basis(), -joints[i]))
			var p := parents[i]
			rests.append(joints[i] - (joints[p] if p >= 0 else Vector3.ZERO))
		return {"mesh": mesh, "skin": skin, "names": names, "parents": parents, "rests": rests, "meta": meta}


# ---------------------------------------------------------------------------
# Helpers

static func _sh(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1))


static func _fill(vb: VoxelBuilder, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c) -> void:
	if x1 < x0 or y1 < y0 or z1 < z0:
		return
	vb.box(Vector3i(x0, y0, z0), Vector3i(x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1), c)


static func _h(p: Vector3i, s := 0) -> float:
	return VoxelBuilder.hash3(p + Vector3i(s * 131, s * 71, s * 37))


## Hair colour with column streaks (strands) and per-voxel noise.
static func _hair_fn(base: Color) -> Callable:
	return func(p: Vector3i) -> Color:
		var strand := _h(Vector3i(p.x * 2 + p.z, 0, p.z * 3 - p.x), 5)
		var f := 0.78 + 0.32 * strand + 0.08 * _h(p, 9)
		return _sh(base, f)


static func _noise_fn(base: Color, amt: float, s := 1) -> Callable:
	return func(p: Vector3i) -> Color:
		return _sh(base, 1.0 + (_h(p, s) - 0.5) * 2.0 * amt)


## Plaid flannel. `w`/`d` are the part's x/z extents so side faces use z for
## their vertical stripes.
static func _plaid_fn(base: Color, dark: Color, w: int, d: int, ox := 0) -> Callable:
	return func(p: Vector3i) -> Color:
		# Buffalo check: 2-voxel dark bands both ways on 4-voxel repeats,
		# so the flannel reads as big red/black squares at phone size.
		var u := p.z if (p.x == 0 or p.x == w - 1) else p.x + ox
		var vb_ := posmod(u, 4) < 2
		var hb_ := posmod(p.y, 4) < 2
		var c := base
		if vb_ and hb_:
			c = _sh(dark, 0.9)
		elif vb_ or hb_:
			c = base.lerp(dark, 0.5)
		return _sh(c, 1.0 + (_h(p, 3) - 0.5) * 0.06)


static func _gingham_fn(a: Color, b: Color, w: int) -> Callable:
	return func(p: Vector3i) -> Color:
		var u := p.z if (p.x == 0 or p.x == w - 1) else p.x
		var cu := posmod(u, 2) == 0
		var cv := posmod(p.y, 2) == 0
		if cu and cv:
			return b
		if cu or cv:
			return b.lerp(a, 0.55)
		return a


static func _stripe_fn(a: Color, b: Color) -> Callable:
	return func(p: Vector3i) -> Color:
		return a if posmod(p.y, 2) == 0 else b


static func _denim_fn(base: Color) -> Callable:
	return func(p: Vector3i) -> Color:
		var f := 0.92 + 0.14 * _h(p, 4)
		if posmod(p.x + p.y, 3) == 0:
			f *= 0.96
		return _sh(base, f)


# ---------------------------------------------------------------------------
# Humans

static func _build_human(L: Dictionary) -> Dictionary:
	var D: Dictionary = BODY[L.get("body", "slim")]
	var lw: int = D.lw
	var shin: int = D.shin
	var thigh: int = D.thigh
	var tw: int = D.tw
	var td: int = D.td
	var th: int = D.th
	var aw: int = D.aw
	var ua: int = D.ua
	var fa: int = D.fa
	var hw: int = D.hw
	var hh: int = D.hh
	var hd: int = D.hd
	var child: bool = L.get("body", "") == "child"

	var acc := Acc.new()
	acc.vs = VS
	var hip_j := float(shin + thigh) - 0.5
	var P := shin + thigh + 2           # first torso row
	var neck := P + th                  # neck row (head joint)
	var sh_y := float(P + th) - 1.5     # shoulder joint
	var ax := tw * 0.5 + aw * 0.5       # arm centre x
	var lx := lw * 0.5                  # leg centre x

	acc.bone("root", "", Vector3.ZERO)
	acc.bone("hips", "root", Vector3(0, hip_j, 0))
	acc.bone("torso", "hips", Vector3(0, P, 0))
	acc.bone("head", "torso", Vector3(0, neck, 0))
	acc.bone("eyes", "head", Vector3(0, neck + 1 + hh * 0.5, 0))
	acc.bone("arm_l", "torso", Vector3(ax, sh_y, 0))
	acc.bone("fore_l", "arm_l", Vector3(ax, sh_y - (ua - 1.5), 0))
	acc.bone("arm_r", "torso", Vector3(-ax, sh_y, 0))
	acc.bone("fore_r", "arm_r", Vector3(-ax, sh_y - (ua - 1.5), 0))
	acc.bone("thigh_l", "hips", Vector3(lx, hip_j, 0))
	acc.bone("shin_l", "thigh_l", Vector3(lx, shin, 0))
	acc.bone("thigh_r", "hips", Vector3(-lx, hip_j, 0))
	acc.bone("shin_r", "thigh_r", Vector3(-lx, shin, 0))

	var head := _human_head(L, D)
	var hat: String = L.get("hat", "")
	var ear_y := float(neck) + hh + 1.5
	var ear_x := hw * 0.5 - 2.5
	if hat == "cat":
		ear_x = hw * 0.5 - 3.0
	if hat == "bunny" or hat == "cat":
		acc.bone("ear_l", "head", Vector3(ear_x, ear_y, -0.5))
		acc.bone("ear_r", "head", Vector3(-ear_x, ear_y, -0.5))
	else:
		acc.bone("ear_l", "head", Vector3(0, neck + hh * 0.5, 0))
		acc.bone("ear_r", "head", Vector3(0, neck + hh * 0.5, 0))

	acc.part("head", head.head, Vector3(hw * 0.5, 0, hd * 0.5))
	acc.part("eyes", head.eyes, Vector3(hw * 0.5, 1 + hh * 0.5, hd * 0.5))
	if head.has("ear_l"):
		acc.part("ear_l", head.ear_l, head.ear_origin)
		acc.part("ear_r", head.ear_r, head.ear_origin)

	acc.part("torso", _human_torso(L, D), Vector3(tw * 0.5, 0, td * 0.5))
	acc.part("hips", _human_pelvis(L, D), Vector3(tw * 0.5, 0.5, td * 0.5))
	acc.part("arm_l", _human_upper_arm(L, D, true), Vector3(aw * 0.5, ua - 1.5, aw * 0.5))
	acc.part("arm_r", _human_upper_arm(L, D, false), Vector3(aw * 0.5, ua - 1.5, aw * 0.5))
	acc.part("fore_l", _human_forearm(L, D), Vector3(aw * 0.5, fa, aw * 0.5))
	acc.part("fore_r", _human_forearm(L, D), Vector3(aw * 0.5, fa, aw * 0.5))
	acc.part("thigh_l", _human_thigh(L, D, true), Vector3(lw * 0.5, thigh - 0.5, lw * 0.5))
	acc.part("thigh_r", _human_thigh(L, D, false), Vector3(lw * 0.5, thigh - 0.5, lw * 0.5))
	acc.part("shin_l", _human_shin(L, D), Vector3(lw * 0.5, shin, lw * 0.5))
	acc.part("shin_r", _human_shin(L, D), Vector3(lw * 0.5, shin, lw * 0.5))

	var top_extra := 2.0
	if hat == "bunny":
		top_extra = 8.0
	elif hat == "cat":
		top_extra = 4.0
	var meta := {
		"species": "human",
		"kind": "child" if child else "adult",
		"hip_y": hip_j * VS,
		"leg_half": lw * 0.5 * VS,
		"torso_half": td * 0.5 * VS,
		"head_h": (hh + 1 + top_extra) * VS,
		"height": (neck + 1 + hh + 2) * VS,
		"fore_len": fa * VS,
		"shin_len": shin * VS,
		"arm_x": ax * VS,
		"elderly": L.get("elderly", false),
	}
	return acc.finish(meta)


## Head local coords: x 0..hw-1, neck row y=0, head rows 1..hh, z 0..hd-1 (+z = face).
## The skull is a rounded box (superellipse sides, domed crown, tapered jaw),
## so heads read as soft chibi shapes instead of cubes; facial features are
## painted onto whatever voxel is frontmost in their column.
static func _in_skull(x: int, y: int, z: int, W: int, B: int, T: int, F: int) -> bool:
	if x < 0 or x >= W or z < 0 or z > F or y < B or y > T:
		return false
	var dx := absf(x - (W - 1) * 0.5) / (W * 0.5 + 0.15)
	var dz := absf(z - F * 0.5) / ((F + 1) * 0.5 + 0.15)
	var top0 := float(T) - 3.1
	var bot0 := float(B) + 2.1
	var dy := 0.0
	if y > top0:
		dy = (y - top0) / 3.6
	elif y < bot0:
		dy = (bot0 - y) / 2.6
	return pow(dx, 2.8) + pow(dz, 2.8) + pow(dy, 2.5) <= 1.04


## Frontmost occupied z in column (x, y), or -100.
static func _front_z(vb: VoxelBuilder, x: int, y: int, from_z: int) -> int:
	for z in range(from_z, -3, -1):
		if vb.has(Vector3i(x, y, z)):
			return z
	return -100


static func _paint_front(vb: VoxelBuilder, x: int, y: int, c: Color, from_z: int, proud := 0) -> void:
	var z := _front_z(vb, x, y, from_z)
	if z < -50:
		return
	if proud > 0:
		for k in proud:
			vb.set_v(Vector3i(x, y, z + 1 + k), c)
	else:
		vb.set_v(Vector3i(x, y, z), c)


static func _human_head(L: Dictionary, D: Dictionary) -> Dictionary:
	var W: int = D.hw
	var H: int = D.hh
	var Dd: int = D.hd
	var B := 1
	var T := H
	var F := Dd - 1
	var child: bool = L.get("body", "") == "child"
	var skin: Color = L.skin
	var hair: Color = L.get("hair", Color(0.3, 0.2, 0.1))
	var style: String = L.get("hair_style", "short")
	var hat: String = L.get("hat", "")
	var girl: bool = L.get("lashes", false)
	var beard: String = L.get("beard", "")
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	var eyes := VoxelBuilder.new()
	eyes.jitter = 0.0
	var hair_fn := _hair_fn(hair)
	var cxl := W / 2 - 1     # left of the two centre columns
	var cxr := W / 2

	# Skull: rounded box; the lower face is a touch warmer/darker (jaw shade).
	var skin_fn := func(p: Vector3i) -> Color:
		var f := 1.0 + (_h(p, 2) - 0.5) * 0.035
		if p.y <= B:
			f *= 0.95
		return _sh(skin, f)
	for x in range(0, W):
		for y in range(B, T + 1):
			for z in range(0, F + 1):
				if _in_skull(x, y, z, W, B, T, F):
					vb.set_v(Vector3i(x, y, z), skin_fn.call(Vector3i(x, y, z)))
	# Neck.
	_fill(vb, cxl - 1, cxr + 1, 0, 0, F / 2 - 2, F / 2 + 1, _sh(skin, 0.84))

	# Feature rows. Adults: mouth 3, nose 4, eyes 5-6, brows 7.
	# Kids (chibi): smile 2-3, cheeks 4, big eyes 5-7, brows 8.
	var E := B + 4
	var eh := 3 if child else 2
	if girl and not child:
		eh = 3
	var M := B + 2
	var exs: Array = [2, W - 4] if (child or W <= 10) else [3, W - 5]
	# Ears (skin nubs) level with the lower eye row.
	var ear_skin := _sh(skin, 0.88)
	var ez := F / 2
	var ears := true
	if ears:
		_fill(vb, -1, -1, E - 1, E, ez - 1, ez, ear_skin)
		_fill(vb, W, W, E - 1, E, ez - 1, ez, ear_skin)
		vb.set_v(Vector3i(-1, E, ez), _sh(skin, 0.8))
		vb.set_v(Vector3i(W, E, ez), _sh(skin, 0.8))

	var fz := F + 2
	var eye_dark := Color(0.07, 0.05, 0.05)
	var eye_mid: Color = L.get("eye", Color(0.33, 0.19, 0.1))
	var white := Color(1.0, 1.0, 0.98)
	var lid := _sh(skin, 0.86)
	var lash := Color(0.16, 0.09, 0.07)
	for ei in exs.size():
		var ex: int = exs[ei]
		# Highlight on the same (screen-left / outer-top) corner of both eyes.
		var hx := 0
		for dx in 2:
			for dy in eh:
				var x := ex + dx
				var y := E + dy
				var z := _front_z(vb, x, y, fz)
				if z < -50:
					continue
				var p := Vector3i(x, y, z)
				vb.erase(p)
				vb.set_v(p - Vector3i(0, 0, 1), lash if dy == eh - 1 else lid)
				var c := eye_dark
				if dy == eh - 1 and dx == hx:
					c = white
				elif dy == 0:
					c = eye_mid.lerp(eye_dark, 0.25)
				eyes.set_v(p, c)
	# Lower lash line / lids: lashes flick out at the outer top corners.
	if girl:
		var lx0: int = exs[0] - 1
		var lx1: int = exs[1] + 2
		_paint_front(vb, lx0, E + eh - 1, lash, fz)
		_paint_front(vb, lx1, E + eh - 1, lash, fz)
		if not child:
			_paint_front(vb, lx0, E + eh, lash, fz)
			_paint_front(vb, lx1, E + eh, lash, fz)
	# Brows: thick and a little proud on men, soft 2-wide arcs otherwise.
	var brow: Color = L.get("brow", _sh(hair, 0.75))
	var by := E + eh
	if not child and not girl:
		by = E + eh + 1   # a row of skin between brow and eye so both read
	if child:
		by = E + eh
		for ei in exs.size():
			var ex: int = exs[ei]
			_paint_front(vb, ex, by, _sh(brow, 1.05), fz)
			_paint_front(vb, ex + 1, by, _sh(brow, 1.05), fz)
	elif girl:
		for ei in exs.size():
			var ex: int = exs[ei]
			_paint_front(vb, ex, by, brow, fz)
			_paint_front(vb, ex + 1, by, brow, fz)
	else:
		for ei in exs.size():
			var ex: int = exs[ei]
			var outer := ex - 1 if ei == 0 else ex + 2
			for x in [outer, ex, ex + 1]:
				_paint_front(vb, x, by, brow, fz)
			# Proud ridge over the inner two so brows cast a little shadow.
			_paint_front(vb, ex, by, _sh(brow, 1.1), fz, 1)
			_paint_front(vb, ex + 1, by, _sh(brow, 1.1), fz, 1)
	# Cheeks (blush) under the outer half of each eye.
	var blush := skin.lerp(Color(0.98, 0.42, 0.45), 0.5 if child else (0.38 if girl else 0.3))
	_paint_front(vb, exs[0], E - 1, blush, fz)
	_paint_front(vb, exs[0] - 1 if child else exs[0], E - 1, blush, fz)
	_paint_front(vb, exs[1] + 1, E - 1, blush, fz)
	_paint_front(vb, exs[1] + 2 if child else exs[1] + 1, E - 1, blush, fz)
	if child:
		_paint_front(vb, exs[0] + 1, E - 1, blush.lerp(skin, 0.4), fz)
		_paint_front(vb, exs[1], E - 1, blush.lerp(skin, 0.4), fz)
	# Nose.
	if child:
		_paint_front(vb, cxl, E - 1, _sh(skin, 0.92), fz)
		_paint_front(vb, cxr, E - 1, _sh(skin, 0.92), fz)
	else:
		_paint_front(vb, cxl, E - 1, _sh(skin, 0.94), fz, 1)
		_paint_front(vb, cxr, E - 1, _sh(skin, 0.9), fz, 1)
	# Mouth: a little smile (corners up), open + tongue on kids.
	var mouth := Color(0.55, 0.18, 0.2)
	var lip := Color(0.85, 0.42, 0.45)
	if child:
		_paint_front(vb, cxl, M - 1, mouth, fz)
		_paint_front(vb, cxr, M - 1, Color(0.93, 0.45, 0.5), fz)
		_paint_front(vb, cxl - 1, M, mouth, fz)
		_paint_front(vb, cxr + 1, M, mouth, fz)
		_paint_front(vb, cxl, M, _sh(skin, 0.97), fz)
		_paint_front(vb, cxr, M, _sh(skin, 0.97), fz)
	elif beard != "full":
		_paint_front(vb, cxl, M, mouth if not girl else Color(0.78, 0.3, 0.34), fz)
		_paint_front(vb, cxr, M, mouth if not girl else Color(0.78, 0.3, 0.34), fz)
		_paint_front(vb, cxl - 1, M + 1 if girl else M, _sh(skin, 0.86), fz)
		_paint_front(vb, cxr + 1, M + 1 if girl else M, _sh(skin, 0.86), fz)

	# Beard.
	var beard_c: Color = L.get("beard_color", _sh(hair, 0.8))
	var bcell := func(p: Vector3i) -> Color:
		# Curly clumps: shade varies per 2x2 cell, lighter on the cell tops.
		var cell := Vector3i(floori(p.x / 2.0), floori(p.y / 2.0), floori(p.z / 2.0))
		var f := 0.84 + 0.3 * _h(cell, 61) + (0.07 if posmod(p.y, 2) == 1 else -0.03)
		return _sh(beard_c, f * (1.0 + (_h(p, 62) - 0.5) * 0.08))
	if beard == "full":
		var mus := _sh(beard_c.lerp(hair, 0.45), 1.08)
		# 1) Recolour the skull surface on the lower face / jaw / sideburns.
		var bset := {}
		for p: Vector3i in vb.vox.keys():
			if p.y < B or p.x < 0 or p.x >= W:
				continue
			var side := p.x <= 1 or p.x >= W - 2
			var in_beard := false
			# Front half of the head only: behind the jaw line the side of
			# the head shows skin, the ear and the hair, so the profile
			# (seen 3/4 from the house camera) reads as a face, not a mop.
			var bz := F - 5
			if p.y <= M and p.z >= bz:
				in_beard = true
			elif p.y == M + 1 and p.z >= bz and (p.x <= cxl - 3 or p.x >= cxr + 3 or p.z <= F - 2):
				in_beard = true
			elif side and p.y <= E and p.z >= bz + 1 and p.z <= F - 2:
				in_beard = true
			if in_beard:
				bset[p] = true
		for p: Vector3i in bset:
			vb.set_v(p, bcell.call(p))
		# 2) One voxel of volume outward (front + sides), so it wraps the jaw.
		for p: Vector3i in bset:
			for d: Vector3i in [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
				var q := p + d
				if vb.has(q) or q == Vector3i(-1, E, ez) or q == Vector3i(W, E, ez):
					continue
				if d.z == 0 and (p.y > M or p.z > F - 2):
					continue
				vb.set_v(q, bcell.call(q))
		if ears:
			_fill(vb, -1, -1, E - 1, E, ez - 1, ez, ear_skin)
			_fill(vb, W, W, E - 1, E, ez - 1, ez, ear_skin)
		# 3) Chin volume under the jaw, rounded, hanging a little low.
		# Jaw-hugging: one row under the jaw and a short rounded chin only.
		_fill(vb, 2, W - 3, 0, 0, F - 3, F + 1, bcell)
		_fill(vb, cxl, cxr, -1, -1, F, F + 1, bcell)
		for x in [2, W - 3]:
			vb.erase(Vector3i(x, 0, F + 1))
		# 4) Mouth: a warm smile showing through the beard under the moustache.
		for x in [cxl, cxr]:
			_paint_front(vb, x, M - 1, Color(0.6, 0.22, 0.22), F + 3)
		# 5) Lighter moustache across the upper lip, ends curling down.
		var muz := _front_z(vb, cxl, M, F + 3)
		for x in range(cxl - 2, cxr + 3):
			var z := maxi(muz, _front_z(vb, x, M, F + 3))
			vb.set_v(Vector3i(x, M, z), _sh(mus, 0.95 + 0.1 * _h(Vector3i(x, M, 0), 63)))
		vb.set_v(Vector3i(cxl - 2, M - 1, muz), _sh(mus, 0.92))
		vb.set_v(Vector3i(cxr + 2, M - 1, muz), _sh(mus, 0.92))
	elif beard == "short":
		for p: Vector3i in vb.vox.keys():
			if p.y >= B and p.y <= M and p.z >= 3 and p.x >= 0 and p.x < W:
				if p.y == M and p.x >= cxl - 1 and p.x <= cxr + 1 and p.z >= F - 1:
					continue
				vb.set_v(p, bcell.call(p))
			elif (p.x <= 0 or p.x >= W - 1) and p.y <= E and p.y >= B and p.z >= 3 and p.z <= F - 2:
				vb.set_v(p, bcell.call(p))
		_fill(vb, 2, W - 3, 0, 0, 4, F, bcell)
		_paint_front(vb, cxl, M, mouth, F + 2)
		_paint_front(vb, cxr, M, mouth, F + 2)
		for x in range(cxl - 2, cxr + 3):
			_paint_front(vb, x, M + 1 if (x >= cxl - 1 and x <= cxr + 1) else M, bcell.call(Vector3i(x, M + 1, F)), F + 2)
		_paint_front(vb, cxl, M + 1, bcell.call(Vector3i(cxl, M + 1, F)), F + 2, 1)
		_paint_front(vb, cxr, M + 1, bcell.call(Vector3i(cxr, M + 1, F)), F + 2, 1)
	elif beard == "moustache":
		var mus2 := _sh(beard_c, 1.0)
		for x in range(cxl - 2, cxr + 3):
			_paint_front(vb, x, M + 1 if x < cxl - 1 or x > cxr + 1 else M + 1, mus2, F + 1, 1)
		_paint_front(vb, cxl - 2, M, mus2, F + 1, 1)
		_paint_front(vb, cxr + 2, M, mus2, F + 1, 1)

	_human_hair(vb, style, hair_fn, W, H, Dd, B, T, F, hat != "", child)
	if style != "shaggy" and style != "curly" and style != "afro" and hat == "":
		# Round off the hair's box corners and crown (soft chibi silhouette).
		var hx := W * 0.5 + 1.6
		var hz := (F + 1) * 0.5 + 1.6
		var cut: Array[Vector3i] = []
		for p: Vector3i in vb.vox.keys():
			if p.y < T - 3:
				continue
			var dx := absf(p.x - (W - 1) * 0.5) / hx
			var dz := absf(p.z - F * 0.5) / hz
			var dy := maxf(0.0, (p.y - (T - 2.0)) / 4.2)
			if pow(dx, 3.0) + pow(dz, 3.0) + pow(dy, 2.2) > 1.0:
				cut.append(p)
		for p in cut:
			vb.erase(p)
	# Sun-kissed crown: hair on top catches a little more light.
	if hat == "":
		for p: Vector3i in vb.vox.keys():
			if p.y >= T + 1:
				vb.vox[p] = _sh(vb.vox[p], 1.08)
	var out := {"head": vb, "eyes": eyes}
	if hat != "":
		_human_hat(vb, L, W, H, Dd, B, T, F, out)
	if L.get("glasses", false):
		# Thin warm-gold rims standing one voxel proud; lenses stay open.
		var gc := Color(0.55, 0.4, 0.26)
		var gz := F + 1
		for ex: int in exs:
			for x in range(ex - 1, ex + 3):
				vb.set_v(Vector3i(x, E + eh, gz), gc)
				vb.set_v(Vector3i(x, E - 1, gz), gc)
			for y in range(E, E + eh):
				vb.set_v(Vector3i(ex - 1, y, gz), gc)
				vb.set_v(Vector3i(ex + 2, y, gz), gc)
		for z in range(F - 4, F + 1):
			vb.set_v(Vector3i(-1, E + eh - 1, z), gc)
			vb.set_v(Vector3i(W, E + eh - 1, z), gc)
	return out


static func _human_hair(vb: VoxelBuilder, style: String, hc: Callable, W: int, H: int, Dd: int, B: int, T: int, F: int, has_hat: bool, child := false) -> void:
	if style == "bald":
		# Short fringe of hair behind the ears (not a block over them).
		_fill(vb, -1, -1, B + 4, T - 3, 0, F - 6, hc)
		_fill(vb, W, W, B + 4, T - 3, 0, F - 6, hc)
		_fill(vb, 0, W - 1, B + 2, T - 3, -1, -1, hc)
		return
	if style == "shaggy":
		# Dad (r10): a TIGHT curly cap that hugs the skull, 1 voxel proud with
		# a few 1-voxel curl bumps on the crown, a clean short fringe over the
		# top of the forehead, tidy sides above the ears and a short back.
		# The face (forehead, brows, eyes, nose, cheeks) stays fully exposed.
		var E := B + 4
		var curl := func(p: Vector3i) -> Color:
			# Curls: shade per 2x2 clump, lit on the clump top, darker in gaps.
			var cell := Vector3i(floori((p.x + 1) / 2.0), floori(p.y / 2.0), floori((p.z + 1) / 2.0))
			var f := 0.86 + 0.26 * _h(cell, 54) + (0.08 if posmod(p.y, 2) == 1 else -0.04)
			return _sh(hc.call(p), f)
		var in_region := func(p: Vector3i) -> bool:
			var front := p.z >= F - 1
			var side := p.x < 0 or p.x >= W
			var back := p.z <= 1
			if p.y > T:
				return true
			if front and not side:
				return p.y >= T - 1
			if side:
				if p.z >= F - 1:
					return p.y >= T - 1
				return p.y >= (E + 2 if p.z >= 3 else B + 3)
			if back:
				return p.y >= B + 2
			return p.y >= T - 1
		var shell := {}
		for p: Vector3i in vb.vox.keys():
			if p.y < B:
				continue
			for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var q: Vector3i = p + d
				if vb.has(q) or shell.has(q):
					continue
				if in_region.call(q):
					shell[q] = true
		# Paint the skull surface itself in the hair region too (no skin gaps).
		for p: Vector3i in vb.vox.keys():
			if p.y >= T or (p.y >= T - 1 and p.z < F - 1) or (p.z <= 1 and p.y >= B + 3) or ((p.x == 0 or p.x == W - 1) and p.y >= E + 3 and p.z < F - 2):
				vb.set_v(p, _sh(curl.call(p), 0.8))
		for q: Vector3i in shell:
			vb.set_v(q, curl.call(q))
		# Fringe: ragged short locks dipping one row onto the forehead.
		for x in range(1, W - 1):
			if _h(Vector3i(x, 2, 9), 55) > 0.45:
				var z := _front_z(vb, x, T - 2, F + 1)
				if z > -50:
					vb.set_v(Vector3i(x, T - 2, z + 1), curl.call(Vector3i(x, T - 2, z + 1)))
		# Small curls breaking the side/back outline.
		for p: Vector3i in shell:
			if (p.x < 0 or p.x >= W or p.z < 0) and p.y >= T - 2 and _h(p, 57) > 0.8:
				var o := Vector3i(-1 if p.x < 0 else (1 if p.x >= W else 0), 0, -1 if p.z < 0 and p.x >= 0 and p.x < W else 0)
				vb.set_v(p + o, curl.call(p + o))
		return
	var curly := style == "curly" or style == "curly_long" or style == "afro"
	# Cap over the top of the skull.
	_fill(vb, 0, W - 1, T + 1, T + 1, 0, F, hc)
	# Side + back shell.
	var side_lo := T - 3
	var back_lo := B + 1
	_fill(vb, -1, -1, side_lo, T, 0, F - 1, hc)
	_fill(vb, W, W, side_lo, T, 0, F - 1, hc)
	_fill(vb, -1, -1, B + 4, side_lo, 0, 3, hc)
	_fill(vb, W, W, B + 4, side_lo, 0, 3, hc)
	_fill(vb, 0, W - 1, back_lo, T, -1, -1, hc)
	# Hairline on the forehead.
	_fill(vb, 0, W - 1, T, T, F, F, hc)
	if not has_hat:
		for x in range(0, W):
			if _h(Vector3i(x, 1, 2), 7) > 0.35:
				vb.set_v(Vector3i(x, T - 1, F), hc.call(Vector3i(x, T - 1, F)))
	match style:
		"messy", "short":
			_fill(vb, 0, W - 1, T - 1, T - 1, F, F, hc)
			# Fringe that sticks out over the forehead.
			for x in range(0, W):
				if style == "messy" and _h(Vector3i(x, 3, 1), 11) > 0.3:
					vb.set_v(Vector3i(x, T, F + 1), hc.call(Vector3i(x, T, F + 1)))
				elif style == "short" and x > 0 and x < W - 1:
					vb.set_v(Vector3i(x, T, F + 1), hc.call(Vector3i(x, T, F + 1)))
			_fill(vb, -1, W, T + 1, T + 1, -1, F, hc)
			_fill(vb, 0, W - 1, T + 2, T + 2, 0, F, func(p: Vector3i) -> Color:
				if style == "short" and (p.x == 0 or p.x == W - 1 or p.z == 0):
					return Color(0, 0, 0, 0)
				return hc.call(p) if _h(p, 12) > (0.15 if style == "messy" else 0.0) else Color(0, 0, 0, 0))
			if style == "messy":
				for x in range(1, W - 1):
					for z in range(2, F + 1):
						if _h(Vector3i(x, 0, z), 13) > 0.78:
							vb.set_v(Vector3i(x, T + 3, z), hc.call(Vector3i(x, T + 3, z)))
				# Swept quiff at the front.
				_fill(vb, 1, W - 3, T + 2, T + 2, F - 2, F + 1, hc)
				_fill(vb, 2, W - 4, T + 3, T + 3, F - 1, F, hc)
		"long", "curly_long", "ponytail", "bun":
			if not has_hat:
				_fill(vb, -1, W, T + 1, T + 1, -1, F, hc)
				_fill(vb, 0, W - 1, T + 2, T + 2, 0, F - 1, hc)
			var low := (-6 if child else -7) if style != "bun" and style != "ponytail" else B + 1
			if style == "long" or style == "curly_long":
				# r10: long hair that falls BEHIND the shoulders. Side curtains
				# frame the face only down to the jaw; behind the ears the hair
				# drops straight down the back (tucked close to the shoulders,
				# never a puffed dome), ending in ragged locks at mid back.
				var lock_fn := func(p: Vector3i) -> Color:
					var c: Color = hc.call(p)
					var lock := posmod(p.x + 1, 3) == 0
					var f := 0.84 if lock else 1.0
					if p.y < B:
						f *= 0.94
					return _sh(c, f)
				for z in range(0, F - 2):
					for x in [-1, W]:
						# Front edge of the curtain stops above the jaw so the
						# cheek shows in profile; the back falls to the neck.
						var y0 := B + 3 if z >= F - 4 else B + 1
						for y in range(y0, T + 1):
							vb.set_v(Vector3i(x, y, z), lock_fn.call(Vector3i(x, y, z)))
				# Front corner wisps framing the cheeks (in the face plane).
				for x in [0, W - 1]:
					for y in range(B + 3, T - 1):
						_paint_front(vb, x, y, lock_fn.call(Vector3i(x, y, F)), F + 1)
				var cx := (W - 1) * 0.5
				for x in range(-1, W + 1):
					var lk := int(floor((x + 1) / 3.0))
					var taper := int(absf(x - cx) * 0.45)
					var end := low + taper + int(_h(Vector3i(lk, 0, 0), 15) * 2.0) + (1 if posmod(x + 1, 3) == 0 else 0)
					# Back of the head.
					for y in range(maxi(end, B), T + 1):
						vb.set_v(Vector3i(x, y, -1), lock_fn.call(Vector3i(x, y, -1)))
					# Below the head: a slab hanging against the upper back.
					if x >= 0 and x < W:
						for y in range(end, B):
							for z in range(-1, 3):
								if z == -1 and y < end + 2:
									continue
								vb.set_v(Vector3i(x, y, z), lock_fn.call(Vector3i(x, y, z)))
					elif not has_hat:
						for y in range(B + 3, T - 1):
							for z in range(0, F - 3):
								vb.set_v(Vector3i(x - 1 if x < 0 else x + 1, y, z), lock_fn.call(Vector3i(x, y, z)))
			else:
				_fill(vb, -1, -1, B + 2, T, 0, F - 1, hc)
				_fill(vb, W, W, B + 2, T, 0, F - 1, hc)
			# Bangs.
			var bang_top := T - 2 if has_hat else T
			var bang_lo := T - 2 if has_hat else T - 3
			for x in range(0, W):
				for y in range(bang_lo, bang_top + 1):
					if y == bang_lo and not has_hat and _h(Vector3i(x, 0, 0), 16) < 0.5:
						continue
					vb.set_v(Vector3i(x, y, F), hc.call(Vector3i(x, y, F)))
				if _h(Vector3i(x, 1, 0), 17) > 0.3:
					vb.set_v(Vector3i(x, bang_top, F + 1), hc.call(Vector3i(x, bang_top, F + 1)))
			if style == "bun":
				_fill(vb, W / 2 - 2, W / 2 + 1, T + 2, T + 4, 1, 4, hc)
				_fill(vb, W / 2 - 1, W / 2, T + 5, T + 5, 2, 3, hc)
			elif style == "ponytail":
				_fill(vb, W / 2 - 1, W / 2, B - 3, T - 2, -3, -2, hc)
				_fill(vb, W / 2 - 1, W / 2, T - 3, T - 2, -1, -1, Color(0.85, 0.2, 0.3))
		"curly", "afro":
			var r := 2 if style == "afro" else 1
			for x in range(-r - 1, W + r + 1):
				for z in range(-r - 1, F + 2):
					for y in range(T - 4, T + 2 + r + 1):
						var inside_head := x >= -1 and x <= W and z >= -1 and z <= F and y <= T + 1
						if inside_head and not (y > T or x < 0 or x >= W or z < 0):
							continue
						if z >= F and y < T - 1:
							continue
						if (z > F) and y < T:
							continue
						# Bumpy shell.
						var dx := maxf(maxf(-x, x - (W - 1)), 0.0)
						var dz := maxf(maxf(-z, z - F), 0.0)
						var dy := maxf(float(y - (T + 1)), 0.0)
						var d := dx + dz + dy
						if d <= r + (1 if _h(Vector3i(x, y, z), 18) > 0.5 else 0):
							vb.set_v(Vector3i(x, y, z), hc.call(Vector3i(x, y, z)))
			for x in range(0, W):
				if _h(Vector3i(x, 0, 5), 19) > 0.3:
					vb.set_v(Vector3i(x, T - 1, F), hc.call(Vector3i(x, T - 1, F)))
				vb.set_v(Vector3i(x, T, F + 1), hc.call(Vector3i(x, T, F + 1)))


static func _human_hat(vb: VoxelBuilder, L: Dictionary, W: int, H: int, Dd: int, B: int, T: int, F: int, out: Dictionary) -> void:
	var hat: String = L.hat
	var hc: Color = L.get("hat_color", Color(0.9, 0.7, 0.8))
	var knit := func(p: Vector3i) -> Color:
		var u := p.z if (p.x <= -1 or p.x >= W) else p.x
		var f := 0.95 if posmod(u, 2) == 0 else 1.04
		return _sh(hc, f * (1.0 + (_h(p, 21) - 0.5) * 0.05))
	if hat == "bunny" or hat == "cat":
		# Rounded knit beanie that sits ON the head: ribbed cuff just above the
		# brows, shell hugging the skull one voxel out, then a soft dome with
		# cut corners on every row (no stacked "cake" tiers). The face stays
		# fully exposed below the cuff.
		var cuff_c: Color = L.get("cuff_color", _sh(hc, 1.06))
		# r10: SNUG beanie. The hat is the skull grown by one voxel on every
		# side and two on top (same rounded superellipse), from just above
		# the brows up; nothing stands off the head like a cake or helmet.
		var c0 := T - 1
		var hcx := (W - 1) * 0.5
		var hcz := F * 0.5
		var in_hat := func(x: int, y: int, z: int) -> bool:
			if y < c0:
				return false
			# Rounded-box beanie: squarish sides (few terraces), soft crown.
			var dx := absf(x - hcx) / (W * 0.5 + 0.95)
			var dz := absf(z - hcz) / ((F + 1) * 0.5 + 0.95)
			var dy := maxf(0.0, (y - (T - 0.5)) / 3.4)
			return pow(dx, 3.4) + pow(dz, 3.4) + pow(dy, 2.6) <= 1.0
		# Hair can't poke through the hat above the cuff line.
		for y in range(c0, T + 7):
			for x in range(-4, W + 4):
				for z in range(-5, F + 4):
					var p := Vector3i(x, y, z)
					if vb.has(p) and not in_hat.call(x, y, z):
						vb.erase(p)
		for y in range(c0, T + 4):
			for x in range(-1, W + 1):
				for z in range(-1, F + 2):
					if not in_hat.call(x, y, z):
						continue
					# Only the outer shell needs voxels (inside is skull/hidden).
					var p := Vector3i(x, y, z)
					var u := z if (x <= 0 or x >= W - 1) else x
					if y <= c0 + 1:
						# Ribbed cuff: vertical ribs, brighter turned-up band.
						vb.set_v(p, _sh(cuff_c, 0.92 if posmod(u, 2) == 0 else 1.03))
					else:
						vb.set_v(p, knit.call(p))
		# Fold shadow just above the cuff, all the way round.
		for p: Vector3i in vb.vox.keys():
			if p.y == c0 + 2 and not _in_skull(p.x, p.y, p.z, W, B, T, F):
				vb.set_v(p, _sh(vb.vox[p], 0.88))
		if hat == "cat":
			# Stitched seam dots near the front corners (like the ref hat).
			var st := _sh(hc, 0.62)
			for x in [2, W - 3]:
				var z := _front_z(vb, x, c0 + 3, F + 3)
				if z > -50:
					vb.set_v(Vector3i(x, c0 + 3, z), st)
		# Ears on their own bones.
		var outer: Color = L.get("ear_color", hc)
		var inner: Color = L.get("ear_inner", Color(0.95, 0.55, 0.65))
		var el := VoxelBuilder.new()
		el.jitter = 0.03
		if hat == "bunny":
			# r10: small accent ears, 3 wide, 7 tall, 2 deep, pink inner front,
			# rounded tip, slightly pinched base.
			for y in range(0, 7):
				for x in range(0, 3):
					for z in range(0, 2):
						if y == 6 and x != 1:
							continue
						if y == 0 and x != 1 and z == 0:
							continue
						var c := outer
						if z == 1 and x == 1 and y >= 1 and y <= 5:
							c = inner
						el.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 22) - 0.5) * 0.06))
			out["ear_origin"] = Vector3(1.5, 0.5, 1.0)
		else:
			# Round teddy/cat ears: 4 wide, 3 tall, pink inner on the front.
			for y in range(0, 4):
				var x0 := 0
				var x1 := 3
				if y == 3:
					x0 = 1; x1 = 2
				for x in range(x0, x1 + 1):
					for z in range(0, 2):
						var c := outer
						if z == 1 and y >= 1 and y <= 2 and (x == 1 or x == 2):
							c = inner
						el.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 24) - 0.5) * 0.06))
			out["ear_origin"] = Vector3(2.0, 0.5, 1.0)
		out["ear_l"] = el
		out["ear_r"] = el
		if hat == "cat":
			# Little stitched face on the beanie (as in the reference).
			pass
	elif hat == "cap" or hat == "flat_cap":
		var cc := _noise_fn(hc, 0.04, 23)
		_fill(vb, -1, W, T - 1, T + 1, -1, F + 1, cc)
		_fill(vb, 0, W - 1, T + 2, T + 2, 0, F, cc)
		_fill(vb, 0, W - 1, T - 1, T + 1, 0, F, Color(0, 0, 0, 0))
		var brim_len := 3 if hat == "cap" else 2
		_fill(vb, 0, W - 1, T - 1, T - 1, F + 2, F + 1 + brim_len, _sh(hc, 0.85))
		for x in range(-1, W + 1):
			for z in range(-1, F + 2):
				for y in range(T - 1, T + 2):
					var p := Vector3i(x, y, z)
					var shell := x == -1 or x == W or z == -1 or z == F + 1
					if shell:
						vb.set_v(p, cc.call(p))
		# Round the crown + corners (keep the brim).
		var cut: Array[Vector3i] = []
		for p: Vector3i in vb.vox.keys():
			if p.y < T - 1 or (p.z > F + 1 and p.y == T - 1):
				continue
			var dx := absf(p.x - (W - 1) * 0.5) / (W * 0.5 + 1.2)
			var dz := absf(p.z - F * 0.5) / ((F + 1) * 0.5 + 1.2)
			var dy := maxf(0.0, (p.y - (T - 0.5)) / 3.0)
			if pow(dx, 3.0) + pow(dz, 3.0) + pow(dy, 2.2) > 1.0:
				cut.append(p)
		for p in cut:
			vb.erase(p)
		if hat == "cap":
			vb.set_v(Vector3i(W / 2, T + 2, F / 2), _sh(hc, 0.8))


static func _human_torso(L: Dictionary, D: Dictionary) -> VoxelBuilder:
	var tw: int = D.tw
	var td: int = D.td
	var th: int = D.th
	var F := td - 1
	var c := tw / 2
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var top: String = L.get("top", "plain")
	var tc: Color = L.get("top_color", Color(0.8, 0.8, 0.8))
	var tc2: Color = L.get("top_color2", Color(0.95, 0.95, 0.95))
	var skin: Color = L.skin
	var fn: Callable
	match top:
		"plaid":
			fn = _plaid_fn(tc, tc2, tw, td)
		"gingham":
			fn = _gingham_fn(tc2, tc, tw)
		"striped":
			fn = _stripe_fn(tc, tc2)
		_:
			fn = _noise_fn(tc, 0.035, 6)
	_fill(vb, 0, tw - 1, 0, th - 1, 0, F, fn)
	# Round the shoulders a little.
	for z in range(0, td):
		vb.erase(Vector3i(0, th - 1, z))
		vb.erase(Vector3i(tw - 1, th - 1, z))
	for x in range(0, tw):
		vb.erase(Vector3i(x, th - 1, 0))
	# Neckline.
	_fill(vb, c - 1, c, th - 1, th - 1, F, F, _sh(skin, 0.9))
	match top:
		"plaid":
			# Open flannel over a dark tee; pocket; button placket.
			var tee: Color = L.get("tee", Color(0.22, 0.22, 0.25))
			_fill(vb, c - 1, c, th - 4, th - 1, F, F, _noise_fn(tee, 0.04, 7))
			vb.set_v(Vector3i(c - 2, th - 1, F + 1), _sh(tc, 1.08))
			vb.set_v(Vector3i(c + 1, th - 1, F + 1), _sh(tc, 1.08))
			vb.set_v(Vector3i(c - 2, th - 2, F + 1), _sh(tc, 1.0))
			vb.set_v(Vector3i(c + 1, th - 2, F + 1), _sh(tc, 1.0))
			for y in range(0, th - 4):
				vb.set_v(Vector3i(c - 1, y, F), _sh(tc, 0.78) if posmod(y, 2) == 1 else _sh(tc, 0.9))
			_fill(vb, c + 2, c + 3, th - 4, th - 4, F + 1, F + 1, _plaid_fn(tc, tc2, tw, td, 1))
			vb.set_v(Vector3i(c + 2, th - 3, F + 1), _sh(tc2, 0.9))
			vb.set_v(Vector3i(c + 3, th - 3, F + 1), _sh(tc2, 0.9))
		"gingham", "plain", "striped":
			var collar: Color = L.get("collar", Color(0, 0, 0, 0))
			if collar.a > 0:
				for x in range(c - 2, c + 2):
					vb.set_v(Vector3i(x, th - 1, F + 1) if (x == c - 2 or x == c + 1) else Vector3i(x, th - 1, F), collar)
				vb.set_v(Vector3i(c - 1, th - 1, F), _sh(skin, 0.9))
				vb.set_v(Vector3i(c, th - 1, F), _sh(skin, 0.9))
		"cardigan", "jacket", "vest", "hoodie":
			var inner: Color = L.get("tee", Color(0.95, 0.93, 0.88))
			_fill(vb, c - 1, c, 0, th - 1, F, F, _noise_fn(inner, 0.03, 8))
			if top == "cardigan":
				for y in range(1, th - 1, 2):
					vb.set_v(Vector3i(c - 2, y, F + 1), Color(0.85, 0.78, 0.6))
				for x in range(0, tw):
					vb.set_v(Vector3i(x, 0, F), _sh(tc, 0.85))
			elif top == "jacket":
				_fill(vb, c - 2, c - 2, th - 3, th - 1, F + 1, F + 1, _sh(tc, 1.1))
				_fill(vb, c + 1, c + 1, th - 3, th - 1, F + 1, F + 1, _sh(tc, 1.1))
				_fill(vb, 1, 2, 1, 2, F + 1, F + 1, _sh(tc, 0.85))
				_fill(vb, tw - 3, tw - 2, 1, 2, F + 1, F + 1, _sh(tc, 0.85))
			elif top == "vest":
				for y in range(1, th - 2, 2):
					vb.set_v(Vector3i(c - 2, y, F + 1), Color(0.8, 0.7, 0.4))
			elif top == "hoodie":
				_fill(vb, 0, tw - 1, 0, th - 1, F, F, fn)
				_fill(vb, c - 2, c + 1, 1, 3, F + 1, F + 1, _sh(tc, 0.88))
				vb.set_v(Vector3i(c - 1, th - 2, F + 1), Color(0.95, 0.95, 0.95))
				vb.set_v(Vector3i(c, th - 2, F + 1), Color(0.95, 0.95, 0.95))
				vb.set_v(Vector3i(c - 1, th - 3, F + 1), Color(0.95, 0.95, 0.95))
				vb.set_v(Vector3i(c, th - 3, F + 1), Color(0.95, 0.95, 0.95))
				_fill(vb, 1, tw - 2, th - 3, th - 1, -1, -1, _sh(tc, 0.92))
				_fill(vb, c - 1, c, th - 1, th - 1, F, F, _sh(tc, 0.8))
	var bottom: String = L.get("bottom", "jeans")
	if bottom == "overalls":
		var den: Color = L.get("bottom_color", Color(0.35, 0.5, 0.8))
		var dfn := _denim_fn(den)
		var bib_top := th - 3 if th > 6 else th - 2
		_fill(vb, 2, tw - 3, 0, bib_top, F + 1, F + 1, dfn)
		_fill(vb, 0, tw - 1, 0, 0, -1, F, dfn)
		# Pocket on the bib.
		_fill(vb, c - 1, c, bib_top - 1, bib_top - 1, F + 2, F + 2, _sh(den, 0.85))
		# Straps over the shoulders.
		for sx in [2, tw - 3]:
			_fill(vb, sx, sx, bib_top, th - 1, F + 1, F + 1, dfn)
			_fill(vb, sx, sx, th, th, 0, F + 1, dfn)
			_fill(vb, sx, sx, th - 4, th - 1, -1, -1, dfn)
			vb.set_v(Vector3i(sx, bib_top, F + 2), Color(0.95, 0.78, 0.3))
	if L.get("apron", false):
		var ac: Color = L.get("apron_color", Color(0.18, 0.45, 0.28))
		var afn := _noise_fn(ac, 0.04, 9)
		_fill(vb, 1, tw - 2, 0, th - 3, F + 1, F + 1, afn)
		_fill(vb, 2, 2, th - 2, th - 1, F + 1, F + 1, afn)
		_fill(vb, tw - 3, tw - 3, th - 2, th - 1, F + 1, F + 1, afn)
		_fill(vb, 0, tw - 1, 1, 1, -1, -1, afn)
		# Leaf logo.
		var leaf := Color(0.62, 0.85, 0.45)
		vb.set_v(Vector3i(c, th - 4, F + 2), leaf)
		vb.set_v(Vector3i(c - 1, th - 5, F + 2), leaf)
		vb.set_v(Vector3i(c, th - 5, F + 2), _sh(leaf, 0.85))
	return vb


static func _human_pelvis(L: Dictionary, D: Dictionary) -> VoxelBuilder:
	var tw: int = D.tw
	var td: int = D.td
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var bottom: String = L.get("bottom", "jeans")
	var bc: Color = L.get("bottom_color", Color(0.22, 0.32, 0.55))
	var fn := _denim_fn(bc) if bottom in ["jeans", "overalls", "shorts"] else _noise_fn(bc, 0.04, 10)
	_fill(vb, 0, tw - 1, 0, 2, 0, td - 1, fn)
	var top: String = L.get("top", "plain")
	if L.get("untucked", false):
		var tc: Color = L.get("top_color", Color.WHITE)
		var tfn := _plaid_fn(tc, L.get("top_color2", Color.BLACK), tw, td) if top == "plaid" else _noise_fn(tc, 0.03, 6)
		_fill(vb, 0, tw - 1, 2, 2, 0, td - 1, tfn)
		var c := tw / 2
		vb.set_v(Vector3i(c - 1, 2, td - 1), _sh(tc, 0.8))
	elif L.get("belt", false):
		_fill(vb, 0, tw - 1, 2, 2, 0, td - 1, Color(0.3, 0.2, 0.12))
		vb.set_v(Vector3i(tw / 2, 2, td), Color(0.85, 0.7, 0.35))
		vb.set_v(Vector3i(tw / 2 - 1, 2, td), Color(0.85, 0.7, 0.35))
	if L.get("apron", false):
		var ac: Color = L.get("apron_color", Color(0.18, 0.45, 0.28))
		_fill(vb, 1, tw - 2, -2, 2, td, td, _noise_fn(ac, 0.04, 9))
	return vb


static func _sleeve_fn(L: Dictionary, D: Dictionary, left: bool) -> Callable:
	var tc: Color = L.get("top_color", Color.WHITE)
	var top: String = L.get("top", "plain")
	var aw: int = D.aw
	match top:
		"plaid":
			return _plaid_fn(tc, L.get("top_color2", Color.BLACK), aw, aw, 0 if left else 2)
		"gingham":
			return _gingham_fn(L.get("top_color2", Color.WHITE), tc, aw)
		"striped":
			return _stripe_fn(tc, L.get("top_color2", Color.WHITE))
	return _noise_fn(tc, 0.035, 6)


static func _human_upper_arm(L: Dictionary, D: Dictionary, left: bool) -> VoxelBuilder:
	var aw: int = D.aw
	var ua: int = D.ua
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var skin: Color = L.skin
	var long: bool = L.get("sleeves", "long") == "long"
	var sfn := _sleeve_fn(L, D, left)
	_fill(vb, 0, aw - 1, 0, ua - 1, 0, aw - 1, sfn)
	if not long:
		var cut := ua - 3 if ua > 4 else ua - 2
		_fill(vb, 0, aw - 1, 0, cut - 1, 0, aw - 1, _noise_fn(skin, 0.03, 2))
		_fill(vb, 0, aw - 1, cut, cut, 0, aw - 1, _sh(L.get("top_color", Color.WHITE), 0.92))
	if L.get("bottom", "") == "overalls":
		pass
	return vb


static func _human_forearm(L: Dictionary, D: Dictionary) -> VoxelBuilder:
	var aw: int = D.aw
	var fa: int = D.fa
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var skin: Color = L.skin
	var long: bool = L.get("sleeves", "long") == "long"
	_fill(vb, 0, aw - 1, 0, fa - 1, 0, aw - 1, _noise_fn(skin, 0.03, 2))
	if long:
		_fill(vb, 0, aw - 1, 2, fa - 1, 0, aw - 1, _sleeve_fn(L, D, true))
		var tc: Color = L.get("cuff", _sh(L.get("top_color", Color.WHITE), 0.85))
		_fill(vb, 0, aw - 1, 2, 2, 0, aw - 1, tc)
	# Hand: thumb nub and slightly darker palm.
	vb.set_v(Vector3i(aw / 2, 1, aw), _sh(skin, 0.95))
	_fill(vb, 0, aw - 1, 0, 0, 0, aw - 1, _sh(skin, 0.93))
	return vb


static func _human_thigh(L: Dictionary, D: Dictionary, left: bool) -> VoxelBuilder:
	var lw: int = D.lw
	var thigh: int = D.thigh
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var bottom: String = L.get("bottom", "jeans")
	var bc: Color = L.get("bottom_color", Color(0.22, 0.32, 0.55))
	var fn := _denim_fn(bc) if bottom in ["jeans", "overalls", "shorts"] else _noise_fn(bc, 0.04, 10)
	_fill(vb, 0, lw - 1, 0, thigh - 1, 0, lw - 1, fn)
	if bottom == "shorts" or bottom == "overalls":
		var skin: Color = L.skin
		var cut := 1 if thigh <= 3 else thigh / 2
		_fill(vb, 0, lw - 1, 0, cut - 1, 0, lw - 1, _noise_fn(skin, 0.03, 2))
		# Rolled hem.
		_fill(vb, 0, lw - 1, cut, cut, 0, lw - 1, _sh(bc, 1.12))
	elif bottom == "skirt":
		_fill(vb, -1 if left else 0, lw if not left else lw - 1, thigh - 3, thigh - 1, -1, lw, fn)
	if L.get("apron", false):
		var ac: Color = L.get("apron_color", Color(0.18, 0.45, 0.28))
		_fill(vb, 0, lw - 1, thigh - 3, thigh - 1, lw, lw, _noise_fn(ac, 0.04, 9))
	return vb


static func _human_shin(L: Dictionary, D: Dictionary) -> VoxelBuilder:
	var lw: int = D.lw
	var shin: int = D.shin
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var bottom: String = L.get("bottom", "jeans")
	var bc: Color = L.get("bottom_color", Color(0.22, 0.32, 0.55))
	var skin: Color = L.skin
	var long := bottom == "jeans" or bottom == "pants"
	var leg_fn := (_denim_fn(bc) if bottom == "jeans" else _noise_fn(bc, 0.04, 10)) if long else _noise_fn(skin, 0.03, 2)
	_fill(vb, 0, lw - 1, 2, shin - 1, 0, lw - 1, leg_fn)
	if long:
		# Turned-up cuff.
		_fill(vb, 0, lw - 1, 2, 2, 0, lw - 1, _sh(bc, 1.15) if bottom == "jeans" else _sh(bc, 0.9))
	else:
		var sock: Color = L.get("socks", Color(0.97, 0.97, 0.97))
		_fill(vb, 0, lw - 1, 2, 2, 0, lw - 1, sock)
	# Shoes: rows 0..1, toe one voxel proud.
	var shoe: Color = L.get("shoes", Color(0.3, 0.2, 0.12))
	var kind: String = L.get("shoe_style", "boot")
	var sole := Color(0.95, 0.95, 0.93) if kind == "sneaker" else _sh(shoe, 0.6)
	_fill(vb, 0, lw - 1, 0, 1, 0, lw, _noise_fn(shoe, 0.04, 11))
	_fill(vb, 0, lw - 1, 0, 0, 0, lw, sole)
	if kind == "sneaker":
		vb.set_v(Vector3i(lw / 2, 1, lw), Color(0.97, 0.97, 0.97))
		if lw > 3:
			vb.set_v(Vector3i(lw / 2 - 1, 1, lw), Color(0.97, 0.97, 0.97))
		var accent: Color = L.get("shoe_accent", Color(0.97, 0.97, 0.97))
		vb.set_v(Vector3i(0, 1, lw / 2), accent)
		vb.set_v(Vector3i(lw - 1, 1, lw / 2), accent)
	elif kind == "boot":
		_fill(vb, 0, lw - 1, 2, 2, 0, lw - 1, _noise_fn(shoe, 0.04, 11))
		vb.set_v(Vector3i(lw / 2, 2, lw - 1), _sh(shoe, 0.7))
	return vb


# ---------------------------------------------------------------------------
# Beagle

## True when voxel p lies inside a rounded box (superellipsoid of power `n`)
## spanning 0..size; `fat` grows it slightly so faces stay mostly flat.
static func _in_rbox(p: Vector3i, size: Vector3, n: float, fat := 0.0) -> bool:
	var h := size * 0.5
	var d := (Vector3(p) + Vector3(0.5, 0.5, 0.5) - h).abs()
	var a := h + Vector3(fat, fat, fat)
	return pow(d.x / a.x, n) + pow(d.y / a.y, n) + pow(d.z / a.z, n) <= 1.0


static func _build_dog(L: Dictionary) -> Dictionary:
	# Chibi beagle (ref1): big rounded head with a white blaze running down
	# into a protruding white muzzle, glossy black nose, big black eyes, long
	# dark-brown floppy ears hanging past the jaw, tan body under a dark
	# brown saddle "blanket", white chest/belly/paws, red collar and an
	# upright white-tipped tail. Tuned for a lying 3/4 view from above.
	var acc := Acc.new()
	acc.vs = VS
	var tan: Color = L.get("tan", Color(0.80, 0.47, 0.2))
	var saddle: Color = L.get("saddle", Color(0.42, 0.25, 0.13))
	var white: Color = L.get("white", Color(0.97, 0.95, 0.9))
	var earc: Color = L.get("ear", Color(0.6, 0.33, 0.14))
	var collar: Color = L.get("collar", Color(0.85, 0.18, 0.18))
	const LEG := 5
	const BW := 10
	const BH := 8
	const BL := 17
	const HW := 12
	const HH := 10
	const HD := 9
	const MZ := 3          # muzzle depth (voxels in front of the face)
	var head_j := Vector3(0, LEG + BH - 2, BL * 0.5 - 1.5)
	var h_origin := Vector3(HW * 0.5, 2.0, 2.0)
	var eye_d := Vector3(0, 3.5, HD - 1.5)
	acc.bone("root", "", Vector3.ZERO)
	acc.bone("body", "root", Vector3(0, LEG, 0))
	acc.bone("head", "body", head_j)
	acc.bone("eyes", "head", head_j + eye_d)
	var ear_d := Vector3(HW * 0.5 + 0.5, HH - 4.5, 2.0)
	acc.bone("ear_l", "head", head_j + Vector3(ear_d.x, ear_d.y, ear_d.z))
	acc.bone("ear_r", "head", head_j + Vector3(-ear_d.x, ear_d.y, ear_d.z))
	acc.bone("tail", "body", Vector3(0, LEG + BH - 1.5, -BL * 0.5 + 1.0))
	acc.bone("leg_fl", "body", Vector3(2.6, LEG + 1, BL * 0.5 - 3.0))
	acc.bone("leg_fr", "body", Vector3(-2.6, LEG + 1, BL * 0.5 - 3.0))
	acc.bone("leg_bl", "body", Vector3(2.6, LEG + 1, -BL * 0.5 + 3.5))
	acc.bone("leg_br", "body", Vector3(-2.6, LEG + 1, -BL * 0.5 + 3.5))

	# Body: x 0..BW-1, y 0..BH-1, z 0..BL-1 (front = +z).
	var body := VoxelBuilder.new()
	body.jitter = 0.03
	var body_fn := func(p: Vector3i) -> Color:
		var c := tan
		var cx := absf(p.x - (BW - 1) * 0.5)
		# Saddle edge wanders in soft 2x3 clumps.
		var wob := int(_h(Vector3i(p.x / 2, 0, p.z / 3), 30) * 2.0)
		if p.y <= 1 or (p.z >= BL - 4 and p.y <= 5 and cx < 3.6):
			c = white
		elif (p.z == BL - 5 or p.z == BL - 4) and p.y >= 4:
			c = collar
		elif p.z >= 3 - wob and p.z <= BL - 7 + wob and (p.y >= BH - 1 or (p.y >= BH - 2 + wob and cx < 4.0) or (p.y >= BH - 3 + wob and cx < 2.5)):
			c = saddle.lerp(tan, 0.12 * _h(p, 35))
		elif p.y == 2 and _h(p, 31) > 0.55:
			c = white.lerp(tan, 0.45)
		return _sh(c, 1.0 + (_h(p, 32) - 0.5) * 0.09)
	_fill(body, 0, BW - 1, 0, BH - 1, 0, BL - 1, func(p: Vector3i) -> Color:
		if not _in_rbox(p, Vector3(BW, BH, BL), 2.6, 0.35):
			return Color(0, 0, 0, 0)
		return body_fn.call(p))
	# Haunches: rounded tan bumps over the back legs.
	for sx in [-1, BW]:
		_fill(body, sx, sx, 1, 5, 1, 6, func(p: Vector3i) -> Color:
			if (p.y == 5 or p.y == 1) and (p.z == 1 or p.z == 6):
				return Color(0, 0, 0, 0)
			return _sh(tan, 0.96 + (_h(p, 38) - 0.5) * 0.1))
	# Fluffy white chest tuft under the chin + gold collar tag.
	_fill(body, 3, BW - 4, 1, 4, BL, BL, func(p: Vector3i) -> Color:
		return _sh(white, 0.98 + (_h(p, 39) - 0.5) * 0.05))
	body.set_v(Vector3i(BW / 2, 4, BL), Color(0.98, 0.82, 0.3))
	body.set_v(Vector3i(BW / 2 - 1, 4, BL), Color(0.98, 0.82, 0.3))
	acc.part("body", body, Vector3(BW * 0.5, 0, BL * 0.5))

	# Head: x 0..HW-1, y 0..HH-1, z 0..HD-1, muzzle in front (z >= HD).
	var head := VoxelBuilder.new()
	head.jitter = 0.03
	var head_fn := func(p: Vector3i) -> Color:
		var c := tan
		var fx := float(p.x) - (HW - 1) * 0.5   # -5.5..5.5
		var ax := absf(fx)
		# Blaze: 2-wide stripe up the face and back over the crown, opening
		# into white cheeks and jaw below the eyes.
		if ax < 1.0 and p.y >= 3 and (p.z >= HD - 2 or (p.y >= HH - 2 and p.z >= 3)):
			c = white
		elif ax < 2.0 and p.y >= 3 and p.y <= 4 and p.z >= HD - 1:
			c = white
		elif p.y <= 2 and p.z >= HD - 3 and ax < 4.0:
			c = white
		elif p.y <= 0 and p.z >= 3:
			c = white
		if c == tan:
			if p.y >= HH - 2 and ax >= 2.0:
				c = _sh(tan, 0.9)
			elif p.z <= 2:
				c = _sh(tan, 0.94)
		return _sh(c, 1.0 + (_h(p, 33) - 0.5) * 0.08)
	_fill(head, 0, HW - 1, 0, HH - 1, 0, HD - 1, func(p: Vector3i) -> Color:
		if not _in_rbox(p, Vector3(HW, HH, HD), 2.4, 0.55):
			return Color(0, 0, 0, 0)
		return head_fn.call(p))
	# Muzzle: white, 6 wide, 4 tall, MZ deep, rounded front corners.
	var muz := func(p: Vector3i) -> Color:
		return _sh(white, 0.99 + (_h(p, 34) - 0.5) * 0.06 - 0.03 * float(p.z - HD))
	_fill(head, 3, HW - 4, 0, 3, HD, HD + MZ - 1, muz)
	_fill(head, 4, HW - 5, 4, 4, HD, HD, muz)
	for zz in [HD + MZ - 1]:
		for cc: Vector3i in [Vector3i(3, 3, zz), Vector3i(HW - 4, 3, zz), Vector3i(3, 0, zz), Vector3i(HW - 4, 0, zz)]:
			head.erase(cc)
	# Big glossy black nose capping the muzzle tip.
	var nose := Color(0.06, 0.04, 0.04)
	var m0 := HW / 2 - 1
	_fill(head, m0 - 1, m0 + 2, 3, 3, HD + MZ - 2, HD + MZ - 1, nose)
	head.erase(Vector3i(m0 - 1, 3, HD + MZ - 1))
	head.erase(Vector3i(m0 + 2, 3, HD + MZ - 1))
	_fill(head, m0, m0 + 1, 4, 4, HD + MZ - 2, HD + MZ - 2, nose)
	head.set_v(Vector3i(m0, 3, HD + MZ - 1), Color(0.3, 0.26, 0.27))
	# Smile: dark line down from the nose and a pink tongue-ish mouth.
	var lip := Color(0.3, 0.17, 0.15)
	head.set_v(Vector3i(m0, 2, HD + MZ - 1), lip)
	head.set_v(Vector3i(m0 + 1, 2, HD + MZ - 1), lip)
	head.set_v(Vector3i(m0 - 1, 1, HD + MZ - 1), lip)
	head.set_v(Vector3i(m0 + 2, 1, HD + MZ - 1), lip)
	head.set_v(Vector3i(m0, 1, HD + MZ - 1), Color(0.92, 0.45, 0.5))
	head.set_v(Vector3i(m0 + 1, 1, HD + MZ - 1), Color(0.92, 0.45, 0.5))
	# Eyes (own bone so they blink): 2 x 3 glossy black with a glint, set
	# either side of the blaze.
	var eyes := VoxelBuilder.new()
	eyes.jitter = 0.0
	for ex: int in [2, HW - 4]:
		for dx in 2:
			for ey in [4, 5, 6]:
				var p := Vector3i(ex + dx, ey, HD - 1)
				if not head.vox.has(p):
					p.z -= 1
				head.erase(p)
				# Closed lid (seen while blinking/sleeping).
				head.set_v(p - Vector3i(0, 0, 1), Color(0.16, 0.09, 0.06) if ey == 4 else _sh(tan, 0.82))
				var glint: bool = ey == 6 and dx == (0 if ex < HW / 2 else 1)
				eyes.set_v(p, Color(1.0, 1.0, 0.98) if glint else Color(0.04, 0.03, 0.03))
		# Soft dark brow above each eye.
		head.set_v(Vector3i(ex, 7, HD - 1), _sh(tan, 0.72))
		head.set_v(Vector3i(ex + 1, 7, HD - 1), _sh(tan, 0.72))
	acc.part("head", head, h_origin)
	acc.part("eyes", eyes, h_origin + eye_d)

	# Long floppy ears: 2 thick, 6 wide flaring to 7, hanging past the jaw.
	var ear := VoxelBuilder.new()
	ear.jitter = 0.03
	for y in range(-11, 1):
		var z0 := 0
		var z1 := 5
		if y <= -5:
			z1 = 6
		if y == 0:
			z0 = 1
			z1 = 4
		if y == -11:
			z0 = 1
			z1 = 5
		for z in range(z0, z1 + 1):
			for x in range(0, 2):
				if x == 1 and y <= -7:
					continue
				var c := earc
				if y >= -1:
					c = _sh(earc, 1.12)
				elif y <= -9:
					c = _sh(earc, 0.8)
				elif x == 0 and (z == z0 or z == z1):
					c = _sh(earc, 0.88)
				ear.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 36) - 0.5) * 0.1))
	acc.part("ear_l", ear, Vector3(0.5, 0.5, 3.0))
	var ear_r := VoxelBuilder.new()
	ear_r.jitter = 0.03
	for p: Vector3i in ear.vox:
		ear_r.set_v(Vector3i(1 - p.x, p.y, p.z), ear.vox[p])
	acc.part("ear_r", ear_r, Vector3(1.5, 0.5, 3.0))

	# Tail: stands up with a forward curl, saddle base, white tip.
	var tail := VoxelBuilder.new()
	tail.jitter = 0.03
	for y in range(0, 10):
		var c := white if y >= 7 else (_sh(saddle, 1.05) if y < 3 else tan)
		var zz := 0 if y < 5 else (1 if y < 8 else 2)
		_fill(tail, 0, 1, y, y, zz, zz + 1, _sh(c, 1.0 + (_h(Vector3i(0, y, 0), 39) - 0.5) * 0.1))
	acc.part("tail", tail, Vector3(1, 0, 1))

	# Legs: 3 x (LEG+1) x 3; front legs white, hind legs tan with white feet,
	# a toe row that reads as a paw when stretched forward.
	for nm in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
		var leg := VoxelBuilder.new()
		leg.jitter = 0.03
		var front: bool = nm.begins_with("leg_f")
		_fill(leg, 0, 2, 0, LEG + 1, 0, 2, func(p: Vector3i) -> Color:
			var c := white
			if not front and p.y >= 2:
				c = tan
			elif front and p.y >= LEG:
				c = white.lerp(tan, 0.35)
			return _sh(c, 1.0 + (_h(p, 37) - 0.5) * 0.08))
		_fill(leg, 0, 2, 0, 0, 3, 3, _sh(white, 0.95))
		leg.set_v(Vector3i(1, 0, 3), _sh(white, 0.8))
		acc.part(nm, leg, Vector3(1.5, LEG + 1.5, 1.5))

	var meta := {
		"species": "dog", "kind": "dog",
		"height": (LEG + BH - 2 - 2 + HH) * VS,
		"head_h": (HH - 2) * VS,
		"leg": LEG * VS,
		"mouth": Vector3(0, -1.0, HD + MZ - 1.0 - h_origin.z) * VS,
		# Body-bone local spot on the floor between the stretched front paws
		# (body lowered by LEG - 0.3 voxels in lying poses).
		"paws": Vector3(0, -0.3 + 1.0, BL * 0.5 + 5.5) * VS,
		# Root-space floor spot in front of the chest for the play bow.
		"paws_root": Vector3(0, 1.0, BL * 0.5 + 7.0) * VS,
	}
	return acc.finish(meta)


# ---------------------------------------------------------------------------
# Hand props (small separate meshes shown only while a pose needs them)

static func prop_mesh(pname: String) -> ArrayMesh:
	if _prop_cache.has(pname):
		return _prop_cache[pname]
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var origin := Vector3.ZERO
	var size := 0.03
	match pname:
		"book":
			# Open picture book; pages face +z.
			var cover := Color(0.25, 0.55, 0.75)
			_fill(vb, 0, 9, 0, 6, 0, 0, cover)
			_fill(vb, 0, 3, 0, 6, 1, 1, Color(0.97, 0.95, 0.88))
			_fill(vb, 6, 9, 0, 6, 1, 1, Color(0.97, 0.95, 0.88))
			_fill(vb, 4, 5, 0, 6, 1, 1, Color(0.85, 0.82, 0.75))
			_fill(vb, 1, 2, 2, 4, 2, 2, Color(0.95, 0.6, 0.3))
			_fill(vb, 7, 8, 1, 2, 2, 2, Color(0.4, 0.7, 0.4))
			vb.set_v(Vector3i(7, 4, 2), Color(0.9, 0.4, 0.5))
			origin = Vector3(5, 7, 0)
			size = 0.035
		"brush":
			_fill(vb, 0, 0, 2, 11, 0, 0, Color(0.85, 0.65, 0.35))
			_fill(vb, 0, 0, 1, 1, 0, 0, Color(0.8, 0.8, 0.82))
			_fill(vb, 0, 0, 0, 0, 0, 0, Color(0.3, 0.55, 0.95))
			vb.set_v(Vector3i(0, -1, 0), Color(0.95, 0.35, 0.45))
			origin = Vector3(0.5, 9, 0.5)
			size = 0.034
		"palette":
			_fill(vb, 0, 6, 0, 4, 0, 0, Color(0.78, 0.6, 0.38))
			vb.erase(Vector3i(0, 0, 0))
			vb.erase(Vector3i(6, 4, 0))
			vb.set_v(Vector3i(1, 3, 1), Color(0.95, 0.3, 0.3))
			vb.set_v(Vector3i(3, 3, 1), Color(0.98, 0.85, 0.3))
			vb.set_v(Vector3i(5, 2, 1), Color(0.3, 0.6, 0.95))
			vb.set_v(Vector3i(2, 1, 1), Color(0.4, 0.8, 0.4))
			vb.set_v(Vector3i(4, 1, 1), Color(0.95, 0.55, 0.8))
			origin = Vector3(3.5, 2.5, 0)
		"spatula":
			_fill(vb, 0, 0, 3, 10, 0, 0, Color(0.15, 0.15, 0.15))
			_fill(vb, -1, 1, 0, 2, 0, 0, Color(0.75, 0.75, 0.78))
			origin = Vector3(0.5, 8, 0.5)
		"toothbrush":
			_fill(vb, 0, 0, 0, 6, 0, 0, Color(0.35, 0.65, 0.95))
			_fill(vb, 0, 0, 5, 6, 1, 1, Color(0.98, 0.98, 0.98))
			origin = Vector3(0.5, 1, 0.5)
			size = 0.022
		"block":
			_fill(vb, 0, 2, 0, 2, 0, 2, Color(0.95, 0.35, 0.3))
			vb.set_v(Vector3i(1, 3, 1), Color(0.95, 0.35, 0.3))
			origin = Vector3(1.5, 1.5, 1.5)
		"bone":
			# Blue rubber chew bone (dog toy), lies along x.
			var bl := Color(0.22, 0.52, 0.92)
			var bfn := func(p: Vector3i) -> Color:
				return _sh(bl, 1.0 + (_h(p, 40) - 0.5) * 0.14 + (0.08 if p.y >= 1 else 0.0))
			_fill(vb, 2, 9, 0, 1, 0, 1, bfn)
			for ex in [0, 10]:
				_fill(vb, ex, ex + 1, 0, 1, -1, 2, bfn)
				_fill(vb, ex, ex + 1, 2, 2, 0, 1, bfn)
			origin = Vector3(6, 1, 1)
			size = 0.04
		"robot":
			# Little toy robot the kids build (ref1 rug).
			var g := Color(0.88, 0.88, 0.9)
			_fill(vb, 0, 3, 0, 3, 0, 2, Color(0.25, 0.45, 0.85))
			_fill(vb, 1, 2, 4, 5, 0, 2, g)
			vb.set_v(Vector3i(1, 5, 3), Color(0.1, 0.1, 0.12))
			vb.set_v(Vector3i(2, 5, 3), Color(0.1, 0.1, 0.12))
			_fill(vb, 0, 0, -2, -1, 1, 1, Color(0.2, 0.2, 0.22))
			_fill(vb, 3, 3, -2, -1, 1, 1, Color(0.2, 0.2, 0.22))
			vb.set_v(Vector3i(1, 6, 1), Color(0.98, 0.8, 0.25))
			vb.set_v(Vector3i(1, 2, 3), Color(0.98, 0.8, 0.25))
			origin = Vector3(2, 2, 1.5)
		"mug":
			_fill(vb, 0, 2, 0, 3, 0, 2, Color(0.95, 0.93, 0.88))
			vb.set_v(Vector3i(1, 3, 1), Color(0.35, 0.2, 0.1))
			vb.set_v(Vector3i(3, 2, 1), Color(0.95, 0.93, 0.88))
			vb.set_v(Vector3i(3, 1, 1), Color(0.95, 0.93, 0.88))
			origin = Vector3(1.5, 2, 1.5)
	var m := vb.build(size, origin)
	_prop_cache[pname] = m
	return m
