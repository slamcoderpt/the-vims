class_name NavGrid
extends RefCounted
## Walkable grid for one location, derived from the location's own voxel
## meshes (no hand-authored nav data needed):
##   * floor  = lowest upward-facing surface near a level height in each cell
##   * blocked = any geometry between floor + STEP and floor + HEAD
##   * seat   = lowest top surface 0.25..0.85 m above the floor (chairs, beds)
## Each level (storey) gets its own AStarGrid2D; levels are joined by links
## (stairs) that a sim walks along in a straight line.
## Bought furniture is added as dynamic obstacles (add_obstacle / remove_obstacle).

const CELL := 0.25
const STEP := 0.16        # anything lower than this above the floor is walkable
const HEAD := 1.55        # clearance needed above the floor
const SEAT_MIN := 0.25
const SEAT_MAX := 0.85

static var _cache := {}   # key -> NavGrid (static geometry never changes per location)

var key := ""
var cs := CELL
var ox := 0.0
var oz := 0.0
var w := 0
var h := 0
var level_y: Array[float] = []
var floor_tol := 0.25
var floors: Array[PackedFloat32Array] = []
var seats: Array[PackedFloat32Array] = []
var raw_block: Array[PackedByteArray] = []   # geometry only
var block: Array[PackedByteArray] = []       # dilated + dynamic (what A* sees)
var dyn: Array[PackedInt32Array] = []
var astars: Array[AStarGrid2D] = []
## links: {a: Vector3, b: Vector3, la: int, lb: int}
var links: Array[Dictionary] = []
var obstacles := {}   # id -> {level, cells: PackedInt32Array}
var build_ms := 0


# =================================================================== build

## cfg: {key, levels: [y...], bounds: Rect2 (xz), floor_tol, links: [{a, b}]}
static func for_location(root: Node3D, cfg: Dictionary) -> NavGrid:
	var k: String = cfg.get("key", "")
	if k != "" and _cache.has(k):
		var g: NavGrid = _cache[k]
		g.clear_obstacles()
		return g
	var g := NavGrid.new()
	g.build(root, cfg)
	if k != "":
		_cache[k] = g
	return g


static func clear_cache() -> void:
	_cache.clear()


