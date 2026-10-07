extends RefCounted
## Who is at the barbecue and where: family + neighbours, with their
## Interactables (guests can be chatted with).

const Party := preload("res://scripts/locations/backyard/party.gd")
const Gestures := preload("res://scripts/locations/backyard/gestures.gd")
const DOG_POS := Vector3(3.45, 0.0, 1.5)

## key -> [look, aliases]
const PEOPLE := {
	"Jack": ["dad", ["dad"]],
	"Lily": ["bunny_girl", ["bunny_girl"]],
	"Maya": ["cat_girl", ["cat_girl"]],
	"Biscuit": ["beagle", ["beagle", "dog"]],
	"neighbor_1": ["npc_5", ["npc_5"]],
	"neighbor_2": ["npc_1", ["npc_1"]],
	"neighbor_3": ["npc_0", ["npc_0"]],
	"neighbor_4": ["npc_2", ["npc_2"]],
	"neighbor_5": ["npc_6", ["npc_6"]],
	"neighbor_6": ["npc_4", ["npc_4"]],
	"neighbor_7": ["npc_7", ["npc_7"]],
	"neighbor_8": ["npc_3", ["npc_3"]],
}

const GUEST_NAMES := {
	"neighbor_1": "Nia", "neighbor_2": "Marcus", "neighbor_3": "Rosie", "neighbor_4": "Edith",
	"neighbor_5": "Walter", "neighbor_6": "Sam", "neighbor_7": "Leo", "neighbor_8": "June",
}

var actors := {}   # key/alias -> Node3D
var root: Node3D
var gestures


func build(parent: Node3D, party) -> void:
	root = Node3D.new()
	root.name = "Cast"
	parent.add_child(root)
	# Jack at the grill.
	# Beside the grill (its right end, table side) so his whole body reads in
	# 3/4 view instead of hiding behind the firebox.
	var gf: Vector3 = Party.GRILL_POS + Vector3(0.8, 0.0, -0.5)
	_spawn("Jack", gf, 0.0, "grill").face(Party.GRILL_POS + Vector3(0.0, 0.0, 0.45))
	# Table: diners turned toward the camera on the far side and the ends,
	# two guests with their backs to us on the near side (ref4).
	_seat("Lily", party, "end_l", "sit_talk", -1.25)
	_seat("neighbor_7", party, "far_l", "sit_talk")
	_seat("neighbor_4", party, "far_m", "sit_talk")
	_seat("Maya", party, "far_r", "sit_talk", -0.3)
	_seat("neighbor_6", party, "near_l", "sit_talk", -0.6)
	_seat("neighbor_3", party, "near_r", "sit_talk", 0.8)
	gestures = Gestures.new()
	parent.add_child(gestures)
	gestures.add(actors.get("Lily"), "burger", false)
	gestures.add(actors.get("neighbor_7"), "toast", true)
	gestures.add(actors.get("neighbor_4"), "drink", false)
	gestures.add(actors.get("Maya"), "burger", true)
	gestures.add(actors.get("neighbor_6"), "drink", false)
	gestures.add(actors.get("neighbor_3"), "drink", true)
	# On the deck, chatting with plates and drinks.
	var a := _spawn("neighbor_1", Vector3(4.3, 0.375, -3.4), 0.0, "talk")
	var b := _spawn("neighbor_2", Vector3(6.9, 0.375, -3.6), 0.0, "idle")
	a.face(Vector3(6.0, 0, 1.5))
	b.face(Vector3(3.6, 0, 0.5))
	gestures.add(a, "burger", true, "burger")
	gestures.add(b, "toast", false)
	# Lounge by the fire pit.
	var c := _spawn_seated("neighbor_5", Vector3(6.55, 0, 1.05), -PI * 0.5 - 0.25, "sit_talk", 0.5)
	var e := _spawn_seated("neighbor_8", Vector3(6.55, 0, 2.5), -PI * 0.5 + 0.1, "sit", 0.5)
	gestures.add(c, "mug", true)
	gestures.add(e, "mug", false)
	# Biscuit trotting across the lawn between the table and the fire pit.
	var d := _spawn("Biscuit", DOG_POS, -PI * 0.36, "walk")
	d.position.y = 0.0
	d.scale = Vector3.ONE * 0.86
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
	_tune.call_deferred(a)
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


func _seat(key: String, party, seat: String, pose: String, turn := 0.0) -> Node3D:
	var t: Transform3D = party.world_seat(seat)
	var a := _spawn_seated(key, t.origin, t.basis.get_euler().y + turn, pose, 0.4375)
	a.set_meta("diner", true)
	return a


## Proportions for this wide party shot: chibi heads read as a "pile of heads"
## around the table from this distance, so shrink them (bone scale at the
## neck; SimActor never touches the head bone's scale) and slightly shrink the
## bodies so torsos + arms show above the table.
const HEAD_SCALE := {"adult": 0.86, "child": 0.9, "dog": 1.0}
## Diners are the heroes of the shot: a bit larger than the rest of the cast.
const DINER_BOOST := 1.14
const BODY_SCALE := {"adult": 1.2, "child": 1.26, "dog": 1.0}


func _tune(a: Node3D) -> void:
	if not is_instance_valid(a) or not a.has_method("kind"):
		return
	var k: String = a.kind()
	if "body_scale" in a:
		a.body_scale = BODY_SCALE.get(k, 1.0) * (DINER_BOOST if a.has_meta("diner") else 1.0)
	var sk = a.get("skeleton")
	var hb = a.get("b_head")
	if sk is Skeleton3D and hb is int and hb >= 0 and k != "dog":
		(sk as Skeleton3D).set_bone_pose_scale(hb, Vector3.ONE * float(HEAD_SCALE.get(k, 1.0)))


func get_actor(key: String) -> Node3D:
	return actors.get(key)
