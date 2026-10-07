extends Node3D
## The family home: a two-storey voxel house with Sims-style cutaway walls.
##
##   Upstairs (floor at y = 3 m)
##     Office / family room   x -9..-1   (ref1: desk, cork board, easel, piano, toys, dog bed)
##       with a balcony railing over the double-height living room (void, front-left)
##     Pink bunny bedroom     x -1..3.5, z -5..0
##     Blue star bedroom      x 3.5..9,  z -5..0
##     Hallway + stairs       x -1..5.5, z 0..5   (dog cushion)
##     Bathroom               x 5.5..9,  z 0..5
##   Downstairs: living room (under the office) and kitchen/dining.
##   Outside: garden, trees, a street with lamps and neighbour houses.
##
## Cutaway: walls that face the camera are lowered. Which walls are up depends
## on the "wall view" ("office" or "bed"); set_wall_view() switches it, and in
## live play it follows the camera automatically.
##
## API: build(), apply_preset(name), camera_home(), lighting_profile(),
##      get_actor(name) -> SimActor, set_wall_view(view).

const U := 0.0625          # fine grid (windows, railings, stairs)
const PU := 0.09           # furniture display grid (1.44 x U; PropLib.FU is 1.25 x U)
const FS := 1.25           # furniture display scale
const UH := 25             # upstairs wall height in structure cells (3.125 m)
const C := 0.125           # structure grid
const UF := 3.0            # upstairs floor height (m)
const VIEWS := ["office", "bed"]
## Household display scale relative to the rig's life size (dad ~1.4 m, kids
## ~1.0 m, beagle about the size of its bed). SimActor clamps body_scale to a
## hero minimum, so the remainder is applied as a node scale (see _spawn_household).
const ACTOR_SCALE := {"dad": 0.9, "bunny_girl": 0.84, "cat_girl": 0.84, "beagle": 0.62}
## Ground-floor front facade windows (x0, x1 metres), y 0.9..2.1.
const FRONT_WINDOWS := [[-8.2, -6.8], [-5.6, -4.2], [-3.0, -1.6], [2.0, 3.0], [5.9, 7.3], [7.6, 8.5]]
const HALO_NIGHT := 0.55
const ShotPresets := preload("res://scripts/core/shot_presets.gd")
const PropLib := preload("res://scripts/props/prop_lib.gd")
const Mesher := preload("res://scripts/props/mesher.gd")

# --- palette
const SIDING := Color("f3ead9")
const TRIM := Color("fbf8f1")
const CAP := Color("2e3450")
const FOUND := Color("8c8378")
const W_OFFICE := Color("f0e3cc")
const W_PINK := Color("f2b9c7")
const W_BLUE := Color("8399d8")
const W_HALL := Color("efe1c6")
const W_LIVING := Color("e9dcc2")
const W_KITCHEN := Color("dfe8d6")
const FLOOR_WOOD := Color("d3a272")
const FLOOR_LIGHT := Color("d9a56c")

var actors := {}                 # key -> SimActor
var wall_view := "office"
var _sb := {}                    # structure groups "zone|sig|part" -> VoxelBuilder
var _fb := {}                    # furniture builders room -> VoxelBuilder (PU grid)
var _gb := {}                    # fine builders room -> VoxelBuilder (U grid)
var _wall_nodes := {}            # sig -> {part -> Array[MeshInstance3D]}
var _view_meshes := []           # [MeshInstance3D, view]: props on walls that are only tall in that view
var _hood_day: MeshInstance3D
var _hood_night: MeshInstance3D
var _glass_day: MeshInstance3D
var _glass_night: MeshInstance3D
var _front_glass_day: MeshInstance3D
var _front_glass_night: MeshInstance3D
var _glass_up_day: MeshInstance3D
var _glass_up_night: MeshInstance3D
var _moon: MeshInstance3D
var _moon_disc: MeshInstance3D   # billboard moon pinned near the top of the frame
var _is_night := false
var _view_timer := 0.0
var _auto_view := true
var _halo_pts := []
var _halos: MultiMeshInstance3D
var _blanket: MeshInstance3D
var _night_tint: Array[MeshInstance3D] = []   # exterior meshes darkened at night
var _hood_mat: StandardMaterial3D


# =================================================================== API

func build() -> void:
	var t0 := Time.get_ticks_msec()
	_is_night = Game.is_night()
	var stats := OS.get_environment("VIMS_STATS") != ""
	var steps := [_build_structure, _build_office, _build_living, _build_pink, _build_blue, _build_hall,
		_build_bath, _build_kitchen, _build_exterior, _bake, _ensure_neighbourhood.bind(_is_night)]
	for st: Callable in steps:
		var ts := Time.get_ticks_usec()
		st.call()
		if stats:
			print("  step ", st.get_method(), " ", (Time.get_ticks_usec() - ts) / 1000, " ms")
	_make_moon()
	if OS.get_environment("VIMS_HALOTEST") != "":
		_halo_pts.append({"pos": Vector3(-4.6, 4.5, -0.7), "size": 3.0, "color": Color(1, 0, 0)})
	_halos = PropLib.halos(_halo_pts)
	add_child(_halos)
	PropLib.set_halo_strength(_halos, HALO_NIGHT if _is_night else 0.0)
	_spawn_household()
	_stage("home_night" if _is_night else "home_day")
	set_wall_view("bed" if _is_night else "office")
	Game.time_changed.connect(_on_time)
	if OS.get_environment("VIMS_STATS") != "":
		print("HOME_BUILD_MS ", Time.get_ticks_msec() - t0)


func camera_home() -> Dictionary:
	return ShotPresets.PRESETS["home_day"].camera.duplicate()


func lighting_profile() -> Dictionary:
	return {
		"sun_heading": 205.0, "sun_elev": 34.0, "sun_energy": 1.8,
		"ambient_day": Color(0.94, 0.86, 0.76), "ambient_energy": 0.58,
		"ambient_night": Color(0.66, 0.54, 0.52), "ambient_night_energy": 0.34, "lamp_night_mult": 3.8,
		"sky_day": Color(0.64, 0.8, 0.94), "sky_night": Color(0.07, 0.09, 0.22),
		"fog_day": Color(0.9, 0.9, 0.88), "fog_night": Color(0.12, 0.15, 0.32), "fog_density": 0.004,
		"moon_heading": 150.0, "moon_energy": 0.32, "glow_boost_night": 1.2,
		"shadow_distance": 40.0,
		"post_day": {"focus_y": 0.5, "band": 0.3, "falloff": 0.24, "blur_px": 4.5, "top_boost": 1.0,
			"saturation": 1.16, "contrast": 1.12, "tint": Vector3(1.02, 1.0, 0.96), "vignette": 0.22},
		"post_night": {"focus_y": 0.55, "band": 0.33, "falloff": 0.2, "blur_px": 2.6, "top_boost": 0.8},
	}


func get_actor(key: String) -> SimActor:
	return actors.get(key, null)


func apply_preset(preset: String) -> void:
	_stage(preset)
	set_wall_view("bed" if preset == "home_night" else "office")
	_auto_view = false


func set_wall_view(view: String) -> void:
	wall_view = view
	_sync_front_glass()
	for vm in _view_meshes:
		vm[0].visible = vm[1] == view
	for sig: String in _wall_nodes:
		var mode := _mode_for(sig, view)
		var parts: Dictionary = _wall_nodes[sig]
		for part: String in parts:
			var vis := false
			match part:
				"base": vis = mode != "none"
				"cap": vis = mode == "low"
				"upper": vis = mode == "tall"
			for mi: MeshInstance3D in parts[part]:
				mi.visible = vis


func _sync_front_glass() -> void:
	if _front_glass_day:
		_front_glass_day.visible = wall_view == "bed" and not _is_night
		_front_glass_night.visible = wall_view == "bed" and _is_night


# =================================================================== helpers

static func cc(m: float) -> int:
	return roundi(m * 8.0)


static func fc(m: float) -> int:
	return roundi(m * 16.0)


## Metres -> furniture cells (PU grid).
static func pc(m: float) -> int:
	return roundi(m / PU)


func _zone(q: Vector3i) -> int:
	# Coarse cell -> light zone (x band, z half, floor). Keeps the number of
	# omni lights touching each merged mesh low (GL Compatibility: <= 8 / mesh).
	var xb := 0 if q.x < -8 else (1 if q.x < 28 else 2)
	var zb := 0 if q.z < 0 else 1
	var fl := 0 if q.y < 22 else 1
	return (xb + 3 * zb) * 2 + fl


func _sgroup(zone: int, sig: String, part: String) -> VoxelBuilder:
	var key := "%d|%s|%s" % [zone, sig, part]
	if not _sb.has(key):
		var vb := VoxelBuilder.new()
		vb.jitter = 0.0
		_sb[key] = vb
	return _sb[key]


func _f(room: String) -> VoxelBuilder:
	if not _fb.has(room):
		var vb := VoxelBuilder.new()
		vb.jitter = 0.03
		_fb[room] = vb
	return _fb[room]


## Fine-grid builder (U cells) for windows, railings, stairs, string lights.
func _g(room: String) -> VoxelBuilder:
	if not _gb.has(room):
		var vb := VoxelBuilder.new()
		vb.jitter = 0.05
		_gb[room] = vb
	return _gb[room]


## Place a prop with its footprint min corner at `pos` (metres). Returns its box in metres.
func _put(room: String, pname: String, pos: Vector3, rot := 0, v := 0) -> AABB:
	var at := Vector3i(pc(pos.x), pc(pos.y), pc(pos.z))
	var bb := PropLib.place(_f(room), pname, at, rot, v)
	return AABB(bb.position * PU, bb.size * PU)


## Place a prop centred on (x, z) metres.
func _putc(room: String, pname: String, x: float, y: float, z: float, rot := 0, v := 0) -> AABB:
	var rs := PropLib.rotated_size(pname, rot, v)
	return _put(room, pname, Vector3(x - rs.x * PU * 0.5, y, z - rs.z * PU * 0.5), rot, v)


## Wall-mounted prop against a wall face. side: "-x" (left wall, faces +X),
## "+x" (right wall, faces -X), "-z" (back wall, faces +Z), "+z" (faces -Z).
## `along` is the min coordinate along the wall, `face` the wall's inner face.
func _wallput(room: String, pname: String, side: String, face: float, along: float, y: float, v := 0) -> AABB:
	var rs: Vector3i
	match side:
		"-x":
			return _put(room, pname, Vector3(face, y, along), 1, v)
		"+x":
			rs = PropLib.rotated_size(pname, 3, v)
			return _put(room, pname, Vector3(face - rs.x * PU, y, along), 3, v)
		"+z":
			rs = PropLib.rotated_size(pname, 2, v)
			return _put(room, pname, Vector3(along, y, face - rs.z * PU), 2, v)
		_:
			return _put(room, pname, Vector3(along, y, face), 0, v)


## Rug of w x d metres at (x, z) min corner on floor y (PU grid).
func _rug(room: String, x: float, y: float, z: float, w: float, d: float, style: String) -> AABB:
	PropLib.rug(_f(room), Vector3i(pc(x), pc(y), pc(z)), pc(w), pc(d), style)
	return AABB(Vector3(x, y, z), Vector3(w, PU, d))


## Wall sconce with a warm light pool. side as _wallput.
func _sconce(room: String, side: String, face: float, along: float, y: float, energy := 1.7, v := 0, shadow := false) -> void:
	var bb := _wallput(room, "sconce", side, face, along, y, v)
	var c := bb.get_center()
	var out := Vector3.ZERO
	match side:
		"-x": out = Vector3(0.3, 0, 0)
		"+x": out = Vector3(-0.3, 0, 0)
		"+z": out = Vector3(0, 0, -0.3)
		_: out = Vector3(0, 0, 0.3)
	_lamp(c + out + Vector3(0, 0.05, 0), energy, 3.6, 0.25, Color(1.0, 0.64, 0.32), 0.8, shadow)


