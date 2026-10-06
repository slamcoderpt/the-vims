extends VoxelBuilder
## VoxelBuilder with two mobile-friendly extras (same look, fewer triangles):
##  * greedy merging of coplanar faces whose four corner colours match
##    (flat walls / boards / roofs with jitter 0 collapse to a few quads),
##  * `skip_normals`: face directions that can never be seen (e.g. the
##    inside of a wall, or bottoms resting on the ground).

## Face directions to drop entirely.
var skip_normals: Array[Vector3i] = []
## Drop downward faces whose voxel sits at or below this grid y (ground contact).
var skip_down_below := -1000000


func build(voxel_size := 0.0625, origin := Vector3.ZERO, ao := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for g in [false, true]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for fi in 6:
			var n: Vector3i = FACES[fi][0]
			if skip_normals.has(n):
				continue
			var corners: Array = FACES[fi][1]
			var shade: float = FACE_SHADE[fi]
			# slices[layer] -> {Vector2i(u,v): Color}
			var slices := {}
			for p: Vector3i in vox:
				if glow.has(p) != g:
					continue
				if vox.has(p + n):
					continue
				if n.y < 0 and p.y <= skip_down_below:
					continue
				var base: Color = vox[p]
				var j := (hash3(p) - 0.5) * 2.0 * jitter
				var cols: Array[Color] = []
				var uniform := true
				for k in 4:
					var a := _ao(p, n, corners[k]) if (ao and not g) else 1.0
					var f := shade * a * (1.0 + j)
					cols.append(Color(base.r * f, base.g * f, base.b * f, 1.0))
					if k > 0 and not cols[k].is_equal_approx(cols[0]):
						uniform = false
				if uniform:
					var layer := _layer(p, n)
					if not slices.has(layer):
						slices[layer] = {}
					slices[layer][_uv(p, n)] = cols[0]
				else:
					_emit(st, Vector3(p), Vector3.ONE, n, corners, cols, voxel_size, origin)
					count += 1
			for layer in slices:
				count += _greedy(st, slices[layer], layer, n, corners, voxel_size, origin)
		if count == 0:
			continue
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_material() if g else solid_material())
	return mesh


static func _layer(p: Vector3i, n: Vector3i) -> int:
	return p.x if n.x != 0 else (p.y if n.y != 0 else p.z)


static func _uv(p: Vector3i, n: Vector3i) -> Vector2i:
	if n.x != 0:
		return Vector2i(p.z, p.y)
	if n.y != 0:
		return Vector2i(p.x, p.z)
	return Vector2i(p.x, p.y)


static func _from_uv(uv: Vector2i, layer: int, n: Vector3i) -> Vector3:
	if n.x != 0:
		return Vector3(layer, uv.y, uv.x)
	if n.y != 0:
		return Vector3(uv.x, layer, uv.y)
	return Vector3(uv.x, uv.y, layer)


static func _ext(du: int, dv: int, n: Vector3i) -> Vector3:
	if n.x != 0:
		return Vector3(1, dv, du)
	if n.y != 0:
		return Vector3(du, 1, dv)
	return Vector3(du, dv, 1)


func _greedy(st: SurfaceTool, cells: Dictionary, layer: int, n: Vector3i, corners: Array, vs: float, origin: Vector3) -> int:
	var count := 0
	var done := {}
	for uv: Vector2i in cells:
		if done.has(uv):
			continue
		var c: Color = cells[uv]
		# Grow along u.
		var du := 1
		while true:
			var nx := uv + Vector2i(du, 0)
			if done.has(nx) or not cells.has(nx) or not (cells[nx] as Color).is_equal_approx(c):
				break
			du += 1
		# Grow along v while the whole row matches.
		var dv := 1
		var grow := true
		while grow:
			for k in du:
				var nx := uv + Vector2i(k, dv)
				if done.has(nx) or not cells.has(nx) or not (cells[nx] as Color).is_equal_approx(c):
					grow = false
					break
			if grow:
				dv += 1
		for a in du:
			for b in dv:
				done[uv + Vector2i(a, b)] = true
		var cols: Array[Color] = [c, c, c, c]
		_emit(st, _from_uv(uv, layer, n), _ext(du, dv, n), n, corners, cols, vs, origin)
		count += 1
	return count


static func _emit(st: SurfaceTool, base: Vector3, ext: Vector3, n: Vector3i, corners: Array, cols: Array[Color], vs: float, origin: Vector3) -> void:
	var verts: Array[Vector3] = []
	for k in 4:
		var c: Vector3 = corners[k]
		verts.append((base + Vector3(c.x * ext.x, c.y * ext.y, c.z * ext.z) - origin) * vs)
	var nn := Vector3(n)
	var order := [0, 2, 1, 0, 3, 2]
	if cols[0].get_luminance() + cols[2].get_luminance() < cols[1].get_luminance() + cols[3].get_luminance():
		order = [1, 3, 2, 1, 0, 3]
	for idx in order:
		st.set_normal(nn)
		st.set_color(cols[idx])
		st.add_vertex(verts[idx])
