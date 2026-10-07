class_name SimActor
extends Node3D
## A voxel person or pet.
## Contract used by locations and gameplay (keep these signatures stable):
##   SimActor.create(look: String) -> SimActor     looks: "dad", "bunny_girl", "cat_girl", "beagle", "npc_0".."npc_7"
##   set_pose(pose: String)       "idle", "walk", "sit", "sit_floor", "lie", "sleep", "type", "paint", "read", "talk", "wave", "grill", "brush_teeth", "play"
##   walk_to(world_pos: Vector3) -> void (emits arrived)
##   face(world_pos: Vector3)
##   head_top() -> Vector3       world position above the head, where bubbles anchor
##
## Extra (additive) API:
##   kind() -> "adult" | "child" | "dog"
##   seat_height       metres; hip rests here for seated poses (chair seat top). Default 0.45.
##   lie_height        metres; mattress top for "lie"/"sleep". Default 0.5.
##   Poses also accept "sit_<pose>" (e.g. "sit_paint", "sit_talk", "sit_read")
##   and "stand_<pose>" (e.g. "stand_read", "stand_type") to force seated/standing.
##   "type" and "read" are seated by default; the rest stand.
##   lie/sleep: place the actor at the middle of the mattress; the head points
##   along the actor's local -Z (use face() towards the foot end).
##   Dog poses: idle, walk, sit, lie, sleep, play (belly down facing the
##   camera in 3/4, head up, chew bone between the front paws), chew (lying
##   side-on gnawing the bone), bow (play bow), talk (bark);
##   anything else falls back to idle.
##
## Rendering: every body part is its own voxel model on its own bone; the parts
## are merged into ONE rigidly skinned mesh per look (shared across instances),
## so each character is a single draw call (+1 while holding a prop).

signal arrived

const RigBuilder := preload("res://scripts/world/actors/sim_rig_builder.gd")

var look := "dad"
var pose := "idle"
var seat_height := 0.45
var lie_height := 0.5
## Walking speed in m/s (set automatically from the body type).
var walk_speed := 1.3
## Display scale of the voxel body (<= 0: automatic per body type). Chibi
## characters read better slightly larger than life next to furniture.
var body_scale := -1.0:
	set(v):
		body_scale = v
		_apply_scale()
## When true, seated/activity poses "cheat" toward the active camera (Sims
## style): the body swivels and the head turns so faces read in 3/4 even when
## the sim works facing away from the player.
var camera_cheat := true

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var _rig: Dictionary
var _meta: Dictionary
var _dog := false
var _nb := 0
var _rests := PackedVector3Array()
var _cur := PackedVector3Array()   # current euler per bone
var _tgt := PackedVector3Array()   # target euler per bone
var _cur_pos := Vector3.ZERO       # hips/body offset (current)
var _tgt_pos := Vector3.ZERO
var _root_rot := Vector3.ZERO
var _tgt_root_rot := Vector3.ZERO
var _root_pos := Vector3.ZERO
var _tgt_root_pos := Vector3.ZERO
var _t := 0.0
var _phase := 0.0
var _walk_phase := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _eyes_closed := false
var _walking := false
var _walk_target := Vector3.ZERO
var _pose_after_walk := "idle"
var _props := {}       # name -> MeshInstance3D
var _attach := {}      # bone name -> BoneAttachment3D
var _frames := 0
var _s := 1.0          # resolved body scale
var _cam_a := 0.0      # signed yaw (rad) from the actor's forward to the camera
var _brush_left := false  # paint: brush held in the left hand (camera on the right)

# Bone indices (humans).
var b_root := -1
var b_hips := -1
var b_torso := -1
var b_head := -1
var b_eyes := -1
var b_arm_l := -1
var b_fore_l := -1
var b_arm_r := -1
var b_fore_r := -1
var b_thigh_l := -1
var b_shin_l := -1
var b_thigh_r := -1
var b_shin_r := -1
var b_ear_l := -1
var b_ear_r := -1
# Dog.
var b_body := -1
var b_tail := -1
var b_leg_fl := -1
var b_leg_fr := -1
var b_leg_bl := -1
var b_leg_br := -1


static func create(look_name: String) -> SimActor:
	var a := SimActor.new()
	a.look = look_name
	a.name = look_name.capitalize().replace(" ", "")
	return a


