extends Node
var main: Node
var args := {}
func _ready() -> void:
	for i in 4:
		await get_tree().process_frame
	var sim = main.sim
	var nav: NavGrid = sim.nav
	for probe in [Vector3(-1.0, 3.0, 2.0), Vector3(2.75, 3.0, 0.0), Vector3(5.5, 3.0, 4.0), Vector3(4.7, 3.0, 0.0)]:
		var c := nav.cell_of(probe)
		var row := ""
		for dx in range(-3, 4):
			for dz in [0]:
				pass
		# print a 7x7 block map around it
		print("probe ", probe, " cell ", c)
		for dz in range(-3, 4):
			var line := ""
			for dx in range(-3, 4):
				var q := c + Vector2i(dx, dz)
				var i := q.y * nav.w + q.x
				line += str(nav.block[1][i]) + ("f" if nav.floors[1][i] != INF else "-") + " "
			print("   ", line)
		for mi: MeshInstance3D in sim.location.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null: continue
			var ab: AABB = mi.global_transform * mi.get_aabb()
			var box := AABB(Vector3(probe.x - 0.15, 3.17, probe.z - 0.15), Vector3(0.3, 1.3, 0.3))
			if ab.intersects(box) and ab.size.x < 30:
				print("   mesh ", mi.get_path(), " ", ab)
	get_tree().quit()
