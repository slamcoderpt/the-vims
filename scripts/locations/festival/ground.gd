extends RefCounted
## Plaza floor: one textured plane (procedural cobblestones with baked bevels
## and leaf litter, nearest filtered so every texel reads as a voxel) plus a
## merged mesh of 3D fallen leaves, curbs and leaf piles.

const K := preload("res://scripts/locations/festival/kit.gd")

const X0 := -22.0
const X1 := 22.0
const Z0 := -34.0
const Z1 := 14.0
const PPM := 16  # texels per metre (1 texel = 1 voxel of 1/16 m)

## Tree trunk positions (metres) get extra leaf litter around them.
var litter_spots: Array = []


func build(parent: Node3D) -> void:
	var w := int((X1 - X0) * PPM)
	var h := int((Z1 - Z0) * PPM)
	var img := _cobbles(w, h)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.92
	mat.metallic_specular = 0.2
	var pm := PlaneMesh.new()
	pm.size = Vector2(X1 - X0, Z1 - Z0)
	var mi := MeshInstance3D.new()
	mi.name = "Cobbles"
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3((X0 + X1) * 0.5, 0.0, (Z0 + Z1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_leaves(parent)


const TILE := 96   # Voronoi tile size in texels (6 m), tiles seamlessly
const CELL := 6    # stone spacing in texels (~0.37 m)


## Precomputed seamless Voronoi tile: per texel the stone id and a shade
## factor (bevel: lit far edge, dark near edge, dark grout between stones).
func _stone_tile() -> Array:
	var n := TILE / CELL
	var centers := PackedVector2Array()
	centers.resize(n * n)
	for cy in n:
		for cx in n:
			var jx := 0.5 + (K.hs(cx, cy, 41) - 0.5) * 0.7
			var jy := 0.5 + (K.hs(cx, cy, 43) - 0.5) * 0.7
			centers[cy * n + cx] = Vector2((cx + jx) * CELL, (cy + jy) * CELL)
	var ids := PackedInt32Array()
	var shade := PackedFloat32Array()
	ids.resize(TILE * TILE)
	shade.resize(TILE * TILE)
	for y in TILE:
		for x in TILE:
			var p := Vector2(x + 0.5, y + 0.5)
			var gx := x / CELL
			var gy := y / CELL
			var d1 := 1e9
			var d2 := 1e9
			var best := 0
			var bc := Vector2.ZERO
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var cx := gx + ox
					var cy := gy + oy
					var wx := posmod(cx, n)
					var wy := posmod(cy, n)
					var c := centers[wy * n + wx] + Vector2((cx - wx) * CELL, (cy - wy) * CELL)
					var d := p.distance_squared_to(c)
					if d < d1:
						d2 = d1
						d1 = d
						best = wy * n + wx
						bc = c
					elif d < d2:
						d2 = d
			var edge := sqrt(d2) - sqrt(d1)
			var f := 1.0
			if edge < 0.9:
				f = -1.0  # grout
			else:
				var rel := (p - bc) / CELL
				f = 1.0 - rel.y * 0.22 - rel.x * 0.06
				if edge < 1.9:
					f *= 0.93 if rel.y > 0.0 else 1.05
			ids[y * TILE + x] = best
			shade[y * TILE + x] = f
	return [ids, shade]


func _cobbles(w: int, h: int) -> Image:
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var tones := [
		Color("b8b0a6"), Color("a39c94"), Color("c8bfb2"), Color("98918b"), Color("bba595"),
		Color("ad9f96"), Color("cfc6ba"), Color("a69a96"), Color("b9a493"), Color("d6cdbf"),
		Color("c2a898"), Color("9c958f"), Color("c9b5a8"), Color("b0aaa2"),
	]
	var grout := Color("6a625b")
	var tile := _stone_tile()
	var ids: PackedInt32Array = tile[0]
	var shd: PackedFloat32Array = tile[1]
	# Precompute colours per (tile, stone) lazily via hash: cheap enough per texel.
	var cw := w / 8 + 1
	var dmap := PackedFloat32Array()
	dmap.resize(cw * (h / 8 + 1))
	for cy in h / 8 + 1:
		for cx in cw:
			var mx := X0 + (cx * 8 + 4.0) / PPM
			var mz := Z0 + (cy * 8 + 4.0) / PPM
			var dens := 0.018 + 0.05 * smoothstep(5.0, 10.0, absf(mx - 0.5))
			for sp: Vector2 in litter_spots:
				var d := Vector2(mx, mz).distance_to(sp)
				dens += 0.2 * (1.0 - smoothstep(0.8, 3.0, d))
			dmap[cy * cw + cx] = dens
	for ty in h:
		var tyy := ty % TILE
		var tiy := ty / TILE
		for tx in w:
			var k := tyy * TILE + (tx % TILE)
			var f := shd[k]
			var c: Color
			if f < 0.0:
				c = grout
				if K.hs(tx, ty, 77) > 0.94:
					c = Color("7d7448")
			else:
				var sid := ids[k] + (tx / TILE) * 997 + tiy * 7919
				c = K.pick(tones, K.hs(sid, 1, 3))
				c = K.shade(c, f * (0.82 + K.hs(tx, ty, 5) * 0.05))
			# Painted leaf litter (denser towards the edges and under trees).
			var dens := dmap[(ty / 8) * cw + tx / 8]
			var lh := K.hs(tx / 2, ty / 2, 31)
			if lh < dens:
				c = K.pick(K.LEAF_GROUND, K.hs(tx / 2, ty / 2, 8))
				c = K.shade(c, 0.9 + K.hs(tx, ty, 3) * 0.15)
			var i := (ty * w + tx) * 3
			data[i] = int(clampf(c.r, 0, 1) * 255.0)
			data[i + 1] = int(clampf(c.g, 0, 1) * 255.0)
			data[i + 2] = int(clampf(c.b, 0, 1) * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return img


## 3D fallen leaves (1/16 m voxels) scattered over the centre of the square.
func _leaves(parent: Node3D) -> void:
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var shapes := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, -1)],
		[Vector2i(0, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(0, 2)],
	]
	var n := 0
	var i := 0
	while n < 240 and i < 4000:
		i += 1
		var x := -9.0 + K.hs(i, 1, 2) * 19.0
		var z := -9.0 + K.hs(i, 3, 4) * 17.0
		var cx := int(x * 16)
		var cz := int(z * 16)
		var shp: Array = shapes[int(K.hs(i, 5, 6) * shapes.size()) % shapes.size()]
		var c := K.pick(K.LEAF_GROUND, K.hs(i, 7, 8))
		var flip := K.hs(i, 9, 1) > 0.5
		for o: Vector2i in shp:
			var q := Vector3i(cx + (o.y if flip else o.x), 0, cz + (o.x if flip else o.y))
			vb.set_v(q, K.shade(c, 0.92 + K.hs(q.x, 0, q.z) * 0.16))
		n += 1
	# Leaf piles at tree bases.
	K.inst(parent, vb, 1.0 / 16.0, Vector3.ZERO, 0.0, false, Vector3.ZERO, "FallenLeaves")
