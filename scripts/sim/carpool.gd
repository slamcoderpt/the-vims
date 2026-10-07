extends Node3D
## The carpool / school bus that picks a sim up at the start of a shift and
## drops them off afterwards (Sims 3 rabbit-hole commute). A small voxel
## vehicle that drives in along the street, waits, and drives off; the mesh is
## built once and shared. SimWorld spawns one per pickup / drop-off.

const CAR_VOX := 0.1
## "car" (yellow carpool) or "bus" (school bus).
var kind := "car"
## Where it stops (world), and the street direction it drives along.
var stop := Vector3.ZERO
var dir := Vector3(1, 0, 0)
## Real seconds it waits at the stop (scaled by the game speed).
var wait := 2.5
var _t := 0.0
var _phase := 0   # 0 arrive, 1 wait, 2 leave
const DRIVE := 9.0     # metres driven in / out
const DRIVE_T := 1.6   # seconds for that

static var _meshes := {}


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(kind)
	add_child(mi)
	look_at_dir()
	global_position = stop - dir * DRIVE
	set_process(true)


func look_at_dir() -> void:
	# The model's length runs along +x.
	rotation.y = atan2(-dir.z, dir.x)


func _process(delta: float) -> void:
	var mult := 1.0 if Game.speed <= 1 else float(Game.speed)
	if Game.speed == 0:
		mult = 0.0
	_t += delta * mult
	match _phase:
		0:
			var k := clampf(_t / DRIVE_T, 0.0, 1.0)
			k = 1.0 - pow(1.0 - k, 2.0)
			global_position = stop - dir * DRIVE * (1.0 - k)
			if _t >= DRIVE_T:
				_phase = 1
				_t = 0.0
		1:
			global_position = stop + Vector3(0, sin(_t * 30.0) * 0.006, 0)
			if _t >= wait:
				_phase = 2
				_t = 0.0
		2:
			var k := clampf(_t / DRIVE_T, 0.0, 1.0)
			global_position = stop + dir * DRIVE * k * k
			if _t >= DRIVE_T:
				queue_free()


static func mesh_for(k: String) -> ArrayMesh:
	if _meshes.has(k):
		return _meshes[k]
	var vb := VoxelBuilder.new()
	vb.jitter = 0.05
	var body := Color("f2c230") if k == "car" else Color("f0a020")
	var dark := Color("2b2f3a")
	var glass := Color("9fd3ea")
	var trim := Color("e8e4dc")
	var L := 24 if k == "car" else 40
	var W := 11 if k == "car" else 13
	var H := 7 if k == "car" else 13
	# chassis
	vb.box(Vector3i(0, 2, 0), Vector3i(L, 4, W), body)
	# cabin
	var c0 := 5 if k == "car" else 2
	var c1 := L - 6 if k == "car" else L - 1
	vb.box(Vector3i(c0, 6, 1), Vector3i(c1 - c0, H - 4, W - 2), body)
	# windows (both sides + front / back)
	for x in range(c0 + 1, c1 - 1):
		if (x - c0) % 6 == 5:
			continue
		for y in range(7, 5 + H - 4):
			vb.set_v(Vector3i(x, y, 0), glass)
			vb.set_v(Vector3i(x, y, W - 1), glass)
	for z in range(2, W - 2):
		for y in range(7, 5 + H - 4):
			vb.set_v(Vector3i(c1, y, z), glass)
			vb.set_v(Vector3i(c0 - 1, y, z), glass)
	# roof sign / stripe
	if k == "car":
		vb.box(Vector3i(c0 + 5, H + 2, W / 2 - 2), Vector3i(4, 2, 4), trim)
		vb.set_v(Vector3i(c0 + 6, H + 3, W / 2), Color("ee4a3c"))
	else:
		vb.box(Vector3i(0, 5, 0), Vector3i(L, 1, 1), dark)
		vb.box(Vector3i(0, 5, W - 1), Vector3i(L, 1, 1), dark)
	# bumpers + lights
	vb.box(Vector3i(-1, 2, 1), Vector3i(1, 2, W - 2), trim)
	vb.box(Vector3i(L, 2, 1), Vector3i(1, 2, W - 2), trim)
	vb.set_v(Vector3i(L, 4, 1), Color("fff2b0"), true)
	vb.set_v(Vector3i(L, 4, W - 2), Color("fff2b0"), true)
	vb.set_v(Vector3i(-1, 4, 1), Color("ff5a4a"), true)
	vb.set_v(Vector3i(-1, 4, W - 2), Color("ff5a4a"), true)
	# wheels
	for wx in [3, L - 7]:
		for wz in [-1, W - 2]:
			vb.box(Vector3i(wx, 0, wz), Vector3i(4, 3, 3), dark)
			vb.set_v(Vector3i(wx + 1, 1, wz if wz < 0 else wz + 2), Color("9aa0aa"))
	var m := vb.build(CAR_VOX, Vector3(L * 0.5, 0, W * 0.5))
	_meshes[k] = m
	return m
