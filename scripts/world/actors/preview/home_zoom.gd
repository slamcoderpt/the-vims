extends Node3D
## Throwaway: real home_day staging, camera zoomed onto the characters.
## godot ... res://scripts/world/actors/preview/home_zoom.tscn -- --out=/x.png --cam=tx,ty,tz,yaw,pitch,dist,fov

func _ready() -> void:
	var out := "user://hz.png"
	var cam := {"target": Vector3(-5.6, 3.4, -1.6), "yaw": 36.0, "pitch": 36.0, "distance": 6.0, "fov": 30.0}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cam="):
			var v := a.substr(6).split(",")
			cam = {"target": Vector3(float(v[0]), float(v[1]), float(v[2])), "yaw": float(v[3]), "pitch": float(v[4]), "distance": float(v[5]), "fov": float(v[6])}
	Game.frozen = true
	Game.season = 1
	Game.set_time(1, 14, 16)
	var lighting: Node = preload("res://scripts/world/lighting.gd").new()
	add_child(lighting)
	var rig: Node3D = preload("res://scripts/world/camera_rig.gd").new()
	add_child(rig)
	var loc: Node3D = load("res://scripts/locations/home.gd").new()
	add_child(loc)
	loc.build()
	lighting.configure(loc)
	if OS.get_environment("NOPOST") != "":
		lighting.post.visible = false
	loc.apply_preset("home_day")
	rig.apply(cam)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("PREVIEW_SAVED ", out)
	get_tree().quit()
