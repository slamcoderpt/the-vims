extends "res://scripts/ui/tap_area.gd"
## Household portrait card: the member's voxel head rendered live from a
## SimActor in a private SubViewport, inside a white rounded card. The
## selected sim gets a blue rim and a small plumbob gem (ref top-left).

const UI := preload("res://scripts/ui/ui_kit.gd")
const SIM_ACTOR := "res://scripts/world/actors/sim_actor.gd"
const Plumbob := preload("res://scripts/ui/plumbob.gd")
const Bust := preload("res://scripts/ui/portrait_bust.gd")
const PORTRAIT_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(100.0, 130.0);
uniform float radius = 9.0;
uniform vec4 bg_top : source_color = vec4(0.98, 0.9, 0.8, 1.0);
uniform vec4 bg_bottom : source_color = vec4(0.9, 0.72, 0.56, 1.0);
uniform float seed = 0.0;
uniform float ss = 2.0;
uniform float smooth_px = 0.0;
uniform float smooth_sigma = 0.14;
void fragment() {
	// Box-filter downsample of the supersampled render (4 bilinear taps
	// cover ~ss x ss texels): proper AA on voxel edges, no shimmer.
	vec2 o = TEXTURE_PIXEL_SIZE * ss * 0.25;
	vec4 t = (texture(TEXTURE, UV + vec2(-o.x, -o.y)) + texture(TEXTURE, UV + vec2(o.x, -o.y))
		+ texture(TEXTURE, UV + vec2(-o.x, o.y)) + texture(TEXTURE, UV + vec2(o.x, o.y))) * 0.25;
	// Edge-preserving smooth at one-voxel spacing: neighbouring voxels of
	// nearly the same colour (the per-voxel jitter on hats / hair) blend
	// into clean flat planes like the ref cards, while real edges (eyes,
	// mouth, hair line, plaid) are kept crisp by the colour weight.
	if (t.a > 0.5 && smooth_px > 0.0) {
		vec3 c0 = t.rgb / t.a;
		vec3 acc = c0;
		float wsum = 1.0;
		vec2 st = TEXTURE_PIXEL_SIZE * smooth_px;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				if (i == 0 && j == 0) continue;
				vec4 s = texture(TEXTURE, UV + vec2(float(i), float(j)) * st);
				if (s.a < 0.9) continue;
				vec3 cs = s.rgb / s.a;
				vec3 d = cs - c0;
				float w = exp(-dot(d, d) / (smooth_sigma * smooth_sigma)) * (abs(i) + abs(j) == 2 ? 0.6 : 1.0);
				acc += cs * w;
				wsum += w;
			}
		}
		t.rgb = acc / wsum * t.a;
	}
	vec3 bg = mix(bg_top.rgb, bg_bottom.rgb, UV.y);
	// soft vignette so the head pops
	float v = 1.0 - 0.1 * length((UV - vec2(0.5, 0.42)) * vec2(1.2, 1.0));
	bg *= v;
	// out-of-focus room behind the sim: a few soft warm bokeh blobs
	vec2 bu = UV * vec2(rect_size.x / rect_size.y, 1.0);
	float asp = rect_size.x / rect_size.y;
	bg += vec3(1.0, 0.93, 0.8) * 0.16 * smoothstep(0.2, 0.0, length(bu - vec2(0.12 * asp, 0.2 + seed * 0.2)));
	bg += vec3(1.0, 0.97, 0.9) * 0.12 * smoothstep(0.26, 0.0, length(bu - vec2(0.92 * asp, 0.14 + seed * 0.1)));
	bg -= vec3(0.06, 0.05, 0.03) * smoothstep(0.3, 0.0, length(bu - vec2(0.85 * asp, 0.8 - seed * 0.2)));
	// Soft drop shadow of the bust on the backdrop (down-right, 4 taps) so
	// the silhouette separates from the backdrop like a studio photo.
	vec2 so = vec2(0.035, 0.025);
	vec2 sb = vec2(0.02, 0.016);
	float sh = (texture(TEXTURE, UV - so + vec2(sb.x, sb.y)).a + texture(TEXTURE, UV - so - vec2(sb.x, sb.y))
		.a + texture(TEXTURE, UV - so + vec2(-sb.x, sb.y)).a + texture(TEXTURE, UV - so + vec2(sb.x, -sb.y)).a) * 0.25;
	bg *= 1.0 - 0.2 * sh;
	vec3 fg = t.rgb / max(t.a, 0.001);
	// A touch more saturation + contrast so skin stays warm, not chalky.
	float l = dot(fg, vec3(0.299, 0.587, 0.114));
	// Vibrance: lift dull tones (skin, hair) so faces stay warm, but calm
	// already-loud ones (plaid red, hat pastels) so nothing looks garish.
	float sat = max(fg.r, max(fg.g, fg.b)) - min(fg.r, min(fg.g, fg.b));
	fg = clamp(mix(vec3(l), fg, mix(1.14, 0.9, smoothstep(0.35, 0.8, sat))), 0.0, 1.0);
	fg = clamp((fg - 0.5) * 1.08 + 0.5, 0.0, 1.0);
	// Soft studio key from the upper left: a gentle falloff across the bust.
	fg *= mix(1.07, 0.96, clamp(dot(UV, vec2(0.4, 0.6)), 0.0, 1.0));
	// Studio falloff below the chin: shirt and shoulders sink a little so
	// the face is the brightest, most contrasty part of the card.
	fg *= 1.0 - 0.07 * smoothstep(0.7, 1.0, UV.y);
	vec3 c = mix(bg, fg, t.a);
	vec2 p = (UV - 0.5) * rect_size;
	vec2 q = abs(p) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = clamp(0.5 - d, 0.0, 1.0);
	COLOR = vec4(c, a);
}
"""

## Studio bust material: the sim's own vertex colours (AO baked in), lit by
## a fixed soft front key in view space instead of the scene lights. Faces
## pointing at the lens get full, even light; tops a touch brighter, sides a
## gentle step darker, so the voxels read as clean pixel-art blocks (ref cards)
## instead of muddy angled shading.
const BUST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform float side_shade = 0.8;
uniform float top_lift = 1.06;
uniform float bottom_shade = 0.62;
uniform float gain = 1.04;
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = c;
	if (!OUTPUT_IS_SRGB) {
		lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	}
	vec3 n = normalize(NORMAL);
	float front = clamp(n.z, 0.0, 1.0);
	float up = clamp(n.y, 0.0, 1.0);
	float down = clamp(-n.y, 0.0, 1.0);
	float side = abs(n.x);
	float k = front + up * top_lift + down * bottom_shade + side * side_shade;
	k /= max(front + up + down + side, 0.001);
	ALBEDO = lin * k * gain;
}
"""

