class_name Interactable
extends StaticBody3D
## Makes a piece of furniture / prop tappable. Locations attach these; the
## gameplay layer raycasts them, shows the action menu, walks a sim to
## `use_spot` and runs the chosen action.
##
## action dictionary keys:
##   id: String, label: String, icon: String,
##   minutes: float (in-game duration), needs: {need_name: delta_per_action},
##   skill: String (optional, e.g. "Creativity"), pose: String (SimActor pose),
##   money: int (optional, +earn / -cost), task: String (optional task title it completes),
##   who: Array[String] (optional kinds allowed: "adult", "child", "dog")

var title := ""
var actions: Array = []
## Local-space point where a sim stands/sits to use this object.
var use_spot := Vector3.ZERO
## Local-space point the sim faces while using it.
var look_at_spot := Vector3.ZERO


## Attach a tappable box collider of `size` (metres, centred at `center`) to `parent`.
static func attach(parent: Node3D, p_title: String, p_actions: Array, size: Vector3, center := Vector3.ZERO, p_use_spot := Vector3.ZERO) -> Interactable:
	var it := Interactable.new()
	it.title = p_title
	it.actions = p_actions
	it.use_spot = p_use_spot
	it.look_at_spot = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	it.add_child(cs)
	parent.add_child(it)
	return it


func world_use_spot() -> Vector3:
	return global_transform * use_spot
