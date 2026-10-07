extends Node3D
## Throwaway studio: --spec=look:pose:yawdeg;look:pose:yawdeg ... --out=x.png --cam=tx,ty,tz,yaw,pitch,dist,fov
func _ready() -> void:
	var out := "user://studio.png"
	var spec := "cat_girl:play:0"
	var cam := {"target": Vector3(0, 0.5, 0), "yaw": 22.0, "pitch": 37.0, "distance": 6.0, "fov": 30.0}
	var gap := 1.4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--spec="): spec = a.substr(7)
		elif a.begins_with("--gap="): gap = float(a.substr(6))
		elif a.begins_with("--cam="):
			var v := a.substr(6).split(",")
			cam = {"target": Vector3(float(v[0]), float(v[1]), float(v[2])), "yaw": float(v[3]), "pitch": float(v[4]), "distance": float(v[5]), "fov": float(v[6])}
	Game.frozen = true
	Game.set_time(1, 14, 16)
	var lighting: Node = preload("res://scripts/world/lighting.gd").new()
	add_child(lighting)
	lighting.post.visible = false
	var rig: Node3D = preload("res://scripts/world/camera_rig.gd").new()
	add_child(rig)
	var vb := VoxelBuilder.new()
	vb.box(Vector3i(-80, -1, -50), Vector3i(160, 1, 100), func(p: Vector3i) -> Color:
		return Color(0.72, 0.5, 0.3) * (0.9 + 0.12 * float(posmod(p.z, 3) == 0)))
	add_child(vb.build_instance(0.0625))
	rig.apply(cam)
	var items := spec.split(";")
	var r := Basis.from_euler(Vector3(0, deg_to_rad(cam.yaw), 0))
	var x0 := -gap * (items.size() - 1) * 0.5
	for i in items.size():
		var f := items[i].split(":")
		var a := SimActor.create(f[0])
		a.body_scale = 0.76 if f[0].ends_with("girl") else (0.58 if f[0] == "beagle" else 0.946)
		add_child(a)
		var k: float = a.body_scale / a.skeleton.scale.x
		if k < 0.999: a.scale = Vector3.ONE * k
		a.position = Vector3(cam.target.x, 0, cam.target.z) + r * Vector3(x0 + gap * i, 0, 0)
		if OS.get_environment("NOCHEAT") != "": a.camera_cheat = false
		a.rotation_degrees.y = float(f[2]) if f.size() > 2 else 0.0
		if f.size() > 3: a.seat_height = float(f[3]) / a.scale.y
		a.set_pose(f[1])
		if f[1].contains("paint") or f[1].begins_with("sit") or f[1] == "type":
			var st := VoxelBuilder.new()
			var sh := int(round((float(f[3]) if f.size() > 3 else 0.45) / 0.0625))
			st.box(Vector3i(-3, 0, -3), Vector3i(6, sh, 6), Color(0.5, 0.3, 0.2))
			var m := st.build_instance(0.0625)
			m.position = a.position
			add_child(m)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("STUDIO_SAVED ", out)
	get_tree().quit()
