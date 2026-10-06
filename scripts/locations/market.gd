extends Node3D
## "Fresh & Local" grocery market interior (ref5_grocery_market).
##
##   Camera looks down -Z into the store from the entrance.
##   Left  (x < -2): produce: tiered wall racks, chalkboard, crate islands.
##   Back  (z ~ -10.5): glowing dairy / drinks fridges under daylight windows.
##   Right (x > 1.6): gondola aisles of packaged goods, Bakery corner.
##   Right front: checkout counter with register and cashier.
##   Centre: the family (Jack with the cart + Biscuit in it, Lily, Maya).
##
## API: build(), apply_preset(name), camera_home(), lighting_profile(),
##      get_actor(name) -> SimActor (household names, looks, "cashier", "shopper_N").

const Kit := preload("res://scripts/locations/market/kit.gd")
const Fx := preload("res://scripts/locations/market/fixtures.gd")
const Produce := preload("res://scripts/locations/market/produce.gd")
const Shell := preload("res://scripts/locations/market/shell.gd")
const Stands := preload("res://scripts/locations/market/stands.gd")

const U := 0.0625
const P := 0.03125

var actors := {}
var _cart: MeshInstance3D
var _halo_pts := []
var _frames := 0


# =================================================================== API

func build() -> void:
	var t0 := Time.get_ticks_msec()
	Shell.build(self, _halo_pts)
	Stands.build(self, _halo_pts)
	if not _halo_pts.is_empty():
		add_child(Kit.halos(_halo_pts))
	_spawn_people()
	_stage()
	if OS.get_environment("VIMS_STATS") != "":
		print("MARKET_BUILD_MS ", Time.get_ticks_msec() - t0)


func camera_home() -> Dictionary:
	return {"target": Vector3(0.2, 1.4, 1.0), "yaw": 0.0, "pitch": 10.0, "distance": 4.75, "fov": 46.0}


func lighting_profile() -> Dictionary:
	return {
		"sun_heading": 215.0, "sun_elev": 58.0, "sun_energy": 1.1,
		"ambient_day": Color(1.0, 0.88, 0.74), "ambient_energy": 0.62,
		"ambient_night": Color(0.75, 0.62, 0.5), "ambient_night_energy": 0.7,
		"lamp_night_mult": 1.2,
		"sky_day": Color(0.36, 0.27, 0.2), "sky_night": Color(0.2, 0.14, 0.1),
		"fog_day": Color(0.98, 0.9, 0.78), "fog_night": Color(0.4, 0.3, 0.22), "fog_density": 0.004,
		"exposure": 1.02,
		"shadow_distance": 24.0,
		"post": {"focus_y": 0.52, "band": 0.2, "falloff": 0.26, "blur_px": 6.0, "top_boost": 0.9,
			"saturation": 1.2, "contrast": 1.1, "tint": Vector3(1.03, 1.0, 0.94), "vignette": 0.2},
	}


func get_actor(key: String) -> SimActor:
	return actors.get(key, null)


func apply_preset(_preset: String) -> void:
	_stage()


# =================================================================== people

func _spawn_people() -> void:
	for look: String in ["dad", "bunny_girl", "cat_girl", "beagle"]:
		var a := SimActor.create(look)
		add_child(a)
		actors[look] = a
	for m in Game.household:
		if actors.has(m.get("look", "")):
			actors[m.name] = actors[m.look]
	var cashier := SimActor.create("npc_3")
	cashier.name = "Cashier"
	add_child(cashier)
	actors["cashier"] = cashier
	actors["npc_3"] = cashier
	var shoppers := ["npc_2", "npc_5", "npc_4", "npc_0", "npc_6"]
	for i in shoppers.size():
		var s := SimActor.create(shoppers[i])
		s.name = "Shopper%d" % i
		add_child(s)
		actors["shopper_%d" % i] = s
		actors[shoppers[i]] = s
	# Cart (with Biscuit riding in it).
	_cart = Kit.add(self, Fx.cart(), P * 1.2, "Cart", true, null, Vector3.ZERO, Vector3(8.5, 0, -3))
	Interactable.attach(_cart, "Shopping Cart", [
		_act("push", "Push Cart", "cart", 2.0),
		_act("pet", "Pet Biscuit", "paw", 3.0, {"fun": 0.1}),
	], Vector3(0.6, 0.9, 0.9), Vector3(0, 0.45, 0.35))
	# Cashier chat
	Interactable.attach(cashier, "Cashier", [
		_act("chat", "Chat", "chat", 10.0, {"social": 0.15}, {"task": "Meet a Neighbor"}),
		_act("ask", "Ask About Deals", "tag", 5.0, {"social": 0.05}),
	], Vector3(0.6, 1.7, 0.5), Vector3(0, 0.85, 0))


func _place(key: String, pos: Vector3, face_to: Vector3, pose: String) -> SimActor:
	var a: SimActor = actors[key]
	a.position = pos
	a.face(face_to)
	a.set_pose(pose)
	return a


