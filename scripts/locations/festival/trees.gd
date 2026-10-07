extends RefCounted
## Autumn trees (ref2): big rounded, layered canopies built from a few large
## clustered lobes. Each lobe has ONE leaf colour (orange / red / yellow) and
## is shaded in 3 flat tones (sunlit top-left, mid, shadowed underside) like
## the reference's chunky painted voxel crowns - no per-voxel random colours
## (r14 critic: "speckled confetti"). Flat tones also let the mesher merge
## long face runs, so the crowns are cheap.
##
## Two layers for the standard high game camera:
##  * near trees (real scale) framing the top-left of the square and the
##    left edge;
##  * far trees (forced perspective, matching the scaled-down town hall
##    backdrop): trunks stand below the plaza level so only the round crowns
##    show either side of the clock tower; they get a light distance haze.
## Each layer is one merged mesh. Downward faces are skipped (the camera is
## always above them).

const K := preload("res://scripts/locations/festival/kit.gd")

## [x, z (world, not depth-compressed), base_y, trunk_h, crown_r, palette, layer]
## palette: 0 orange, 1 red, 2 yellow, 3 mixed orange/red
const TREES := [
	# --- near (layer 0): top-left corner behind the FALL TREATS stall.
	[-8.7, -7.4, 0.0, 1.9, 2.5, 0, 0],
	[-10.8, -2.4, 0.0, 2.0, 2.3, 1, 0],
	[-7.2, -11.6, 0.0, 1.6, 1.9, 3, 0],
	[-12.0, -9.6, 0.0, 1.4, 2.2, 3, 0],
	# --- far (layer 1, forced perspective): crowns behind / beside the
	# scaled town hall so foliage, not empty plaza, fills the top band.
	[-5.2, -12.6, 0.2, 1.0, 1.5, 1, 1],
	[-3.2, -13.8, 0.6, 1.0, 1.15, 2, 1],
	[-4.0, -12.7, -0.1, 0.8, 1.1, 0, 1],
	[-0.8, -13.3, 0.45, 1.0, 1.25, 0, 1],
	[-7.4, -13.4, 0.45, 1.0, 1.25, 3, 1],
]
const VS := [0.14, 0.12]
const NAMES := ["TreesNear", "TreesFar"]
const HAZE := Color(0.95, 0.85, 0.72)

## Leaf tones per colour family: [highlight, mid, shadow].
const TONES := {
	"orange": [Color("f0902c"), Color("dc6a1a"), Color("a64418")],
	"red": [Color("e05c2c"), Color("c0351c"), Color("84211a")],
	"yellow": [Color("f5c24c"), Color("e99c28"), Color("c06e1c")],
}
## Light comes from the front-left, high (golden hour, matches the sun).
const LDIR := Vector3(-0.45, 0.78, 0.43)


static func spots() -> Array:
	var out := []
	for t: Array in TREES:
		if t[6] == 0:
			out.append(Vector2(t[0], t[1]))
	return out


func build(parent: Node3D) -> void:
	var groups := [VoxelBuilder.new(), VoxelBuilder.new()]
	var occs := [{}, {}]
	for g: VoxelBuilder in groups:
		g.jitter = 0.0
	var i := 0
	for t: Array in TREES:
		var li: int = t[6]
		_tree(groups[li], occs[li], VS[li], t[0], t[1], t[2], t[3], t[4], t[5], i * 17 + 3, li == 1)
		i += 1
	for li in 2:
		var mi := MeshInstance3D.new()
		mi.name = NAMES[li]
		mi.mesh = K.mesh(groups[li], VS[li], Vector3.ZERO, 100000, occs[li])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if li == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## Colour family sequence for the lobes of one tree (dominant first).
func _families(p: int) -> Array:
	match p:
		0: return ["orange", "orange", "yellow", "orange", "red"]
		1: return ["red", "red", "orange", "red", "orange"]
		2: return ["yellow", "yellow", "orange", "yellow", "orange"]
	return ["orange", "red", "orange", "yellow", "red"]


