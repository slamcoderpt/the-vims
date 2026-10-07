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
const PU := 0.07           # furniture display grid (= PropLib.FU: ~real-world furniture)
const MU := 0.035          # micro grid for detail.gd "_hd" props (half a furniture cell)
const FS := 1.25           # furniture display scale
const UH := 28             # upstairs wall height in structure cells (3.5 m: ref1 tall walls)
const C := 0.125           # structure grid
const UF := 3.0            # upstairs floor height (m)
## "office_in": the camera stands on the office side of the x = -1 divider
## (ref1 framing), so that divider can stand tall and hide the pink room.
const VIEWS := ["office", "office_in", "bed"]
## Household display scale relative to the rig's life size (dad ~1.4 m, kids
## ~1.0 m, beagle about the size of its bed). SimActor clamps body_scale to a
## hero minimum, so the remainder is applied as a node scale (see _spawn_household).
## Art direction: adult ~1.75 m, kids ~70 % of that, beagle's back at a kid's knee-to-hip.
const ACTOR_SCALE := {"dad": 0.946, "bunny_girl": 0.76, "cat_girl": 0.76, "beagle": 0.58}
## Ground-floor front facade windows (x0, x1 metres), y 0.9..2.1.
const FRONT_WINDOWS := [[-8.2, -6.8], [-5.6, -4.2], [-3.0, -1.6], [2.0, 3.0], [5.9, 7.3], [7.6, 8.5]]
## Upstairs office front windows (only standing in the "bed" view), x0, x1.
const UP_FRONT_WINDOWS := [[-7.7, -6.2], [-3.5, -2.0]]
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
const W_PINK := Color("eaa2b6")
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
var _mb := {}                    # micro builders room -> VoxelBuilder (MU grid, "_hd" props)
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
var _shafts: MeshInstance3D


# =================================================================== API

func build() -> void:
	var t0 := Time.get_ticks_msec()
	_is_night = Game.is_night()
	var stats := OS.get_environment("VIMS_STATS") != ""
	var steps := [_build_structure, _build_office, _build_living, _build_pink, _build_blue, _build_hall,
		_build_bath, _build_kitchen, _build_exterior, _bake, _build_sun_shafts, _ensure_neighbourhood.bind(_is_night)]
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
	_budget_lights()
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
		"sun_heading": 205.0, "sun_elev": 34.0, "sun_energy": 2.05,
		"ambient_day": Color(0.96, 0.84, 0.72), "ambient_energy": 0.5,
		"ambient_night": Color(0.66, 0.54, 0.52), "ambient_night_energy": 0.34, "lamp_night_mult": 3.8,
		"sky_day": Color(0.64, 0.8, 0.94), "sky_night": Color(0.07, 0.09, 0.22),
		"fog_day": Color(0.9, 0.9, 0.88), "fog_night": Color(0.12, 0.15, 0.32), "fog_density": 0.004,
		"moon_heading": 150.0, "moon_energy": 0.32, "glow_boost_night": 1.2,
		"shadow_distance": 40.0,
		"post_day": {"focus_y": 0.5, "band": 0.35, "falloff": 0.18, "blur_px": 4.0, "top_boost": 1.0,
			"saturation": 1.16, "contrast": 1.12, "tint": Vector3(1.02, 1.0, 0.96), "vignette": 0.22},
		"post_night": {"focus_y": 0.52, "band": 0.4, "falloff": 0.12, "blur_px": 2.6, "top_boost": 0.8},
	}


func get_actor(key: String) -> SimActor:
	return actors.get(key, null)


func apply_preset(preset: String) -> void:
	_stage(preset)
	set_wall_view("bed" if preset == "home_night" else "office_in")
	_auto_view = false


## Interior groups closed off under the office roof / ground-floor facade in
## the "bed" view: hidden there (nothing to see, saves draws + triangles).
const CLOSED_IN_BED := ["Furniture_office", "Fine_office", "Micro_office", "Workstation", "Easel",
	"Furniture_living", "Fine_living", "Micro_living", "Furniture_kitchen"]


func set_wall_view(view: String) -> void:
	wall_view = view
	_sync_front_glass()
	for n: String in CLOSED_IN_BED:
		var c := get_node_or_null(n)
		if c is Node3D:
			c.visible = view != "bed"
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


## Micro-grid builder (MU cells) for the detail.gd "_hd" props.
func _m(room: String) -> VoxelBuilder:
	if not _mb.has(room):
		var vb := VoxelBuilder.new()
		vb.jitter = 0.025
		_mb[room] = vb
	return _mb[room]


## Place an "_hd" prop (min corner at `pos`, metres) on the micro grid.
func _putm(room: String, pname: String, pos: Vector3, rot := 0, v := 0) -> AABB:
	var at := Vector3i(roundi(pos.x / MU), roundi(pos.y / MU), roundi(pos.z / MU))
	var bb := PropLib.place(_m(room), pname, at, rot, v)
	return AABB(bb.position * MU, bb.size * MU)


## Centred variant of _putm.
func _putmc(room: String, pname: String, x: float, y: float, z: float, rot := 0, v := 0) -> AABB:
	var rs := PropLib.rotated_size(pname, rot, v)
	return _putm(room, pname, Vector3(x - rs.x * MU * 0.5, y, z - rs.z * MU * 0.5), rot, v)


