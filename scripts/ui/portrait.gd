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
uniform float ss = 2.0;
void fragment() {
	// Box-filter downsample of the supersampled render (4 bilinear taps
	// cover ~ss x ss texels): proper AA on voxel edges, no shimmer.
	vec2 o = TEXTURE_PIXEL_SIZE * ss * 0.25;
	vec4 t = (texture(TEXTURE, UV + vec2(-o.x, -o.y)) + texture(TEXTURE, UV + vec2(o.x, -o.y))
		+ texture(TEXTURE, UV + vec2(-o.x, o.y)) + texture(TEXTURE, UV + vec2(o.x, o.y))) * 0.25;
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
	vec3 fg = t.rgb / max(t.a, 0.001);
	// A touch more saturation + contrast so skin stays warm, not chalky.
	float l = dot(fg, vec3(0.299, 0.587, 0.114));
	fg = clamp(mix(vec3(l), fg, 1.18), 0.0, 1.0);
	fg = clamp((fg - 0.5) * 1.06 + 0.5, 0.0, 1.0);
	vec3 c = mix(bg, fg, t.a);
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
var _rim_l: DirectionalLight3D
var _render_frames := 0
## Silhouette bounds in camera-plane coords (from the measure pass) and the
## plane centre / height of the last framing.
var _measured := Rect2()
var _measuring := false
var _plane_c := Vector2.ZERO
var _plane_h := 1.0

## Framing (fractions of the head height neck->top-of-hat), tuned so the face
## fills the card like the refs.
const ADULT_TOP := 0.26
const ADULT_BELOW := 0.56
const KID_TOP := -0.05
const KID_BELOW := 0.16
const PERSON_YAW := -14.0
const PERSON_PITCH := -2.0
const DOG_YAW := -42.0
const DOG_PITCH := -8.0
const DOG_ZOOM := 1.2


func _ready() -> void:
	# Keep finishing pending portrait renders even while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	var k := clampf(px * 3.0, 2.0, 4.0)
	# Cap the render target (~480px tall): plenty for a 140pt card and cheap
	# on phones.
	k = minf(k, 480.0 / maxf(_tex.size.y, 1.0))
	_mat.set_shader_parameter("ss", k)
	var s := (_tex.size * k).round()
	var want := Vector2i(int(s.x), int(s.y))
	if _vp.size != want:
		_vp.size = want
		_request_render()


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(200, 260)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffe9d6")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Studio portrait light: warm key from camera-left and above (gives the
	# face planes shape), a cool soft fill from the right so side faces never
	# go black, and a warm rim from behind that separates hair from backdrop.
	var key := DirectionalLight3D.new()
	key.light_color = Color("ffe6c8")
	key.light_energy = 0.78
	key.rotation_degrees = Vector3(-28, -35, 0)
	_vp.add_child(key)
	_key = key
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("d8e4ff")
	fill.light_energy = 0.32
	fill.rotation_degrees = Vector3(-10, 60, 0)
	_vp.add_child(fill)
	_fill = fill
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("fff1d8")
	rim.light_energy = 0.45
	rim.rotation_degrees = Vector3(-20, 160, 0)
	_vp.add_child(rim)
	_rim_l = rim
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
	# The portrait camera does the 3/4 framing; no presentation swivel.
	if "camera_cheat" in a:
		a.set("camera_cheat", false)
	_vp.add_child(a)
	var dog: bool = member.get("kind", "") == "dog"
	if a.has_method("set_pose"):
		a.set_pose("idle")
	# Let the actor build its meshes and snap into its pose, then freeze it:
	# a portrait is a still (eyes open, no idle sway), rendered on demand.
	for i in 3:
		await get_tree().process_frame
	if not is_instance_valid(a) or a != _actor:
		return
	a.process_mode = Node.PROCESS_MODE_DISABLED
	_neutralize_pose()
	# Measure pass: render once with a wide view, read back the silhouette
	# (alpha) and fit the final framing to what is really there (hair tufts,
	# bunny ears, the dog's ears and tail), so nothing gets clipped.
	_measured = Rect2()
	_measuring = true
	_frame_camera(true)
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(a) or a != _actor:
		return
	_measure_silhouette()
	_measuring = false
	_frame_camera()


## The idle pose sways the head / hips by a per-instance random phase, so a
## frozen frame can catch the head turned away. Square the spine and head up
## (keep only the pitch) so every portrait looks straight down the lens.
func _neutralize_pose() -> void:
	var sk = _actor.get("skeleton")
	if not (sk is Skeleton3D):
		return
	for bn in ["b_hips", "b_torso", "b_head", "b_body"]:
		var v = _actor.get(bn)
		if v == null or int(v) < 0:
			continue
		var i := int(v)
		var e: Vector3 = sk.get_bone_pose_rotation(i).get_euler()
		var keep_pitch := e.x if bn in ["b_head", "b_body"] else 0.0
		sk.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(keep_pitch, 0.0, 0.0)))
	var eb = _actor.get("b_eyes")
	if eb != null and int(eb) >= 0:
		sk.set_bone_pose_scale(int(eb), Vector3.ONE)


