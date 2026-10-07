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
const ShotPresets := preload("res://scripts/core/shot_presets.gd")

const U := 0.0625
const P := 0.03125
const CART_S := 1.25

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


## Same Sims-style camera language as home / backyard (pitch 32-38, fov
## 37-42); single source of truth is the "market" shot preset.
func camera_home() -> Dictionary:
	return ShotPresets.PRESETS["market"].camera.duplicate()


func lighting_profile() -> Dictionary:
	# Indoors, cosy and warm-neutral: a dim skylight key for soft shadow
	# direction and a low warm ambient so the store is NOT flat. The pendant
	# lamps (bright emissive bulbs + warm omni/spot lights) paint amber pools
	# on the cream tiles and crates; the fridge cases glow cool blue-white.
	return {
		"sun_heading": 200.0, "sun_elev": 64.0, "sun_energy": 0.32,
		"ambient_day": Color(1.0, 0.92, 0.82), "ambient_energy": 0.48,
		"ambient_night": Color(0.85, 0.74, 0.62), "ambient_night_energy": 0.4,
		"lamp_night_mult": 1.2,
		"sky_day": Color(0.8, 0.84, 0.9), "sky_night": Color(0.2, 0.18, 0.2),
		"fog_day": Color(0.95, 0.89, 0.8), "fog_night": Color(0.4, 0.32, 0.26), "fog_density": 0.006,
		"exposure": 0.92,
		"shadow_distance": 24.0,
		"post": {"focus_y": 0.53, "band": 0.3, "falloff": 0.28, "blur_px": 3.4, "top_boost": 0.2,
			"saturation": 1.3, "contrast": 1.1, "tint": Vector3(1.03, 0.97, 0.92),
			"lift": Vector3(0.006, 0.006, 0.008), "vignette": 0.18},
	}


## lighting.gd tints the sun warm in the morning (it is an outdoor sun); in
## here it stands in for neutral skylight, so re-colour it after each update.
func _fix_sun(_a = null, _b = null) -> void:
	var lt := get_parent().get_node_or_null("Lighting") if get_parent() else null
	if lt == null:
		return
	var sun = lt.get("sun")
	if sun is DirectionalLight3D:
		sun.light_color = Color(1.0, 0.98, 0.95)


func get_actor(key: String) -> SimActor:
	return actors.get(key, null)


func apply_preset(_preset: String) -> void:
	_stage()
	_fix_sun()


func _ready() -> void:
	if not Game.time_changed.is_connected(_fix_sun):
		Game.time_changed.connect(_fix_sun)
	_fix_sun.call_deferred()


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
	var shoppers := ["npc_2", "npc_5", "npc_4", "npc_0", "npc_6", "npc_1", "npc_7"]
	for i in shoppers.size():
		var s := SimActor.create(shoppers[i])
		s.name = "Shopper%d" % i
		add_child(s)
		actors["shopper_%d" % i] = s
		actors[shoppers[i]] = s
	# Real-world sizes (shared art direction): adult ~1.75 m, child ~70 % of
	# that, the beagle's back about a child's knee-to-hip. SimActor clamps
	# body_scale to a hero minimum, so shrink the node by what it kept.
	for k: String in actors:
		_life_size(actors[k])
	# Soft contact shadows under everyone standing on the tiles.
	for k: String in ["dad", "bunny_girl", "cat_girl", "cashier", "shopper_0", "shopper_1", "shopper_2", "shopper_3", "shopper_4", "shopper_5", "shopper_6"]:
		Kit.blob(actors[k], 0.95 if k != "bunny_girl" and k != "cat_girl" else 0.8)
	# Cart (with Biscuit riding in it).
	_cart = Kit.add(self, Fx.cart(), P * CART_S, "Cart", true, null, Vector3.ZERO, Vector3(8.5, 0, -3))
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


const LIFE_H := {"dad": 1.75, "bunny_girl": 1.24, "cat_girl": 1.24, "beagle": 0.52}


