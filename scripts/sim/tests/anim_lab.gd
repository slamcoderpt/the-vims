extends Node
## Pose lab for ActionAnims: lines up voxel sims on the lawn, each playing one
## action anim with its props, and saves close-up screenshots.
## run: tools/playtest.sh anim_lab [--anims=eat,cook] [--at=x,z]

const ActionAnims := preload("res://scripts/world/actors/action_anims.gd")

var main: Node
var args := {}
var shot_dir := "res://shots"
const BATCHES := [
	["eat", "snack_eat", "drink", "chop", "stir", "toilet"],
	["shower", "bath", "wash_hands", "dishes", "guitar", "phone_call"],
	["chat", "listen", "joke", "laugh", "hug", "kiss"],
	["argue", "upset", "deep_talk", "pet_dog", "watch_tv", "react_stretch"],
	["react_yes", "react_satisfied", "react_shake", "pull_chair", "water_plant", "telescope"],
]
var FACE := 2.6
const LOOKS := ["dad", "bunny_girl", "cat_girl", "dad", "cat_girl", "bunny_girl"]


func _ready() -> void:
	shot_dir = args.get("shots", "res://shots")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	Game.speed = 0
	for a in main.sim.agents:
		if a and a.actor:
			a.actor.visible = false
	await _frames(3)
	var base := Vector3(2.0, 0.0, 9.0)
	if args.has("at"):
		var p: PackedStringArray = str(args.at).split(",")
		base = Vector3(float(p[0]), 0.0, float(p[1]))
	var batches: Array = BATCHES
	if args.has("face"):
		FACE = float(args.face)
	if args.has("anims"):
		batches = [str(args.anims).split(",")]
	var bi := 0
	for batch in batches:
		var nodes: Array = []
		var i := 0
		for an: String in batch:
			var pos := base + Vector3(i * 3.0 - 7.5, 0.0, 0.0)
			var a := SimActor.create(LOOKS[i % LOOKS.size()])
			main.location.add_child(a)
			a.global_position = pos
			a.rotation.y = FACE
			nodes.append(a)
			var ctx := {"base": "sit" if an in ["watch_tv"] else "idle"}
			if an in ["eat", "chop", "stir", "toilet", "dishes", "wash_hands"]:
				var t := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var h := 0.75 if an == "eat" else 0.9
				bm.size = Vector3(0.9, h, 0.6)
				t.mesh = bm
				main.location.add_child(t)
				var fwd := Basis(Vector3.UP, FACE) * Vector3(0, 0, 1)
				t.global_position = pos + fwd * 0.75 + Vector3(0, h * 0.5, 0)
				t.rotation.y = FACE
				nodes.append(t)
				ctx["surface"] = pos + fwd * 0.75 + Vector3(0, h, 0)
			if an in ["toilet", "eat", "watch_tv"]:
				a.seat_height = 0.45
				var st := MeshInstance3D.new()
				var sb := BoxMesh.new()
				sb.size = Vector3(0.4, 0.43, 0.4)
				st.mesh = sb
				main.location.add_child(st)
				st.global_position = pos + Vector3(0, 0.215, 0)
				nodes.append(st)
			if an == "bath":
				var tub := MeshInstance3D.new()
				var bm2 := BoxMesh.new()
				bm2.size = Vector3(0.7, 0.25, 1.6)
				tub.mesh = bm2
				main.location.add_child(tub)
				var fwd2 := Basis(Vector3.UP, FACE) * Vector3(0, 0, 1)
				var c := pos + fwd2 * 0.45 + Vector3(0, 0.125, 0)
				tub.global_position = c
				tub.rotation.y = FACE
				tub.transparency = 0.6
				nodes.append(tub)
				ctx["tub_center"] = c
				ctx["tub_half"] = Vector3(0.8, 0.3, 0.35)
				ctx["tub_yaw"] = FACE + PI * 0.5
			await _frames(1)
			ActionAnims.of(a).play(an, ctx)
			i += 1
		await _wait(0.6)
		var j := 0
		for an: String in batch:
			var pos := base + Vector3(j * 3.0 - 7.5, 0.0, 0.0)
			main.camera_rig.apply({"target": pos + Vector3(0, 1.0, 0), "distance": float(args.get("dist", 4.2)), "pitch": 36.0, "yaw": 20.0})
			await _wait(0.8)
			var act: Node = nodes.filter(func(n): return n is SimActor)[j]
			print("  %s: pose=%s anim=%s/%s props=%s fx=%s" % [an, act.pose, ActionAnims.of(act).current, ActionAnims.of(act).active, str(ActionAnims.of(act).visible_props()), str(ActionAnims.of(act).fx_active())])
			await _shot("lab_%s_a" % an)
			await _frames(int(args.get("bframes", 9)))
			await _shot("lab_%s_b" % an)
			j += 1
		for n in nodes:
			n.queue_free()
		await _frames(2)
		bi += 1
	print("RESULT PASS (lab)")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [shot_dir, tag]
	img.save_png(path)
	print("  shot ", path)
