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
## A* cost of walking through the clearance margin (dilated cells).
const MARGIN_COST := 4.0

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
## Connected region id of every open cell per level (-1 = not walkable).
var comps: Array[PackedInt32Array] = []
## Result of the last find_path(): did it really reach `to` (false = it only
## gets as close as the walkable region allows), and how far from `to` it ends.
var last_ok := true
var last_gap := 0.0


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
	for cv: Dictionary in cfg.get("carve", []):
		carve(int(cv.get("level", 0)), cv.rect)
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


## Force a rectangle (xz) walkable where it has floor: doorways that the
## set dressing crowds (a bath right behind the bathroom door) stay passable.
func carve(li: int, r: Rect2) -> void:
	if li < 0 or li >= level_y.size():
		return
	var x0 := maxi(0, int(floor((r.position.x - ox) / cs)))
	var x1 := mini(w - 1, int(floor((r.end.x - ox) / cs - 0.001)))
	var z0 := maxi(0, int(floor((r.position.y - oz) / cs)))
	var z1 := mini(h - 1, int(floor((r.end.y - oz) / cs - 0.001)))
	var f := floors[li]
	var rb := raw_block[li]
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := z * w + x
			if f[c] != INF:
				rb[c] = 0


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
	_label_regions(li)
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
	a.fill_weight_scale_region(a.region, 1.0)
	# The clearance margin is walkable but costly: paths keep away from walls
	# and furniture, yet a gap narrower than the margin (a kitchen between the
	# island and the counters) never cuts a room in two.
	for z in h:
		var row := z * w
		for x in w:
			var v := out[row + x]
			if v == 1 or v == 2:
				a.set_point_solid(Vector2i(x, z), true)
			elif v == 3:
				a.set_point_weight_scale(Vector2i(x, z), MARGIN_COST)


## Flood-fill the open cells of a level into connected regions (4-neighbour:
## A* only moves diagonally when both side cells are open, so this matches).
func _label_regions(li: int) -> void:
	var bl := block[li]
	var cm := PackedInt32Array()
	cm.resize(w * h)
	cm.fill(-1)
	var stack := PackedInt32Array()
	var next_id := 0
	for c0 in w * h:
		if not _walk_v(bl[c0]) or cm[c0] >= 0:
			continue
		cm[c0] = next_id
		stack.clear()
		stack.append(c0)
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := c % w
			if x > 0 and _walk_v(bl[c - 1]) and cm[c - 1] < 0:
				cm[c - 1] = next_id
				stack.append(c - 1)
			if x < w - 1 and _walk_v(bl[c + 1]) and cm[c + 1] < 0:
				cm[c + 1] = next_id
				stack.append(c + 1)
			if c >= w and _walk_v(bl[c - w]) and cm[c - w] < 0:
				cm[c - w] = next_id
				stack.append(c - w)
			if c < w * (h - 1) and _walk_v(bl[c + w]) and cm[c + w] < 0:
				cm[c + w] = next_id
				stack.append(c + w)
		next_id += 1
	if li < comps.size():
		comps[li] = cm
	else:
		comps.append(cm)


static func _walk_v(v: int) -> bool:
	return v == 0 or v == 3


