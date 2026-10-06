extends RefCounted
## Fast mesher for static VoxelBuilder content (same look as VoxelBuilder.build:
## face shading, vertex AO, per-voxel jitter, glow surface) but:
##   * writes packed arrays + an index buffer directly (several times faster
##     than SurfaceTool, 4 verts per quad instead of 6),
##   * can skip faces pointing straight down (never seen by the game camera),
##   * can merge runs of identical coplanar faces (`merge`), which collapses
##     flat single-colour walls/floors into long strips. Only useful when the
##     builder's jitter is 0 (otherwise no two faces match).
## Use: Mesher.build(vb, voxel_size, origin, skip_down, merge) -> ArrayMesh

const N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const SHADE := [0.94, 0.94, 1.0, 0.72, 0.97, 0.88]
const AOV := [1.0, 0.82, 0.68, 0.55]
## Run axis used when merging, per face: +X/-X faces run along Z, +Y/-Y along X, +Z/-Z along X.
const RUN := [2, 2, 0, 0, 0, 0]


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
		# Flip the diagonal to avoid AO anisotropy (same rule as VoxelBuilder).
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


static func build(vb: VoxelBuilder, vs := 0.0625, origin := Vector3.ZERO, skip_down := true, merge := false) -> ArrayMesh:
	var vox: Dictionary = vb.vox
	var glow: Dictionary = vb.glow
	var jit: float = vb.jitter
	var solid := Surf.new()
	var lit := Surf.new()
	# For merging: key "fi|plane|row" -> Array of [run_coord, cols(4), p]
	var runs := {}
	for p: Vector3i in vox:
		var g := glow.has(p)
		var base: Color = vox[p]
		var j := (VoxelBuilder.hash3(p) - 0.5) * 2.0 * jit
		for fi in 6:
			if skip_down and fi == 3:
				continue
			var n: Vector3i = N[fi]
			if vox.has(p + n):
				continue
			var cs: Array = CORNERS[fi]
			var sh: float = SHADE[fi] * (1.0 + j)
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
			if merge and not g:
				var ra: int = RUN[fi]
				var rc := p.x if ra == 0 else p.z
				var plane := p.x if fi < 2 else (p.y if fi < 4 else p.z)
				var row := p.y if fi < 2 or fi >= 4 else p.z
				if fi >= 4:
					row = p.y
				var key := Vector3i(fi, plane, row)
				if not runs.has(key):
					runs[key] = []
				runs[key].append([rc, c0, c1, c2, c3, p])
				continue
			var pf := Vector3(p)
			var s := lit if g else solid
			s.quad((pf + cs[0] - origin) * vs, (pf + cs[1] - origin) * vs, (pf + cs[2] - origin) * vs, (pf + cs[3] - origin) * vs,
				Vector3(n), c0, c1, c2, c3)
	if merge:
		for key: Vector3i in runs:
			var lst: Array = runs[key]
			lst.sort_custom(func(a, b): return a[0] < b[0])
			var fi := key.x
			var n: Vector3i = N[fi]
			var cs: Array = CORNERS[fi]
			var ra: int = RUN[fi]
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
				# Corner positions: corners whose run-axis component is 0 come from the
				# first voxel, 1 from the last.
				var q: Array[Vector3] = []
				for ci in 4:
					var cc: Vector3 = cs[ci]
					var comp := cc.x if ra == 0 else cc.z
					q.append(((p1 if comp > 0.5 else p0) + cc - origin) * vs)
				solid.quad(q[0], q[1], q[2], q[3], Vector3(n), e[1], e[2], e[3], e[4])
				k = m + 1
	var mesh := ArrayMesh.new()
	for pair in [[solid, VoxelBuilder.solid_material()], [lit, VoxelBuilder.glow_material()]]:
		var s: Surf = pair[0]
		if s.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_INDEX] = s.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh
