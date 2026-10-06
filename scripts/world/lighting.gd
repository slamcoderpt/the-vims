extends Node3D
## Sun / moon, sky + ambient, fog, glow, lamps and screen post (tilt-shift +
## grade), driven by Game time-of-day and the active location.
##
## Locations may expose `lighting_profile()` -> Dictionary with any of:
##   sun_yaw        degrees added to the default sun heading (legacy, relative)
##   sun_heading    absolute heading (deg) the sunlight travels towards (0 = -Z, 90 = -X, 180 = +Z)
##   sun_elev       fixed daytime sun elevation (deg) instead of the arc
##   sun_energy, ambient_energy, ambient_day, ambient_night (Color), sky_day, sky_night (Color)
##   fog_day, fog_night (Color), fog_density
##   exposure, shadow_distance
##   post: Dictionary for post_fx.configure (focus_y, band, blur_px, ...)
##   post_day / post_night: overrides merged by time of day
## Lamps: any OmniLight3D/SpotLight3D in group "vims_lamps" (PropLib.add_light)
## gets energy = base_energy * lerp(day_factor, lamp_night_mult (profile, default 1), night).

const PostFX := preload("res://scripts/world/post/post_fx.gd")
const Mesher := preload("res://scripts/props/mesher.gd")

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var post: CanvasLayer
var profile := {}
## 0 = full day, 1 = full night (read by locations for window glow etc.).
var night := 0.0


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 40.0
	moon.light_color = Color(0.55, 0.66, 1.0)
	add_child(moon)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	post = PostFX.new()
	add_child(post)
	Game.time_changed.connect(func(_d, _m): _apply())
	_apply()


func configure(location: Node) -> void:
	profile = location.lighting_profile() if location.has_method("lighting_profile") else {}
	_apply()


func _apply() -> void:
	var h := Game.hour()
	# Daylight factor: sunrise 5.5-7.5, sunset 18.5-20.5.
	var day := (1.0 - smoothstep(18.5, 20.5, h)) if h > 12.0 else smoothstep(5.5, 7.5, h)
	night = 1.0 - day
	var golden := clampf(1.0 - absf(h - 13.0) / 6.5, 0.0, 1.0)  # 1 at midday, 0 at dawn/dusk
	# --- Sun
	var t := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var elev: float = profile.get("sun_elev", sin(t * PI) * 60.0 + 5.0)
	var heading: float
	if profile.has("sun_heading"):
		heading = profile.sun_heading - t * 40.0 + 20.0
	else:
		heading = 180.0 - t * 160.0 + profile.get("sun_yaw", 0.0)
	sun.rotation_degrees = Vector3(-elev, heading, 0)
	var warm := Color(1.0, 0.66, 0.4).lerp(Color(1.0, 0.94, 0.84), golden)
	sun.light_color = warm
	sun.light_energy = lerpf(0.0, profile.get("sun_energy", 1.35), day)
	sun.visible = day > 0.02
	# --- Moon (night key light, cool, soft).
	moon.rotation_degrees = Vector3(-48.0, profile.get("moon_heading", profile.get("sun_heading", 160.0) + 30.0), 0)
	moon.light_energy = profile.get("moon_energy", 0.32) * night
	moon.visible = night > 0.05
	sun.shadow_enabled = sun.visible
	moon.shadow_enabled = moon.visible and not sun.visible
	if profile.has("shadow_distance"):
		sun.directional_shadow_max_distance = profile.shadow_distance
		moon.directional_shadow_max_distance = profile.shadow_distance
	# --- Ambient + sky + fog
	var amb_night: Color = profile.get("ambient_night", Color(0.32, 0.36, 0.62))
	var amb_day: Color = profile.get("ambient_day", Color(0.92, 0.82, 0.72))
	env.ambient_light_color = amb_night.lerp(amb_day, day)
	env.ambient_light_energy = lerpf(profile.get("ambient_night_energy", 0.42), profile.get("ambient_energy", 0.62), day)
	var sky_n: Color = profile.get("sky_night", Color(0.06, 0.08, 0.2))
	var sky_d: Color = profile.get("sky_day", Color(0.62, 0.8, 0.95))
	env.background_color = sky_n.lerp(sky_d, day)
	var fog_n: Color = profile.get("fog_night", Color(0.09, 0.11, 0.25))
	var fog_d: Color = profile.get("fog_day", Color(0.9, 0.86, 0.78))
	env.fog_light_color = fog_n.lerp(fog_d, day)
	env.fog_density = profile.get("fog_density", 0.006)
	env.tonemap_exposure = profile.get("exposure", lerpf(1.12, 0.95, day))
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.glow_intensity = lerpf(0.5, 0.9, night)
	env.glow_hdr_threshold = lerpf(0.95, 0.7, night)
	# --- Emissive voxels (lamp shades, lit windows) bloom more after dark.
	Mesher.set_glow_boost(lerpf(1.0, profile.get("glow_boost_night", 1.7), night))
	# --- Lamps
	if is_inside_tree():
		for l in get_tree().get_nodes_in_group("vims_lamps"):
			if l is Light3D:
				var base: float = l.get_meta("base_energy", 1.0)
				var df: float = l.get_meta("day_factor", 0.25)
				l.light_energy = base * lerpf(df, profile.get("lamp_night_mult", 1.0), night)
				l.visible = l.light_energy > 0.01 and OS.get_environment("VIMS_NOLAMPS") == ""
				# Shadowed practicals (a couple per scene) only cast after dark:
				# omni shadows are expensive on phones and invisible in daylight.
				if l.has_meta("night_shadow"):
					l.shadow_enabled = night > 0.5
	# --- Post
	var pp := {
		"focus_y": 0.55, "band": 0.14, "falloff": 0.3, "blur_px": 7.0, "top_boost": 1.3,
		"saturation": lerpf(1.03, 1.08, night), "contrast": lerpf(1.08, 1.06, night),
		"tint": Vector3(1.005, 1.0, 0.985).lerp(Vector3(0.99, 0.98, 1.03), night),
		"lift": Vector3(0.004, 0.004, 0.006).lerp(Vector3(0.0, 0.004, 0.02), night),
		"vignette": lerpf(0.22, 0.32, night), "gamma": 1.0,
	}
	pp.merge(profile.get("post", {}), true)
	if OS.get_environment("VIMS_NOPOST") != "":
		pp["enabled"] = false
	pp.merge(profile.get("post_night" if night > 0.5 else "post_day", {}), true)
	post.configure(pp)


## Re-apply lamp energies (call after a location adds lamps).
func refresh() -> void:
	_apply()
