extends Node3D
## Autumn Festival town square (ref2): cobblestone plaza with fallen leaves,
## autumn trees, brick town hall with a clock tower, the FALL TREATS stall,
## a game booth, crafts table, music stage, fountain, lamp posts with maple
## banners, string lights + bunting, pumpkins, hay bales, flower barrels and
## a crowd of townsfolk. Pieces live in scripts/locations/festival/.

const K := preload("res://scripts/locations/festival/kit.gd")
const ShotPresets := preload("res://scripts/core/shot_presets.gd")
const Ground := preload("res://scripts/locations/festival/ground.gd")
const Trees := preload("res://scripts/locations/festival/trees.gd")
const Town := preload("res://scripts/locations/festival/town.gd")
const Stalls := preload("res://scripts/locations/festival/stalls.gd")
const Stage := preload("res://scripts/locations/festival/stage.gd")
const Decor := preload("res://scripts/locations/festival/decor.gd")
const Crowd := preload("res://scripts/locations/festival/crowd.gd")

## Camera lock (game owner): the festival uses the same high Sims-style 3/4
## camera as the rest of the game (pitch 32-38, fov 37-42, similar distance),
## never the concept art's eye-level angle. The live camera and the
## screenshot preset are the same shot (see ShotPresets "festival").
## Round 12 (game owner): same distance / character screen size as home and
## backyard (adult ~220 px tall at 1672x941). The square is composed for
## this camera: depth behind z = -5 is compressed (K.dz) so the fountain,
## stage and town-hall front all land in the upper third, with short-trunked
## trees whose canopies drop into the top band.
const TOWN_SCALE := 0.58
const STAGE_POS := Vector3(2.7, 0, -8.5)  # r12: upper centre-right, clear of the HUD task panel
const TOWN_POS := Vector3(0.0, -0.3, 2.75)  # hall front at z ~ -14.05 (= K.dz(-22.4))

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
	var town_root := Node3D.new()
	town_root.name = "Town"
	town_root.position = TOWN_POS
	town_root.scale = Vector3.ONE * TOWN_SCALE
	add_child(town_root)
	town = Town.new()
	town.build(town_root)
	stalls = Stalls.new()
	stalls.build(self)
	stage = Stage.new()
	stage.build(self, STAGE_POS, -8.0)
	decor = Decor.new()
	decor.stage_pos = STAGE_POS
	decor.build(self)
	crowd = Crowd.new()
	crowd.build(self, stalls, stage)
	_lights()
	_interactables()
	_tune_env.call_deferred()
	Game.time_changed.connect(_on_time_changed)
	if OS.has_environment("VIMS_STATS"):
		print("FESTIVAL_BUILD_MS ", Time.get_ticks_msec() - t0)
		_print_stats.call_deferred()


func _lights() -> void:
	# Halos are subtle (they suggest glow without washing the frame out);
	# street lamps + floor lanterns get the strongest ones.
	var pts: Array = []
	_add_halos(pts, stalls.glow_points, 0.45)
	_add_halos(pts, stage.glow_points, 0.5)
	_add_halos(pts, decor.glow_points, 0.55)
	for w: Vector3 in town.window_glows:
		pts.append([TOWN_POS + w * TOWN_SCALE, 1.0 * TOWN_SCALE, Color(0.25, 0.16, 0.08, 0.5)])
	halos = K.halos(pts)
	add_child(halos)
	# A handful of real lights (each costs an extra pass per lit mesh on GL Compatibility).
	K.light(self, Vector3(-3.9, 2.3, 0.4), Color(1.0, 0.66, 0.36), 1.5, 4.5, 0.7)
	K.light(self, stage.node.position + Vector3(0, 3.6, 1.0), Color(1.0, 0.68, 0.4), 1.4, 5.0, 0.6)


func _add_halos(out: Array, src: Array, k: float) -> void:
	for e: Array in src:
		var c: Color = e[2]
		out.append([e[0], e[1] * 0.6, Color(c.r * k, c.g * k * 0.92, c.b * k * 0.85, c.a)])


func _interactables() -> void:
	Interactable.attach(stalls.treats, "Fall Treats", [
		{"id": "buy_snack", "label": "Buy Snack", "icon": "cart", "minutes": 10.0, "pose": "talk",
		 "money": -6, "needs": {"hunger": 0.35, "fun": 0.05}, "task": "Buy Festival Snack"},
		{"id": "buy_cider", "label": "Buy Apple Cider", "icon": "apple", "minutes": 8.0, "pose": "talk",
		 "money": -4, "needs": {"hunger": 0.15, "fun": 0.1}},
		{"id": "chat_vendor", "label": "Chat", "icon": "chat", "minutes": 10.0, "pose": "talk",
		 "needs": {"social": 0.2}, "task": "Meet 3 Neighbors", "who": ["adult", "child"]},
	], Vector3(3.2, 3.8, 1.6), Vector3(0, 1.9, 0.1), Vector3(0.2, 0, 1.6))
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
## ("vendor", "game_host", "crafter", "guitarist", "neighbor_1".."neighbor_8").
func get_actor(actor_name: String) -> Node3D:
	return crowd.get_actor(actor_name) if crowd else null