func _ready() -> void:
	_rig = RigBuilder.get_rig(look)
	_meta = _rig.meta
	_dog = _meta.species == "dog"
	var names: Array[String] = _rig.names
	var parents: PackedInt32Array = _rig.parents
	_rests = _rig.rests
	_nb = names.size()
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	for i in _nb:
		skeleton.add_bone(names[i])
	for i in _nb:
		if parents[i] >= 0:
			skeleton.set_bone_parent(i, parents[i])
		skeleton.set_bone_rest(i, Transform3D(Basis(), _rests[i]))
		skeleton.set_bone_pose_position(i, _rests[i])
	add_child(skeleton)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = _rig.mesh
	mesh_instance.skin = _rig.skin
	mesh_instance.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 2.6, 2.4))
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	_cur.resize(_nb)
	_tgt.resize(_nb)
	for n in names:
		var idx := names.find(n)
		match n:
			"root": b_root = idx
			"hips": b_hips = idx
			"torso": b_torso = idx
			"head": b_head = idx
			"eyes": b_eyes = idx
			"arm_l": b_arm_l = idx
			"fore_l": b_fore_l = idx
			"arm_r": b_arm_r = idx
			"fore_r": b_fore_r = idx
			"thigh_l": b_thigh_l = idx
			"shin_l": b_shin_l = idx
			"thigh_r": b_thigh_r = idx
			"shin_r": b_shin_r = idx
			"ear_l": b_ear_l = idx
			"ear_r": b_ear_r = idx
			"body": b_body = idx
			"tail": b_tail = idx
			"leg_fl": b_leg_fl = idx
			"leg_fr": b_leg_fr = idx
			"leg_bl": b_leg_bl = idx
			"leg_br": b_leg_br = idx
	if _dog:
		walk_speed = 1.5
	elif _meta.kind == "child":
		walk_speed = 1.1
	_apply_scale()
	_phase = VoxelBuilder.hash3(Vector3i(get_instance_id() % 9973, 3, 7)) * TAU
	_t = _phase * 3.0
	_blink_t = 1.0 + _phase
	# Snaps straight into the pose on spawn (no blend from T-pose).
	set_pose(pose)


func _apply_scale() -> void:
	if skeleton == null:
		return
	_s = body_scale
	if _s <= 0.0:
		_s = AUTO_SCALE.get(_meta.kind, 1.0)
	else:
		# Locations pass a "life size" scale; the hero household never drops
		# below a legible minimum (ref1: chunky chibi sims about half the wall
		# height, the beagle as long as a kid) so faces and silhouettes read
		# on a phone even in a zoomed-out house view.
		_s = maxf(_s, HERO_MIN.get(look, 0.0))
	skeleton.scale = Vector3.ONE * _s
	walk_speed = (1.5 if _dog else (1.1 if _meta.kind == "child" else 1.3)) * sqrt(_s)


const AUTO_SCALE := {"adult": 1.35, "child": 1.35, "dog": 1.45}
const HERO_MIN := {"dad": 1.22, "bunny_girl": 1.25, "cat_girl": 1.25, "beagle": 1.18}


func kind() -> String:
	if _meta.is_empty():
		var L: Dictionary = RigBuilder.Looks.get_look(look)
		if L.get("species", "") == "dog":
			return "dog"
		return "child" if L.get("body", "") == "child" else "adult"
	return _meta.kind


func set_pose(p: String) -> void:
	if p == "":
		p = "idle"
	if _walking and p != "walk":
		_walking = false
	pose = p
	if skeleton == null:
		return
	_update_props()
	if _frames < 2:
		_snap()


func _snap() -> void:
	_compute_targets(0.0)
	for i in _nb:
		_cur[i] = _tgt[i]
	_cur_pos = _tgt_pos
	_root_rot = _tgt_root_rot
	_root_pos = _tgt_root_pos
	_apply()


func walk_to(world_pos: Vector3) -> void:
	if not is_inside_tree():
		position = world_pos
		arrived.emit()
		return
	_walk_target = world_pos
	_walking = true
	if pose != "walk":
		_pose_after_walk = "idle"
	pose = "walk"
	_update_props()


func face(world_pos: Vector3) -> void:
	var d := world_pos - global_position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func head_top() -> Vector3:
	var h: float = (_meta.get("height", 1.75) if not _meta.is_empty() else (0.75 if look == "beagle" else 1.8)) * _s
	if skeleton == null or b_head < 0 or not is_inside_tree():
		return global_position + Vector3(0, h + 0.15, 0)
	var g := skeleton.global_transform * skeleton.get_bone_global_pose(b_head)
	var up: float = _meta.head_h
	if _dog:
		return g * Vector3(0, up + 0.12, 0.1)
	var p := g * Vector3(0, up + 0.1, 0)
	# Keep the anchor above the head even when lying.
	p.y = maxf(p.y, (g.origin.y) + 0.35)
	return p


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if skeleton == null:
		return
	delta = minf(delta, 0.1)
	_t += delta
	_frames += 1
	if _walking:
		_step_walk(delta)
	elif pose == "walk":
		# Walk in place (e.g. a staged screenshot).
		var stride: float = (0.9 if _dog else 1.6) * maxf(0.3, _meta.get("hip_y", 0.25)) * _s
		_walk_phase += walk_speed * delta / stride * PI
	# Blinking.
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 0.13
		_blink_t = 2.5 + VoxelBuilder.hash3(Vector3i(int(_t * 10.0), 1, 2)) * 3.5
	_blink = maxf(0.0, _blink - delta)
	_compute_targets(delta)
	var k := 1.0 - exp(-delta * 14.0)
	for i in _nb:
		_cur[i] = _cur[i].lerp(_tgt[i], k)
	_cur_pos = _cur_pos.lerp(_tgt_pos, k)
	_root_rot = _root_rot.lerp(_tgt_root_rot, k)
	_root_pos = _root_pos.lerp(_tgt_root_pos, k)
	_apply()


