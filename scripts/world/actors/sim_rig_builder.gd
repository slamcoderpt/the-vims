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
	"big": {"lw": 5, "shin": 6, "thigh": 6, "tw": 12, "td": 7, "th": 9, "aw": 3, "ua": 6, "fa": 6, "hw": 10, "hh": 10, "hd": 10},
	"slim": {"lw": 4, "shin": 6, "thigh": 6, "tw": 10, "td": 6, "th": 9, "aw": 3, "ua": 6, "fa": 6, "hw": 10, "hh": 10, "hd": 10},
	# Chibi child: head (with hat) ~40% of total height, about 1:1.5 head:body.
	"child": {"lw": 3, "shin": 4, "thigh": 4, "tw": 8, "td": 5, "th": 6, "aw": 2, "ua": 4, "fa": 3, "hw": 10, "hh": 9, "hd": 9},
}

static var _cache := {}
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
		mesh.surface_set_material(0, VoxelBuilder.solid_material())
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
		var u := p.z if (p.x == 0 or p.x == w - 1) else p.x + ox
		var vline := posmod(u, 4) == 1
		var hline := posmod(p.y, 4) == 2
		var thin := posmod(u, 4) == 3 or posmod(p.y, 4) == 0
		var c := base
		if vline and hline:
			c = _sh(dark, 0.8)
		elif vline or hline:
			c = dark.lerp(base, 0.25)
		elif thin:
			c = _sh(base, 0.86)
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
	var ear_y := float(neck) + hh + 2.0
	var ear_x := hw * 0.5 - 2.0
	if hat == "cat":
		ear_x = hw * 0.5 - 2.5
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
		top_extra = 9.0
	elif hat == "cat":
		top_extra = 6.0
	var meta := {
		"species": "human",
		"kind": "child" if child else "adult",
		"hip_y": hip_j * VS,
		"leg_half": lw * 0.5 * VS,
		"torso_half": td * 0.5 * VS,
		"head_h": (hh + 1 + top_extra) * VS,
		"height": (neck + 1 + hh + 2) * VS,
		"fore_len": fa * VS,
		"arm_x": ax * VS,
		"elderly": L.get("elderly", false),
	}
	return acc.finish(meta)


