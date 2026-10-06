extends RefCounted
## Background town: brick town hall with a clock tower, brick townhouse on the
## left, stone house on the right and a far skyline row.
## Wall slabs are textured boxes (pixel-art brick / ashlar textures, world
## triplanar, 16 texels per metre, nearest filtered so they read as voxels)
## which keeps the triangle count tiny; trims, windows, doors and the clock
## are 1/8 m voxels; roofs are 1/4 m voxels.

const K := preload("res://scripts/locations/festival/kit.gd")
const VS := 0.125
const C := 8  # detail cells per metre
const R := 4  # roof cells per metre

const BRICK := [Color("b4583c"), Color("a54d34"), Color("bf6446"), Color("9c4630"), Color("c46e4e"), Color("ab5238")]
const BRICK2 := [Color("c98258"), Color("b8704a"), Color("d39066"), Color("ad6442"), Color("c27a50")]
const STONE := [Color("e2d6bf"), Color("d6c8ae"), Color("ebe0cb"), Color("cbbb9f")]
const GREYSTONE := [Color("b4b4b0"), Color("a6a6a2"), Color("c0c0bb"), Color("9a9a96")]
const SLATE := [Color("4c5566"), Color("434b5a"), Color("566072"), Color("3d4452")]
const ROOF_BROWN := [Color("6a4a40"), Color("5a3e36"), Color("74544a")]
const TRIM := Color("f3eee4")
const GLASS := Color("3a5068")
const GLASS_LIT := Color("ffc56a")

const HALL_Z := -29.0
const HALL_H := 6.6

var clock_center := Vector3.ZERO
var window_glows: Array = []  # world positions of lit windows (for halos)

var _walls := {}   # material key -> Array of [from: Vector3, size: Vector3]
var det: VoxelBuilder
var roof: VoxelBuilder


func build(parent: Node3D) -> void:
	det = VoxelBuilder.new()
	det.jitter = 0.0
	roof = VoxelBuilder.new()
	roof.jitter = 0.0
	_town_hall()
	_house_left()
	_house_right()
	_wall_meshes(parent)
	K.inst(parent, det, VS, Vector3.ZERO, 0.0, true, Vector3.ZERO, "TownDetail")
	K.inst(parent, roof, 1.0 / R, Vector3.ZERO, 0.0, true, Vector3.ZERO, "TownRoofs")
	var far := VoxelBuilder.new()
	far.jitter = 0.0
	_skyline(far)
	K.inst(parent, far, 0.5, Vector3.ZERO, 0.0, false, Vector3.ZERO, "Skyline")


# ------------------------------------------------------------------ walls

func _wall(key: String, from: Vector3, size: Vector3) -> void:
	if not _walls.has(key):
		_walls[key] = []
	_walls[key].append([from, size])


func _wall_meshes(parent: Node3D) -> void:
	var m := ArrayMesh.new()
	for key: String in _walls:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b: Array in _walls[key]:
			_box_faces(st, b[0], b[1])
		st.index()
		st.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, _wall_material(key))
	var mi := MeshInstance3D.new()
	mi.name = "TownWalls"
	mi.mesh = m
	parent.add_child(mi)


func _box_faces(st: SurfaceTool, o: Vector3, s: Vector3) -> void:
	var p := [o, o + Vector3(s.x, 0, 0), o + Vector3(s.x, 0, s.z), o + Vector3(0, 0, s.z),
		o + Vector3(0, s.y, 0), o + Vector3(s.x, s.y, 0), o + Vector3(s.x, s.y, s.z), o + Vector3(0, s.y, s.z)]
	var quads := [
		[3, 2, 6, 7, Vector3(0, 0, 1)],   # front (+Z)
		[1, 0, 4, 5, Vector3(0, 0, -1)],  # back
		[2, 1, 5, 6, Vector3(1, 0, 0)],   # +X
		[0, 3, 7, 4, Vector3(-1, 0, 0)],  # -X
		[7, 6, 5, 4, Vector3(0, 1, 0)],   # top
	]
	for q: Array in quads:
		st.set_normal(q[4])
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(p[q[idx]])


static var _mats := {}

