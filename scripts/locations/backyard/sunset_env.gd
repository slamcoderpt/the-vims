extends RefCounted
## Sunset sky + environment for the backyard. The shared lighting rig only
## exposes a solid background colour, so the backyard assigns its own
## Environment (copied from the shared one, so global settings carry over) to
## the active camera while it is loaded.

const SKY_SHADER := """
shader_type sky;
// Sunset gradient: warm gold at the horizon -> peach/orange -> pink ->
// violet overhead, with streaky lit clouds and a soft sun glow.
uniform vec3 top_color : source_color = vec3(0.30, 0.22, 0.48);
uniform vec3 mid_color : source_color = vec3(0.78, 0.42, 0.55);
uniform vec3 low_color : source_color = vec3(1.0, 0.62, 0.42);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.80, 0.52);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.62, 0.55);
uniform vec3 cloud_dark : source_color = vec3(0.52, 0.34, 0.58);
uniform vec3 sun_dir = vec3(-0.85, 0.08, -0.5);
uniform vec3 sun_color : source_color = vec3(1.0, 0.75, 0.45);
uniform float horizon_y = -0.02;
uniform float zenith_y = 0.34;
uniform float brightness = 1.0;
uniform float cloud_amount = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float t = clamp((d.y - horizon_y) / (zenith_y - horizon_y), 0.0, 1.0);
	vec3 c = mix(horizon_color, low_color, smoothstep(0.0, 0.22, t));
	c = mix(c, mid_color, smoothstep(0.16, 0.5, t));
	c = mix(c, top_color, smoothstep(0.45, 1.0, t));
	// Streaky sunset clouds: long horizontal wisps, lit pink-orange from
	// below near the horizon, cooler violet higher up.
	float az = atan(d.x, -d.z);
	vec2 uv = vec2(az * 5.0, t * 22.0);
	float n = noise(uv * vec2(0.6, 1.0)) * 0.55 + noise(uv * vec2(1.7, 2.3) + 3.1) * 0.3 + noise(uv * vec2(4.0, 5.0)) * 0.15;
	float band = smoothstep(0.12, 0.26, t) * (1.0 - smoothstep(0.7, 0.95, t));
	float cl = smoothstep(0.52, 0.72, n) * band * cloud_amount;
	vec3 ccol = mix(cloud_lit, cloud_dark, smoothstep(0.25, 0.75, t));
	c = mix(c, ccol, cl * 0.75);
	// Thin bright rims under the clouds.
	float rim = smoothstep(0.55, 0.6, n) * (1.0 - smoothstep(0.6, 0.66, n)) * band * cloud_amount;
	c += cloud_lit * rim * 0.12;
	// Sun glow low on the horizon.
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	c += sun_color * (pow(s, 4.0) * 0.32 + pow(s, 40.0) * 0.5);
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
	env.fog_density = 0.22
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 60.0
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
	# Saturated dusk: gold -> tangerine -> magenta-pink -> violet. The bbq
	# camera looks down at the yard, so the only sky it sees lies just
	# below the true horizon (behind the sunken neighbour lots): the
	# gradient is compressed into that band so it reads purple -> orange.
	var top := Color(0.30, 0.16, 0.50).lerp(Color(0.05, 0.06, 0.16), n).lerp(Color(0.38, 0.58, 0.9), day)
	var mid := Color(0.78, 0.28, 0.56).lerp(Color(0.16, 0.12, 0.3), n).lerp(Color(0.6, 0.76, 0.95), day)
	var low := Color(1.0, 0.44, 0.26).lerp(Color(0.3, 0.16, 0.3), n).lerp(Color(0.8, 0.86, 0.95), day)
	var hor := Color(1.0, 0.66, 0.30).lerp(Color(0.36, 0.2, 0.3), n).lerp(Color(0.92, 0.9, 0.86), day)
	sky_mat.set_shader_parameter("sun_dir", Vector3(-0.45, -0.2, -1.0))
	sky_mat.set_shader_parameter("horizon_y", -0.05)
	sky_mat.set_shader_parameter("zenith_y", 0.24)
	sky_mat.set_shader_parameter("cloud_amount", lerpf(1.0, 0.4, n))
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("mid_color", mid)
	sky_mat.set_shader_parameter("low_color", low)
	sky_mat.set_shader_parameter("horizon_color", hor)
	env.fog_light_color = Color(0.40, 0.25, 0.46).lerp(Color(0.2, 0.16, 0.3), n).lerp(Color(0.85, 0.85, 0.88), day)


func release() -> void:
	if camera and is_instance_valid(camera) and camera.environment == env:
		camera.environment = null