## Head local coords: x 0..hw-1, neck row y=0, head rows 1..hh, z 0..hd-1 (+z = face).
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
	var vb := VoxelBuilder.new()
	vb.jitter = 0.035
	var eyes := VoxelBuilder.new()
	eyes.jitter = 0.0
	var hair_fn := _hair_fn(hair)

	# Skull, slightly rounded.
	var skin_fn := func(p: Vector3i) -> Color:
		return _sh(skin, 1.0 + (_h(p, 2) - 0.5) * 0.04)
	_fill(vb, 0, W - 1, B, T, 0, F, skin_fn)
	for y in range(B, T + 1):
		vb.erase(Vector3i(0, y, 0))
		vb.erase(Vector3i(W - 1, y, 0))
		vb.erase(Vector3i(0, y, F))
		vb.erase(Vector3i(W - 1, y, F))
	for x in [0, W - 1]:
		for z in range(0, Dd):
			vb.erase(Vector3i(x, B, z))
	for x in range(0, W):
		vb.erase(Vector3i(x, B, 0))
	# Neck.
	_fill(vb, W / 2 - 2, W / 2 + 1, 0, 0, Dd / 2 - 2, Dd / 2 + 1, _sh(skin, 0.86))
	# Ears.
	var ear_skin := _sh(skin, 0.95)
	_fill(vb, -1, -1, B + 2, B + 3, Dd / 2 - 1, Dd / 2, ear_skin)
	_fill(vb, W, W, B + 2, B + 3, Dd / 2 - 1, Dd / 2, ear_skin)

	# Face.
	var eye_dark := Color(0.09, 0.06, 0.05)
	var eye_mid: Color = L.get("eye", Color(0.33, 0.19, 0.1))
	var white := Color(0.98, 0.98, 0.96)
	var lid := _sh(skin, 0.88)
	var lash := Color(0.18, 0.1, 0.08)
	var E := B + 2 if child else B + 3
	var eh := 3 if child else 2
	var exs := [2, 6]
	for ex: int in exs:
		for dx in 2:
			for dy in eh:
				var p := Vector3i(ex + dx, E + dy, F)
				vb.erase(p)
				vb.set_v(p - Vector3i(0, 0, 1), lash if dy == 0 else lid)
				var c := eye_dark
				if dy == eh - 1 and dx == 0:
					c = white
				elif dy == 0 and child:
					c = eye_mid
				elif dy == 0 and dx == 1:
					c = eye_mid.lerp(eye_dark, 0.4)
				eyes.set_v(p, c)
	if girl:
		vb.set_v(Vector3i(1, E + eh - 1, F), lash)
		vb.set_v(Vector3i(8, E + eh - 1, F), lash)
		if not child:
			vb.set_v(Vector3i(1, E + eh, F), lash)
			vb.set_v(Vector3i(8, E + eh, F), lash)
	# Mouth + cheeks + nose.
	var mouth := Color(0.62, 0.24, 0.24)
	if child:
		vb.set_v(Vector3i(4, B + 1, F), mouth)
		vb.set_v(Vector3i(5, B + 1, F), mouth)
		vb.set_v(Vector3i(3, B + 2, F), _sh(skin, 0.9))
		var blush := skin.lerp(Color(0.98, 0.45, 0.5), 0.55)
		for x in [1, 2, 7, 8]:
			vb.set_v(Vector3i(x, B + 1, F), blush)
		vb.set_v(Vector3i(4, B + 2, F), _sh(skin, 0.93))
		vb.set_v(Vector3i(5, B + 2, F), _sh(skin, 0.93))
	else:
		vb.set_v(Vector3i(4, B + 1, F), mouth)
		vb.set_v(Vector3i(5, B + 1, F), mouth)
		vb.set_v(Vector3i(4, B + 2, F + 1), _sh(skin, 0.92))
		vb.set_v(Vector3i(5, B + 2, F + 1), _sh(skin, 0.92))
		if girl:
			var blush2 := skin.lerp(Color(0.95, 0.45, 0.45), 0.35)
			vb.set_v(Vector3i(1, B + 2, F), blush2)
			vb.set_v(Vector3i(8, B + 2, F), blush2)
			vb.set_v(Vector3i(4, B + 1, F), Color(0.75, 0.3, 0.32))
			vb.set_v(Vector3i(5, B + 1, F), Color(0.75, 0.3, 0.32))
		# Brows.
		var brow: Color = L.get("brow", _sh(hair, 0.8))
		for x in [1, 2, 3, 6, 7, 8]:
			if girl and (x == 1 or x == 8):
				continue
			vb.set_v(Vector3i(x, E + eh + 1, F), brow)

	# Beard.
	var beard: String = L.get("beard", "")
	var bc := _hair_fn(_sh(hair, 0.8))
	if beard == "full":
		for y in range(B, B + 3):
			for x in range(0, W):
				if y == B + 1 and (x == 4 or x == 5):
					continue
				vb.set_v(Vector3i(x, y, F), bc.call(Vector3i(x, y, F)))
				if x > 0 and x < W - 1:
					vb.set_v(Vector3i(x, y, F + 1), bc.call(Vector3i(x, y, F + 1)))
		# Mouth recessed in beard.
		vb.set_v(Vector3i(4, B + 1, F), mouth)
		vb.set_v(Vector3i(5, B + 1, F), mouth)
		vb.erase(Vector3i(4, B + 1, F + 1))
		vb.erase(Vector3i(5, B + 1, F + 1))
		# Moustache over the lip, nose on top.
		for x in range(2, 8):
			vb.set_v(Vector3i(x, B + 2, F + 1), bc.call(Vector3i(x, B + 2, F + 2)))
		vb.set_v(Vector3i(4, B + 3, F + 1), _sh(skin, 0.9))
		vb.set_v(Vector3i(5, B + 3, F + 1), _sh(skin, 0.9))
		# Jaw / chin volume.
		_fill(vb, 1, W - 2, 0, 0, 3, F + 1, bc)
		_fill(vb, 2, W - 3, -1, -1, 5, F + 1, bc)
		_fill(vb, 3, W - 4, -2, -2, 7, F, bc)
		# Sideburns + cheeks.
		for x in [0, W - 1]:
			for y in range(B, B + 6):
				for z in range(5, F + 1):
					vb.set_v(Vector3i(x, y, z), bc.call(Vector3i(x, y, z)))
		for x in [-1, W]:
			for y in range(B + 1, B + 4):
				for z in range(6, F):
					vb.set_v(Vector3i(x, y, z), bc.call(Vector3i(x, y, z)))
	elif beard == "short":
		for y in range(B, B + 2):
			for x in range(0, W):
				if y == B + 1 and (x == 4 or x == 5):
					continue
				vb.set_v(Vector3i(x, y, F), bc.call(Vector3i(x, y, F)))
		for x in range(3, 7):
			vb.set_v(Vector3i(x, B + 2, F), bc.call(Vector3i(x, B + 2, F)))
		_fill(vb, 2, W - 3, 0, 0, 5, F, bc)
		for x in [0, W - 1]:
			_fill(vb, x, x, B, B + 3, 5, F - 1, bc)
	elif beard == "moustache":
		for x in range(2, 8):
			vb.set_v(Vector3i(x, B + 2, F + 1), bc.call(Vector3i(x, B + 2, F + 1)))
		vb.set_v(Vector3i(2, B + 1, F + 1), bc.call(Vector3i(2, B + 1, F + 1)))
		vb.set_v(Vector3i(7, B + 1, F + 1), bc.call(Vector3i(7, B + 1, F + 1)))

	_human_hair(vb, style, hair_fn, W, H, Dd, B, T, F, hat != "", child)
	# Sun-kissed crown: hair on top catches a little more light.
	if hat == "":
		for p: Vector3i in vb.vox.keys():
			if p.y >= T + 1:
				vb.vox[p] = _sh(vb.vox[p], 1.08)
	var out := {"head": vb, "eyes": eyes}
	if hat != "":
		_human_hat(vb, L, W, H, Dd, B, T, F, out)
	if L.get("glasses", false):
		# Thin warm-gold rims; the lens area stays open so the eyes read.
		var gc := Color(0.5, 0.36, 0.24)
		for ex: int in exs:
			for x in range(ex - 1, ex + 3):
				vb.set_v(Vector3i(x, E + eh, F + 1), gc)
			for y in range(E, E + eh):
				vb.set_v(Vector3i(ex - 1, y, F + 1), gc)
				vb.set_v(Vector3i(ex + 2, y, F + 1), gc)
		# Bridge.
		vb.set_v(Vector3i(W / 2 - 1, E + eh - 1, F + 1), gc)
		vb.set_v(Vector3i(W / 2, E + eh - 1, F + 1), gc)
		for z in range(F - 4, F + 1):
			vb.set_v(Vector3i(-1, E + 1, z), gc)
			vb.set_v(Vector3i(W, E + 1, z), gc)
	return out