func _step_walk(delta: float) -> void:
	var to := _walk_target - global_position
	to.y = 0.0
	var dist := to.length()
	var step := walk_speed * delta
	if dist <= step or dist < 0.02:
		global_position = Vector3(_walk_target.x, global_position.y, _walk_target.z)
		_walking = false
		pose = _pose_after_walk
		_update_props()
		arrived.emit()
		return
	var dir := to / dist
	global_position += dir * step
	var want := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-delta * 10.0))
	var stride: float = (0.9 if _dog else 1.6) * maxf(0.3, _meta.get("hip_y", 0.25)) * _s
	_walk_phase += step / stride * PI


func _apply() -> void:
	for i in _nb:
		skeleton.set_bone_pose_rotation(i, Quaternion.from_euler(_cur[i]))
	var hb := b_body if _dog else b_hips
	skeleton.set_bone_pose_position(hb, _rests[hb] + _cur_pos)
	skeleton.set_bone_pose_rotation(b_root, Quaternion.from_euler(_root_rot))
	skeleton.set_bone_pose_position(b_root, _root_pos)
	var closed := _eyes_closed or _blink > 0.0
	skeleton.set_bone_pose_scale(b_eyes, Vector3.ZERO if closed else Vector3.ONE)


# ---------------------------------------------------------------------------
# Poses

func _base_pose() -> String:
	var p := pose
	if p.begins_with("sit_") and p != "sit_floor":
		return p.substr(4)
	if p.begins_with("stand_"):
		return p.substr(6)
	return p


func _seated() -> bool:
	var p := pose
	if p == "sit" or p == "sit_floor":
		return true
	if p.begins_with("sit_"):
		return true
	if p.begins_with("stand_"):
		return false
	return p == "type" or p == "read"


func _compute_targets(_delta: float) -> void:
	for i in _nb:
		_tgt[i] = Vector3.ZERO
	_tgt_pos = Vector3.ZERO
	_tgt_root_rot = Vector3.ZERO
	_tgt_root_pos = Vector3.ZERO
	_eyes_closed = false
	_cam_a = _camera_angle()
	if has_meta("dbg_cam_a"):
		_cam_a = get_meta("dbg_cam_a")
	if _dog:
		_dog_pose()
	else:
		_human_pose()
	if has_meta("dbg_head_yaw"):
		_tgt[b_head].y = get_meta("dbg_head_yaw")


## Signed yaw from the actor's forward (+Z) to the active camera, radians.
## Positive = camera on the actor's left (+X).
func _camera_angle() -> float:
	if not camera_cheat or not is_inside_tree():
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var d := cam.global_position - global_position
	var b := global_transform.basis.orthonormalized()
	var lx := b.x.dot(d)
	var lz := b.z.dot(d)
	return atan2(lx, lz)


## Sims-style presentation turn: swivel hips/torso/head toward the camera so
## the face shows in roughly 3/4 view (`keep` radians off the camera axis),
## capped at `max_turn`. Returns the yaw given to hips+torso (for arm
## compensation).
func _cheat(max_turn: float, wh := 0.3, wt := 0.25, keep := 0.75) -> float:
	var a := _cam_a
	if absf(a) <= keep:
		return 0.0
	var want := clampf(a - signf(a) * keep, -max_turn, max_turn)
	_ab(b_hips, 0.0, want * wh, 0.0)
	_ab(b_torso, 0.0, want * wt, 0.0)
	_ab(b_head, 0.0, want * (1.0 - wh - wt), 0.0)
	return want * (wh + wt)


## Partial presentation turn for activities done facing away from the player:
## the head (and a little of the torso) turns toward the camera by at most
## `max_turn` radians, so the face reads in profile / back three-quarter while
## the body stays square to the work. Returns the hips+torso yaw.
func _glance(max_turn: float, wh := 0.1, wt := 0.2) -> float:
	var a := _cam_a
	if absf(a) < 0.15:
		return 0.0
	var want := clampf(a, -max_turn, max_turn)
	_ab(b_hips, 0.0, want * wh, 0.0)
	_ab(b_torso, 0.0, want * wt, 0.0)
	_ab(b_head, 0.0, want * (1.0 - wh - wt), 0.0)
	return want * (wh + wt)


func _sb(i: int, x: float, y := 0.0, z := 0.0) -> void:
	if i >= 0:
		_tgt[i] = Vector3(x, y, z)


func _ab(i: int, x: float, y := 0.0, z := 0.0) -> void:
	if i >= 0:
		_tgt[i] += Vector3(x, y, z)


