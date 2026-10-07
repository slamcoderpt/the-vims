extends Node3D
## Backyard BBQ at sunset (ref4): the back of the family house with a lit
## porch deck, string lights, grill, long dinner table, fire pit lounge,
## flower beds, picket fences and neighbours' houses against a purple-orange
## sky. Pieces live in scripts/locations/backyard/.

const Garden := preload("res://scripts/locations/backyard/garden.gd")
const House := preload("res://scripts/locations/backyard/house.gd")
const Party := preload("res://scripts/locations/backyard/party.gd")
const Cast := preload("res://scripts/locations/backyard/cast.gd")
const SunsetEnv := preload("res://scripts/locations/backyard/sunset_env.gd")

const CAMERA := {"target": Vector3(1.8, 0.6, -2.0), "yaw": -14.0, "pitch": 25.0, "distance": 11.5, "fov": 58.0}

var garden
var house
var party
var cast
var sunset
var _t := 0.0
var _shared_env: Environment
var fill: DirectionalLight3D


func build() -> void:
	garden = Garden.new()
	garden.build(self)
	house = House.new()
	house.build(self)
	party = Party.new()
	party.build(self)
	cast = Cast.new()
	cast.build(self, party)
	_interactables()
	sunset = SunsetEnv.new()
	var shared: Environment = null
	var lighting := get_parent().get_node_or_null("Lighting") if get_parent() else null
	if lighting and "env" in lighting:
		shared = lighting.env
	sunset.setup(get_viewport(), shared)
	# Warm golden bounce from the camera side (no shadows): keeps faces,
	# pickets and the table cloth reading warm instead of lilac while the
	# real sun sits low behind the yard.
	fill = DirectionalLight3D.new()
	fill.name = "SunsetFill"
	fill.shadow_enabled = false
	fill.light_color = Color(1.0, 0.74, 0.5)
	fill.rotation_degrees = Vector3(-28.0, -20.0, 0.0)
	fill.light_specular = 0.0
	add_child(fill)
	_shared_env = shared
	sunset.update(Game.hour())
	# Lighting.configure() runs right after build(); sync once it has.
	_sync_env.call_deferred()
	if not Game.time_changed.is_connected(_on_time):
		Game.time_changed.connect(_on_time)
	if OS.has_environment("VIMS_STATS"):
		_print_stats.call_deferred()


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
				var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				tris += n
				if n > 4000:
					print("  mesh ", mi.name, " surf ", si, " tris ", n)
	var vp := get_viewport()
	print("BACKYARD_DRAWS visible=%d shadow=%d canvas=%d" % [
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	print("BACKYARD_STATS meshes=%d tris=%d draws=%d prims=%d" % [meshes, tris,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _exit_tree() -> void:
	if sunset:
		sunset.release()
	if Game.time_changed.is_connected(_on_time):
		Game.time_changed.disconnect(_on_time)


func _on_time(_d: int, _m: float) -> void:
	_sync_env()


func _sync_env() -> void:
	if sunset:
		sunset.sync(_shared_env)
		sunset.update(Game.hour())
	if garden:
		var hh := Game.hour()
		var on := smoothstep(17.5, 19.5, hh) if hh > 12.0 else 1.0 - smoothstep(5.5, 7.0, hh)
		garden.set_lamp_glow(on)
		if party:
			party.halos.set_strength(on)
	if fill:
		var h := Game.hour()
		# Golden around sunset, a faint cool moon-fill at night, off by day.
		var gold := smoothstep(16.5, 18.5, h) * (1.0 - smoothstep(20.0, 21.5, h))
		var nite := smoothstep(20.5, 22.0, h) if h > 12.0 else 1.0 - smoothstep(4.5, 6.0, h)
		fill.light_color = Color(1.0, 0.74, 0.5).lerp(Color(0.6, 0.66, 1.0), nite)
		fill.light_energy = gold * 0.42 + nite * 0.12
		fill.visible = fill.light_energy > 0.01


func _process(delta: float) -> void:
	_t += delta
	if party:
		party.process(_t)


func _interactables() -> void:
	var grill: Node3D = party.grill_node
	Interactable.attach(grill, "Grill", [
		{"id": "cook", "label": "Cook Food", "icon": "cook", "minutes": 45.0, "pose": "grill",
		 "skill": "Cooking", "needs": {"fun": 0.1}, "task": "Grill Dinner", "who": ["adult"]},
		{"id": "serve", "label": "Serve Food", "icon": "plate", "minutes": 15.0, "pose": "idle",
		 "needs": {"social": 0.1}, "task": "Serve Food", "who": ["adult"]},
		{"id": "invite", "label": "Invite to Eat", "icon": "people", "minutes": 5.0, "pose": "wave",
		 "needs": {"social": 0.15}, "who": ["adult", "child"]},
		{"id": "give", "label": "Give Food", "icon": "gift", "minutes": 5.0, "pose": "idle",
		 "needs": {"social": 0.1}, "who": ["adult", "child"]},
	], Vector3(1.2, 1.1, 0.8), Vector3(0, 0.55, 0), Vector3(0, 0, 0.65))
	Interactable.attach(party.table_node, "Dinner Table", [
		{"id": "eat", "label": "Eat", "icon": "burger", "minutes": 30.0, "pose": "sit",
		 "needs": {"hunger": 0.6, "social": 0.1}},
		{"id": "chat_table", "label": "Chat at Table", "icon": "chat", "minutes": 20.0, "pose": "sit_talk",
		 "needs": {"social": 0.25}, "task": "Talk to Neighbors"},
	], Vector3(4.4, 0.8, 1.6), Vector3(0, 0.4, 0), Vector3(0, 0, 1.0))
	var pit := Node3D.new()
	pit.name = "FirePit"
	pit.position = Party.PIT_POS
	add_child(pit)
	Interactable.attach(pit, "Fire Pit", [
		{"id": "warm", "label": "Warm Up", "icon": "fire", "minutes": 20.0, "pose": "idle",
		 "needs": {"fun": 0.15, "energy": 0.05}},
		{"id": "stories", "label": "Tell Stories", "icon": "chat", "minutes": 30.0, "pose": "talk",
		 "needs": {"social": 0.3, "fun": 0.1}},
	], Vector3(1.3, 0.6, 1.3), Vector3(0, 0.3, 0), Vector3(-0.9, 0, 0.3))


## Resolve actors by household name, look or neighbour key ("neighbor_1".."neighbor_8", "npc_N").
func get_actor(actor_name: String) -> Node3D:
	return cast.get_actor(actor_name) if cast else null


func apply_preset(preset: String) -> void:
	if preset != "bbq" or cast == null:
		return
	var jack = cast.get_actor("Jack")
	if jack and jack.has_method("set_pose"):
		jack.set_pose("grill")


func camera_home() -> Dictionary:
	return CAMERA


func lighting_profile() -> Dictionary:
	# Sun, ambient, exposure and screen post come from the shared lighting rig;
	# the gradient sky + depth fog are applied locally by sunset_env.gd
	# (camera environment override, synced from the shared environment).
	# Dusk: a low, weak orange sun and a cool violet ambient so the lanterns,
	# string lights, fire pit and the lit house make the warm pools.
	return {
		"sun_heading": 262.0, "sun_elev": 11.0, "sun_energy": 1.25,
		"ambient_day": Color(0.78, 0.62, 0.74), "ambient_night": Color(0.40, 0.38, 0.66),
		"ambient_energy": 0.62, "ambient_night_energy": 0.5,
		"exposure": 1.0, "shadow_distance": 30.0,
		"lamp_night_mult": 1.35, "glow_boost_night": 1.9,
		"post": {"focus_y": 0.6, "band": 0.27, "falloff": 0.45, "blur_px": 4.0, "top_boost": 0.95,
			"saturation": 1.12, "contrast": 1.06, "tint": Vector3(1.04, 0.97, 0.98), "vignette": 0.26},
	}
