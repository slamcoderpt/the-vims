extends RefCounted
## The family plus townsfolk filling the square. Held props (guitar, candy
## apple, fox plush) are small voxel meshes on BoneAttachment3D nodes.

const K := preload("res://scripts/locations/festival/kit.gd")
const U := 1.0 / 16.0

var actors := {}      # key -> SimActor
var npc_keys: Array[String] = []
var _prop_meshes := {}


func spawn(parent: Node3D, key: String, look: String, pos: Vector3, face_to: Vector3, pose := "idle", seat := -1.0) -> SimActor:
	var a := SimActor.create(look)
	a.name = key
	if seat > 0.0:
		a.seat_height = seat
	a.position = pos
	parent.add_child(a)
	_life_size(a)
	a.face(face_to)
	a.set_pose(pose)
	actors[key] = a
	return a


## Art direction (fixed): adult ~1.75 m (desk + monitor), child ~70 % of
## that, beagle's back at a child's knee-to-hip; stalls are real-world size.
const LIFE_H := {"adult": 1.76, "child": 1.24, "dog": 0.8}


## Scale an actor to real-world height. body_scale is clamped to the hero
## minimum inside SimActor, so the remainder goes on the node scale.
func _life_size(a: SimActor) -> void:
	var m: Dictionary = a._meta
	var mh: float = float(m.get("height", 0.0))
	if mh <= 0.01 or a.skeleton == null:
		return
	var want: float = LIFE_H.get(String(m.get("kind", "adult")), 1.76) / mh
	a.body_scale = want
	var eff: float = a.skeleton.scale.x
	if want / eff < 0.999:
		a.scale = Vector3.ONE * (want / eff)


func build(parent: Node3D, stalls, stage) -> void:
	# --- Family (positions match the reference composition).
	var vendor_pos: Vector3 = stalls.vendor_spot
	# Heroes ~1/4 screen tall and spaced apart so faces never overlap:
	# Jack at the treats counter, Biscuit in front of him, Lily centre, Maya right.
	var jack := spawn(parent, "Jack", "dad", Vector3(-2.75, 0, 0.15), Vector3(-1.6, 0, 7.4), "talk")
	var lily := spawn(parent, "Lily", "bunny_girl", Vector3(-0.45, 0, -0.4), Vector3(1.6, 0, 8.4), "talk")
	_hold(lily, "candy_apple", "fore_r")
	var dog := spawn(parent, "Biscuit", "beagle", Vector3(-1.75, 0, 0.6), Vector3(0.6, 0, 4.6), "idle")
	var maya := spawn(parent, "Maya", "cat_girl", Vector3(1.85, 0, 0.15), Vector3(-1.6, 0, 10.4), "talk")
	_hold(maya, "fox_plush", "torso")
	# The standard game camera looks down ~35-40 deg at the heroes; a slight
	# lean back (pivot at the feet) lifts the faces out from under the hats.
	maya.rotation.x = deg_to_rad(-6.0)
	jack.rotation.x = deg_to_rad(-5.0)
	lily.rotation.x = deg_to_rad(-4.0)
	# --- Stall keepers.
	spawn(parent, "vendor", "npc_6", vendor_pos, jack.position, "talk")
	var g: Node3D = stalls.game
	spawn(parent, "game_host", "npc_5", g.transform * Vector3(0.0, 0, -0.35), g.transform * Vector3(0, 0, 3.0), "wave")
	var cr: Node3D = stalls.crafts
	spawn(parent, "crafter", "npc_6", cr.transform * Vector3(0.1, 0, -0.85), cr.transform * Vector3(0, 0, 3.0), "talk")
	# --- Guitarist on stage.
	# Faces the camera (front-on, guitar across the body), lit by the stage wash.
	var gt := spawn(parent, "guitarist", "npc_1", stage.performer_spot, Vector3(0.0, 0, 14.0), "stand_type")
	_hold(gt, "guitar", "torso")
	# --- Townsfolk.
	# Animated townsfolk spaced along the walkway and round the stalls (three
	# depth bands; nobody stands on the open path between Lily and the fountain).
	var folk := [
		["npc_7", Vector3(-1.0, 0, -6.6), Vector3(-0.2, 0, 6.0), "walk"],
		["npc_5", Vector3(-3.9, 0, -5.6), Vector3(-5.2, 0, -3.4), "talk"],
		["npc_3", Vector3(5.9, 0, -5.0), Vector3(5.1, 0, -5.7), "talk"],
		["npc_0", Vector3(5.1, 0, -5.7), Vector3(5.9, 0, -5.0), "idle"],
		["npc_4", Vector3(0.9, 0, -9.0), Vector3(1.4, 0, 6.0), "walk"],
		# r12: a chatting pair filling the open cobbles right of Lily.
		["npc_2", Vector3(2.2, 0, -2.3), Vector3(3.1, 0, -1.6), "talk"],
		["npc_4", Vector3(3.0, 0, -1.7), Vector3(2.0, 0, -2.1), "talk"],
	]
	_far_folk(parent, stage.node.transform)
	var i := 1
	for f: Array in folk:
		var key := "neighbor_%d" % i
		spawn(parent, key, f[0], K.dv(f[1]), K.dv(f[2]), f[3])
		npc_keys.append(key)
		i += 1
	# Seated at the picnic table (bench tops at 0.5 m).
	var seated := [
		["npc_2", Vector3(-4.4, 0, K.dz(-8.0) - 0.25), Vector3(-4.4, 0, -4.0)],
		["npc_6", Vector3(-3.7, 0, K.dz(-8.0) + 1.0), Vector3(-3.7, 0, -11.0)],
	]
	for s: Array in seated:
		var key := "neighbor_%d" % i
		spawn(parent, key, s[0], K.dv(s[1]), K.dv(s[2]), "sit_talk", 0.5)
		npc_keys.append(key)
		i += 1