## Walkable at all (open or in the clearance margin).
func is_walkable(li: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return false
	return _walk_v(block[li][c.y * w + c.x])


func region_of(li: int, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or li >= comps.size():
		return -1
	return comps[li][c.y * w + c.x]


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


## Nearest open cell to c on level li (ring search), or (-1,-1). With
## region >= 0 only cells of that connected region count.
func nearest_open(li: int, c: Vector2i, max_r := 24, region := -1) -> Vector2i:
	if is_open(li, c) and (region < 0 or region_of(li, c) == region):
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
## segments between levels). Always returns at least one point so callers can
## fall back to walking straight. `exact` appends `to` itself after the last
## open cell (the final approach onto a seat / into a use spot) -- but only when
## `to` is really reached: when the walkable region of `from` does not connect
## to `to`, the path stops at the closest reachable cell and last_ok is false.
func find_path(from: Vector3, to: Vector3, exact := true) -> PackedVector3Array:
	var out := PackedVector3Array()
	var la := level_of(from)
	var lb := level_of(to)
	last_ok = true
	var ok := true
	var links_ok := true
	if la == lb:
		out = _level_path(la, from, to)
		ok = _seg_ok
	else:
		# Try every stair link that joins the two levels; keep the shortest
		# one that actually connects (both halves reachable).
		var best := PackedVector3Array()
		var best_len := INF
		var best_ok := false
		for l in links:
			for dirn in [0, 1]:
				var s: int = l.la if dirn == 0 else l.lb
				var e: int = l.lb if dirn == 0 else l.la
				if s != la or e != lb:
					continue
				var pa: Vector3 = l.a if dirn == 0 else l.b
				var pb: Vector3 = l.b if dirn == 0 else l.a
				var v: Array = (l.via as Array).duplicate()
				if dirn == 1:
					v.reverse()
				# Each leg must really reach its stair end (not stop behind
				# furniture next to it) for the link to count.
				var p1 := _level_path(la, from, pa)
				var ok1 := _seg_ok and _seg_end_gap < 1.0
				var p2 := _level_path(lb, pb, to)
				var ok2 := _seg_ok and _seg_start_gap < 1.0
				var cand := PackedVector3Array()
				cand.append_array(p1)
				cand.append(pa)
				for vp: Vector3 in v:
					cand.append(vp)
				cand.append(pb)
				cand.append_array(p2)
				var ln := path_length(from, cand)
				var good := ok1 and ok2
				if (good and not best_ok) or (good == best_ok and ln < best_len):
					best = cand
					best_len = ln
					best_ok = good
		if best.is_empty():
			out = _level_path(la, from, Vector3(to.x, from.y, to.z))
			ok = false
		else:
			out = best
			ok = best_ok
		links_ok = ok
	last_ok = ok
	var end_p: Vector3 = out[out.size() - 1] if not out.is_empty() else from
	last_gap = Vector2(end_p.x - to.x, end_p.z - to.z).length() if level_of(end_p) == lb or out.is_empty() else INF
	if exact:
		# The last open cell is next to `to` (use spots sit on chairs, in front
		# of counters): finish the approach. Never walk a long straight line
		# through walls to a place the grid could not reach.
		if links_ok and ((ok and last_gap < 1.0) or last_gap < 0.5):
			if out.is_empty() or out[out.size() - 1].distance_to(to) > 0.04:
				out.append(to)
			last_ok = true
			last_gap = 0.0
		else:
			# Reachable region ends too far from `to` (behind a wall of
			# furniture): the caller must treat it as a route failure.
			last_ok = false
	if out.is_empty():
		out.append(to if ok else from)
	return out


## Region a walker coming from `from` arrives in on level li (its own region
## on the same storey, else the region at the foot / head of the stairs).
func entry_region(from: Vector3, li: int) -> int:
	var la := level_of(from)
	if la == li:
		return region_of(la, approach_cell(la, cell_of(from), -1, 40))
	for l in links:
		if l.la == la and l.lb == li:
			return region_of(li, approach_cell(li, cell_of(l.b), -1, 40))
		if l.lb == la and l.la == li:
			return region_of(li, approach_cell(li, cell_of(l.a), -1, 40))
	return -1


## Where to stand to use something whose spot is inside furniture (a fridge,
## a counter): the walkable cell, reachable from `from`, that approaches
## `target` most directly. Vector3.INF when nothing reachable is near.
func stand_spot(from: Vector3, target: Vector3, max_cost := 32) -> Vector3:
	if not in_bounds(target):
		return Vector3.INF
	var li := level_of(target)
	var tc := cell_of(target)
	var reg := entry_region(from, li)
	var c := approach_cell(li, tc, reg, max_cost)
	if c.x < 0:
		return Vector3.INF
	if c == tc:
		return Vector3(target.x, floor_y(target, li), target.z)
	var p := center_of(li, c)
	# Step a little toward the object (stay inside the cell).
	var d := Vector3(target.x - p.x, 0, target.z - p.z)
	if d.length() > 0.01:
		p += d.normalized() * minf(d.length(), cs * 0.35)
	return p


## Walking length of a path that starts at `from`.
static func path_length(from: Vector3, p: PackedVector3Array) -> float:
	var d := 0.0
	var prev := from
	for q in p:
		d += prev.distance_to(q)
		prev = q
	return d


var _seg_ok := true
var _seg_start_gap := 0.0   # last _level_path: start cell centre -> from (m, flat)
var _seg_end_gap := 0.0     # goal cell centre -> to

func _level_path(li: int, from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	_seg_ok = false
	if not in_bounds(from) or not in_bounds(to):
		return out
	var fc := cell_of(from)
	var tc := cell_of(to)
	# Start: the walkable cell the sim steps into (off a chair, out of a bed).
	# Goal: the cell of that same region from which `to` is approached most
	# cheaply (crossing at most a little furniture, never a cut wall).
	var a := approach_cell(li, fc, -1, 40)
	if a.x < 0:
		return out
	var b := approach_cell(li, tc, region_of(li, a), 48)
	if b.x >= 0:
		_seg_ok = true
	else:
		# The sim may stand in a pocket (between a bed and the wall): try the
		# region of the goal's own approach cell from where the sim stands.
		var b0 := approach_cell(li, tc, -1, 48)
		var a2 := approach_cell(li, fc, region_of(li, b0), 40) if b0.x >= 0 else Vector2i(-1, -1)
		if a2.x >= 0:
			a = a2
			b = b0
			_seg_ok = true
		else:
			# Not connected: get as close to `to` as the start region allows.
			b = _closest_in_region(li, region_of(li, a), to)
			if b.x < 0:
				return out
	var ca := center_of(li, a)
	var cb := center_of(li, b)
	_seg_start_gap = Vector2(ca.x - from.x, ca.z - from.z).length()
	_seg_end_gap = Vector2(cb.x - to.x, cb.z - to.z).length()
	var ids: Array[Vector2i] = astars[li].get_id_path(a, b, true)
	if ids.is_empty():
		_seg_ok = false
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
	# Start cell too when the sim isn't standing in it (stepping out of a
	# chair or off the stair foot must go through the open cell, not a wall).
	if fc != a and center_of(li, a).distance_to(from) > cs * 0.75 and not _los(li, a, fc):
		out.append(center_of(li, a))
	for k in range(1, keep.size()):
		out.append(center_of(li, keep[k]))
	if out.is_empty():
		out.append(center_of(li, b))
	return out


## The open cell a sim reaches c from: a cheapest-first search out of c that
## may cross furniture (cost 4 per cell) and the dilated margin (cost 1) but
## never a floorless cell (the cut walls / holes). So the final approach to a
## fridge against the back wall comes from the kitchen, not from the garden
## behind the wall, even when the garden cell is a little closer.
## With region >= 0 only open cells of that region count. (-1,-1) if none.
func approach_cell(li: int, c: Vector2i, region := -1, max_cost := 64) -> Vector2i:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return Vector2i(-1, -1)
	var bl := block[li]
	var cm := comps[li]
	var c0 := c.y * w + c.x
	if _walk_v(bl[c0]) and (region < 0 or cm[c0] == region):
		return c
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(max_cost + 5)
	for k in buckets.size():
		buckets[k] = PackedInt32Array()
	var best := {c0: 0}
	buckets[0].append(c0)
	for cost in max_cost + 1:
		var bk: PackedInt32Array = buckets[cost]
		var i := 0
		while i < bk.size():
			var cur: int = bk[i]
			i += 1
			if int(best.get(cur, 1 << 30)) < cost:
				continue
			if _walk_v(bl[cur]) and (region < 0 or cm[cur] == region):
				return Vector2i(cur % w, cur / w)
			var x := cur % w
			for n in [cur - 1 if x > 0 else -1, cur + 1 if x < w - 1 else -1, cur - w, cur + w]:
				if n < 0 or n >= w * h or bl[n] == 2:
					continue
				var step := 1 if _walk_v(bl[n]) else 4
				var nc := cost + step
				if nc > max_cost or int(best.get(n, 1 << 30)) <= nc:
					continue
				best[n] = nc
				buckets[nc].append(n)
			bk = buckets[cost]
	return Vector2i(-1, -1)


## Open cell of region `reg` closest (straight line) to world point p.
func _closest_in_region(li: int, reg: int, p: Vector3) -> Vector2i:
	if reg < 0:
		return Vector2i(-1, -1)
	var cm := comps[li]
	var pc := cell_of(p)
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in w * h:
		if cm[c] != reg:
			continue
		var dx := c % w - pc.x
		var dz := c / w - pc.y
		var d := float(dx * dx + dz * dz)
		if d < bd:
			bd = d
			best = Vector2i(c % w, c / w)
	return best


## Grid line of sight (supercover walk): every cell walkable (open or the
## clearance margin) so string-pulled paths stay smooth near furniture.
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
			if not _walk_v(bl[z * w + x + sx]) or not _walk_v(bl[(z + sz) * w + x]):
				return false
			x += sx
			z += sz
			err += dx - dz
		if x < 0 or z < 0 or x >= w or z >= h or not _walk_v(bl[z * w + x]):
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
