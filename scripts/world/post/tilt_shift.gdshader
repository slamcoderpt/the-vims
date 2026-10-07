shader_type canvas_item;
// Tilt-shift depth of field + colour grade, drawn under the HUD.
// Blur grows towards the top and bottom of the frame around a sharp band.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float focus_y = 0.55;      // 0 top .. 1 bottom (screen uv)
uniform float band = 0.16;         // half height of the sharp band
uniform float falloff = 0.32;      // distance over which blur ramps to max
uniform float blur_px = 7.0;       // max blur radius in pixels (at 1672 px wide)
uniform float top_boost = 1.25;    // the top edge (far away) blurs a bit more
uniform float bottom_boost = 1.0;  // scales the bottom-edge blur (keep the lower floor legible)
uniform float saturation = 1.1;
uniform float contrast = 1.05;
uniform vec3 tint = vec3(1.03, 1.0, 0.95);
uniform vec3 lift = vec3(0.0);
uniform float vignette = 0.22;
uniform float gamma = 1.0;

const vec2 DISC[16] = vec2[16](
	vec2(0.0, 0.0), vec2(0.53, 0.0), vec2(-0.27, 0.46), vec2(-0.27, -0.46),
	vec2(1.0, 0.0), vec2(0.5, 0.87), vec2(-0.5, 0.87), vec2(-1.0, 0.0),
	vec2(-0.5, -0.87), vec2(0.5, -0.87), vec2(0.0, 0.62), vec2(0.0, -0.62),
	vec2(0.72, 0.42), vec2(-0.72, 0.42), vec2(0.72, -0.42), vec2(-0.72, -0.42)
);

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = uv.y - focus_y;
	float amt = smoothstep(band, band + falloff, abs(d));
	if (d < 0.0) {
		amt *= top_boost;
	} else {
		amt *= bottom_boost;
	}
	amt = clamp(amt, 0.0, 1.5);
	vec3 col;
	if (amt > 0.01) {
		vec2 px = SCREEN_PIXEL_SIZE * blur_px * amt * (1.0 / max(SCREEN_PIXEL_SIZE.x * 1672.0, 0.0001));
		float lod = amt * 1.6;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			acc += textureLod(screen_tex, uv + DISC[i] * px, lod).rgb;
		}
		col = acc / 16.0;
	} else {
		col = textureLod(screen_tex, uv, 0.0).rgb;
	}
	// Grade.
	col = pow(max(col, vec3(0.0)), vec3(gamma));
	col = col * tint + lift;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	vec2 vc = uv - 0.5;
	float vig = 1.0 - vignette * smoothstep(0.25, 0.85, dot(vc, vc) * 2.2);
	col *= vig;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
