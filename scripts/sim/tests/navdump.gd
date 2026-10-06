extends Node
## Debug: dump the NavGrid of the start location as images and quit.
## tools/playtest.sh navdump  (with --location=<name>)

var main: Node
var args := {}


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame
	var sim = main.sim
	var dir: String = args.get("shots", "res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for li in sim.nav.level_y.size():
		var img: Image = sim.nav.debug_image(li, 3)
		img.save_png("%s/nav_%s_%d.png" % [dir, sim.loc_name, li])
	print("NAVDUMP ", sim.loc_name, " ", sim.nav.w, "x", sim.nav.h, " ms=", sim.nav.build_ms)
	get_tree().quit()
