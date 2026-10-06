extends Node
## Debug: dump the NavGrid of the start location as images and quit.
## tools/playtest.sh navdump  (with --location=<name>)
## nav_<loc>_<level>.png: walkability; navreg_<loc>_<level>.png: connected
## regions (one colour each), interactable use spots as white dots.

var main: Node
var args := {}


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame
	var sim = main.sim
	var nav: NavGrid = sim.nav
	var dir: String = args.get("shots", "res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for li in nav.level_y.size():
		var img: Image = nav.debug_image(li, 3)
		img.save_png("%s/nav_%s_%d.png" % [dir, sim.loc_name, li])
		var sc := 4
		var rimg := Image.create(nav.w * sc, nav.h * sc, false, Image.FORMAT_RGB8)
		var sizes := {}
		for c in nav.w * nav.h:
			var r: int = nav.comps[li][c]
			sizes[r] = sizes.get(r, 0) + 1
		for z in nav.h:
			for x in nav.w:
				var r: int = nav.comps[li][z * nav.w + x]
				var col := Color(0.08, 0.08, 0.1)
				if nav.block[li][z * nav.w + x] == 1:
					col = Color(0.5, 0.2, 0.2)
				elif nav.block[li][z * nav.w + x] == 3:
					col = Color(0.35, 0.3, 0.25)
				if r >= 0:
					col = Color.from_hsv(fmod(r * 0.137, 1.0), 0.7, 0.9)
				rimg.fill_rect(Rect2i(x * sc, z * sc, sc, sc), col)
		for it in sim.interactables:
			var p: Vector3 = it.world_use_spot()
			if nav.level_of(p) != li or not nav.in_bounds(p):
				continue
			var c: Vector2i = nav.cell_of(p)
			rimg.fill_rect(Rect2i(c.x * sc - 2, c.y * sc - 2, sc + 4, sc + 4), Color.WHITE)
		for l in nav.links:
			for e in [[l.a, l.la], [l.b, l.lb]]:
				if e[1] == li:
					var c: Vector2i = nav.cell_of(e[0])
					rimg.fill_rect(Rect2i(c.x * sc - 3, c.y * sc - 3, sc + 6, sc + 6), Color.BLACK)
		rimg.save_png("%s/navreg_%s_%d.png" % [dir, sim.loc_name, li])
		var big: Array = []
		for r in sizes:
			if r >= 0 and sizes[r] > 20:
				big.append("%d:%d" % [r, sizes[r]])
		print("level %d regions(>20 cells) %s" % [li, str(big)])
	print("NAVDUMP ", sim.loc_name, " ", nav.w, "x", nav.h, " ms=", nav.build_ms)
	get_tree().quit()
