extends RefCounted
## Back of the family house: siding wall, glowing sliding doors with a cosy
## lit living room behind, upper windows, a raised wooden deck with a shingled
## porch roof on posts, wall lanterns and potted plants.

const V := preload("res://scripts/locations/backyard/vox.gd")
const FastBuilder := preload("res://scripts/locations/backyard/fast_builder.gd")
const M := 8
const F := 16

const SIDING := Color("c9c4d6")
const TRIM := Color("f3efe8")
const DECK := Color("b5794a")
const DECK_D := Color("8a5532")
const FRAME := Color("5b3b26")
const SHINGLE := Color("4e4a58")
const GLASS_LIT := Color("ffd690")

## Deck top height (m) and extents, used by the location for placing people.
const DECK_Y := 0.375
const X0 := 12      # 1.5 m
const X1 := 104     # 13 m
const WALL_Z := -48 # -6 m (outer face)
const UX0 := 44     # 5.5 m: left edge of the two-storey block
const DECK_Z1 := -21
const DOOR_X0 := 20  # 2.5 m
const DOOR_X1 := 92  # 11.5 m

var root: Node3D


func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "House"
	parent.add_child(root)
	var vb := FastBuilder.new()
	vb.jitter = 0.0
	vb.skip_normals = [Vector3i(0, 0, -1)]
	vb.skip_down_below = 2
	_shell(vb)
	_deck(vb)
	_porch(vb)
	V.inst(vb, root, V.SIZE_MID, Vector3.ZERO, 0.0, Vector3.ZERO, true, false, "HouseShell")
	var fine := FastBuilder.new()
	fine.jitter = 0.0
	fine.skip_normals = [Vector3i(0, 0, -1)]
	fine.skip_down_below = 6
	_interior(fine)
	_deck_decor(fine)
	V.inst(fine, root, V.SIZE_FINE, Vector3.ZERO, 0.0, Vector3.ZERO, true, true, "HouseDecor")
	# Warm interior light (two lamps filling the room) spilling out + porch fill.
	V.omni(root, Vector3(4.5, 2.4, -8.0), Color(1.0, 0.74, 0.46), 3.2, 6.0)
	V.omni(root, Vector3(9.5, 2.4, -8.0), Color(1.0, 0.74, 0.46), 3.2, 6.0)
	V.omni(root, Vector3(7.0, 2.6, -3.6), Color(1.0, 0.76, 0.5), 2.6, 6.0)
	_glass(root)


