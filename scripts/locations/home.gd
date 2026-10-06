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

const U := 0.0625          # furniture grid (PropLib.U)
const C := 0.125           # structure grid
const UF := 3.0            # upstairs floor height (m)
const VIEWS := ["office", "bed"]
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
const W_BLUE := Color("6f84c4")
const W_HALL := Color("efe1c6")
const W_LIVING := Color("e9dcc2")
const W_KITCHEN := Color("dfe8d6")
const FLOOR_WOOD := Color("c98b52")
const FLOOR_LIGHT := Color("d9a56c")

var actors := {}                 # key -> SimActor
var wall_view := "office"
var _sb := {}                    # structure groups "zone|sig|part" -> VoxelBuilder
var _fb := {}                    # furniture builders room -> VoxelBuilder
var _wall_nodes := {}            # sig -> {part -> Array[MeshInstance3D]}
var _hood_day: MeshInstance3D
var _hood_night: MeshInstance3D
var _glass_day: MeshInstance3D
var _glass_night: MeshInstance3D
var _moon: MeshInstance3D
var _is_night := false
var _view_timer := 0.0
var _auto_view := true
var _halo_pts := []
var _halos: MultiMeshInstance3D
var _blanket: MeshInstance3D
var _night_tint: Array[MeshInstance3D] = []   # exterior meshes darkened at night


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
	PropLib.set_halo_strength(_halos, 1.0 if _is_night else 0.6)
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
		"sun_heading": 205.0, "sun_elev": 36.0, "sun_energy": 1.55,
		"ambient_day": Color(0.9, 0.88, 0.86), "ambient_energy": 0.72,
		"ambient_night": Color(0.36, 0.42, 0.64), "ambient_night_energy": 0.34, "lamp_night_mult": 3.2,
		"sky_day": Color(0.64, 0.8, 0.94), "sky_night": Color(0.07, 0.09, 0.22),
		"fog_day": Color(0.9, 0.9, 0.88), "fog_night": Color(0.1, 0.12, 0.28), "fog_density": 0.004,
		"moon_heading": 150.0, "moon_energy": 0.3,
		"shadow_distance": 40.0,
		"post_day": {"focus_y": 0.52, "band": 0.24, "falloff": 0.22, "blur_px": 5.0, "top_boost": 1.2},
		"post_night": {"focus_y": 0.46, "band": 0.21, "falloff": 0.22, "blur_px": 7.0, "top_boost": 1.35},
	}


func get_actor(key: String) -> SimActor:
	return actors.get(key, null)


func apply_preset(preset: String) -> void:
	_stage(preset)
	set_wall_view("bed" if preset == "home_night" else "office")
	_auto_view = false


func set_wall_view(view: String) -> void:
	wall_view = view
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


# =================================================================== helpers

static func cc(m: float) -> int:
	return roundi(m * 8.0)


static func fc(m: float) -> int:
	return roundi(m * 16.0)


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
		vb.jitter = 0.06
		_fb[room] = vb
	return _fb[room]


## Place a prop with its footprint min corner at `pos` (metres). Returns its box in metres.
func _put(room: String, pname: String, pos: Vector3, rot := 0, v := 0) -> AABB:
	var at := Vector3i(fc(pos.x), fc(pos.y), fc(pos.z))
	var bb := PropLib.place(_f(room), pname, at, rot, v)
	return AABB(bb.position * U, bb.size * U)


## Place a prop centred on (x, z) metres.
func _putc(room: String, pname: String, x: float, y: float, z: float, rot := 0, v := 0) -> AABB:
	var rs := PropLib.rotated_size(pname, rot, v)
	return _put(room, pname, Vector3(x - rs.x * U * 0.5, y, z - rs.z * U * 0.5), rot, v)


func _use(bb: AABB, title: String, acts: Array, spot := Vector3.INF) -> Interactable:
	var s := spot if spot != Vector3.INF else bb.get_center() + Vector3(0, -bb.size.y * 0.5, 0)
	var it := Interactable.attach(self, title, acts, Vector3(maxf(bb.size.x, 0.2), maxf(bb.size.y, 0.2), maxf(bb.size.z, 0.2)), bb.get_center(), s)
	it.name = title.replace(" ", "")
	return it