func _human_pose() -> void:
	var t := _t
	var bp := _base_pose()
	var breath := sin(t * 2.1 + _phase)
	var child: bool = _meta.kind == "child"
	var elderly: bool = _meta.elderly
	# Neutral stance: arms hang slightly out, gentle breathing.
	_sb(b_arm_l, 0.04 * breath, 0.0, 0.09 + 0.015 * breath)
	_sb(b_arm_r, 0.04 * breath, 0.0, -0.09 - 0.015 * breath)
	_sb(b_fore_l, -0.12)
	_sb(b_fore_r, -0.12)
	_sb(b_torso, 0.012 * breath + (0.12 if elderly else 0.0))
	_sb(b_head, -0.015 * breath - (0.08 if elderly else 0.0), 0.0, 0.0)
	_tgt_pos.y = 0.003 * breath
	# Hat ears splay out a little and wobble.
	var ear_w := 0.05 * sin(t * 1.7 + _phase)
	_sb(b_ear_l, -0.08 + ear_w * 0.5, 0.0, -0.18 - ear_w)
	_sb(b_ear_r, -0.08 - ear_w * 0.5, 0.0, 0.18 + ear_w)

	if _seated() and bp != "play":
		if pose == "sit_floor":
			_sit_floor()
		else:
			_sit_chair()

	match bp:
		"idle":
			_ab(b_head, 0.0, 0.22 * sin(t * 0.37 + _phase) * smoothstep(0.3, 1.0, sin(t * 0.21 + _phase)), 0.03 * sin(t * 0.5))
			_ab(b_hips, 0.0, 0.0, 0.025 * sin(t * 0.6 + _phase))
			_ab(b_torso, 0.0, 0.0, -0.02 * sin(t * 0.6 + _phase))
			if not _seated():
				# Weight on one leg.
				var w := 0.5 + 0.5 * sin(t * 0.6 + _phase)
				_ab(b_thigh_l, -0.04 * w, 0.0, 0.02)
				_ab(b_shin_l, 0.08 * w)
				_ab(b_thigh_r, -0.04 * (1.0 - w), 0.0, -0.02)
				_ab(b_shin_r, 0.08 * (1.0 - w))
		"walk":
			var f := _walk_phase
			var s := sin(f)
			var c := cos(f)
			var amp := 0.6 if child else 0.5
			_sb(b_thigh_l, -amp * s)
			_sb(b_thigh_r, amp * s)
			_sb(b_shin_l, 0.1 + 0.75 * maxf(0.0, c))
			_sb(b_shin_r, 0.1 + 0.75 * maxf(0.0, -c))
			_sb(b_arm_l, 0.5 * s, 0.0, 0.1)
			_sb(b_arm_r, -0.5 * s, 0.0, -0.1)
			_sb(b_fore_l, -0.35 - 0.15 * maxf(0.0, -s))
			_sb(b_fore_r, -0.35 - 0.15 * maxf(0.0, s))
			_sb(b_hips, 0.0, 0.1 * s, 0.0)
			_sb(b_torso, 0.06 + (0.12 if elderly else 0.0), -0.16 * s, 0.0)
			_sb(b_head, -0.03 + 0.03 * absf(c), 0.06 * s, 0.0)
			_tgt_pos.y = 0.025 * absf(c) - 0.01
			var fl := 0.25 * absf(c)
			_sb(b_ear_l, 0.1 + fl, 0.0, -0.2 - fl * 0.4)
			_sb(b_ear_r, 0.1 + fl, 0.0, 0.2 + fl * 0.4)
		"sit", "sit_floor":
			_ab(b_head, 0.0, 0.18 * sin(t * 0.33 + _phase), 0.0)
		"lie", "sleep":
			_lie()
			if bp == "sleep":
				_eyes_closed = true
				var slow := sin(t * 1.1 + _phase)
				_sb(b_torso, 0.025 * slow)
				_sb(b_head, -0.02 * slow, 0.35, 0.0)
		"type":
			# Seated at the desk, back three-quarter to a Sims camera: the body
			# stays square to the keyboard (forearms forward on the desk), and
			# only the head turns part way so the beard + nose read in profile.
			var tap := sin(t * 13.0)
			var tap2 := sin(t * 11.0 + 1.3)
			var body_yaw := 0.0
			if _seated():
				# Office chairs swivel: the whole body turns part way toward
				# the player and the head the rest, so beard, nose and eye
				# read in profile / 3/4 even from behind the desk.
				var behind := smoothstep(1.6, 2.6, absf(_cam_a))
				body_yaw = _glance(2.0, lerpf(0.2, 0.24, behind), lerpf(0.16, 0.22, behind))
				# Sit squarely ON the seat (scooted to its front edge), sit
				# up tall and lean in a little toward the screen; the swivel
				# + head turn above keeps beard, eye and plaid in 3/4 view.
				var sd := signf(_cam_a) if absf(_cam_a) > 0.3 else 0.0
				var ws := _s * maxf(scale.x, 0.01)
				_tgt_pos.z += (0.1 + 0.03 * behind) / ws
				_tgt_pos.y += 0.03 / ws
				_ab(b_torso, 0.1, 0.0, -sd * 0.06)
				_ab(b_head, -0.18, 0.0, sd * 0.08)
			# The far hand stays on the keyboard; the hand nearer the camera
			# works the mouse out to the side, so a plaid arm and a hand on
			# the desk read beside the body instead of hiding behind it.
			# Both forearms reach forward onto the keyboard (the shoulders
			# compensate the presentation swivel so the hands stay on it).
			_sb(b_arm_l, -1.15, -0.16 - body_yaw * 0.9, -0.04)
			_sb(b_arm_r, -1.15, 0.16 - body_yaw * 0.9, 0.04)
			_sb(b_fore_l, -0.45 + 0.1 * maxf(0.0, tap), 0.0, 0.0)
			_sb(b_fore_r, -0.45 + 0.1 * maxf(0.0, tap2), 0.0, 0.0)
			_ab(b_head, -0.04 + 0.02 * sin(t * 0.8), 0.05 * sin(t * 0.4), 0.04)
		"read":
			_sb(b_arm_l, -0.45, 0.0, -0.18)
			_sb(b_arm_r, -0.45, 0.0, 0.18)
			_sb(b_fore_l, -1.05, 0.0, 0.0)
			_sb(b_fore_r, -1.05, 0.0, 0.0)
			_ab(b_torso, 0.06)
			_ab(b_head, 0.2, 0.05 * sin(t * 0.6), 0.0)
			_cheat(1.7, 0.25, 0.3, 0.85)
		"paint":
			# Facing the easel, brush arm reaching forward-up to the canvas,
			# palette held low in the other hand; the head turns part way to
			# the player. The brush goes in the hand nearer the camera so the
			# reaching arm reads against the body (it stays below the face).
			var dab := sin(t * 3.2)
			var dab2 := sin(t * 1.3 + _phase)
			var want_left := _cam_a > 0.05
			if want_left != _brush_left:
				_brush_left = want_left
				_update_props()
			var m := -1.0 if _brush_left else 1.0
			var bi := b_arm_l if _brush_left else b_arm_r
			var bf := b_fore_l if _brush_left else b_fore_r
			var pi_ := b_arm_r if _brush_left else b_arm_l
			var pf := b_fore_r if _brush_left else b_fore_l
			# Brush arm stretched out level toward the canvas (reads as
			# "painting" in silhouette), small dabbing strokes.
			_sb(bi, -1.62 + 0.08 * dab, (0.1 + 0.06 * dab2) * m, 0.08 * m)
			_sb(bf, -0.12 - 0.14 * maxf(0.0, dab))
			if _seated():
				# Perch on the front edge of the stool, leaning in to the canvas.
				_tgt_pos.z += 0.12 / _s
			_sb(pi_, -0.5, 0.0, 0.3 * m)
			_sb(pf, -1.15)
			_ab(b_head, 0.02, 0.05 * dab2, 0.06 * sin(t * 0.7))
			_ab(b_torso, 0.24, 0.0, 0.0)
			# Mostly in profile, looking at her canvas; the head turns only
			# part way so eyes and smile still read.
			var py := _glance(1.3, 0.08, 0.14)
			_ab(bi, 0.0, -py, 0.0)
			_ab(pi_, 0.0, -py, 0.0)
		"talk":
			var g := sin(t * 2.3 + _phase)
			_sb(b_arm_r, -0.45 + 0.2 * g, 0.0, -0.15)
			_sb(b_fore_r, -0.9 - 0.25 * g)
			_sb(b_arm_l, -0.1 - 0.1 * maxf(0.0, -g), 0.0, 0.15)
			_sb(b_fore_l, -0.5)
			_ab(b_head, 0.07 * sin(t * 3.3), 0.12 * sin(t * 0.9 + _phase), 0.05 * sin(t * 1.3))
		"wave":
			var wv := sin(t * 9.0)
			_sb(b_arm_r, -0.3, 0.0, -2.45)
			_sb(b_fore_r, 0.0, 0.0, -0.25 + 0.4 * wv)
			_ab(b_head, -0.06, 0.0, 0.08)
			_ab(b_torso, 0.0, 0.0, 0.05)
		"grill":
			var flip := pow(maxf(0.0, sin(t * 2.4)), 4.0)
			_sb(b_arm_r, -0.75, 0.0, 0.1)
			_sb(b_fore_r, -0.55 - 0.5 * flip)
			_sb(b_arm_l, -0.45, 0.0, -0.05)
			_sb(b_fore_l, -0.9)
			_ab(b_head, 0.16, 0.0, 0.0)
			_ab(b_torso, 0.1)
		"brush_teeth":
			var br := sin(t * 18.0)
			_sb(b_arm_r, -0.55, 0.06 * br, 0.4)
			_sb(b_fore_r, -2.0, 0.0, 0.0)
			_sb(b_arm_l, 0.0, 0.0, 0.08)
			_ab(b_head, -0.05, 0.0, 0.0)
		"play":
			# Cross-legged on the rug, leaning in over the toys, both hands busy.
			_sit_floor()
			var pl := sin(t * 3.0 + _phase)
			var pl2 := sin(t * 2.2 + _phase * 2.0)
			_sb(b_arm_l, -0.95 + 0.18 * pl, -0.25, -0.05)
			_sb(b_arm_r, -0.75 - 0.22 * pl2, 0.3, 0.05)
			_sb(b_fore_l, -0.7 - 0.15 * pl2)
			_sb(b_fore_r, -0.85 + 0.15 * pl)
			_ab(b_torso, 0.04)
			# Head tips back up so the face stays visible from above.
			_ab(b_head, -0.3, 0.12 * sin(t * 0.7), 0.08 * sin(t * 1.1))


