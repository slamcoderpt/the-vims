extends Node
## Debug: paths from a few probe points to every household-usable object,
## printing failures (tools/playtest.sh navprobe, or headless).

var main: Node
var args := {}


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame
	var sim = main.sim
	var nav: NavGrid = sim.nav
	var probes: Array = [Vector3(8.125, 3.0, 3.875), Vector3(7.125, 3.0, -4.125), Vector3(-2.85, 3.0, -0.1), Vector3(0, 0, 0)]
	for a in sim.agents:
		if a:
			probes.append(a.actor.global_position)
	var lily = sim.agents[1]
	for it in sim.interactables:
		if not is_instance_valid(it) or sim.townie_of(it) != "":
			continue
		for act in sim.actions_for(it, lily.member).slice(0, 1):
			var r: Dictionary = sim.approach(lily, {"action": act, "target": it})
			if r.is_empty():
				print("NO APPROACH ", it.title)
				continue
			var bad: Array = []
			for p in probes:
				nav.find_path(p, r.spot, true)
				if not nav.last_ok:
					bad.append(str(p))
			print("%-16s %-12s spot=%s  %s" % [it.title, act.get("pose", ""), str(r.spot), "OK" if bad.is_empty() else "FAIL from " + ", ".join(bad)])
	for sp in [Vector3(-2.61, 2.97, -3.51)]:
		var li := nav.level_of(sp)
		var c := nav.cell_of(sp)
		print("around ", sp, " cell ", c, " region of approach ", nav.region_of(li, nav.approach_cell(li, c, -1, 48)))
		for z in range(c.y - 9, c.y + 10):
			var row := ""
			for x in range(c.x - 12, c.x + 13):
				if x < 0 or z < 0 or x >= nav.w or z >= nav.h:
					row += " "
					continue
				var v: int = nav.block[li][z * nav.w + x]
				var ch := ".#*o"[v] if v < 4 else "?"
				if nav.floors[li][z * nav.w + x] == INF:
					ch = "_"
				if x == c.x and z == c.y:
					ch = "X"
				row += ch
			print(row)
	var col := AABB(Vector3(-3.4, 3.2, -3.4), Vector3(1.6, 1.2, 1.2))
	for mi: MeshInstance3D in sim.location.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if ab.intersects(col):
			print("MESH ", mi.get_path(), " aabb ", ab, " nav_ignore=", mi.has_meta("nav_ignore"), " vis=", mi.visible)
	get_tree().quit()