static func _human_hair(vb: VoxelBuilder, style: String, hc: Callable, W: int, H: int, Dd: int, B: int, T: int, F: int, has_hat: bool, child := false) -> void:
	if style == "bald":
		_fill(vb, -1, -1, B + 3, T - 3, 1, F - 4, hc)
		_fill(vb, W, W, B + 3, T - 3, 1, F - 4, hc)
		_fill(vb, 0, W - 1, B + 2, T - 3, -1, -1, hc)
		return
	if style == "shaggy":
		# Big wavy mop (dad): curly shell + clumpy tufts and a swept fringe.
		var clump := func(p: Vector3i) -> Color:
			var c: Color = hc.call(p)
			var k := _h(Vector3i(floori(p.x / 2.0), floori(p.y / 2.0), floori(p.z / 2.0)), 41)
			return _sh(c, 0.84 + 0.3 * k)
		for x in range(-2, W + 2):
			for z in range(-2, F + 1):
				for y in range(B + 1, T + 4):
					var inside_head := x >= 0 and x < W and z >= 0 and z <= F and y <= T
					if inside_head:
						continue
					# Low rows: only the back of the head / behind the ears.
					if y < T - 5 and z > 2:
						continue
					if z >= F - 1 and y < T - 1 and (x >= 0 and x < W):
						continue
					if z >= F - 2 and y < T - 3:
						continue
					# Keep the ear + cheek clear on the sides so the face reads
					# in profile (hair only behind the ear / above the temple).
					var side := x < 0 or x >= W
					if side and z >= 4 and y < T - 2:
						continue
					var dx := maxf(maxf(-x, x - (W - 1)), 0.0)
					var dz := maxf(maxf(-z, z - F), 0.0)
					var dy := maxf(float(y - T), 0.0)
					var lim := 1.6 + _h(Vector3i(x, y, z), 42) * 1.1
					if dy > 0.0:
						lim = 2.2 + _h(Vector3i(x, 0, z), 43) * 1.3
					if dx + dz + dy * 0.9 <= lim:
						vb.set_v(Vector3i(x, y, z), clump.call(Vector3i(x, y, z)))
		# Fringe swept to one side over the forehead.
		for x in range(0, W):
			vb.set_v(Vector3i(x, T, F + 1), clump.call(Vector3i(x, T, F + 1)))
			if x < W - 3 and _h(Vector3i(x, 2, 2), 44) > 0.25:
				vb.set_v(Vector3i(x, T - 1, F + 1), clump.call(Vector3i(x, T - 1, F + 1)))
			vb.set_v(Vector3i(x, T, F), clump.call(Vector3i(x, T, F)))
			if x < W - 4:
				vb.set_v(Vector3i(x, T - 1, F), clump.call(Vector3i(x, T - 1, F)))
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
			var low := (-3 if child else -5) if style != "bun" and style != "ponytail" else B + 1
			if style == "long" or style == "curly_long":
				# Curtains framing the face down past the chin, ragged ends.
				for z in range(0, F):
					for x in [-1, W]:
						var end := low + 1 + int(_h(Vector3i(x, 0, z), 14) * 2.5) + (1 if z > F - 4 else 0)
						for y in range(end, T + 1):
							if y < B + 4 and z > F - 2:
								continue
							vb.set_v(Vector3i(x, y, z), hc.call(Vector3i(x, y, z)))
					# Outer wave of volume (tucked in under hats).
					if z >= 1 and z <= F - 3 and not has_hat:
						for y in range(low + 3, T - 2):
							vb.set_v(Vector3i(-2, y, z), hc.call(Vector3i(-2, y, z)))
							vb.set_v(Vector3i(W + 1, y, z), hc.call(Vector3i(W + 1, y, z)))
				# Back: long hair falling in uneven locks (alternating lengths,
				# darker gaps between locks), slightly tapered, only 2 deep.
				var cx := (W - 1) * 0.5
				var lock_fn := func(p: Vector3i) -> Color:
					var c: Color = hc.call(p)
					var lock := posmod(p.x + 1, 3) == 0
					return _sh(c, 0.82 if lock else 1.0)
				for x in range(-1, W + 1):
					var taper := int(absf(x - cx) * 0.3)
					var lk := int(floor((x + 1) / 3.0))
					var end := low + taper + int(_h(Vector3i(lk, 0, 0), 15) * 2.5) + (1 if posmod(x + 1, 3) == 0 else 0)
					for y in range(end, T + 1):
						vb.set_v(Vector3i(x, y, -1), lock_fn.call(Vector3i(x, y, -1)))
					if x >= 0 and x < W:
						for y in range(end + 2, T - 1):
							vb.set_v(Vector3i(x, y, -2), lock_fn.call(Vector3i(x, y, -2)))
					# Curl at the tip of every other lock.
					if posmod(lk, 2) == 0 and x >= 0 and x < W:
						vb.set_v(Vector3i(x, end, -2), lock_fn.call(Vector3i(x, end, -2)))
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
		# Snug beanie that sits ON the head: ribbed cuff just above the brows,
		# shell hugging the skull one voxel out, rounded dome on top. The face
		# stays fully exposed below the cuff.
		var cuff_c: Color = L.get("cuff_color", _sh(hc, 1.06))
		for y in range(T - 1, T + 1):
			for x in range(-1, W + 1):
				for z in range(-1, F + 2):
					var shell := x == -1 or x == W or z == -1 or z == F + 1
					if not shell:
						continue
					if (x == -1 or x == W) and (z == -1 or z == F + 1):
						continue
					var p := Vector3i(x, y, z)
					if y <= T - 1:
						var u := z if (x == -1 or x == W) else x
						vb.set_v(p, _sh(cuff_c, 0.93 if posmod(u, 2) == 0 else 1.02))
					else:
						vb.set_v(p, knit.call(p))
		# Top layer (inset by the shell) + dome.
		_fill(vb, 0, W - 1, T + 1, T + 1, 0, F, knit)
		for x in [0, W - 1]:
			for z in [0, F]:
				vb.erase(Vector3i(x, T + 1, z))
		_fill(vb, 1, W - 2, T + 2, T + 2, 1, F - 1, knit)
		for x in [1, W - 2]:
			for z in [1, F - 1]:
				vb.erase(Vector3i(x, T + 2, z))
		# Hair can't poke through the hat: clear anything above the cuff
		# outside the hat volume.
		for y in range(T - 1, T + 6):
			for x in range(-3, W + 3):
				for z in range(-4, F + 3):
					var inside := x >= -1 and x <= W and z >= -1 and z <= F + 1 and y <= T
					if y == T + 1:
						inside = x >= 0 and x < W and z >= 0 and z <= F
					elif y == T + 2:
						inside = x >= 1 and x < W - 1 and z >= 1 and z < F
					elif y > T + 2:
						inside = false
					if not inside:
						vb.erase(Vector3i(x, y, z))
		if hat == "cat":
			# Stitched cat face on the front of the hat: two eyes + nose.
			# Stitched seam dots near the front corners (like the ref hat).
			var st := _sh(hc, 0.6)
			vb.set_v(Vector3i(1, T, F + 1), st)
			vb.set_v(Vector3i(W - 2, T, F + 1), st)
		# Ears on their own bones.
		var outer: Color = L.get("ear_color", hc)
		var inner: Color = L.get("ear_inner", Color(0.95, 0.55, 0.65))
		var el := VoxelBuilder.new()
		el.jitter = 0.03
		if hat == "bunny":
			# 4 wide, 9 tall, 2 deep; pink inner on the front, rounded tip.
			for y in range(0, 9):
				for x in range(0, 4):
					for z in range(0, 2):
						if y == 8 and (x == 0 or x == 3):
							continue
						if y == 0 and (x == 0 or x == 3):
							continue
						var c := outer
						if z == 1 and (x == 1 or x == 2) and y >= 1 and y <= 7:
							c = inner if y < 7 else inner.lerp(outer, 0.5)
						el.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 22) - 0.5) * 0.06))
			out["ear_origin"] = Vector3(2.0, 0.5, 1.0)
		else:
			# Round teddy/cat ears: 5 wide, 5 tall, pink inner on the front.
			for y in range(0, 5):
				var x0 := 0
				var x1 := 4
				if y == 4:
					x0 = 1; x1 = 3
				for x in range(x0, x1 + 1):
					for z in range(0, 2):
						var c := outer
						if z == 1 and y >= 1 and y <= 3 and x >= 1 and x <= 3 and not (y == 3 and x != 2):
							c = inner
						el.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 24) - 0.5) * 0.06))
			out["ear_origin"] = Vector3(2.5, 0.5, 1.0)
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
		if hat == "cap":
			vb.set_v(Vector3i(W / 2, T + 3, F / 2), _sh(hc, 0.8))


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