func _lamp(pos: Vector3, energy := 1.0, rng := 3.5, day_factor := 0.25, col := Color(1.0, 0.66, 0.36), halo := 0.9) -> void:
	PropLib.add_light(self, pos, col, energy, rng, day_factor)
	if halo > 0.0:
		_halo_pts.append({"pos": pos, "size": halo * 1.4, "color": Color(1.25, 0.8, 0.4, 1.0)})


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
		"bath": return _tiles(Color("eef2f4"), Color("c9d9e4"))
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
					return Color("dfe9ec") if posmod(q.x + q.z + q.y, 2) == 0 else Color("cbdde3")
				return Color("f2e8d6") if posmod(q.y, 24) != 9 else Color("c9b48f")
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
	var cneg = _wall_col(neg)
	var cpos = _wall_col(pos)
	for a in range(a0, a1):
		for ry in 22:
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
				if ry == 0 and side != "ext":
					col = Color("8a5a36") if side != "bath" else Color("c9d3da")
				elif ry == 0:
					col = FOUND
				if ry == 21:
					col = CAP
				elif ry == 20 and side != "ext":
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
	_wall(0, 4.75, -9, -1, 0, "living", "ext", both_low)
	_wall(0, 4.75, -1, 8.75, 0, "kitchen", "ext", both_low, [[0.5, 1.6, 0.0, 2.1]])
	_wall(2, -1.0, -5, 5, 0, "living", "kitchen", both_tall, [[-1.0, 1.5, 0.0, 2.2]])
	# ---- Upstairs walls.
	# Back exterior wall: big office windows, bedroom windows.
	var back_holes := [[-6.25, -4.25, 0.45, 2.45], [-3.95, -1.95, 0.45, 2.45], [0.9, 2.4, 0.9, 2.2], [6.4, 7.8, 0.9, 2.2]]
	_wall(0, -5.0, -9, -1, 1, "ext", "office", both_tall, back_holes)
	_wall(0, -5.0, -1, 3.5, 1, "ext", "pink", both_tall, back_holes)
	_wall(0, -5.0, 3.5, 9, 1, "ext", "blue", both_tall, back_holes)
	# Left exterior (office L wall).
	_wall(2, -9.0, -4.75, 5, 1, "ext", "office", both_tall, [[2.0, 3.6, 0.9, 2.3]])
	# Front exterior: always cut.
	_wall(0, 4.75, -9, -4.5, 1, "office", "ext", {"office": "none", "bed": "low"})
	_wall(0, 4.75, -4.5, 9, 1, "office", "ext", both_low)
	# Right exterior.
	_wall(2, 8.75, -4.75, 0.0, 1, "blue", "ext", both_low)
	_wall(2, 8.75, 0.0, 4.75, 1, "bath", "ext", both_low)
	# Office | pink+hall divider (low from the office, tall for the bedrooms).
	_wall(2, -1.0, -4.75, 0.0, 1, "office", "pink", {"office": "low", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	_wall(2, -1.0, 0.0, 4.75, 1, "office", "hall", {"office": "low", "bed": "tall"}, [[1.4, 2.6, 0.0, 2.15]])
	# Bedroom fronts onto the hall.
	_wall(0, 0.0, -0.75, 5.5, 1, "pink", "hall", both_low, [[2.3, 3.2, 0.0, 2.1], [4.2, 5.2, 0.0, 2.1]])
	_wall(0, 0.0, 5.5, 8.75, 1, "blue", "bath", {"office": "low", "bed": "tall"})
	# Pink | blue divider, hall | bath divider.
	_wall(2, 3.5, -4.75, 0.0, 1, "pink", "blue", {"office": "low", "bed": "tall"})
	_wall(2, 5.5, 0.25, 4.75, 1, "hall", "bath", {"office": "low", "bed": "tall"}, [[3.4, 4.4, 0.0, 2.1]])


# =================================================================== rooms

func _windows_upstairs() -> void:
	# Office big windows (back wall, two units).
	for wx: float in [-6.25, -3.95]:
		PropLib.window_frame(_f("office"), Vector3i(fc(wx), fc(UF + 0.45), fc(-5.0)), fc(2.0), fc(2.0), 4, 0, 3, 1)
	PropLib.window_frame(_f("office"), Vector3i(fc(-9.0), fc(UF + 0.9), fc(2.0)), fc(1.6), fc(1.4), 4, 2, 2, 1)
	PropLib.window_frame(_f("pink"), Vector3i(fc(0.9), fc(UF + 0.9), fc(-5.0)), fc(1.5), fc(1.3), 4, 0, 2, 1, Color("ffffff"), Color("f3c0cf"))
	PropLib.window_frame(_f("blue"), Vector3i(fc(6.4), fc(UF + 0.9), fc(-5.0)), fc(1.4), fc(1.3), 4, 0, 2, 1)


func _build_office() -> void:
	var R := "office"
	var y := UF
	var fx := -8.75   # inner face of the L wall
	var bz := -4.75   # inner face of the back wall
	_windows_upstairs()
	# --- Work corner on the L wall.
	var desk := _put(R, "desk", Vector3(fx, y, -2.85), 1)
	var dy := y + 12 * U
	_put(R, "monitor", Vector3(fx + 0.05, dy, -2.2), 1, 0)
	_put(R, "monitor", Vector3(fx + 0.12, dy, -2.9), 1, 1)
	_put(R, "keyboard", Vector3(fx + 0.38, dy, -2.05), 1)
	_put(R, "laptop", Vector3(fx + 0.3, dy, -1.55), 1)
	_put(R, "mug", Vector3(fx + 0.55, dy, -1.2))
	_put(R, "pencil_cup", Vector3(fx + 0.1, dy, -1.3))
	_put(R, "desk_lamp", Vector3(fx + 0.05, dy, -2.85), 1)
	_put(R, "plant", Vector3(fx + 0.02, dy, -1.62), 0, 3)
	_put(R, "book_stack", Vector3(fx + 0.45, dy, -2.75), 1, 1)
	var chair := _putc(R, "office_chair", fx + 1.25, y, -2.0, 3)
	_put(R, "filing_cabinet", Vector3(fx, y, -1.0), 1)
	_put(R, "printer", Vector3(fx + 0.02, y + 12 * U, -0.98), 1)
	_put(R, "plant", Vector3(fx + 0.05, y, -0.45), 0, 2)
	_put(R, "corkboard", Vector3(fx, y + 1.3, -3.3), 1, 1)
	_put(R, "wall_shelf", Vector3(fx, y + 2.25, -2.0), 1, 2)
	_put(R, "plant", Vector3(fx + 0.02, y + 2.25 + U, -1.5), 0, 2)
	_put(R, "frame", Vector3(fx, y + 1.45, -4.05), 1, 0)
	_put(R, "frame", Vector3(fx, y + 1.05, -3.5), 1, 1)
	_put(R, "frame", Vector3(fx, y + 1.5, -1.25), 1, 6)
	_put(R, "sconce", Vector3(fx, y + 1.55, -0.6), 1)
	_lamp(Vector3(fx + 0.35, y + 1.75, -0.45), 0.9, 3.0, 0.35)
	_put(R, "wall_shelf", Vector3(fx, y + 2.0, -0.2), 1, 0)
	# --- Corner shelves on the back wall.
	_put(R, "bookshelf", Vector3(fx + 0.05, y, bz), 0, 4)
	_put(R, "bookshelf", Vector3(fx + 1.1, y, bz), 0, 0)
	_put(R, "lamp_table", Vector3(fx + 1.35, y + 30 * U, bz + 0.05), 0, 3)
	_lamp(Vector3(fx + 1.55, y + 2.25, bz + 0.35), 0.7, 2.6, 0.4)
	_put(R, "plant", Vector3(-6.75, y, bz + 0.05), 0, 5)
	_put(R, "sconce", Vector3(-6.62, y + 1.6, bz), 0, 1)
	# --- Window wall: curtains, sill plants, ivy.
	for cx: float in [-6.6, -4.25, -1.95]:
		_put(R, "curtain", Vector3(cx, y + 0.1, bz), 0, 0)
	for wx: float in [-6.25, -3.95]:
		for k in 3:
			_put(R, "plant", Vector3(wx + 0.2 + k * 0.62, y + 0.45, bz - 0.06), 0, [0, 6, 2][posmod(k + int(wx), 3)])
		_put(R, "ivy", Vector3(wx + 0.12, y + 0.95, bz + 0.02), 0, 2)
		_put(R, "ivy", Vector3(wx + 1.62, y + 1.3, bz + 0.02), 0, 1)
		_put(R, "hanging_plant", Vector3(wx + 0.78, y + 1.35, bz + 0.12), 0, absi(int(wx)))
	# --- Art corner: easel + stool + paint table on the pink rug.
	PropLib.rug(_f(R), Vector3i(fc(-6.4), fc(y), fc(-3.9)), fc(2.6), fc(2.1), "patch_pink")
	# The easel is its own instance, turned so the canvas shows in profile like ref1.
	var easel_mi := PropLib.instance("easel", 0)
	easel_mi.position = Vector3(-5.05, y, -3.3)
	easel_mi.rotation_degrees.y = -28.0
	add_child(easel_mi)
	var easel := AABB(Vector3(-5.5, y, -3.75), Vector3(0.9, 1.7, 0.9))
	var stool := _putc(R, "stool", -5.75, y, -2.75, 0, 1)
	var ptable := _putc(R, "side_table", -4.25, y, -3.0, 3, 1)
	_put(R, "frame", Vector3(-4.2, y + 2.35, bz), 0, 5)
	# --- Music corner.
	var piano := _putc(R, "piano", -2.6, y, -4.45, 0)
	var bench := _putc(R, "piano_bench", -2.6, y, -3.7, 0)
	var guitar := _put(R, "guitar", Vector3(-1.45, y, -3.4), 3)
	_put(R, "plant", Vector3(-1.62, y, -4.68), 0, 1)
	_put(R, "plant", Vector3(-3.95, y, -4.65), 0, 4)
	# --- Play area.
	PropLib.rug(_f(R), Vector3i(fc(-7.1), fc(y), fc(-1.0)), fc(2.7), fc(2.2), "check_blue")
	PropLib.rug(_f(R), Vector3i(fc(-3.9), fc(y), fc(-1.7)), fc(2.6), fc(2.8), "blue_braid")
	var ball := _put(R, "tennis_ball", Vector3(-5.0, y + U, 0.85))
	var dogbed := _putc(R, "dog_bed", -3.55, y, 1.75, 0)
	var toybox := _putc(R, "toy_box", -1.75, y, 2.1, 3)
	_put(R, "soccer_ball", Vector3(-2.45, y + U, 2.75))
	_put(R, "toy_blocks", Vector3(-3.2, y + U, 0.2), 0, 1)
	_put(R, "toy_robot", Vector3(-2.55, y + U, 0.55), 1)
	_put(R, "toy_blocks", Vector3(-2.3, y, 2.7), 0, 0)
	_put(R, "plush", Vector3(-1.6, y + U, 0.0), 2, 1)
	_put(R, "bookshelf", Vector3(-1.375, y, -2.6), 3, 3)
	_put(R, "plant", Vector3(-1.33, y + 18 * U, -2.5), 0, 0)
	_put(R, "plant", Vector3(-1.62, y, 4.15), 0, 1)
	# --- Balcony railing over the living room, with planters.
	PropLib.railing(_f(R), Vector3i(fc(-8.75), fc(y), fc(1.5) - 2), fc(4.25) + 2, 0)
	PropLib.railing(_f(R), Vector3i(fc(-4.5), fc(y), fc(1.5) - 2), fc(3.25) + 2, 2)
	for k in 4:
		_put(R, "plant", Vector3(-8.35 + k * 1.05, y + 15 * U, 1.38), 0, [2, 0, 6, 2][k])
	_put(R, "plant", Vector3(-4.62, y + 15 * U, 3.0), 0, 2)
	_put(R, "plant", Vector3(-8.6, y, -0.2), 0, 1)

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
	])
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
	_put(R, "bookshelf", Vector3(fx, 0, 0.95), 1, 0)
	_put(R, "plant", Vector3(fx + 0.05, 30 * U, 1.05), 0, 2)
	_put(R, "nightstand", Vector3(fx + 0.02, 0, 2.05), 1, 0)
	_put(R, "lamp_table", Vector3(fx + 0.1, 10 * U, 2.15), 0, 0)
	_lamp(Vector3(fx + 0.45, 0.95, 2.3), 1.0, 3.2, 0.7)
	_put(R, "frame", Vector3(fx, 1.25, 2.0), 1, 7)
	_put(R, "frame", Vector3(fx, 1.55, 2.4), 1, 2)
	_put(R, "bookshelf", Vector3(fx, 0, 2.7), 1, 2)
	_put(R, "globe", Vector3(fx + 0.1, 30 * U, 2.85))
	_put(R, "lamp_floor", Vector3(fx + 0.1, 0, 3.85))
	_lamp(Vector3(fx + 0.35, 1.75, 4.05), 1.1, 3.6, 0.6)
	_put(R, "plant", Vector3(fx + 0.6, 0, 4.2), 0, 4)
	_put(R, "sconce", Vector3(fx, 1.6, 0.55), 1, 0)
	_put(R, "plant", Vector3(fx + 0.05, 0, 0.3), 0, 5)
	PropLib.rug(_f(R), Vector3i(fc(-7.7), 0, fc(1.4)), fc(2.6), fc(2.9), "red_kilim")
	_put(R, "coffee_table", Vector3(-7.25, U, 2.2), 1)
	_put(R, "book_stack", Vector3(-7.0, U + 8 * U, 2.45), 0, 1)
	_put(R, "sofa", Vector3(-6.05, 0, 1.6), 3, 0)
	_put(R, "armchair", Vector3(-7.6, 0, 4.0), 2, 0)
	_put(R, "plant", Vector3(-4.95, 0, 1.75), 0, 1)
	_put(R, "bookshelf", Vector3(-5.6, 0, 4.25), 2, 1)
	_put(R, "lamp_table", Vector3(-5.2, 30 * U, 4.4), 0, 0)
	_lamp(Vector3(-5.0, 2.1, 4.3), 0.8, 3.0, 0.5)
	_put(R, "bookshelf", Vector3(fx, 0, -2.25), 1, 0)
	_put(R, "nightstand", Vector3(fx + 0.02, 0, -0.9), 1, 0)
	_put(R, "lamp_table", Vector3(fx + 0.1, 10 * U, -0.8), 0, 0)
	_put(R, "tv", Vector3(-3.2, 0, -4.7), 0)
	_put(R, "sofa", Vector3(-4.6, 0, -1.6), 2, 2)
	_put(R, "dining_table", Vector3(-7.9, 0, -3.8), 0)
	var sofa := AABB(Vector3(-6.05, 0, 1.6), Vector3(0.9, 0.8, 2.1))
	_use(sofa, "Sofa", [
		_act("relax", "Relax", "sofa", 30, {"energy": 0.1, "fun": 0.05}, {"pose": "sit"}),
		_act("nap_sofa", "Nap", "zzz", 60, {"energy": 0.3}, {"pose": "sleep"}),
	])
	_use(AABB(Vector3(-3.2, 0, -4.7), Vector3(1.75, 1.4, 0.5)), "TV", [
		_act("watch", "Watch TV", "tv", 60, {"fun": 0.25}, {"pose": "sit"}),
	], Vector3(-2.3, 0, -2.0))