func _bone_pos(sk: Skeleton3D, idx: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(idx).origin


func _bone_xf(sk: Skeleton3D, idx: int) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(idx)


## Frame a head-and-shoulders shot (people) or the whole sitting pet at a
## gentle 3/4. Key points of the rig are projected onto the camera plane and
## the ortho camera is fitted around them, so the framing is the same for
## every card size and every look (tall bunny ears included).
func _frame_camera(measure := false) -> void:
	# A resize during the measure pass must keep the wide measure view.
	measure = measure or _measuring
	if _actor == null or not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return
	var dog: bool = member.get("kind", "") == "dog"
	var kid: bool = member.get("kind", "") == "child"
	var aspect := _tex.size.x / maxf(_tex.size.y, 1.0)
	var yaw := deg_to_rad(DOG_YAW if dog else PERSON_YAW) + _actor.global_rotation.y
	var pitch := deg_to_rad(DOG_PITCH if dog else PERSON_PITCH)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var right := Vector3.UP.cross(dir).normalized()
	var up := dir.cross(right).normalized()
	var pts := PackedVector3Array()
	var top_pad := 0.0
	var bot_pad := 0.0
	var side_pad := 0.0
	var sk = _actor.get("skeleton")
	var hb := int(_actor.get("b_head")) if _actor.get("b_head") != null else -1
	var meta = _actor.get("_meta")
	if sk is Skeleton3D and hb >= 0 and meta is Dictionary and not meta.is_empty():
		var s: float = sk.global_transform.basis.get_scale().y
		var vs := 0.05
		var g := _bone_xf(sk, hb)
		var head_h: float = meta.get("head_h", 0.6)
		if dog:
			# Whole sitting dog: paws, rump, tail tip, head top, nose, ears.
			pts.append(_actor.global_position)
			for bn in ["b_body", "b_tail", "b_leg_fl", "b_leg_fr", "b_leg_bl", "b_leg_br", "b_ear_l", "b_ear_r"]:
				var bi = _actor.get(bn)
				if bi != null and int(bi) >= 0:
					pts.append(_bone_pos(sk, int(bi)))
			for cx in [-7.5, 7.5]:
				for cy in [-3.0, 9.0]:
					for cz in [-3.0, 11.0]:
						pts.append(g * (Vector3(cx, cy, cz) * vs))
			var tb = _actor.get("b_tail")
			if tb != null and int(tb) >= 0:
				pts.append(_bone_xf(sk, int(tb)) * (Vector3(0, 6, 0) * vs))
			top_pad = 0.07
			bot_pad = 0.05
			side_pad = 0.05
		else:
			# Head + hat + shoulders: neck row up to the hat top, the
			# head's width, and the chest below the chin.
			var hh := 9.0 if kid else 10.0
			var face := (hh + 1.0) * vs
			pts.append(g * Vector3(0, head_h, 0))
			pts.append(g * Vector3(0, -face * (0.36 if kid else 0.42), 0))
			for sx in [-1.0, 1.0]:
				pts.append(g * Vector3(sx * 6.0 * vs, face * 0.5, 0))
			top_pad = 0.09 if kid else 0.08
			bot_pad = 0.0
			side_pad = 0.02
	else:
		var box := _actor_aabb()
		if box.size == Vector3.ZERO:
			box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
		for i in 8:
			pts.append(box.get_endpoint(i))
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	var origin := pts[0]
	for p in pts:
		var d := p - origin
		var px := d.dot(right)
		var py := d.dot(up)
		minx = minf(minx, px)
		maxx = maxf(maxx, px)
		miny = minf(miny, py)
		maxy = maxf(maxy, py)
	if _measured.size != Vector2.ZERO and not measure:
		if dog:
			minx = _measured.position.x
			maxx = _measured.end.x
			miny = _measured.position.y
			maxy = _measured.end.y
		else:
			# people: real top of hair / hat ears; keep the chest crop line
			maxy = maxf(maxy, _measured.end.y)
	var w := maxx - minx
	var h := maxy - miny
	var view_h := maxf(h * (1.0 + top_pad + bot_pad), w * (1.0 + side_pad * 2.0) / aspect)
	# Centre horizontally; vertically keep the requested top margin and let
	# any extra height fall below (more chest / floor, never empty sky).
	var cy := maxy + h * top_pad - view_h * 0.5
	if dog:
		cy = (maxy + miny) * 0.5 + h * (top_pad - bot_pad) * 0.5
	var cx := (minx + maxx) * 0.5
	if measure:
		view_h *= 1.9
		cy = (maxy + miny) * 0.5 + h * 0.2
	var center := origin + right * cx + up * cy
	_plane_c = Vector2(cx, cy)
	_plane_h = view_h
	_cam.size = view_h
	_cam.global_position = center + dir * 6.0
	_cam.look_at(center, Vector3.UP)
	# Key light follows the camera so every portrait gets the same look.
	_key.rotation = Vector3(deg_to_rad(-28.0), yaw - deg_to_rad(35.0), 0)
	_fill.rotation = Vector3(deg_to_rad(-10.0), yaw + deg_to_rad(60.0), 0)
	_rim_l.rotation = Vector3(deg_to_rad(-20.0), yaw + deg_to_rad(160.0), 0)
	_request_render()


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


## Read the measure render back and store the silhouette's bounds in the
## camera plane (one GPU readback per portrait, at spawn only).
func _measure_silhouette() -> void:
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	var used := img.get_used_rect()
	if OS.has_environment("PORTRAIT_DUMP"):
		img.save_png(OS.get_environment("PORTRAIT_DUMP") + "/meas_%s.png" % member.get("look", ""))
		print("PDUMP measure ", member.get("look"), " used=", used, " img=", img.get_size(), " c=", _plane_c, " h=", _plane_h, " m=", _measured)
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var W := float(img.get_width())
	var H := float(img.get_height())
	var k := _plane_h / H
	var x0 := _plane_c.x + (used.position.x - W * 0.5) * k
	var x1 := _plane_c.x + (used.end.x - W * 0.5) * k
	var y_top := _plane_c.y - (used.position.y - H * 0.5) * k
	var y_bot := _plane_c.y - (used.end.y - H * 0.5) * k
	_measured = Rect2(x0, y_bot, x1 - x0, y_top - y_bot)


## Render the portrait for a few frames after any change (size, framing,
## actor), then stop: a still costs nothing per frame. Several frames, not
## UPDATE_ONCE, because a resize in the same frame can leave a stale
## (stretched) texture on some GL drivers.
func _request_render() -> void:
	if _vp == null:
		return
	_render_frames = 4
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(delta: float) -> void:
	if _render_frames > 0:
		_render_frames -= 1
		if _render_frames == 0:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			if OS.has_environment("PORTRAIT_DUMP"):
				_vp.get_texture().get_image().save_png(OS.get_environment("PORTRAIT_DUMP") + "/final_%s.png" % member.get("look", ""))
				print("PDUMP final ", member.get("look"), " vp=", _vp.size, " c=", _plane_c, " h=", _plane_h, " m=", _measured, " meas=", _measuring)
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
