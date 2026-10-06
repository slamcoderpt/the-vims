extends Node3D
## Sun, sky/ambient and post-processing, driven by Game time-of-day and the
## active location (locations may expose `lighting_profile()` -> Dictionary).

var sun: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var profile := {}


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	Game.time_changed.connect(func(_d, _m): _apply())
	_apply()


func configure(location: Node) -> void:
	profile = location.lighting_profile() if location.has_method("lighting_profile") else {}
	_apply()


func _apply() -> void:
	var h := Game.hour()
	# Sun arc: rises 6, sets 20.
	var t := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var elev := sin(t * PI) * 60.0 + 5.0
	sun.rotation_degrees = Vector3(-elev, 180.0 - t * 160.0 + profile.get("sun_yaw", 0.0), 0)
	var day := 1.0 - smoothstep(18.5, 20.5, h) if h > 12.0 else smoothstep(5.5, 7.5, h)
	var warm := Color(1.0, 0.72, 0.45).lerp(Color(1.0, 0.95, 0.85), sin(t * PI))
	sun.light_color = warm
	sun.light_energy = lerpf(0.05, 1.3, day)
	var night_amb := Color(0.18, 0.2, 0.42)
	var day_amb := Color(0.75, 0.72, 0.68)
	env.ambient_light_color = night_amb.lerp(day_amb, day)
	env.ambient_light_energy = lerpf(0.55, 0.65, day)
	env.background_color = Color(0.05, 0.07, 0.18).lerp(Color(0.6, 0.78, 0.95), day)
