extends Node3D
## Autumn Festival town square (ref2): cobblestone plaza with fallen leaves,
## autumn trees, brick town hall with a clock tower, the FALL TREATS stall,
## a game booth, crafts table, music stage, fountain, lamp posts with maple
## banners, string lights + bunting, pumpkins, hay bales, flower barrels and
## a crowd of townsfolk. Pieces live in scripts/locations/festival/.

const K := preload("res://scripts/locations/festival/kit.gd")
const Ground := preload("res://scripts/locations/festival/ground.gd")
const Trees := preload("res://scripts/locations/festival/trees.gd")
const Town := preload("res://scripts/locations/festival/town.gd")
const Stalls := preload("res://scripts/locations/festival/stalls.gd")
const Stage := preload("res://scripts/locations/festival/stage.gd")
const Decor := preload("res://scripts/locations/festival/decor.gd")
const Crowd := preload("res://scripts/locations/festival/crowd.gd")

const CAMERA := {"target": Vector3(0.6, 1.2, -0.8), "yaw": 0.0, "pitch": 15.0, "distance": 11.0, "fov": 42.0}

var stalls
var stage
var decor
var town
var crowd
var halos: MultiMeshInstance3D


func build() -> void:
	var t0 := Time.get_ticks_msec()
	var ground := Ground.new()
	ground.litter_spots = Trees.spots()
	ground.build(self)
	Trees.new().build(self)
	town = Town.new()
	town.build(self)
	stalls = Stalls.new()
	stalls.build(self)
	stage = Stage.new()
	stage.build(self, Vector3(6.0, 0, -12.5), -12.0)
	decor = Decor.new()
	decor.build(self)
	crowd = Crowd.new()
	crowd.build(self, stalls, stage)
	_lights()
	_interactables()
	if OS.has_environment("VIMS_STATS"):
		print("FESTIVAL_BUILD_MS ", Time.get_ticks_msec() - t0)
		_print_stats.call_deferred()


func _lights() -> void:
	var pts: Array = []
	pts.append_array(stalls.glow_points)
	pts.append_array(stage.glow_points)
	pts.append_array(decor.glow_points)
	for w: Vector3 in town.window_glows:
		pts.append([w, 1.2, Color(1.0, 0.7, 0.35, 0.6)])
	halos = K.halos(pts)
	add_child(halos)
	# A handful of real lights (each costs an extra pass per lit mesh on GL Compatibility).
	K.light(self, Vector3(-3.0, 1.9, 2.0), Color(1.0, 0.66, 0.36), 1.4, 4.0, 0.7)
	K.light(self, stage.node.position + Vector3(0, 3.6, 1.0), Color(1.0, 0.68, 0.4), 1.4, 5.0, 0.6)