## Shader for one lobe: 3 flat tones by the lobe's surface normal vs the sun,
## plus a darker band on the crown underside and rare clustered leaf flecks.
func _lobe_shader(center: Vector3, rad: Vector3, fam: String, crown_lo: float, crown_hi: float, seed: int, haze: float) -> Callable:
	var tones: Array = TONES[fam]
	var ld := LDIR.normalized()
	return func(q: Vector3i) -> Color:
		var rel := (Vector3(q) + Vector3(0.5, 0.5, 0.5) - center) / rad
		var nrm := rel.normalized() if rel.length() > 0.01 else Vector3.UP
		var d := nrm.dot(ld)
		# Clustered break-up: 2-cell patches occasionally shift one tone.
		var cell := Vector3i(floori(q.x / 3.0), floori(q.y / 3.0), floori(q.z / 3.0))
		var ph := VoxelBuilder.hash3(cell + Vector3i(seed, 3, -seed))
		d += (ph - 0.5) * 0.24
		var ti := 0 if d > 0.62 else (1 if d > 0.02 else 2)
		var ky := clampf((q.y - crown_lo) / maxf(crown_hi - crown_lo, 1.0), 0.0, 1.0)
		if ky < 0.22 and ti < 2:
			ti += 1
		var c: Color = tones[ti]
		if haze > 0.0:
			c = c.lerp(HAZE, haze)
		return c


func _tree(vb: VoxelBuilder, occ: Dictionary, vs: float, x: float, z: float, y0: float, th_m: float, r: float, pal: int, seed: int, far: bool) -> void:
	var cx := int(round(x / vs))
	var cz := int(round(z / vs))
	var by := int(round(y0 / vs))
	var th := int(th_m / vs)
	var rc := r / vs
	var bark := [Color("5e3b22"), Color("4f311c"), Color("6b452a"), Color("573620")]
	var haze := 0.24 if far else 0.07
	# Trunk 2x2 (3x3 at the base) with bark streaks.
	for y in range(by, by + th):
		var w := 3 if y < by + 2 else 2
		for dx in w:
			for dz in w:
				var c: Color = bark[(dx + y / 3) % 2]
				vb.set_v(Vector3i(cx - w / 2 + dx, y, cz - w / 2 + dz), c)
	if y0 >= 0.0:
		for o in [Vector3i(-2, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, -2), Vector3i(0, 0, 2)]:
			vb.set_v(Vector3i(cx, by, cz) + o, bark[1])
	var top := Vector3(cx + 0.5, by + th, cz + 0.5)
	var crown := top + Vector3(0, rc * 0.6, 0)
	# Two branches forking into the crown (visible through the lobe gaps).
	for b in 3:
		var ang := TAU * b / 3.0 + K.hs(seed, b, 3)
		var start := top - Vector3(0, th * 0.25, 0)
		var end := crown + Vector3(cos(ang) * rc * 0.5, -rc * 0.1, sin(ang) * rc * 0.5)
		K.line(vb, start, end, bark[0])
	var fams: Array = _families(pal)
	var lo := crown.y - rc * 0.85
	var hi := crown.y + rc * 1.05
	# Shadowed inner core (fills the gaps between clumps with deep shade, so
	# the crown reads as dense foliage with depth instead of see-through).
	var core_c := crown + Vector3(0, -rc * 0.05, 0)
	var core_r := Vector3(rc * 0.78, rc * 0.62, rc * 0.78)
	var core_fam: String = fams[0]
	var deep: Color = (TONES[core_fam] as Array)[2]
	deep = K.shade(deep, 0.86)
	if haze > 0.0:
		deep = deep.lerp(HAZE, haze)
	K.blob(vb, core_c, core_r, deep, 0.1, seed, occ)
	# Leaf clumps: rounded clusters scattered over the crown surface (more
	# on top and on the camera side), each ONE colour family in 3 flat tones.
	var n := int(clampf(rc * rc * 0.28, 14.0, 70.0))
	for k in n:
		var u := K.hs(seed, k, 21)
		var v := K.hs(k, seed, 22)
		var ang := TAU * u
		var yy := lerpf(-0.45, 1.0, sqrt(v))   # biased upwards
		var rr := sqrt(maxf(1.0 - yy * yy, 0.0))
		var dir := Vector3(cos(ang) * rr, yy, sin(ang) * rr)
		var dist := rc * (0.62 + 0.22 * K.hs(seed, k, 23))
		var c := crown + Vector3(dir.x * dist, dir.y * dist * 0.78, dir.z * dist)
		var cr := rc * (0.24 + 0.1 * K.hs(k, seed, 24))
		var rad := Vector3(cr, cr * 0.82, cr)
		var fi := 0 if K.hs(seed, k, 25) < 0.62 else 1 + int(K.hs(seed, k, 26) * 4.0)
		var fam: String = fams[fi % fams.size()]
		K.blob(vb, c, rad, _lobe_shader(c, rad, fam, lo, hi, seed + k, haze), 0.25, seed + k * 7, occ)