func build(root: Node3D, cfg: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	key = cfg.get("key", "")
	var lv: Array = cfg.get("levels", [0.0])
	for y in lv:
		level_y.append(float(y))
	floor_tol = cfg.get("floor_tol", 0.25)
	var b: Rect2 = cfg.get("bounds", Rect2(-16, -16, 32, 32))
	ox = b.position.x
	oz = b.position.y
	w = int(ceil(b.size.x / cs))
	h = int(ceil(b.size.y / cs))
	for i in level_y.size():
		var f := PackedFloat32Array()
		f.resize(w * h)
		f.fill(INF)
		floors.append(f)
		var s := PackedFloat32Array()
		s.resize(w * h)
		s.fill(INF)
		seats.append(s)
		var rb := PackedByteArray()
		rb.resize(w * h)
		raw_block.append(rb)
		var d := PackedInt32Array()
		d.resize(w * h)
		dyn.append(d)
	var tris := _collect(root)
	_rasterize(tris)
	for i in level_y.size():
		block.append(PackedByteArray())
		_rebuild_level(i)
	for l: Dictionary in cfg.get("links", []):
		add_link(l.a, l.b, l.get("via", []))
	build_ms = Time.get_ticks_msec() - t0


## Collect triangle boxes: [minx, maxx, miny, maxy, minz, maxz, kind] where
## kind 0 = vertical side, 1 = up-facing top, 2 = down-facing bottom.
func _collect(root: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var lo: float = level_y.min() - 0.4
	var hi: float = level_y.max() + HEAD + 0.5
	var bx0 := ox
	var bx1 := ox + w * cs
	var bz0 := oz
	var bz1 := oz + h * cs
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin != null or _under_actor(mi, root):
			continue
		if mi.has_meta("nav_ignore"):
			continue
		var xf := mi.global_transform
		var ab := xf * mi.get_aabb()
		if ab.position.y > hi or ab.end.y < lo:
			continue
		if ab.position.x > bx1 or ab.end.x < bx0 or ab.position.z > bz1 or ab.end.z < bz0:
			continue
		var yaw_only := absf(xf.basis.y.y - 1.0) < 0.001
		for si in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var nrm = arr[Mesh.ARRAY_NORMAL]
			var has_n: bool = nrm is PackedVector3Array and (nrm as PackedVector3Array).size() == verts.size() and yaw_only
			var idx = arr[Mesh.ARRAY_INDEX]
			var indexed: bool = idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0
			var n_tri: int = ((idx as PackedInt32Array).size() if indexed else verts.size()) / 3
			for t in n_tri:
				var i0: int
				var i1: int
				var i2: int
				if indexed:
					i0 = idx[t * 3]
					i1 = idx[t * 3 + 1]
					i2 = idx[t * 3 + 2]
				else:
					i0 = t * 3
					i1 = i0 + 1
					i2 = i0 + 2
				var a := verts[i0]
				var bb := verts[i1]
				var c := verts[i2]
				var miny := minf(a.y, minf(bb.y, c.y))
				var maxy := maxf(a.y, maxf(bb.y, c.y))
				if miny > hi or maxy < lo:
					continue
				var minx := minf(a.x, minf(bb.x, c.x))
				var maxx := maxf(a.x, maxf(bb.x, c.x))
				var minz := minf(a.z, minf(bb.z, c.z))
				var maxz := maxf(a.z, maxf(bb.z, c.z))
				if minx > bx1 or maxx < bx0 or minz > bz1 or maxz < bz0:
					continue
				var n: Vector3
				if has_n:
					n = nrm[i0]
				else:
					n = (bb - a).cross(c - a)
					var ln := n.length()
					if ln < 1e-9:
						continue
					n /= ln
					if n.y < 0.0 and absf(n.y) > 0.7:
						n = -n   # unknown winding: treat flat faces as tops
				var kind := 0
				if n.y > 0.7:
					kind = 1
				elif n.y < -0.7:
					kind = 2
				else:
					# Vertical face: nudge into the solid so it lands in the right cell.
					minx -= n.x * 0.01
					maxx -= n.x * 0.01
					minz -= n.z * 0.01
					maxz -= n.z * 0.01
				out.append(minx); out.append(maxx); out.append(miny); out.append(maxy)
				out.append(minz); out.append(maxz); out.append(kind)
	return out


static func _under_actor(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p and p != root:
		if p is SimActor or p is Skeleton3D:
			return true
		p = p.get_parent()
	return false


func _rasterize(tris: PackedFloat32Array) -> void:
	var nt := tris.size() / 7
	var nl := level_y.size()
	var inv := 1.0 / cs
	# Pass 1: floors.
	for t in nt:
		var o := t * 7
		if tris[o + 6] != 1.0:
			continue
		var y := tris[o + 2]
		for li in nl:
			var L: float = level_y[li]
			if y < L - 0.3 or y > L + floor_tol:
				continue
			var x0 := maxi(0, int(floor((tris[o] - ox) * inv)))
			var x1 := mini(w - 1, int(floor((tris[o + 1] - ox) * inv - 0.0001)))
			var z0 := maxi(0, int(floor((tris[o + 4] - oz) * inv)))
			var z1 := mini(h - 1, int(floor((tris[o + 5] - oz) * inv - 0.0001)))
			var f := floors[li]
			for z in range(z0, z1 + 1):
				var row := z * w
				for x in range(x0, x1 + 1):
					if y < f[row + x]:
						f[row + x] = y
	# Pass 2: obstacles + seats.
	for t in nt:
		var o := t * 7
		var kind := tris[o + 6]
		var miny := tris[o + 2]
		var maxy := tris[o + 3]
		var x0 := maxi(0, int(floor((tris[o] - ox) * inv)))
		var x1 := mini(w - 1, int(floor((tris[o + 1] - ox) * inv - 0.0001)))
		var z0 := maxi(0, int(floor((tris[o + 4] - oz) * inv)))
		var z1 := mini(h - 1, int(floor((tris[o + 5] - oz) * inv - 0.0001)))
		if x1 < x0:
			x1 = x0
		if z1 < z0:
			z1 = z0
		if x0 >= w or z0 >= h or x1 < 0 or z1 < 0:
			continue
		for li in nl:
			var L: float = level_y[li]
			if maxy < L - 0.3 + STEP or miny > L + floor_tol + HEAD:
				continue
			var f := floors[li]
			var rb := raw_block[li]
			var st := seats[li]
			for z in range(z0, z1 + 1):
				var row := z * w
				for x in range(x0, x1 + 1):
					var c := row + x
					var fy := f[c]
					if fy == INF:
						continue
					if maxy > fy + STEP and miny < fy + HEAD:
						if kind == 1.0 and miny <= fy + STEP:
							continue
						rb[c] = 1
						if kind == 1.0 and miny >= fy + SEAT_MIN and miny <= fy + SEAT_MAX and miny < st[c]:
							st[c] = miny


## Recompute the A* view of one level: no-floor + geometry (dilated) + dynamic.
func _rebuild_level(li: int) -> void:
	var f := floors[li]
	var rb := raw_block[li]
	var d := dyn[li]
	var bl := PackedByteArray()
	bl.resize(w * h)
	for z in h:
		var row := z * w
		for x in w:
			var c := row + x
			if f[c] == INF:
				bl[c] = 2
			elif rb[c] != 0 or d[c] > 0:
				bl[c] = 1
	# Dilate solid geometry by one cell so sims don't brush walls; keep floor
	# holes undilated (thin bridges between rooms stay walkable).
	var out := bl.duplicate()
	for z in range(1, h - 1):
		var row := z * w
		for x in range(1, w - 1):
			var c := row + x
			if bl[c] != 0:
				continue
			if bl[c - 1] == 1 or bl[c + 1] == 1 or bl[c - w] == 1 or bl[c + w] == 1:
				out[c] = 3
	block[li] = out
	var a: AStarGrid2D
	if li < astars.size():
		a = astars[li]
	else:
		a = AStarGrid2D.new()
		a.region = Rect2i(0, 0, w, h)
		a.cell_size = Vector2(1, 1)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
		astars.append(a)
	a.fill_solid_region(a.region, false)
	for z in h:
		var row := z * w
		for x in w:
			if out[row + x] != 0:
				a.set_point_solid(Vector2i(x, z), true)


# =================================================================== queries

func level_of(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in level_y.size():
		var d: float = absf(p.y - level_y[i])
		# Prefer the level we're standing on or just above.
		if p.y + 0.6 < level_y[i]:
			d += 10.0
		if d < bd:
			bd = d
			best = i
	return best


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - ox) / cs)), 0, w - 1), clampi(int(floor((p.z - oz) / cs)), 0, h - 1))


