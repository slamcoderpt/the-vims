extends CanvasLayer
## Screen-space post for the GL Compatibility renderer (phones / WebGL2):
## tilt-shift blur (top & bottom of frame) + colour grade + vignette.
## Sits on canvas layer 1, under the HUD (layer 10), so UI stays sharp.
## lighting.gd owns it and feeds it per time-of-day / per-location settings.

const SHADER := preload("res://scripts/world/post/tilt_shift.gdshader")

var rect: ColorRect
var mat: ShaderMaterial


func _init() -> void:
	layer = 1
	name = "PostFX"
	rect = ColorRect.new()
	rect.name = "TiltShift"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)


## Keys: focus_y, band, falloff, blur_px, top_boost, saturation, contrast,
## tint (Vector3/Color), lift, vignette, gamma, enabled.
func configure(p: Dictionary) -> void:
	rect.visible = p.get("enabled", true)
	for k in ["focus_y", "band", "falloff", "blur_px", "top_boost", "bottom_boost", "saturation", "contrast", "vignette", "gamma"]:
		if p.has(k):
			mat.set_shader_parameter(k, float(p[k]))
	for k in ["tint", "lift"]:
		if p.has(k):
			var v = p[k]
			if v is Color:
				v = Vector3(v.r, v.g, v.b)
			mat.set_shader_parameter(k, v)