func _sit_chair() -> void:
	# Hips on the seat (in skeleton space, i.e. unscaled body units).
	var hs: float = seat_height / _s + float(_meta.leg_half)
	# Shins hang straight down; if the seat is too low for the (scaled) legs
	# the knees open up so the feet stay on the floor instead of sinking in.
	var shin_len: float = _meta.get("shin_len", 0.3)
	var knee := PI * 0.5 - 0.06
	if hs < shin_len:
		knee = PI * 0.5 - acos(clampf(hs / shin_len, 0.0, 1.0))
	_sb(b_thigh_l, -PI * 0.5, 0.06, 0.0)
	_sb(b_thigh_r, -PI * 0.5, -0.06, 0.0)
	_sb(b_shin_l, knee)
	_sb(b_shin_r, knee - 0.12)
	_sb(b_arm_l, -0.3, 0.0, 0.05)
	_sb(b_arm_r, -0.3, 0.0, -0.05)
	_sb(b_fore_l, -0.75)
	_sb(b_fore_r, -0.75)
	_tgt_pos.y += hs - float(_meta.hip_y)


func _sit_floor() -> void:
	# Cross-legged: thighs forward and splayed out, shins folded across in
	# front, feet tucked under the opposite knee.
	_sb(b_thigh_l, -PI * 0.5 + 0.05, 0.85, 0.0)
	_sb(b_thigh_r, -PI * 0.5 + 0.05, -0.85, 0.0)
	_sb(b_shin_l, 0.0, 0.0, -PI * 0.5 - 0.55)
	_sb(b_shin_r, 0.08, 0.0, PI * 0.5 + 0.55)
	_sb(b_arm_l, -0.35, 0.0, 0.12)
	_sb(b_arm_r, -0.35, 0.0, -0.12)
	_sb(b_fore_l, -0.7)
	_sb(b_fore_r, -0.7)
	_ab(b_torso, 0.05)
	_tgt_pos.y += float(_meta.leg_half) - float(_meta.hip_y)