## Static crowd (one mesh, one draw call): stage audience, fountain
## loiterers, people strolling between the stalls (mid ground) and in front
## of the town hall (far). Gives the square three depth layers of people.
func _far_folk(parent: Node3D, stage_xf: Transform3D) -> void:
	var F := preload("res://scripts/locations/festival/folk.gd").new()
	var seed := 1
	# Stage audience, placed in the stage's own frame (rows on the cobbles
	# in front of the deck, facing the guitarist; a few turned to chat).
	var sb := stage_xf.basis.orthonormalized()
	var sy := rad_to_deg(sb.get_euler().y)
	for p in [[-1.1, 2.2, 0], [-0.2, 2.5, 10], [0.6, 2.3, -8], [1.7, 2.1, 15],
			[-1.1, 3.3, 25], [0.2, 3.5, 0], [1.3, 3.2, -30], [2.4, 3.0, 60]]:
		var w: Vector3 = stage_xf.origin + sb * Vector3(p[0], 0, p[1])
		F.add(w.x, w.z, 180.0 + sy + p[2], seed % 4 == 0, seed)
		seed += 1
	# Around the fountain (0.2, -9.6) and across the back of the square.
	for p in [[-4.9, -9.0, 60], [0.2, -9.6, 300], [-3.4, -11.2, 20], [2.0, -12.4, 90],
			[-3.9, -13.6, 30], [0.8, -14.8, 0], [-0.9, -16.5, 270],
			[-5.8, -14.8, 90], [3.2, -16.6, 180], [-2.6, -18.6, 0], [1.6, -19.8, 90],
			[-7.4, -17.6, 45], [5.6, -19.4, 270], [-4.4, -20.6, 0]]:
		if not _on_stage(stage_xf, p[0], K.dz(p[1])):
			F.add(p[0], K.dz(p[1]), p[2], seed % 5 == 0, seed)
		seed += 1
	# Mid ground: browsing the side stalls, queueing at the game booth,
	# chatting in pairs at the edges of the walkway.
	for p in [[-6.4, -5.6, 90, false], [-7.0, -7.4, 0, false], [-6.7, -6.6, 270, true],
			[7.2, -4.0, 270, false],
			[9.4, -6.0, 300, false], [9.8, -9.6, 270, false],
			[-0.6, -7.4, 135, true], [6.3, -8.4, 200, false], [7.0, -9.0, 30, true],
			# Round 9 (wider camera): a scattered, smaller crowd filling the
			# open cobbles between the heroes, fountain, game booth and stage.
			[8.2, -4.0, 200, false], [9.0, -4.6, 120, false],
			[4.4, -6.4, 0, false],
			[0.2, -13.6, 180, false],
			[-4.6, -11.6, 220, false], [10.4, -8.0, 300, true]]:
		if not _on_stage(stage_xf, p[0], K.dz(p[1])):
			F.add(p[0], K.dz(p[1]), p[2], p[3], seed)
		seed += 1
	F.build(parent, U * 1.0)


