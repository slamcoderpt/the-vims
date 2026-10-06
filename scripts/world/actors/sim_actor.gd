class_name SimActor
extends Node3D
## A voxel person or pet. Placeholder; to be replaced by the characters builder.
## Contract used by locations and gameplay (keep these signatures stable):
##   SimActor.create(look: String) -> SimActor     looks: "dad", "bunny_girl", "cat_girl", "beagle", plus NPC looks
##   set_pose(pose: String)       "idle", "walk", "sit", "sit_floor", "lie", "sleep", "type", "paint", "read", "talk", "wave", "grill", "brush_teeth", "play"
##   walk_to(world_pos: Vector3) -> void (emits arrived)
##   face(world_pos: Vector3)
##   head_top() -> Vector3       world position above the head, where bubbles anchor

signal arrived

var look := "dad"
var pose := "idle"


static func create(look_name: String) -> SimActor:
	var a := SimActor.new()
	a.look = look_name
	return a


func _ready() -> void:
	var vb := VoxelBuilder.new()
	var h := 28 if look != "beagle" else 10
	vb.box(Vector3i(0, 0, 0), Vector3i(8, h, 5), Color(0.8, 0.2, 0.2))
	add_child(vb.build_instance(0.0625, Vector3(4, 0, 2.5)))


func set_pose(p: String) -> void:
	pose = p


func walk_to(world_pos: Vector3) -> void:
	global_position = world_pos
	arrived.emit()


func face(world_pos: Vector3) -> void:
	var d := world_pos - global_position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func head_top() -> Vector3:
	return global_position + Vector3(0, 2.0 if look != "beagle" else 0.8, 0)
