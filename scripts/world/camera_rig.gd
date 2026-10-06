extends Node3D
## Sims-style camera: orbits a ground target at a fixed pitch.
## Touch: one-finger drag pans, pinch zooms, two-finger twist rotates.
## Mouse: left-drag pans, wheel zooms, right-drag rotates.

var target := Vector3.ZERO
var yaw := 35.0
var pitch := 40.0
var distance := 12.0
var min_distance := 4.0
var max_distance := 30.0
var camera: Camera3D
var _touches := {}
var _pinch_start := 0.0
var _pinch_dist0 := 0.0
var _twist0 := 0.0
var _yaw0 := 0.0


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
	_update()


func _update() -> void:
	if camera == null:
		return
	var r := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
	camera.global_position = target + r * Vector3(0, 0, distance)
	camera.look_at(target, Vector3.UP)


func _pan(screen_delta: Vector2) -> void:
	var k := distance * 0.0016
	var right := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	target -= (right * screen_delta.x + fwd * screen_delta.y) * k
	_update()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_dist0 = pts[0].distance_to(pts[1])
			_pinch_start = distance
			_twist0 = (pts[1] - pts[0]).angle()
			_yaw0 = yaw
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_pan(e.relative)
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