func in_bounds(p: Vector3) -> bool:
	return p.x >= ox and p.z >= oz and p.x < ox + w * cs and p.z < oz + h * cs


func center_of(li: int, c: Vector2i) -> Vector3:
	var fy: float = floors[li][c.y * w + c.x]
	if fy == INF:
		fy = level_y[li]
	return Vector3(ox + (c.x + 0.5) * cs, fy, oz + (c.y + 0.5) * cs)


func is_open(li: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return false
	return block[li][c.y * w + c.x] == 0


func has_floor(li: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return false
	return floors[li][c.y * w + c.x] != INF


## Floor height under p on its level (falls back to the level height).
func floor_y(p: Vector3, li := -1) -> float:
	if li < 0:
		li = level_of(p)
	if not in_bounds(p):
		return level_y[li]
	var c := cell_of(p)
	var fy: float = floors[li][c.y * w + c.x]
	return level_y[li] if fy == INF else fy


## Seat / mattress top above the floor at p, or -1 when there is none.
func seat_height(p: Vector3) -> float:
	var li := level_of(p)
	if not in_bounds(p):
		return -1.0
	var best := -1.0
	var c0 := cell_of(p)
	# Look at the cell and its 4 neighbours (use spots sit on cell borders).
	for dc: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := c0 + dc
		if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
			continue
		var s: float = seats[li][c.y * w + c.x]
		var fy: float = floors[li][c.y * w + c.x]
		if s == INF or fy == INF:
			continue
		if dc == Vector2i.ZERO:
			return s - fy
		if best < 0.0:
			best = s - fy
	return best


## Nearest open cell to c on level li (ring search), or (-1,-1).
func nearest_open(li: int, c: Vector2i, max_r := 24) -> Vector2i:
	if is_open(li, c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if is_open(li, q):
					var d := float(dx * dx + dz * dz)
					if d < bd:
						bd = d
						best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Count of open cells within r cells of c (used to face the open side of beds/sofas).
func openness(li: int, p: Vector3, dir: Vector3, dist := 1.0) -> int:
	var n := 0
	var steps := int(dist / cs)
	for k in range(1, steps + 1):
		var q := p + dir * (k * cs)
		if in_bounds(q) and is_open(li, cell_of(q)):
			n += 1
	return n


## A walkable connection between levels; `via` are intermediate points (a -> b order).
func add_link(a: Vector3, b: Vector3, via: Array = []) -> void:
	links.append({"a": a, "b": b, "la": level_of(a), "lb": level_of(b), "via": via})


## Path from -> to as world waypoints (y follows the floor; stairs are straight
## segments between levels). Always returns at least [to] so callers can fall
## back to walking straight. `exact` appends `to` itself after the last open cell.
func find_path(from: Vector3, to: Vector3, exact := true) -> PackedVector3Array:
	var out := PackedVector3Array()
	var la := level_of(from)
	var lb := level_of(to)
	if la == lb:
		out = _level_path(la, from, to)
	else:
		var best: Dictionary = {}
		var bd := INF
		for l in links:
			for dirn in [0, 1]:
				var s: int = l.la if dirn == 0 else l.lb
				var e: int = l.lb if dirn == 0 else l.la
				if s != la or e != lb:
					continue
				var pa: Vector3 = l.a if dirn == 0 else l.b
				var pb: Vector3 = l.b if dirn == 0 else l.a
				var d := Vector2(from.x - pa.x, from.z - pa.z).length() + Vector2(to.x - pb.x, to.z - pb.z).length()
				if d < bd:
					bd = d
					var v: Array = (l.via as Array).duplicate()
					if dirn == 1:
						v.reverse()
					best = {"pa": pa, "pb": pb, "via": v}
		if best.is_empty():
			out = _level_path(la, from, Vector3(to.x, from.y, to.z))
		else:
			out = _level_path(la, from, best.pa)
			out.append(best.pa)
			for vp: Vector3 in best.via:
				out.append(vp)
			out.append(best.pb)
			out.append_array(_level_path(lb, best.pb, to))
	if exact:
		if out.is_empty() or out[out.size() - 1].distance_to(to) > 0.04:
			out.append(to)
	elif out.is_empty():
		out.append(to)
	return out


func _level_path(li: int, from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not in_bounds(from) or not in_bounds(to):
		return out
	var a := nearest_open(li, cell_of(from), 8)
	var b := nearest_open(li, cell_of(to), 24)
	if a.x < 0 or b.x < 0:
		return out
	var ids: Array[Vector2i] = astars[li].get_id_path(a, b, true)
	if ids.is_empty():
		return out
	# String-pull: keep only the cells where line of sight breaks.
	var keep: Array[Vector2i] = [ids[0]]
	var i := 0
	while i < ids.size() - 1:
		var j := ids.size() - 1
		while j > i + 1 and not _los(li, ids[i], ids[j]):
			j -= 1
		keep.append(ids[j])
		i = j
	for k in range(1, keep.size()):
		out.append(center_of(li, keep[k]))
	if out.is_empty():
		out.append(center_of(li, b))
	return out


## Grid line of sight (supercover walk, all cells must be open).
func _los(li: int, a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(b.x - a.x)
	var dz := absi(b.y - a.y)
	var sx := 1 if b.x > a.x else -1
	var sz := 1 if b.y > a.y else -1
	var x := a.x
	var z := a.y
	var n := dx + dz
	var err := dx - dz
	dx *= 2
	dz *= 2
	var bl := block[li]
	for _k in n:
		if err > 0:
			x += sx
			err -= dz
		elif err < 0:
			z += sz
			err += dx
		else:
			# Exactly through a corner: both neighbours must be open.
			if x + sx < 0 or x + sx >= w or z + sz < 0 or z + sz >= h:
				return false
			if bl[z * w + x + sx] != 0 or bl[(z + sz) * w + x] != 0:
				return false
			x += sx
			z += sz
			err += dx - dz
		if x < 0 or z < 0 or x >= w or z >= h or bl[z * w + x] != 0:
			return false
	return true


# =================================================================== dynamic obstacles

## Footprint box (world AABB) of a bought object. Returns false if any cell is taken.
func can_place(box: AABB, ignore_id := -1) -> bool:
	var li := level_of(box.position + Vector3(0, 0.05, 0))
	var cells := _cells_in(li, box)
	if cells.is_empty():
		return false
	var mine: PackedInt32Array = obstacles[ignore_id].cells if obstacles.has(ignore_id) else PackedInt32Array()
	var f := floors[li]
	var rb := raw_block[li]
	var d := dyn[li]
	for c in cells:
		if f[c] == INF or absf(f[c] - box.position.y) > 0.3:
			return false
		if rb[c] != 0:
			return false
		if d[c] > 0 and not mine.has(c):
			return false
	return true


func add_obstacle(id: int, box: AABB) -> void:
	remove_obstacle(id)
	var li := level_of(box.position + Vector3(0, 0.05, 0))
	var cells := _cells_in(li, box)
	var d := dyn[li]
	for c in cells:
		d[c] += 1
	obstacles[id] = {"level": li, "cells": cells}
	_rebuild_level(li)


func remove_obstacle(id: int) -> void:
	if not obstacles.has(id):
		return
	var o: Dictionary = obstacles[id]
	var d := dyn[o.level]
	for c in o.cells:
		d[c] = maxi(0, d[c] - 1)
	obstacles.erase(id)
	_rebuild_level(o.level)


func clear_obstacles() -> void:
	var lv := {}
	for id in obstacles:
		lv[obstacles[id].level] = true
	for li in dyn.size():
		dyn[li].fill(0)
	obstacles.clear()
	for li in lv:
		_rebuild_level(li)


func _cells_in(_li: int, box: AABB) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := int(floor((box.position.x - ox) / cs + 0.001))
	var x1 := int(floor((box.end.x - ox) / cs - 0.001))
	var z0 := int(floor((box.position.z - oz) / cs + 0.001))
	var z1 := int(floor((box.end.z - oz) / cs - 0.001))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if x < 0 or z < 0 or x >= w or z >= h:
				return PackedInt32Array()
			out.append(z * w + x)
	return out


# =================================================================== debug

## Top-down image of a level: dark = no floor, red = blocked, orange = dilated,
## blue = dynamic, green = walkable, yellow = seat.
func debug_image(li: int, scale := 3) -> Image:
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGB8)
	for z in h:
		for x in w:
			var c := z * w + x
			var col := Color(0.25, 0.75, 0.35)
			match block[li][c]:
				2: col = Color(0.08, 0.08, 0.1)
				1: col = Color(0.85, 0.2, 0.2) if dyn[li][c] == 0 else Color(0.2, 0.4, 0.95)
				3: col = Color(0.9, 0.55, 0.2)
			if seats[li][c] != INF and block[li][c] != 2:
				col = col.lerp(Color(1, 1, 0.2), 0.5)
			img.fill_rect(Rect2i(x * scale, z * scale, scale, scale), col)
	return img