func _wall_material(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var img: Image
	match key:
		"brick": img = _brick_tex(BRICK, Color("d8c8b0"))
		"brick2": img = _brick_tex(BRICK2, Color("e2d4bc"))
		"grey": img = _ashlar_tex(GREYSTONE, Color("7e7e7a"))
		_: img = _ashlar_tex(STONE, Color("b0a088"))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	mat.roughness = 0.9
	mat.metallic_specular = 0.2
	_mats[key] = mat
	return mat


## 64x64 texel tile = 4 m. Bricks 4x2 texels with 1 texel mortar, running bond.
func _brick_tex(pal: Array, mortar: Color) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var row := y / 2
		var off := 2 if row % 2 == 0 else 0
		for x in 64:
			var c: Color
			if y % 2 == 1 or (x + off) % 4 == 3:
				c = K.shade(mortar, 0.9 + K.hs(x, y, 3) * 0.12)
				if y % 2 == 1 and (x + off) % 4 != 3:
					c = K.shade(c, 0.92)
			else:
				var bi := (x + off) / 4
				c = K.pick(pal, K.hs(bi, row, 11))
				c = K.shade(c, 0.95 + K.hs(x, y, 7) * 0.1)
				if (x + off) % 4 == 0:
					c = K.shade(c, 1.06)
			img.set_pixel(x, y, c)
	return img


func _ashlar_tex(pal: Array, mortar: Color) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var row := y / 5
		var off := 4 if row % 2 == 0 else 0
		for x in 64:
			var c: Color
			if y % 5 == 4 or (x + off) % 8 == 7:
				c = mortar
			else:
				c = K.pick(pal, K.hs((x + off) / 8, row, 5))
				c = K.shade(c, 0.95 + K.hs(x, y, 9) * 0.08)
				if y % 5 == 0:
					c = K.shade(c, 1.06)
			img.set_pixel(x, y, c)
	return img


# ------------------------------------------------------------------ details

func _band(x0: float, x1: float, y: float, z: float, h: float, d := 0.25, pal := STONE) -> void:
	K.box(det, int(x0 * C), int(y * C), int(z * C), int((x1 - x0) * C), int(h * C), int(d * C), func(q: Vector3i) -> Color:
		return K.pick(pal, K.hs(q.x / 4, q.y, q.z / 4)))


## Window on a front wall whose outer face is at z (metres). x, y = bottom-left.
func _window(x: float, y: float, z: float, w: int, h: int, lit: bool, arch := false) -> void:
	var cx := int(round(x * C))
	var cy := int(round(y * C))
	var cz := int(round(z * C))
	# Frame (protrudes 1 cell).
	for i in range(-1, w + 1):
		for j in range(-1, h + 1):
			var edge := i == -1 or i == w or j == -1 or j == h
			var mull := i == w / 2 or j == h * 6 / 10
			var p := Vector3i(cx + i, cy + j, cz)
			if edge:
				det.set_v(p, TRIM)
				det.set_v(p + Vector3i(0, 0, 1), TRIM)
			elif mull:
				det.set_v(p, TRIM)
			elif lit:
				det.set_v(p, K.shade(GLASS_LIT, 0.85 + 0.2 * float(j) / h), true)
			else:
				det.set_v(p, K.shade(GLASS, 1.0 + 0.45 * float((i + j) % 6 == 0)))
	if arch:
		for i in range(-1, w + 1):
			var t := absf(i + 0.5 - w * 0.5) / (w * 0.5 + 1.0)
			var extra := int(round((1.0 - t * t) * 3.0))
			for e in extra + 1:
				det.set_v(Vector3i(cx + i, cy + h + 1 + e, cz), TRIM)
				det.set_v(Vector3i(cx + i, cy + h + 1 + e, cz + 1), TRIM)
	# Sill + shutters.
	K.box(det, cx - 2, cy - 2, cz, w + 4, 1, 3, Color("e8e0cf"))
	if not arch and h > 8:
		for sx in [cx - 4, cx + w + 1]:
			K.box(det, sx, cy, cz, 3, h, 1, K.wood(Color("3f5f4a"), 2, 1))
	if lit:
		window_glows.append(Vector3((cx + w * 0.5) * VS, (cy + h * 0.5) * VS, cz * VS + 0.15))


## Gable roof (ridge along X) in roof cells. Metres in, slope 1:1.
func _roof_x(x0: float, x1: float, zb: float, zf: float, h: float, pal: Array) -> void:
	var rx0 := int(x0 * R)
	var rx1 := int(x1 * R)
	var rzb := int(zb * R)
	var rzf := int(zf * R)
	var rh := int(h * R)
	var half := (rzf - rzb) / 2
	for z in range(rzb, rzf + 1):
		var t := mini(z - rzb, rzf - z)
		var y := rh + t
		for x in range(rx0, rx1):
			var c: Color = K.pick(pal, K.hs(x / 5, y, 5))
			roof.set_v(Vector3i(x, y, z), c)
		# Eave overhang trim underneath.
		if t == 0:
			for x in range(rx0, rx1):
				roof.set_v(Vector3i(x, y - 1, z), Color("e8e0cf"))
	for x in range(rx0, rx1):
		roof.set_v(Vector3i(x, rh + half + 1, rzb + half), Color("3a3f4a"))


## Gable roof whose ridge runs along Z (front gable facing the square).
func _roof_z(x0: float, x1: float, zb: float, zf: float, h: float, pal: Array, wall_key: String) -> void:
	var rx0 := int(x0 * R)
	var rx1 := int(x1 * R)
	var rzb := int(zb * R)
	var rzf := int(zf * R)
	var rh := int(h * R)
	var half := (rx1 - rx0) / 2
	for x in range(rx0, rx1):
		var t := mini(x - rx0, rx1 - 1 - x)
		var y := rh + t
		for z in range(rzb, rzf + 1):
			var c: Color = K.pick(pal, K.hs(z / 2, y, 9))
			if posmod(z + y, 5) == 0:
				c = K.shade(c, 0.9)
			roof.set_v(Vector3i(x, y, z), c)
			roof.set_v(Vector3i(x, y - 1, z), K.shade(c, 0.8))
		# Front gable triangle: stacked wall slabs (textured).
	for i in half:
		var y0 := h + float(i) / R
		var a := x0 + float(i + 1) / R
		var b := x1 - float(i + 1) / R
		if b > a:
			_wall(wall_key, Vector3(a, y0, zf - 0.75), Vector3(b - a, 1.0 / R, 0.25))
	# White barge boards along the gable edge.
	for x in range(rx0, rx1):
		var t := mini(x - rx0, rx1 - 1 - x)
		roof.set_v(Vector3i(x, rh + t - 1, rzf + 1), TRIM)


# ------------------------------------------------------------------ buildings

func _town_hall() -> void:
	var z := HALL_Z
	var h := HALL_H
	_wall("brick", Vector3(-6.5, 0, z - 4.5), Vector3(13.0, h, 4.5))
	# Stone plinth, floor band, cornice, quoins.
	_band(-6.6, 6.6, 0.0, z - 0.1, 0.5, 0.375)
	_band(-6.6, 6.6, 2.4, z - 0.1, 0.25, 0.375)
	_band(-6.6, 6.6, 4.45, z - 0.1, 0.25, 0.375)
	_band(-6.7, 6.7, h - 0.375, z - 0.1, 0.375, 0.5)
	for y in range(0, int(h * 2)):
		var w := 0.625 if y % 2 == 0 else 0.375
		_band(-6.6, -6.6 + w, y * 0.5, z - 0.1, 0.25, 0.375)
		_band(6.6 - w, 6.6, y * 0.5, z - 0.1, 0.25, 0.375)
	# Windows (two floors) either side of the tower.
	for fl in 3:
		var wy := 0.75 + fl * 2.05
		for wx in [-5.5, -3.9, 2.9, 4.5]:
			var lit := K.hs(int(wx * 4.0), fl, 21) < 0.35
			_window(wx, wy, z, 8, 11, lit, fl != 1)
	# Roof.
	_roof_x(-7.0, 7.0, z - 5.0, z + 0.5, h, SLATE)
	# Dormers on the roof.
	for dx in [-4.8, 3.4]:
		_wall("stone", Vector3(dx, h + 0.25, z - 1.4), Vector3(1.5, 1.3, 1.0))
		_window(dx + 0.25, h + 0.45, z - 0.4, 7, 7, dx > 0, false)
		var rx := int(dx * R)
		for i in 4:
			for zz in range(int((z - 1.6) * R), int((z - 0.25) * R)):
				roof.set_v(Vector3i(rx - 1 + i, int((h + 1.5) * R) + i, zz), SLATE[0])
				roof.set_v(Vector3i(rx + 6 - i, int((h + 1.5) * R) + i, zz), SLATE[1])
	# --- Clock tower (front at z + 0.5).
	var tz := z + 0.5
	var th := 11.5
	_wall("brick", Vector3(-1.75, 0, tz - 3.0), Vector3(3.5, th, 3.0))
	for y in range(0, int(th * 2)):
		var w := 0.5 if y % 2 == 0 else 0.375
		_band(-1.85, -1.85 + w, y * 0.5, tz - 0.1, 0.25, 0.375)
		_band(1.85 - w, 1.85, y * 0.5, tz - 0.1, 0.25, 0.375)
	_band(-1.9, 1.9, h - 0.375, tz - 0.1, 0.375, 0.5)
	_band(-2.0, 2.0, th - 0.25, tz - 3.1, 0.375, 3.25)
	_band(-1.9, 1.9, 0, tz - 0.1, 0.5, 0.375)
	# Door + steps.
	K.box(det, -7, 4, int(tz * C), 14, 18, 1, K.wood(Color("5a3520"), 2, 2))
	for y in 17:
		det.set_v(Vector3i(0, 4 + y, int(tz * C) + 1), Color("3e2414"))
	K.box(det, -9, 4, int(tz * C), 2, 20, 2, K.mix(STONE, 7))
	K.box(det, 7, 4, int(tz * C), 2, 20, 2, K.mix(STONE, 8))
	K.box(det, -9, 22, int(tz * C), 18, 3, 2, K.mix(STONE, 9))
	det.set_v(Vector3i(-2, 12, int(tz * C) + 1), Color("d9b45a"))
	det.set_v(Vector3i(1, 12, int(tz * C) + 1), Color("d9b45a"))
	K.box(det, -14, 0, int(tz * C), 28, 2, 6, K.mix(STONE, 9))
	K.box(det, -11, 2, int(tz * C), 22, 2, 3, K.mix(STONE, 10))
	# Window above the door.
	_window(-0.5, 3.35, tz, 8, 9, true, true)
	_window(-0.5, 5.6, tz, 8, 10, false, true)
	_band(-1.9, 1.9, 7.1, tz - 0.1, 0.25, 0.375)
	# Clock face.
	var cy := int(8.5 * C)
	clock_center = Vector3(0.0, (cy + 0.5) * VS, tz + 0.15)
	_clock(0, cy, int(tz * C))
	# Belfry openings with a bell.
	for bx in [-10, 3]:
		K.box(det, bx, int(10.15 * C), int(tz * C), 7, 7, 1, Color("2a2420"))
	K.box(det, -1, int(10.2 * C), int(tz * C) - 1, 3, 4, 1, Color("c9a040"))
	# Spire (roof cells).
	var sp := 0
	var w := 16
	while w - 2 * sp > 1:
		var y := int(th * R) + sp * 2
		K.box(roof, -8 + sp, y, int((tz - 3.25) * R) + sp, w - 2 * sp, 2, 14 - 2 * sp, K.mix(SLATE, sp))
		sp += 1
	var top := int(th * R) + sp * 2
	var mz := int((tz - 3.25) * R) + 7
	K.box(roof, -1, top, mz - 1, 1, 4, 1, Color("d9b04a"))
	roof.set_v(Vector3i(-1, top + 4, mz - 1), Color("f0c85a"))


func _clock(cx: int, cy: int, z: int) -> void:
	var r := 11.0
	for x in range(-12, 13):
		for y in range(-12, 13):
			var d := sqrt((x + 0.5) * (x + 0.5) + (y + 0.5) * (y + 0.5))
			if d > r:
				continue
			var c := Color("fbf6ea")
			if d > r - 1.5:
				c = Color("2d2a28")
			elif d > r - 2.5:
				c = Color("d9b04a")
			det.set_v(Vector3i(cx + x, cy + y, z), c)
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector2(sin(a), cos(a)) * (r - 4.0)
		det.set_v(Vector3i(cx + roundi(p.x - 0.5), cy + roundi(p.y - 0.5), z + 1), Color("2d2a28"))
	var am := TAU * 42.0 / 60.0
	var ah := TAU * (4.0 + 42.0 / 60.0) / 12.0
	for t in range(0, 9):
		var p := Vector2(sin(am), cos(am)) * t
		det.set_v(Vector3i(cx + roundi(p.x - 0.5), cy + roundi(p.y - 0.5), z + 1), Color("1e1c1a"))
	for t in range(0, 6):
		var p := Vector2(sin(ah), cos(ah)) * t
		det.set_v(Vector3i(cx + roundi(p.x - 0.5), cy + roundi(p.y - 0.5), z + 1), Color("1e1c1a"))
	det.set_v(Vector3i(cx, cy, z + 2), Color("d9b04a"))


func _house_left() -> void:
	# Brick townhouse, front gable, close to the left of the square.
	var x0 := -14.5
	var x1 := -5.5
	var z := -14.5
	var h := 5.6
	_wall("brick2", Vector3(x0, 0, z - 5.0), Vector3(x1 - x0, h, 5.0))
	_band(x0 - 0.1, x1 + 0.1, 0, z - 0.1, 0.375, 0.375)
	_band(x0 - 0.1, x1 + 0.1, 2.75, z - 0.1, 0.25, 0.375)
	var cols := [x0 + 0.9, x0 + 3.0, x0 + 5.2, x0 + 7.3]
	for fl in 2:
		for i in cols.size():
			var lit := K.hs(i, fl, 4) < 0.45
			if fl == 0 and i == 2:
				# Shop door with a striped awning.
				K.box(det, int(cols[i] * C), 3, int(z * C), 10, 18, 1, Color("3f5f4a"))
				K.box(det, int(cols[i] * C) + 1, 4, int(z * C) + 1, 8, 15, 1, Color(GLASS_LIT), true)
				for k in 14:
					K.box(det, int(cols[i] * C) - 2 + k, 22, int(z * C), 1, 1, 5, Color("c23a2a") if (k / 2) % 2 == 0 else TRIM)
				continue
			_window(cols[i], 0.9 + fl * 2.6, z, 8, 12, lit)
	_roof_z(x0 - 0.5, x1 + 0.5, z - 5.5, z + 0.25, h, SLATE, "brick2")
	# Round attic window.
	var cx := int((x0 + x1) * 0.5 * C)
	var cy := int((h + 1.6) * C)
	for x in range(-4, 5):
		for y in range(-4, 5):
			var d := Vector2(x, y).length()
			if d <= 4.4:
				det.set_v(Vector3i(cx + x, cy + y, int(z * C)), TRIM if d > 3.0 else Color(GLASS_LIT), d <= 3.0)
	window_glows.append(Vector3(cx * VS, cy * VS, z + 0.1))


func _house_right() -> void:
	var x0 := 8.0
	var x1 := 19.0
	var z := -17.0
	var h := 5.4
	_wall("grey", Vector3(x0, 0, z - 5.0), Vector3(x1 - x0, h, 5.0))
	_band(x0 - 0.1, x1 + 0.1, 0, z - 0.1, 0.375, 0.375, GREYSTONE)
	_band(x0 - 0.1, x1 + 0.1, h - 0.375, z - 0.1, 0.375, 0.5)
	for fl in 2:
		for i in 4:
			_window(x0 + 1.0 + i * 2.6, 0.8 + fl * 2.4, z, 8, 12, K.hs(i, fl, 9) < 0.4)
	_roof_x(x0 - 0.5, x1 + 0.5, z - 5.5, z + 0.5, h, ROOF_BROWN)
	for dx in [x0 + 2.0, x0 + 7.0]:
		_wall("stone", Vector3(dx, h + 0.25, z - 1.4), Vector3(1.5, 1.3, 1.0))
		_window(dx + 0.25, h + 0.45, z - 0.4, 7, 7, dx < x0 + 3.0, false)


func _skyline(vb: VoxelBuilder) -> void:
	# 1/2 m cells: a row of houses / roofs well behind the town hall.
	var cols := [Color("c9805a"), Color("d8c3a0"), Color("9fb0b8"), Color("b8644a"), Color("e0cfa8"), Color("a88a70")]
	var roofs := [Color("4c5566"), Color("6a4a3e"), Color("5a6272")]
	var x := -50
	var i := 0
	while x < 50:
		var w := 8 + int(K.hs(i, 1, 2) * 6)
		var h := 10 + int(K.hs(i, 3, 4) * 7)
		var z0 := -62 - int(K.hs(i, 5, 6) * 6)
		var c: Color = cols[i % cols.size()]
		K.box(vb, x, 0, z0, w, h, 2, K.noisy(c, 0.05, i))
		var rc: Color = roofs[i % roofs.size()]
		for t in w / 2 + 1:
			K.box(vb, x + t, h + t, z0 - 1, maxi(w - 2 * t, 1), 1, 4, K.noisy(rc, 0.08, i))
		for wy in range(2, h - 2, 4):
			for wx in range(x + 1, x + w - 1, 3):
				var lit := K.hs(wx, wy, i) > 0.65
				vb.set_v(Vector3i(wx, wy, z0 + 2), Color(GLASS_LIT) if lit else Color(GLASS), lit)
		x += w
		i += 1