func _use(bb: AABB, title: String, acts: Array, spot := Vector3.INF) -> Interactable:
	var s := spot if spot != Vector3.INF else bb.get_center() + Vector3(0, -bb.size.y * 0.5, 0)
	var it := Interactable.attach(self, title, acts, Vector3(maxf(bb.size.x, 0.2), maxf(bb.size.y, 0.2), maxf(bb.size.z, 0.2)), bb.get_center(), s)
	it.name = title.replace(" ", "")
	return it


func _lamp(pos: Vector3, energy := 1.0, rng := 3.5, day_factor := 0.25, col := Color(1.0, 0.66, 0.36), halo := 0.9, shadow := false) -> void:
	var l := PropLib.add_light(self, pos, col, energy, rng, day_factor)
	if shadow:
		l.shadow_enabled = true
		l.shadow_bias = 0.06
		l.shadow_normal_bias = 1.5
		l.set_meta("night_shadow", true)
	if halo > 0.0:
		_halo_pts.append({"pos": pos, "size": halo * 1.1, "color": Color(1.0, 0.62, 0.3, 1.0)})


static func _act(id: String, label: String, icon: String, minutes: float, needs := {}, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "icon": icon, "minutes": minutes, "needs": needs}
	d.merge(extra)
	return d


# =================================================================== structure

## Floor plank colour (coarse grid).
func _planks(base: Color, along_x := true) -> Callable:
	return func(q: Vector3i) -> Color:
		var row := q.z if along_x else q.x
		var col := q.x if along_x else q.z
		var r := floori(row / 2.0)
		var off := int(VoxelBuilder.hash3(Vector3i(r, 3, 9)) * 11.0)
		var seg := floori((col + off) / 11.0)
		var tone := 0.9 + VoxelBuilder.hash3(Vector3i(r, seg, 5)) * 0.18
		if posmod(col + off, 11) == 0 or posmod(row, 2) == 0 and VoxelBuilder.hash3(Vector3i(col, r, 1)) > 0.92:
			tone *= 0.86
		return Color(base.r * tone, base.g * tone, base.b * tone)


func _tiles(a: Color, b: Color) -> Callable:
	return func(q: Vector3i) -> Color:
		var c := a if posmod(q.x + q.z, 2) == 0 else b
		var f := 0.96 + VoxelBuilder.hash3(q) * 0.06
		return Color(c.r * f, c.g * f, c.b * f)


func _upper_room(xm: float, zm: float) -> String:
	if xm < -1.0:
		return "office"
	if zm < 0.0:
		return "pink" if xm < 3.5 else "blue"
	return "hall" if xm < 5.5 else "bath"


func _floor_col(room: String) -> Callable:
	match room:
		"office": return _planks(FLOOR_WOOD)
		"pink": return _planks(Color("ddb184"))
		"blue": return _planks(Color("c08a58"), false)
		"hall": return _planks(Color("c4864e"), false)
		"bath": return _tiles(Color("dfe6ea"), Color("aec3cf"))
		"living": return _planks(Color("b9804c"))
		_: return _tiles(Color("efe8da"), Color("d7c7a8"))


func _wall_col(room: String) -> Variant:
	match room:
		"office": return W_OFFICE
		"pink":
			return func(q: Vector3i) -> Color:
				return W_PINK if posmod(q.x + q.z + q.y, 6) != 0 else Color("f9dbe2")
		"blue":
			return func(q: Vector3i) -> Color:
				return Color("f3e7b0") if VoxelBuilder.hash3(q) > 0.985 else W_BLUE
		"hall": return W_HALL
		"bath":
			return func(q: Vector3i) -> Color:
				if posmod(q.y, 24) < 9:
					return Color("cfe0e6") if posmod(q.x + q.z + q.y, 2) == 0 else Color("b5ccd6")
				return Color("e6d7bd") if posmod(q.y, 24) != 9 else Color("b89a6e")
		"living": return W_LIVING
		"kitchen": return W_KITCHEN
		"ext":
			return func(q: Vector3i) -> Color:
				var f := 0.93 if posmod(q.y, 2) == 0 else 1.0
				return Color(SIDING.r * f, SIDING.g * f, SIDING.b * f)
	return W_HALL


func _sig(modes: Dictionary) -> String:
	var parts: Array[String] = []
	var all_same := true
	var first: String = modes.get(VIEWS[0], "low")
	for v: String in VIEWS:
		var m: String = modes.get(v, "low")
		if m != first:
			all_same = false
		parts.append("%s:%s" % [v, m])
	if all_same:
		return "T" if first == "tall" else ("L" if first == "low" else "N")
	return ",".join(parts)


func _mode_for(sig: String, view: String) -> String:
	for kv in sig.split(","):
		var p := kv.split(":")
		if p.size() == 2 and p[0] == view:
			return p[1]
	return "low"


## A wall two coarse cells thick. axis 0 runs along X at z = at, axis 2 along Z
## at x = at (metres, min corner). Rooms: neg (the -Z / -X side) and pos.
## modes: {view: "tall"|"low"|"none"}; holes: [[a0, a1, y0, y1]] metres.
func _wall(axis: int, at: float, from: float, to: float, floor_i: int, neg: String, pos: String, modes: Dictionary, holes := []) -> void:
	var sig := _sig(modes)
	if sig == "N":
		return
	var c0 := cc(at)
	var a0 := cc(from)
	var a1 := cc(to)
	var y_base := 0 if floor_i == 0 else 24
	var hgt := 22 if floor_i == 0 else UH
	var cneg = _wall_col(neg)
	var cpos = _wall_col(pos)
	for a in range(a0, a1):
		for ry in hgt:
			var am := (a + 0.5) / 8.0
			var ym := (ry + 0.5) / 8.0
			var hole := false
			for hdef in holes:
				if am > hdef[0] and am < hdef[1] and ym > hdef[2] and ym < hdef[3]:
					hole = true
					break
			for k in 2:
				var q := Vector3i(a, y_base + ry, c0 + k) if axis == 0 else Vector3i(c0 + k, y_base + ry, a)
				var side := neg if k == 0 else pos
				var cv = cneg if k == 0 else cpos
				var col: Color = cv.call(q) if cv is Callable else cv
				if side != "ext" and side != "bath" and ry >= 1 and ry <= 6:
					col = _wainscot(side, a, ry)
				elif side != "ext" and side != "bath" and ry == 7:
					col = Color("9a6a40")
				if ry == 0 and side != "ext":
					col = Color("7a4e2e") if side != "bath" else Color("c9d3da")
				elif ry == 0:
					col = FOUND
				if ry == hgt - 1:
					col = CAP
				elif ry == hgt - 2 and side != "ext":
					col = col.lerp(TRIM, 0.5)
				var part := "base"
				if sig == "T":
					part = "base"
				elif sig == "L":
					if ry > 5:
						continue
					if ry == 5:
						col = CAP
				else:
					if ry == 5:
						# Duplicate the row: cap for low mode, wall for tall mode.
						if not hole:
							_sgroup(_zone(q), sig, "cap").set_v(q, CAP)
						part = "upper"
					elif ry > 5:
						part = "upper"
				if hole:
					continue
				var g := "static" if (sig == "T" or sig == "L") else sig
				_sgroup(_zone(q), g, part if g != "static" else "s").set_v(q, col)


## Panelled wainscot colour for the lower wall (interior sides).
func _wainscot(room: String, a: int, ry: int) -> Color:
	var base: Color
	match room:
		"pink": base = Color("fbf1ee")
		"blue": base = Color("5d72b8")
		"office": base = Color("ecdcc0")
		"living": base = Color("e2d0b0")
		"kitchen": base = Color("f1ece2")
		_: base = Color("f3e6cf")
	if ry == 6 or posmod(a, 6) == 0:
		return base.darkened(0.08)
	return base