func _build_pink() -> void:
	var R := "pink"
	var y := UF
	var fx := -0.75
	var bz := -4.75
	PropLib.rug(_f(R), Vector3i(fc(-0.35), fc(y), fc(-3.7)), fc(3.1), fc(2.9), "patch_pink")
	# Bed with its headboard on the left wall (like ref3), dad's reading chair beside it.
	var bed := _put(R, "bed", Vector3(-0.73, y, -3.95), 1, 0)
	_put(R, "nightstand", Vector3(-0.72, y, bz + 0.05), 0, 2)
	_put(R, "lamp_table", Vector3(-0.62, y + 10 * U, bz + 0.12), 0, 1)
	_lamp(Vector3(-0.42, y + 0.95, bz + 0.45), 1.4, 3.6, 0.2)
	_put(R, "book_stack", Vector3(-0.3, y + 10 * U, bz + 0.1), 0, 2)
	_put(R, "plush", Vector3(-0.6, y + 13 * U, -3.85), 1, 0)
	_put(R, "plush", Vector3(1.1, y + 5 * U, -3.0), 3, 2)
	_put(R, "frame", Vector3(fx, y + 1.45, -3.75), 1, 2)
	_put(R, "frame", Vector3(fx, y + 1.35, -2.85), 1, 5)
	_put(R, "frame", Vector3(fx, y + 1.8, -2.25), 1, 6)
	_put(R, "wall_shelf", Vector3(fx, y + 1.95, -4.4), 1, 1)
	_put(R, "wall_shelf", Vector3(0.6, y + 1.65, bz), 0, 1)
	_put(R, "plant", Vector3(0.75, y + 1.65 + U, bz + 0.02), 0, 6)
	_put(R, "frame", Vector3(1.4, y + 1.25, bz), 0, 1)
	_put(R, "dresser", Vector3(2.45, y, bz + 0.05), 0, 2)
	_put(R, "lamp_table", Vector3(2.5, y + 14 * U, bz + 0.1), 0, 1)
	_lamp(Vector3(2.7, y + 1.3, bz + 0.45), 1.0, 3.0, 0.2)
	_put(R, "plant", Vector3(3.0, y + 14 * U, bz + 0.1), 0, 6)
	_put(R, "frame", Vector3(2.55, y + 1.55, bz), 0, 1)
	_put(R, "bookshelf", Vector3(3.5 - 0.4, y, -1.6), 3, 1)
	_put(R, "plant", Vector3(3.08, y + 30 * U, -1.45), 0, 0)
	_put(R, "plant", Vector3(fx + 0.05, y, -0.6), 0, 1)
	_put(R, "plant", Vector3(2.55, y, -3.9), 0, 4)
	_put(R, "toy_box", Vector3(fx + 0.05, y, -1.75), 1)
	var chair := _putc(R, "chair", 0.75, y, -4.4, 0, 2)
	_put(R, "plush", Vector3(1.9, y + U, -1.3), 3, 2)
	_put(R, "toy_blocks", Vector3(0.6, y + U, -2.2), 0, 3)
	_put(R, "sconce", Vector3(fx, y + 1.6, -1.15), 1, 1)
	_lamp(Vector3(fx + 0.4, y + 1.8, -1.0), 0.8, 2.8, 0.2)
	_lamp(Vector3(1.4, y + 2.25, -2.2), 0.8, 4.5, 0.0, Color(1.0, 0.76, 0.52), 0.0)
	_use(bed, "Pink Bed", [
		_act("sleep", "Sleep", "bed", 480, {"energy": 1.0}, {"pose": "sleep", "task": "Go to Sleep"}),
		_act("story", "Read Story", "book_open", 20, {"social": 0.2, "fun": 0.1}, {"pose": "sit_read", "task": "Read Story", "who": ["adult"]}),
		_act("nap", "Nap", "zzz", 60, {"energy": 0.3}, {"pose": "sleep"}),
	], chair.get_center() - Vector3(0, chair.size.y * 0.5, 0))