func _lie() -> void:
	var h: float = _meta.height
	_tgt_root_rot = Vector3(-PI * 0.5, 0.0, 0.0)
	_tgt_root_pos = Vector3(0.0, lie_height / _s + float(_meta.torso_half) + 0.02, h * 0.5)
	_sb(b_arm_l, 0.0, 0.0, 0.12)
	_sb(b_arm_r, 0.0, 0.0, -0.12)
	_sb(b_fore_l, -0.25)
	_sb(b_fore_r, -0.25)
	_sb(b_thigh_l, 0.0, 0.0, 0.03)
	_sb(b_thigh_r, 0.0, 0.0, -0.03)
	_sb(b_shin_l, 0.06)
	_sb(b_shin_r, 0.06)
	_sb(b_head, -0.25)


func _dog_pose() -> void:
	var t := _t
	var bp := pose
	var breath := sin(t * 2.6 + _phase)
	var wag := sin(t * 11.0)
	_sb(b_tail, -0.45, 0.0, 0.35 * wag)
	_sb(b_body, 0.0)
	_tgt_pos.y = 0.004 * breath
	_sb(b_head, -0.05 + 0.03 * breath, 0.12 * sin(t * 0.45 + _phase), 0.12 * smoothstep(0.6, 1.0, sin(t * 0.3 + _phase)))
	_sb(b_ear_l, 0.0, 0.0, 0.08 + 0.03 * breath)
	_sb(b_ear_r, 0.0, 0.0, -0.08 - 0.03 * breath)
	var vs: float = RigBuilder.VS
	match bp:
		"walk":
			var f := _walk_phase
			var s := sin(f)
			var c := cos(f)
			_sb(b_leg_fl, -0.55 * s)
			_sb(b_leg_br, -0.55 * s)
			_sb(b_leg_fr, 0.55 * s)
			_sb(b_leg_bl, 0.55 * s)
			_sb(b_body, 0.03 * c, 0.05 * s, 0.0)
			_tgt_pos.y = 0.012 * absf(c)
			_sb(b_head, 0.04 * absf(c) - 0.05, -0.05 * s, 0.0)
			_sb(b_tail, -0.6, 0.0, 0.5 * sin(t * 16.0))
			_sb(b_ear_l, -0.3 * absf(c), 0.0, 0.15 + 0.1 * absf(s))
			_sb(b_ear_r, -0.3 * absf(c), 0.0, -0.15 - 0.1 * absf(s))
		"sit":
			_sb(b_body, -0.38)
			_tgt_pos.y = -1.3 * vs
			_sb(b_leg_fl, 0.38)
			_sb(b_leg_fr, 0.38)
			_sb(b_leg_bl, -1.25, 0.15, 0.0)
			_sb(b_leg_br, -1.25, -0.15, 0.0)
			_ab(b_head, 0.3)
			_sb(b_tail, -1.3, 0.0, 0.25 * wag)
		"lie", "sleep":
			var ly := _dog_lie()
			if bp == "sleep":
				_eyes_closed = true
				_sb(b_head, 0.35 + 0.02 * breath, 0.55 + ly * 0.5, 0.15)
				_sb(b_tail, -1.4, 0.9, 0.0)
				_sb(b_body, 0.0, 0.0, 0.0)
		"chew":
			# Lying on the rug gnawing a chew toy held across the mouth.
			var ly := _dog_lie()
			var chew := sin(t * 7.0)
			_sb(b_head, -0.04 + 0.05 * maxf(0.0, chew), ly + 0.1 * sin(t * 0.9 + _phase), 0.1 * sin(t * 1.7))
			_sb(b_tail, -0.9, 0.0, 0.55 * sin(t * 14.0))
			_sb(b_ear_l, 0.05 * chew, 0.0, 0.3)
			_sb(b_ear_r, 0.05 * chew, 0.0, -0.3)
		"play":
			# Belly down facing the player in a 3/4 front view (ref1): front
			# paws stretched forward either side of the chew bone, head up
			# looking at the camera with the ears framing the white blaze,
			# rump and wagging white-tipped tail up behind.
			var ly := _dog_lie(true)
			var perk := smoothstep(0.55, 1.0, sin(t * 0.8 + _phase))
			var paw := pow(maxf(0.0, sin(t * 1.9 + _phase)), 6.0)
			_sb(b_head, -0.38 - 0.05 * perk + 0.02 * breath, ly, 0.22 * sin(t * 0.6 + _phase) * (0.4 + 0.6 * perk))
			_sb(b_tail, -0.75, 0.0, 0.6 * sin(t * 13.0))
			_ab(b_leg_fl, -0.25 * paw, 0.0, 0.0)
			# Head is tipped up, so tip the ears back down to hang beside the
			# cheeks (framing the face) instead of sticking out.
			_sb(b_ear_l, 0.12 + 0.05 * perk, 0.0, 0.02 + 0.04 * perk)
			_sb(b_ear_r, 0.12 + 0.05 * perk, 0.0, -0.02 - 0.04 * perk)
			# Rump slightly raised (playful), chest low.
			_sb(b_body, 0.06)
		"bow":
			var hop := absf(sin(t * 5.0))
			_sb(b_body, 0.32)
			_tgt_pos.y = -1.6 * vs + 0.02 * hop
			_sb(b_leg_fl, -1.25, 0.1, 0.0)
			_sb(b_leg_fr, -1.25, -0.1, 0.0)
			_sb(b_leg_bl, -0.32)
			_sb(b_leg_br, -0.32)
			_sb(b_head, -0.55, 0.1 * sin(t * 2.0), 0.18 * sin(t * 1.3))
			_sb(b_tail, -0.2, 0.0, 0.6 * sin(t * 18.0))
			_sb(b_ear_l, 0.0, 0.0, 0.25 + 0.1 * hop)
			_sb(b_ear_r, 0.0, 0.0, -0.25 - 0.1 * hop)
		"talk":
			var bark := pow(maxf(0.0, sin(t * 4.0)), 6.0)
			_ab(b_head, -0.25 * bark - 0.1, 0.0, 0.0)
			_sb(b_tail, -0.6, 0.0, 0.5 * sin(t * 15.0))


