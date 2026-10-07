extends RefCounted
## Who is at the barbecue and where: family + neighbours, with their
## Interactables (guests can be chatted with).

const Party := preload("res://scripts/locations/backyard/party.gd")
const Gestures := preload("res://scripts/locations/backyard/gestures.gd")
const DOG_POS := Vector3(2.2, 0.0, 2.6)

## key -> [look, aliases]
const PEOPLE := {
	"Jack": ["dad", ["dad"]],
	"Lily": ["bunny_girl", ["bunny_girl"]],
	"Maya": ["cat_girl", ["cat_girl"]],
	"Biscuit": ["beagle", ["beagle", "dog"]],
	"neighbor_1": ["npc_0", ["npc_0"]],
	"neighbor_2": ["npc_1", ["npc_1"]],
	"neighbor_3": ["npc_2", ["npc_2"]],
	"neighbor_4": ["npc_7", ["npc_7"]],
	"neighbor_5": ["npc_6", ["npc_6"]],
	"neighbor_6": ["npc_4", ["npc_4"]],
	"neighbor_7": ["npc_5", ["npc_5"]],
	"neighbor_8": ["npc_3", ["npc_3"]],
}

const GUEST_NAMES := {
	"neighbor_1": "Rosie", "neighbor_2": "Marcus", "neighbor_3": "Edith", "neighbor_4": "Leo",
	"neighbor_5": "Walter", "neighbor_6": "Sam", "neighbor_7": "Nia", "neighbor_8": "June",
}

var actors := {}   # key/alias -> Node3D
var root: Node3D
var gestures


func build(parent: Node3D, party) -> void:
	root = Node3D.new()
	root.name = "Cast"
	parent.add_child(root)
	# Jack at the grill (ref4): behind its right end, body turned to the
	# grate with tongs + spatula over the food, 3/4 to the camera.
	var gb := Basis(Vector3.UP, Party.GRILL_ROT)
	var gf: Vector3 = Party.GRILL_POS + gb * Party.COOK_SPOT
	var gd: Vector3 = Party.GRILL_POS + gb * Vector3(0.0, 0.0, 0.0) - gf
	_spawn("Jack", gf, atan2(gd.x, gd.z) + 0.28, "grill")
	# Sit-down dinner (ref4): the long table runs across the picture with
	# just five diners spaced out along it. Four on the far side face the
	# camera in 3/4 with an empty chair-width between each; one child sits
	# on the near side with his back to us in a gap; the other near chairs
	# stay empty so the chairs and the cloth read.
	_seat("Lily", party, "far_1", "sit_talk", 0.25)
	_seat("neighbor_7", party, "far_2", "sit_talk", 0.15)
	_seat("neighbor_4", party, "far_3", "sit_talk", -0.1)
	_seat("Maya", party, "far_4", "sit_talk", -0.25)
	# Near side, backs to the camera in the gaps between the far diners (ref4:
	# a long-haired neighbour and the blond boy, shoulders over the chair backs).
	_seat("neighbor_8", party, "near_l", "sit_talk", 0.0)
	_seat("neighbor_6", party, "near_r", "sit_talk", 0.0)
	gestures = Gestures.new()
	parent.add_child(gestures)
	# Every diner has one hand busy (burger / glass) and the other forearm
	# resting on the cloth, so arms read on the table instead of in the air.
	gestures.add(actors.get("Lily"), "burger", false, "burger", 0.05, 0.3, true)
	gestures.add(actors.get("neighbor_7"), "drink", true, "", 0.08, 0.3, true)
	gestures.add(actors.get("neighbor_4"), "toast", false, "", 0.05, 0.3, true)
	gestures.add(actors.get("Maya"), "drink", true, "", 0.1, 0.3, true)
	gestures.add(actors.get("neighbor_6"), "burger", false, "burger", 0.0, 0.0, true)
	gestures.add(actors.get("neighbor_8"), "drink", true, "", 0.0, 0.0, true)
	# Jack works the food with tongs (left hand; the pose's spatula stays in
	# the right) and his head turns just enough for the face to read.
	gestures.add(actors.get("Jack"), "tongs", true, "tongs", -0.02, 0.6)
	# On the pergola deck by the lit doors, chatting with plates and drinks.
	var a := _spawn("neighbor_1", Vector3(4.0, 0.375, -3.3), 0.0, "talk")
	var b := _spawn("neighbor_2", Vector3(5.1, 0.375, -3.45), 0.0, "idle")
	a.face(Vector3(6.5, 0, 2.5))
	b.face(Vector3(1.5, 0, 1.0))
	gestures.add(a, "burger", true, "burger")
	gestures.add(b, "drink", false)
	# The two elders on the outdoor sofa by the fire pit, mugs in hand.
	var s0: Transform3D = Party.sofa_seat(0)
	var s1: Transform3D = Party.sofa_seat(1)
	var c := _spawn_seated("neighbor_5", s0.origin, s0.basis.get_euler().y + 0.15, "sit_talk", 0.5)
	gestures.add(c, "mug", true, "", 0.0, 0.4)
	var g := _spawn_seated("neighbor_3", s1.origin, s1.basis.get_euler().y - 0.1, "sit_talk", 0.5)
	gestures.add(g, "mug", false, "", 0.0, 0.5)
	# Biscuit trotting across the lawn between the table and the fire pit.
	var d := _spawn("Biscuit", DOG_POS, -1.3, "walk")
	d.position.y = 0.0
	# (size comes from BODY_SCALE["dog"] in _tune)
	for k in PEOPLE:
		gestures.keep_eyes_open(actors.get(k))
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
	var a := _spawn_seated(key, t.origin, t.basis.get_euler().y + turn, pose, Party.seat_height(seat))
	a.set_meta("diner", true)
	return a


## Proportions for this wide party shot: chibi heads read as a "pile of heads"
## around the table from this distance, so shrink them (bone scale at the
## neck; SimActor never touches the head bone's scale) and slightly shrink the
## bodies so torsos + arms show above the table.
## Heads ~1/4 of the body (ref4 guests are less chibi than the house cast).
const HEAD_SCALE := {"adult": 0.88, "child": 0.94, "dog": 1.0}
## Life-size scales for this shot (shared art rule: adult ~1.75 m, child
## ~70 % of that, beagle's back at a child's knee-to-hip). SimActor clamps
## the household to a "hero minimum" meant for the zoomed-out house view,
## so the resolved scale is overridden here (and seat heights compensated).
const BODY_SCALE := {"adult": 0.96, "child": 0.84, "dog": 0.55}
const LOOK_SCALE := {"dad": 1.04}


func _tune(a: Node3D) -> void:
	if not is_instance_valid(a) or not a.has_method("kind"):
		return
	var k: String = a.kind()
	var want: float = LOOK_SCALE.get(String(a.get("look")), BODY_SCALE.get(k, 1.0))
	if "body_scale" in a:
		a.body_scale = want
	var sk = a.get("skeleton")
	if sk is Skeleton3D and "_s" in a and absf(float(a.get("_s")) - want) > 0.001:
		a.set("_s", want)
		(sk as Skeleton3D).scale = Vector3.ONE * want
	var hb = a.get("b_head")
	if sk is Skeleton3D and hb is int and hb >= 0 and k != "dog":
		(sk as Skeleton3D).set_bone_pose_scale(hb, Vector3.ONE * float(HEAD_SCALE.get(k, 1.0)))


func get_actor(key: String) -> Node3D:
	return actors.get(key)