func _build_blue() -> void:
	var R := "blue"
	var y := UF
	var bz := -4.75
	PropLib.rug(_f(R), Vector3i(fc(4.3), fc(y), fc(-2.6)), fc(2.2), fc(2.2), "round_blue")
	var bed := _put(R, "bed", Vector3(4.25, y, bz + 0.02), 0, 1)
	_put(R, "nightstand", Vector3(5.5, y, bz + 0.05), 0, 3)
	_put(R, "rocket_lamp", Vector3(5.6, y + 10 * U, bz + 0.15), 0)
	_put(R, "lamp_table", Vector3(5.85, y + 10 * U, bz + 0.12), 0, 2)
	_lamp(Vector3(5.95, y + 1.05, bz + 0.45), 1.2, 3.2, 0.2, Color(1.0, 0.8, 0.6))
	_put(R, "frame", Vector3(4.6, y + 1.55, bz), 0, 4)
	_put(R, "frame", Vector3(3.75, y + 1.35, -3.2), 1, 8)
	PropLib.string_lights(_f(R), Vector3i(fc(4.0), fc(y + 2.45), fc(bz) + 1), Vector3i(fc(8.6), fc(y + 2.45), fc(bz) + 1), 7, 4.0, true)
	_put(R, "telescope", Vector3(7.6, y, -3.9), 3)
	_put(R, "desk", Vector3(8.75 - 0.6, y, -2.6), 3, 1)
	_put(R, "globe", Vector3(8.35, y + 10 * U, -2.4))
	_put(R, "book_stack", Vector3(8.3, y + 10 * U, -1.7), 0, 2)
	_put(R, "chair", Vector3(7.45, y, -2.3), 1, 3)
	_put(R, "bookshelf", Vector3(3.75, y, -1.95), 1, 2)
	_put(R, "plant", Vector3(3.8, y + 30 * U, -1.85), 0, 2)
	_put(R, "plush", Vector3(5.0, y + U, -1.5), 0, 1)
	PropLib.rug(_f(R), Vector3i(fc(5.6), fc(y), fc(-2.9)), fc(1.8), fc(1.8), "star")
	_put(R, "toy_blocks", Vector3(6.1, y + U, -2.2), 0, 1)
	_put(R, "wall_shelf", Vector3(3.75, y + 1.7, -3.9), 1, 2)
	_put(R, "globe", Vector3(3.8, y + 1.7 + U, -3.6))
	_put(R, "frame", Vector3(7.95, y + 1.5, bz), 0, 3)
	_put(R, "toy_box", Vector3(6.9, y, -0.75), 2)
	_put(R, "plant", Vector3(8.15, y, -0.6), 0, 4)
	_put(R, "plant", Vector3(6.55, y + 0.85, bz + 0.25), 0, 3)
	_lamp(Vector3(6.3, y + 2.2, bz + 0.6), 0.6, 3.0, 0.1, Color(1.0, 0.88, 0.74), 0.0)
	_lamp(Vector3(5.6, y + 2.0, -2.2), 0.6, 3.5, 0.0, Color(1.0, 0.88, 0.74), 0.0)
	_use(bed, "Star Bed", [
		_act("sleep", "Sleep", "bed", 480, {"energy": 1.0}, {"pose": "sleep", "task": "Go to Sleep"}),
		_act("story", "Read Story", "book_open", 20, {"social": 0.2}, {"pose": "sit_read", "who": ["adult"]}),
	])
	_use(AABB(Vector3(7.6, y, -4.3), Vector3(0.5, 1.4, 0.5)), "Telescope", [
		_act("stargaze", "Stargaze", "star", 30, {"fun": 0.2}, {"skill": "Logic", "pose": "idle"}),
	])


