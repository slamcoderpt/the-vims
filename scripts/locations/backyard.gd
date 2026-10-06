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

const CAMERA := {"target": Vector3(1.4, 0.6, -0.6), "yaw": -8.0, "pitch": 24.0, "distance": 12.5, "fov": 36.0}

var garden
var house
var party
var cast
var sunset
var _t := 0.0
var _shared_env: Environment


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
	_shared_env = shared
	sunset.update(Game.hour())
	# Lighting.configure() runs right after build(); sync once it has.
	_sync_env.call_deferred()
	if not Game.time_changed.is_connected(_on_time):
		Game.time_changed.connect(_on_time)


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
	], Vector3(3.2, 0.8, 1.2), Vector3(0, 0.4, 0), Vector3(0, 0, 0.85))
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
	# Shared lighting supports sun_yaw; the sky/ambient/fog look is applied
	# locally through sunset_env.gd (camera environment override).
	return {
		"sun_heading": 262.0, "sun_elev": 13.0, "sun_energy": 2.4,
		"ambient_day": Color(0.98, 0.74, 0.66), "ambient_night": Color(0.52, 0.42, 0.70),
		"ambient_energy": 0.8, "ambient_night_energy": 0.62,
		"exposure": 1.08, "shadow_distance": 34.0,
		"post": {"focus_y": 0.6, "band": 0.2, "falloff": 0.32, "blur_px": 7.0, "top_boost": 1.25,
			"saturation": 1.14, "contrast": 1.05, "tint": Vector3(1.05, 0.98, 0.95), "vignette": 0.24},
	}
