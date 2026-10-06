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
	a.face(face_to)
	a.set_pose(pose)
	actors[key] = a
	return a


func build(parent: Node3D, stalls, stage) -> void:
	# --- Family (positions match the reference composition).
	var vendor_pos: Vector3 = stalls.vendor_spot
	var jack := spawn(parent, "Jack", "dad", Vector3(-1.1, 0, 2.3), Vector3(-3.4, 0, 5.4), "talk")
	var lily := spawn(parent, "Lily", "bunny_girl", Vector3(0.2, 0, 1.65), Vector3(-0.5, 0, 8.0), "talk")
	_hold(lily, "candy_apple", "fore_r")
	var dog := spawn(parent, "Biscuit", "beagle", Vector3(-0.5, 0, 2.7), Vector3(0.6, 0, 3.0), "idle")
	dog.rotation.y += 0.0
	var maya := spawn(parent, "Maya", "cat_girl", Vector3(3.0, 0, 2.7), Vector3(2.0, 0, 9.0), "stand_type")
	_hold(maya, "fox_plush", "torso")
	# --- Stall keepers.
	spawn(parent, "vendor", "npc_6", vendor_pos, jack.position, "talk")
	var g: Node3D = stalls.game
	spawn(parent, "game_host", "npc_5", g.transform * Vector3(0.0, 0, -0.35), g.transform * Vector3(0, 0, 3.0), "wave")
	var cr: Node3D = stalls.crafts
	spawn(parent, "crafter", "npc_6", cr.transform * Vector3(0.1, 0, -0.85), cr.transform * Vector3(0, 0, 3.0), "talk")
	# --- Guitarist on stage.
	var gt := spawn(parent, "guitarist", "npc_1", stage.performer_spot, Vector3(0.5, 0, 8.0), "stand_type")
	_hold(gt, "guitar", "torso")
	# --- Townsfolk.
	var folk := [
		["npc_7", Vector3(-0.9, 0, -4.8), Vector3(-0.4, 0, 6.0), "walk"],
		["npc_5", Vector3(-2.6, 0, -1.6), Vector3(-2.8, 0, 6.0), "walk"],
		["npc_5", Vector3(5.6, 0, -1.4), Vector3(4.0, 0, 1.0), "talk"],
		["npc_1", Vector3(7.8, 0, -5.8), Vector3(9.2, 0, -7.4), "talk"],
		["npc_3", Vector3(-1.7, 0, -2.5), Vector3(-0.8, 0, -2.9), "talk"],
		["npc_0", Vector3(-0.8, 0, -2.9), Vector3(-1.7, 0, -2.5), "idle"],
		["npc_4", Vector3(2.6, 0, -5.4), Vector3(2.0, 0, 6.0), "walk"],
		["npc_3", Vector3(-4.6, 0, -3.8), Vector3(-5.8, 0, -5.4), "idle"],
	]
	_far_folk(parent)
	var i := 1
	for f: Array in folk:
		var key := "neighbor_%d" % i
		spawn(parent, key, f[0], f[1], f[2], f[3])
		npc_keys.append(key)
		i += 1
	# Seated at the picnic table (bench tops at 0.5 m).
	var seated := [
		["npc_2", Vector3(2.95, 0, -3.45), Vector3(2.95, 0, 0.0)],
		["npc_6", Vector3(3.75, 0, -2.2), Vector3(3.75, 0, -6.0)],
	]
	for s: Array in seated:
		var key := "neighbor_%d" % i
		spawn(parent, key, s[0], s[1], s[2], "sit_talk", 0.5)
		npc_keys.append(key)
		i += 1


## Far crowd (static, one mesh): stage audience, fountain loiterers, people
## strolling in front of the town hall.
func _far_folk(parent: Node3D) -> void:
	var F := preload("res://scripts/locations/festival/folk.gd").new()
	var seed := 1
	# Stage audience (backs to the camera, some turned).
	for p in [[3.4, -9.6, 180], [4.3, -9.9, 160], [5.2, -9.5, 200], [6.1, -9.8, 180], [7.0, -9.4, 220],
			[7.9, -9.9, 180], [4.8, -8.7, 150], [6.6, -8.6, 190], [8.6, -8.9, 240], [3.0, -8.4, 120]]:
		F.add(p[0] - 0.3, p[1] + 1.9, p[2], seed % 4 == 0, seed)
		seed += 1
	# Around the fountain and across the back of the square.
	for p in [[-2.2, -9.4, 60], [1.9, -9.0, 300], [-1.4, -11.2, 0], [1.0, -12.0, 90], [-3.2, -12.6, 30],
			[2.6, -13.4, 0], [-0.2, -14.6, 270], [-4.6, -11.6, 90], [-6.4, -8.0, 0], [-7.2, -11.0, 45],
			[-5.6, -14.6, 0], [3.8, -15.0, 180], [-2.4, -16.0, 0], [1.6, -16.8, 90], [9.6, -11.6, 270],
			[-8.4, -6.2, 30], [5.0, -6.8, 330],
			[-2.6, -7.2, 45], [-1.9, -6.3, 225], [-3.6, -6.4, 120], [1.6, -6.6, 200]]:
		F.add(p[0], p[1], p[2], seed % 5 == 0, seed)
		seed += 1
	F.build(parent)


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
			mi.position = Vector3(0.0, hand - 0.02, 0.03)
			mi.rotation = Vector3(1.1, 0, -0.6)
		"fox_plush":
			mi.position = Vector3(0.0, 0.1, 0.17)
			mi.rotation = Vector3(0, 0, 0)
		"guitar":
			mi.position = Vector3(0.0, 0.14, 0.17)
			mi.rotation = Vector3(0, 0, deg_to_rad(-55.0))
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
