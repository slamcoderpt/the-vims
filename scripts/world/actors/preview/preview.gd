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
	if mode != "ref":
		lighting.post.visible = false
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
			rig.apply({"target": Vector3(0.2, 0.95, 0), "yaw": 15.0, "pitch": 14.0, "distance": 6.8, "fov": 30.0})
		"kidsit":
			var x := -2.4
			for yy in [0.0, 90.0, 45.0, 180.0]:
				var a := SimActor.create("cat_girl")
				a.position = Vector3(x, 0, 0)
				a.rotation_degrees.y = yy
				add_child(a)
				a.set_pose("play")
				x += 1.2
			for yy in [0.0, 90.0]:
				var a := SimActor.create("bunny_girl")
				a.position = Vector3(x - 5.4, 0, -1.8)
				a.rotation_degrees.y = yy
				a.seat_height = 0.375
				add_child(a)
				a.set_pose("sit_paint")
				x += 1.2
			rig.apply({"target": Vector3(-0.6, 0.4, -0.4), "yaw": 0.0, "pitch": 25.0, "distance": 5.0, "fov": 30.0})
		"dadturn":
			var x := -2.0
			for yy in [1.3, -1.3]:
				var a := SimActor.create("dad")
				a.position = Vector3(x, 0, 0)
				add_child(a)
				a.set_pose("idle")
				a.set_meta("dbg_head_yaw", yy)
				x += 1.5
			rig.apply({"target": Vector3(-1.2, 1.2, 0), "yaw": 0.0, "pitch": 10.0, "distance": 6.0, "fov": 30.0})
		"stage":
			# Home-day camera angle, close, with seats so seated poses read.
			var specs := [
				["dad", Vector3(-1.4, 0, -0.6), "type", -90.0, 0.44],
				["bunny_girl", Vector3(0.2, 0, -1.4), "sit_paint", 125.0, 0.375],
				["cat_girl", Vector3(1.0, 0, 0.6), "play", 45.0, 0.0],
				["beagle", Vector3(-0.6, 0, 0.9), "play", 30.0, 0.0],
			]
			var seat := VoxelBuilder.new()
			for s2 in specs:
				var a := SimActor.create(s2[0])
				a.position = s2[1]
				a.rotation_degrees.y = s2[3]
				if s2[4] > 0.0:
					a.seat_height = s2[4]
					var c := Vector3i(roundi(s2[1].x / 0.0625), 0, roundi(s2[1].z / 0.0625))
					var h := roundi(s2[4] / 0.0625)
					seat.box(c - Vector3i(3, 0, 3), Vector3i(7, h, 7), Color(0.35, 0.35, 0.38))
				add_child(a)
				a.set_pose(s2[2])
			add_child(seat.build_instance(0.0625))
			rig.apply({"target": Vector3(-0.2, 0.5, -0.2), "yaw": 46.0, "pitch": 35.0, "distance": 9.0, "fov": 19.0})
		"homeclose", "homefar":
			# Exact home_day placements, camera closer.
			var specs := [
				["dad", Vector3(-7.5, 0, -2.0), Vector3(-9.5, 0, -2.0), "type", 0.44],
				["bunny_girl", Vector3(-5.75, 0, -2.75), Vector3(-4.6, 0, -3.55), "sit_paint", 0.375],
				["cat_girl", Vector3(-2.85, 0, -0.1), Vector3(-2.1, 0, 0.9), "play", 0.0],
				["beagle", Vector3(-5.6, 0, 0.2), Vector3(-4.9, 0, 0.95), "play", 0.0],
			]
			var seat := VoxelBuilder.new()
			for s2 in specs:
				var a := SimActor.create(s2[0])
				a.position = s2[1]
				add_child(a)
				a.face(s2[2])
				if s2[4] > 0.0:
					a.seat_height = s2[4]
					var c := Vector3i(roundi(s2[1].x / 0.0625), 0, roundi(s2[1].z / 0.0625))
					var h := roundi(s2[4] / 0.0625)
					seat.box(c - Vector3i(3, 0, 3), Vector3i(7, h, 7), Color(0.35, 0.35, 0.38))
				a.set_pose(s2[3])
			add_child(seat.build_instance(0.0625))
			if mode == "homeclose":
				rig.apply({"target": Vector3(-5.2, 0.6, -1.3), "yaw": 46.0, "pitch": 37.0, "distance": 9.0, "fov": 30.0})
			else:
				rig.apply({"target": Vector3(-5.0, 3.1, -0.3), "yaw": 46.0, "pitch": 37.0, "distance": 17.0, "fov": 30.0})
		"ref":
			# Approximate ref1 camera and staging (home_day preset camera).
			var specs := [
				["dad", Vector3(-1.5, 0, -1.2), "type", 270.0],
				["bunny_girl", Vector3(0.6, 0, -1.8), "sit_paint", 150.0],
				["cat_girl", Vector3(1.6, 0, 1.0), "play", 45.0],
				["beagle", Vector3(-0.6, 0, 0.8), "play", 45.0],
				["npc_3", Vector3(-2.6, 0, 1.4), "talk", 40.0],
				["npc_1", Vector3(-3.4, 0, 0.6), "wave", 60.0],
			]
			for s in specs:
				var a := SimActor.create(s[0])
				a.position = s[1]
				a.rotation_degrees.y = s[3]
				add_child(a)
				a.set_pose(s[2])
			rig.apply({"target": Vector3(0, 0.8, 0), "yaw": 46.0, "pitch": 35.0, "distance": 7.0, "fov": 30.0})
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
		"quad":
			# Home-day camera angle, the four household members, each facing
			# the way the home staging has them (dad -X, painter +X-Z).
			var specs := [
				["dad", Vector3(-1.2, 0, -0.4), Vector3(-3.0, 0, -0.25), "type", 0.55],
				["bunny_girl", Vector3(0.6, 0, -0.9), Vector3(1.7, 0, -1.8), "sit_paint", 0.47],
				["cat_girl", Vector3(1.2, 0, 0.9), Vector3(2.0, 0, 2.6), "play", 0.0],
				["beagle", Vector3(-0.6, 0, 1.0), Vector3(0.1, 0, 1.75), "play", 0.0],
			]
			var seat := VoxelBuilder.new()
			for s2 in specs:
				var a := SimActor.create(s2[0])
				a.position = s2[1]
				add_child(a)
				a.body_scale = 1.0
				a.face(s2[2])
				if s2[4] > 0.0:
					a.seat_height = s2[4]
					var c := Vector3i(roundi(s2[1].x / 0.0625), 0, roundi(s2[1].z / 0.0625))
					var h := roundi(s2[4] / 0.0625)
					seat.box(c - Vector3i(3, 0, 3), Vector3i(7, h, 7), Color(0.35, 0.35, 0.38))
				a.set_pose(s2[3])
			add_child(seat.build_instance(0.0625))
			rig.apply({"target": Vector3(0.0, 0.6, 0.1), "yaw": 32.0, "pitch": 31.0, "distance": 9.0, "fov": 30.0})
		"dog4":
			var x := -3.0
			for p in ["idle", "sit", "walk", "sleep"]:
				var d := SimActor.create("beagle")
				d.position = Vector3(x, 0, 0.0)
				d.rotation_degrees.y = 60.0
				add_child(d)
				d.set_pose(p)
				x += 2.0
			rig.apply({"target": Vector3(0, 0.5, 0), "yaw": 10.0, "pitch": 22.0, "distance": 10.0, "fov": 30.0})
		"dogplay":
			var x := -1.6
			for yy in [55.0, -120.0, 180.0]:
				var d := SimActor.create("beagle")
				d.position = Vector3(x, 0, 0)
				d.rotation_degrees.y = yy
				add_child(d)
				d.body_scale = 1.18
				d.set_pose("play")
				x += 1.6
			var h := SimActor.create("dad")
			h.position = Vector3(-1.5, 0, -2.0)
			h.rotation_degrees.y = 180.0
			h.seat_height = 0.5
			add_child(h)
			h.set_pose("type")
			var g := SimActor.create("bunny_girl")
			g.position = Vector3(0.5, 0, -2.0)
			g.rotation_degrees.y = 126.0
			g.seat_height = 0.45
			add_child(g)
			g.set_pose("sit_paint")
			var k := SimActor.create("cat_girl")
			k.position = Vector3(2.0, 0, -1.6)
			k.rotation_degrees.y = 8.0
			add_child(k)
			k.set_pose("play")
			rig.apply({"target": Vector3(0, 0.5, -0.8), "yaw": 33.0, "pitch": 28.0, "distance": 6.5, "fov": 40.0})
		"dogcheck":
			var x := -1.5
			for p in ["play", "idle", "sleep"]:
				var d := SimActor.create("beagle")
				d.position = Vector3(x, 0, 0)
				d.camera_cheat = false
				d.rotation_degrees.y = 90.0
				add_child(d)
				d.set_pose(p)
				x += 1.5
			rig.apply({"target": Vector3(0, 0.3, 0), "yaw": 20.0, "pitch": 40.0, "distance": 4.5, "fov": 30.0})
		"doglie":
			var specs := [["play", Vector3(-1.4, 0, 0)], ["sleep", Vector3(0.2, 0, 0)], ["idle", Vector3(1.6, 0, 0)], ["sit", Vector3(-0.6, 0, -1.4)], ["walk", Vector3(1.0, 0, -1.4)]]
			for s3 in specs:
				var d := SimActor.create("beagle")
				d.position = s3[1]
				add_child(d)
				d.body_scale = 1.0
				d.face(s3[1] + Vector3(0.3, 0, 0.4))
				d.set_pose(s3[0])
			rig.apply({"target": Vector3(0.0, 0.3, -0.5), "yaw": 32.0, "pitch": 31.0, "distance": 8.0, "fov": 32.0})
		"painter":
			var x := -2.4
			for cfg in [[90.0, false], [0.0, false], [130.0, true], [-50.0, true]]:
				var a := SimActor.create("bunny_girl")
				a.position = Vector3(x, 0, 0)
				a.rotation_degrees.y = cfg[0]
				a.camera_cheat = cfg[1]
				add_child(a)
				a.body_scale = 1.0
				a.seat_height = 0.54
				a.set_pose("sit_paint")
				x += 1.6
			rig.apply({"target": Vector3(0.0, 0.8, 0.0), "yaw": 0.0, "pitch": 12.0, "distance": 8.0, "fov": 30.0})
		"dadback":
			var specs := [[Vector3(-0.9, 0, 0), 180.0 + 30.0, "type"], [Vector3(0.9, 0, 0), 20.0, "idle"]]
			for s4 in specs:
				var a := SimActor.create("dad")
				a.position = s4[0]
				a.rotation_degrees.y = s4[1]
				add_child(a)
				a.body_scale = 0.86
				a.seat_height = 0.63
				a.set_pose(s4[2])
			rig.apply({"target": Vector3(0.0, 1.1, 0.0), "yaw": 28.0, "pitch": 34.0, "distance": 6.0, "fov": 30.0})
		"faces":
			var x := -2.0
			for l in ["dad", "bunny_girl", "cat_girl", "npc_3", "npc_2"]:
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