func _build_hall() -> void:
	var R := "hall"
	var y := UF
	# Stairs down to the kitchen (in the stair well x 3..5.25, z 1.75..4.75).
	var st := _f(R)
	for k in 16:
		var z0 := fc(1.75) + k * 3
		var top := fc(UF) - k * 3
		for x in range(fc(3.1), fc(4.4)):
			for yy in range(maxi(top - 3, 0), top):
				for zz in 3:
					st.set_v(Vector3i(x, yy, z0 + zz), Color("b07a46") if yy == top - 1 else Color("efe7da"))
	PropLib.railing(st, Vector3i(fc(3.0), fc(y), fc(1.75) - 2), fc(2.25), 0)
	PropLib.railing(st, Vector3i(fc(5.25) - 2, fc(y), fc(1.75) - 2), fc(3.0), 2)
	PropLib.railing(st, Vector3i(fc(3.0) - 2, fc(y), fc(1.75)), fc(3.0), 2)
	# Dog cushion, plants, frames, sconces.
	PropLib.rug(st, Vector3i(fc(-0.3), fc(y), fc(3.0)), fc(1.8), fc(1.4), "round_cream")
	var cushion := _putc(R, "dog_cushion", 1.15, y, 2.25)
	_put(R, "dog_bowl", Vector3(2.3, y, 0.45))
	_put(R, "plant", Vector3(-0.65, y, 0.4), 0, 1)
	_put(R, "bookshelf", Vector3(-0.75, y, 1.2), 1, 1)
	_put(R, "lamp_table", Vector3(-0.55, y + 12 * U, 1.35), 0, 0)
	_put(R, "plant", Vector3(-0.6, y + 12 * U, 1.85), 0, 6)
	_lamp(Vector3(-0.3, y + 1.0, 1.6), 1.0, 3.0, 0.2)
	_put(R, "frame", Vector3(-0.75, y + 1.4, 3.0), 1, 7)
	_put(R, "frame", Vector3(-0.75, y + 1.5, 3.9), 1, 6)
	_put(R, "sconce", Vector3(-0.75, y + 1.6, 2.6), 1, 0)
	_lamp(Vector3(-0.35, y + 1.8, 2.7), 0.9, 3.5, 0.2)
	_put(R, "sconce", Vector3(5.5 - 6 * U, y + 1.6, 1.2), 3, 0)
	_lamp(Vector3(5.0, y + 1.8, 1.3), 0.8, 3.0, 0.2)
	_put(R, "plant", Vector3(2.5, y, 4.2), 0, 5)
	_lamp(Vector3(1.4, y + 2.1, 2.6), 0.7, 3.5, 0.0, Color(1.0, 0.74, 0.45), 0.0)
	_put(R, "toy_blocks", Vector3(0.2, y, 4.0), 0, 2)
	_use(cushion, "Dog Cushion", [
		_act("nap", "Nap", "zzz", 60, {"energy": 0.4}, {"pose": "sleep", "who": ["dog"]}),
	])