func _dog_lie(front := false) -> float:
	# Sphinx pose: belly on the floor, front legs stretched forward, hind legs
	# folded out to the sides.
	var vs: float = RigBuilder.VS
	var look_yaw := 0.0
	# Presentation (a lying dog seen nose-on from above is a shapeless blob):
	# side: nose toward screen-right and a little toward the viewer, body and
	#   tail trailing left, head turned back toward the player.
	# front: nose toward the viewer and to screen-right (ref1 3/4 front view,
	#   mirrored), body trailing back-left, head looking straight at the camera.
	if camera_cheat and is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam:
			var r := cam.global_transform.basis.x
			r.y = 0.0
			var c := cam.global_position - global_position
			c.y = 0.0
			if r.length() > 0.01 and c.length() > 0.01:
				r = r.normalized()
				c = c.normalized()
				var want := (r * 0.95 + c * 0.25).normalized()
				if front:
					# Long side toward the player (body length, saddle and
					# tail read), nose to screen-right and a little toward
					# the viewer, head swung round to look at the camera.
					want = (r * 1.0 + c * 0.12).normalized()
				var want_yaw := atan2(want.x, want.z)
				_tgt_root_rot.y = wrapf(want_yaw - global_rotation.y, -PI, PI)
				look_yaw = clampf(wrapf(atan2(c.x, c.z) - want_yaw, -PI, PI), -0.9, 0.9)
	# A lying dog's anchor sits at its haunches: the chest, paws and head
	# reach forward (toward the toy) instead of centring on the spot.
	_tgt_root_pos = Basis(Vector3.UP, _tgt_root_rot.y) * Vector3(0.0, 0.0, (17.0 if front else 6.0) * vs)
	_tgt_pos.y = -float(_meta.leg) + 0.3 * vs
	if front:
		# Paws splayed a little so the bone sits between them.
		_sb(b_leg_fl, -1.52, 0.0, 0.16)
		_sb(b_leg_fr, -1.52, 0.0, -0.16)
	else:
		_sb(b_leg_fl, -1.5, 0.1, 0.0)
		_sb(b_leg_fr, -1.5, -0.1, 0.0)
	# Hind legs folded along the flanks (a side-on dog with splayed hips
	# shows a stray tan block poking at the camera).
	var splay := 0.08 if front else 0.55
	_sb(b_leg_bl, -1.45, splay, 0.0)
	_sb(b_leg_br, -1.45, -splay, 0.0)
	_sb(b_tail, -1.25, 0.0, 0.15 * sin(_t * 11.0))
	_ab(b_head, 0.1, look_yaw, 0.0)
	return look_yaw


