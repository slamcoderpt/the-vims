extends "res://scripts/ui/tap_area.gd"
## Household portrait card: the member's voxel head rendered live from a
## SimActor in a private SubViewport, inside a white rounded card. The
## selected sim gets a blue rim and a small plumbob gem (ref top-left).

const UI := preload("res://scripts/ui/ui_kit.gd")
const SIM_ACTOR := "res://scripts/world/actors/sim_actor.gd"
const Plumbob := preload("res://scripts/ui/plumbob.gd")
const PORTRAIT_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(100.0, 130.0);
uniform float radius = 9.0;
uniform vec4 bg_top : source_color = vec4(0.98, 0.9, 0.8, 1.0);
uniform vec4 bg_bottom : source_color = vec4(0.9, 0.72, 0.56, 1.0);
uniform float seed = 0.0;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 bg = mix(bg_top.rgb, bg_bottom.rgb, UV.y);
	// soft vignette so the head pops
	float v = 1.0 - 0.18 * length((UV - vec2(0.5, 0.42)) * vec2(1.2, 1.0));
	bg *= v;
	// out-of-focus room behind the sim: a few soft warm bokeh blobs
	vec2 bu = UV * vec2(rect_size.x / rect_size.y, 1.0);
	float asp = rect_size.x / rect_size.y;
	bg += vec3(1.0, 0.93, 0.8) * 0.16 * smoothstep(0.2, 0.0, length(bu - vec2(0.12 * asp, 0.2 + seed * 0.2)));
	bg += vec3(1.0, 0.97, 0.9) * 0.12 * smoothstep(0.26, 0.0, length(bu - vec2(0.92 * asp, 0.14 + seed * 0.1)));
	bg -= vec3(0.06, 0.05, 0.03) * smoothstep(0.3, 0.0, length(bu - vec2(0.85 * asp, 0.8 - seed * 0.2)));
	vec3 c = mix(bg, t.rgb / max(t.a, 0.001), t.a);
	vec2 p = (UV - 0.5) * rect_size;
	vec2 q = abs(p) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = clamp(0.5 - d, 0.0, 1.0);
	COLOR = vec4(c, a);
}
"""

## Portrait backdrop gradients per look (top, bottom), like the soft room
## blur behind each head in the refs.
const BG_TINTS := {
	"dad": [Color("fbe6cf"), Color("e3b48c")],
	"bunny_girl": [Color("fde8ee"), Color("efc0cc")],
	"cat_girl": [Color("e9e6fb"), Color("c3c2ea")],
	"beagle": [Color("eef2f8"), Color("cfd9e6")],
	"default": [Color("fde9d2"), Color("e9b993")],
}

static var _shader: Shader

var index := 0
var member: Dictionary = {}
var selected := false
var _vp: SubViewport
var _cam: Camera3D
var _actor: Node3D
var _tex: TextureRect
var _mat: ShaderMaterial
var _rim: StyleBoxFlat
var _card: StyleBoxFlat
var _refresh_t := 0.0
var _gem_phase := 0.0
var _gem: Control
var _inner: StyleBoxFlat
var _key: DirectionalLight3D
var _fill: DirectionalLight3D

## Framing (fractions of the head height neck->top-of-hat), tuned so the face
## fills the card like the refs.
const ADULT_TOP := 0.26
const ADULT_BELOW := 0.56
const KID_TOP := -0.05
const KID_BELOW := 0.16
const PERSON_YAW := -14.0
const PERSON_PITCH := -2.0
const DOG_YAW := -40.0
const DOG_PITCH := -8.0
const DOG_ZOOM := 1.2


func _ready() -> void:
	_card = UI.card_style(14, UI.WHITE, 8)
	_rim = UI.card_style(15, UI.BLUE, 10)
	_rim.shadow_color = Color(0.15, 0.4, 0.9, 0.35)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PORTRAIT_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.material = _mat
	add_child(_tex)
	_inner = UI.card_style(12, UI.WHITE, 0)
	_gem = Control.new()
	_gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gem.draw.connect(_draw_gem)
	add_child(_gem)
	_build_viewport()
	_layout()


func setup(i: int, m: Dictionary, sel: bool, card_size: Vector2) -> void:
	index = i
	selected = sel
	var look_changed: bool = member.get("look", "") != m.get("look", "")
	member = m
	custom_minimum_size = card_size
	size = card_size
	hit_pad = Vector4(4, 6, 4, 6)
	if is_inside_tree():
		_layout()
		if look_changed:
			_spawn_actor()
	queue_redraw()


func _layout() -> void:
	if _tex == null:
		return
	_gem.size = size
	var inset := 6.0 if selected else 5.0
	_tex.position = Vector2(inset, inset)
	_tex.size = size - Vector2(inset, inset) * 2.0
	_mat.set_shader_parameter("rect_size", _tex.size)
	_mat.set_shader_parameter("radius", 9.0)
	var bg: Array = BG_TINTS.get(member.get("look", ""), BG_TINTS["default"])
	_mat.set_shader_parameter("bg_top", bg[0])
	_mat.set_shader_parameter("bg_bottom", bg[1])
	_mat.set_shader_parameter("seed", float(index % 4) * 0.33)
	if _vp:
		_resize_viewport()
		_frame_camera()


## Supersample: render at 2x the on-screen pixel size of the card so the
## voxel edges stay crisp after the (bilinear) downscale on any screen.
func _resize_viewport() -> void:
	var px := 1.0
	if is_inside_tree():
		px = get_global_transform_with_canvas().get_scale().y * get_viewport().get_final_transform().get_scale().y
	var k := clampf(px * 2.0, 2.0, 4.0)
	var s := (_tex.size * k).round()
	var want := Vector2i(int(s.x), int(s.y))
	if _vp.size != want:
		_vp.size = want


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.size = Vector2i(200, 260)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff3e6")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Warm key from camera-left and above, cool soft fill from the right, a
	# rim from behind: a studio portrait light that keeps the face bright.
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff0dc")
	key.light_energy = 0.85
	key.rotation_degrees = Vector3(-24, -24, 0)
	_vp.add_child(key)
	_key = key
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("dfe8ff")
	fill.light_energy = 0.3
	fill.rotation_degrees = Vector3(-8, 40, 0)
	_vp.add_child(fill)
	_fill = fill
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.05
	_cam.far = 50.0
	_vp.add_child(_cam)
	_cam.current = true
	_tex.texture = _vp.get_texture()
	_spawn_actor()


func _spawn_actor() -> void:
	if _actor:
		_actor.queue_free()
		_actor = null
	var look: String = member.get("look", "")
	if look == "" or not ResourceLoader.exists(SIM_ACTOR):
		return
	var script: Script = load(SIM_ACTOR)
	if script == null or not script.can_instantiate():
		return
	var a: Node3D = script.create(look)
	_actor = a
	a.name = "PortraitActor"
	_vp.add_child(a)
	if a.has_method("set_pose"):
		a.set_pose("idle")
	# Let the actor build its meshes and snap into its pose, then freeze it:
	# a portrait is a still (eyes open, no idle sway), rendered on demand.
	for i in 3:
		await get_tree().process_frame
	if not is_instance_valid(a) or a != _actor:
		return
	a.process_mode = Node.PROCESS_MODE_DISABLED
	_frame_camera()


func _bone_pos(sk: Skeleton3D, idx: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(idx).origin


## Frame a head-and-shoulders shot (people) or the whole pet, front-on at eye
## level. Prefers the actor's optional portrait_focus() -> [center, view_h].
func _frame_camera() -> void:
	if _actor == null or not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return
	var dog: bool = member.get("kind", "") == "dog"
	var kid: bool = member.get("kind", "") == "child"
	var center := Vector3.ZERO
	var view_h := 0.0
	var aspect := _tex.size.x / maxf(_tex.size.y, 1.0)
	var sk = _actor.get("skeleton")
	var hb := int(_actor.get("b_head")) if _actor.get("b_head") != null else -1
	if _actor.has_method("portrait_focus"):
		var f: Array = _actor.portrait_focus()
		center = f[0]
		view_h = f[1]
	elif sk is Skeleton3D and hb >= 0 and _actor.has_method("head_top"):
		var neck := _bone_pos(sk, hb)
		var top: Vector3 = _actor.head_top()
		if dog:
			var base := _actor.global_position
			var hh := top.y - base.y
			var body_i := int(_actor.get("b_body"))
			var body := _bone_pos(sk, body_i) if body_i >= 0 else base
			var mid := (body + neck) * 0.5
			center = Vector3(mid.x, base.y + hh * 0.46, mid.z)
			view_h = hh * DOG_ZOOM
		else:
			var hh := top.y - neck.y
			var eyes_i := int(_actor.get("b_eyes"))
			var eyes := _bone_pos(sk, eyes_i) if eyes_i >= 0 else neck + Vector3(0, hh * 0.4, 0)
			var y1 := top.y + hh * (KID_TOP if kid else ADULT_TOP)
			var y0 := neck.y - hh * (KID_BELOW if kid else ADULT_BELOW)
			center = Vector3(eyes.x, (y0 + y1) * 0.5, eyes.z)
			view_h = y1 - y0
	else:
		var box := _actor_aabb()
		if box.size == Vector3.ZERO:
			box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
		var h := box.size.y
		if dog:
			center = box.get_center()
			view_h = maxf(h, maxf(box.size.x, box.size.z) * 0.8) * 1.05
		else:
			view_h = h * 0.5
			center = Vector3(box.get_center().x, box.end.y - view_h * 0.5, box.get_center().z)
	var yaw := deg_to_rad(DOG_YAW if dog else PERSON_YAW) + _actor.global_rotation.y
	var pitch := deg_to_rad(DOG_PITCH if dog else PERSON_PITCH)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	_cam.size = view_h
	_cam.global_position = center + dir * 6.0
	_cam.look_at(center, Vector3.UP)
	# Key light follows the camera so every portrait gets the same look.
	_key.rotation = Vector3(deg_to_rad(-26.0), yaw - deg_to_rad(30.0), 0)
	_fill.rotation = Vector3(deg_to_rad(-6.0), yaw + deg_to_rad(55.0), 0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _actor_aabb() -> AABB:
	var out := AABB()
	var first := true
	var inv := _actor.global_transform.affine_inverse()
	for n in _actor.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var b: AABB = (inv * vi.global_transform) * vi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return _actor.global_transform * out if not first else AABB()


func _process(delta: float) -> void:
	if selected:
		_gem_phase += delta
		_gem.queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if selected:
		draw_style_box(_rim, r.grow(1.0))
		draw_style_box(_inner, r.grow(-3.0))
	else:
		draw_style_box(_card, r)


func _draw_gem() -> void:
	if selected:
		Plumbob.draw_gem(_gem, Vector2(size.x - 14.0, 17.0), 8.0, 13.0, _gem_phase * 1.6)