const GLASS_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Sliding-door glass: a faint warm sheen with soft diagonal reflection
// streaks, so the panes read as glass while the lit room shows through.
void fragment() {
	float s = fract((UV.x * 9.0 + UV.y * 3.2));
	float streak = smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.1, 0.22, s));
	float edge = smoothstep(0.75, 1.0, UV.y);
	ALBEDO = mix(vec3(1.0, 0.9, 0.75), vec3(1.0), streak);
	ALPHA = 0.05 + streak * 0.1 + edge * 0.06;
}
"""


func _glass(parent: Node3D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(float(DOOR_X1 - DOOR_X0) / M, 21.0 / M)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GLASS_SHADER
	mat.shader = sh
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "DoorGlass"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(float(DOOR_X0 + DOOR_X1) * 0.5 / M, (3.0 + 10.5) / M, float(WALL_Z) / M - 0.12)
	parent.add_child(mi)


func _siding(q: Vector3i) -> Color:
	var row := posmod(q.y, 2)
	var c := V.shade(SIDING, 1.0 if row == 0 else 0.9)
	return V.shade(c, 0.97 + V.h1(Vector3i(q.x / 6, q.y, 0), 2) * 0.06)


func _shell(vb: VoxelBuilder) -> void:
	var zb := -82
	# Foundation.
	V.b(vb, X0, 0, WALL_Z - 2, X1 - X0, 3, 2, Color("8f8790"))
	# Back wall (2 cells thick) + side walls. The left wing (X0..UX0) is a
	# single storey with a low lean-to roof so the sunset sky shows above it;
	# the two-storey block sits to the right.
	V.b(vb, X0, 3, WALL_Z - 2, X1 - X0, 25, 2, _siding)
	V.b(vb, UX0, 28, WALL_Z - 2, X1 - UX0, 20, 2, _siding)
	V.b(vb, X0, 3, zb, 2, 25, WALL_Z - zb, _siding)
	V.b(vb, UX0, 28, zb, 2, 20, WALL_Z - zb, _siding)
	V.b(vb, X1 - 2, 3, zb, 2, 45, WALL_Z - zb, _siding)
	# Interior back wall: warm lamp-lit cream plaster (soft emissive so the
	# room glows through the glass wall at dusk), brightest around the lamps.
	var lit_wall := func(q: Vector3i) -> Color:
		var hot := 1.0 - clampf(absf(float(q.y) - 12.0) / 18.0, 0.0, 1.0) * 0.3
		var lamp := maxf(0.0, 1.0 - absf(float(q.x) - 40.0) / 20.0) * 0.12 + maxf(0.0, 1.0 - absf(float(q.x) - 86.0) / 16.0) * 0.12
		return V.shade(Color("f1d7a8"), (0.8 + lamp) * hot + V.h1(q, 3) * 0.03)
	V.b(vb, X0, 3, zb, UX0 - X0, 25, 2, lit_wall, true)
	V.b(vb, UX0, 3, zb, X1 - UX0, 24, 2, lit_wall, true)
	# Inner faces of the side walls, also lamp-lit.
	V.b(vb, X0 + 2, 3, zb + 2, 1, 24, WALL_Z - zb - 4, V.shade(Color("e8c896"), 0.8), true)
	V.b(vb, X1 - 3, 3, zb + 2, 1, 24, WALL_Z - zb - 4, V.shade(Color("e8c896"), 0.8), true)
	V.b(vb, UX0, 27, zb, X1 - UX0, 21, 2, Color("e8d2b0"))
	# Corner trim boards.
	V.b(vb, X0 - 1, 3, WALL_Z - 2, 1, 25, 3, TRIM)
	V.b(vb, UX0 - 1, 28, WALL_Z - 2, 1, 20, 3, TRIM)
	V.b(vb, X1, 3, WALL_Z - 2, 1, 45, 3, TRIM)
	# Lean-to roof over the single-storey wing, rising towards the back.
	for z in range(zb - 2, WALL_Z + 1):
		var ry := 28 + int(float(WALL_Z - z) / 4.0)
		V.b(vb, X0 - 2, ry, z, UX0 - X0 + 2, 1, 1, func(q: Vector3i) -> Color:
			return V.shade(SHINGLE, 0.86 + V.h1(Vector3i(q.x / 3 + posmod(q.z, 2) * 7, 0, q.z), 5) * 0.28))
	# Floor / ceiling between storeys.
	V.b(vb, X0, 2, zb, X1 - X0, 1, WALL_Z - zb - 2, func(q: Vector3i) -> Color:
		return V.shade(Color("c08a58"), 0.92 + V.hs((q.x + q.z * 5) / 7, q.z, 2) * 0.16))
	V.b(vb, X0, 27, zb, X1 - X0, 1, WALL_Z - zb - 2, Color("f0e4cc"))
	# Trim band between floors.
	V.b(vb, X0, 27, WALL_Z - 2, X1 - X0, 1, 3, TRIM)
	# Wide sliding glass wall: x DOOR_X0..DOOR_X1, y 3..24, chunky dark
	# frames every 12 cells (ref4's floor-to-ceiling panels).
	vb.clear_box(Vector3i(DOOR_X0, 3, WALL_Z - 2), Vector3i(DOOR_X1 - DOOR_X0, 21, 2))
	V.b(vb, DOOR_X0 - 1, 3, WALL_Z - 2, 2, 22, 3, FRAME)
	V.b(vb, DOOR_X1 - 1, 3, WALL_Z - 2, 2, 22, 3, FRAME)
	V.b(vb, DOOR_X0 - 1, 24, WALL_Z - 2, DOOR_X1 - DOOR_X0 + 2, 1, 3, FRAME)
	V.b(vb, DOOR_X0, 3, WALL_Z - 2, DOOR_X1 - DOOR_X0, 1, 3, V.shade(FRAME, 0.8))
	var mx := DOOR_X0 + 12
	while mx < DOOR_X1 - 2:
		V.b(vb, mx, 4, WALL_Z - 2, 1, 20, 2, FRAME)
		mx += 12
	# Trim around the opening.
	V.b(vb, DOOR_X0 - 2, 3, WALL_Z, 1, 23, 1, TRIM)
	V.b(vb, DOOR_X1 + 1, 3, WALL_Z, 1, 23, 1, TRIM)
	V.b(vb, DOOR_X0 - 2, 25, WALL_Z, DOOR_X1 - DOOR_X0 + 4, 1, 1, TRIM)
	# Upper floor windows.
	_window(vb, 56, 32, 12, 10)
	_window(vb, 80, 32, 14, 10)
	# Roof: gable along X, ridge over the house.
	var eave_y := 48
	for k in 22:
		var z := WALL_Z + 1 - k
		V.b(vb, UX0 - 2, eave_y + k, z - 1, X1 - UX0 + 4, 1, 2, func(q: Vector3i) -> Color:
			return V.shade(SHINGLE, 0.86 + V.h1(Vector3i(q.x / 3 + (q.y % 2) * 7, q.y, 0), 5) * 0.28))
	# Fascia board.
	V.b(vb, UX0 - 2, eave_y - 1, WALL_Z, X1 - UX0 + 4, 1, 1, TRIM)
	# Gable end of the upper block (left side) closes the roof triangle.
	for k in 22:
		var dz := WALL_Z - 1 - k - zb
		if dz > 0:
			V.b(vb, UX0, eave_y + k, zb, 2, 1, dz, _siding)


func _window(vb: VoxelBuilder, x: int, y: int, w: int, h: int) -> void:
	vb.clear_box(Vector3i(x, y, WALL_Z - 2), Vector3i(w, h, 2))
	# Lit glass, slightly varied so it reads as curtains/room depth.
	V.b(vb, x, y, WALL_Z - 2, w, h, 1, func(q: Vector3i) -> Color:
		var t := float(q.y - y) / float(h)
		return V.shade(GLASS_LIT, 0.82 + t * 0.22 + V.h1(q, 8) * 0.05), true)
	# Mullions + trim.
	V.b(vb, x + w / 2, y, WALL_Z - 1, 1, h, 1, TRIM)
	V.b(vb, x, y + h / 2, WALL_Z - 1, w, 1, 1, TRIM)
	V.b(vb, x - 1, y - 1, WALL_Z - 1, w + 2, 1, 2, TRIM)
	V.b(vb, x - 1, y + h, WALL_Z - 1, w + 2, 1, 2, TRIM)
	V.b(vb, x - 1, y, WALL_Z - 1, 1, h, 1, TRIM)
	V.b(vb, x + w, y, WALL_Z - 1, 1, h, 1, TRIM)
	# Shutters.
	V.b(vb, x - 4, y, WALL_Z, 3, h, 1, Color("6f7fa3"))
	V.b(vb, x + w + 1, y, WALL_Z, 3, h, 1, Color("6f7fa3"))


func _deck(vb: VoxelBuilder) -> void:
	V.b(vb, X0, 0, DECK_Z1 - 1, X1 - X0, 2, 1, DECK_D)
	V.b(vb, X0, 2, WALL_Z, X1 - X0, 1, DECK_Z1 - WALL_Z, func(q: Vector3i) -> Color:
		var board := q.z
		var seg := (q.x + board * 7) / 13
		var c := V.shade(DECK, 0.9 + V.hs(seg, board, 3) * 0.2)
		return V.shade(c, 0.88) if posmod(q.x + board * 5, 13) == 0 else c)
	# Fascia.
	V.b(vb, X0, 0, DECK_Z1, X1 - X0, 3, 1, V.shade(DECK_D, 0.9))
	# Steps (x 20..36).
	V.b(vb, 20, 0, DECK_Z1, 16, 2, 2, V.wood(DECK, 0, 1))
	V.b(vb, 20, 0, DECK_Z1 + 2, 16, 1, 2, V.wood(DECK, 0, 1))


func _porch(vb: VoxelBuilder) -> void:
	var beam_z := DECK_Z1 - 2
	for px in [X0 + 1, 54, X1 - 3]:
		V.b(vb, px, 3, beam_z, 2, 22, 2, V.wood(Color("8a5a36"), 1, 1))
		V.b(vb, px - 1, 3, beam_z - 1, 4, 1, 4, Color("6b4428"))
	V.b(vb, X0, 25, beam_z, X1 - X0, 2, 2, V.wood(Color("7a4c2c"), 0, 1))
	# Rafters.
	var x := X0 + 2
	while x < X1 - 2:
		var zz := beam_z + 2
		while zz > WALL_Z:
			var yy := 27 + int(float(beam_z + 2 - zz) / 9.0)
			vb.set_v(Vector3i(x, yy, zz), Color("7a4c2c"))
			zz -= 1
		x += 7
	# Shingled roof sloping from the wall down past the beam.
	for z in range(WALL_Z, beam_z + 4):
		var yy := 28 + int(float(beam_z + 4 - z) / 9.0)
		V.b(vb, X0 - 1, yy, z, X1 - X0 + 2, 1, 1, func(q: Vector3i) -> Color:
			var c := V.shade(Color("4a4754"), 0.8 + V.h1(Vector3i(q.x / 3 + posmod(q.z, 2) * 5, 0, q.z), 6) * 0.32)
			return V.shade(c, 0.78) if posmod(q.z, 3) == 0 else c)
	# Chunky timber fascia along the front edge (reads like ref4's pergola).
	V.b(vb, X0 - 1, 26, beam_z + 3, X1 - X0 + 2, 2, 1, V.wood(Color("8a5a36"), 0, 1))


func _interior(vb: VoxelBuilder) -> void:
	# Fine grid (16/m). Room behind the glass wall: x 1.75..12.75 m,
	# z -10.25..-6.25 m, floor y 0.375 m (6), ceiling 3.375 m (54).
	var fy := 6
	var bz := -160  # back wall inner face
	# Fluffy pink rug.
	V.b(vb, 70, fy, -134, 84, 1, 30, func(q: Vector3i) -> Color:
		var u := q.x - 70
		var w := q.z + 134
		if u < 2 or u > 81 or w < 2 or w > 27:
			return Color("f3dfe4")
		# Shaggy pile in soft 3-cell tufts (merges into few quads).
		return V.shade(Color("f0b8c8"), 0.94 + V.hs(u / 3, w / 3, 6) * 0.1))
	# Light grey sofa against the back wall (facing the glass), with cushions.
	var sc := Color("d9d4cf")
	V.b(vb, 82, fy, bz, 72, 7, 18, sc)
	V.b(vb, 82, fy + 7, bz, 72, 12, 6, V.shade(sc, 0.94))
	V.b(vb, 78, fy, bz, 4, 12, 18, V.shade(sc, 0.9))
	V.b(vb, 154, fy, bz, 4, 12, 18, V.shade(sc, 0.9))
	for k in 3:
		V.b(vb, 84 + k * 23, fy + 7, bz + 6, 22, 2, 11, V.shade(sc, 1.04))
	V.b(vb, 88, fy + 9, bz + 6, 8, 8, 2, Color("6f86a8"))
	V.b(vb, 140, fy + 9, bz + 6, 8, 8, 2, Color("e2b456"))
	V.b(vb, 114, fy + 9, bz + 6, 8, 7, 2, Color("8a8f9c"))
	# Mustard armchair on the left, angled to the room.
	var ac := Color("d9a441")
	V.b(vb, 50, fy, -136, 16, 7, 16, ac)
	V.b(vb, 46, fy, -136, 4, 16, 16, V.shade(ac, 0.88))
	V.b(vb, 50, fy, -138, 16, 11, 2, V.shade(ac, 0.92))
	V.b(vb, 50, fy, -120, 16, 11, 2, V.shade(ac, 0.92))
	# Coffee table with a lamp-lit bowl + books.
	V.b(vb, 96, fy + 6, -134, 40, 2, 14, V.wood(Color("9a6a3e"), 0, 2))
	for lq in [Vector2i(97, -133), Vector2i(134, -133), Vector2i(97, -122), Vector2i(134, -122)]:
		V.b(vb, lq.x, fy, lq.y, 1, 6, 1, Color("6d4426"))
	V.b(vb, 104, fy + 8, -130, 6, 2, 6, Color("f1ede4"))
	V.b(vb, 105, fy + 10, -129, 4, 1, 4, Color("e85a3a"))
	V.b(vb, 120, fy + 8, -130, 8, 1, 6, Color("2f5e8f")); V.b(vb, 120, fy + 9, -130, 7, 1, 6, Color("e0b44c"))
	V.b(vb, 130, fy + 8, -128, 2, 4, 2, Color("ffd890"), true)
	# Big framed plant print above the sofa + two small frames.
	V.b(vb, 106, 32, bz, 22, 18, 1, Color("6b4428"))
	V.b(vb, 108, 34, bz + 1, 18, 14, 1, Color("f4ead6"))
	for i in 9:
		var ly := 36 + i
		var lw := 2 + (4 - absi(i - 4))
		V.b(vb, 117 - lw / 2, ly, bz + 1, lw, 1, 1, Color("4f8f44") if i % 2 == 0 else Color("3a7034"))
	V.b(vb, 117, 35, bz + 1, 1, 10, 1, Color("2f5a2a"))
	for fx: int in [88, 136]:
		V.b(vb, fx, 36, bz, 10, 10, 1, Color("5b3b26"))
		V.b(vb, fx + 1, 37, bz + 1, 8, 8, 1, func(q: Vector3i) -> Color:
			return Color("8fb7d9").lerp(Color("f6c98f"), float(q.y - 37) / 8.0))
	# Wall sconces (glowing).
	for sx: int in [72, 162]:
		V.b(vb, sx, 34, bz, 4, 6, 2, Color("ffe1a0"), true)
		V.b(vb, sx, 33, bz, 4, 1, 3, Color("3a3030"))
	# Tall bookshelves with books + ceramics, left and right.
	for bx0: int in [172]:
		V.b(vb, bx0, fy, bz, 24, 44, 9, V.wood(Color("94592f"), 1, 2))
		for sh in 5:
			var sy := fy + 2 + sh * 8
			vb.clear_box(Vector3i(bx0 + 1, sy, bz + 2), Vector3i(22, 6, 7))
			var bx: int = bx0 + 1
			while bx < bx0 + 23:
				var kind := int(V.hs(bx, sy, 9) * 5.0)
				if kind == 0 and bx < bx0 + 19:
					# Ceramic vase / jar.
					var vc: Color = [Color("f1ede4"), Color("8fb7d9"), Color("e48a6a")][int(V.hs(bx, sy, 7) * 3.0) % 3]
					V.b(vb, bx, sy, bz + 4, 3, 4, 3, vc)
					V.p(vb, bx + 1, sy + 4, bz + 5, vc)
					bx += 4
					continue
				if kind == 1 and bx < bx0 + 19:
					V.b(vb, bx, sy, bz + 4, 3, 2, 3, Color("d98a5a"))
					V.blob(vb, Vector3(bx + 1.5, sy + 3.5, bz + 5.5), Vector3(2.2, 1.6, 2.0), V.leaves(bx, 0, sy), 0.3, bx)
					bx += 4
					continue
				var bw := 1 + int(V.hs(bx, sy, 3) * 2.0)
				var bh := 4 + int(V.hs(bx, sy, 4) * 2.5)
				var bc: Color = [Color("b8403a"), Color("2f5e8f"), Color("e0b44c"), Color("3f7f4f"), Color("7a4b8c"), Color("e88a3a"), Color("d9d2bf")][int(V.hs(bx, sy, 5) * 7) % 7]
				V.b(vb, bx, sy, bz + 3, bw, bh, 6, bc)
				bx += bw
	# Floor lamp (glowing shade) between sofa and shelf + big leafy plants.
	V.b(vb, 66, fy, -152, 1, 26, 1, Color("3b3e47"))
	V.b(vb, 62, fy + 26, -156, 9, 7, 9, Color("ffe1a8"), true)
	_pot_plant(vb, 164, fy, -146, 18, 2)
	_pot_plant(vb, 40, fy, -112, 14, 1)
	_pot_plant(vb, 196, fy, -112, 12, 3)
	# Side table + table lamp by the sofa.
	V.b(vb, 160, fy, -134, 10, 9, 10, V.wood(Color("b07a46"), 0, 2))
	V.b(vb, 164, fy + 9, -130, 2, 4, 2, Color("3a3030"))
	V.b(vb, 161, fy + 13, -133, 8, 6, 8, Color("ffe6b0"), true)
	# Pendant lamps + a hanging lantern near the glass (ref4).
	for px: int in [116]:
		V.b(vb, px, 44, -128, 1, 10, 1, Color("2d2d33"))
		V.b(vb, px - 5, 40, -133, 11, 4, 11, Color("ffdc95"), true)
	V.b(vb, 186, 46, -110, 1, 8, 1, Color("2d2d33"))
	V.b(vb, 182, 36, -114, 9, 1, 9, Color("2a2a30"))
	V.b(vb, 183, 37, -113, 7, 8, 7, Color("ffd27a"), true)
	V.b(vb, 182, 45, -114, 9, 1, 9, Color("2a2a30"))


func _pot_plant(vb: VoxelBuilder, x: int, y: int, z: int, h: int, seed: int) -> void:
	var pot: Color = [Color("c8643c"), Color("ede7db"), Color("7393b3"), Color("d98a5a")][seed % 4]
	V.cyl(vb, x, y, z, 3.0, 5, V.noisy(pot, 0.05, seed))
	V.blob(vb, Vector3(x, y + 5 + h * 0.45, z), Vector3(4.5, h * 0.55, 4.5), V.leaves(seed, seed % 3, y + 5), 0.5, seed)


func _deck_decor(vb: VoxelBuilder) -> void:
	var fy := 6  # deck top (0.375 m)
	# Big potted plants along the wall and by the posts.
	_pot_plant(vb, 32, fy, -91, 12, 1)
	_pot_plant(vb, 128, fy, -91, 14, 2)
	_pot_plant(vb, 182, fy, -90, 10, 3)
	_pot_plant(vb, 196, fy, -48, 9, 0)
	_pot_plant(vb, 30, fy, -50, 8, 2)
	# Flower pots along the deck edge (steps at x 40..72).
	for i in 7:
		var px: int = [26, 84, 112, 138, 176, 196, 152][i]
		V.flower_pot(vb, px, fy, -46 + (i % 2) * 2, 11 + i * 7, i % 3 == 0)
	# Wall lanterns either side of the doors.
	for lx in [27, 191]:
		V.b(vb, lx, 34, -97, 5, 1, 4, Color("2a2a30"))
		V.b(vb, lx, 35, -97, 1, 6, 4, Color("2a2a30"))
		V.b(vb, lx + 4, 35, -97, 1, 6, 4, Color("2a2a30"))
		V.b(vb, lx + 1, 35, -96, 3, 6, 3, Color("ffd27a"), true)
		V.b(vb, lx, 41, -97, 5, 1, 4, Color("2a2a30"))
		V.b(vb, lx + 2, 42, -96, 1, 2, 1, Color("2a2a30"))
	# Doormat + a little bench with cushions on the right.
	V.b(vb, 92, fy, -95, 24, 1, 8, V.noisy(Color("a8835a"), 0.1))
	V.b(vb, 170, fy, -94, 26, 1, 8, V.wood(Color("b07a46"), 0, 2))
	V.b(vb, 170, fy + 1, -94, 26, 6, 8, Color(0, 0, 0, 0))
	for lx in [171, 193]:
		V.b(vb, lx, fy + 1, -93, 1, 6, 6, Color("7d4f2b"))
	V.b(vb, 170, fy + 7, -94, 26, 1, 8, V.wood(Color("b07a46"), 0, 2))
	V.b(vb, 172, fy + 8, -93, 8, 3, 6, Color("e9a3b8"))
	V.b(vb, 182, fy + 8, -93, 8, 3, 6, Color("f3e3c3"))
