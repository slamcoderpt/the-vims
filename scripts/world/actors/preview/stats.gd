extends Node
## Throwaway: run the main scene (pass --shot=<preset>) and print render stats.

var _n := 0


func _ready() -> void:
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene")
	add_child(load(main_path).instantiate())


func _process(_d: float) -> void:
	_n += 1
	if _n == 41:
		var n := 0
		var tris := 0
		for a in get_tree().root.find_children("*", "SimActor", true, false):
			n += 1
			tris += (a as SimActor).mesh_instance.mesh.surface_get_array_index_len(0) / 3
		print("ACTORS ", n, " tris=", tris)
		get_tree().quit()
	if _n % 10 == 0:
		print("STATS frame=", _n, " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " objs=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
