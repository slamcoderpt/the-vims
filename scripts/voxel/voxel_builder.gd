class_name VoxelBuilder
extends RefCounted
## Accumulates coloured voxels and bakes them into a single ArrayMesh with
## hidden-face culling, per-vertex ambient occlusion and subtle per-voxel
## colour jitter (the "hand placed blocks" look of the reference art).
##
## Voxels flagged emissive go to a second surface that glows (lamps, windows,
## screens, string lights).
##
## Coordinates are integer grid cells; `build(voxel_size)` converts to metres.

const FACES := [
	# normal, 4 corner offsets (counter-clockwise seen from outside)
	[Vector3i(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]],
	[Vector3i(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
	[Vector3i(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]],
	[Vector3i(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
]
# Directional face tint so un-lit voxel faces still read as 3D blocks.
const FACE_SHADE := [0.94, 0.94, 1.0, 0.72, 0.97, 0.88]

static var _mat_solid: StandardMaterial3D
static var _mat_glow: StandardMaterial3D

var vox := {}   # Vector3i -> Color
var glow := {}  # Vector3i -> true
## Max random brightness variation per voxel (0..1). 0.06 reads as "crafted".
var jitter := 0.05


func set_v(p: Vector3i, c: Color, emissive := false) -> void:
	vox[p] = c
	if emissive:
		glow[p] = true
	else:
		glow.erase(p)


func erase(p: Vector3i) -> void:
	vox.erase(p)
	glow.erase(p)


func has(p: Vector3i) -> bool:
	return vox.has(p)


## Fill an axis-aligned box. `c` may be a Color or a Callable(p: Vector3i) -> Color
## (return Color(0,0,0,0) to leave a cell empty).
func box(from: Vector3i, size: Vector3i, c, emissive := false) -> void:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				var p := from + Vector3i(x, y, z)
				var col: Color = c.call(p) if c is Callable else c
				if col.a <= 0.0:
					continue
				set_v(p, col, emissive)


func clear_box(from: Vector3i, size: Vector3i) -> void:
	for x in size.x:
		for y in size.y:
			for z in size.z:
				erase(from + Vector3i(x, y, z))


## Hollow box shell (walls/frames).
func frame(from: Vector3i, size: Vector3i, c, thickness := 1, emissive := false) -> void:
	box(from, size, c, emissive)
	var t := thickness
	if size.x > 2 * t and size.y > 2 * t and size.z > 2 * t:
		clear_box(from + Vector3i(t, t, t), size - Vector3i(2 * t, 2 * t, 2 * t))


## Copy another builder's voxels in at an offset.
func stamp(other: VoxelBuilder, offset: Vector3i) -> void:
	for p in other.vox:
		set_v(p + offset, other.vox[p], other.glow.has(p))


static func hash3(p: Vector3i) -> float:
	var h := (p.x * 73856093) ^ (p.y * 19349663) ^ (p.z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


func _ao(p: Vector3i, n: Vector3i, corner: Vector3) -> float:
	# Vertex AO from the three cells touching this vertex on the face's outer side.
	var ax: Vector3i
	var bx: Vector3i
	var c := Vector3i(int(corner.x * 2 - 1), int(corner.y * 2 - 1), int(corner.z * 2 - 1))
	if n.x != 0:
		ax = Vector3i(0, c.y, 0); bx = Vector3i(0, 0, c.z)
	elif n.y != 0:
		ax = Vector3i(c.x, 0, 0); bx = Vector3i(0, 0, c.z)
	else:
		ax = Vector3i(c.x, 0, 0); bx = Vector3i(0, c.y, 0)
	var o := p + n
	var s1 := vox.has(o + ax)
	var s2 := vox.has(o + bx)
	var cr := vox.has(o + ax + bx)
	var occ := 3 if (s1 and s2) else int(s1) + int(s2) + int(cr)
	return [1.0, 0.82, 0.68, 0.55][occ]


## Bake to an ArrayMesh. `origin` is subtracted (in voxel units) before scaling,
## so e.g. origin = Vector3(w/2, 0, d/2) centres a model on its footprint.
func build(voxel_size := 0.0625, origin := Vector3.ZERO, ao := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var groups := [false, true]
	for g in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for p: Vector3i in vox:
			if glow.has(p) != g:
				continue
			var base: Color = vox[p]
			var j := (hash3(p) - 0.5) * 2.0 * jitter
			for fi in 6:
				var n: Vector3i = FACES[fi][0]
				if vox.has(p + n):
					continue
				var corners: Array = FACES[fi][1]
				var cols: Array[Color] = []
				var shade: float = FACE_SHADE[fi]
				for k in 4:
					var a := _ao(p, n, corners[k]) if (ao and not g) else 1.0
					var f := shade * a * (1.0 + j)
					cols.append(Color(base.r * f, base.g * f, base.b * f, 1.0))
				var verts: Array[Vector3] = []
				for k in 4:
					verts.append((Vector3(p) + corners[k] - origin) * voxel_size)
				var nn := Vector3(n)
				# Flip the quad diagonal to avoid AO anisotropy.
				var order := [0, 2, 1, 0, 3, 2]
				if cols[0].get_luminance() + cols[2].get_luminance() < cols[1].get_luminance() + cols[3].get_luminance():
					order = [1, 3, 2, 1, 0, 3]
				for idx in order:
					st.set_normal(nn)
					st.set_color(cols[idx])
					st.add_vertex(verts[idx])
				count += 1
		if count == 0:
			continue
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_material() if g else solid_material())
	return mesh


func build_instance(voxel_size := 0.0625, origin := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build(voxel_size, origin)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func solid_material() -> StandardMaterial3D:
	if _mat_solid == null:
		_mat_solid = StandardMaterial3D.new()
		_mat_solid.vertex_color_use_as_albedo = true
		_mat_solid.vertex_color_is_srgb = true
		_mat_solid.roughness = 0.85
		_mat_solid.metallic_specular = 0.25
	return _mat_solid


static func glow_material() -> StandardMaterial3D:
	if _mat_glow == null:
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.vertex_color_use_as_albedo = true
		_mat_glow.vertex_color_is_srgb = true
		_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_glow.emission_enabled = true
		_mat_glow.emission = Color(1, 0.85, 0.6)
		_mat_glow.emission_energy_multiplier = 0.6
	return _mat_glow