func _stage() -> void:
	if actors.is_empty():
		return
	var cam := Vector3(0.4, 0, 6.0)
	var jack := _place("dad", Vector3(-0.3, 0, 0.45), Vector3(1.1, 0, 5.0), "stand_type")
	var fwd := Vector3(sin(jack.rotation.y), 0, cos(jack.rotation.y))
	_cart.position = jack.position + fwd * 0.4
	_cart.rotation.y = jack.rotation.y
	var dog := _place("beagle", _cart.position + fwd * 0.45 + Vector3(0, 13 * P * 1.2, 0), cam + Vector3(-1.5, 0, 0), "sit")
	dog.rotation.y = jack.rotation.y + 0.35
	var lily := _place("bunny_girl", Vector3(-1.0, 0, 0.35), Vector3(-0.4, 0, 5.0), "stand_type")
	var maya := _place("cat_girl", Vector3(1.0, 0, 0.8), Vector3(0.0, 0, 6.0), "stand_type")
	_hold(lily, "carrots")
	_hold(maya, "cereal")
	_place("cashier", Vector3(2.95, 0, 0.75), Vector3(0.6, 0, 3.0), "idle")
	_place("npc_2", Vector3(-1.75, 0, -2.6), Vector3(-3.0, 0, -3.4), "idle")
	_place("npc_5", Vector3(0.9, 0, -6.4), Vector3(0.6, 0, -10.0), "idle")
	_place("npc_4", Vector3(-0.2, 0, -4.4), Vector3(-0.4, 0, -9.0), "idle")
	_place("npc_0", Vector3(1.95, 0, -3.6), Vector3(3.0, 0, -3.8), "stand_read")
	_place("npc_6", Vector3(-3.0, 0, -7.4), Vector3(-6.0, 0, -7.2), "idle")


## Give an actor a hand-held voxel item (attached to the right forearm).
func _hold(a: SimActor, what: String) -> void:
	if a.skeleton == null or a.has_node("Skeleton/Hold_" + what):
		return
	var att := BoneAttachment3D.new()
	att.name = "Hold_" + what
	att.bone_name = "fore_r"
	a.skeleton.add_child(att)
	var vb := VoxelBuilder.new()
	vb.jitter = 0.04
	var hand := -0.2
	if a._meta.has("fore_len"):
		hand = -float(a._meta.fore_len)
	var ax := 0.0
	if a._meta.has("arm_x"):
		ax = float(a._meta.arm_x)
	var mi := MeshInstance3D.new()
	match what:
		"carrots":
			for i in 3:
				Produce.carrot(vb, Vector3i(i * 2 - 2, (i % 2), i), 1)
			mi.mesh = Kit.mesh(vb, P * 0.95, Vector3(0.5, 1, 1))
			mi.position = Vector3(0.0, hand - 0.03, 0.02)
			mi.rotation = Vector3(PI, 0.0, 0.0)
		"cereal":
			# Box with a cartoon bear face, held in front with both hands.
			var red := Color("e8402f")
			vb.box(Vector3i(0, 0, 0), Vector3i(8, 11, 3), red)
			vb.box(Vector3i(1, 8, 3), Vector3i(6, 2, 1), Color("fde46a"))
			vb.box(Vector3i(2, 2, 3), Vector3i(4, 5, 1), Color("f3b25a"))
			vb.set_v(Vector3i(2, 7, 3), Color("c97a35"))
			vb.set_v(Vector3i(5, 7, 3), Color("c97a35"))
			vb.set_v(Vector3i(3, 5, 4), Color("2a1d14"))
			vb.set_v(Vector3i(4, 5, 4), Color("2a1d14"))
			vb.box(Vector3i(3, 3, 4), Vector3i(2, 1, 1), Color("fbe4c4"))
			mi.mesh = Kit.mesh(vb, 0.036, Vector3(4, 5.5, 0))
			mi.position = Vector3(ax, hand - 0.07, 0.12)
			mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	att.add_child(mi)


static func _act(id: String, label: String, icon: String, minutes: float, needs := {}, extra := {}) -> Dictionary:
	var d := {"id": id, "label": label, "icon": icon, "minutes": minutes, "needs": needs, "pose": "talk"}
	d.merge(extra, true)
	return d


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 12 and OS.get_environment("VIMS_STATS") != "":
		print("MARKET_STATS draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			" objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		var rows := []
		for mi in find_children("*", "MeshInstance3D", true, false):
			if not (mi.mesh is ArrayMesh):
				continue
			var tris := 0
			for si in mi.mesh.get_surface_count():
				var il: int = mi.mesh.surface_get_array_index_len(si)
				tris += (il if il > 0 else mi.mesh.surface_get_array_len(si)) / 3
			rows.append([tris, mi.name])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		var tot := 0
		for r in rows:
			tot += r[0]
		print("MARKET_TRIS total=", tot, " meshes=", rows.size(), " top=", rows.slice(0, 12))
	if _frames > 12:
		set_process(false)