func _life_size(a: SimActor) -> void:
	if a.skeleton == null or a._meta.is_empty():
		return
	var want: float = LIFE_H.get(a.look, 1.72 if a.kind() != "child" else 1.24)
	var eff := float(a._meta.get("height", 1.75)) * a.skeleton.scale.y
	if eff > 0.01:
		a.scale = Vector3.ONE * (want / eff)
	if OS.get_environment("VIMS_STATS") != "":
		print("MARKET_ACTOR ", a.look, " height_m=", eff * a.scale.y)


func _place(key: String, pos: Vector3, face_to: Vector3, pose: String) -> SimActor:
	var a: SimActor = actors[key]
	a.position = pos
	a.face(face_to)
	a.set_pose(pose)
	return a


func _stage() -> void:
	if actors.is_empty():
		return
	var cam := Vector3(2.7, 0, 7.1)
	# Telephoto view down the main aisle: the family is spread across the
	# mid-ground (Lily at the produce island, Jack pushing the cart with
	# Biscuit riding in it, Maya by the checkout) with open tile between them,
	# so the tall glowing fridge wall and the shelving runs read behind.
	# "stand_type" holds both forearms forward at chest height: hands on the
	# cart handle.
	var jack := _place("dad", Vector3(-0.25, 0, 0.6), cam + Vector3(3.0, 0, 0), "stand_type")
	var cart_yaw := jack.rotation.y
	var fwd := Vector3(sin(cart_yaw), 0, cos(cart_yaw))
	_cart.position = jack.position + fwd * 0.4
	_cart.rotation.y = cart_yaw
	# Biscuit rides in the cart, sitting up on the groceries, head above the rim.
	var dog := _place("beagle", _cart.position + fwd * 0.6 + Vector3(0, 0.8, 0), cam + Vector3(-0.6, 0, 0), "sit")
	# The "type" pose turns the head ~0.9 rad to the sim's left, so the
	# girls' bodies are turned the other way to keep their faces on camera.
	var lily := _place("bunny_girl", Vector3(-1.6, 0, 1.25), cam, "stand_type")
	lily.rotation.y -= 0.75
	var maya := _place("cat_girl", Vector3(1.4, 0, 1.4), cam, "stand_type")
	maya.rotation.y -= 0.5
	_hold(lily, "carrots")
	_hold(maya, "cereal")
	var cashier := _place("cashier", Vector3(4.4, 0, 0.9), Vector3(1.0, 0, 9.0), "idle")
	# Background shoppers browse down the aisles, in the screen gaps between
	# the family (never directly behind a head).
	_place("npc_2", Vector3(0.12, 0, -1.75), Vector3(-1.6, 0, 1.2), "idle")
	_place("npc_1", Vector3(-0.2, 0, -4.4), Vector3(-1.2, 0, -4.2), "idle")
	_place("npc_7", Vector3(1.5, 0, -5.0), Vector3(2.4, 0, -5.0), "stand_read")
	_hold(actors["npc_1"], "basket")
	_place("npc_5", Vector3(-2.6, 0, -7.2), Vector3(-2.4, 0, -8.6), "idle")
	_place("npc_4", Vector3(1.1, 0, -7.3), Vector3(0.6, 0, -8.6), "idle")
	_place("npc_0", Vector3(-1.6, 0, -6.9), Vector3(-3.2, 0, -5.6), "stand_read")
	_place("npc_6", Vector3(4.0, 0, -5.2), Vector3(4.9, 0, -5.4), "idle")
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
			# A bunch of four chunky carrots, leafy tops together at the hand.
			for i in 4:
				Produce.big_carrot(vb, Vector3i(i * 2 - 4, (i % 2), -(i % 2)), i, 11 + (i % 2))
			mi.mesh = Kit.mesh(vb, P * 1.1, Vector3(0, 1, 3))
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