## Wall-mounted "_hd" prop (see _wallput).
func _wallputm(room: String, pname: String, side: String, face: float, along: float, y: float, v := 0) -> AABB:
	var rs: Vector3i
	match side:
		"-x":
			return _putm(room, pname, Vector3(face, y, along), 1, v)
		"+x":
			rs = PropLib.rotated_size(pname, 3, v)
			return _putm(room, pname, Vector3(face - rs.x * MU, y, along), 3, v)
		"+z":
			rs = PropLib.rotated_size(pname, 2, v)
			return _putm(room, pname, Vector3(along, y, face - rs.z * MU), 2, v)
		_:
			return _putm(room, pname, Vector3(along, y, face), 0, v)


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
		var m: String = modes.get(v, modes.get("office", "low") if v == "office_in" else "low")
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
	# In the night/bedroom view the office wing is closed (walls up + roof):
	# the shot reads as a lit house beside the cut-away bedrooms (ref3).
	var up_front := []
	for w: Array in UP_FRONT_WINDOWS:
		up_front.append([w[0], w[1], 0.9, 2.2])
	_wall(0, 4.75, -9, -4.5, 1, "office", "ext", {"office": "none", "bed": "tall"}, up_front)
	_wall(0, 4.75, -4.5, -1.0, 1, "office", "ext", {"office": "low", "bed": "tall"}, up_front)
	_wall(0, 4.75, -1.0, 9, 1, "hall", "ext", both_low)
	# Right exterior.
	var bed_tall := {"office": "low", "bed": "tall"}
	_wall(2, 8.75, -4.75, 0.0, 1, "blue", "ext", bed_tall)
	_wall(2, 8.75, 0.0, 4.75, 1, "bath", "ext", bed_tall, [[3.3, 4.45, 1.0, 2.3]])
	# Office | pink+hall divider (low from the office, tall for the bedrooms).
	_wall(2, -1.0, -4.75, 0.0, 1, "office", "pink", {"office": "low", "office_in": "tall", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	_wall(2, -1.0, 0.0, 4.75, 1, "office", "hall", {"office": "low", "office_in": "tall", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	# Bedroom fronts onto the hall.
	_wall(0, 0.0, -0.75, 5.5, 1, "pink", "hall", both_low, [[2.3, 3.2, 0.0, 2.1], [4.2, 5.2, 0.0, 2.1]])
	_wall(0, 0.0, 5.5, 8.75, 1, "blue", "bath", both_low)
	# Pink | blue divider, hall | bath divider.
	# Low in both views: the camera looks in from the +x side, so a tall
	# divider would hide the bedside story scene behind it.
	_wall(2, 3.5, -4.75, 0.0, 1, "pink", "blue", both_low)
	_wall(2, 5.5, 0.25, 4.75, 1, "hall", "bath", {"office": "low", "bed": "tall"}, [[3.4, 4.4, 0.0, 2.1]])
	_build_office_roof()


## Gable roof over the office wing, standing only in the "bed" view. Ridge
## along Z; the front gable end (siding + a lit attic window) faces the
## night camera, stepped slate slopes either side.
func _build_office_roof() -> void:
	var sig := _sig({"office": "none", "office_in": "none", "bed": "tall"})
	var x0 := cc(-9.4)
	var x1 := cc(-0.75)
	var z0 := cc(-5.3)
	var z1 := cc(5.05)
	var base := 24 + UH          # wall top (cells)
	var mid := (x0 + x1) * 0.5
	var half := (x1 - x0) * 0.5
	var slope := 0.62
	var slate := [Color("3c4562"), Color("343c56"), Color("444e6c")]
	for x in range(x0, x1):
		var h := base + floori((half - absf(x + 0.5 - mid)) * slope)
		for z in range(z0, z1):
			var edge := z == z0 or z == z1 - 1 or x == x0 or x == x1 - 1
			for yy in range(h - 2, h + 1):
				var q := Vector3i(x, yy, z)
				var c: Color = slate[posmod(floori(h / 2.0) + (1 if VoxelBuilder.hash3(Vector3i(x, 0, z / 3)) > 0.85 else 0), 3)]
				if yy < h:
					c = c.darkened(0.15)
				if edge:
					c = TRIM if yy == h else CAP
				if absf(x + 0.5 - mid) < 1.0:
					c = CAP
				_sgroup(_zone(q), sig, "base").set_v(q, c)
		# Gable ends (siding up to the roof line), front and back.
		for gz: int in [cc(-5.0), cc(-5.0) + 1, cc(4.75), cc(4.75) + 1]:
			if x < cc(-9.0) or x >= cc(-1.0):
				continue
			for yy in range(base, h - 2):
				var q := Vector3i(x, yy, gz)
				var c := SIDING if posmod(yy, 2) == 0 else SIDING.darkened(0.06)
				var ax := absf(x + 0.5 - mid)
				if ax < 3.2 and yy >= base + 5 and yy <= base + 11 and gz >= cc(4.75):
					if ax < 2.2 and yy > base + 5 and yy < base + 11:
						_sgroup(_zone(q), sig, "base").set_v(q, Color("ffcf7a"), true)
						continue
					c = TRIM
				_sgroup(_zone(q), sig, "base").set_v(q, c)


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
	PropLib.window_frame(_g("bath"), Vector3i(fc(8.75), fc(UF + 1.0), fc(3.3)), fc(1.15), fc(1.3), 4, 2, 2, -1)
	# Glass: bright sky panes by day (the light source of ref1's window wall),
	# deep night-blue panes after dark. Two merged meshes, toggled by time.
	_up_glass("office", 0, -5.0, -5.85, -3.95, UF + 0.45, UF + 2.55)
	_up_glass("office", 0, -5.0, -3.75, -1.85, UF + 0.45, UF + 2.55)
	_up_glass("office", 2, -9.0, 2.0, 3.6, UF + 0.9, UF + 2.3)
	_up_glass("pink", 0, -5.0, 1.85, 3.15, UF + 0.9, UF + 2.2)
	_up_glass("blue", 0, -5.0, 6.4, 7.8, UF + 0.9, UF + 2.2)
	_up_glass("bath", 2, 8.75, 3.3, 4.45, UF + 1.0, UF + 2.3)


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
			var day := _foliage(a, yy, t, h)
			_upg_day.set_v(q, day, true)
			var night := Color("1b2550").lerp(Color("2a3a74"), 1.0 - t)
			if h > 0.985:
				night = Color("e8ecff")
			_upg_night.set_v(q, night, true)


## Sunlit garden seen through the day glass: leafy clusters (denser low
## down) over a pale sky, a few branches; like the trees outside ref1's windows.
func _foliage(a: int, yy: int, t: float, h: float) -> Color:
	var h1 := VoxelBuilder.hash3(Vector3i(floori(a / 3.0), floori(yy / 3.0), 7))
	var h2 := VoxelBuilder.hash3(Vector3i(floori(a / 7.0) + 11, floori(yy / 6.0), 1))
	var leafy := 0.3 + 0.45 * (1.0 - t) + (h2 - 0.5) * 0.6
	if h1 < leafy:
		var lit := VoxelBuilder.hash3(Vector3i(a, yy, 3))
		if lit > 0.82:
			return Color("c9e87a")
		if lit > 0.5:
			return Color("8cc456")
		if lit > 0.18:
			return Color("6aa845")
		return Color("4f8a3a")
	if h > 0.965 and t < 0.6:
		return Color("8a6440")
	return Color("cfeaf7").lerp(Color("f6fcff"), t)


const WS_ANGLE := 40.0


## The work desk with all its gear as one turned group (two merged meshes:
## furniture grid + micro grid). `at` = desk centre on the floor, `deg` =
## turn about Y (the desk front, local +X, swings towards -Z). Returns world
## boxes / points: desk, chair (AABBs), seat, look, lamp (Vector3).
func _workstation(at: Vector3, deg: float) -> Dictionary:
	var wf := VoxelBuilder.new()
	wf.jitter = 0.03
	var wm := VoxelBuilder.new()
	wm.jitter = 0.025
	PropLib.place(wf, "desk", Vector3i.ZERO, 1)          # 12 x 28 cells (0.84 x 1.96 m)
	var top := 24                                           # desk top in MU cells
	PropLib.place(wm, "keyboard_hd", Vector3i(13, top, 14), 1)
	PropLib.place(wm, "laptop_hd", Vector3i(7, top, 41), 1)
	PropLib.place(wm, "mug_hd", Vector3i(18, top, 50), 0, 1)
	PropLib.place(wm, "pencil_cup_hd", Vector3i(3, top, 2))
	PropLib.place(wm, "desk_plant_hd", Vector3i(9, top, 1), 0, 0)
	PropLib.place(wm, "sticky_stack_hd", Vector3i(16, top, 4), 1)
	PropLib.place(wf, "desk_lamp", Vector3i(1, 12, 25), 1)
	var cs := PropLib.rotated_size("office_chair_hd", 3, 1)
	var chair_c := Vector3(0.84 + 0.34, 0, 0.98 + 0.12)          # local metres (desk min corner = 0)
	PropLib.place(wm, "office_chair_hd", Vector3i(roundi(chair_c.x / MU) - cs.x / 2, 0, roundi(chair_c.z / MU) - cs.z / 2), 3, 1)
	var ctr := Vector3(0.42, 0, 0.98)
	var node := Node3D.new()
	node.name = "Workstation"
	node.position = at
	node.rotation.y = deg_to_rad(deg)
	add_child(node)
	var mf := MeshInstance3D.new()
	mf.name = "DeskF"
	mf.mesh = Mesher.build(wf, PU, ctr / PU)
	node.add_child(mf)
	var mm := MeshInstance3D.new()
	mm.name = "DeskM"
	mm.mesh = Mesher.build(wm, MU, ctr / MU)
	node.add_child(mm)
	# Dual monitors as their own instances, angled towards the room (and the
	# camera) like a real two-screen setup.
	for k in 2:
		var mon := PropLib.instance("monitor_hd", k)
		mon.position = Vector3(0.24, top * MU, [0.62, 1.3][k]) - ctr
		mon.rotation.y = deg_to_rad(90.0 - [52.0, 30.0][k])
		node.add_child(mon)
	var xf := node.transform
	var seat := xf * (chair_c - ctr)
	var look := xf * (Vector3(0.1, 0, 0.98) - ctr)
	var lamp := xf * (Vector3(0.45, 1.25, 1.85) - ctr)
	var dbox := AABB(at - Vector3(0.9, 0, 0.9), Vector3(1.8, 1.3, 1.8))
	var cbox := AABB(seat - Vector3(0.32, 0, 0.32), Vector3(0.64, 1.0, 0.64))
	return {"desk": dbox, "chair": cbox, "seat": seat, "look": look, "lamp": lamp}


func _build_office() -> void:
	var R := "office"
	var y := UF
	var fx := -8.75   # inner face of the L wall
	var bz := -4.75   # inner face of the back wall
	var rx := -1.0    # inner face of the divider (pink/hall side)
	_windows_upstairs()
	# ref1 layout for a diagonal camera looking into the back-left corner:
	# the work wall is the LEFT wall (cork board, mountain painting, long desk
	# with two bright monitors, printer cabinet), tall bookshelves with globe
	# and trophies stand in the corner on the back wall, and the window wall
	# (easel, piano + guitar) runs off to the right.
	# Corner workstation, turned WS_ANGLE off the left wall so the seated
	# dad's face reads in 3/4 from the shot camera (ref1) instead of his back.
	var ws := _workstation(Vector3(fx + 1.02, y, -2.55), WS_ANGLE)
	var desk: AABB = ws.desk
	var chair: AABB = ws.chair
	_lamp(ws.lamp, 0.5, 2.2, 0.6, Color(1.0, 0.7, 0.4), 0.5)
	_wallputm(R, "corkboard_hd", "-x", fx, -4.2, y + 1.55, 0)
	_wallput(R, "frame", "-x", fx, -2.55, y + 1.8, 0)
	_wallput(R, "frame", "-x", fx, -1.0, y + 1.85, 1)
	_wallput(R, "wall_clock", "-x", fx, -1.85, y + 2.55, 1)
	_lamp(Vector3(fx + 1.6, y + 1.7, -2.2), 0.6, 2.6, 0.35, Color(0.75, 0.85, 1.0), 0.0)
	var fcab := _put(R, "filing_cabinet", Vector3(fx, y, -1.25), 1)
	_putm(R, "printer_hd", Vector3(fx + 0.02, fcab.end.y, fcab.position.z - 0.05), 1)
	_put(R, "book_stack", Vector3(fx + 0.06, fcab.end.y, fcab.end.z - 0.02), 1, 2)
	# Reading corner by the railing: beanbag, floor lamp, a leafy plant.
	_put(R, "beanbag", Vector3(fx + 0.15, y, 0.05), 1, 0)
	_put(R, "lamp_floor", Vector3(fx + 0.05, y, -0.55))
	_lamp(Vector3(fx + 0.35, y + 1.95, -0.3), 0.5, 2.6, 0.5, Color(1.0, 0.7, 0.4), 0.5)
	_put(R, "plant", Vector3(fx + 0.06, y, 1.0), 0, 1)
	_sconce(R, "-x", fx, -0.45, y + 2.2, 1.0)
	# Corner bookshelves on the back wall (globe, trophies, books, plants).
	var bs1 := _wallput(R, "bookshelf", "-z", bz, fx + 0.04, y, 4)
	var bs2 := _wallput(R, "bookshelf", "-z", bz, bs1.end.x + 0.02, y, 0)
	_put(R, "trophy", Vector3(bs1.position.x + 0.2, y + 30 * PU, bz + 0.12))
	_put(R, "plant", Vector3(bs2.end.x - 0.5, y + 30 * PU, bz + 0.04), 0, 2)
	_put(R, "ivy", Vector3(bs2.end.x - 0.4, y + 2.4, bz + 0.03), 0, 1)
	_put(R, "plant", Vector3(fx + 0.06, y, -4.2), 0, 1)
	_lamp(Vector3(bs2.get_center().x, y + 2.3, bz + 0.9), 0.7, 3.0, 0.4)
	# --- Window wall: two big multi-pane windows, curtains, sill plants, ivy.
	for cx: float in [-3.82, -1.7]:
		_put(R, "curtain", Vector3(cx, y, bz + 0.02), 0, 0)
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
	# --- Divider wall, office side (only standing in the "office_in" view):
	# gallery of frames, a music poster, ivy, a sconce, like ref1's right wall.
	var DW := R + "@office_in"
	_wallput(DW, "frame", "+x", rx, -4.5, y + 1.45, 4)
	_wallput(DW, "frame", "+x", rx, -3.45, y + 1.75, 1)
	_sconce(DW, "+x", rx, -3.0, y + 2.3, 0.0, 1)
	_wallput(DW, "ivy", "+x", rx, -0.95, y + 1.3, 1)
	_wallput(DW, "wall_shelf", "+x", rx, -0.5, y + 2.0, 1)
	_wallput(DW, "frame", "+x", rx, 0.6, y + 1.5, 3)
	_wallput(DW, "frame", "+x", rx, 3.3, y + 1.6, 8)
	# --- Right side along the low divider: cube storage + plants.
	_wallput(R, "bookshelf", "+x", rx, -2.2, y, 3)
	_put(R, "plant", Vector3(-1.5, y + 18 * PU, -2.1), 0, 0)
	_put(R, "plant", Vector3(-1.5, y + 18 * PU, -1.4), 0, 6)
	# --- Play area (dog + cat girl), pulled in front of the work/art/music
	# corners so the ref1 framing shows them all with breathing room.
	_rug(R, -6.6, y, -1.0, 2.5, 2.0, "check_blue")
	_rug(R, -3.9, y, -1.75, 2.6, 2.6, "blue_braid")
	var ball := _put(R, "tennis_ball", Vector3(-4.35, y + PU, -0.85))
	var dogbed := _putc(R, "dog_bed", -5.55, y, 0.35, 0)
	var toybox := _wallput(R, "toy_box", "+x", rx, -0.95, y)
	_put(R, "soccer_ball", Vector3(-1.75, y + PU, 0.35))
	_put(R, "toy_blocks", Vector3(-3.25, y + PU, -0.35), 0, 1)
	_put(R, "toy_robot", Vector3(-2.3, y + PU, -0.45), 1)
	_put(R, "toy_blocks", Vector3(-2.15, y + PU, 0.15), 0, 0)
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
	_spots["dad_seat"] = ws.seat
	_spots["dad_look"] = ws.look
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
	# ref3 staging: the bunny canopy bed runs ACROSS the room with its
	# headboard on the left wall, so the tucked-in girl lies sideways to the
	# camera (face in profile / 3/4, not foreshortened); dad's reading chair
	# stands at the foot end, turned to the camera. Tall pieces stay on the
	# back and left walls; the front (camera side) keeps only low things.
	_rug(R, -0.35, y, -4.1, 3.6, 3.2, "patch_pink")
	var ns := _put(R, "nightstand", Vector3(fx + 0.04, y, bz + 0.04), 1, 2)
	_put(R, "lamp_table", Vector3(ns.position.x + 0.1, y + 10 * PU, ns.position.z + 0.12), 0, 1)
	_lamp(Vector3(ns.get_center().x + 0.35, y + 1.2, ns.get_center().z + 0.3), 0.55, 3.0, 0.2, Color(1.0, 0.6, 0.3), 0.5)
	var bed := _put(R, "bed", Vector3(fx + 0.1, y, ns.end.z + 0.04), 1, 3)
	_put(R, "plush", Vector3(bed.position.x + 0.3, y + 10 * PU, bed.end.z - 0.5), 1, 0)
	var chair := _putc(R, "chair", bed.end.x + 0.42, y, bed.get_center().z + 0.35, 3, 2)
	var st := _put(R, "side_table", Vector3(bed.end.x + 0.15, y, bz + 0.08), 0, 2)
	_put(R, "lamp_table", Vector3(st.position.x + 0.05, y + 11 * PU, bz + 0.12), 0, 1)
	_put(R, "book_stack", Vector3(st.end.x - 0.4, y + 11 * PU, bz + 0.2), 0, 2)
	_spots["pink_bed"] = bed
	_spots["pink_chair"] = chair
	# Back wall: bunny pictures, window with pink curtains and sill plants.
	_wallput(R, "frame", "-z", bz, 0.55, y + 1.9, 2)
	_put(R, "curtain", Vector3(1.6, y, bz + 0.02), 0, 1)
	_put(R, "curtain", Vector3(3.2 - 5 * PU, y, bz + 0.02), 0, 1)
	_put(R, "plant", Vector3(2.05, y + 0.9, bz - 0.04), 0, 6)
	_put(R, "plant", Vector3(2.6, y + 0.9, bz - 0.04), 0, 3)
	_put(R, "hanging_plant", Vector3(2.3, y + 1.95, bz + 0.1), 0, 2)
	# Left wall in front of the bed: shelf with plushies + books, frames, a
	# warm sconce, the toy box with plushies on the floor.
	_wallput(R + "@bed", "shelf_unit", "-x", fx, -1.75, y + 1.35, 0)
	_wallput(R + "@bed", "frame", "-x", fx, -2.2, y + 1.6, 2)
	_sconce(R + "@bed", "-x", fx, -2.0, y + 2.25, 0.6, 1)
	var toybox := _wallput(R, "toy_box", "-x", fx, -1.25, y)
	_put(R, "plush", Vector3(fx + 0.15, y + 9 * PU, -0.95), 1, 1)
	_put(R, "plant", Vector3(fx + 0.06, y, -0.55), 0, 0)
	# Right wall (pink|blue divider): dresser with lamp and plush, frames above.
	var dr := _wallput(R, "dresser", "+x", rx, -3.6, y, 2)
	_put(R, "plant", Vector3(dr.position.x + 0.12, y + 14 * PU, dr.position.z + 0.08), 0, 6)
	_put(R, "plush", Vector3(dr.position.x + 0.1, y + 14 * PU, dr.end.z - 0.45), 3, 2)
	_put(R, "lamp_table", Vector3(dr.position.x + 0.12, y + 14 * PU, dr.end.z - 1.0), 0, 1)
	_lamp(Vector3(dr.position.x - 0.15, y + 1.6, dr.end.z - 0.7), 0.5, 3.0, 0.2, Color(1.0, 0.62, 0.34), 0.5)
	_sconce(R, "-z", bz, 1.1, y + 2.1, 0.0, 1)
	_lamp(Vector3(1.2, y + 2.3, -2.2), 0.35, 4.0, 0.0, Color(1.0, 0.62, 0.36), 0.0)
	# Floor: pouf, blocks, basket, small plants in the front corners.
	_put(R, "pouf", Vector3(2.35, y, -1.4), 0, 0)
	_put(R, "toy_blocks", Vector3(0.6, y + PU, -1.0), 0, 3)
	_put(R, "plant", Vector3(rx - 0.5, y, -0.62), 0, 3)
	_put(R, "basket", Vector3(1.55, y, -0.7), 0, 1)
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
	# Low dresser (not a tall shelf) on the half-height divider so the pink
	# room's story scene stays visible from the camera side; globe on top.
	var bdr := _wallput(R, "dresser", "-x", lx, -2.0, y, 1)
	_put(R, "globe", Vector3(bdr.position.x + 0.1, y + 14 * PU, bdr.position.z + 0.15))
	_put(R, "book_stack", Vector3(bdr.position.x + 0.1, y + 14 * PU, bdr.end.z - 0.45), 1, 0)
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
					var runner := x >= fc(3.4) and x < fc(4.1)
					var sc := Color("b07a46") if yy == top - 1 else Color("efe7da")
					if runner and yy >= top - 2:
						# Stair runner: deep blue with a cream border stripe.
						sc = Color("e9dcc0") if (x == fc(3.4) or x == fc(4.1) - 1) else Color("3d5590").lerp(Color("4a64a4"), VoxelBuilder.hash3(Vector3i(x, yy, zz)) * 0.5)
					st.set_v(Vector3i(x, yy, z0 + zz), sc)
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
	_lamp(Vector3(lx + 0.5, y + 1.25, 0.8), 0.8, 3.0, 0.2)
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
	var rx := 8.75     # right exterior wall face: tall at night, faces the camera
	var fz := 4.75
	# ref3 bathroom: glass shower cubicle in the back-left corner, a wooden
	# vanity with a vessel basin and a tall mirror between two sconces on the
	# right wall (the wall the night camera looks at), window beside it, the
	# kid on her step stool at the sink turned to the camera; toilet in the
	# back-right corner, tub across the front, bath mats, plants.
	var shower := _put(R, "shower", Vector3(lx, y, bz), 0, 1)
	var glass := PropLib.instance("shower_glass", 1, false)
	glass.scale = Vector3.ONE * (PU / PropLib.FU)
	var gs := PropLib.size_of("shower_glass", 1)
	# Glass model spans x 2..15 / z 2..15 of the 16-cell tray (normalised to 0).
	glass.position = Vector3(lx + (2 + gs.x * 0.5) * PU, y + 2 * PU, bz + (2 + gs.z * 0.5) * PU)
	add_child(glass)
	_put(R, "bath_mat", Vector3(lx + 0.35, y, shower.end.z + 0.08), 0, 0)
	var toilet := _put(R, "toilet", Vector3(rx - 0.8, y, bz + 0.05), 0)
	_put(R, "basket", Vector3(toilet.position.x - 0.66, y, bz + 0.08), 0, 2)
	# Vanity + tall mirror on the right wall, a sconce either side.
	var vz := 1.6
	var vanity := _wallput(R, "vanity", "+x", rx, vz, y, 1)
	_spots["vanity"] = vanity
	_sconce(R + "@bed", "+x", rx, vanity.position.z - 0.28, y + 1.95, 0.55, 1)
	_sconce(R + "@bed", "+x", rx, vanity.end.z - 0.06, y + 1.95, 0.55, 1)
	var step := _put(R, "step_stool", Vector3(vanity.position.x - 0.5, y, vanity.get_center().z - 0.32), 1)
	_spots["step"] = step
	_put(R, "bath_mat", Vector3(vanity.position.x - 1.2, y, vanity.position.z + 0.1), 1, 1)
	_wallput(R + "@bed", "towel_rack", "+x", rx, vanity.end.z + 0.1, y + 0.95, 2)
	_put(R, "plant", Vector3(rx - 0.55, y, fz - 0.55), 0, 6)
	_wallput(R + "@bed", "wall_planter", "+x", rx, 4.45, y + 2.3, 2)
	_wallput(R + "@bed", "frame", "+x", rx, bz + 0.25, y + 1.7, 5)
	# Tub across the front of the room (low, never hides the sink scene).
	var tub := _put(R, "bathtub", Vector3(lx + 0.06, y, fz - PropLib.size_of("bathtub").z * PU - 0.04), 0)
	_put(R, "plant", Vector3(lx + 0.05, y, shower.end.z + 0.95), 0, 2)
	_wallput(R, "towel_rack", "-x", lx, shower.end.z + 0.3, y + 0.9, 1)
	# Warm overhead light so the room reads bright (ref3's bathroom glows).
	_lamp(Vector3(7.3, y + 2.6, 2.4), 0.45, 3.6, 0.0, Color(1.0, 0.74, 0.48), 0.0)
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
		# Right-hand lawns (seen beside the bathroom in the night shot).
		Vector3(13.5, 0, -6.0), Vector3(17.5, 0, -2.5), Vector3(16.0, 0, 3.5), Vector3(20.5, 0, -6.5),
		Vector3(10.5, 0, -9.0), Vector3(19.0, 0, -12.0), Vector3(23.0, 0, 1.0),
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
		else:
			_halo_pts.append({"pos": Vector3(lx + 0.3, 3.35, -9.3), "size": 2.0, "color": Color(1.0, 0.7, 0.35, 1.0)})
		_halo_pts.append({"pos": Vector3(lx + 3.5, 3.35, -14.3), "size": 2.0, "color": Color(1.0, 0.7, 0.35, 1.0)})
	# Lamp posts along the back garden path, in frame above the bedrooms at
	# night (ref3): glow voxels + halos only (no extra omni lights).
	for lp: Vector3 in [Vector3(-1.2, 0, -7.4), Vector3(10.6, 0, -6.6), Vector3(11.0, 0, 2.6)]:
		PropLib.place(o, "street_lamp", Vector3i(cc(lp.x), 0, cc(lp.z)), 0)
		_halo_pts.append({"pos": lp + Vector3(0.31, 3.35, 0.31), "size": 2.0, "color": Color(1.0, 0.7, 0.35, 1.0)})
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
	for k in 22:
		var fx0 := fc(-11.0) + k * 16
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
	# Upstairs office front windows (bed view only): frames + warm lit glass.
	for wdef: Array in UP_FRONT_WINDOWS:
		var ux0 := fc(wdef[0])
		var uw := fc(wdef[1]) - ux0
		var uy0 := fc(UF + 0.9)
		PropLib.window_frame(_g("front@bed"), Vector3i(ux0, uy0, fc(4.75)), uw, fc(1.3), 4, 0, 2, -1)
		var ufr := _g("front@bed")
		for a in range(ux0 + 1, ux0 + uw - 1):
			for yy in range(uy0 + 1, fc(UF + 2.2) - 1):
				var q := Vector3i(a, yy, fc(4.75) + 2)
				if ufr.has(q):
					continue
				var tt := float(yy - uy0) / 20.0
				fd.set_v(q, Color("9cc4dc").lerp(Color("e8f4fa"), tt))
				fn.set_v(q, Color("ffbf66").lerp(Color("ffe2a0"), tt * 0.6 + VoxelBuilder.hash3(q) * 0.25), true)
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
		var spots := [Vector3(-25, 0, -20.5), Vector3(-15, 0, -20.0), Vector3(-5, 0, -20.5), Vector3(5, 0, -20.0), Vector3(15, 0, -20.5), Vector3(25, 0, -20.0),
			Vector3(-26, 0, -5.0), Vector3(23, 0, -4.0),
			# Second row across the back gardens (their roofs + lit upstairs
			# windows fill the top band of the night shot, ref3).
			Vector3(-20, 0, -33.0), Vector3(-9, 0, -32.0), Vector3(2, 0, -33.0), Vector3(13, 0, -32.5), Vector3(24, 0, -33.0)]
		var styles := [1, 4, 2, 0, 5, 3, 2, 5, 3, 0, 4, 1, 2]
		# Neighbour houses drawn a little smaller than authored (0.2 m cells):
		# they read as a street of homes behind ours, roofs in frame (ref3).
		var hs: float = PropLib.scale_of("house") * 0.85
		# Mobile budget: the lit (night) street keeps only the houses the
		# bedroom camera can see.
		var night_skip := [0, 6, 7, 8, 12]
		for i in spots.size():
			if lit and i in night_skip:
				continue
			var c: Vector3 = spots[i] + Vector3(4.0, 0, 3.25)
			var rot := 0 if (i < 6 or i > 7) else (1 if i == 6 else 3)
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
			_hood_mat.albedo_color = Color(0.6, 0.6, 0.82)
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


## Soft volumetric sunbeams through the office's big back windows (ref1's
## warm light shafts): one additive, unshaded prism per window pane, merged
## into a single mesh (one draw call), fading from the glass to the floor.
## Direction matches the afternoon sun from lighting_profile().
const SHAFT_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint = vec3(1.0, 0.8, 0.5);
uniform float strength = 0.22;
void fragment() {
	ALBEDO = tint * COLOR.a * strength;
}
"""


func _build_sun_shafts() -> void:
	var dir := Vector3(0.3, -0.56, 0.77).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wins := [[-5.75, -4.05], [-3.65, -1.95]]
	for w: Array in wins:
		for pane in 2:
			var x0: float = lerpf(w[0], w[1], pane * 0.5) + 0.06
			var x1: float = lerpf(w[0], w[1], pane * 0.5 + 0.5) - 0.06
			var y0 := UF + 0.55
			var y1 := UF + 2.45
			var z := -4.85
			var tl := Vector3(x0, y1, z)
			var tr := Vector3(x1, y1, z)
			var bl := Vector3(x0, y0, z)
			var br := Vector3(x1, y0, z)
			var reach := func(p: Vector3) -> Vector3:
				return p + dir * ((p.y - UF) / -dir.y)
			var ftl: Vector3 = reach.call(tl)
			var ftr: Vector3 = reach.call(tr)
			var fbl: Vector3 = reach.call(bl)
			var fbr: Vector3 = reach.call(br)
			# Four long sides of the prism (top, bottom, left, right sheets).
			for q in [[tl, tr, ftr, ftl], [bl, br, fbr, fbl], [tl, bl, fbl, ftl], [tr, br, fbr, ftr]]:
				var a0: Vector3 = q[0]
				var a1: Vector3 = q[1]
				var b1: Vector3 = q[2]
				var b0: Vector3 = q[3]
				for tri in [[a0, a1, b1, 1.0, 1.0, 0.0], [a0, b1, b0, 1.0, 0.0, 0.0]]:
					for k in 3:
						st.set_color(Color(1, 1, 1, tri[3 + k] * 0.9 + 0.1 * (1.0 - tri[3 + k])))
						st.add_vertex(tri[k])
	_shafts = MeshInstance3D.new()
	_shafts.name = "SunShafts"
	_shafts.mesh = st.commit()
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SHAFT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	_shafts.material_override = m
	_shafts.visible = not _is_night
	add_child(_shafts)


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
	for room: String in _mb:
		var vb: VoxelBuilder = _mb[room]
		var mmi := _add_mesh(Mesher.build(vb, MU), "Micro_" + room.replace("@", "_"), true)
		if "@" in room:
			_view_meshes.append([mmi, room.split("@")[1]])
	_sb.clear()
	_fb.clear()
	_gb.clear()
	_mb.clear()


## GL Compatibility shades each mesh with at most 8 omni lights, and when
## more overlap it keeps whichever were paired first, so a room could lose its
## own lamps to the neighbours' (the dark blue room). Each lamp gets the
## render-layer bit of the room it stands in (plus bit 0 for the sims and
## anything added later); each mesh that touches more than 8 lamps listens
## only to the rooms that light it most, never more than 8 lamps in total.
const LIGHT_CAP := 8
const EXTERIOR_MESHES := ["Ground", "Trees", "BigTrees", "Garden", "HoodDay", "HoodNight", "Fine_ext", "Furniture_ext"]
const LAMP_ROOMS := ["office", "pink", "blue", "hall", "bath", "living", "kitchen", "facade", "street"]


func _lamp_room(p: Vector3) -> String:
	if p.z > 4.8 and p.x > -9.5 and p.x < 9.5:
		return "facade"
	if p.x < -9.0 or p.x > 8.9 or p.z < -5.0 or p.z > 4.8:
		return "street"
	if p.y < UF:
		return "living" if p.x < -1.0 else "kitchen"
	return _upper_room(p.x, p.z)


func _budget_lights() -> void:
	var lamps: Array[OmniLight3D] = []
	for n in find_children("*", "OmniLight3D", true, false):
		var l := n as OmniLight3D
		if l.is_in_group("vims_lamps") and float(l.get_meta("base_energy", 1.0)) > 0.01:
			lamps.append(l)
	if lamps.is_empty():
		return
	var lroom := PackedInt32Array()
	for l in lamps:
		var ri := LAMP_ROOMS.find(_lamp_room(l.position))
		lroom.append(ri)
		l.light_cull_mask = 1 | (1 << (ri + 1))
	var n_budget := 0
	for node in find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if m.mesh == null or m.name in ["SkyCard", "MoonDisc"] or m.get_parent() is Skeleton3D:
			continue
		var ext: bool = String(m.name) in EXTERIOR_MESHES
		var ab: AABB = m.transform * m.get_aabb() if m.get_parent() == self else m.global_transform * m.get_aabb()
		var per_room := {}   # room index -> [score, count]
		var total := 0
		for i in lamps.size():
			var l := lamps[i]
			var lp := l.position
			var cp := Vector3(clampf(lp.x, ab.position.x, ab.end.x), clampf(lp.y, ab.position.y, ab.end.y), clampf(lp.z, ab.position.z, ab.end.z))
			var d := lp.distance_to(cp)
			if d >= l.omni_range:
				continue
			total += 1
			var ri := lroom[i]
			if ext and ri < 7:
				continue
			var f := 1.0 - d / l.omni_range
			var e: Array = per_room.get(ri, [0.0, 0])
			e[0] += float(l.get_meta("base_energy", 1.0)) * f * f
			e[1] += 1
			per_room[ri] = e
		if total <= LIGHT_CAP and not ext:
			continue
		var order := per_room.keys()
		order.sort_custom(func(x, y): return per_room[x][0] > per_room[y][0])
		var bits := 0
		var used := 0
		for ri: int in order:
			var c: int = per_room[ri][1]
			if used + c > LIGHT_CAP:
				continue
			used += c
			bits |= 1 << (ri + 1)
		m.layers = bits if bits != 0 else (1 << 20 - 1)
		n_budget += 1
	if OS.get_environment("VIMS_STATS") != "":
		print("HOME_LIGHT_BUDGET lamps=", lamps.size(), " budgeted_meshes=", n_budget)


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
		if OS.get_environment("VIMS_STATS") != "":
			print("HOME_ACTOR ", look, " height_m=", float(a._meta.get("height", 0.0)) * a.skeleton.scale.y * a.scale.y)
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
		# Tucked in sideways: head on the pillows at the headboard (left wall),
		# feet towards the reading chair; the rig lies centred on its position.
		var lily := _place("bunny_girl", Vector3(bed.position.x + 0.98, y, bc.z), Vector3(bed.end.x + 2.0, y, bc.z), "lie")
		lily.lie_height = 10 * PU / lily.scale.y
		var ch: AABB = _spots["pink_chair"]
		var cc3 := ch.get_center()
		var jack := _place("dad", Vector3(cc3.x, y, cc3.z), Vector3(cc3.x - 1.0, y, cc3.z + 0.85), "sit_read", 7 * PU)
		var st: AABB = _spots["step"]
		var maya := _place("cat_girl", Vector3(st.get_center().x, y + 6 * PU, st.get_center().z), Vector3(st.get_center().x + 0.55, y, st.get_center().z + 1.6), "brush_teeth")
		var cu: AABB = _spots["dog_cushion"]
		var dog := _place("beagle", Vector3(cu.get_center().x, y + 3 * PU, cu.get_center().z), Vector3(cu.get_center().x + 1.0, y, cu.get_center().z + 1.2), "sleep")
		Game.show_bubble(jack, {"text": "Read Story", "icon": "book_open", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(maya, {"text": "Brush Teeth", "icon": "brush", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(dog, {"icon": "zzz", "kind": "emote", "id": "action"})
		lily.set_pose("lie")
		# Propped up on the pillows so her face reads from the high camera.
		lily.rotation.x = 0.42
		if _blanket == null:
			_blanket = PropLib.instance("blanket", 0)
			_blanket.scale = Vector3.ONE * (PU / PropLib.FU)
			add_child(_blanket)
		_blanket.position = Vector3(bed.position.x + 1.3, y + 10 * PU, bc.z)
		_blanket.rotation_degrees.y = 90.0
		_blanket.visible = true
	else:
		if _blanket:
			_blanket.visible = false
		var jack := _place("dad", _spots["dad_seat"], _spots["dad_look"], "type", 13 * MU)
		actors["bunny_girl"].rotation.x = 0.0
		var stl: AABB = _spots["stool"]
		var lily := _place("bunny_girl", Vector3(stl.get_center().x, y, stl.get_center().z), Vector3(-4.45, y, -3.7), "sit_paint", 6 * PU)
		var maya := _place("cat_girl", Vector3(-2.85, y, -0.8), Vector3(-2.2, y, 0.5), "play")
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
		var lamps := get_tree().get_nodes_in_group("vims_lamps").filter(func(l): return l is OmniLight3D and l.visible)
		var over := []
		for mi in find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var ab: AABB = mi.global_transform * mi.get_aabb()
			var n := 0
			for l: OmniLight3D in lamps:
				var r := l.omni_range
				if (l.light_cull_mask & mi.layers) != 0 and ab.grow(r).has_point(l.global_position):
					n += 1
			if n > 8:
				over.append([mi.name, n])
		print("HOME_LIGHTS visible=", lamps.size(), " over8=", over)
		var groups := {}
		for gi in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
			if not gi.is_visible_in_tree():
				continue
			var key := String(gi.get_parent().name) if gi.get_parent() != self else String(gi.name).split("_")[0]
			var surf := 1
			if gi is MeshInstance3D and gi.mesh:
				surf = gi.mesh.get_surface_count()
			groups[key] = groups.get(key, 0) + surf
		print("HOME_GEOM ", groups)
		print("HOME_TRIS total=", tot, " meshes=", rows.size(), " top=", rows.slice(0, 60), " lights=", get_tree().get_nodes_in_group("vims_lamps").size())
	if _frames == 2 and OS.get_environment("VIMS_HOME_CAM") != "":
		# Debug: VIMS_HOME_CAM="x,y,z,yaw,pitch,dist" overrides the shot camera.
		var c := OS.get_environment("VIMS_HOME_CAM").split_floats(",")
		var rig := get_viewport().get_camera_3d().get_parent()
		if rig and rig.has_method("apply") and c.size() >= 6:
			rig.apply({"target": Vector3(c[0], c[1], c[2]), "yaw": c[3], "pitch": c[4], "distance": c[5]})
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
	var v := "bed"
	if hit.x < -1.0:
		v = "office_in" if o.x < -1.2 else "office"
	if v != wall_view:
		set_wall_view(v)
