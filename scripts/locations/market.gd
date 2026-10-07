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
	return {"target": Vector3(0.4, 1.1, -2.6), "yaw": 0.0, "pitch": 12.0, "distance": 13.5, "fov": 46.0}


func lighting_profile() -> Dictionary:
	# Indoors: a weak, high "skylight" sun for soft shadow direction; the
	# store is lit mostly by warm pendant omnis + bright neutral ambient.
	return {
		"sun_heading": 200.0, "sun_elev": 62.0, "sun_energy": 0.55,
		"ambient_day": Color(1.0, 0.95, 0.88), "ambient_energy": 0.62,
		"ambient_night": Color(0.8, 0.7, 0.6), "ambient_night_energy": 0.6,
		"lamp_night_mult": 1.2,
		"sky_day": Color(0.36, 0.27, 0.2), "sky_night": Color(0.2, 0.14, 0.1),
		"fog_day": Color(0.98, 0.94, 0.88), "fog_night": Color(0.4, 0.3, 0.22), "fog_density": 0.0022,
		"exposure": 1.05,
		"shadow_distance": 18.0,
		"post": {"focus_y": 0.56, "band": 0.24, "falloff": 0.3, "blur_px": 3.6, "top_boost": 0.2,
			"saturation": 1.16, "contrast": 1.1, "tint": Vector3(1.0, 1.0, 0.98), "vignette": 0.16},
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
	# Soft contact shadows under everyone standing on the tiles.
	for k: String in ["dad", "bunny_girl", "cat_girl", "cashier", "shopper_0", "shopper_1", "shopper_2", "shopper_3", "shopper_4"]:
		Kit.blob(actors[k], 0.95 if k != "bunny_girl" and k != "cat_girl" else 0.8)
	# Cart (with Biscuit riding in it).
	_cart = Kit.add(self, Fx.cart(), P * 1.45, "Cart", true, null, Vector3.ZERO, Vector3(8.5, 0, -3))
	Kit.blob(_cart, 1.05, 0.4, Vector3(0, 0, 0.5))
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
	var cam := Vector3(0.4, 0, 10.6)
	# The family stands in the mid-ground of the main aisle (about a quarter
	# of the frame tall) with clear tile between them, so the aisle, fridges
	# and signs stay readable behind (ref5): Lily at the produce island
	# (left), Jack pushing the cart with Biscuit riding in it (centre), Maya
	# with a cereal box (centre-right).
	var jack := _place("dad", Vector3(-0.3, 0, 0.0), cam + Vector3(7.5, 0, 0), "idle")
	var cart_yaw := jack.rotation.y
	var fwd := Vector3(sin(cart_yaw), 0, cos(cart_yaw))
	_cart.position = jack.position + fwd * 0.55
	_cart.rotation.y = cart_yaw
	var dog := _place("beagle", _cart.position + fwd * 0.55 + Vector3(0, 13 * P * 1.45, 0), cam + Vector3(-1.5, 0, 0), "sit")
	dog.body_scale = 1.0
	dog.rotation.y = lerp_angle(cart_yaw, dog.rotation.y, 0.6)
	# The "type" pose turns the head ~0.9 rad to the sim's left, so the
	# girls' bodies are turned the other way to keep their faces on camera.
	var lily := _place("bunny_girl", Vector3(-1.5, 0, 1.15), cam, "stand_type")
	lily.rotation.y -= 0.75
	var maya := _place("cat_girl", Vector3(1.9, 0, 0.8), cam, "stand_type")
	maya.rotation.y -= 0.8
	lily.body_scale = 1.0
	maya.body_scale = 1.0
	_hold(lily, "carrots")
	_hold(maya, "cereal")
	var cashier := _place("cashier", Vector3(3.95, 0, 2.7), Vector3(1.0, 0, 8.0), "idle")
	cashier.body_scale = 1.12
	# Background shoppers spread down the aisles, in the gaps between the family.
	_place("npc_2", Vector3(-3.0, 0, -3.4), Vector3(-5.0, 0, -4.2), "idle")
	_place("npc_5", Vector3(0.9, 0, -8.6), Vector3(0.6, 0, -11.0), "idle")
	_place("npc_4", Vector3(-0.7, 0, -5.4), Vector3(-0.4, 0, -11.0), "idle")
	_place("npc_0", Vector3(1.55, 0, -5.6), Vector3(2.4, 0, -6.0), "stand_read")
	_place("npc_6", Vector3(4.0, 0, -6.2), Vector3(4.6, 0, -6.6), "idle")
	_hold(actors["npc_4"], "basket")
	_hold(actors["npc_2"], "basket")
	_hold(actors["npc_6"], "basket")


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
		"basket":
			# Red shopping basket hanging from the hand, a few groceries inside.
			var red := Color("d8322c")
			for x in 9:
				for z in 6:
					for y in 5:
						var side := x == 0 or x == 8 or z == 0 or z == 5
						if y == 0 or (side and (y == 4 or (x + z + y) % 2 == 0)):
							vb.set_v(Vector3i(x, y, z), red if y != 4 else Color("ef4a3c"))
			vb.box(Vector3i(1, 1, 1), Vector3i(3, 5, 2), Color("fbfbf8"))
			vb.box(Vector3i(5, 1, 2), Vector3i(3, 4, 3), Color("f6c22c"))
			vb.set_v(Vector3i(2, 6, 2), Color("2e7de0"))
			vb.box(Vector3i(5, 5, 2), Vector3i(2, 1, 2), Color("4f9e34"))
			for y in 4:
				vb.set_v(Vector3i(4, 5 + y, 0), Color("2a2a2c"))
				vb.set_v(Vector3i(4, 5 + y, 5), Color("2a2a2c"))
			for z in 6:
				vb.set_v(Vector3i(4, 9, z), Color("2a2a2c"))
			mi.mesh = Kit.mesh(vb, P, Vector3(4.5, 9.5, 3))
			mi.position = Vector3(ax, hand - 0.02, 0.0)
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
			" objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			" main_vp_draws=", get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" main_vp_shadow_draws=", get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" main_vp_prims=", get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
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
		var by := {}
		for n in find_children("*", "GeometryInstance3D", true, false):
			var par: Node = n
			while par.get_parent() != self and par.get_parent() != null:
				par = par.get_parent()
			var key := n.get_class() + ":" + String(par.name)
			by[key] = by.get(key, 0) + 1
		print("MARKET_NODES ", by)
		print("MARKET_TRIS total=", tot, " meshes=", rows.size(), " top=", rows.slice(0, 12))
	if _frames > 12:
		set_process(false)