func apply_preset(preset: String) -> void:
	if preset != "festival" or crowd == null:
		return
	# Staged poses for the reference screenshot are set at spawn already.
	# Keep every face open-eyed for the still (no mid-blink captures).
	for a in crowd.actors.values():
		if "_blink_t" in a:
			a._blink_t = 600.0
	# Debug: VIMS_FCAM="x,y,z,yaw,pitch,dist,fov" overrides the shot camera.
	if OS.has_environment("VIMS_FCAM"):
		_debug_cam.call_deferred(OS.get_environment("VIMS_FCAM"))


func _debug_cam(s: String) -> void:
	var v := s.split_floats(",")
	var rig := get_parent().get_node_or_null("CameraRig")
	if rig and v.size() >= 7:
		rig.apply({"target": Vector3(v[0], v[1], v[2]), "yaw": v[3], "pitch": v[4], "distance": v[5], "fov": v[6]})


func camera_home() -> Dictionary:
	return ShotPresets.PRESETS["festival"].camera.duplicate()


## Golden late-afternoon light (the shared lighting.gd reads this).
## Kept deliberately restrained: mid-value cobbles, crisp backdrop, only a
## mild tilt-shift past the fountain (critic round 1: haze/bloom too strong).
func lighting_profile() -> Dictionary:
	# Round 7: the backdrop must stay crisp and saturated against a blue-ish
	# sky. Low warm key from behind-left (golden hour), cool clear sky, almost
	# no haze, very light tilt-shift confined to thin top/bottom bands.
	return {
		"sun_heading": -12.0, "sun_elev": 24.0, "sun_energy": 1.5,
		"ambient_day": Color(0.78, 0.76, 0.84), "ambient_energy": 0.72,
		"ambient_night": Color(0.42, 0.38, 0.62), "ambient_night_energy": 0.45,
		"sky_day": Color(0.56, 0.72, 0.92), "sky_night": Color(0.1, 0.1, 0.22),
		"fog_day": Color(0.78, 0.8, 0.88), "fog_night": Color(0.12, 0.12, 0.26),
		"fog_density": 0.0007, "exposure": 0.98, "shadow_distance": 45.0,
		"lamp_night_mult": 1.6,
		"post": {"focus_y": 0.49, "band": 0.35, "falloff": 0.15, "blur_px": 3.0, "top_boost": 0.6,
			"saturation": 1.1, "contrast": 1.12, "tint": Vector3(1.02, 1.0, 0.96),
			"lift": Vector3(0.0, 0.0, 0.0), "vignette": 0.22, "gamma": 1.04},
	}


func _on_time_changed(_d: int, _m: float) -> void:
	_tune_env()


## lighting.gd owns the Environment; it re-applies a fairly strong global glow
## on every time change, which washes this bright scene out. Tame it here.
func _tune_env() -> void:
	var lt := get_parent().get_node_or_null("Lighting") if get_parent() else null
	if lt == null or not ("env" in lt) or lt.env == null:
		return
	var env: Environment = lt.env
	var n: float = lt.night
	env.glow_intensity = lerpf(0.34, 0.6, n)
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = lerpf(1.15, 0.9, n)
	env.tonemap_white = 5.0
	# Golden late-afternoon key: warmer than lighting.gd's default ramp.
	if "sun" in lt and lt.sun:
		lt.sun.light_color = Color(1.0, 0.8, 0.58)


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
				if n > 2500:
					print("  mesh ", mi.get_parent().name, "/", mi.name, " vis=", mi.is_visible_in_tree(), " surf ", si, " tris ", n)
	var cam := get_viewport().get_camera_3d()
	if cam:
		for k: String in ["Jack", "Lily", "Maya", "Biscuit", "vendor", "guitarist", "game_host", "crafter", "neighbor_6", "neighbor_7"]:
			var a: Node3D = crowd.actors.get(k)
			if a:
				var f := cam.unproject_position(a.global_position)
				var h := cam.unproject_position(a.head_top()) if a.has_method("head_top") else f
				print("SCREEN %s feet=%s head=%s h=%d worldh=%.2f" % [k, f.round(), h.round(), int(f.y - h.y), (a.head_top().y - a.global_position.y) if a.has_method("head_top") else 0.0])
		for k: String in ["Fountain", "Stage", "TreatsStall", "GameStall", "CraftsStall"]:
			var n := find_child(k, true, false) as Node3D
			if n:
				print("SCREEN %s %s" % [k, cam.unproject_position(n.global_position).round()])
		print("SCREEN FountainSpot ", cam.unproject_position(Decor.FOUNTAIN).round())
		var cw: Vector3 = TOWN_POS + town.clock_center * TOWN_SCALE
		print("SCREEN Clock world=%s px=%s cam=%s" % [cw, cam.unproject_position(cw).round(), cam.global_position])
	print("FESTIVAL_STATS meshes=%d tris=%d draws=%d prims=%d" % [meshes, tris,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	# Same frame without the 2D layers (HUD + post), to isolate the 3D cost.
	var hidden: Array = []
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if c.visible:
			c.visible = false
			hidden.append(c)
	for i in 3:
		await get_tree().process_frame
	print("FESTIVAL_STATS_3D draws=%d objects=%d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	for c in hidden:
		c.visible = true