static func _build_dog(L: Dictionary) -> Dictionary:
	# Chibi beagle: big round head with a white blaze and muzzle, long brown
	# floppy ears, tan body with a darker saddle, white chest/belly/socks and
	# a white-tipped tail that stands up.
	var acc := Acc.new()
	acc.vs = VS
	var tan: Color = L.get("tan", Color(0.80, 0.47, 0.2))
	var saddle: Color = L.get("saddle", Color(0.42, 0.25, 0.13))
	var white: Color = L.get("white", Color(0.97, 0.95, 0.9))
	var earc: Color = L.get("ear", Color(0.6, 0.33, 0.14))
	var collar: Color = L.get("collar", Color(0.85, 0.18, 0.18))
	const LEG := 4
	const BW := 7
	const BH := 6
	const BL := 13
	const HW := 9
	const HH := 8
	const HD := 7
	var head_j := Vector3(0, LEG + BH - 2, BL * 0.5 - 1.5)
	var h_origin := Vector3(HW * 0.5, 1.0, 1.0)
	# Eye rows 4..5 (local), joint between them, on the face plane.
	var eye_d := Vector3(0, 3.5, HD - 1.0)
	acc.bone("root", "", Vector3.ZERO)
	acc.bone("body", "root", Vector3(0, LEG, 0))
	acc.bone("head", "body", head_j)
	acc.bone("eyes", "head", head_j + eye_d)
	var ear_d := Vector3(HW * 0.5 + 0.5, HH - 2.0, 2.5)
	acc.bone("ear_l", "head", head_j + Vector3(ear_d.x, ear_d.y, ear_d.z))
	acc.bone("ear_r", "head", head_j + Vector3(-ear_d.x, ear_d.y, ear_d.z))
	acc.bone("tail", "body", Vector3(0, LEG + BH - 1.5, -BL * 0.5 + 1.0))
	acc.bone("leg_fl", "body", Vector3(2.0, LEG, BL * 0.5 - 2.5))
	acc.bone("leg_fr", "body", Vector3(-2.0, LEG, BL * 0.5 - 2.5))
	acc.bone("leg_bl", "body", Vector3(2.0, LEG, -BL * 0.5 + 2.5))
	acc.bone("leg_br", "body", Vector3(-2.0, LEG, -BL * 0.5 + 2.5))

	# Body: x 0..BW-1, y 0..BH-1, z 0..BL-1 (front = +z).
	var body := VoxelBuilder.new()
	body.jitter = 0.05
	var body_fn := func(p: Vector3i) -> Color:
		var c := tan
		var cx := absf(p.x - (BW - 1) * 0.5)
		if p.y <= 1 or (p.z >= BL - 3 and p.y <= 3 and cx < 2.6):
			c = white
		elif p.y >= BH - 2 and p.z >= 2 and p.z <= BL - 4 and _h(Vector3i(p.x, 0, p.z), 30) > 0.18:
			c = saddle if p.y == BH - 1 or cx < 3.0 else tan
		elif p.y == 2 and _h(p, 31) > 0.55:
			c = white.lerp(tan, 0.35)
		return _sh(c, 1.0 + (_h(p, 32) - 0.5) * 0.12)
	_fill(body, 0, BW - 1, 0, BH - 1, 0, BL - 1, body_fn)
	for z in range(0, BL):
		for x in [0, BW - 1]:
			body.erase(Vector3i(x, BH - 1, z))
			body.erase(Vector3i(x, 0, z))
	for x in range(0, BW):
		for z in [0, BL - 1]:
			body.erase(Vector3i(x, BH - 1, z))
			body.erase(Vector3i(x, 0, z))
	for y in range(0, BH):
		for x in [0, BW - 1]:
			body.erase(Vector3i(x, y, 0))
	# Haunches: rounded bumps over the back legs.
	for sx in [-1, BW]:
		_fill(body, sx, sx, 1, 3, 1, 4, func(p: Vector3i) -> Color:
			return _sh(tan, 0.97 + (_h(p, 38) - 0.5) * 0.1))
	# Chest tuft.
	_fill(body, 2, BW - 3, 1, 3, BL, BL, white)
	acc.part("body", body, Vector3(BW * 0.5, 0, BL * 0.5))

	# Head: x 0..HW-1, y 0..HH-1, z 0..HD-1, + muzzle in front.
	var head := VoxelBuilder.new()
	head.jitter = 0.04
	var mid := (HW - 1) / 2   # 4
	var head_fn := func(p: Vector3i) -> Color:
		var c := tan
		var dx := absi(p.x - mid)
		# Blaze: thin stripe up the forehead, widening down the face.
		if dx == 0 and p.y >= 2:
			c = white
		elif dx == 1 and p.y <= 3 and p.z >= HD - 3:
			c = white
		elif p.y <= 1 and p.z >= HD - 3 and dx <= 3:
			c = white
		elif p.y <= 0:
			c = white
		elif p.y >= HH - 1 and dx <= 1:
			c = white
		if c == tan and p.y >= HH - 2 and dx >= 2:
			c = _sh(tan, 0.92)
		return _sh(c, 1.0 + (_h(p, 33) - 0.5) * 0.1)
	_fill(head, 0, HW - 1, 0, HH - 1, 0, HD - 1, head_fn)
	# Round the skull.
	for y in range(0, HH):
		for x in [0, HW - 1]:
			head.erase(Vector3i(x, y, 0))
	for x in [0, HW - 1]:
		for z in range(0, HD):
			head.erase(Vector3i(x, HH - 1, z))
			head.erase(Vector3i(x, 0, z))
	for x in range(0, HW):
		head.erase(Vector3i(x, HH - 1, 0))
	head.erase(Vector3i(0, HH - 2, HD - 1))
	head.erase(Vector3i(HW - 1, HH - 2, HD - 1))
	# Muzzle: white, 5 wide, 3 tall, sticking out 2.
	var muz := func(p: Vector3i) -> Color:
		return _sh(white, 0.98 + (_h(p, 34) - 0.5) * 0.06)
	_fill(head, mid - 2, mid + 2, 0, 2, HD, HD + 1, muz)
	_fill(head, mid - 1, mid + 1, 3, 3, HD, HD, muz)
	head.erase(Vector3i(mid - 2, 2, HD + 1))
	head.erase(Vector3i(mid + 2, 2, HD + 1))
	# Big black nose on top of the muzzle tip, with a shine.
	var nose := Color(0.1, 0.07, 0.07)
	_fill(head, mid - 1, mid + 1, 2, 3, HD + 1, HD + 1, nose)
	head.set_v(Vector3i(mid, 2, HD + 2), nose)
	head.set_v(Vector3i(mid - 1, 3, HD + 2), Color(0.32, 0.3, 0.32))
	head.set_v(Vector3i(mid, 3, HD + 2), nose)
	# Mouth line + tongue.
	head.set_v(Vector3i(mid - 1, 1, HD + 2), Color(0.3, 0.16, 0.14))
	head.set_v(Vector3i(mid + 1, 1, HD + 2), Color(0.3, 0.16, 0.14))
	head.set_v(Vector3i(mid, 0, HD + 2), Color(0.92, 0.45, 0.52))
	head.set_v(Vector3i(mid, -1, HD + 1), Color(0.92, 0.45, 0.52))
	# Eyes (own bone so they can blink): 1 wide x 2 tall, glint on top.
	var eyes := VoxelBuilder.new()
	eyes.jitter = 0.0
	for ex in [mid - 2, mid + 2]:
		for ey in [4, 5]:
			var p := Vector3i(ex, ey, HD - 1)
			head.erase(p)
			head.set_v(p - Vector3i(0, 0, 1), Color(0.14, 0.09, 0.07))
			eyes.set_v(p, Color(0.97, 0.97, 0.95) if ey == 5 and ex == mid - 2 else Color(0.07, 0.05, 0.04))
		# Brow ridge.
		head.set_v(Vector3i(ex, 6, HD - 1), _sh(tan, 0.78))
	# Lids / eye whites when blinking are just the socket colour.
	# Collar.
	for x in range(0, HW):
		for z in range(0, HD - 1):
			if x == 0 or x == HW - 1 or z == 0 or z == HD - 2:
				head.set_v(Vector3i(x, -1, z), collar)
	head.set_v(Vector3i(mid, -2, HD - 1), Color(0.98, 0.82, 0.3))
	head.set_v(Vector3i(mid, -1, HD - 1), Color(0.98, 0.82, 0.3))
	acc.part("head", head, h_origin)
	acc.part("eyes", eyes, h_origin + eye_d)

	# Long floppy ears hanging down the sides of the head past the jaw.
	var ear := VoxelBuilder.new()
	ear.jitter = 0.05
	for y in range(-7, 1):
		for z in range(0, 5):
			if y <= -6 and (z == 0 or z == 4):
				continue
			if y == -7 and z == 1:
				continue
			if y == 0 and (z == 0 or z == 4):
				continue
			for x in range(0, 2):
				if x == 1 and y <= -5:
					continue
				var c := earc
				if y >= -1:
					c = tan
				elif y <= -6:
					c = _sh(earc, 0.82)
				ear.set_v(Vector3i(x, y, z), _sh(c, 1.0 + (_h(Vector3i(x, y, z), 36) - 0.5) * 0.12))
	acc.part("ear_l", ear, Vector3(0.5, 0.5, 2.5))
	var ear_r := VoxelBuilder.new()
	ear_r.jitter = 0.05
	for p: Vector3i in ear.vox:
		ear_r.set_v(Vector3i(1 - p.x, p.y, p.z), ear.vox[p])
	acc.part("ear_r", ear_r, Vector3(1.5, 0.5, 2.5))

	# Tail: stands up with a slight curl, white tip.
	var tail := VoxelBuilder.new()
	tail.jitter = 0.05
	for y in range(0, 7):
		var c := white if y >= 5 else (_sh(saddle, 1.1) if y < 2 else tan)
		var zz := 0 if y < 4 else -1
		_fill(tail, 0, 1, y, y, zz, zz + 1, _sh(c, 1.0 + (_h(Vector3i(0, y, 0), 39) - 0.5) * 0.1))
	acc.part("tail", tail, Vector3(1, 0, 1))

	# Legs: 3 x LEG x 3 with white socks and a toe row.
	for nm in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
		var leg := VoxelBuilder.new()
		leg.jitter = 0.05
		var front: bool = nm.begins_with("leg_f")
		_fill(leg, 0, 2, 0, LEG, 0, 2, func(p: Vector3i) -> Color:
			var c := white
			if not front and p.y >= 2:
				c = tan
			elif front and p.y >= LEG - 1:
				c = white.lerp(tan, 0.3)
			return _sh(c, 1.0 + (_h(p, 37) - 0.5) * 0.08))
		_fill(leg, 0, 2, 0, 0, 3, 3, _sh(white, 0.95))
		leg.set_v(Vector3i(1, 0, 3), _sh(white, 0.86))
		acc.part(nm, leg, Vector3(1.5, LEG + 0.5, 1.5))

	var meta := {
		"species": "dog", "kind": "dog",
		"height": (LEG + BH - 2 + HH) * VS,
		"head_h": (HH - 1) * VS,
		"leg": LEG * VS,
		"mouth": Vector3(0, -0.5, HD + 1.5 - h_origin.z) * VS,
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
			origin = Vector3(0.5, 9, 0.5)
			size = 0.025
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
