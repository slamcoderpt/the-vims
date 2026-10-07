extends Node
## Debug probe: camera cutaway when looking at the ground floor of a 2-storey lot.
var main: Node
var args := {}


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame
	var t := Vector3(6.6, 0.0, 2.0)
	if args.has("at"):
		var p: PackedStringArray = str(args.at).split(",")
		t = Vector3(float(p[0]), float(p[1]), float(p[2]))
	main.camera_rig.apply({"target": t + Vector3(0, 0.8, 0), "yaw": 22.0, "pitch": 52.0, "distance": 6.5})
	for i in 4:
		await get_tree().process_frame
	if args.has("near"):
		main.camera_rig.set_cut_height(INF)
		main.camera_rig.camera.near = float(args.near)
	await get_tree().process_frame
	var cam: Camera3D = main.camera_rig.camera
	print("levels=", main.sim.nav.level_y, " view_floor=", main.view_floor, " cut=", main.camera_rig.cut_height, " near=", cam.near, " cam=", cam.global_position)
	for it in main.sim.interactables:
		if it.title in ["Dining Table", "Stove", "Shower", "Bathtub"]:
			print("  it ", it.title, " center=", it.global_transform * it.look_at_spot)
	var n := 0
	for gi in main.location.find_children("*", "GeometryInstance3D", true, false):
		var bb: AABB = gi.global_transform * gi.get_aabb()
		if bb.grow(0.05).has_point(t + Vector3(0, 0.6, 0)) and n < 30:
			n += 1
			print("  mesh ", gi.get_path(), " aabb=", bb, " vis=", gi.is_visible_in_tree())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(args.get("shots", "/tmp")) + "/cutprobe.png")
	print("RESULT PASS probe")
	get_tree().quit(0)
