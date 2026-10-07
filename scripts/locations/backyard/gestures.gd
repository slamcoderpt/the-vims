extends Node
## Party gestures layered on top of SimActor poses (runs after the actors'
## own _process via process_priority): seated diners raise a glass, hold a
## burger up, or lift a mug, with the held item as a small voxel prop that
## stays upright in the hand. Purely cosmetic; the SimActor contract is
## untouched (we only overwrite arm bone rotations after it has applied).

const VS := 0.05

## actor -> {mode, arm, fore, prop, side}
var _items: Array = []
var _t := 0.0
static var _meshes := {}


func _init() -> void:
	name = "PartyGestures"
	process_priority = 100


## mode: "toast" (glass raised high), "drink" (glass at chest), "burger"
## (burger held up near the mouth), "mug" (mug at chest), "cheer" (both arms).
func add(actor: Node3D, mode: String, left := false, item := "") -> void:
	if actor == null:
		return
	if item == "":
		item = {"toast": "glass", "drink": "glass", "burger": "burger", "mug": "mug", "cheer": "glass"}.get(mode, "glass")
	_items.append({"a": actor, "mode": mode, "left": left, "item": item, "mi": null,
		"ph": randf_range(0.0, TAU)})


func _process(delta: float) -> void:
	_t += delta
	for it: Dictionary in _items:
		var a: Node3D = it.a
		if not is_instance_valid(a):
			continue
		var sk = a.get("skeleton")
		if not (sk is Skeleton3D):
			continue
		var skel: Skeleton3D = sk
		var left: bool = it.left
		var arm: int = a.get("b_arm_l") if left else a.get("b_arm_r")
		var fore: int = a.get("b_fore_l") if left else a.get("b_fore_r")
		if arm < 0 or fore < 0:
			continue
		var m := -1.0 if left else 1.0
		var w := sin(_t * 1.7 + float(it.ph))
		var arm_e := Vector3.ZERO
		var fore_e := Vector3.ZERO
		match String(it.mode):
			"toast":
				arm_e = Vector3(-2.1 + 0.08 * w, 0.0, -0.32 * m)
				fore_e = Vector3(-0.55, 0.0, 0.0)
			"cheer":
				arm_e = Vector3(-2.3 + 0.1 * w, 0.0, -0.45 * m)
				fore_e = Vector3(-0.3, 0.0, 0.0)
			"burger":
				arm_e = Vector3(-1.3 + 0.05 * w, 0.2 * m, -0.12 * m)
				fore_e = Vector3(-1.45, 0.0, 0.0)
			"mug", "drink":
				arm_e = Vector3(-0.75 + 0.04 * w, 0.15 * m, -0.18 * m)
				fore_e = Vector3(-1.2, 0.0, 0.0)
		skel.set_bone_pose_rotation(arm, Quaternion.from_euler(arm_e))
		skel.set_bone_pose_rotation(fore, Quaternion.from_euler(fore_e))
		if String(it.mode) == "cheer":
			var arm2: int = a.get("b_arm_r") if left else a.get("b_arm_l")
			var fore2: int = a.get("b_fore_r") if left else a.get("b_fore_l")
			if arm2 >= 0:
				skel.set_bone_pose_rotation(arm2, Quaternion.from_euler(Vector3(-1.0, -0.2 * m, 0.2 * m)))
				skel.set_bone_pose_rotation(fore2, Quaternion.from_euler(Vector3(-1.1, 0.0, 0.0)))
		# Held item: in skeleton space, at the hand, kept upright.
		var mi: MeshInstance3D = it.mi
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = _mesh(String(it.item))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skel.add_child(mi)
			it.mi = mi
		var meta = a.get("_meta")
		var fl: float = 0.3
		if meta is Dictionary:
			fl = float(meta.get("fore_len", 0.3))
		var gp := skel.get_bone_global_pose(fore)
		var hand := gp * Vector3(0.0, -fl + 0.01, 0.045)
		mi.transform = Transform3D(Basis(), hand)


static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var vb := VoxelBuilder.new()
	vb.jitter = 0.03
	match kind:
		"glass":
			# Amber drink in a clear tumbler, foam on top, lemon slice.
			vb.box(Vector3i(-1, -1, -1), Vector3i(3, 4, 3), Color("f2a63a"))
			vb.box(Vector3i(-1, -2, -1), Vector3i(3, 1, 3), Color("e9eef0"))
			vb.box(Vector3i(-1, 3, -1), Vector3i(3, 1, 3), Color("fff6e2"))
			vb.set_v(Vector3i(1, 4, 1), Color("ffe14a"))
		"burger":
			vb.box(Vector3i(-2, -1, -1), Vector3i(4, 1, 3), Color("d9984e"))
			vb.box(Vector3i(-2, 0, -1), Vector3i(4, 1, 3), Color("6cb04a"))
			vb.box(Vector3i(-2, 1, -1), Vector3i(4, 1, 3), Color("5a2e18"))
			vb.box(Vector3i(-2, 2, -1), Vector3i(4, 1, 3), Color("f2c22a"))
			vb.box(Vector3i(-2, 3, -1), Vector3i(4, 2, 3), Color("e3a85a"))
			vb.set_v(Vector3i(-1, 5, 0), Color("f7e9c8"))
		"mug":
			vb.box(Vector3i(-1, -2, -1), Vector3i(3, 4, 3), Color("f3efe6"))
			vb.box(Vector3i(-1, 2, -1), Vector3i(3, 1, 3), Color("7a4a2a"))
			vb.box(Vector3i(2, -1, 0), Vector3i(1, 2, 1), Color("f3efe6"))
	var mesh := vb.build(VS * 0.8, Vector3.ZERO)
	_meshes[kind] = mesh
	return mesh