func _interactables() -> void:
	Interactable.attach(stalls.treats, "Fall Treats", [
		{"id": "buy_snack", "label": "Buy Snack", "icon": "cart", "minutes": 10.0, "pose": "talk",
		 "money": -6, "needs": {"hunger": 0.35, "fun": 0.05}, "task": "Buy Festival Snack"},
		{"id": "buy_cider", "label": "Buy Apple Cider", "icon": "apple", "minutes": 8.0, "pose": "talk",
		 "money": -4, "needs": {"hunger": 0.15, "fun": 0.1}},
		{"id": "chat_vendor", "label": "Chat", "icon": "chat", "minutes": 10.0, "pose": "talk",
		 "needs": {"social": 0.2}, "task": "Meet 3 Neighbors", "who": ["adult", "child"]},
	], Vector3(3.0, 2.8, 1.6), Vector3(0, 1.4, 0.2), Vector3(0.2, 0, 1.6))
	Interactable.attach(stalls.game, "Festival Game", [
		{"id": "play_game", "label": "Play Game", "icon": "target", "minutes": 20.0, "pose": "play",
		 "money": -2, "needs": {"fun": 0.35}, "task": "Play Festival Game", "who": ["adult", "child"]},
		{"id": "win_prize", "label": "Win Prize", "icon": "trophy", "minutes": 15.0, "pose": "wave",
		 "money": -2, "needs": {"fun": 0.4}, "task": "Win Prize", "who": ["adult", "child"]},
	], Vector3(1.8, 2.6, 1.2), Vector3(0, 1.3, 0.1), Vector3(0, 0, 1.2))
	Interactable.attach(stage.node, "Stage", [
		{"id": "watch_show", "label": "Watch Show", "icon": "music", "minutes": 30.0, "pose": "idle",
		 "needs": {"fun": 0.35, "social": 0.1}},
		{"id": "dance", "label": "Dance", "icon": "music", "minutes": 20.0, "pose": "wave",
		 "needs": {"fun": 0.4, "energy": -0.1}, "who": ["adult", "child"]},
	], Vector3(6.2, 4.8, 3.0), Vector3(0, 2.4, 0), Vector3(0, 0, 2.8))
	Interactable.attach(stalls.crafts, "Handmade Crafts", [
		{"id": "browse", "label": "Browse Crafts", "icon": "gift", "minutes": 15.0, "pose": "idle",
		 "needs": {"fun": 0.15}},
		{"id": "buy_plush", "label": "Buy Plush", "icon": "gift", "minutes": 5.0, "pose": "talk",
		 "money": -12, "needs": {"fun": 0.25}},
	], Vector3(2.8, 1.2, 1.2), Vector3(0, 0.6, 0), Vector3(0, 0, 1.2))
	var fountain := Node3D.new()
	fountain.name = "FountainSpot"
	fountain.position = Decor.FOUNTAIN
	add_child(fountain)
	Interactable.attach(fountain, "Fountain", [
		{"id": "photo", "label": "Take Family Photo", "icon": "camera", "minutes": 10.0, "pose": "wave",
		 "needs": {"fun": 0.15, "social": 0.1}, "task": "Take Family Photo"},
		{"id": "wish", "label": "Make a Wish", "icon": "star", "minutes": 5.0, "pose": "idle",
		 "money": -1, "needs": {"fun": 0.1}},
	], Vector3(3.0, 1.2, 3.0), Vector3(0, 0.6, 0), Vector3(0, 0, 2.0))
	for key: String in crowd.npc_keys + ["vendor", "game_host", "crafter", "guitarist"]:
		var a: Node3D = crowd.actors[key]
		Interactable.attach(a, "Neighbor", [
			{"id": "chat", "label": "Chat", "icon": "chat", "minutes": 15.0, "pose": "talk",
			 "needs": {"social": 0.3, "fun": 0.05}, "task": "Meet 3 Neighbors"},
			{"id": "wave", "label": "Wave", "icon": "smile", "minutes": 2.0, "pose": "wave",
			 "needs": {"social": 0.08}},
		], Vector3(0.6, 1.7, 0.6), Vector3(0, 0.85, 0), Vector3(0, 0, 0.9))


## Resolve actors by household name ("Jack"), look ("dad"), or NPC key
## ("vendor", "game_host", "crafter", "guitarist", "neighbor_1".."neighbor_17").
func get_actor(actor_name: String) -> Node3D:
	return crowd.get_actor(actor_name) if crowd else null


func apply_preset(preset: String) -> void:
	if preset != "festival" or crowd == null:
		return
	# Staged poses for the reference screenshot are set at spawn already.


func camera_home() -> Dictionary:
	return CAMERA


## Golden late-afternoon light (the shared lighting.gd reads this).
func lighting_profile() -> Dictionary:
	return {
		"sun_heading": -28.0, "sun_elev": 30.0, "sun_energy": 1.7,
		"ambient_day": Color(0.94, 0.86, 0.8), "ambient_energy": 0.75,
		"ambient_night": Color(0.42, 0.38, 0.62), "ambient_night_energy": 0.5,
		"sky_day": Color(0.93, 0.84, 0.72), "sky_night": Color(0.1, 0.1, 0.22),
		"fog_day": Color(0.95, 0.85, 0.72), "fog_night": Color(0.12, 0.12, 0.26),
		"fog_density": 0.0045, "exposure": 1.0, "shadow_distance": 40.0,
		"lamp_night_mult": 1.6,
		"post": {"focus_y": 0.62, "band": 0.22, "falloff": 0.32, "blur_px": 5.5, "top_boost": 1.1,
			"saturation": 1.08, "contrast": 1.07, "tint": Vector3(1.01, 1.0, 0.98), "vignette": 0.2},
	}


func _print_stats() -> void:
	for i in 8:
		await get_tree().process_frame
	var tris := 0
	var meshes := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh:
			meshes += 1
			for si in mi.mesh.get_surface_count():
				var arr = mi.mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				var n: int = (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				tris += n
				if n > 4000:
					print("  mesh ", mi.name, " surf ", si, " tris ", n)
	print("FESTIVAL_STATS meshes=%d tris=%d draws=%d prims=%d" % [meshes, tris,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