func _build_bath() -> void:
	var R := "bath"
	var y := UF
	var bz := 0.25
	var shower := _put(R, "shower", Vector3(5.75, y, bz), 0)
	_put(R, "bath_mat", Vector3(6.0, y, 1.35), 0, 0)
	var vanity := _put(R, "vanity", Vector3(7.35, y, bz), 0)
	_put(R, "sconce", Vector3(8.4, y + 1.65, bz), 0, 1)
	_lamp(Vector3(8.5, y + 1.85, bz + 0.45), 1.1, 3.0, 0.2)
	_put(R, "towel_rack", Vector3(6.85, y + 0.2, bz), 0, 2)
	_lamp(Vector3(7.2, y + 2.3, 2.4), 0.8, 4.0, 0.0, Color(1.0, 0.74, 0.5), 0.0)
	_put(R, "plant", Vector3(8.35, y, 0.35), 0, 4)
	var tub := _put(R, "bathtub", Vector3(6.85, y, 3.85), 2)
	var toilet := _put(R, "toilet", Vector3(5.8, y, 3.35), 1)
	_put(R, "bath_mat", Vector3(7.3, y, 3.1), 0, 1)
	_put(R, "plant", Vector3(8.35, y, 2.2), 0, 0)
	_putc(R, "stool", 7.85, y, 1.25, 0, 2)
	PropLib.rug(_f(R), Vector3i(fc(7.25), fc(y), fc(1.0)), fc(1.2), fc(0.8), "round_blue")
	_put(R, "wall_shelf", Vector3(5.5 + 2 * U, y + 1.45, 2.0), 1, 2)
	_put(R, "plant", Vector3(5.5 + 3 * U, y + 1.45 + U, 2.15), 0, 3)
	_put(R, "frame", Vector3(5.5 + 2 * U, y + 1.3, 2.95), 1, 4)
	_put(R, "plant", Vector3(8.25, y, 4.15), 0, 2)
	_put(R, "plant", Vector3(8.0, y + 14 * U, 0.3), 0, 3)
	var glass := PropLib.instance("shower_glass", 0, false)
	var gs := PropLib.size_of("shower_glass")
	glass.position = Vector3(5.75 + U * 1 + gs.x * U * 0.5, y + U, bz + U + gs.z * U * 0.5)
	add_child(glass)
	_use(shower, "Shower", [_act("shower", "Take Shower", "shower", 20, {"hygiene": 0.8}, {"pose": "idle"})])
	_use(tub, "Bathtub", [_act("bath", "Take Bath", "bath", 40, {"hygiene": 0.9, "fun": 0.1}, {"pose": "lie", "task": "Take Bath"})])
	_use(vanity, "Sink", [
		_act("brush", "Brush Teeth", "brush", 5, {"hygiene": 0.2}, {"pose": "brush_teeth", "task": "Brush Teeth"}),
		_act("wash", "Wash Hands", "wave", 3, {"hygiene": 0.1}, {"pose": "idle"}),
	], Vector3(7.85, y, 1.45))
	_use(toilet, "Toilet", [_act("use_toilet", "Use", "toilet", 5, {"bladder": 1.0}, {"pose": "sit"})])