func _build_structure() -> void:
	# ---- Ground floor slab (y cell -1) and foundation lip.
	for x in range(cc(-9), cc(9)):
		for z in range(cc(-5), cc(5)):
			var xm := (x + 0.5) / 8.0
			var room := "living" if xm < -1.0 else "kitchen"
			_sgroup(_zone(Vector3i(x, -1, z)), "static", "s").set_v(Vector3i(x, -1, z), _floor_col(room).call(Vector3i(x, -1, z)))
	for x in range(cc(-9) - 1, cc(9) + 1):
		for z in [cc(-5) - 1, cc(5)]:
			_sgroup(_zone(Vector3i(x, -1, z)), "static", "s").set_v(Vector3i(x, -1, z), FOUND)
	for z in range(cc(-5) - 1, cc(5) + 1):
		for x in [cc(-9) - 1, cc(9)]:
			_sgroup(_zone(Vector3i(x, -1, z)), "static", "s").set_v(Vector3i(x, -1, z), FOUND)
	# ---- Upstairs slab (cells 22, 23) with the balcony void and the stair well.
	for x in range(cc(-9), cc(9)):
		for z in range(cc(-5), cc(5)):
			var xm := (x + 0.5) / 8.0
			var zm := (z + 0.5) / 8.0
			var in_void := xm > -8.75 and xm < -4.5 and zm > 1.5 and zm < 4.75
			var in_stair := xm > 3.0 and xm < 5.25 and zm > 1.75 and zm < 4.75
			if in_void or in_stair:
				continue
			var room := _upper_room(xm, zm)
			var edge := x == cc(-9) or x == cc(9) - 1 or z == cc(-5) or z == cc(5) - 1
			var g := _sgroup(_zone(Vector3i(x, 22, z)), "static", "s")
			g.set_v(Vector3i(x, 22, z), TRIM if edge else Color("efe9df"))
			g.set_v(Vector3i(x, 23, z), TRIM if edge else _floor_col(room).call(Vector3i(x, 23, z)))
	# Void rim trim (wood fascia).
	for x in range(cc(-8.75), cc(-4.5)):
		_sgroup(_zone(Vector3i(x, 22, 1)), "static", "s").set_v(Vector3i(x, 22, cc(1.5) - 1), Color("8a5a36"))
	for z in range(cc(1.5), cc(4.75)):
		_sgroup(_zone(Vector3i(cc(-4.5), 22, 1)), "static", "s").set_v(Vector3i(cc(-4.5), 22, z), Color("8a5a36"))

	var both_tall := {"office": "tall", "bed": "tall"}
	var both_low := {"office": "low", "bed": "low"}
	var win_hi := [1.0, 2.3]
	# ---- Ground floor walls.
	_wall(0, -5.0, -9, 9, 0, "ext", "living", both_tall, [[-7.0, -5.0, 1.0, 2.2], [-3.5, -2.0, 1.0, 2.2]])
	_wall(0, -5.0, -1, 9, 0, "ext", "kitchen", both_tall, [[1.0, 3.0, 1.1, 2.1], [5.0, 7.0, 1.1, 2.1]])
	_wall(2, -9.0, -5, 5, 0, "ext", "living", both_tall, [[-3.0, -1.0, 1.0, 2.2]])
	_wall(2, 8.75, -5, 5, 0, "kitchen", "ext", both_tall, [[-3.5, -1.5, 1.0, 2.2], [1.0, 3.0, 1.0, 2.2]])
	# Front ground-floor walls are always cut (dollhouse view into the ground
	# floor under the upstairs slab, like the lower level in ref1/ref3).
	# Night (bed view) shows them as a lit facade below the cut-away upstairs (ref3).
	var front_modes := {"office": "low", "bed": "tall"}
	var fh := []
	for w: Array in FRONT_WINDOWS:
		fh.append([w[0], w[1], 0.9, 2.1])
	_wall(0, 4.75, -9, -1, 0, "living", "ext", front_modes, fh)
	_wall(0, 4.75, -1, 8.75, 0, "kitchen", "ext", front_modes, fh + [[0.5, 1.6, 0.0, 2.1]])
	_wall(2, -1.0, -5, 5, 0, "living", "kitchen", both_tall, [[-1.0, 1.5, 0.0, 2.2]])
	# ---- Upstairs walls.
	# Back exterior wall: big office windows, bedroom windows.
	var back_holes := [[-5.85, -3.95, 0.45, 2.55], [-3.75, -1.85, 0.45, 2.55], [1.85, 3.15, 0.9, 2.2], [6.4, 7.8, 0.9, 2.2]]
	_wall(0, -5.0, -9, -1, 1, "ext", "office", both_tall, back_holes)
	_wall(0, -5.0, -1, 3.5, 1, "ext", "pink", both_tall, back_holes)
	_wall(0, -5.0, 3.5, 9, 1, "ext", "blue", both_tall, back_holes)
	# Left exterior (office L wall).
	_wall(2, -9.0, -4.75, 5, 1, "ext", "office", both_tall, [[2.0, 3.6, 0.9, 2.3]])
	# Front exterior: always cut.
	_wall(0, 4.75, -9, -4.5, 1, "office", "ext", {"office": "none", "bed": "low"})
	_wall(0, 4.75, -4.5, 9, 1, "office", "ext", both_low)
	# Right exterior.
	var bed_tall := {"office": "low", "bed": "tall"}
	_wall(2, 8.75, -4.75, 0.0, 1, "blue", "ext", bed_tall)
	_wall(2, 8.75, 0.0, 4.75, 1, "bath", "ext", bed_tall, [[2.6, 4.2, 1.0, 2.3]])
	# Office | pink+hall divider (low from the office, tall for the bedrooms).
	_wall(2, -1.0, -4.75, 0.0, 1, "office", "pink", {"office": "low", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	_wall(2, -1.0, 0.0, 4.75, 1, "office", "hall", {"office": "low", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	# Bedroom fronts onto the hall.
	_wall(0, 0.0, -0.75, 5.5, 1, "pink", "hall", both_low, [[2.3, 3.2, 0.0, 2.1], [4.2, 5.2, 0.0, 2.1]])
	_wall(0, 0.0, 5.5, 8.75, 1, "blue", "bath", both_low)
	# Pink | blue divider, hall | bath divider.
	# Low in both views: the camera looks in from the +x side, so a tall
	# divider would hide the bedside story scene behind it.
	_wall(2, 3.5, -4.75, 0.0, 1, "pink", "blue", both_low)
	_wall(2, 5.5, 0.25, 4.75, 1, "hall", "bath", {"office": "low", "bed": "tall"}, [[3.4, 4.4, 0.0, 2.1]])


# =================================================================== rooms
# Furniture is placed on the PU grid (1.25 x the authoring cell) so it reads at
# the chunky, chibi scale of the reference shots. Heights stacked on furniture
# tops use N * PU (N = the model's top in cells: desk 12, nightstand 10,
# dresser 14, side table 11, counter 15, shelf 30).

var _spots := {}     # staging spots computed while building (actor poses)


func _windows_upstairs() -> void:
	# Office big windows (back wall, two units).
	for wx: float in [-5.85, -3.75]:
		PropLib.window_frame(_g("office"), Vector3i(fc(wx), fc(UF + 0.45), fc(-5.0)), fc(1.9), fc(2.1), 4, 0, 3, 1)
	PropLib.window_frame(_g("office"), Vector3i(fc(-9.0), fc(UF + 0.9), fc(2.0)), fc(1.6), fc(1.4), 4, 2, 2, 1)
	PropLib.window_frame(_g("pink"), Vector3i(fc(1.85), fc(UF + 0.9), fc(-5.0)), fc(1.3), fc(1.3), 4, 0, 2, 1, Color("ffffff"), Color("f3c0cf"))
	PropLib.window_frame(_g("blue"), Vector3i(fc(6.4), fc(UF + 0.9), fc(-5.0)), fc(1.4), fc(1.3), 4, 0, 2, 1)
	PropLib.window_frame(_g("bath"), Vector3i(fc(8.75), fc(UF + 1.0), fc(2.6)), fc(1.6), fc(1.3), 4, 2, 2, -1)
	# Glass: bright sky panes by day (the light source of ref1's window wall),
	# deep night-blue panes after dark. Two merged meshes, toggled by time.
	_up_glass("office", 0, -5.0, -5.85, -3.95, UF + 0.45, UF + 2.55)
	_up_glass("office", 0, -5.0, -3.75, -1.85, UF + 0.45, UF + 2.55)
	_up_glass("office", 2, -9.0, 2.0, 3.6, UF + 0.9, UF + 2.3)
	_up_glass("pink", 0, -5.0, 1.85, 3.15, UF + 0.9, UF + 2.2)
	_up_glass("blue", 0, -5.0, 6.4, 7.8, UF + 0.9, UF + 2.2)
	_up_glass("bath", 2, 8.75, 2.6, 4.2, UF + 1.0, UF + 2.3)


var _upg_day := VoxelBuilder.new()
var _upg_night := VoxelBuilder.new()


## Fill a window opening's mid plane with glass cells (skipping the frame's
## mullions so nothing z-fights). axis 0: wall along X at z = at; 2: along Z at x = at.
func _up_glass(room: String, axis: int, at: float, a0: float, a1: float, y0: float, y1: float) -> void:
	var fr := _g(room)
	var mid := fc(at) + 2
	for a in range(fc(a0), fc(a1)):
		for yy in range(fc(y0), fc(y1)):
			var q := Vector3i(a, yy, mid) if axis == 0 else Vector3i(mid, yy, a)
			if fr.has(q):
				continue
			var t := float(yy - fc(y0)) / maxf(1.0, float(fc(y1) - fc(y0)))
			var h := VoxelBuilder.hash3(q)
			var day := Color("bfe0f2").lerp(Color("f2fbff"), t)
			if h > 0.93:
				day = Color("ffffff")
			_upg_day.set_v(q, day, true)
			var night := Color("1b2550").lerp(Color("2a3a74"), 1.0 - t)
			if h > 0.985:
				night = Color("e8ecff")
			_upg_night.set_v(q, night, true)


func _build_office() -> void:
	var R := "office"
	var y := UF
	var fx := -8.75   # inner face of the L wall
	var bz := -4.75   # inner face of the back wall
	var rx := -1.0    # inner face of the divider (pink/hall side)
	_windows_upstairs()
	# --- Work corner on the back wall (ref1: desk with two bright monitors,
	# laptop, mug, black office chair; cork board with notes above). Dad sits
	# with his back half to the camera so the screens read over his shoulder.
	var desk := _put(R, "desk", Vector3(fx + 0.07, y, bz + 0.02), 0)
	var dy := y + 12 * PU
	_put(R, "monitor", Vector3(desk.position.x + 0.32, dy, bz + 0.06), 0, 0)
	_put(R, "monitor", Vector3(desk.position.x + 1.55, dy, bz + 0.1), 0, 1)
	_put(R, "keyboard", Vector3(desk.position.x + 0.55, dy, bz + 0.62))
	_put(R, "laptop", Vector3(desk.end.x - 0.78, dy, bz + 0.38))
	_put(R, "mug", Vector3(desk.position.x + 0.06, dy, bz + 0.72), 0, 0)
	_put(R, "pencil_cup", Vector3(desk.position.x + 0.05, dy, bz + 0.12))
	_put(R, "book_stack", Vector3(desk.end.x - 0.45, dy, bz + 0.06), 0, 1)
	var chair := _putc(R, "office_chair", desk.get_center().x - 0.05, y, desk.end.z + 0.42, 2)
	_wallput(R, "corkboard", "-z", bz, desk.position.x + 0.2, y + 1.4, 0)
	_wallput(R, "wall_clock", "-z", bz, desk.end.x - 0.55, y + 2.55, 1)
	_lamp(Vector3(desk.get_center().x, y + 1.7, desk.end.z + 0.2), 0.6, 2.6, 0.35, Color(0.75, 0.85, 1.0), 0.0)
	# --- Left wall: filing cabinet + printer, tall shelves (globe, trophy, books),
	# a big landscape picture, plants.
	_put(R, "filing_cabinet", Vector3(fx, y, desk.end.z + 0.12), 1)
	_put(R, "printer", Vector3(fx + 0.02, y + 12 * PU, desk.end.z + 0.16), 1)
	_wallput(R, "frame", "-x", fx, desk.end.z + 0.05, y + 1.55, 0)
	_wallput(R, "bookshelf", "-x", fx, -2.55, y, 4)
	_wallput(R, "bookshelf", "-x", fx, -1.05, y, 2)
	_put(R, "trophy", Vector3(fx + 0.1, y + 30 * PU, -2.2))
	_put(R, "plant", Vector3(fx + 0.06, y + 30 * PU, -0.85), 0, 2)
	_put(R, "plant", Vector3(fx + 0.04, y, 0.55), 0, 5)
	_sconce(R, "-x", fx, 0.2, y + 1.7, 1.2)
	_wallput(R, "frame", "-x", fx, 0.55, y + 1.25, 6)
	# --- Window wall: two big multi-pane windows, curtains, sill plants, ivy.
	for cx: float in [-6.1, -3.82, -1.7]:
		_put(R, "curtain", Vector3(cx, y, bz + 0.02), 0, 3 if cx < -5.0 else 0)
	for wx: float in [-5.7, -3.6]:
		_put(R, "plant", Vector3(wx + 0.1, y + 0.45, bz - 0.04), 0, 3)
		_put(R, "plant", Vector3(wx + 1.3, y + 0.45, bz - 0.04), 0, 6)
		_put(R, "ivy", Vector3(wx + 0.05, y + 1.35, bz + 0.03), 0, 2)
	_put(R, "hanging_plant", Vector3(-3.95, y + 2.25, bz + 0.15), 0, 1)
	# --- Art corner: easel by the first window, canvas angled to the camera.
	_rug(R, -6.1, y, -3.95, 2.9, 2.2, "patch_pink")
	var easel_mi := PropLib.instance("easel", 0)
	easel_mi.scale = Vector3.ONE * (PU / PropLib.FU)
	easel_mi.position = Vector3(-4.45, y, -3.7)
	easel_mi.rotation_degrees.y = 24.0
	add_child(easel_mi)
	var easel := AABB(Vector3(-5.05, y, -4.25), Vector3(1.2, 2.4, 1.1))
	var stool := _putc(R, "stool", -5.55, y, -2.85, 0, 1)
	var ptable := _putc(R, "side_table", -3.55, y, -2.7, 0, 1)
	_put(R, "pencil_cup", Vector3(-3.7, y + 11 * PU, -2.8))
	# --- Music corner: keyboard piano under the second window, guitar beside it.
	var piano := _putc(R, "piano", -2.6, y, bz + 0.4, 0)
	var bench := _putc(R, "piano_bench", -2.6, y, -3.55, 0)
	var guitar := _put(R, "guitar", Vector3(-1.85, y, -3.05), 0)
	_put(R, "plant", Vector3(-1.62, y, bz + 0.05), 0, 1)
	_wallput(R, "frame", "+x", rx, -4.3, y + 1.75, 3)
	_lamp(Vector3(-2.6, y + 2.2, bz + 0.6), 0.8, 3.0, 0.45)
	# --- Right side along the low divider: cube storage + plants.
	_wallput(R, "bookshelf", "+x", rx, -2.2, y, 3)
	_put(R, "plant", Vector3(-1.5, y + 18 * PU, -2.1), 0, 0)
	_put(R, "plant", Vector3(-1.5, y + 18 * PU, -1.4), 0, 6)
	# --- Play area (dog + cat girl), pulled in front of the work/art/music
	# corners so the ref1 framing shows them all with breathing room.
	_rug(R, -7.4, y, -1.9, 3.0, 2.5, "check_blue")
	_rug(R, -3.9, y, -1.75, 2.6, 2.6, "blue_braid")
	var ball := _put(R, "tennis_ball", Vector3(-4.35, y + PU, -0.85))
	var dogbed := _putc(R, "dog_bed", -5.55, y, 0.35, 0)
	var toybox := _wallput(R, "toy_box", "+x", rx, -0.95, y)
	_put(R, "soccer_ball", Vector3(-1.75, y + PU, 0.35))
	_put(R, "toy_blocks", Vector3(-2.85, y + PU, -0.55), 0, 1)
	_put(R, "toy_robot", Vector3(-2.35, y + PU, -1.15), 1)
	_put(R, "toy_blocks", Vector3(-2.2, y + PU, 0.35), 0, 0)
	_put(R, "plush", Vector3(-1.55, y + PU, -1.35), 3, 1)
	_put(R, "plant", Vector3(-1.55, y, 4.15), 0, 4)
	_put(R, "plant", Vector3(-4.3, y, 4.1), 0, 4)
	_put(R, "toy_blocks", Vector3(-2.75, y, 3.05), 0, 0)
	# --- Balcony railing over the living room, with trailing planters on it.
	PropLib.railing(_g(R), Vector3i(fc(-8.75), fc(y), fc(1.5) - 2), fc(4.25) + 2, 0, 16)
	PropLib.railing(_g(R), Vector3i(fc(-4.5), fc(y), fc(1.5) - 2), fc(3.25) + 2, 2, 16)
	for k in 2:
		_put(R, "plant", Vector3(-8.4 + k * 1.6, y + 17 * U, 1.3), 0, [2, 6][k])
	_put(R, "plant", Vector3(-4.68, y + 17 * U, 3.2), 0, 2)
	_spots["office_chair"] = chair
	_spots["desk"] = desk
	_spots["stool"] = stool
	_spots["easel"] = easel
	_spots["ball"] = ball

	# --- Interactables.
	_use(desk, "Computer", [
		_act("work", "Work", "laptop", 120, {"fun": -0.1, "energy": -0.15}, {"skill": "Logic", "pose": "type", "money": 180, "who": ["adult"]}),
		_act("emails", "Answer Emails", "email", 30, {"fun": -0.03}, {"pose": "type", "task": "Answer Emails", "who": ["adult", "child"]}),
		_act("games", "Play Games", "gamepad", 60, {"fun": 0.3}, {"pose": "type", "who": ["adult", "child"]}),
		_act("homework", "Do Homework", "book", 45, {"fun": -0.05}, {"pose": "type", "task": "Do Homework", "who": ["child"]}),
		_act("bills", "Pay Bills", "bill", 15, {}, {"pose": "type", "money": -120, "task": "Pay Bills", "who": ["adult"]}),
	], chair.get_center() - Vector3(0, chair.size.y * 0.5, 0))
	_use(easel, "Easel", [
		_act("paint", "Paint", "palette", 60, {"fun": 0.2}, {"skill": "Creativity", "pose": "sit_paint", "task": "Practice Creativity"}),
	], stool.get_center() - Vector3(0, stool.size.y * 0.5, 0))
	_use(piano, "Piano", [
		_act("practice", "Practice", "music", 45, {"fun": 0.15}, {"skill": "Music", "pose": "sit_type", "task": "Build Skill"}),
		_act("play_song", "Play a Song", "piano", 20, {"fun": 0.2, "social": 0.05}, {"skill": "Music", "pose": "sit_type"}),
	], bench.get_center() - Vector3(0, bench.size.y * 0.5, 0))
	_use(guitar, "Guitar", [_act("practice_guitar", "Practice", "guitar", 45, {"fun": 0.15}, {"skill": "Music", "pose": "play"})])
	_use(toybox, "Toy Box", [
		_act("play_toys", "Play", "toys", 40, {"fun": 0.3}, {"pose": "play", "who": ["child"]}),
		_act("tidy", "Tidy Toys", "broom", 15, {"fun": -0.05}, {"pose": "play", "task": "Tidy Toys"}),
	], Vector3(-1.9, y, -0.5))
	_use(dogbed, "Dog Bed", [
		_act("nap", "Nap", "zzz", 60, {"energy": 0.4}, {"pose": "sleep", "who": ["dog"]}),
		_act("pet", "Pet Dog", "paw", 10, {"social": 0.1, "fun": 0.1}, {"pose": "talk", "who": ["adult", "child"]}),
	])
	_use(ball, "Ball", [_act("fetch", "Play Fetch", "ball", 20, {"fun": 0.3}, {"pose": "play", "task": "Play with Dog"})])
	_use(ptable, "Art Supplies", [_act("tidy_art", "Tidy Up", "broom", 10, {})])


func _build_living() -> void:
	var R := "living"
	var fx := -8.75
	# Library wall: the part of the living room you look down on through the
	# balcony void upstairs (ref1's lower floor: shelves, glowing lamps, sofa).
	_wallput(R, "bookshelf", "-x", fx, 1.55, 0, 0)
	_put(R, "nightstand", Vector3(fx + 0.02, 0, 2.85), 1, 0)
	_put(R, "lamp_table", Vector3(fx + 0.12, 10 * PU, 2.95), 0, 0)
	_lamp(Vector3(fx + 0.5, 1.15, 3.2), 1.3, 3.4, 0.8)
	_put(R, "plant", Vector3(fx + 0.12, 10 * PU, 3.35), 0, 3)
	_wallput(R, "frame", "-x", fx, 2.75, 1.35, 7)
	_wallput(R, "frame", "-x", fx, 3.55, 1.6, 2)
	_wallput(R, "bookshelf", "-x", fx, 3.75, 0, 2)
	_put(R, "globe", Vector3(fx + 0.12, 30 * PU, 3.9))
	_sconce(R, "-x", fx, 1.05, 1.6, 1.3)
	_put(R, "plant", Vector3(fx + 0.05, 0, 0.55), 0, 5)
	_rug(R, -8.0, 0, 1.6, 3.0, 2.9, "red_kilim")
	_put(R, "coffee_table", Vector3(-7.35, PU, 2.25), 1)
	_put(R, "book_stack", Vector3(-7.1, PU + 8 * PU, 2.6), 0, 1)
	_put(R, "mug", Vector3(-7.0, PU + 8 * PU, 3.2), 0, 1)
	var sofa := _put(R, "sofa", Vector3(-6.25, 0, 1.75), 3, 0)
	_put(R, "armchair", Vector3(-7.9, 0, 4.0), 2, 0)
	_put(R, "lamp_floor", Vector3(-5.05, 0, 4.15))
	_lamp(Vector3(-4.8, 2.05, 4.4), 1.2, 3.4, 0.6)
	_put(R, "plant", Vector3(-5.05, 0, 1.6), 0, 1)
	_wallput(R, "bookshelf", "+z", 4.75, -6.6, 0, 1)
	_put(R, "plant", Vector3(-6.4, 12 * PU, 4.25), 0, 6)
	# Under the slab (seen through the front cutaway).
	_wallput(R, "bookshelf", "-x", fx, -2.4, 0, 0)
	_put(R, "nightstand", Vector3(fx + 0.02, 0, -0.95), 1, 0)
	_put(R, "lamp_table", Vector3(fx + 0.12, 10 * PU, -0.85), 0, 0)
	_lamp(Vector3(fx + 0.5, 1.15, -0.6), 0.9, 3.0, 0.5)
	_wallput(R, "tv", "-z", -4.75, -3.6, 0)
	_put(R, "sofa", Vector3(-4.6, 0, -1.6), 2, 2)
	_put(R, "dining_table", Vector3(-8.0, 0, -4.0), 0)
	_use(sofa, "Sofa", [
		_act("relax", "Relax", "sofa", 30, {"energy": 0.1, "fun": 0.05}, {"pose": "sit"}),
		_act("nap_sofa", "Nap", "zzz", 60, {"energy": 0.3}, {"pose": "sleep"}),
	])
	_use(AABB(Vector3(-3.6, 0, -4.75), Vector3(2.2, 1.8, 0.7)), "TV", [
		_act("watch", "Watch TV", "tv", 60, {"fun": 0.25}, {"pose": "sit"}),
	], Vector3(-2.5, 0, -2.0))


func _build_pink() -> void:
	var R := "pink"
	var y := UF
	var fx := -0.75   # left wall face (divider with the office)
	var bz := -4.75
	var rx := 3.5     # right wall face (divider with the blue room)
	# ref3 layout: bunny bed with its headboard on the back wall and the quilt
	# running towards the camera, so the tucked-in girl's face reads; dad's
	# reading chair beside the bed (right side) in the open, turned to the
	# camera. Tall pieces stay on the back/left walls so nothing in the front
	# right corner (the camera side) hides the story scene.
	_rug(R, -0.3, y, -3.2, 3.5, 2.9, "patch_pink")
	var ns := _put(R, "nightstand", Vector3(fx + 0.04, y, bz + 0.04), 0, 2)
	var bed := _put(R, "bed", Vector3(ns.end.x + 0.06, y, bz + 0.02), 0, 0)
	_put(R, "lamp_table", Vector3(ns.position.x + 0.12, y + 10 * PU, ns.position.z + 0.1), 0, 1)
	_lamp(Vector3(ns.get_center().x + 0.25, y + 1.3, ns.end.z + 0.3), 0.55, 3.2, 0.2, Color(1.0, 0.6, 0.3), 0.55, true)
	_put(R, "plush", Vector3(bed.end.x - 0.55, y + 10 * PU, bz + 0.3), 0, 0)
	var chair := _putc(R, "chair", bed.end.x + 0.55, y, bed.position.z + 1.55, 3, 2)
	var st := _put(R, "side_table", Vector3(bed.end.x + 0.12, y, bz + 0.08), 0, 2)
	_put(R, "lamp_table", Vector3(st.position.x + 0.05, y + 11 * PU, bz + 0.12), 0, 1)
	_put(R, "book_stack", Vector3(st.end.x - 0.4, y + 11 * PU, bz + 0.2), 0, 2)
	_spots["pink_bed"] = bed
	_spots["pink_chair"] = chair
	# Back wall: bunny pictures above the headboard, window with pink curtains.
	_wallput(R, "frame", "-z", bz, bed.position.x + 0.1, y + 2.1, 2)
	_wallput(R, "frame", "-z", bz, bed.position.x + 0.95, y + 2.3, 5)
	_put(R, "curtain", Vector3(1.6, y, bz + 0.02), 0, 1)
	_put(R, "curtain", Vector3(3.2 - 5 * PU, y, bz + 0.02), 0, 1)
	_put(R, "plant", Vector3(2.05, y + 0.9, bz - 0.04), 0, 6)
	_put(R, "plant", Vector3(2.6, y + 0.9, bz - 0.04), 0, 3)
	_put(R, "hanging_plant", Vector3(2.3, y + 1.95, bz + 0.1), 0, 2)
	# Left wall: plush/book shelves, frames, sconce, toy box + plushies on the floor.
	_wallput(R + "@bed", "shelf_unit", "-x", fx, -3.15, y + 1.3, 0)
	_wallput(R + "@bed", "wall_shelf", "-x", fx, -1.6, y + 2.15, 2)
	_wallput(R + "@bed", "frame", "-x", fx, -1.55, y + 1.3, 2)
	_sconce(R + "@bed", "-x", fx, -2.0, y + 1.85, 0.6)
	var toybox := _wallput(R, "toy_box", "-x", fx, -1.2, y)
	_put(R, "plush", Vector3(fx + 0.15, y + 9 * PU, -0.95), 1, 1)
	_put(R, "plant", Vector3(fx + 0.06, y, -2.05), 0, 0)
	# Right wall (pink|blue divider): dresser + lamp at the back, mirror and
	# frames above, a wall planter and a sconce; only low pieces at the front.
	var dr := _wallput(R, "dresser", "+x", rx, -4.7, y, 2)
	_put(R, "plant", Vector3(dr.position.x + 0.12, y + 14 * PU, dr.position.z + 0.08), 0, 6)
	_put(R, "plush", Vector3(dr.position.x + 0.1, y + 14 * PU, dr.end.z - 0.45), 3, 2)
	_put(R, "lamp_table", Vector3(dr.position.x + 0.12, y + 14 * PU, dr.end.z - 1.0), 0, 1)
	_lamp(Vector3(dr.position.x - 0.1, y + 1.75, dr.end.z - 0.7), 0.5, 3.0, 0.2, Color(1.0, 0.62, 0.34), 0.5)
	_sconce(R, "-z", bz, 2.55 - 0.2, y + 2.5, 0.0)
	_lamp(Vector3(1.4, y + 2.3, -2.0), 0.35, 4.0, 0.0, Color(1.0, 0.62, 0.36), 0.0)
	# Floor: pouf, blocks, small plants in the front corners.
	_put(R, "pouf", Vector3(1.25, y, -1.1), 0, 0)
	_put(R, "toy_blocks", Vector3(0.35, y + PU, -1.0), 0, 3)
	_put(R, "plant", Vector3(rx - 0.5, y, -0.62), 0, 3)
	_put(R, "basket", Vector3(2.2, y, -0.75), 0, 1)
	_use(toybox, "Pink Toy Box", [
		_act("play_toys", "Play", "toys", 40, {"fun": 0.3}, {"pose": "play", "who": ["child"]}),
		_act("tidy", "Tidy Toys", "broom", 15, {"fun": -0.05}, {"pose": "play", "task": "Tidy Toys"}),
	])
	_use(bed, "Pink Bed", [
		_act("sleep", "Sleep", "bed", 480, {"energy": 1.0}, {"pose": "sleep", "task": "Go to Sleep"}),
		_act("story", "Read Story", "book_open", 20, {"social": 0.2, "fun": 0.1}, {"pose": "sit_read", "task": "Read Story", "who": ["adult"]}),
		_act("nap", "Nap", "zzz", 60, {"energy": 0.3}, {"pose": "sleep"}),
	], chair.get_center() - Vector3(0, chair.size.y * 0.5, 0))
	_use(ns, "Nightstand", [_act("read_book", "Read a Book", "book", 30, {"fun": 0.1}, {"pose": "sit_read"})], chair.get_center() - Vector3(0, chair.size.y * 0.5, 0))


func _build_blue() -> void:
	var R := "blue"
	var y := UF
	var bz := -4.75
	var lx := 3.75    # left wall face
	var rx := 8.75    # right exterior wall face
	_rug(R, 4.2, y, -2.75, 2.6, 2.2, "round_blue")
	# Star bed in the middle of the back wall (clear of the pink|blue divider so
	# it reads from the ref3 camera), nightstand + rocket lamp on its left.
	var ns := _put(R, "nightstand", Vector3(lx + 0.05, y, bz + 0.05), 0, 3)
	var bed := _put(R, "bed", Vector3(ns.end.x + 0.08, y, bz + 0.02), 0, 1)
	_put(R, "rocket_lamp", Vector3(ns.position.x + 0.06, y + 10 * PU, bz + 0.15), 0)
	_put(R, "lamp_table", Vector3(ns.position.x + 0.3, y + 10 * PU, bz + 0.1), 0, 2)
	_lamp(Vector3(ns.get_center().x + 0.1, y + 1.25, bz + 0.6), 1.7, 3.6, 0.2, Color(1.0, 0.72, 0.44))
	_put(R, "plush", Vector3(bed.position.x + 0.25, y + 10 * PU, bz + 0.35), 0, 1)
	_wallput(R, "frame", "-z", bz, 4.55, y + 2.2, 4)
	_wallput(R, "frame", "-z", bz, 5.45, y + 2.3, 8)
	PropLib.string_lights(_g(R), Vector3i(fc(lx + 0.1), fc(y + 2.9), fc(bz) + 1), Vector3i(fc(rx - 0.1), fc(y + 2.9), fc(bz) + 1), 8, 4.0, true)
	_put(R, "curtain", Vector3(6.22, y, bz + 0.02), 0, 2)
	_put(R, "curtain", Vector3(7.82, y, bz + 0.02), 0, 2)
	_put(R, "telescope", Vector3(7.2, y, -4.1), 3)
	_put(R, "plant", Vector3(8.15, y, bz + 0.05), 0, 4)
	# Right wall: kid desk with lamp, globe and books; shelf unit above.
	var desk := _wallput(R, "desk", "+x", rx, -3.0, y, 1)
	_put(R, "globe", Vector3(rx - 0.45, y + 10 * PU, -2.85))
	_put(R, "book_stack", Vector3(rx - 0.55, y + 10 * PU, -2.25), 1, 2)
	_put(R, "lamp_table", Vector3(rx - 0.5, y + 10 * PU, -2.0), 0, 2)
	_lamp(Vector3(rx - 0.6, y + 1.35, -1.85), 1.1, 3.0, 0.2)
	_put(R, "chair", Vector3(desk.position.x - 0.6, y, -2.75), 1, 3)
	_wallput(R + "@bed", "shelf_unit", "+x", rx, -3.0, y + 1.5, 1)
	_sconce(R + "@bed", "+x", rx, -1.0, y + 1.7, 1.5)
	# Left wall: bookshelf, poster, wall shelf.
	_wallput(R, "bookshelf", "-x", lx, -1.55, y, 0)
	_put(R, "plush", Vector3(5.1, y + PU, -1.3), 0, 1)
	_rug(R, 5.9, y, -2.8, 1.9, 1.8, "star")
	_put(R, "toy_blocks", Vector3(6.3, y + PU, -2.2), 0, 1)
	_put(R, "beanbag", Vector3(6.9, y, -1.15), 2, 1)
	_put(R, "plant", Vector3(rx - 0.6, y, -0.65), 0, 1)
	_lamp(Vector3(6.2, y + 2.5, -2.2), 1.3, 4.4, 0.0, Color(1.0, 0.74, 0.46), 0.0)
	_use(bed, "Star Bed", [
		_act("sleep", "Sleep", "bed", 480, {"energy": 1.0}, {"pose": "sleep", "task": "Go to Sleep"}),
		_act("story", "Read Story", "book_open", 20, {"social": 0.2}, {"pose": "sit_read", "who": ["adult"]}),
	])
	_use(AABB(Vector3(7.2, y, -4.1), Vector3(0.8, 1.6, 0.6)), "Telescope", [
		_act("stargaze", "Stargaze", "star", 30, {"fun": 0.2}, {"skill": "Logic", "pose": "idle"}),
	])
	_use(desk, "Kid Desk", [
		_act("homework_desk", "Do Homework", "book", 45, {"fun": -0.05}, {"pose": "sit_type", "task": "Do Homework", "who": ["child"]}),
	], Vector3(desk.position.x - 0.3, y, desk.get_center().z))


func _build_hall() -> void:
	var R := "hall"
	var y := UF
	var lx := -0.75
	# Stairs down to the kitchen (in the stair well x 3..5.25, z 1.75..4.75).
	var st := _g(R)
	for k in 16:
		var z0 := fc(1.75) + k * 3
		var top := fc(UF) - k * 3
		for x in range(fc(3.1), fc(4.4)):
			for yy in range(maxi(top - 3, 0), top):
				for zz in 3:
					st.set_v(Vector3i(x, yy, z0 + zz), Color("b07a46") if yy == top - 1 else Color("efe7da"))
	PropLib.railing(st, Vector3i(fc(3.0), fc(y), fc(1.75) - 2), fc(2.25), 0, 16)
	PropLib.railing(st, Vector3i(fc(5.25) - 2, fc(y), fc(1.75) - 2), fc(3.0), 2, 16)
	PropLib.railing(st, Vector3i(fc(3.0) - 2, fc(y), fc(1.75)), fc(3.0), 2, 16)
	# Dog cushion on a round rug, bowl, laundry basket.
	_rug(R, 0.4, y, 1.4, 2.2, 2.2, "round_cream")
	var cushion := _putc(R, "dog_cushion", 1.5, y, 2.5)
	_spots["dog_cushion"] = cushion
	_put(R, "dog_bowl", Vector3(2.15, y, 0.4))
	_put(R, "basket", Vector3(2.55, y, 3.95), 0, 0)
	# Left wall: bookshelf with lamp, console, frames, sconces.
	_wallput(R, "bookshelf", "-x", lx, 0.4, y, 1)
	_put(R, "lamp_table", Vector3(lx + 0.12, y + 12 * PU, 0.55), 0, 0)
	_put(R, "plant", Vector3(lx + 0.12, y + 12 * PU, 1.0), 0, 6)
	_lamp(Vector3(lx + 0.5, y + 1.25, 0.8), 1.4, 3.2, 0.2)
	_wallput(R + "@bed", "frame", "-x", lx, 1.75, y + 1.45, 7)
	_wallput(R + "@bed", "frame", "-x", lx, 2.75, y + 1.55, 1)
	_wallput(R + "@bed", "frame", "-x", lx, 3.35, y + 1.3, 6)
	_sconce(R + "@bed", "-x", lx, 2.2, y + 1.75, 1.7, 0)
	_wallput(R, "dresser", "-x", lx, 3.55, y, 1)
	_put(R, "plant", Vector3(lx + 0.1, y + 14 * PU, 3.6), 0, 0)
	# Right wall (bathroom wall, hall side) facing the stairs.
	_sconce(R + "@bed", "+x", 5.5, 0.6, y + 1.75, 1.4)
	# Gallery on the bathroom wall (hall side): frames + a second sconce so the
	# tall wall facing the camera is dressed like ref3's corridor.
	_wallput(R + "@bed", "frame", "+x", 5.5, 1.35, y + 1.45, 7)
	_wallput(R + "@bed", "frame", "+x", 5.5, 2.35, y + 1.6, 1)
	_wallput(R + "@bed", "frame", "+x", 5.5, 2.35, y + 0.95, 6)
	_sconce(R + "@bed", "+x", 5.5, 3.3, y + 1.75, 1.2)
	_wallput(R + "@bed", "wall_planter", "+x", 5.5, 4.05, y + 1.5, 2)
	_put(R, "plant", Vector3(5.5 - 0.55, y, 0.35), 0, 6)
	_put(R, "plant", Vector3(2.35, y, 4.15), 0, 0)
	_put(R, "toy_blocks", Vector3(0.2, y, 3.9), 0, 2)
	_lamp(Vector3(1.4, y + 2.4, 2.4), 0.7, 3.8, 0.0, Color(1.0, 0.74, 0.45), 0.0)
	_use(cushion, "Dog Cushion", [
		_act("nap", "Nap", "zzz", 60, {"energy": 0.4}, {"pose": "sleep", "who": ["dog"]}),
	])


func _build_bath() -> void:
	var R := "bath"
	var y := UF
	var bz := 0.25     # back wall face (low wall to the blue room)
	var lx := 5.75     # left wall face (hall)
	var rx := 8.75     # right exterior wall face
	var fz := 4.75
	# Glass shower stall in the back-left corner (towel on the door), tub on
	# the back wall beside it; vanity + mirror on the right wall facing the
	# camera side (ref3: the kid on a step stool brushes her teeth side-on).
	var shower := _put(R, "shower", Vector3(lx, y, bz), 0)
	var gs := PropLib.size_of("shower_glass")
	var glass := PropLib.instance("shower_glass", 0, false)
	glass.scale = Vector3.ONE * (PU / PropLib.FU)
	glass.position = Vector3(lx + PU + gs.x * PU * 0.5, y + PU, bz + PU + gs.z * PU * 0.5)
	add_child(glass)
	var tsz := PropLib.rotated_size("bathtub", 1)
	var tub := _put(R, "bathtub", Vector3(rx - tsz.x * PU - 0.02, y, bz + 0.04), 1)
	_put(R, "plant", Vector3(shower.end.x + 0.04, y, bz + 0.05), 0, 3)
	var vanity := _wallput(R, "vanity", "+x", rx, tub.end.z + 0.12, y)
	_spots["vanity"] = vanity
	var ss := PropLib.rotated_size("step_stool", 3)
	var step := _put(R, "step_stool", Vector3(vanity.position.x - ss.x * PU - 0.02, y, vanity.get_center().z - ss.z * PU * 0.5), 3)
	_spots["step"] = step
	_put(R, "bath_mat", Vector3(step.position.x - 0.45, y, step.position.z - 0.15), 1, 0)
	_put(R, "plant", Vector3(rx - 0.42, y + 13 * PU, vanity.end.z - 0.42), 0, 3)
	_wallput(R + "@bed", "shelf_unit", "+x", rx, 0.55, y + 1.8, 2)
	_wallput(R + "@bed", "towel_rack", "+x", rx, vanity.end.z + 0.1, y + 0.75, 2)
	_sconce(R + "@bed", "+x", rx, vanity.position.z - 0.35, y + 2.0, 0.55, 1)
	_sconce(R + "@bed", "+x", rx, vanity.end.z + 0.05, y + 2.0, 0.55, 1)
	_wallput(R + "@bed", "frame", "+x", rx, vanity.end.z + 0.65, y + 1.55, 7)
	# Front-left: toilet against the hall wall, laundry basket, plants.
	var toilet := _put(R, "toilet", Vector3(lx + 0.02, y, 3.3), 1)
	_put(R, "basket", Vector3(lx + 0.05, y, 2.45), 1, 2)
	_wallput(R + "@bed", "towel_rack", "-x", lx, 2.3, y + 0.95, 1)
	_wallput(R + "@bed", "wall_planter", "-x", lx, 3.5, y + 1.7, 2)
	_put(R, "plant", Vector3(rx - 0.6, y, fz - 0.6), 0, 6)
	_put(R, "plant", Vector3(lx + 0.05, y, fz - 0.55), 0, 2)
	_lamp(Vector3(7.3, y + 2.6, 2.4), 0.35, 3.5, 0.0, Color(1.0, 0.66, 0.4), 0.0)
	_use(shower, "Shower", [_act("shower", "Take Shower", "shower", 20, {"hygiene": 0.8}, {"pose": "idle"})])
	_use(tub, "Bathtub", [_act("bath", "Take Bath", "bath", 40, {"hygiene": 0.9, "fun": 0.1}, {"pose": "lie", "task": "Take Bath"})])
	_use(vanity, "Sink", [
		_act("brush", "Brush Teeth", "brush", 5, {"hygiene": 0.2}, {"pose": "brush_teeth", "task": "Brush Teeth"}),
		_act("wash", "Wash Hands", "wave", 3, {"hygiene": 0.1}, {"pose": "idle"}),
	], Vector3(step.get_center().x, y, step.get_center().z))
	_use(toilet, "Toilet", [_act("use_toilet", "Use", "toilet", 5, {"bladder": 1.0}, {"pose": "sit"})])


func _build_kitchen() -> void:
	var R := "kitchen"
	var bz := -4.75
	var fridge := _put(R, "fridge", Vector3(-0.6, 0, bz + 0.02), 0)
	_put(R, "counter", Vector3(0.45, 0, bz + 0.02), 0, 2)
	var sink := _put(R, "counter", Vector3(1.7, 0, bz + 0.02), 0, 1)
	var stove := _put(R, "stove", Vector3(2.95, 0, bz + 0.02), 0)
	_put(R, "counter", Vector3(4.2, 0, bz + 0.02), 0, 0)
	var bowl := _put(R, "dog_bowl", Vector3(0.3, 0, -0.8))
	_put(R, "plant", Vector3(5.6, 0, bz + 0.1), 0, 1)
	_lamp(Vector3(2.0, 2.3, -2.5), 0.9, 4.0, 0.2, Color(1.0, 0.72, 0.42), 0.0)
	# Dining nook right of the stairs (seen under the upstairs slab).
	_rug(R, 5.6, 0, 1.0, 3.0, 2.9, "red_kilim")
	var dtable := _put(R, "dining_table", Vector3(6.0, PU, 1.75), 0)
	for k in 2:
		_put(R, "chair", Vector3(6.25 + k * 1.0, PU, 1.1), 0, 0)
		_put(R, "chair", Vector3(6.25 + k * 1.0, PU, 2.95), 2, 0)
	_put(R, "plant", Vector3(8.1, 0, 0.3), 0, 5)
	_put(R, "plant", Vector3(5.4, 0, 4.1), 0, 2)
	_put(R, "lamp_floor", Vector3(8.15, 0, 4.0))
	_lamp(Vector3(8.4, 2.0, 4.2), 1.1, 3.5, 0.3)
	_lamp(Vector3(7.0, 2.4, 2.2), 0.9, 3.6, 0.0, Color(1.0, 0.7, 0.4), 1.1)
	# Hallway wall left of the stairs: shelves, console with lamp, frames.
	var wx := -0.75
	_wallput(R, "bookshelf", "-x", wx, 0.35, 0, 2)
	_wallput(R, "dresser", "-x", wx, 1.6, 0, 1)
	_put(R, "lamp_table", Vector3(wx + 0.12, 14 * PU, 1.75), 0, 0)
	_put(R, "plant", Vector3(wx + 0.12, 14 * PU, 2.3), 0, 6)
	_lamp(Vector3(wx + 0.5, 1.45, 2.0), 1.1, 3.4, 0.3)
	_wallput(R, "frame", "-x", wx, 1.75, 1.6, 7)
	_sconce(R, "-x", wx, 3.5, 1.65, 1.1)
	_put(R, "plant", Vector3(wx + 0.05, 0, 4.1), 0, 4)
	_rug(R, 0.2, 0, 1.3, 2.4, 2.6, "round_cream")
	_put(R, "armchair", Vector3(0.9, 0, 0.3), 0, 1)
	_put(R, "side_table", Vector3(2.2, 0, 0.5), 0, 0)
	_put(R, "plant", Vector3(2.35, 11 * PU, 0.6), 0, 3)
	_use(dtable, "Dining Table", [_act("eat", "Eat", "plate", 30, {"hunger": 0.3, "social": 0.1}, {"pose": "sit"})])
	_use(fridge, "Fridge", [
		_act("snack", "Grab a Snack", "apple", 5, {"hunger": 0.2}, {"pose": "idle"}),
		_act("cook_fridge", "Cook", "cook", 45, {"hunger": 0.6}, {"skill": "Cooking", "pose": "grill"}),
	])
	_use(stove, "Stove", [_act("cook", "Cook", "cook", 45, {"hunger": 0.7}, {"skill": "Cooking", "pose": "grill", "who": ["adult"]})])
	_use(sink, "Kitchen Sink", [_act("dishes", "Wash Dishes", "plate", 15, {"hygiene": -0.05}, {"pose": "idle"})])
	_use(bowl, "Dog Bowl", [_act("feed_dog", "Feed Dog", "bone", 5, {}, {"pose": "idle", "task": "Feed Dog", "who": ["adult", "child"]})])


# =================================================================== exterior

func _build_exterior() -> void:
	# Ground: 0.5 m grass tiles with a few colour patches, path and street.
	var g := VoxelBuilder.new()
	g.jitter = 0.04
	for x in range(-56, 52):
		for z in range(-62, 40):
			var xm := x * 0.5 + 0.25
			var zm := z * 0.5 + 0.25
			if xm > -9.2 and xm < 9.2 and zm > -5.2 and zm < 5.2:
				continue
			var c: Color
			var hh := VoxelBuilder.hash3(Vector3i(x, 0, z))
			if zm < -10.0 and zm > -14.0:
				c = Color("4a4d57") if not (absf(zm + 12.0) < 0.3 and posmod(x, 6) < 3) else Color("e9d98a")
			elif (zm <= -9.0 and zm >= -10.0) or (zm <= -14.0 and zm >= -15.0):
				c = Color("bdb6aa") if posmod(x, 4) != 0 else Color("a9a297")
			elif xm > 0.3 and xm < 1.9 and zm > 5.0:
				c = Color("d8c8a8") if posmod(z, 2) == 0 else Color("cbb994")
			else:
				c = [Color("5f9c40"), Color("68a646"), Color("57903a"), Color("72ae4c")][int(hh * 4.0)]
			g.set_v(Vector3i(x, -1, z), c)
	_night_tint.append(_add_mesh(Mesher.build(g, 0.5), "Ground", false))
	# Trees, bushes, street lamps.
	var t := VoxelBuilder.new()
	var o := VoxelBuilder.new()
	var trees := [
		Vector3(-8.5, 0, -8.0), Vector3(-3.5, 0, -7.6), Vector3(1.5, 0, -8.2), Vector3(6.5, 0, -7.7),
		Vector3(-13.5, 0, -2.0), Vector3(-13.0, 0, 5.5), Vector3(12.5, 0, -1.0), Vector3(13.0, 0, 6.5),
		Vector3(-18.5, 0, -17.0), Vector3(-6.5, 0, -16.8), Vector3(5.5, 0, -17.2), Vector3(17.0, 0, -16.6),
		Vector3(-24.0, 0, -6.0), Vector3(22.0, 0, -8.0), Vector3(-20, 0, 10.0), Vector3(19, 0, 12.0),
		Vector3(-12.0, 0, 9.5), Vector3(12.0, 0, 9.0), Vector3(-6.0, 0, 11.5), Vector3(7.5, 0, 12.0),
		Vector3(11.5, 0, 3.0), Vector3(-12.5, 0, -6.5), Vector3(14.0, 0, -12.0), Vector3(-15.0, 0, -12.5),
	]
	for i in trees.size():
		var p: Vector3 = trees[i]
		var nm := "pine" if i % 5 == 4 else "tree"
		var rs := PropLib.size_of(nm, i % 3)
		PropLib.place(t, nm, Vector3i(roundi(p.x * 4) - rs.x / 2, 0, roundi(p.z * 4) - rs.z / 2), i % 4, i % 3)
	_night_tint.append(_add_mesh(Mesher.build(t, 0.25), "Trees", true))
	# Big shade trees right behind the office (fill the view over the back wall
	# with leaves, like the greenery outside ref1's windows).
	var bt := VoxelBuilder.new()
	var big := [Vector3(-12.5, 0, -9.0), Vector3(-8.2, 0, -9.6), Vector3(-4.2, 0, -9.2), Vector3(-0.6, 0, -9.8), Vector3(-15.5, 0, -4.0)]
	for i in big.size():
		var p: Vector3 = big[i]
		var rs := PropLib.size_of("tree", [0, 2, 0, 1, 2][i])
		PropLib.place(bt, "tree", Vector3i(roundi(p.x / 0.34) - rs.x / 2, 0, roundi(p.z / 0.34) - rs.z / 2), i % 4, [0, 2, 0, 1, 2][i])
	_night_tint.append(_add_mesh(Mesher.build(bt, 0.34), "BigTrees", true))
	for i in 9:
		var lx := -24.0 + i * 6.5
		PropLib.place(o, "street_lamp", Vector3i(cc(lx), 0, cc(-9.6)), 0)
		PropLib.place(o, "street_lamp", Vector3i(cc(lx + 3.2), 0, cc(-14.6)), 0)
		if lx > -14.0 and lx < 12.0:
			_lamp(Vector3(lx + 0.3, 3.3, -9.3), 1.6, 3.4, 0.0, Color(1.0, 0.78, 0.45))
	var bushes := [Vector3(-9.8, 0, -3.0), Vector3(-9.8, 0, 1.0), Vector3(9.4, 0, -3.5), Vector3(9.4, 0, 0.5),
		Vector3(-6.0, 0, 5.6), Vector3(-2.5, 0, 5.6), Vector3(3.5, 0, 5.6), Vector3(6.5, 0, 5.6), Vector3(-9.8, 0, 4.2), Vector3(9.4, 0, 3.6)]
	for i in bushes.size():
		var p: Vector3 = bushes[i]
		PropLib.place(o, "bush", Vector3i(cc(p.x), 0, cc(p.z)), 0, i)
	for k in 6:
		PropLib.place(o, "hedge", Vector3i(cc(-9.0 + k * 3.0), 0, cc(-6.1)), 0, k)
	PropLib.place(o, "mailbox", Vector3i(cc(2.4), 0, cc(7.5)), 0)
	_night_tint.append(_add_mesh(Mesher.build(o, 0.125), "Garden", true))
	# Picket fence (fine grid) along the front garden.
	var fz := fc(8.2)
	for k in 30:
		var fx0 := fc(-15.0) + k * 16
		if fx0 > fc(0.2) and fx0 < fc(1.9):
			continue
		PropLib.place(_g("ext"), "fence", Vector3i(fx0, 0, fz), 0)
	# Ground-floor window glass (day: sky reflection, night: warm glow).
	var gd := VoxelBuilder.new()
	var gn := VoxelBuilder.new()
	gd.jitter = 0.0
	gn.jitter = 0.0
	for wdef in [[2, 8.75, -3.5, -1.5], [2, 8.75, 1.0, 3.0]]:
		var axis: int = wdef[0]
		var at: float = wdef[1]
		for a in range(fc(wdef[2]), fc(wdef[3])):
			for yy in range(fc(1.0), fc(2.2)):
				var mull: bool = (a - fc(wdef[2])) % 12 == 0 or yy == fc(1.0) or yy == fc(2.2) - 1 or yy == fc(1.7)
				var q := Vector3i(a, yy, fc(at) + 2) if axis == 0 else Vector3i(fc(at) + 2, yy, a)
				if mull:
					gd.set_v(q, TRIM); gn.set_v(q, TRIM)
				else:
					gd.set_v(q, Color("9cc4dc").lerp(Color("e8f4fa"), float(yy - fc(1.0)) / 20.0))
					gn.set_v(q, Color("ffc874").lerp(Color("ffe6a8"), VoxelBuilder.hash3(q) * 0.5), true)
	# Front facade (only standing in the "bed" view): frames, door, lit glass.
	var fd := VoxelBuilder.new()
	var fn := VoxelBuilder.new()
	fd.jitter = 0.0
	fn.jitter = 0.0
	for wdef: Array in FRONT_WINDOWS:
		var x0 := fc(wdef[0])
		var w := fc(wdef[1]) - x0
		PropLib.window_frame(_g("front@bed"), Vector3i(x0, fc(0.9), fc(4.75)), w, fc(1.2), 4, 0, 2, -1)
		var fr := _g("front@bed")
		# Flower box under the window (outside).
		for a in range(x0 + 1, x0 + w - 1):
			for k in range(4, 7):
				fr.set_v(Vector3i(a, fc(0.9) - 2, fc(4.75) + k), Color("8a5a36"))
				fr.set_v(Vector3i(a, fc(0.9) - 1, fc(4.75) + k), Color("9c6a40") if k == 6 else Color("5b3a22"))
				var fh := VoxelBuilder.hash3(Vector3i(a, 7, k))
				if fh > 0.35:
					fr.set_v(Vector3i(a, fc(0.9), fc(4.75) + k), Color("4f8a3a") if fh < 0.7 else Color("63a046"))
				if fh > 0.82:
					fr.set_v(Vector3i(a, fc(0.9) + 1, fc(4.75) + k), [Color("f28fb0"), Color("ffd45a"), Color("ffffff")][int(fh * 97.0) % 3])
		for a in range(x0 + 1, x0 + w - 1):
			for yy in range(fc(0.9) + 1, fc(2.1) - 1):
				var q := Vector3i(a, yy, fc(4.75) + 2)
				if fr.has(q):
					continue
				var tt := float(yy - fc(0.9)) / 19.0
				fd.set_v(q, Color("9cc4dc").lerp(Color("e8f4fa"), tt))
				var warm := Color("ffbf66").lerp(Color("ffe2a0"), tt * 0.6 + VoxelBuilder.hash3(q) * 0.25)
				fn.set_v(q, warm, true)
	# Front door with a porch lantern.
	var door := _g("front@bed")
	for a in range(fc(0.55), fc(1.55)):
		for yy in range(0, fc(2.05)):
			var edge := a == fc(0.55) or a == fc(1.55) - 1 or yy == fc(2.05) - 1
			var c := TRIM if edge else (Color("2f5a7a") if posmod(a - fc(0.55), 5) != 0 else Color("284e6a"))
			if not edge and yy > fc(1.3) and yy < fc(1.85) and a > fc(0.7) and a < fc(1.4):
				fn.set_v(Vector3i(a, yy, fc(4.75) + 3), Color("ffd68a"), true)
				fd.set_v(Vector3i(a, yy, fc(4.75) + 3), Color("b9d6e6"))
				continue
			door.set_v(Vector3i(a, yy, fc(4.75) + 3), c)
	door.set_v(Vector3i(fc(1.4), fc(1.0), fc(4.75) + 4), Color("d8b46a"))
	_put("front@bed", "sconce", Vector3(1.7, 1.75, 5.0), 0, 1)
	_lamp(Vector3(1.9, 2.0, 5.45), 0.5, 2.6, 0.0, Color(1.0, 0.7, 0.4), 0.5)
	# Wall lanterns along the facade: warm light pools on the siding (ref3).
	for lx: float in [-6.2, -3.6, -0.6, 4.45]:
		_put("front@bed", "sconce", Vector3(lx - 0.18, 1.75, 5.0), 0, 0)
		_lamp(Vector3(lx, 1.95, 5.45), 0.7, 2.6, 0.0, Color(1.0, 0.66, 0.36), 0.55)
	_front_glass_day = _add_mesh(Mesher.build(fd, U, Vector3.ZERO, true, true), "FrontGlassDay", false)
	_front_glass_night = _add_mesh(Mesher.build(fn, U, Vector3.ZERO, true, true), "FrontGlassNight", false)
	_front_glass_night.material_override = PropLib.lit_window_material(1.25)
	_glass_day = _add_mesh(Mesher.build(gd, U, Vector3.ZERO, true, true), "GlassDay", false)
	_glass_night = _add_mesh(Mesher.build(gn, U, Vector3.ZERO, true, true), "GlassNight", false)
	_upg_day.jitter = 0.0
	_upg_night.jitter = 0.0
	_glass_up_day = _add_mesh(Mesher.build(_upg_day, U, Vector3.ZERO, true, false), "GlassUpDay", false)
	_glass_up_night = _add_mesh(Mesher.build(_upg_night, U, Vector3.ZERO, true, false), "GlassUpNight", false)
	_glass_day.visible = not _is_night
	_glass_night.visible = _is_night
	_glass_up_day.visible = not _is_night
	_glass_up_night.visible = _is_night
	_glass_night.material_override = PropLib.lit_window_material()
	# Wall lanterns on the outside of the ground floor.
	for lp in [Vector3(9.0, 1.9, -0.4), Vector3(9.0, 1.9, 4.2)]:
		var rot := 0 if lp.z > 4.0 else 1
		_put("ext", "sconce", lp - Vector3(0.15, 0, 0) if rot == 0 else lp, rot, 0)
		_lamp(lp + (Vector3(0, 0.3, 0.35) if rot == 0 else Vector3(0.35, 0.3, 0)), 0.4, 2.2, 0.0)


func _ensure_neighbourhood(lit: bool) -> void:
	var cur := _hood_night if lit else _hood_day
	if cur == null:
		# All neighbour houses merged into ONE mesh (one draw call).
		var vb := VoxelBuilder.new()
		vb.jitter = 0.0
		var spots := [Vector3(-26, 0, -21.5), Vector3(-14, 0, -21.0), Vector3(-2, 0, -21.5), Vector3(10, 0, -21.0), Vector3(22, 0, -21.5),
			Vector3(-26, 0, -5.0), Vector3(21, 0, -4.0)]
		var styles := [1, 4, 2, 1, 4, 2, 5]
		var hs: float = PropLib.scale_of("house")
		for i in spots.size():
			var c: Vector3 = spots[i] + Vector3(4.0, 0, 3.25)
			var rot := 0 if (i < 5 or i > 6) else (1 if i == 5 else 3)
			if i > 6:
				rot = 0
			var rs := PropLib.rotated_size("house", rot, styles[i] + (8 if lit else 0))
			PropLib.place(vb, "house", Vector3i(roundi(c.x / hs) - rs.x / 2, 0, roundi(c.z / hs) - rs.z / 2), rot, styles[i] + (8 if lit else 0))
		var mi := MeshInstance3D.new()
		mi.name = "HoodNight" if lit else "HoodDay"
		mi.mesh = Mesher.build(vb, hs, Vector3.ZERO, true, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cur = mi
		add_child(cur)
		if lit:
			_hood_night = cur
			_night_tint.append(mi)
		else:
			_hood_day = cur
	if _hood_day:
		_hood_day.visible = not lit
	if _hood_night:
		_hood_night.visible = lit
	_apply_night_tint(lit)
	if lit and _hood_night and _hood_night.mesh.get_surface_count() > 0:
		# Neighbour houses sit darker than the lawn so their lit windows pop.
		if _hood_mat == null:
			_hood_mat = PropLib.night_exterior_material().duplicate()
			_hood_mat.albedo_color = Color(0.34, 0.36, 0.52)
		_hood_night.set_surface_override_material(0, _hood_mat)


## Exterior meshes get a cool, darker material at night so the warm interior
## pops (moonlit lawn instead of a bright green field).
func _apply_night_tint(lit: bool) -> void:
	for mi in _night_tint:
		if is_instance_valid(mi):
			# Surface 0 is the solid surface (Mesher writes it first); glow stays.
			if mi.mesh and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) == VoxelBuilder.solid_material():
				mi.set_surface_override_material(0, PropLib.night_exterior_material() if lit else null)


## Night sky backdrop: one big unshaded card (gradient, stars, moon) standing
## far behind the neighbourhood, turned to face the camera heading. It hides
## the edge of the ground and gives the top of the frame a sky like ref3.
func _make_moon() -> void:
	_moon = MeshInstance3D.new()
	_moon.name = "SkyCard"
	var q := QuadMesh.new()
	q.size = Vector2(SKY_W, SKY_H)
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	q.material = m
	_moon.mesh = q
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_moon)
	_place_moon(ShotPresets.PRESETS["home_night"].camera)
	_moon_disc = MeshInstance3D.new()
	_moon_disc.name = "MoonDisc"
	var mq := QuadMesh.new()
	mq.size = Vector2(7.0, 7.0)
	var msh := Shader.new()
	msh.code = MOON_SHADER
	var mm := ShaderMaterial.new()
	mm.shader = msh
	mm.render_priority = 10
	mq.material = mm
	_moon_disc.mesh = mq
	_moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_disc.visible = _is_night
	add_child(_moon_disc)


const MOON_SHADER := """shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled, shadows_disabled;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	float R = 0.17;
	// Pixelated disc (voxel look): quantise to a 16x16 grid inside the disc.
	vec2 q = floor((d / R) * 8.0) / 8.0 + 0.0625;
	float disc = step(length(q), 1.0);
	float crater = h21(floor((d / R) * 8.0));
	vec3 moon = vec3(1.0, 0.96, 0.84) * (0.9 + 0.1 * crater) - vec3(0.06, 0.07, 0.04) * step(0.82, crater);
	// Crescent shadow on the left like ref3.
	float shade = step(length(q + vec2(0.55, 0.05)), 0.95);
	moon = mix(moon, vec3(0.62, 0.66, 0.82) * 0.55, shade * 0.0);
	float glow = exp(-max(r - R, 0.0) * 18.0) * 0.32 * (1.0 - disc);
	ALBEDO = mix(vec3(0.6, 0.68, 0.95), moon * 0.98, disc);
	ALPHA = clamp(disc + glow, 0.0, 1.0);
}
"""
const SKY_W := 160.0
const SKY_H := 90.0
const SKY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
// Night sky backdrop drawn in screen space: a camera-facing card stands just
// beyond the first row of neighbour houses, so their roofs and the trees read
// as silhouettes against it (ref3), whatever the camera pitch.
uniform vec3 top_col = vec3(0.03, 0.045, 0.15);
uniform vec3 mid_col = vec3(0.08, 0.11, 0.28);
uniform vec3 low_col = vec3(0.17, 0.2, 0.4);
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = mix(top_col, mid_col, smoothstep(0.0, 0.18, uv.y));
	col = mix(col, low_col, smoothstep(0.15, 0.4, uv.y));
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 g = uv * vec2(90.0 * aspect, 90.0);
	vec2 cell = floor(g);
	float hs = h21(cell);
	vec2 f = fract(g) - 0.5;
	float star = step(0.965, hs) * (1.0 - smoothstep(0.1, 0.22, max(abs(f.x), abs(f.y)))) * (1.0 - smoothstep(0.12, 0.3, uv.y));
	col += vec3(0.85, 0.88, 1.0) * star * (0.5 + 0.5 * h21(cell + 7.0));
	ALBEDO = col;
}
"""
## Depth (m, along the view axis beyond the orbit target) of the sky card.
const SKY_BEYOND := 40.0


func _place_moon(_cam: Dictionary) -> void:
	_moon.visible = _is_night
	_place_sky()


## Stand the sky card perpendicular to the view, SKY_BEYOND m past the target.
func _place_sky() -> void:
	var c3 := get_viewport().get_camera_3d() if is_inside_tree() else null
	if c3 == null or _moon == null:
		return
	var rig := c3.get_parent()
	var dist: float = rig.get("distance") if rig and "distance" in rig else 20.0
	var fwd := -c3.global_transform.basis.z
	_moon.global_transform = Transform3D(c3.global_transform.basis, c3.global_position + fwd * (dist + SKY_BEYOND))


func _add_mesh(m: ArrayMesh, n: String, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _bake() -> void:
	# Structure groups.
	for key: String in _sb:
		var vb: VoxelBuilder = _sb[key]
		if vb.vox.is_empty():
			continue
		var parts := key.split("|")
		var sig := parts[1]
		var part := parts[2]
		var mi := _add_mesh(Mesher.build(vb, C, Vector3.ZERO, true, true), "Struct_%s" % key.replace("|", "_").replace(":", "-").replace(",", "_"), true)
		if sig != "static":
			if not _wall_nodes.has(sig):
				_wall_nodes[sig] = {"base": [], "cap": [], "upper": []}
			_wall_nodes[sig][part].append(mi)
	# Furniture per room.
	for room: String in _fb:
		var vb: VoxelBuilder = _fb[room]
		var mi := _add_mesh(Mesher.build(vb, PU), "Furniture_" + room.replace("@", "_"), true)
		if "@" in room:
			_view_meshes.append([mi, room.split("@")[1]])
	for room: String in _gb:
		var vb: VoxelBuilder = _gb[room]
		var fmi := _add_mesh(Mesher.build(vb, U), "Fine_" + room.replace("@", "_"), true)
		if "@" in room:
			_view_meshes.append([fmi, room.split("@")[1]])
	_sb.clear()
	_fb.clear()
	_gb.clear()


# =================================================================== people

func _spawn_household() -> void:
	for look: String in ["dad", "bunny_girl", "cat_girl", "beagle"]:
		var a := SimActor.create(look)
		# Household at house scale (~1/3 - 1/2 of the 3.1 m walls), not the
		# chunkier street-scene scale.
		a.body_scale = ACTOR_SCALE.get(look, 1.0)
		add_child(a)
		# body_scale is clamped to SimActor.HERO_MIN; shrink the node itself by
		# what the clamp kept, so the household sits at house scale.
		var eff := a.skeleton.scale.x if a.skeleton else 1.0
		var k: float = ACTOR_SCALE.get(look, 1.0) / maxf(eff, 0.01)
		if k < 0.999:
			a.scale = Vector3.ONE * k
		actors[look] = a
	for m in Game.household:
		if actors.has(m.get("look", "")):
			actors[m.name] = actors[m.look]


func _place(look: String, pos: Vector3, face_to: Vector3, pose: String, seat := -1.0) -> SimActor:
	var a: SimActor = actors[look]
	a.position = pos
	if seat > 0.0:
		a.seat_height = seat / a.scale.y   # actor-local (node may be scaled)
	a.face(face_to)
	a.set_pose(pose)
	return a


func _stage(preset: String) -> void:
	if actors.is_empty():
		return
	var y := UF
	if preset == "home_night":
		var bed: AABB = _spots["pink_bed"]
		var bc := bed.get_center()
		# Tucked in: head on the pillow at the headboard (back wall), feet to the camera.
		var lily := _place("bunny_girl", Vector3(bc.x, y, bed.position.z + 1.05), Vector3(bc.x, y, bed.end.z + 2.0), "lie")
		lily.lie_height = 8 * PU / lily.scale.y
		var ch: AABB = _spots["pink_chair"]
		var cc3 := ch.get_center()
		var jack := _place("dad", Vector3(cc3.x, y, cc3.z), Vector3(cc3.x - 1.0, y, cc3.z + 0.75), "sit_read", 7 * PU)
		var st: AABB = _spots["step"]
		var maya := _place("cat_girl", Vector3(st.get_center().x, y + 6 * PU, st.get_center().z), Vector3(st.get_center().x + 3.0, y, st.get_center().z + 0.5), "brush_teeth")
		var cu: AABB = _spots["dog_cushion"]
		var dog := _place("beagle", Vector3(cu.get_center().x, y + 3 * PU, cu.get_center().z), Vector3(cu.get_center().x + 1.0, y, cu.get_center().z + 1.2), "sleep")
		Game.show_bubble(jack, {"text": "Read Story", "icon": "book_open", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(maya, {"text": "Brush Teeth", "icon": "brush", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(dog, {"icon": "zzz", "kind": "emote", "id": "action"})
		lily.set_pose("lie")
		if _blanket == null:
			_blanket = PropLib.instance("blanket", 0)
			_blanket.scale = Vector3.ONE * (PU / PropLib.FU)
			add_child(_blanket)
		_blanket.position = Vector3(bc.x, y + 8 * PU, bed.position.z + 1.55)
		_blanket.rotation_degrees.y = 0.0
		_blanket.visible = true
	else:
		if _blanket:
			_blanket.visible = false
		var ch: AABB = _spots["office_chair"]
		var dk: AABB = _spots["desk"]
		var jack := _place("dad", Vector3(ch.get_center().x, y, ch.get_center().z), Vector3(dk.get_center().x - 0.1, y, dk.position.z), "type", 7 * PU)
		var stl: AABB = _spots["stool"]
		var lily := _place("bunny_girl", Vector3(stl.get_center().x, y, stl.get_center().z), Vector3(-4.45, y, -3.7), "sit_paint", 6 * PU)
		var maya := _place("cat_girl", Vector3(-2.55, y, -0.15), Vector3(-2.35, y, 1.2), "play")
		var ball: AABB = _spots["ball"]
		var dog := _place("beagle", ball.get_center() + Vector3(-0.75, -ball.size.y * 0.5, 0.1), ball.get_center() + Vector3(0.4, 0, 0.9), "play")
		Game.show_bubble(jack, {"text": "Work", "icon": "laptop", "kind": "action", "id": "action", "progress": 0.32})
		Game.show_bubble(lily, {"text": "Paint", "icon": "palette", "kind": "action", "id": "action", "progress": 0.48})
		Game.show_bubble(maya, {"text": "Play", "icon": "toys", "kind": "action", "id": "action", "progress": 0.55})
		Game.show_bubble(dog, {"text": "Play", "icon": "paw", "kind": "action", "id": "action", "progress": 0.6})


# =================================================================== live

func _on_time(_d: int, _m: float) -> void:
	var n := Game.is_night()
	if n == _is_night:
		return
	_is_night = n
	_ensure_neighbourhood(n)
	if _glass_day:
		_glass_day.visible = not n
		_glass_night.visible = n
	_sync_front_glass()
	if _glass_up_day:
		_glass_up_day.visible = not n
		_glass_up_night.visible = n
	if _moon:
		_moon.visible = n
	if _halos:
		PropLib.set_halo_strength(_halos, HALO_NIGHT if n else 0.0)


var _frames := 0


func _process(delta: float) -> void:
	_frames += 1
	if _frames == 12 and OS.get_environment("VIMS_STATS") != "":
		print("HOME_STATS draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			" objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		var vp := get_viewport()
		for t in [[Viewport.RENDER_INFO_TYPE_VISIBLE, "visible"], [Viewport.RENDER_INFO_TYPE_SHADOW, "shadow"], [Viewport.RENDER_INFO_TYPE_CANVAS, "canvas"]]:
			print("HOME_PASS ", t[1], " draws=", vp.get_render_info(t[0], Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				" prims=", vp.get_render_info(t[0], Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), " objs=", vp.get_render_info(t[0], Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
		var rows := []
		for mi in find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var tris := 0
			for si in mi.mesh.get_surface_count():
				if not (mi.mesh is ArrayMesh):
					continue
				var il: int = mi.mesh.surface_get_array_index_len(si)
				tris += (il if il > 0 else mi.mesh.surface_get_array_len(si)) / 3
			rows.append([tris, mi.name])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var tot := 0
		for r in rows:
			tot += r[0]
		print("HOME_TRIS total=", tot, " meshes=", rows.size(), " top=", rows.slice(0, 60), " lights=", get_tree().get_nodes_in_group("vims_lamps").size())
	if _moon_disc:
		_moon_disc.visible = _is_night
		if _is_night:
			var c3 := get_viewport().get_camera_3d()
			if c3:
				var vs := get_viewport().get_visible_rect().size
				var sp := Vector2(vs.x * 0.715, vs.y * 0.06)
				_moon_disc.global_position = c3.project_ray_origin(sp) + c3.project_ray_normal(sp) * 80.0
	if _moon and _moon.visible:
		_place_sky()
	if not _auto_view:
		return
	_view_timer -= delta
	if _view_timer > 0.0:
		return
	_view_timer = 0.3
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	if absf(d.y) < 0.01:
		return
	var t := (UF - o.y) / d.y
	if t <= 0.0:
		return
	var hit := o + d * t
	var v := "office" if hit.x < -1.0 else "bed"
	if v != wall_view:
		set_wall_view(v)
