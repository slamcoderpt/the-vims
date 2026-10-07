extends Node3D
## Sims-style camera: orbits a ground target at a fixed pitch.
## Touch: one-finger drag pans (with a little inertia), pinch zooms, two-finger
## twist rotates. Mouse: left-drag pans, wheel zooms, right-drag rotates.
## Keyboard (desktop/web): WASD / arrows pan, Q/E rotate, +/- zoom.
##
## API: apply(preset), glide_to(target), input_locked (gameplay sets it while
## dragging a build ghost), bounds (Rect2 over x/z the target stays inside).

var target := Vector3.ZERO
var yaw := 35.0
var pitch := 40.0
var distance := 12.0
var min_distance := 4.0
var max_distance := 30.0
var camera: Camera3D
## When true, drags don't pan (a build ghost is being dragged).
var input_locked := false
## Target clamp over x/z (empty = no clamp).
var bounds := Rect2()
var _touches := {}
var _pinch_start := 0.0
var _pinch_dist0 := 0.0
var _twist0 := 0.0
var _yaw0 := 0.0
var _vel := Vector2.ZERO        # pan inertia (screen px / s)
var _glide := Vector3.INF
var _last_drag_t := 0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	_update()


func apply(p: Dictionary) -> void:
	target = p.get("target", target)
	yaw = p.get("yaw", yaw)
	pitch = p.get("pitch", pitch)
	distance = p.get("distance", distance)
	if camera:
		camera.fov = p.get("fov", camera.fov)
	_glide = Vector3.INF
	_vel = Vector2.ZERO
	max_distance = maxf(max_distance, distance * 1.6)
	_update()


## Smoothly move the orbit target (e.g. to a newly selected sim).
func glide_to(p: Vector3) -> void:
	_glide = p


func _update() -> void:
	if camera == null:
		return
	if bounds.has_area():
		target.x = clampf(target.x, bounds.position.x, bounds.end.x)
		target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	var r := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
	camera.global_position = target + r * Vector3(0, 0, distance)
	camera.look_at(target, Vector3.UP)
	_update_cut()


## Sims-style cutaway for lower storeys: with cut_height set (the ceiling of
## the floor being viewed), the near clip plane slices off the storey above
## (its floor slab, walls, roof) around the target, so the room below and its
## sims show. Pure camera trick: no materials or meshes change (GL
## Compatibility / WebGL2 safe).
var cut_height := INF


func _update_cut() -> void:
	if cut_height == INF or target.y > cut_height:
		camera.near = 0.1
		return
	var cam := camera.global_position
	var f := -camera.global_transform.basis.z
	var fh := Vector3(f.x, 0.0, f.z)
	if fh.length() < 0.01 or cam.y <= cut_height:
		camera.near = 0.1
		return
	fh = fh.normalized()
	# The ceiling plane a little beyond the target is cut away...
	var q := Vector3(target.x, cut_height, target.z) + fh * 0.6
	var d := (q - cam).dot(f)
	# ...but never the sim standing at the target (head ~1.2 m above it).
	var head := (target + Vector3(0, 1.1, 0) - cam).dot(f) - 0.35
	camera.near = clampf(minf(d, head), 0.1, maxf(0.1, distance - 1.2))


func set_cut_height(h: float) -> void:
	cut_height = h
	if camera:
		_update_cut()


func _process(delta: float) -> void:
	var moved := false
	if _glide != Vector3.INF:
		var k := 1.0 - exp(-delta * 5.0)
		target = target.lerp(_glide, k)
		if target.distance_to(_glide) < 0.01:
			target = _glide
			_glide = Vector3.INF
		moved = true
	if _vel.length() > 5.0 and _touches.is_empty():
		_pan(_vel * delta, false)
		_vel *= exp(-delta * 6.0)
		moved = false
	else:
		_vel = Vector2.ZERO
	# Keyboard (desktop / web builds).
	var kp := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kp.x += 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kp.x -= 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		kp.y += 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		kp.y -= 1
	if kp != Vector2.ZERO:
		_pan(kp * 520.0 * delta, false)
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += 70.0 * delta
		moved = true
	if Input.is_physical_key_pressed(KEY_E):
		yaw -= 70.0 * delta
		moved = true
	if moved:
		_update()


func _pan(screen_delta: Vector2, cancel_glide := true) -> void:
	if cancel_glide:
		_glide = Vector3.INF
	var k := distance * 0.0016
	var right := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	target -= (right * screen_delta.x + fwd * screen_delta.y) * k
	_update()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			_vel = Vector2.ZERO
		else:
			_touches.erase(e.index)
			if Time.get_ticks_msec() - _last_drag_t > 80:
				_vel = Vector2.ZERO
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_dist0 = pts[0].distance_to(pts[1])
			_pinch_start = distance
			_twist0 = (pts[1] - pts[0]).angle()
			_yaw0 = yaw
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			if input_locked:
				return
			_pan(e.relative)
			_last_drag_t = Time.get_ticks_msec()
			var v: Vector2 = e.velocity if "velocity" in e else e.relative * 60.0
			_vel = _vel.lerp(v, 0.5).limit_length(2500.0)
		elif _touches.size() == 2:
			var pts: Array = _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch_dist0 > 0:
				distance = clampf(_pinch_start * _pinch_dist0 / max(d, 1.0), min_distance, max_distance)
			yaw = _yaw0 - rad_to_deg((pts[1] - pts[0]).angle() - _twist0)
			_update()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9); _update()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1); _update()
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		yaw -= e.relative.x * 0.3
		_update()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]:
			distance = maxf(min_distance, distance * 0.85); _update()
		elif e.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			distance = minf(max_distance, distance * 1.15); _update()