# ---------------------------------------------------------------------------
# Props

const _PROPS_FOR := {
	"read": [["book", "fore_r"]],
	"paint": [["brush", "fore_r"], ["palette", "fore_l"]],
	"grill": [["spatula", "fore_r"]],
	"brush_teeth": [["toothbrush", "fore_r"]],
	"play": [["block", "fore_r"], ["robot", "fore_l"]],
}
const _DOG_PROPS_FOR := {
	"play": [["bone", "body"]],
	"chew": [["bone", "head"]],
}


func _update_props() -> void:
	if skeleton == null:
		return
	var want: Array = (_DOG_PROPS_FOR.get(pose, []) if _dog else _PROPS_FOR.get(_base_pose(), []))
	for n: String in _props:
		(_props[n] as Node3D).visible = false
	var swap := _brush_left and not _dog and _base_pose() == "paint"
	for entry: Array in want:
		var pname: String = entry[0]
		var bone: String = entry[1]
		if swap:
			bone = "fore_l" if bone == "fore_r" else "fore_r"
		var key := pname + "@" + bone
		if not _props.has(key):
			_props[key] = _make_prop(pname, bone)
		(_props[key] as Node3D).visible = true


func _make_prop(pname: String, bone: String) -> MeshInstance3D:
	var att: BoneAttachment3D
	if _attach.has(bone):
		att = _attach[bone]
	else:
		att = BoneAttachment3D.new()
		att.bone_name = bone
		skeleton.add_child(att)
		_attach[bone] = att
	var mi := MeshInstance3D.new()
	mi.mesh = RigBuilder.prop_mesh(pname)
	if _dog:
		if bone == "body":
			# On the floor between the outstretched front paws.
			mi.position = _meta.paws
			mi.rotation = Vector3(0.0, 0.35, 0.0)
		else:
			mi.position = _meta.mouth
		att.add_child(mi)
		return mi
	var hand: float = -float(_meta.fore_len) + 0.03
	var ax: float = _meta.arm_x
	match pname:
		"book":
			mi.position = Vector3(ax, hand - 0.02, 0.06)
			mi.rotation = Vector3(0.25, 0, 0)
		"brush", "spatula":
			mi.position = Vector3(0, hand, 0.03)
			mi.rotation = Vector3(-0.3, 0, 0)
		"palette":
			mi.position = Vector3(0, hand - 0.03, 0.04)
			mi.rotation = Vector3(-PI * 0.5, 0, 0)
		"toothbrush":
			mi.position = Vector3(0.0, hand - 0.02, 0.03)
			mi.rotation = Vector3(0, 0, PI * 0.5)
		"block":
			mi.position = Vector3(0, hand - 0.04, 0.03)
		"robot":
			mi.position = Vector3(0, hand - 0.05, 0.04)
	att.add_child(mi)
	return mi
