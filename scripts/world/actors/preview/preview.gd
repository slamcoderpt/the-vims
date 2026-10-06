extends Node3D
## Throwaway character preview (not used by the game).
## godot ... res://scripts/world/actors/preview/preview.tscn -- --mode=lineup --out=/path.png

var mode := "lineup"
var out := "user://preview.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	Game.frozen = true
	Game.set_time(1, 14, 16)
	var lighting: Node = preload("res://scripts/world/lighting.gd").new()
	add_child(lighting)
	var rig: Node3D = preload("res://scripts/world/camera_rig.gd").new()
	add_child(rig)
	# Floor: warm wood planks + a rug.
	var vb := VoxelBuilder.new()
	vb.box(Vector3i(-120, -1, -80), Vector3i(240, 1, 160), func(p: Vector3i) -> Color:
		var plank := posmod(p.z, 3) == 0
		var c := Color(0.72, 0.5, 0.3) if not plank else Color(0.64, 0.44, 0.26)
		return c * (0.92 + 0.16 * VoxelBuilder.hash3(Vector3i(p.x / 5, 0, p.z))))
	add_child(vb.build_instance(0.0625))
	var looks := ["dad", "bunny_girl", "cat_girl", "beagle", "npc_0", "npc_1", "npc_2", "npc_3", "npc_4", "npc_5", "npc_6", "npc_7"]
	match mode:
		"lineup":
			var x := -5.2
			for l in looks:
				var a := SimActor.create(l)
				add_child(a)
				a.position = Vector3(x, 0, 0)
				x += 0.95
			rig.apply({"target": Vector3(0, 0.8, 0), "yaw": 0.0, "pitch": 12.0, "distance": 13.0, "fov": 30.0})
		"closeup":
			var specs := [["dad", Vector3(-1.2, 0, 0)], ["bunny_girl", Vector3(-0.1, 0, 0)], ["cat_girl", Vector3(0.8, 0, 0)], ["beagle", Vector3(1.7, 0, 0.2)]]
			for s in specs:
				var a := SimActor.create(s[0])
				add_child(a)
				a.position = s[1]
			rig.apply({"target": Vector3(0.2, 0.75, 0), "yaw": 15.0, "pitch": 14.0, "distance": 5.0, "fov": 30.0})
		"ref":
			# Approximate ref1 camera and staging (home_day preset camera).
			var specs := [
				["dad", Vector3(-1.5, 0, -1.2), "type", 215.0],
				["bunny_girl", Vector3(0.6, 0, -1.8), "sit_paint", 150.0],
				["cat_girl", Vector3(1.6, 0, 1.0), "play", 10.0],
				["beagle", Vector3(-0.6, 0, 0.8), "lie", 60.0],
				["npc_3", Vector3(-2.6, 0, 1.4), "talk", 40.0],
				["npc_1", Vector3(-3.4, 0, 0.6), "wave", 60.0],
			]
			for s in specs:
				var a := SimActor.create(s[0])
				a.position = s[1]
				a.rotation_degrees.y = s[3]
				add_child(a)
				a.set_pose(s[2])
			rig.apply({"target": Vector3(0, 0.8, 0), "yaw": 35.0, "pitch": 38.0, "distance": 11.0, "fov": 30.0})
		"poses", "poses2":
			var poses := ["idle", "walk", "sit", "sit_floor", "type", "paint", "read", "talk", "wave", "grill", "brush_teeth", "play", "sleep"]
			if mode == "poses2":
				poses = poses.slice(0, 7)
			var x := -6.0
			for p in poses:
				var a := SimActor.create("dad" if poses.find(p) % 2 == 0 else "bunny_girl")
				a.position = Vector3(x, 0, 0)
				add_child(a)
				a.set_pose(p)
				x += 1.0
			var dp := ["idle", "walk", "sit", "lie", "sleep", "play"]
			x = -3.0
			for p in dp:
				var d := SimActor.create("beagle")
				d.position = Vector3(x, 0, 2.0)
				add_child(d)
				d.set_pose(p)
				x += 1.2
			rig.apply({"target": Vector3(0, 0.6, 1.0), "yaw": 30.0, "pitch": 22.0, "distance": 15.0, "fov": 30.0})
			if mode == "poses2":
				rig.apply({"target": Vector3(-3, 0.6, 1.0), "yaw": 35.0, "pitch": 20.0, "distance": 8.0, "fov": 30.0})
		"dogs":
			var dp := ["idle", "walk", "sit", "lie", "sleep", "play"]
			var x := -3.0
			for p in dp:
				var d := SimActor.create("beagle")
				d.position = Vector3(x, 0, 0.0)
				d.rotation_degrees.y = 90.0
				add_child(d)
				d.set_pose(p)
				x += 1.2
			for p in ["sleep", "walk", "sit_floor", "brush_teeth", "grill", "wave"]:
				var a := SimActor.create("cat_girl" if p != "grill" else "dad")
				a.position = Vector3(x - 8.0, 0, -1.6)
				a.rotation_degrees.y = 60.0
				add_child(a)
				a.set_pose(p)
				x += 1.3
			rig.apply({"target": Vector3(0, 0.4, -0.6), "yaw": 0.0, "pitch": 20.0, "distance": 9.0, "fov": 30.0})
		"walktest":
			var a := SimActor.create("dad")
			add_child(a)
			a.position = Vector3(-1, 0, 0)
			a.arrived.connect(func(): print("ARRIVED at ", a.global_position, " pose=", a.pose))
			a.walk_to(Vector3(0.5, 0, 0.5))
			var d := SimActor.create("beagle")
			add_child(d)
			print("kinds ", a.kind(), " ", d.kind(), " head_top ", a.head_top(), " ", d.head_top())
			d.set_pose("sleep")
			print("dog head_top sleeping ", d.head_top())
			rig.apply({"target": Vector3(0, 0.8, 0), "yaw": 35.0, "pitch": 38.0, "distance": 6.0, "fov": 30.0})
			for i in 120:
				await get_tree().process_frame
		"faces":
			var x := -2.0
			for l in ["npc_6", "bunny_girl", "cat_girl", "npc_3", "npc_2"]:
				var a := SimActor.create(l)
				add_child(a)
				a.position = Vector3(x, 0, 0)
				x += 1.0
			rig.apply({"target": Vector3(0, 1.2, 0), "yaw": 10.0, "pitch": 8.0, "distance": 4.5, "fov": 30.0})
	for i in 40:
		await get_tree().process_frame
	for c in get_children():
		if c is SimActor:
			var m: Mesh = c.mesh_instance.mesh
			print("MESH ", c.look, " verts=", m.surface_get_array_len(0), " tris=", m.surface_get_array_index_len(0) / 3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("PREVIEW_SAVED ", out)
	get_tree().quit()
