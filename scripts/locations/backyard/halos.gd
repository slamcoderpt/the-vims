extends RefCounted
## Soft additive glow sprites (one MultiMesh, one draw call) around every
## light: string-light bulbs, lanterns, candles, the fire pit and the lit
## house. Reads as bloom on phones/WebGL where real glow is weak or off.

const SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float strength = 1.0;
varying vec4 tint;
void vertex() {
	// Camera-facing quad at the instance origin, sized by the instance scale.
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = MODEL_MATRIX[3].xyz + (right * VERTEX.x + up * VERTEX.y) * s;
	// Pull towards the camera so the halo is not clipped by its own lamp.
	wp += normalize(INV_VIEW_MATRIX[3].xyz - wp) * s * 0.35;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	tint = COLOR;
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a * (0.55 + 0.45 * a * a);
	ALBEDO = tint.rgb * a * tint.a * strength;
}
"""

var mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _items: Array = []   # [pos, size, color]


func add(pos: Vector3, size: float, col: Color) -> void:
	_items.append([pos, size, col])


func build(parent: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = _items.size()
	for i in _items.size():
		var it: Array = _items[i]
		var t := Transform3D(Basis().scaled(Vector3.ONE * float(it[1])), it[0])
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, it[2])
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Halos"
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Generous AABB: the quads are expanded in the vertex shader.
	mmi.custom_aabb = AABB(Vector3(-40, -5, -60), Vector3(80, 30, 80))
	parent.add_child(mmi)


func set_strength(k: float) -> void:
	if _mat:
		_mat.set_shader_parameter("strength", k)
	if mmi:
		mmi.visible = k > 0.01
