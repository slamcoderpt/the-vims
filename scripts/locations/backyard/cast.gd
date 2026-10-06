extends RefCounted
## Who is at the barbecue and where: family + neighbours, with their
## Interactables (guests can be chatted with).

const Party := preload("res://scripts/locations/backyard/party.gd")

## key -> [look, aliases]
const PEOPLE := {
	"Jack": ["dad", ["dad"]],
	"Lily": ["bunny_girl", ["bunny_girl"]],
	"Maya": ["cat_girl", ["cat_girl"]],
	"Biscuit": ["beagle", ["beagle", "dog"]],
	"neighbor_1": ["npc_0", ["npc_0"]],
	"neighbor_2": ["npc_1", ["npc_1"]],
	"neighbor_3": ["npc_5", ["npc_5"]],
	"neighbor_4": ["npc_2", ["npc_2"]],
	"neighbor_5": ["npc_6", ["npc_6"]],
	"neighbor_6": ["npc_4", ["npc_4"]],
	"neighbor_7": ["npc_7", ["npc_7"]],
	"neighbor_8": ["npc_3", ["npc_3"]],
}

const GUEST_NAMES := {
	"neighbor_1": "Rosie", "neighbor_2": "Marcus", "neighbor_3": "Nia", "neighbor_4": "Edith",
	"neighbor_5": "Walter", "neighbor_6": "Sam", "neighbor_7": "Leo", "neighbor_8": "June",
}

var actors := {}   # key/alias -> Node3D
var root: Node3D


func build(parent: Node3D, party) -> void:
	root = Node3D.new()
	root.name = "Cast"
	parent.add_child(root)
	# Jack at the grill.
	var gf: Vector3 = party.grill_front()
	_spawn("Jack", gf, 0.0, "grill").face(Party.GRILL_POS)
	# Table.
	_seat("Lily", party, "end_l", "sit_talk")
	_seat("neighbor_3", party, "far_l", "sit_talk")
	_seat("neighbor_4", party, "far_m", "sit")
	_seat("Maya", party, "far_r", "sit_talk")
	_seat("neighbor_6", party, "near_l", "sit")
	_seat("neighbor_8", party, "near_m", "sit_talk")
	# On the deck, chatting with plates and drinks.
	var a := _spawn("neighbor_1", Vector3(5.0, 0.375, -3.4), 0.0, "talk")
	var b := _spawn("neighbor_2", Vector3(6.1, 0.375, -3.55), 0.0, "idle")
	a.face(Vector3(6.4, 0, -1.5))
	b.face(Vector3(4.6, 0, -2.0))
	# Lounge by the fire pit.
	_spawn_seated("neighbor_5", Vector3(7.05, 0, 1.1), -PI * 0.5 - 0.25, "sit_talk", 0.5)
	_spawn_seated("neighbor_7", Vector3(7.05, 0, 2.6), -PI * 0.5 + 0.1, "sit", 0.5)
	# Biscuit trotting across the lawn.
	var d := _spawn("Biscuit", Vector3(4.2, 0, 4.3), PI * 0.5 - 0.35, "walk")
	d.position.y = 0.0
	# Chat interactables on guests.
	for k in GUEST_NAMES:
		var act: Node3D = actors.get(k)
		if act:
			Interactable.attach(act, GUEST_NAMES[k], [
				{"id": "chat", "label": "Chat", "icon": "chat", "minutes": 20.0, "pose": "talk",
				 "needs": {"social": 0.25, "fun": 0.05}, "task": "Talk to Neighbors"},
				{"id": "befriend", "label": "Get to Know", "icon": "heart", "minutes": 30.0, "pose": "talk",
				 "needs": {"social": 0.35}, "task": "Make a New Friend"},
			], Vector3(0.6, 1.7, 0.6), Vector3(0, 0.85, 0), Vector3(0, 0, 0.8))


func _make(key: String) -> Node3D:
	var look: String = PEOPLE[key][0]
	var a: Node3D = SimActor.create(look)
	a.name = key
	root.add_child(a)
	actors[key] = a
	for alias in PEOPLE[key][1]:
		actors[alias] = a
	return a


func _spawn(key: String, pos: Vector3, yaw: float, pose: String) -> Node3D:
	var a := _make(key)
	a.position = pos
	a.rotation.y = yaw
	if a.has_method("set_pose"):
		a.set_pose(pose)
	return a


func _spawn_seated(key: String, pos: Vector3, yaw: float, pose: String, seat_h: float) -> Node3D:
	var a := _make(key)
	a.position = pos
	a.rotation.y = yaw
	if "seat_height" in a:
		a.seat_height = seat_h
	if a.has_method("set_pose"):
		a.set_pose(pose)
	return a


func _seat(key: String, party, seat: String, pose: String) -> Node3D:
	var t: Transform3D = party.world_seat(seat)
	return _spawn_seated(key, t.origin, t.basis.get_euler().y, pose, 0.4375)


func get_actor(key: String) -> Node3D:
	return actors.get(key)
