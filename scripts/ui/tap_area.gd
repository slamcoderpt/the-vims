extends Control
## A tappable Control whose hit area can extend beyond its visual rect, so
## small-looking HUD controls still give phone-sized (44pt+) touch targets.
## Emits `tapped`; gives a quick press squish on the `visual` node if set.

signal tapped

## Extra hit margin in design units: left, top, right, bottom.
var hit_pad := Vector4.ZERO
var visual: Control
var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2(-hit_pad.x, -hit_pad.y), size + Vector2(hit_pad.x + hit_pad.z, hit_pad.y + hit_pad.w)).has_point(point)


func _gui_input(e: InputEvent) -> void:
	var press := false
	var release := false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		press = e.pressed
		release = not e.pressed
	elif e is InputEventScreenTouch:
		press = e.pressed
		release = not e.pressed
	if press:
		_down = true
		_squish(0.93)
		accept_event()
	elif release and _down:
		_down = false
		_squish(1.0)
		accept_event()
		if _has_point(get_local_mouse_position()) or e is InputEventScreenTouch:
			tapped.emit()


func _squish(s: float) -> void:
	var v := visual if visual else self
	v.pivot_offset = v.size * 0.5
	var tw := create_tween()
	tw.tween_property(v, "scale", Vector2(s, s), 0.08)