## True when (x, z) falls on the stage footprint (plus a small margin).
func _on_stage(stage_xf: Transform3D, x: float, z: float) -> bool:
	var sb := stage_xf.basis.orthonormalized()
	var l: Vector3 = sb.inverse() * (Vector3(x, 0, z) - stage_xf.origin)
	return absf(l.x) < 2.6 and absf(l.z) < 1.5


func get_actor(key: String) -> Node3D:
	if actors.has(key):
		return actors[key]
	match key:
		"dad": return actors.get("Jack")
		"bunny_girl": return actors.get("Lily")
		"cat_girl": return actors.get("Maya")
		"beagle", "dog": return actors.get("Biscuit")
		"cashier", "shopkeeper": return actors.get("vendor")
	return null


# ------------------------------------------------------------------ held props

func _hold(a: SimActor, prop: String, bone: String) -> void:
	if a.skeleton == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	a.skeleton.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = _prop_mesh(prop)
	var meta: Dictionary = a._meta
	var hand: float = -float(meta.get("fore_len", 0.22)) + 0.02
	match prop:
		"candy_apple":
			# Held up beside the face (not in front of the mouth).
			mi.position = Vector3(0.03, hand - 0.03, 0.05)
			mi.rotation = Vector3(0.35, 0, -0.25)
		"fox_plush":
			# Hugged against her side, turned 3/4 so its face reads.
			mi.position = Vector3(0.15, 0.02, 0.15)
			mi.rotation = Vector3(0, -0.5, 0)
			mi.scale = Vector3.ONE * 0.9
		"guitar":
			mi.position = Vector3(0.02, 0.1, 0.17)
			mi.rotation = Vector3(0, 0, deg_to_rad(-68.0))
	att.add_child(mi)


func _prop_mesh(prop: String) -> ArrayMesh:
	if _prop_meshes.has(prop):
		return _prop_meshes[prop]
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var origin := Vector3.ZERO
	match prop:
		"candy_apple":
			K.box(vb, 0, 0, 0, 1, 3, 1, Color("e8d4a0"))
			K.box(vb, -1, 3, -1, 3, 3, 3, Color("c0141c"))
			vb.set_v(Vector3i(-1, 5, 1), Color("ff6a6a"))
			vb.set_v(Vector3i(0, 6, 0), Color("6a3a1a"))
			origin = Vector3(0.5, 0, 0.5)
		"fox_plush":
			var o := Color("ec7a26")
			var od := Color("c85e1a")
			var wht := Color("fbf3e6")
			var blk := Color("2a1e1a")
			# Body + legs.
			K.box(vb, 0, 0, 0, 5, 5, 4, o)
			K.box(vb, 1, 1, 4, 3, 4, 1, wht)
			K.box(vb, 0, 0, 4, 2, 2, 1, od)
			K.box(vb, 3, 0, 4, 2, 2, 1, od)
			# Head with white cheeks / muzzle.
			K.box(vb, -1, 5, -1, 7, 5, 5, o)
			K.box(vb, -1, 5, 4, 2, 2, 1, wht)
			K.box(vb, 4, 5, 4, 2, 2, 1, wht)
			K.box(vb, 1, 5, 4, 3, 2, 2, wht)
			vb.set_v(Vector3i(2, 6, 5), blk)
			vb.set_v(Vector3i(0, 8, 4), blk)
			vb.set_v(Vector3i(4, 8, 4), blk)
			# Ears.
			K.box(vb, -1, 10, 1, 2, 2, 2, o)
			K.box(vb, 4, 10, 1, 2, 2, 2, o)
			vb.set_v(Vector3i(-1, 12, 1), blk)
			vb.set_v(Vector3i(5, 12, 1), blk)
			# Tail.
			K.box(vb, 5, 1, 0, 3, 3, 3, o)
			K.box(vb, 8, 2, 0, 1, 2, 3, wht)
			origin = Vector3(2.5, 5, 2.5)
		"guitar":
			var body := Color("c8783a")
			K.box(vb, 0, 0, 0, 8, 6, 2, body)
			K.box(vb, 1, 6, 0, 6, 4, 2, body)
			K.box(vb, 3, 4, 2, 2, 2, 1, Color("2a1a10"))
			K.box(vb, 2, 1, 2, 4, 1, 1, Color("3a2416"))
			K.box(vb, 3, 10, 0, 2, 12, 1, Color("5a3a22"))
			K.box(vb, 2, 22, 0, 4, 3, 1, Color("2a2420"))
			origin = Vector3(4, 8, 1)
	var m := K.mesh(vb, U, origin, -999)
	_prop_meshes[prop] = m
	return m