## Studio light for the dedicated portrait busts: vertex colours (AO and
## block shading baked in) lit by a soft warm key from upper-left of the
## lens, a cool fill so the turned-away side never goes muddy and a warm rim
## on the right-hand edges that separates hair from the backdrop.
const STUDIO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec3 key_dir = vec3(-0.42, 0.5, 0.76);
uniform float ambient = 0.72;
uniform float key = 0.4;
uniform float rim = 0.16;
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 lin = c;
	if (!OUTPUT_IS_SRGB) {
		lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	}
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float k = ambient + key * max(dot(n, normalize(key_dir)), 0.0);
	k += 0.06 * max(n.y, 0.0);
	vec3 col = lin * k * vec3(1.04, 1.0, 0.97);
	col += lin * vec3(1.0, 0.85, 0.6) * rim * max(n.x, 0.0);
	ALBEDO = col;
}
"""

## Portrait backdrop gradients per look (top, bottom), like the soft room
## blur behind each head in the refs.
const BG_TINTS := {
	"dad": [Color("f4ece0"), Color("d9c8b2")],
	"bunny_girl": [Color("f1e6f0"), Color("d6c2da")],
	"cat_girl": [Color("e2ebf8"), Color("b4c6e6")],
	"beagle": [Color("e8f0f8"), Color("bccde2")],
	"default": [Color("f4ece0"), Color("d9c8b2")],
}

static var _shader: Shader
static var _bust_mat: ShaderMaterial
static var _studio_mat: ShaderMaterial

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
## Dedicated high-detail bust (portrait_bust.gd) when the look is known.
var _bust: Dictionary = {}
var _bust_mi: MeshInstance3D
## Silhouette bounds in camera-plane coords (from the measure pass) and the
## plane centre / height of the last framing.
var _measured := Rect2()
## Measured left/right of the head (hair / hat) in the camera plane, and
## the plane-y band (chin, skull top) it was measured in.
var _head_span := Vector2.ZERO
var _head_band := Vector2.ZERO
var _measuring := false
var _plane_c := Vector2.ZERO
var _plane_h := 1.0

## Framing (fractions of the head height neck->top-of-hat), tuned so the face
## fills the card like the refs.
const PERSON_YAW := -8.0
const PERSON_PITCH := -5.0
const DOG_YAW := -34.0
const DOG_PITCH := -6.0
const DOG_HEAD_YAW := -22.0
## Sitting tilts the body back; the head pitches forward to level out.
const DOG_HEAD_PITCH := -4.0
const W_FRAC_ADULT := 0.84
const W_FRAC_KID := 0.92
const CHIN_ADULT := 0.72
const CHIN_KID := 0.87
const W_FRAC_DOG := 0.78
const CHIN_DOG := 0.64


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
	# Integer factor so the box downsample maps whole render pixels to each
	# screen pixel (crisp voxel edges).
	k = maxf(floorf(k), 1.0)
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
	# The bust material is unshaded: keep the tonemap linear so the sims'
	# authored colours come through as-is (no filmic wash).
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
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
	if _bust_mi:
		_bust_mi.queue_free()
		_bust_mi = null
	_bust = {}
	var look: String = member.get("look", "")
	if look == "":
		return
	var bd: Dictionary = Bust.build(look)
	if not bd.is_empty():
		_spawn_bust(bd)
		return
	if not ResourceLoader.exists(SIM_ACTOR):
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
	_apply_bust_material(a)
	var dog: bool = member.get("kind", "") == "dog"
	if a.has_method("set_pose"):
		# Pet card: sitting up, chest out, like a pet photo.
		a.set_pose("sit" if dog else "idle")
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
	_head_span = Vector2.ZERO
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


func _spawn_bust(bd: Dictionary) -> void:
	_bust = bd
	if _studio_mat == null:
		var sh := Shader.new()
		sh.code = STUDIO_SHADER
		_studio_mat = ShaderMaterial.new()
		_studio_mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "PortraitBust"
	mi.mesh = bd.mesh
	mi.material_override = _studio_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(bd.pitch, bd.yaw, 0.0)
	_vp.add_child(mi)
	_bust_mi = mi
	_frame_camera()


## Bust framing: the card window comes from portrait_bust.gd (voxel units,
## measured against the ref cards); the width follows the card aspect.
func _frame_bust() -> void:
	var vs: float = Bust.VS
	var fr: Rect2 = _bust.frame
	var yaw := deg_to_rad(float(_bust.yaw))
	# The face plane (z ~ 6) swings right with the yaw: follow it halfway so
	# the face, not the back of the head, sits mid-card.
	var cx := fr.position.x + 5.0 * sin(yaw)
	var cy := fr.position.y + fr.size.y * 0.5
	var view_h := fr.size.y * vs
	_plane_h = view_h
	_cam.size = view_h
	_cam.transform = Transform3D(Basis(), Vector3(cx * vs, cy * vs, 6.0))
	_mat.set_shader_parameter("smooth_px", 0.0)
	_request_render()


func _apply_bust_material(a: Node3D) -> void:
	if _bust_mat == null:
		var sh := Shader.new()
		sh.code = BUST_SHADER
		_bust_mat = ShaderMaterial.new()
		_bust_mat.shader = sh
	for n in a.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).material_override = _bust_mat
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
		var keep_pitch := e.x if bn == "b_body" else 0.0
		sk.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(keep_pitch, 0.0, 0.0)))
	if member.get("kind", "") == "dog":
		# Pet card (ref): body in 3/4 profile, head turned to the lens.
		var hb = _actor.get("b_head")
		if hb != null and int(hb) >= 0:
			# Level head in skeleton space (the sitting body tilts back):
			# undo the parent's rotation, then yaw toward the lens.
			var par: int = sk.get_bone_parent(int(hb))
			var pb: Basis = sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
			var want := Basis(Vector3.UP, deg_to_rad(DOG_HEAD_YAW)) * Basis(Vector3.RIGHT, deg_to_rad(DOG_HEAD_PITCH))
			sk.set_bone_pose_rotation(int(hb), (pb.inverse() * want).get_rotation_quaternion())
		# Close-up pet card: tuck the tail away so the head reads alone.
		var tb = _actor.get("b_tail")
		if tb != null and int(tb) >= 0:
			sk.set_bone_pose_scale(int(tb), Vector3.ONE * 0.001)
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
	if _bust_mi != null and not _bust.is_empty():
		_frame_bust()
		return
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
	var sk = _actor.get("skeleton")
	var hb := int(_actor.get("b_head")) if _actor.get("b_head") != null else -1
	var meta = _actor.get("_meta")
	var cx := 0.0
	var cy := 0.0
	var view_h := 1.0
	var origin := _actor.global_position
	# Voxel grid in the camera plane (front busts only): size of one voxel
	# and where a grid corner lands, for pixel-exact framing.
	var snap_unit := 0.0
	var snap_o := Vector2.ZERO
	if sk is Skeleton3D and hb >= 0 and meta is Dictionary and not meta.is_empty():
		# Head-and-shoulders close-up: the head (hair included) fills ~62% of
		# the card width, a small margin over the hair / hat, chin at ~62%
		# of the height and the shoulders below, like the ref cards.
		var vs := 0.05
		var g := _bone_xf(sk, hb)
		var hh := 9.0 if kid else 10.0
		# Head-bone local extents (voxels): people's heads sit on the neck
		# joint; the beagle's head bone is mid-skull with the floppy ears
		# hanging to the jaw (sim_rig_builder _build_dog).
		var y_mid := 1.0 + hh * 0.5
		var y_top := hh + 2.0
		var y_chin := 0.5
		var half_w := 6.2
		var z_face := 0.0
		if dog:
			hh = 10.0
			y_mid = 3.0
			y_top = 8.5
			y_chin = -2.5
			half_w = 7.2
			z_face = 9.0
		origin = g * Vector3(0, meta.get("head_h", 0.6), 0)
		var pr := func(v: Vector3) -> Vector2:
			var d: Vector3 = g * (v * vs) - origin
			return Vector2(d.dot(right), d.dot(up))
		var mid: Vector2 = pr.call(Vector3(0, y_mid, z_face))
		snap_o = pr.call(Vector3.ZERO)
		snap_unit = absf((pr.call(Vector3(1, 0, 0)) as Vector2).x - snap_o.x)
		var l: Vector2 = pr.call(Vector3(-half_w, y_mid, 0))
		var r: Vector2 = pr.call(Vector3(half_w, y_mid, 0))
		var head_w := absf(r.x - l.x)
		var skull_top: float = pr.call(Vector3(0, y_top, 0)).y
		var chin: float = pr.call(Vector3(0, y_chin, 0)).y
		# Dog: measure the head above the muzzle only (its back sits behind
		# the jaw at a 3/4 view and would widen the band).
		_head_band = Vector2(mid.y if dog else chin, skull_top)
		cx = mid.x
		if _head_span != Vector2.ZERO and not measure:
			# The real head width from the measure render (hair tufts, hat
			# brim): robust to look / model changes.
			head_w = _head_span.y - _head_span.x
			# Centre between the silhouette and the face itself, so at 3/4 the
			# face (not the back of the hair) sits mid-card like the refs.
			cx = lerpf((_head_span.x + _head_span.y) * 0.5, mid.x, 0.5)
			head_w = maxf(head_w, 2.0 * maxf(cx - _head_span.x, _head_span.y - cx) * 0.94)
		var unit := absf(skull_top - chin) / (hh + 1.5)
		# Hat ears may rise ~6 voxels above the skull; taller tips get cropped
		# by the frame edge (like the ref bunny ears) instead of shrinking
		# the face.
		var top := skull_top + unit * (17.0 if kid else (1.0 if dog else 5.0))
		if _measured.size != Vector2.ZERO and not measure:
			top = minf(_measured.end.y, top)
			top = maxf(top, skull_top)
		# Head-and-shoulders bust like the ref cards: the head (hair / hat
		# included) at ~60% of the card width, the whole hat with its ears
		# inside the frame, chin a little below mid-card so the collar and
		# shoulders of the shirt read underneath.
		# Fit by height (hair / hat top near the card top, chin about 2/3
		# down so collar and shoulders show), then widen only if the head
		# would overflow the card sideways.
		var w_frac := W_FRAC_KID if kid else (W_FRAC_DOG if dog else W_FRAC_ADULT)
		var top_m := 0.03 if kid else (0.12 if dog else 0.05)
		var chin_frac := CHIN_KID if kid else (CHIN_DOG if dog else CHIN_ADULT)
		view_h = maxf((top - chin) / (chin_frac - top_m), head_w / w_frac / aspect)
		cy = top + view_h * top_m - view_h * 0.5
		if measure:
			view_h *= 2.2
			cy = (top + chin) * 0.5
	else:
		var pts := PackedVector3Array()
		var box := _actor_aabb()
		if box.size == Vector3.ZERO:
			box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
		for i in 8:
			pts.append(box.get_endpoint(i))
		origin = pts[0]
		var minx := INF
		var maxx := -INF
		var miny := INF
		var maxy := -INF
		for p in pts:
			var d := p - origin
			minx = minf(minx, d.dot(right))
			maxx = maxf(maxx, d.dot(right))
			miny = minf(miny, d.dot(up))
			maxy = maxf(maxy, d.dot(up))
		if _measured.size != Vector2.ZERO and not measure:
			minx = _measured.position.x
			maxx = _measured.end.x
			miny = _measured.position.y
			maxy = _measured.end.y
		cx = (minx + maxx) * 0.5
		var w := maxx - minx
		var h := maxy - miny
		view_h = maxf(h * (1.16 if dog else 1.14), w * (1.06 if dog else 1.12) / aspect)
		if dog:
			# Pet card: let the tail tip run off the left edge, head centred.
			cx += w * 0.02
		cy = (maxy + miny) * 0.5 + h * (0.06 if dog else 0.01)
		if measure:
			view_h *= 1.9
	if snap_unit > 0.0 and not measure and absf(PERSON_YAW) < 0.01 and absf(PERSON_PITCH) < 0.01:
		# Pixel-exact bust: an integer number of render pixels per voxel and
		# voxel corners on pixel boundaries, so after the integer
		# supersample downscale every block edge is crisp (pixel-art cards
		# like the refs, no smeared half-texel seams).
		var W := float(_vp.size.x)
		var H := float(_vp.size.y)
		var n := maxf(roundf(H * snap_unit / view_h), 1.0)
		var px := snap_unit / n
		view_h = H * px
		cx = snap_o.x + (roundf((cx - snap_o.x) / px - W * 0.5) + W * 0.5) * px
		cy = snap_o.y + (roundf((cy - snap_o.y) / px + H * 0.5) - H * 0.5) * px
	var center := origin + right * cx + up * cy
	_plane_c = Vector2(cx, cy)
	_plane_h = view_h
	_cam.size = view_h
	# One voxel in render pixels, for the edge-preserving smooth.
	var vox := 0.05
	if sk is Skeleton3D:
		vox *= (sk as Skeleton3D).global_transform.basis.get_scale().y
	_mat.set_shader_parameter("smooth_px", 0.0 if measure else vox / view_h * float(_vp.size.y))
	_cam.global_position = center + dir * 6.0
	_cam.look_at(center, Vector3.UP)
	# Soft front key from just above-left of the lens (faces read evenly,
	# like a studio portrait), a cool fill and a warm rim on the hair.
	_key.rotation = Vector3(deg_to_rad(-22.0), yaw - deg_to_rad(22.0), 0)
	_fill.rotation = Vector3(deg_to_rad(-8.0), yaw + deg_to_rad(55.0), 0)
	_rim_l.rotation = Vector3(deg_to_rad(-25.0), yaw + deg_to_rad(165.0), 0)
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
	if _head_band != Vector2.ZERO:
		# Widest row of the head between eye level and the skull top (above
		# beard and shoulders): that is what must fit the card.
		var ya := _head_band.x + (_head_band.y - _head_band.x) * 0.05
		var yb := _head_band.y
		var r0 := int(clampf(H * 0.5 - (yb - _plane_c.y) / k, 0.0, H - 1.0))
		var r1 := int(clampf(H * 0.5 - (ya - _plane_c.y) / k, 0.0, H - 1.0))
		var lo := INF
		var hi := -INF
		for yy in range(r0, r1 + 1, 2):
			for xx in range(used.position.x, used.end.x):
				if img.get_pixel(xx, yy).a > 0.5:
					lo = minf(lo, xx)
					break
			for xx in range(used.end.x - 1, used.position.x - 1, -1):
				if img.get_pixel(xx, yy).a > 0.5:
					hi = maxf(hi, xx + 1)
					break
		if hi > lo:
			_head_span = Vector2(_plane_c.x + (lo - W * 0.5) * k, _plane_c.x + (hi - W * 0.5) * k)


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