func _build_kitchen() -> void:
	var R := "kitchen"
	var bz := -4.75
	var fridge := _put(R, "fridge", Vector3(0.0, 0, bz + 0.02), 0)
	_put(R, "counter", Vector3(0.85, 0, bz + 0.02), 0, 2)
	var sink := _put(R, "counter", Vector3(1.85, 0, bz + 0.02), 0, 1)
	var stove := _put(R, "stove", Vector3(2.85, 0, bz + 0.02), 0)
	_put(R, "counter", Vector3(3.85, 0, bz + 0.02), 0, 0)
	var bowl := _put(R, "dog_bowl", Vector3(0.3, 0, -0.8))
	_put(R, "plant", Vector3(4.9, 0, bz + 0.1), 0, 1)
	_lamp(Vector3(2.0, 2.3, -2.5), 0.9, 4.0, 0.2, Color(1.0, 0.72, 0.42), 0.0)
	# --- Front strip (seen under the upstairs slab in the cutaway).
	# Dining nook right of the stairs.
	PropLib.rug(_f(R), Vector3i(fc(5.7), 0, fc(1.2)), fc(2.8), fc(2.6), "red_kilim")
	var dtable := _put(R, "dining_table", Vector3(6.2, U, 1.75), 0)
	for k in 2:
		_put(R, "chair", Vector3(6.35 + k * 0.8, U, 1.2), 0, 0)
		_put(R, "chair", Vector3(6.35 + k * 0.8, U, 2.95), 2, 0)
	_put(R, "plant", Vector3(8.2, 0, 0.3), 0, 5)
	_put(R, "plant", Vector3(5.5, 0, 4.2), 0, 2)
	_put(R, "lamp_floor", Vector3(8.25, 0, 4.0))
	_lamp(Vector3(8.45, 1.75, 4.15), 1.0, 3.5, 0.3)
	_lamp(Vector3(7.0, 2.4, 2.2), 0.9, 3.6, 0.0, Color(1.0, 0.7, 0.4), 1.1)
	# Hallway wall left of the stairs: shelves, console with lamp, frames.
	var wx := -0.75
	_put(R, "bookshelf", Vector3(wx, 0, 0.35), 1, 2)
	_put(R, "plant", Vector3(wx + 0.05, 30 * U, 0.45), 0, 0)
	_put(R, "dresser", Vector3(wx + 0.02, 0, 1.75), 1, 1)
	_put(R, "lamp_table", Vector3(wx + 0.1, 14 * U, 1.85), 0, 0)
	_put(R, "plant", Vector3(wx + 0.1, 14 * U, 2.4), 0, 6)
	_lamp(Vector3(wx + 0.45, 1.25, 2.1), 1.0, 3.4, 0.3)
	_put(R, "frame", Vector3(wx, 1.45, 1.8), 1, 7)
	_put(R, "frame", Vector3(wx, 1.6, 2.55), 1, 3)
	_put(R, "sconce", Vector3(wx, 1.55, 3.6), 1, 0)
	_lamp(Vector3(wx + 0.4, 1.75, 3.7), 0.8, 3.0, 0.3)
	_put(R, "plant", Vector3(wx + 0.05, 0, 4.15), 0, 4)
	PropLib.rug(_f(R), Vector3i(fc(0.2), 0, fc(1.4)), fc(2.2), fc(2.6), "round_cream")
	_put(R, "armchair", Vector3(1.0, 0, 0.3), 0, 1)
	_put(R, "side_table", Vector3(2.15, 0, 0.5), 0, 0)
	_put(R, "plant", Vector3(2.3, 10 * U, 0.6), 0, 3)
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
		PropLib.place(_f("ext"), "fence", Vector3i(fx0, 0, fz), 0)
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
	_glass_day = _add_mesh(Mesher.build(gd, U, Vector3.ZERO, true, true), "GlassDay", false)
	_glass_night = _add_mesh(Mesher.build(gn, U, Vector3.ZERO, true, true), "GlassNight", false)
	_glass_day.visible = not _is_night
	_glass_night.visible = _is_night
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
		var spots := [Vector3(-26, 0, -24.5), Vector3(-14, 0, -24.0), Vector3(-2, 0, -24.5), Vector3(10, 0, -24.0), Vector3(22, 0, -24.5),
			Vector3(-26, 0, -5.0), Vector3(21, 0, -4.0)]
		var styles := [1, 4, 2, 1, 4, 2, 5]
		var hs: float = PropLib.scale_of("house")
		for i in spots.size():
			var c: Vector3 = spots[i] + Vector3(4.0, 0, 3.25)
			var rot := 0 if (i < 5 or i > 6) else (1 if i == 5 else 3)
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
	m.set_shader_parameter("aspect", SKY_W / SKY_H)
	q.material = m
	_moon.mesh = q
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_moon)
	_place_moon(ShotPresets.PRESETS["home_night"].camera)


