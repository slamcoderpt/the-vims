extends RefCounted
## Sunset sky + environment for the backyard. The shared lighting rig only
## exposes a solid background colour, so the backyard assigns its own
## Environment (copied from the shared one, so global settings carry over) to
## the active camera while it is loaded.

const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.30, 0.22, 0.48);
uniform vec3 mid_color : source_color = vec3(0.78, 0.42, 0.55);
uniform vec3 low_color : source_color = vec3(1.0, 0.62, 0.42);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.80, 0.52);
uniform vec3 sun_dir = vec3(-0.85, 0.08, -0.5);
uniform vec3 sun_color : source_color = vec3(1.0, 0.75, 0.45);
uniform float horizon_y = -0.24;
uniform float zenith_y = -0.02;
uniform float brightness = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float t = clamp((d.y - horizon_y) / (zenith_y - horizon_y), 0.0, 1.0);
	vec3 c = mix(horizon_color, low_color, smoothstep(0.0, 0.18, t));
	c = mix(c, mid_color, smoothstep(0.12, 0.45, t));
	c = mix(c, top_color, smoothstep(0.4, 1.0, t));
	// Streaky sunset clouds (pink lit undersides, violet bodies).
	vec2 uv = vec2(atan(d.x, -d.z) * 3.0, t * 18.0);
	float n = noise(uv * vec2(1.0, 1.0)) * 0.6 + noise(uv * vec2(2.3, 2.0)) * 0.4;
	float band = smoothstep(0.15, 0.3, t) * (1.0 - smoothstep(0.55, 0.8, t));
	float cl = smoothstep(0.55, 0.8, n) * band;
	c = mix(c, mix(vec3(0.98, 0.55, 0.55), vec3(0.62, 0.38, 0.62), t), cl * 0.6);
	// Sun glow.
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	c += sun_color * (pow(s, 6.0) * 0.35 + pow(s, 60.0) * 0.6);
	COLOR = c * brightness;
}
"""

var env: Environment
var sky_mat: ShaderMaterial
var camera: Camera3D


func setup(viewport: Viewport, shared_env: Environment) -> void:
	env = shared_env.duplicate() if shared_env else Environment.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.50, 0.66)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.78, 0.52, 0.62)
	env.fog_light_energy = 1.0
	env.fog_density = 0.6
	env.fog_depth_begin = 14.0
	env.fog_depth_end = 55.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.15
	camera = viewport.get_camera_3d()
	if camera:
		camera.environment = env


## Pull the per-time values the shared lighting computed (from our profile)
## so ambient / exposure / glow / grade stay in step with the clock.
func sync(shared: Environment) -> void:
	if shared == null or env == null:
		return
	env.ambient_light_color = shared.ambient_light_color
	env.ambient_light_energy = shared.ambient_light_energy
	env.tonemap_exposure = shared.tonemap_exposure
	env.glow_intensity = shared.glow_intensity
	env.glow_hdr_threshold = shared.glow_hdr_threshold
	env.glow_bloom = shared.glow_bloom
	env.glow_blend_mode = shared.glow_blend_mode
	for i in 7:
		env.set_glow_level(i, shared.get_glow_level(i))


func update(hour: float) -> void:
	# 0 = golden sunset (~19:30), 1 = night; day = afternoon blue.
	var n := smoothstep(19.9, 21.5, hour) if hour > 12.0 else 1.0 - smoothstep(5.0, 7.0, hour)
	var day := 1.0 - smoothstep(17.0, 19.0, hour) if hour > 12.0 else smoothstep(6.0, 8.0, hour)
	if sky_mat == null:
		return
	sky_mat.set_shader_parameter("brightness", lerpf(1.0, 0.3, n))
	var top := Color(0.30, 0.22, 0.48).lerp(Color(0.05, 0.06, 0.16), n).lerp(Color(0.38, 0.58, 0.9), day)
	var mid := Color(0.80, 0.42, 0.58).lerp(Color(0.16, 0.12, 0.3), n).lerp(Color(0.6, 0.76, 0.95), day)
	var low := Color(1.0, 0.58, 0.40).lerp(Color(0.3, 0.16, 0.3), n).lerp(Color(0.8, 0.86, 0.95), day)
	var hor := Color(1.0, 0.80, 0.52).lerp(Color(0.36, 0.2, 0.3), n).lerp(Color(0.92, 0.9, 0.86), day)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("mid_color", mid)
	sky_mat.set_shader_parameter("low_color", low)
	sky_mat.set_shader_parameter("horizon_color", hor)
	env.fog_light_color = Color(0.86, 0.55, 0.6).lerp(Color(0.2, 0.16, 0.3), n).lerp(Color(0.85, 0.85, 0.88), day)


func release() -> void:
	if camera and is_instance_valid(camera) and camera.environment == env:
		camera.environment = null