const SKY_W := 150.0
const SKY_H := 46.0
const SKY_DIST := 48.0
const SKY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
uniform float aspect = 3.0;
uniform vec3 top_col = vec3(0.035, 0.05, 0.16);
uniform vec3 mid_col = vec3(0.09, 0.12, 0.3);
uniform vec3 low_col = vec3(0.16, 0.2, 0.38);
uniform vec2 moon_uv = vec2(0.6, 0.3);
uniform float moon_r = 0.075;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_col, mid_col, smoothstep(0.0, 0.6, uv.y));
	col = mix(col, low_col, smoothstep(0.55, 1.0, uv.y));
	vec2 g = uv * vec2(160.0 * aspect / 3.0, 60.0);
	vec2 cell = floor(g);
	float hs = h21(cell);
	vec2 f = fract(g) - 0.5;
	float star = step(0.955, hs) * (1.0 - smoothstep(0.08, 0.2, length(f))) * (1.0 - smoothstep(0.35, 0.7, uv.y));
	col += vec3(0.85, 0.88, 1.0) * star * (0.6 + 0.4 * h21(cell + 7.0));
	vec2 d = (uv - moon_uv) * vec2(aspect, 1.0);
	float r = length(d);
	float disc = 1.0 - smoothstep(moon_r - 0.004, moon_r, r);
	float crater = h21(floor((d + 1.0) * 60.0));
	vec3 moon = vec3(1.0, 0.96, 0.82) * (0.92 + 0.08 * crater);
	col += vec3(0.5, 0.55, 0.8) * 0.45 * exp(-max(r - moon_r, 0.0) * 9.0) * (1.0 - disc);
	col = mix(col, moon * 1.15, disc);
	ALBEDO = col;
}
"""


func _place_moon(cam: Dictionary) -> void:
	# Stand the card SKY_DIST m behind the orbit target, facing the camera heading.
	var yaw := deg_to_rad(cam.get("yaw", 30.0))
	var tgt: Vector3 = cam.get("target", Vector3.ZERO)
	var back := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_moon.position = Vector3(tgt.x, 0.0, tgt.z) + back * SKY_DIST + Vector3(0, SKY_H * 0.5 - 6.0, 0)
	_moon.rotation = Vector3(0.0, yaw, 0.0)
	_moon.visible = _is_night


func _place_moon_live(yaw_deg: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var back := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_moon.position = Vector3(tgt.x, 0.0, tgt.z) + back * SKY_DIST + Vector3(0, SKY_H * 0.5 - 6.0, 0)
	_moon.rotation.y = yaw


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
		_add_mesh(Mesher.build(vb, U), "Furniture_" + room, true)
	_sb.clear()
	_fb.clear()


# =================================================================== people

func _spawn_household() -> void:
	for look: String in ["dad", "bunny_girl", "cat_girl", "beagle"]:
		var a := SimActor.create(look)
		add_child(a)
		actors[look] = a
	for m in Game.household:
		if actors.has(m.get("look", "")):
			actors[m.name] = actors[m.look]


func _place(look: String, pos: Vector3, face_to: Vector3, pose: String, seat := -1.0) -> SimActor:
	var a: SimActor = actors[look]
	a.position = pos
	if seat > 0.0:
		a.seat_height = seat
	a.face(face_to)
	a.set_pose(pose)
	return a


func _stage(preset: String) -> void:
	if actors.is_empty():
		return
	var y := UF
	if preset == "home_night":
		var lily := _place("bunny_girl", Vector3(-0.73 + 17 * U - 0.3, y, -3.95 + 9 * U), Vector3(3.0, y, -3.95 + 9 * U), "lie")
		lily.lie_height = 0.53
		var jack := _place("dad", Vector3(0.75, y, -4.4), Vector3(0.4, y, -2.0), "sit_read", 0.44)
		var maya := _place("cat_girl", Vector3(7.85, y + 6 * U, 1.3), Vector3(7.85, y, 0.0), "brush_teeth")
		var dog := _place("beagle", Vector3(1.15, y + 0.12, 2.25), Vector3(2.5, y, 3.0), "sleep")
		Game.show_bubble(jack, {"text": "Read Story", "icon": "book_open", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(maya, {"text": "Brush Teeth", "icon": "brush", "kind": "action", "id": "action", "progress": -1})
		Game.show_bubble(dog, {"icon": "zzz", "kind": "emote", "id": "action"})
		lily.set_pose("lie")
		if _blanket == null:
			_blanket = PropLib.instance("blanket", 0)
			add_child(_blanket)
		_blanket.position = Vector3(-0.73 + 25 * U, y + 8 * U, -3.95 + 9 * U)
		_blanket.rotation_degrees.y = 90.0
		_blanket.visible = true
	else:
		if _blanket:
			_blanket.visible = false
		var jack := _place("dad", Vector3(-8.75 + 1.25, y, -2.0), Vector3(-9.5, y, -2.0), "type", 0.44)
		var lily := _place("bunny_girl", Vector3(-5.75, y, -2.75), Vector3(-4.6, y, -3.55), "sit_paint", 0.375)
		var maya := _place("cat_girl", Vector3(-2.85, y, -0.1), Vector3(-2.1, y, 0.9), "play")
		var dog := _place("beagle", Vector3(-5.6, y, 0.2), Vector3(-4.9, y, 0.95), "play")
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
	if _moon:
		_moon.visible = n
	if _halos:
		PropLib.set_halo_strength(_halos, 1.0 if n else 0.6)


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
	if _moon and _moon.visible:
		var rig := get_viewport().get_camera_3d()
		if rig and rig.get_parent() and "yaw" in rig.get_parent():
			var p: Node = rig.get_parent()
			_place_moon_live(p.yaw, p.target)
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
